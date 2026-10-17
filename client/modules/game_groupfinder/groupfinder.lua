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
local function hms(sec) sec = math.max(0, math.floor(tonumber(sec) or 0)); return string.format('%d:%02d:%02d', math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60) end
local receivedAt = 0
local tickEvent
local dialog

-- 16.10.2026 (Tobeto): difficulty as a bar of pips instead of '*'
local DIFF_COLORS = {'#5fbf4f', '#9fcf3f', '#d8d040', '#e8a830', '#e87a30', '#e04a30', '#c02a5a'}
local function drawPips(panel, stars, size, gap)
  panel:destroyChildren()
  local level = math.max(1, math.min(7, (tonumber(stars) or 4) - 3))
  for k = 1, 7 do
    local p = g_ui.createWidget('UIWidget', panel)
    p:setSize({width = size, height = panel:getHeight()}); p:setPhantom(true)
    p:addAnchor(AnchorTop, 'parent', AnchorTop); p:addAnchor(AnchorLeft, 'parent', AnchorLeft); p:setMarginLeft((k - 1) * (size + gap))
    p:setBackgroundColor(k <= level and DIFF_COLORS[level] or '#2c2c2c')
    p:setBorderWidth(1); p:setBorderColor(k <= level and '#00000060' or '#3a3a3a')
  end
  panel:setTooltip('Difficulty ' .. level .. ' / 7')
end
local function cooldownLeft() return math.max(0, (tonumber(data and data.resetIn) or 0) - math.floor((g_clock.millis() - receivedAt) / 1000)) end

-- 17.10.2026 (Tobeto): human-size outfits (Grimbold, Sir Malthor, Malzareth) use only the
-- lower right quarter of their 64 px picture; an overlay draws them about twice as big and
-- moved so the figure fills the frame like the big monsters (the layout widget stays)
-- 17.10.2026 (Tobeto): Sir Malthor (131) and Azhereth (309) bigger, Malzareth (130) 2 px lower
local SMALL_LOOKS = {[70] = {1.9, 0.47}, [130] = {1.5, 0.16, 2}, [131] = {1.7, 0.3}, [309] = {1.35, 0.2}} -- scale, shift, extra y
local function bigArt(widget, look, name)
  local parent = widget:getParent()
  local overlay = parent:getChildById(widget:getId() .. 'Big')
  if not SMALL_LOOKS[look.type] then
    if overlay then overlay:hide() end
    widget:show()
    OurTibiaArt.creature(widget, look, name)
    return
  end
  local w, h = widget:getWidth(), widget:getHeight()
  if not overlay then
    overlay = g_ui.createWidget('UICreature', parent)
    overlay:setId(widget:getId() .. 'Big'); overlay:setPhantom(true)
    overlay:addAnchor(AnchorLeft, widget:getId(), AnchorLeft); overlay:addAnchor(AnchorTop, widget:getId(), AnchorTop)
  end
  overlay:setOutfit(look)
  local fit = SMALL_LOOKS[look.type]
  pcall(function() overlay:setCreatureSize(math.floor(w * fit[1])) end)
  pcall(function() overlay:setCenter(true) end)
  overlay:setSize({width = w, height = h})
  overlay:setMarginLeft(-math.floor(w * fit[2])); overlay:setMarginTop(-math.floor(h * fit[2]) + (fit[3] or 0))
  overlay:setOpacity(widget:getOpacity())
  overlay:show(); widget:hide()
end
local function introChip(parent, x, title, value)
  local c = g_ui.createWidget('GFInfoChip', parent)
  c:addAnchor(AnchorLeft, 'parent', AnchorLeft); c:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter); c:setMarginLeft(x)
  local a = g_ui.createWidget('Label', c); a:setText(title); a:setColor('#a0a0a0'); a:setTextAutoResize(true)
  a:addAnchor(AnchorLeft, 'parent', AnchorLeft); a:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter); a:setMarginLeft(10)
  local b = g_ui.createWidget('Label', c); b:setText(value); b:setColor('#ffd35a'); b:setFont('verdana-11px-rounded'); b:setTextAutoResize(true)
  -- 17.10.2026 (Tobeto): the yellow value 1 px to the right
  b:addAnchor(AnchorLeft, 'prev', AnchorRight); b:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter); b:setMarginLeft(6)
  b:setMarginTop(-2) -- 17.10.2026 (Tobeto): the yellow value 1 px higher
  local w = 10 + a:getTextSize().width + 6 + b:getTextSize().width + 9
  c:setWidth(w)
  return w
end
local function renderIntro()
  local box = ui('introInner'); if not box or box.built then return end
  box.built = true
  local x = 0
  x = x + introChip(box, x, 'Group size:', 'up to 4 players') + 10
  x = x + introChip(box, x, 'Fight time:', math.floor((tonumber(data.limit) or 900) / 60) .. ' minutes') + 10
  x = x + introChip(box, x, 'Cooldown resets:', 'at server save')
  box:setWidth(x)
