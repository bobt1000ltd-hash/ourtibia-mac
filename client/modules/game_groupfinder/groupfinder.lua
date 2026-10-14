-- Group Finder for the daily bosses (Claude, 03.10.2026).
-- Server: data/scripts/myots/90_group_finder.lua, extended opcode 117.
local OPCODE = 117
local window, data, button, promptBox, promptEvent, overlay, overlayEvent
local parts = {}
local selected = 1
local role = nil
local ROLE_COLOR = {tank = '#6aa8ff', healer = '#60e070', dps = '#ff8a5a'}
local ROLE_TEXT = {tank = 'TANK', healer = 'HEAL', dps = 'DPS'}

-- 11.10.2026: keep the window inside small game windows (default 1020x644)
local function fitToScreen(w, fullW, fullH)
  if not w then return end
  local root = rootWidget or g_ui.getRootWidget()
  local rw, rh = root:getWidth(), root:getHeight()
  w:setWidth(math.min(fullW, rw - 10))
  w:setHeight(math.min(fullH, rh - 10))
  local pos = w:getPosition()
  w:setPosition({x = math.max(0, math.min(pos.x, rw - w:getWidth())), y = math.max(0, math.min(pos.y, rh - w:getHeight()))})
end

local function send(text) if g_game.isOnline() then g_game.getProtocolGame():sendExtendedOpcode(OPCODE, text) end end
local function ui(id) return window and window:recursiveGetChildById(id) end
local function num(n) n = math.floor(tonumber(n) or 0); local s = tostring(n):reverse():gsub('(%d%d%d)', '%1,'):reverse(); return (s:gsub('^,', '')) end
local function clock(sec) sec = math.max(0, math.floor(tonumber(sec) or 0)); return string.format('%d:%02d', math.floor(sec / 60), sec % 60) end
local function stars(n) return string.rep('*', tonumber(n) or 0) end

-- ------------------------------------------------------------------ render
local function renderList()
  local list = ui('list'); list:destroyChildren()
  for i, b in ipairs(data.bosses or {}) do
    local w = g_ui.createWidget('GFBossEntry', list)
    w:setId('boss' .. i)
    local o = b.look or {}
    w:getChildById('creature'):setOutfit({type = o.type, head = o.head or 0, body = o.body or 0, legs = o.legs or 0, feet = o.feet or 0, addons = o.addons or 0})
    w:getChildById('name'):setText(b.name)
    w:getChildById('info'):setText('Level ' .. b.level .. '+   ' .. num(b.hp) .. ' HP   ' .. stars(b.stars))
    local st = w:getChildById('status')
    if b.done then st:setText('Defeated today'); st:setColor('#60d060')
    elseif (tonumber(b.busy) or 0) > 0 then st:setText('Arena occupied (' .. clock(b.busy) .. ')'); st:setColor('#e0a040')
    elseif (data.level or 0) < b.level then st:setText('Requires level ' .. b.level); st:setColor('#a05050')
    else
      local q = b.queue or {}
      st:setText(string.format('Queue: T %d  H %d  D %d', q.tank or 0, q.healer or 0, q.dps or 0)); st:setColor('#a0a0a0')
    end
    w.onFocusChange = function(widget, focused) if focused then selected = i; modules.game_groupfinder.renderDetails() end end
  end
  local w = list:getChildById('boss' .. selected)
  if w then w:focus() end
end

