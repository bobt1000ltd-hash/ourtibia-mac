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

-- OurTibia (02.10.2026): map click keeps going. The client gives up after 3
-- quick retries when a monster steps into the path (or the server cancels a
-- step, e.g. while casting). We remember the clicked destination and walk
-- there again with a fresh path for up to 12 s / 25 retries; any manual
-- walk, Escape or a new click replaces it.
local mapClick = { dest = nil, time = 0, retries = 0, event = nil }
local function clearMapClick()
    mapClick.dest = nil
    mapClick.target = nil
    mapClick.retries = 0
    mapClick.noWay = 0
    if mapClick.event then removeEvent(mapClick.event); mapClick.event = nil end
end
local adjustMapClick -- defined below
local originalAutoWalk = LocalPlayer.autoWalk
local function rememberAutoWalk(player, dest, ...)
    if not mapClick.retrying then
        clearMapClick()
        if dest then
            mapClick.dest = { x = dest.x, y = dest.y, z = dest.z }; mapClick.time = g_clock.millis()
            -- 09.10.2026: the destination belongs to this character only (Ctrl+G relog)
            mapClick.playerId = player and player.getId and player:getId() or nil
            -- 16.10.2026: a click on a creature walks next to it (or does nothing when we already are)
            local pos = player and player:getPosition()
            if pos and pos.z == dest.z then
                local ok, go = pcall(adjustMapClick, pos)
                if ok and not go then clearMapClick(); return false end
                if ok and mapClick.dest then dest = {x = mapClick.dest.x, y = mapClick.dest.y, z = mapClick.dest.z} end
            end
        end
    end
    return originalAutoWalk(player, dest, ...)
end
LocalPlayer.autoWalk = rememberAutoWalk

-- OurTibia (16.10.2026): a click on an NPC / monster (or a tile somebody stands on)
-- walked "into" the creature for 20 s - the character stood next to it and the
-- client kept asking for a path. Now: next to it = arrived; otherwise walk to the
-- free tile next to it that is closest to us.
local function blockedByCreature(dest)
    local t = g_map.getTile(dest)
    if not t then return false end
    local local_ = g_game.getLocalPlayer()
    for _, c in ipairs(t:getCreatures() or {}) do
        if c ~= local_ and not (local_ and c:getId() == local_:getId()) then return true end
    end
    return false
end
local function besideCreature(pos, dest)
    local best, bestD
    for dx = -1, 1 do for dy = -1, 1 do
        if dx ~= 0 or dy ~= 0 then
            local q = {x = dest.x + dx, y = dest.y + dy, z = dest.z}
            local t = g_map.getTile(q)
            if t and t:isWalkable() and not blockedByCreature(q) then
                local d = math.max(math.abs(q.x - pos.x), math.abs(q.y - pos.y)) * 10 + math.abs(q.x - pos.x) + math.abs(q.y - pos.y)
                if not bestD or d < bestD then best, bestD = q, d end
            end
        end
    end end
    return best
end
-- returns false when the map click is finished
adjustMapClick = function(pos)
    local dest = mapClick.dest
    if not dest or not pos then return false end
    if mapClick.target then
        -- walking to the side of a creature: arrived, or the creature left its tile
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
local function retryMapClick()
    local dest = mapClick.dest
    if not dest or mapClick.event then return end
    local player = g_game.getLocalPlayer()
    if not player or g_game.isDead() then clearMapClick(); return end
    if mapClick.playerId and player:getId() ~= mapClick.playerId then clearMapClick(); return end
    local pos = player:getPosition()
    if not pos or pos.z ~= dest.z or (pos.x == dest.x and pos.y == dest.y) then clearMapClick(); return end
    if not adjustMapClick(pos) then clearMapClick(); return end
    if g_clock.millis() - mapClick.time > 20000 or mapClick.retries >= 60 then clearMapClick(); return end
    mapClick.retries = mapClick.retries + 1
    mapClick.event = scheduleEvent(function()
        mapClick.event = nil
        local p = g_game.getLocalPlayer()
        if not p or not mapClick.dest then return end
        mapClick.retrying = true
        pcall(function() originalAutoWalk(p, mapClick.dest) end)
        mapClick.retrying = false
    end, 150 + math.min(mapClick.retries, 6) * 50)