end

-- ------------------------------------------------------------------ render
local function updateCooldowns()
  if not window or not data then return end
  local left = cooldownLeft()
  for i, b in ipairs(data.bosses or {}) do
    local w = ui('list'):getChildById('boss' .. i)
    if w and b.done then w:getChildById('cooldown'):setText('Defeated\nNext fight in ' .. hms(left)) end
  end
end
local function renderList()
  local list = ui('list'); list:destroyChildren()
  for i, b in ipairs(data.bosses or {}) do
    local w = g_ui.createWidget('GFBossEntry', list)
    w:setId('boss' .. i)
    local o = b.look or {}
    -- 17.10.2026 (Tobeto): small outfits (Grimbold, Sir Malthor, Malzareth) fill the box like the big ones
    bigArt(w:getChildById('creature'), {type = o.type, head = o.head or 0, body = o.body or 0, legs = o.legs or 0, feet = o.feet or 0, addons = o.addons or 0}, b.name)
    w:getChildById('name'):setText(b.name)
    w:getChildById('info'):setText('Level ' .. b.level .. '+')
    drawPips(w:getChildById('pips'), b.stars, 12, 3)
    local low = (data.level or 0) < b.level
    if low then
      w:setOpacity(0.45); w:getChildById('info'):setColor('#e06060')
      w:setTooltip('Your level is too low (' .. b.level .. ' needed).')
    end
    if b.done then
      -- 17.10.2026 (Tobeto): no dark box over the text - the level line and the bar make room
      -- for one clean line "Defeated - next fight in ..."
      w:getChildById('creature'):setOpacity(0.4); local ov = w:getChildById('creatureBig'); if ov then ov:setOpacity(0.4) end; w:getChildById('name'):setColor('#8a8a8a')
      w:getChildById('info'):hide(); w:getChildById('pips'):hide()
      w:getChildById('cooldown'):show()
      w:setTooltip('You defeated ' .. b.name .. ' today. The cooldown resets at the server save.')
    end
    w.onFocusChange = function(widget, focused) if focused then selected = i; modules.game_groupfinder.renderDetails() end end
  end
  updateCooldowns()
  local w = list:getChildById('boss' .. selected)
  if w then w:focus() end
end

