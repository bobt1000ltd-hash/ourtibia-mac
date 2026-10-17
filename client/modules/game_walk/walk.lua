local smartWalkDirs = {}
local smartWalkDir = nil
local walkEvent = nil
local lastTurn = 0
local nextWalkDir = nil
local lastWalkDir = nil
local lastCancelWalkTime = 0


local keys = {
    { "Up",      North },
    { "Right",   East },
    { "Down",    South },
    { "Left",    West },
    { "Numpad8", North },
    { "Numpad9", NorthEast },
    { "Numpad6", East },
    { "Numpad3", SouthEast },
    { "Numpad2", South },
    { "Numpad1", SouthWest },
    { "Numpad4", West },
    { "Numpad7", NorthWest },
}

local turnKeys = {
    { "Control+Up",    North },
    { "Control+Right", East },
    { "Control+Down",  South },
    { "Control+Left",  West },
}

WalkController = Controller:new()

-- OurTibia (17.10.2026): map click written anew. The old one asked the client for the same
-- path again and again, so when the server refused a step ("There is not enough room",
-- "Sorry, not possible") the character stood at the wall for 20 s. Now we search the way
-- ourselves (the client's rules: straight step 1, diagonal 3, no fields, no creatures) and
-- remember every tile the server refused - the next search goes around it. Destinations
-- outside the loaded map (minimap clicks) still use the client's own long-distance walk.
local mapClick = { dest = nil, time = 0, sends = 0, event = nil }
local refused = {} -- "x:y:z" -> g_clock.millis() until the tile is avoided
local function pkey(x, y, z) return x .. ':' .. y .. ':' .. z end
local STEPS = {
    {0, -1, Directions.North, 1}, {1, 0, Directions.East, 1}, {0, 1, Directions.South, 1}, {-1, 0, Directions.West, 1},
    {1, -1, Directions.NorthEast, 3}, {1, 1, Directions.SouthEast, 3}, {-1, 1, Directions.SouthWest, 3}, {-1, -1, Directions.NorthWest, 3},
}
local OFFSET = {}
for _, s in ipairs(STEPS) do OFFSET[s[3]] = {s[1], s[2]} end

local function clearMapClick()
    mapClick.dest = nil
    mapClick.target = nil
    mapClick.way = nil
    mapClick.sends = 0
    if mapClick.event then removeEvent(mapClick.event); mapClick.event = nil end
end
local originalAutoWalk = LocalPlayer.autoWalk

local function hasOtherCreature(t)
    local me = g_game.getLocalPlayer()
    for _, c in ipairs(t:getCreatures() or {}) do
        if not (me and c:getId() == me:getId()) then return true end
    end
    return false
end
local function blockedByCreature(dest)
    local t = g_map.getTile(dest)
    return t ~= nil and hasOtherCreature(t)
end

-- binary heap on f
local function hpush(h, n)
    h[#h + 1] = n
    local i = #h
    while i > 1 do
        local p = math.floor(i / 2)
        if h[p].f <= h[i].f then break end
        h[p], h[i] = h[i], h[p]; i = p
    end
end
local function hpop(h)
    local top = h[1]; local last = h[#h]; h[#h] = nil
    if #h > 0 then
        h[1] = last
        local i = 1
        while true do
            local l, r, m = i * 2, i * 2 + 1, i
            if h[l] and h[l].f < h[m].f then m = l end
            if h[r] and h[r].f < h[m].f then m = r end
            if m == i then break end
            h[m], h[i] = h[i], h[m]; i = m
        end
    end
    return top
end

local function findWay(from, to, allowFields, allowCreatures)
    if from.z ~= to.z or (from.x == to.x and from.y == to.y) then return nil end
    local now, z = g_clock.millis(), from.z
    local goal = g_map.getTile(to)
    if not goal or not goal:isWalkable(true) then return nil end
    local best = {[pkey(from.x, from.y, z)] = 0}
    local heap = {{x = from.x, y = from.y, g = 0, f = 0}}
    local done, count = {}, 0
    while #heap > 0 do
        local cur = hpop(heap)
        local ck = pkey(cur.x, cur.y, z)
        if not done[ck] then
            done[ck] = true
            if cur.x == to.x and cur.y == to.y then
                local dirs, n = {}, cur
                while n.prev do table.insert(dirs, 1, n.dir); n = n.prev end
                return dirs
            end
            count = count + 1
            if count > 5000 then return nil end
            for _, s in ipairs(STEPS) do
                local nx, ny = cur.x + s[1], cur.y + s[2]
                local nk = pkey(nx, ny, z)
                if not done[nk] and not ((refused[nk] or 0) > now) then
                    local t = g_map.getTile({x = nx, y = ny, z = z})
                    local isGoal = nx == to.x and ny == to.y
                    local ok = t ~= nil and t:isWalkable(true)
                    if ok and not isGoal then
                        if not allowCreatures and hasOtherCreature(t) then ok = false end
                        if ok and not allowFields and not t:isPathable() then ok = false end
                    end
                    if ok then
                        local g = cur.g + s[4]
                        if not best[nk] or g < best[nk] then
                            best[nk] = g
                            local h = math.max(math.abs(to.x - nx), math.abs(to.y - ny))
                            hpush(heap, {x = nx, y = ny, g = g, f = g + h, prev = cur, dir = s[3]})
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- a click on an NPC / monster walks to the free tile next to it that is closest to us
local function besideCreature(pos, dest)
    local bestPos, bestD
    for dx = -1, 1 do for dy = -1, 1 do
        if dx ~= 0 or dy ~= 0 then
            local q = {x = dest.x + dx, y = dest.y + dy, z = dest.z}
            local t = g_map.getTile(q)
            if t and t:isWalkable(true) and not hasOtherCreature(t) then
                local d = math.max(math.abs(q.x - pos.x), math.abs(q.y - pos.y)) * 10 + math.abs(q.x - pos.x) + math.abs(q.y - pos.y)
                if not bestD or d < bestD then bestPos, bestD = q, d end
            end
        end
    end end
    return bestPos
end
-- returns false when the map click is finished
local function adjustMapClick(pos)
    local dest = mapClick.dest
    if not dest or not pos then return false end
    if mapClick.target then
        if math.max(math.abs(pos.x - mapClick.target.x), math.abs(pos.y - mapClick.target.y)) <= 1 then return false end
        if not blockedByCreature(mapClick.target) then dest.x, dest.y = mapClick.target.x, mapClick.target.y; mapClick.target = nil; return true end
    elseif blockedByCreature(dest) then
        if math.max(math.abs(pos.x - dest.x), math.abs(pos.y - dest.y)) <= 1 then return false end
        mapClick.target = {x = dest.x, y = dest.y, z = dest.z}
    end
    if mapClick.target then
        local side = besideCreature(pos, mapClick.target)
        if not side then return false end
        dest.x, dest.y = side.x, side.y
    end
    return true
end

local function noWay()
    clearMapClick()
    pcall(function() modules.game_textmessage.displayFailureMessage(tr('There is no way.')) end)
end

-- searches the way from where we stand and sends it to the server
local function sendWay(player)
    local dest = mapClick.dest
    local pos = player:getPosition()
    if not dest or not pos then return false end
    if pos.z ~= dest.z then clearMapClick(); return true end
    if not adjustMapClick(pos) then clearMapClick(); return true end
    if pos.x == dest.x and pos.y == dest.y then clearMapClick(); return true end
    local dirs = findWay(pos, dest, false, false) or findWay(pos, dest, true, false) or findWay(pos, dest, true, true)
    if not dirs or #dirs == 0 then return false end
    if #dirs > 127 then local t = {} for i = 1, 127 do t[i] = dirs[i] end dirs = t end
    local way, x, y = {}, pos.x, pos.y
    for i, d in ipairs(dirs) do
        local o = OFFSET[d]; x, y = x + o[1], y + o[2]
        way[i] = {x = x, y = y}
    end
    mapClick.way = way
    mapClick.from = {x = pos.x, y = pos.y, z = pos.z}
    mapClick.sends = mapClick.sends + 1
    mapClick.lastKey = nil
    if player:isAutoWalking() then player:stopAutoWalk() end
    g_game.autoWalk(dirs, pos)
    return true
end

-- the tile the server refused: the next one on our way after the tile we stand on
local function refuseNextTile(ms)
    local player = g_game.getLocalPlayer()
    local way, dest = mapClick.way, mapClick.dest
    if not player or not way or not dest then return end
    local pos = player:getPosition(); if not pos then return end
    local nextTile
    if mapClick.from and pos.x == mapClick.from.x and pos.y == mapClick.from.y then nextTile = way[1]
    else
        for i, t in ipairs(way) do if t.x == pos.x and t.y == pos.y then nextTile = way[i + 1]; break end end
    end
    if not nextTile then return end
    if nextTile.x == dest.x and nextTile.y == dest.y and ms > 5000 then
        -- the clicked tile itself cannot be entered
        mapClick.unreachable = true
    end
    refused[pkey(nextTile.x, nextTile.y, pos.z)] = g_clock.millis() + ms
end

local function continueMapClick(delay)
    if not mapClick.dest or mapClick.event then return end
    mapClick.event = scheduleEvent(function()
        mapClick.event = nil
        local player = g_game.getLocalPlayer()
        if not player or not mapClick.dest or not g_game.isOnline() or g_game.isDead() then clearMapClick(); return end
        if mapClick.playerId and player:getId() ~= mapClick.playerId then clearMapClick(); return end
        if mapClick.unreachable then mapClick.unreachable = nil; noWay(); return end
        if g_clock.millis() - mapClick.time > 20000 or mapClick.sends >= 30 then clearMapClick(); return end
        if not sendWay(player) then noWay() end
    end, delay or 80)
end
local function retryMapClick() continueMapClick(80) end

local function rememberAutoWalk(player, dest, ...)
    clearMapClick()
    if not player or not dest then return false end
    local pos = player:getPosition()
    -- far away (minimap) or another floor: the client's own walk
    if not pos or pos.z ~= dest.z or not g_map.getTile(dest) then return originalAutoWalk(player, dest, ...) end
    mapClick.dest = {x = dest.x, y = dest.y, z = dest.z}
    mapClick.time = g_clock.millis()
    mapClick.playerId = player:getId()
    if not sendWay(player) then noWay(); return false end
    return true
end
LocalPlayer.autoWalk = rememberAutoWalk

-- the server refused a step of the map click: avoid that tile and walk on at once
local function onMapClickBlocked(mode, text)
    if not mapClick.dest or type(text) ~= 'string' then return end
    if text:find('There is not enough room', 1, true) then refuseNextTile(120000)
    elseif text:find('Sorry, not possible', 1, true) then refuseNextTile(2000)
    else return end
    continueMapClick(60)
end

-- watchdog: the character stands still before reaching the clicked tile -> new way
local mapClickWatch = nil
local function watchMapClick()
    local dest = mapClick.dest
    local player = g_game.getLocalPlayer()
    if dest and player and g_game.isOnline() and not mapClick.event then
        local pos = player:getPosition()
        if not pos or pos.z ~= dest.z or (pos.x == dest.x and pos.y == dest.y) then clearMapClick()
        else
            local key = pkey(pos.x, pos.y, pos.z)
            if mapClick.lastKey ~= key then mapClick.lastKey = key; mapClick.lastMove = g_clock.millis() end
            if not player:isWalking() and not player:isServerWalking() and g_clock.millis() - (mapClick.lastMove or 0) > 600 then
                mapClick.lastMove = g_clock.millis()
                continueMapClick(1)
            end
        end
    elseif dest and (not player or not g_game.isOnline()) then clearMapClick() end
    mapClickWatch = scheduleEvent(watchMapClick, 200)
end
mapClickWatch = scheduleEvent(watchMapClick, 1000)

-- game_textmessage asks before "There is no way." (only the client's own long walk gets there)
function ourAutoWalkFail() return false end
OurClearMapClick = clearMapClick -- Escape (game_interface) forgets the clicked destination

--- Stops the smart walking process.
local function stopSmartWalk()
    smartWalkDirs = {}
    smartWalkDir = nil
end

--- Cancels the current walk event if active.
local function cancelWalkEvent()
    if walkEvent then
        removeEvent(walkEvent)
        walkEvent = nil
    end
    nextWalkDir = nil
end

--- Generalized floor change check.
local function canChangeFloor(pos, deltaZ)
    if deltaZ == 0 then
        return false
    end
    local player = g_game.getLocalPlayer()
    if not player then
        return false
    end

    local toPos = {x = pos.x, y = pos.y, z = pos.z + deltaZ}
    local toTile = g_map.getTile(toPos)
    if not toTile then
        return false
    end

    if deltaZ > 0 then
        -- Going DOWN
        return toTile:isWalkable() and (toTile:hasElevation(3) or toTile:hasFloorChange())
    end
    -- deltaZ < 0
    -- Going UP: check if current tile has elevation (stairs to climb) AND destination is walkable
    local fromTile = g_map.getTile(player:getPosition())
    return fromTile and fromTile:hasElevation(3) and toTile:isWalkable()
end

--- Makes the player walk in the given direction.
local function walk(dir)
    local player = g_game.getLocalPlayer()
    if not player or g_game.isDead() or player:isDead() then
        return
    end

    if player:isWalkLocked() then
        nextWalkDir = nil
        return
    end

    if g_game.isFollowing() then
        g_game.cancelFollow()
    end

    clearMapClick()
    local isAutoWalking = player:isAutoWalking()
    if isAutoWalking or player:isServerWalking() then
        g_game.stop()
        if isAutoWalking then
            player:stopAutoWalk()
        end
        player:lockWalk(player:getStepDuration() + 50)
        return
    end

    if not player:canWalk() then
        if lastWalkDir ~= dir then
            nextWalkDir = dir
        end
        return
    end

    nextWalkDir = nil
    lastWalkDir = dir

    if g_game.getFeature(GameAllowPreWalk) then
        local toPos = Position.translatedToDirection(player:getPosition(), dir)
        local toTile = g_map.getTile(toPos)
        if not toTile or not toTile:isWalkable() then
            if not canChangeFloor(toPos, 1) and not canChangeFloor(toPos, -1) then
                return false
            end
        else
            player:preWalk(dir)
        end
    end

    modules.game_interface.lastManualWalk = g_clock.millis()
    g_game.walk(dir)
    return true
end

--- Adds a walk event with an optional delay.
local function addWalkEvent(dir, delay)
    if g_clock.millis() - lastCancelWalkTime > 20 then
        cancelWalkEvent()
        lastCancelWalkTime = g_clock.millis()
    end

    local action = function()
        if g_keyboard.getModifiers() == KeyboardNoModifier then
            walk(smartWalkDir or dir)
        end
    end

    walkEvent = delay ~= nil and delay > 0 and scheduleEvent(action, delay) or addEvent(action)
end

--- Initiates a smart walk in the given direction.
function smartWalk(dir)
    addWalkEvent(dir)
end

--- Changes the current walking direction.
local function changeWalkDir(dir, pop)
    -- Remove all occurrences of the specified direction
    while table.removevalue(smartWalkDirs, dir) do end

    if pop then
        if #smartWalkDirs == 0 then
            stopSmartWalk()
            return
        end
    else
        table.insert(smartWalkDirs, 1, dir)
    end

    smartWalkDir = smartWalkDirs[1]

    if modules.client_options.getOption('smartWalk') and #smartWalkDirs > 1 then
        local diagonalMap = {
            [North] = { [West] = NorthWest, [East] = NorthEast },
            [South] = { [West] = SouthWest, [East] = SouthEast },
            [West]  = { [North] = NorthWest, [South] = SouthWest },
            [East]  = { [North] = NorthEast, [South] = SouthEast }
        }

        for _, d in ipairs(smartWalkDirs) do
            if diagonalMap[smartWalkDir] and diagonalMap[smartWalkDir][d] then
                smartWalkDir = diagonalMap[smartWalkDir][d]
                break
            end
        end
    end
end

--- Handles turning the player.
local function turn(dir, repeated)
    local player = g_game.getLocalPlayer()
    if player:isWalking() and player:getDirection() == dir then
        return
    end

    cancelWalkEvent()

    -- OurTibia (02.10.2026): faster, smoother turning.
    local TURN_DELAY_REPEATED = 90
    local TURN_DELAY_DEFAULT = 0

    local delay = repeated and TURN_DELAY_REPEATED or TURN_DELAY_DEFAULT

    if lastTurn + delay < g_clock.millis() then
        g_game.turn(dir)
        -- OurTibia (02.10.2026): show the turn at once instead of waiting for
        -- the server's answer (one ping later); the server confirms it anyway.
        if not player:isWalking() and player:getDirection() ~= dir then
            pcall(function() player:setDirection(dir) end)
        end
        changeWalkDir(dir)
        lastTurn = g_clock.millis()
        local turnLock = g_settings.getNumber("walkTurnDelay")
        if turnLock > 0 then player:lockWalk(turnLock) end
    end
end

-- OurTibia (01.10.2026): arrows/numpad always walk, like in Tibia. They are
-- also bound on the chat input (otherwise it eats them as cursor keys) and on
-- the root widget as a fallback when the focus is left outside the game panel
-- (e.g. after closing a window), so no extra click on the map is needed.
local extraWidgets = {}
local function bindExtra(widget)
    if not widget or extraWidgets[widget] then return end
    extraWidgets[widget] = true
    for _, keyDir in ipairs(keys) do bindWalkKey(keyDir[1], keyDir[2], widget) end
    for _, keyDir in ipairs(turnKeys) do bindTurnKey(keyDir[1], keyDir[2], widget) end
end
local function unbindExtra()
    for widget in pairs(extraWidgets) do
        for _, keyDir in ipairs(keys) do pcall(unbindWalkKey, keyDir[1], widget) end
        for _, keyDir in ipairs(turnKeys) do pcall(unbindTurnKey, keyDir[1], widget) end
    end
    extraWidgets = {}
end
function bindAlwaysWalk()
    local console = modules.game_console
    local edit = console and console.consoleTextEdit
    if not edit and console and console.getConsole then
        local panel = console.getConsole(); edit = panel and panel:recursiveGetChildById('consoleTextEdit')
    end
    bindExtra(edit)
    bindExtra(g_ui.getRootWidget())
end

--- Binds movement keys to their respective directions.
local function bindKeys()
    modules.game_interface.getRootPanel():setAutoRepeatDelay(200)

    for _, keyDir in ipairs(keys) do bindWalkKey(keyDir[1], keyDir[2]) end
    for _, keyDir in ipairs(turnKeys) do bindTurnKey(keyDir[1], keyDir[2]) end
end

local function unbindKeys()
    for _, keyDir in ipairs(keys) do unbindWalkKey(keyDir[1]) end
    for _, keyDir in ipairs(turnKeys) do unbindTurnKey(keyDir[1]) end
    unbindExtra()
end

--- Handles player teleportation events.
local function onTeleport(player, newPos, oldPos)
    if not newPos or not oldPos then
        return
    end

    local offsetX, offsetY, offsetZ =
        Position.offsetX(newPos, oldPos), Position.offsetY(newPos, oldPos), Position.offsetZ(newPos, oldPos)

    local TELEPORT_DELAY = g_settings.getNumber("walkTeleportDelay")
    local STAIRS_DELAY = g_settings.getNumber("walkStairsDelay")

    local delay = (offsetX >= 3 or offsetY >= 3 or offsetZ >= 2) and TELEPORT_DELAY or STAIRS_DELAY
    player:lockWalk(delay)
end

-- OurTibia (02.10.2026): is any key for this direction still held down?
local function dirKeyHeld(dir)
    if not dir then return false end
    for _, keyDir in ipairs(keys) do
        if keyDir[2] == dir and g_keyboard.isKeyPressed(keyDir[1]) then
            return true
        end
    end
    return false
end
local function heldWalkDir()
    if smartWalkDir and dirKeyHeld(smartWalkDir) then return smartWalkDir end
    for _, d in ipairs(smartWalkDirs) do
        if dirKeyHeld(d) then return d end
    end
    return nil
end

--- Handles the end of a walking event.
local function onWalkFinish(player)
    if nextWalkDir then
        if not g_game.getFeature(GameAllowPreWalk) then
            walk(nextWalkDir)
        else
            -- OurTibia (02.10.2026): change direction right after the step (was +50 ms)
            addWalkEvent(nextWalkDir)
        end
        return
    end
    -- OurTibia (02.10.2026): keep walking while a direction key is held, also
    -- after switching keys mid-run (pressing Down before releasing Right used
    -- to stop the character after one step until the key was pressed again).
    if g_keyboard.getModifiers() == KeyboardNoModifier and not player:isAutoWalking() then
        local dir = heldWalkDir()
        if dir then addWalkEvent(dir) end
    end
end

local function onAutoWalk(player)
end


--- Handles cancellation of a walking event.
local function onCancelWalk(player)
    player:lockWalk(50)
    retryMapClick()
end

--- Initializes the WalkController.
function WalkController:onInit()
    bindKeys()
end

function WalkController:onTerminate()
    unbindKeys()
end

--- Sets up game-related events for the WalkController.
function WalkController:onGameStart()
    -- 09.10.2026: a map click from the previous character (Ctrl+G) must not walk this one
    clearMapClick()
    mapClick.playerId = nil
    -- OurTibia (02.10.2026): once for everybody, no walk delay after a turn.
    if not g_settings.getBoolean('ourtibia_turn_smooth_v1') then
        g_settings.set('walkTurnDelay', 0)
        pcall(function() modules.client_options.setOption('walkTurnDelay', 0) end)
        g_settings.set('ourtibia_turn_smooth_v1', true)
    end
    self:registerEvents(g_game, {
        onGameStart = onGameStart,
        onTeleport = onTeleport,
        onAutoWalk = onAutoWalk,
        onTextMessage = onMapClickBlocked
    })

    self:registerEvents(LocalPlayer, {
        onCancelWalk = onCancelWalk,
        onWalkFinish = onWalkFinish,
        onAutoWalk = onAutoWalk,
    })

    modules.game_interface.getRootPanel().onFocusChange = stopSmartWalk
    scheduleEvent(bindAlwaysWalk, 500)
    modules.game_joystick.addOnJoystickMoveListener(function(dir) g_game.walk(dir) end)

    if not g_game.isOfficialTibia() then
        g_game.enableFeature(GameForceFirstAutoWalkStep)
    else
        g_game.disableFeature(GameForceFirstAutoWalkStep)
    end
end

--- Cleans up resources when the game ends.
function WalkController:onGameEnd()
    stopSmartWalk()
    -- 09.10.2026: forget the map click destination and stop the client autowalk on logout
    clearMapClick()
    mapClick.playerId = nil
    local player = g_game.getLocalPlayer()
    if player then pcall(function() player:stopAutoWalk() end) end
end

--- Utility functions for binding and unbinding keys.
function bindWalkKey(key, dir, widget)
    local gameRootPanel = widget or modules.game_interface.getRootPanel()

    g_keyboard.bindKeyDown(key, function()
        g_keyboard.setKeyDelay(key, 1)
        changeWalkDir(dir)
    end, gameRootPanel, true)

    g_keyboard.bindKeyUp(key, function()
        g_keyboard.setKeyDelay(key, 30)
        changeWalkDir(dir, true)
    end, gameRootPanel, true)

    g_keyboard.bindKeyPress(key, function() smartWalk(dir) end, gameRootPanel)
end

function bindTurnKey(key, dir, widget)
    local gameRootPanel = widget or modules.game_interface.getRootPanel()

    g_keyboard.bindKeyDown(key, function() turn(dir, false) end, gameRootPanel)
    g_keyboard.bindKeyPress(key, function() turn(dir, true) end, gameRootPanel)
    g_keyboard.bindKeyUp(key, function()
        local player = g_game.getLocalPlayer()
        -- OurTibia (02.10.2026): no extra walk lock after releasing a turn key.
        if player then return end
    end, gameRootPanel)
end

function unbindWalkKey(key, widget)
    local gameRootPanel = widget or modules.game_interface.getRootPanel()
    g_keyboard.unbindKeyDown(key, gameRootPanel)
    g_keyboard.unbindKeyUp(key, gameRootPanel)
    g_keyboard.unbindKeyPress(key, gameRootPanel)
end

function unbindTurnKey(key, widget)
    local gameRootPanel = widget or modules.game_interface.getRootPanel()
    g_keyboard.unbindKeyDown(key, gameRootPanel)
    g_keyboard.unbindKeyPress(key, gameRootPanel)
    g_keyboard.unbindKeyUp(key, gameRootPanel)
end