end

-- OurTibia (03.10.2026): watchdog - a map click is never silently dropped.
-- If the character stands still (a monster blocked the path, an NPC stepped
-- in, an attack interrupted the walk) while a clicked destination is still
-- pending, walk there again with a new path (for up to 20 s).
local mapClickWatch = nil
local function watchMapClick()
    local dest = mapClick.dest
    local player = g_game.getLocalPlayer()
    if dest and (not player or not g_game.isOnline() or (mapClick.playerId and player:getId() ~= mapClick.playerId)) then
        -- 09.10.2026: logged out / another character - forget the old map click
        clearMapClick()
    elseif dest and player and g_game.isOnline() and not g_game.isDead() and not mapClick.event then
        local pos = player:getPosition()
        if not pos or pos.z ~= dest.z or (pos.x == dest.x and pos.y == dest.y) or g_clock.millis() - mapClick.time > 20000 or not adjustMapClick(pos) then
            clearMapClick()
            if pos and player:isAutoWalking() and not player:isWalking() then pcall(function() player:stopAutoWalk() end) end
        else
            -- 05.10.2026: also when the client still says "auto walking" but the
            -- character has not moved for 0.7 s (a blocked step can leave that
            -- state behind) - walk on with a fresh path.
            local key = pos.x .. ':' .. pos.y .. ':' .. pos.z
            if mapClick.lastKey ~= key then mapClick.lastKey = key; mapClick.lastMove = g_clock.millis() end
            local idle = not player:isAutoWalking() and not player:isServerWalking() and not player:isWalking()
            local stuck = not player:isWalking() and g_clock.millis() - (mapClick.lastMove or 0) > 700
            if idle or stuck then
                mapClick.lastMove = g_clock.millis()
                mapClick.retrying = true
                pcall(function()
                    if stuck and not idle then player:stopAutoWalk() end
                    originalAutoWalk(player, dest)
                end)
                mapClick.retrying = false
            end
        end
    end
    mapClickWatch = scheduleEvent(watchMapClick, 250)
end
mapClickWatch = scheduleEvent(watchMapClick, 1000)
-- OurTibia (05.10.2026): standing inside a fire bomb (or any ring of fields)
-- the normal path search refuses to step on fields, so a map click said
-- "There is no way". When no normal path exists we search again allowing
-- fields (non-pathable tiles) and send that path to the server.
function ourFieldWalk()
    local dest = mapClick.dest
    local player = g_game.getLocalPlayer()
    if not dest or not player then return false end
    local pos = player:getPosition()
    if not pos or pos.z ~= dest.z then return false end
    local ok, dirs, res = pcall(g_map.findPath, pos, dest, 20000, PathFindFlags.AllowNonPathable)
    if not ok or res ~= PathFindResults.Ok or not dirs or #dirs == 0 then return false end
    if #dirs > 127 then local t = {} for i = 1, 127 do t[i] = dirs[i] end dirs = t end
    g_game.autoWalk(dirs, pos)
    return true
end
-- OurTibia (05.10.2026): a monster or NPC stepping into the path makes the
-- server answer "Sorry, not possible." - walk on at once with a new path around
-- it (the client's own retry waited up to half a second, which looked like the
-- map click was cancelled).
local function onMapClickBlocked(mode, text)
    if not mapClick.dest or type(text) ~= 'string' then return end
    if not (text:find('Sorry, not possible', 1, true) or text:find('There is not enough room', 1, true)) then return end
    scheduleEvent(function()
        local p = g_game.getLocalPlayer()
        local dest = mapClick.dest
        if not p or not dest or mapClick.event then return end
        local pos = p:getPosition()
        if not pos or pos.z ~= dest.z or (pos.x == dest.x and pos.y == dest.y) then return end
        if not adjustMapClick(pos) then clearMapClick(); return end
        mapClick.retrying = true
        pcall(function() originalAutoWalk(p, dest) end)
        mapClick.retrying = false
    end, 40)
end
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
        onAutoWalkFail = function() if not ourFieldWalk() then retryMapClick() end end
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