function renderDetails()
  if not window or not data then return end
  local b = data.bosses and data.bosses[selected]
  if not b then return end
  local o = b.look or {}
  bigArt(ui('bigCreature'), {type = o.type, head = o.head or 0, body = o.body or 0, legs = o.legs or 0, feet = o.feet or 0, addons = o.addons or 0}, b.name)
  ui('bossName'):setText(b.name)
  ui('bossStats'):setText('Level ' .. b.level .. '+     Health ' .. num(b.hp))
  ui('bossStats'):setColor((data.level or 0) < b.level and '#e06060' or '#d0d0d0')
  drawPips(ui('bigPips'), b.stars, 20, 3)
  local mp = ui('mechanics'); mp:destroyChildren()
  for _, m in ipairs(b.mechanics or {}) do
    local c = g_ui.createWidget('GFMechanic', mp); c:setText(m); c:setWidth(c:getTextSize().width + 18)
    local tip = data.mtips and data.mtips[m]
    if tip then c:setTooltip(tip) end
  end
  local panel = ui('rewards'); panel:destroyChildren()
  -- 17.10.2026 (Tobeto): the real item name (it drops unidentified)
  for k, cid in ipairs(b.rewards or {}) do
    local it = g_ui.createWidget('GFRewardItem', panel); it:setItemId(cid)
    local nm = (b.rewardNames or {})[k]
    -- 18.10.2026 (owner): the tier of the dropped item is shown (tooltip + a small T badge)
    local tier = tonumber(b.stars) or 0
    local tierText = tier > 0 and ('Tier ' .. tier .. ', ') or ''
    it:setTooltip(nm and (nm:gsub('^%l', string.upper) .. '\n(' .. tierText .. 'drops unidentified)') or ('Unidentified item' .. (tier > 0 and ('\nTier ' .. tier) or '')))
    if tier > 0 then
      local badge = g_ui.createWidget('Label', it)
      badge:setText('T' .. tier); badge:setPhantom(true); badge:setFont('verdana-11px-rounded'); badge:setColor('#ffd35a')
      badge:addAnchor(AnchorBottom, 'parent', AnchorBottom); badge:addAnchor(AnchorRight, 'parent', AnchorRight)
      badge:setMarginRight(1); badge:setMarginBottom(0); badge:setTextAutoResize(true)
    end
  end
  for k, cid in ipairs(b.extras or {}) do local it = g_ui.createWidget('GFRewardItem', panel); it:setItemId(cid); it:setTooltip(({'Magical stone fragments', b.major and 'Major upgrade stones' or 'Minor upgrade stones', 'Rarity Infuser', 'Astral Protector'})[k]) end
  local lobby = data.lobby
  local canAct = not b.done and (data.level or 0) >= b.level and not (lobby and lobby.state == 'fight')
  local join = ui('joinButton')
  join:setEnabled(canAct and not lobby and next(data.roles or {}) ~= nil)
  ui('createButton'):setEnabled(canAct and not lobby and next(data.roles or {}) ~= nil)
  -- every group waiting for this boss
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
          (g.locked and '\nLocked: you will be asked for the password.' or '') ..
          (g.premade and '\nA party group - it is closed.' or ''))
        if g.locked then row:getChildById('text'):setColor('#e0c070') end
        local mine = lobby and lobby.id == g.id
        local btn = row:getChildById('joinGroup')
        btn:setEnabled(not mine and not g.premade and g.state == 'open' and canAct and #(g.members or {}) < 4 and true or false)
        btn:setText(mine and 'Yours' or 'Join')
        local id, locked = g.id, g.locked
        btn.onClick = function()
          askRole({title = 'Join the group', password = locked, needPassword = locked, taken = count}, function(r, pw) send('joinid:' .. id .. ':' .. r .. ':' .. pw) end)
        end
      end
    end
  end
  if shown == 0 then
    local row = g_ui.createWidget('GFGroupRow', gp)
    row:getChildById('text'):setText('No group is waiting - join or create one, or Start alone.')
    row:getChildById('text'):setColor('#808080'); row:getChildById('joinGroup'):hide()
  elseif more > 0 then
    local row = g_ui.createWidget('GFGroupRow', gp)
    row:getChildById('text'):setText('... and ' .. more .. ' more group(s). Join group picks the oldest one with a free slot.')
    row:getChildById('text'):setColor('#808080'); row:getChildById('joinGroup'):hide()
  end
  -- own group
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
    ui('leaveButton'):show(); ui('roleButton'):show()
    ui('leaveButton'):setEnabled(true)
    ui('roleButton'):setEnabled(lobby.state == 'open')
    ui('startButton'):setEnabled(lobby.leader and lobby.state == 'open')
    ui('startButton'):setTooltip(lobby.leader and 'Start the fight (ready check / agreement of the group)' or 'Only the group leader can start.')
  else
    ui('groupState'):setText('Choose a boss, then join or create a group.')
    -- 17.10.2026 (Tobeto): no Leave group / Change role without a group; Start = fight alone
    ui('leaveButton'):hide(); ui('roleButton'):hide()
    ui('startButton'):setEnabled(canAct and next(data.roles or {}) ~= nil)
    ui('startButton'):setTooltip('Fight ' .. (b.name or 'this boss') .. ' alone.')
  end
end

-- ------------------------------------------------------------------ role dialog
function closeDialog() if dialog then dialog:destroy(); dialog = nil end end
-- 17.10.2026 (Tobeto): small Yes / No window inside the Group Finder (can be dragged inside it)
local confirmBox
function confirm(title, onYes, onNo)
  if confirmBox then confirmBox:destroy(); confirmBox = nil end
  confirmBox = g_ui.createWidget('GFConfirm', window)
  confirmBox:setText(title)
  local wr = window:getRect()
  confirmBox:setPosition({x = wr.x + math.floor((wr.width - confirmBox:getWidth()) / 2), y = wr.y + math.floor((wr.height - confirmBox:getHeight()) / 2)})
  local function close() if confirmBox then confirmBox:destroy(); confirmBox = nil end end
  confirmBox:getChildById('yes').onClick = function() close(); if onYes then onYes() end end
  confirmBox:getChildById('no').onClick = function() close(); if onNo then onNo() end end
  confirmBox.onEnter = function() close(); if onYes then onYes() end end
  confirmBox.onEscape = function() close(); if onNo then onNo() end end
  confirmBox:raise(); confirmBox:focus()
end
function askRole(opt, callback)
  closeDialog()
  dialog = g_ui.createWidget('GFRoleDialog', rootWidget)
  dialog:setText(opt.title or 'Choose your role')
  local allowed = data and data.roles or {}
  local taken = opt.taken or {}
  local pick = (role and allowed[role]) and role or nil
  local buttons = {}
  local function refresh()
    for r, w in pairs(buttons) do w:setChecked(pick == r); w:setOn(pick == r) end
    dialog:getChildById('ok'):setEnabled(pick ~= nil)
  end
  for _, r in ipairs({'tank', 'healer', 'dps'}) do
    local w = dialog:getChildById(r); buttons[r] = w
    local full = (taken[r] or 0) >= (r == 'dps' and 2 or 1)
    w:setEnabled(allowed[r] == true and not full)
    if not allowed[r] then w:setTooltip(r == 'tank' and 'Only knights can be tanks.' or (r == 'healer' and 'Paladins can only join as DPS.') or 'Knights can only join as Tank.')
    elseif full then w:setTooltip('This role is already taken in the group.') end
    if pick == r and not w:isEnabled() then pick = nil end
    w.onClick = function() pick = r; refresh() end
  end
  if not pick then for _, r in ipairs({'tank', 'healer', 'dps'}) do if buttons[r]:isEnabled() then pick = r; break end end end
  local pw = dialog:getChildById('password')
  local showPw = opt.password and true or false
  dialog:getChildById('pwLabel'):setVisible(showPw); pw:setVisible(showPw)
  if opt.needPassword then dialog:getChildById('pwLabel'):setText('Password:') end
  if not showPw then dialog:setHeight(dialog:getHeight() - 30) end
  dialog:getChildById('note'):setText(opt.note or '')
  local function ok()
    if not pick then return end
    local text = (pw:getText() or ''):gsub('[^%w]', ''):sub(1, 16)
    role = pick; g_settings.set('groupfinder_role', pick)
    closeDialog(); callback(pick, text)
  end
  dialog:getChildById('ok').onClick = ok
  dialog:getChildById('cancel').onClick = closeDialog
  dialog.onEnter = ok
  dialog.onEscape = closeDialog
  refresh()
  dialog:raise(); dialog:focus()
  if showPw then pw:focus() end
end

local function tick()
  tickEvent = nil
  if not window or not window:isVisible() then return end
  updateCooldowns()
  tickEvent = scheduleEvent(tick, 1000)
end
local function render()
  if not window or not data then return end
  renderIntro()
  renderList()
  renderDetails()
  if not tickEvent then tickEvent = scheduleEvent(tick, 1000) end
end

-- ------------------------------------------------------------------ actions
function join() askRole({title = 'Quick join'}, function(r) send('join:' .. selected .. ':' .. r) end) end
function create() askRole({title = 'Create a group', password = true}, function(r, pw) send('create:' .. selected .. ':' .. r .. ':' .. pw) end) end
function changeRole()
  local l = data and data.lobby; if not l then return end
  local taken = {tank = 0, healer = 0, dps = 0}
  for _, m in ipairs(l.members or {}) do if not m.me then taken[m.role] = (taken[m.role] or 0) + 1 end end
  askRole({title = 'Change your role', taken = taken}, function(r) send('join:' .. l.boss .. ':' .. r) end)
end
function joinParty() send('party:' .. selected) end
-- 17.10.2026 (Tobeto): one "Join group" button. In a party: asked whether to join as the party;
-- otherwise (or "No") the player joins on his own (the oldest group with a free place).
local function inParty() local p = g_game.getLocalPlayer(); return p and p.isPartyMember and p:isPartyMember() end
function joinGroup()
  if inParty() then
    confirm('Join as a party?', function() joinParty() end, function() join() end)
  else
    join()
  end
end
local function soloRole()
  local allowed = data and data.roles or {}
  if role and allowed[role] then return role end
  for _, r in ipairs({'dps', 'healer', 'tank'}) do if allowed[r] then return r end end
end
function leave() send('leave') end
function start()
  if data and data.lobby then return send('start') end
  -- not in a group: fight the selected boss alone (asked first)
  local r = soloRole(); if not r then return end
  local i = selected
  confirm('Fight alone', function() send('solo:' .. i .. ':' .. r) end)
end
function hide() closeDialog(); if tickEvent then removeEvent(tickEvent); tickEvent = nil end; if window then window:hide() end; send('close') end
function toggle()
  if window:isVisible() then hide() else send('open') end
end

local function closePrompt()
  if promptEvent then removeEvent(promptEvent); promptEvent = nil end
  if promptBox then promptBox:destroy(); promptBox = nil end
end
local function showPrompt(p)
  closePrompt()
  if p.type == 'solo' then
    return confirm('Fight alone', function() send('start:solo') end)
  end
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
  receivedAt = g_clock.millis()
  -- the fight started: get the window out of the way
  if not wasFight and data.lobby and data.lobby.state == 'fight' and window:isVisible() then window:hide() end
  if data.lobby and data.lobby.boss and result.open then selected = data.lobby.boss end
  if result.open then render(); window:show(); fitToScreen(window, 800, 640); window:raise(); window:focus()
  elseif window:isVisible() then render() end
  if button then
    local l = data.lobby
    button:setTooltip(l and ('Group Finder (Ctrl+F)\nIn a group (' .. #l.members .. '/4)') or 'Group Finder (Ctrl+F)')
  end
end
local function onGameEnd() closePrompt(); clearOverlay(); closeDialog(); if window then window:hide() end; data = nil end

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