function renderDetails()
  if not window or not data then return end
  local b = data.bosses and data.bosses[selected]
  if not b then return end
  local o = b.look or {}
  ui('bigCreature'):setOutfit({type = o.type, head = o.head or 0, body = o.body or 0, legs = o.legs or 0, feet = o.feet or 0, addons = o.addons or 0})
  ui('bossName'):setText(b.name)
  ui('bossTitle'):setText(b.title or '')
  ui('bossStats'):setText('Level ' .. b.level .. '+   Health ' .. num(b.hp) .. ' (the same for any group size)\nItem tier: ' .. stars(b.stars) .. ' (' .. b.stars .. ')   Time limit: ' .. clock(data.limit or 900))
  ui('bossDesc'):setText(b.desc or '')
  local mech = {}
  for _, m in ipairs(b.mechanics or {}) do mech[#mech + 1] = '- ' .. m end
  ui('mechanics'):setText(table.concat(mech, '\n'))
  local panel = ui('rewards'); panel:destroyChildren()
  for _, cid in ipairs(b.rewards or {}) do local it = g_ui.createWidget('GFRewardItem', panel); it:setItemId(cid); it:setTooltip('Unidentified, tier ' .. b.stars) end
  for k, cid in ipairs(b.extras or {}) do local it = g_ui.createWidget('GFRewardItem', panel); it:setItemId(cid); it:setTooltip(({'Magical stone fragments', b.major and 'Major upgrade stones' or 'Minor upgrade stones', 'Rarity Infuser', 'Astral Protector'})[k]) end
  local frag = b.frag or {0, 0}
  local stonesTxt = (b.stones and (b.stones[1] .. '-' .. b.stones[2]) or '') .. ' ' .. (b.major and 'major' or 'minor') .. ' stones'
  ui('rewardsText'):setText('1-2 items of the set (unidentified, ' .. b.stars .. ' stars), ' .. frag[1] .. '-' .. frag[2] .. ' fragments, ' .. stonesTxt ..
    ', Rarity Infuser ' .. (b.infuser or 0) .. '%, Astral Protector ' .. (b.protector or 0) .. '%. Only players alive in the arena get rewards.')
  -- roles
  local allowed = data.roles or {}
  if role and not allowed[role] then role = nil end
  if not role then for _, r in ipairs({'tank', 'healer', 'dps'}) do if allowed[r] then role = role or r end end end
  for r, id in pairs({tank = 'roleTank', dps = 'roleDps', healer = 'roleHealer'}) do
    local w = ui(id)
    w:setEnabled(allowed[r] == true)
    w:setOn(role == r); w:setChecked(role == r)
    w:setTooltip(allowed[r] and ('Join as ' .. w:getText()) or (r == 'tank' and 'Only knights can be tanks.' or (r == 'healer' and allowed.dps and 'Paladins can only join as DPS.') or 'Knights can only join as Tank.'))
  end
  local lobby = data.lobby
  local join = ui('joinButton')
  join:setEnabled(not b.done and (data.level or 0) >= b.level and not (lobby and lobby.state == 'fight') and role ~= nil)
  join:setText(lobby and lobby.boss == selected and lobby.state == 'open' and 'Change role' or 'Quick join')
  local canAct = not b.done and (data.level or 0) >= b.level and not (lobby and lobby.state == 'fight')
  ui('createButton'):setEnabled(canAct and role ~= nil)
  ui('partyButton'):setEnabled(canAct)
  -- 04.10.2026: every group waiting for this boss, pick the one you want
  local gp = ui('groups'); gp:destroyChildren()
  local shown, more = 0, 0
  for _, g in ipairs(data.groups or {}) do
    if g.boss == selected then
      if shown >= 4 then more = more + 1 else
        shown = shown + 1
        local row = g_ui.createWidget('GFGroupRow', gp)
        local names, leaderName = {}, ''
        local count = {tank = 0, healer = 0, dps = 0}
        for _, m in ipairs(g.members or {}) do
          count[m.role] = (count[m.role] or 0) + 1
          names[#names + 1] = m.name .. ' (' .. (ROLE_TEXT[m.role] or m.role) .. ')'
          if m.leader then leaderName = m.name end
        end
        local tag = g.premade and '[Party] ' or (g.locked and '[Locked] ' or '')
        row:getChildById('text'):setText(tag .. #(g.members or {}) .. '/4  ' .. table.concat(names, ', '))
        row:setTooltip('Leader: ' .. leaderName .. '\nTank ' .. count.tank .. '/1, Healer ' .. count.healer .. '/1, DPS ' .. count.dps .. '/2' ..
          (g.locked and '\nLocked: type the password into the password field before you join.' or '') ..
          (g.premade and '\nA party group - it is closed.' or ''))
        if g.locked then row:getChildById('text'):setColor('#e0c070') end
        local mine = lobby and lobby.id == g.id
        local btn = row:getChildById('joinGroup')
        local free = role and #(g.members or {}) < 4 and (count[role] or 0) < (role == 'dps' and 2 or 1)
        btn:setEnabled(not mine and not g.premade and g.state == 'open' and canAct and free and true or false)
        btn:setText(mine and 'Yours' or 'Join')
        local id = g.id
        btn.onClick = function() if role then send('joinid:' .. id .. ':' .. role .. ':' .. password()) end end
      end
    end
  end
  if shown == 0 then
    local row = g_ui.createWidget('GFGroupRow', gp)
    row:getChildById('text'):setText('No group is waiting. Use Quick join or create your own group.')
    row:getChildById('text'):setColor('#808080'); row:getChildById('joinGroup'):hide()
  elseif more > 0 then
    local row = g_ui.createWidget('GFGroupRow', gp)
    row:getChildById('text'):setText('... and ' .. more .. ' more group(s). Quick join picks the oldest one with a free slot.')
    row:getChildById('text'):setColor('#808080'); row:getChildById('joinGroup'):hide()
  end
  -- group
  local slots = ui('slots'); slots:destroyChildren()
  if lobby then
    local lb = data.bosses[lobby.boss] or {}
    local stateText = ({open = 'waiting for players', check = 'checking...', fight = 'in the arena'})[lobby.state] or lobby.state
    ui('groupState'):setText((lb.name or '') .. ' - ' .. #lobby.members .. '/4 - ' .. stateText .. (lobby.premade and ' (party)' or (lobby.locked and ' (locked)' or '')))
    for idx, m in ipairs(lobby.members) do
      local s = g_ui.createWidget('GFSlot', slots)
      if lobby.leader and not m.me and lobby.state == 'open' then
        local k = s:getChildById('kick'); k:show()
        k.onClick = function() send('kick:' .. idx) end
      end
      local r = s:getChildById('role'); r:setText(ROLE_TEXT[m.role] or m.role); r:setColor(ROLE_COLOR[m.role] or '#ffffff')
      local mark = (m.ready == true) and '  [ready]' or ((m.ready == false) and '  [no]' or '')
      s:getChildById('name'):setText((m.leader and '[Leader] ' or '') .. m.name .. '  (' .. m.level .. ' ' .. (m.voc or '') .. ')' .. mark)
      if m.me then s:setBorderColor('#d8a840') end
    end
    for _ = #lobby.members + 1, 4 do
      local s = g_ui.createWidget('GFSlot', slots); s:getChildById('name'):setText('- free -'); s:getChildById('name'):setColor('#606060')
    end
    ui('leaveButton'):setEnabled(true)
    ui('startButton'):setEnabled(lobby.leader and lobby.state == 'open')
    ui('startButton'):setTooltip(lobby.leader and 'Start the fight (ready check / agreement of the group)' or 'Only the group leader can start.')
  else
    ui('groupState'):setText('Choose a boss and a role, then join the queue.')
    ui('leaveButton'):setEnabled(false)
    ui('startButton'):setEnabled(false)
  end
end

local function render()
  if not window or not data then return end
  renderList()
  renderDetails()
end

-- ------------------------------------------------------------------ actions
function pickRole(r) role = r; g_settings.set('groupfinder_role', r); renderDetails() end
function password()
  local e = ui('passwordEdit'); local t = e and e:getText() or ''
  return (t:gsub('[^%w]', ''):sub(1, 16))
end
function join() if role then send('join:' .. selected .. ':' .. role) end end
function create() if role then send('create:' .. selected .. ':' .. role .. ':' .. password()) end end
function joinParty() send('party:' .. selected) end
function leave() send('leave') end
function start() send('start') end
function hide() if window then window:hide() end; send('close') end
function toggle()
  if window:isVisible() then hide() else send('open') end
end

local function closePrompt()
  if promptEvent then removeEvent(promptEvent); promptEvent = nil end
  if promptBox then promptBox:destroy(); promptBox = nil end
end
local function showPrompt(p)
  closePrompt()
  local titles = {ready = 'Ready check', agree = 'Start without a full group?', solo = 'Fight alone?'}
  local title = titles[p.type] or 'Group Finder'
  local yesCmd = p.type == 'solo' and 'start:solo' or 'yes'
  local yes = function() closePrompt(); send(yesCmd) end
  local no = function() closePrompt(); if p.type ~= 'solo' then send('no') end end
  promptBox = displayGeneralBox(title, p.text or '', {{text = p.type == 'ready' and 'Ready' or tr('Yes'), callback = yes}, {text = p.type == 'ready' and 'Not ready' or tr('No'), callback = no}, anchor = AnchorHorizontalCenter}, yes, no)
  local left = tonumber(p.timeout) or 0
  if left > 0 then
    local function tick()
      if not promptBox then return end
      promptBox:setText(title .. '  (' .. left .. ' s)')
      left = left - 1
      if left < 0 then closePrompt() return end
      promptEvent = scheduleEvent(tick, 1000)
    end
    tick()
  end
  pcall(function() if g_window.flash then g_window.flash() end end)
end

-- ------------------------------------------------------------------ doom overlay
-- 04.10.2026: the safe tiles are painted on the map tiles themselves (they stay
-- on the floor while you walk); the danger is shown by a red frame around the
-- game screen only, so the whole screen stays visible.
-- 07.10.2026: no more painted (opaque) tiles. The safe tiles get a looping green-rings
-- effect attached to the tile (the floor stays fully visible) and the danger is shown by
-- a pulsing red frame around the game screen.
local SAFE_EFFECT_ID = 9101
local SAFE_GLOW_ID = 9102
local DANGER_ID = 9103 -- 07.10.2026: the other arena tiles glow red at the same time
local marked = {}
local effectsReady = false
local function ensureEffects()
  if effectsReady then return true end
  if not AttachedEffectManager or not g_attachedEffects then return false end
  local ok = pcall(function()
    AttachedEffectManager.register(SAFE_EFFECT_ID, 'Group Finder safe tile', 9, ThingCategoryEffect, {speed = 1.0, opacity = 1.0})
    AttachedEffectManager.register(SAFE_GLOW_ID, 'Group Finder safe glow', 15, ThingCategoryEffect, {speed = 0.6, opacity = 0.8})
    AttachedEffectManager.register(DANGER_ID, 'Group Finder danger glow', 14, ThingCategoryEffect, {speed = 0.6, opacity = 0.8})
  end)
  effectsReady = ok
  return ok
end
local function clearOverlay()
  if overlayEvent then removeEvent(overlayEvent); overlayEvent = nil end
  for _, t in ipairs(marked) do
    pcall(function() t:detachEffectById(SAFE_EFFECT_ID) end)
    pcall(function() t:detachEffectById(SAFE_GLOW_ID) end)
    pcall(function() t:detachEffectById(DANGER_ID) end)
  end
  marked = {}
  if overlay then overlay:destroy(); overlay = nil end
end
local function showDoom(d)
  clearOverlay()
  if ensureEffects() then
    for _, s in ipairs(d.safe or {}) do
      local t = g_map.getTile({x = s[1], y = s[2], z = s[3]})
      if t then
        pcall(function()
          t:attachEffect(g_attachedEffects.getById(SAFE_EFFECT_ID))
          t:attachEffect(g_attachedEffects.getById(SAFE_GLOW_ID))
        end)
        marked[#marked + 1] = t
      end
    end
    -- every other walkable arena tile: the same glow in red
    local safeSet = {}
    for _, s in ipairs(d.safe or {}) do safeSet[s[1] .. ':' .. s[2]] = true end
    local a = d.area
    if type(a) == 'table' and #a >= 5 and (a[3] - a[1]) * (a[4] - a[2]) < 4000 then
      for x = a[1], a[3] do
        for y = a[2], a[4] do
          if not safeSet[x .. ':' .. y] then
            local t = g_map.getTile({x = x, y = y, z = a[5]})
            if t and t:isWalkable(true) then
              pcall(function() t:attachEffect(g_attachedEffects.getById(DANGER_ID)) end)
              marked[#marked + 1] = t
            end
          end
        end
      end
    end
  end
  local map = modules.game_interface and modules.game_interface.getMapPanel and modules.game_interface.getMapPanel()
  if map then
    overlay = g_ui.createWidget('UIWidget', map)
    overlay:setPhantom(true)
    overlay:fill('parent')
    overlay:setBorderWidth(5)
    overlay:setBorderColor('#ff2020c0')
  end
  local untilMs = g_clock.millis() + (tonumber(d.ms) or 4000)
  local pulse = 0
  local function blink()
    if g_clock.millis() >= untilMs then clearOverlay() return end
    pulse = pulse + 1
    if overlay then overlay:setBorderColor(pulse % 2 == 0 and '#ff2020d0' or '#ff202050') end
    overlayEvent = scheduleEvent(blink, 300)
  end
  blink()
end

-- ------------------------------------------------------------------ network
local function receive(protocol, opcode, buffer)
  local i, total, piece = buffer:match('^(%d+)/(%d+)|(.*)$')
  if not i then return end
  i, total = tonumber(i), tonumber(total); if i == 1 then parts = {} end; parts[i] = piece; if i < total then return end
  local ok, result = pcall(json.decode, table.concat(parts)); parts = {}
  if not ok or type(result) ~= 'table' then return end
  if result.kind == 'prompt' then return showPrompt(result) end
  if result.kind == 'closePrompt' then return closePrompt() end
  if result.kind == 'doom' then return showDoom(result) end
  if result.kind ~= 'groupfinder' then return end
  local wasFight = data and data.lobby and data.lobby.state == 'fight'
  data = result
  -- the fight started: get the window out of the way
  if not wasFight and data.lobby and data.lobby.state == 'fight' and window:isVisible() then window:hide() end
  if data.lobby and data.lobby.boss and result.open then selected = data.lobby.boss end
  if result.open then render(); window:show(); fitToScreen(window, 800, 760); window:raise(); window:focus()
  elseif window:isVisible() then render() end
  if button then
    local l = data.lobby
    button:setTooltip(l and ('Group Finder - in a group (' .. #l.members .. '/4)') or 'Group Finder - Daily Bosses (Ctrl+F)')
  end
end
local function onGameEnd() closePrompt(); clearOverlay(); if window then window:hide() end; data = nil end

function init()
  window = g_ui.displayUI('groupfinder'); window:hide()
  role = g_settings.get('groupfinder_role'); if role == '' then role = nil end
  ProtocolGame.registerExtendedOpcode(OPCODE, receive)
  connect(g_game, {onGameEnd = onGameEnd})
  -- the top button is created by game_myotshud (in place of the old Game Panels button)
  scheduleEvent(function() button = modules.game_mainpanel and modules.game_mainpanel.getButton and modules.game_mainpanel.getButton('groupFinder') end, 1500)
  g_keyboard.bindKeyDown('Ctrl+F', toggle)
end
function terminate()
  pcall(ProtocolGame.unregisterExtendedOpcode, OPCODE)
  disconnect(g_game, {onGameEnd = onGameEnd})
  g_keyboard.unbindKeyDown('Ctrl+F')
  closePrompt(); clearOverlay()
  button = nil
  if window then window:destroy() end
end
