-- OurTibia (16.10.2026): Guild Management window (Overview, Members, Achievements, Buffs, Browse).
-- Server: data/scripts/myots/95_guilds.lua, opcode 140. Every premium player can found a guild here.
local OPCODE = 140
local window, button
local defs, pendingDefs, buffDefs, caps, rankPoints = {}, nil, {}, {}, {}
local state, members, pendingMembers, progress = nil, {}, nil, {}
local browse, pendingBrowse = {}, nil
local page = 'Overview'
local selMember, selAch, selBrowse
local category = 'all'

local function send(data) if g_game.isOnline() then g_game.getProtocolGame():sendExtendedOpcode(OPCODE, json.encode(data)) end end
local function ui(id) return window and window:recursiveGetChildById(id) end
local function fmt(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  while true do local r, k = s:gsub('^(-?%d+)(%d%d%d)', '%1,%2'); s = r; if k == 0 then break end end
  return s
end
local function short(n)
  n = tonumber(n) or 0
  if n >= 1000000000 then return string.format('%.1fkkk', n / 1000000000) end
  if n >= 1000000 then return string.format('%.1fkk', n / 1000000) end
  if n >= 1000 then return string.format('%.0fk', n / 1000) end
  return tostring(n)
end
local function bonusText(v, pct)
  if pct then return '+' .. (v / 100) .. '%' end
  return '+' .. v
end
local function myGuild() return state and state.mine and state.mine > 0 end
local function viewing() return state and state.view == 1 end
local function rank() return state and state.rank or 0 end
local CAT = {mob = 'Mob Slayer', boss = 'Boss Slayer', misc = 'Misc'}

-- ---------------------------------------------------------------- pages
local PAGES = {'Overview', 'Members', 'Achievements', 'Buffs', 'Browse'}
local function showPage(name)
  page = name
  local hasGuild = state and state.guild
  for _, p in ipairs(PAGES) do ui('page' .. p):setVisible(false) end
  ui('pageNone'):setVisible(false)
  if name == 'Overview' and not hasGuild then ui('pageNone'):setVisible(true)
  elseif name ~= 'Browse' and not hasGuild then ui('pageNone'):setVisible(true)
  else ui('page' .. name):setVisible(true) end
  for _, p in ipairs(PAGES) do ui('tab' .. p):setOn(p == name) end
  if name == 'Browse' then send({a = 'browse', q = ui('searchText'):getText()}) end
end

local function notice(text, ok)
  ui('noticeText'):setText(text)
  ui('noticeText'):setColor(ok and '#90e090' or '#ff9a7a')
end

-- ---------------------------------------------------------------- render
local function renderHeader()
  local g = state and state.guild
  if g then
    ui('guildName'):setText(g.name .. (viewing() and '   (viewing)' or ''))
    ui('guildLine'):setText(('Rank %d  |  %d achievement points  |  %d members  |  Leader: %s'):format(g.grank or 0, g.points or 0, g.count or 0, g.owner or '?'))
  else
    ui('guildName'):setText('No guild')
    ui('guildLine'):setText('Found your own guild (premium account) or accept an invitation.')
  end
  ui('tabMine'):setVisible(viewing() and true or false)
end

local function renderOverview()
  local g = state and state.guild
  if not g then
    ui('createText'):setText(state and state.premium == 1 and
      'Every premium player can found a guild. Guild members fill the guild achievements together - every reached achievement rank gives a bonus to all members and raises the guild rank, which unlocks stronger guild buffs.'
      or 'You need a premium account to found a guild. You can still join a guild when you are invited.')
    ui('createButton'):setEnabled(state and state.premium == 1 and true or false)
    local list = ui('inviteList'); list:destroyChildren()
    for _, inv in ipairs(state and state.invites or {}) do
      local row = g_ui.createWidget('GuildRow', list)
      row:getChildById('dot'):setBackgroundColor('#d8c070')
      row:getChildById('name'):setText(inv.name)
      row:getChildById('info'):setText('invited you')
      row:getChildById('right'):setText('click to join')
      row.onClick = function() send({a = 'join', id = inv.id}) end
    end
    if #(state and state.invites or {}) == 0 then
      local row = g_ui.createWidget('GuildRow', list)
      row:getChildById('name'):setText('No invitations.')
    end
    return
  end
  local cap = g.cap or 2
  local nextNeed = rankPoints[(g.grank or 0) + 2]
  ui('infoText'):setText(('Guild: %s\nLeader: %s\nFounded: %s\nMembers: %d\nGuild rank: %d (buff levels up to %d)  -  achievement points: %d%s\n\n%s'):format(
    g.name, g.owner or '?', g.created and os.date('%d.%m.%Y', g.created) or '?', g.count or 0, g.grank or 0, cap, g.points or 0,
    nextNeed and ('  (next rank at ' .. nextNeed .. ')') or '  (highest rank)', g.motd and g.motd ~= '' and ('Message: ' .. g.motd) or ''))
  ui('bankText'):setText('Guild bank: ' .. fmt(g.bank or 0) .. ' gold' .. (viewing() and '' or '   -   buff levels are paid from the guild bank'))
  local canDeposit = myGuild() and not viewing()
  ui('depositAmount'):setVisible(canDeposit); ui('depositButton'):setVisible(canDeposit); ui('balanceText'):setVisible(canDeposit)
  ui('balanceText'):setText('Your bank: ' .. fmt(state.balance or 0))
  local list = ui('bonusList'); list:destroyChildren()
  for _, b in ipairs(g.bonus or {}) do
    local l = g_ui.createWidget('Label', list)
    l:setText(bonusText(b.v, b.pct == 1) .. ' ' .. b.label)
    l:setColor('#90e090')
  end
  if #(g.bonus or {}) == 0 then
    local l = g_ui.createWidget('Label', list); l:setText('No bonuses yet.'); l:setColor('#a8a8a8')
  end
end

local function renderMembers()
  local list = ui('memberList'); list:destroyChildren()
  for _, m in ipairs(members) do
    local row = g_ui.createWidget('GuildRow', list)
    row:getChildById('dot'):setBackgroundColor(m.online == 1 and '#40d040' or '#606060')
    row:getChildById('name'):setText(m.name)
    row:getChildById('info'):setText(('Level %d  %s'):format(m.level or 0, m.voc or ''))
    local rn = m.rank == 3 and 'Leader' or m.rank == 2 and 'Vice-Leader' or 'Member'
    row:getChildById('right'):setText(rn .. ((m.gold or 0) > 0 and ('  |  ' .. short(m.gold) .. ' gold') or ''))
    row.onClick = function() selMember = m.name; list:focusChild(row, MouseFocusReason) end
    if selMember == m.name then list:focusChild(row, MouseFocusReason) end
  end
  ui('memberHeader'):setText(('Members (%d)'):format(#members))
  local own = myGuild() and not viewing()
  ui('memberActions'):setVisible(own and true or false)
  ui('promoteButton'):setEnabled(rank() >= 3); ui('demoteButton'):setEnabled(rank() >= 3)
  ui('kickButton'):setEnabled(rank() >= 2); ui('inviteButton'):setEnabled(rank() >= 2)
  ui('inviteName'):setEnabled(rank() >= 2)
  ui('motdButton'):setEnabled(rank() >= 2); ui('motdText'):setEnabled(rank() >= 2)
end

local function progOf(key) for _, p in ipairs(progress) do if p.key == key then return p end end return {v = 0, r = 0} end
local function renderAchDetail()
  local a
  for _, d in ipairs(defs) do if d.key == selAch then a = d end end
  local panel = ui('achDetailPanel'); panel:destroyChildren()
  local function line(t, color)
    local l = g_ui.createWidget('Label', panel)
    l:setText(t); l:setColor(color or '#dcdcdc'); l:setTextWrap(true); l:setTextAutoResize(true)
  end
  if not a then line('Select an achievement.') return end
  local p = progOf(a.key)
  local lines = {}
  ui('achDetailHeader'):setText(a.name)
  lines[#lines + 1] = CAT[a.cat] or ''
  lines[#lines + 1] = ('Rank %d/3   -   progress: %s'):format(p.r or 0, fmt(p.v or 0))
  lines[#lines + 1] = ''
  for i = 1, 3 do
    local mark = (p.r or 0) >= i and '[x] ' or '[ ] '
    local b = a.bonus and a.label and (': ' .. bonusText(a.bonus[i], a.pct == 1) .. ' ' .. a.label) or ': +1 achievement point'
    lines[#lines + 1] = mark .. 'Rank ' .. i .. ' - ' .. fmt(a.need[i]) .. b
  end
  if a.bonus and a.label then
    local total = 0; for i = 1, (p.r or 0) do total = total + a.bonus[i] end
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'Total bonus for every member: ' .. bonusText(total, a.pct == 1) .. ' ' .. a.label
  end
  lines[#lines + 1] = ''
  if a.mobs and #a.mobs > 0 then
    lines[#lines + 1] = (a.cat == 'boss' and 'Bosses' or 'Monsters') .. ' for this achievement (kills of all members count):'
    for _, m in ipairs(a.mobs) do lines[#lines + 1] = '  * ' .. m end
  end
  if a.text then lines[#lines + 1] = a.text end
  if a.cat == 'misc' then lines[#lines + 1] = '(No stats - every rank gives 1 achievement point for the guild rank.)' end
  for _, t in ipairs(lines) do
    local c = '#dcdcdc'
    if t:find('^%[x%]') then c = '#90e090' elseif t:find('^  %*') then c = '#70c8f0' elseif t:find('^Total') then c = '#f0d060' end
    line(t == '' and ' ' or t, c)
  end
end

local function renderAchievements()
  local list = ui('achList'); list:destroyChildren()
  local g = state and state.guild
  ui('pointsLabel'):setText(g and ('Achievement points: ' .. (g.points or 0) .. '   Guild rank: ' .. (g.grank or 0)) or '')
  for _, a in ipairs(defs) do
    if category == 'all' or category == a.cat then
      local p = progOf(a.key)
      local row = g_ui.createWidget('AchRow', list)
      row:getChildById('name'):setText(a.name)
      row:getChildById('name'):setColor((p.r or 0) >= 3 and '#f0d060' or '#e8e8e8')
      row:getChildById('stars'):setText(('Rank %d/3'):format(p.r or 0))
      local r = p.r or 0
      local lo = r > 0 and a.need[r] or 0
      local hi = a.need[math.min(3, r + 1)]
      local pct = r >= 3 and 100 or math.floor(math.max(0, math.min(1, ((p.v or 0) - lo) / math.max(1, hi - lo))) * 100)
      local bar = row:getChildById('bar')
      bar:setPercent(pct)
      bar:setText(r >= 3 and 'complete' or (short(p.v or 0) .. ' / ' .. short(hi)))
      bar:setBackgroundColor(r >= 3 and '#b08a20' or '#2f7a2f')
      row.onClick = function() selAch = a.key; list:focusChild(row, MouseFocusReason); renderAchDetail() end
      if not selAch then selAch = a.key end
      if selAch == a.key then list:focusChild(row, MouseFocusReason) end
    end
  end
  renderAchDetail()
end

local function renderBuffs()
  local g = state and state.guild
  if not g then return end
  local cap = g.cap or 2
  local canBuy = myGuild() and not viewing() and rank() >= 2
  ui('buffInfo'):setText(('Guild rank %d  -  buff levels up to %d / %d.   Guild bank: %s gold.%s'):format(g.grank or 0, cap, 10, fmt(g.bank or 0),
    canBuy and '   The leader and vice-leaders buy levels (cost: level x level x 100,000 gold).' or (viewing() and '   (read-only)' or '   Only the leader and vice-leaders can buy levels.')))
  local titles = {'Defense & Vitality', 'Offense & Power', 'Magic & Elements'}
  local colors = {'#60d060', '#e05050', '#c070ff'}
  for c = 1, 3 do
    local col = ui('col' .. c)
    col:getChildById('title'):setText(titles[c]); col:getChildById('title'):setColor(colors[c])
    col:setBorderColor(colors[c] .. '80')
    local list = col:getChildById('list'); list:destroyChildren()
    for _, b in ipairs(buffDefs) do
      if b.col == c then
        local lvl = (g.buffs or {})[b.key] or 0
        local cell = g_ui.createWidget('BuffCell', list)
        if tonumber(b.icon) and tonumber(b.icon) > 0 then cell:getChildById('icon'):setItem(Item.create(b.icon, 1)) end
        cell:getChildById('name'):setText(b.name); cell:getChildById('name'):setColor(colors[c])
        cell:getChildById('level'):setText(('Level %d / %d'):format(math.min(lvl, cap), cap))
        local per = tonumber(b.per) or 0
        local cur = per * math.min(lvl, cap)
        local unit = b.unit or ''
        local function v(x) return b.pct == 1 and (string.format('%g', x) .. unit) or (string.format('%g', x) .. ' ' .. unit) end
        cell:getChildById('value'):setText('+' .. v(cur))
        cell:setTooltip(('%s\nEach level: +%s\nNow: +%s\nHighest level at your guild rank: %d (absolute max 10)\nNext level costs %s gold from the guild bank.'):format(
          b.name, v(per), v(cur), cap, fmt(100000 * (lvl + 1) * (lvl + 1))))
        local buy = cell:getChildById('buy')
        buy:setVisible(canBuy and true or false)
        buy:setEnabled(lvl < cap)
        buy.onClick = function() send({a = 'buy', key = b.key}) end
      end
    end
  end
end

local function renderBrowse()
  local list = ui('browseList'); list:destroyChildren()
  for _, g in ipairs(browse) do
    local row = g_ui.createWidget('GuildRow', list)
    row:getChildById('dot'):setBackgroundColor(state and state.mine == g.id and '#40d040' or '#d8c070')
    row:getChildById('name'):setText(g.name)
    row:getChildById('info'):setText(('Rank %d  |  %d achievement points'):format(g.grank or 0, g.points or 0))
    row:getChildById('right'):setText(g.count .. ' members')
    row.onClick = function() selBrowse = g.id; list:focusChild(row, MouseFocusReason) end
    row.onDoubleClick = function() send({a = 'state', id = g.id}) end
    if selBrowse == g.id then list:focusChild(row, MouseFocusReason) end
  end
end

local function renderAll()
  if not window then return end
  renderHeader(); renderOverview(); renderMembers(); renderAchievements(); renderBuffs()
  showPage(page)
end

-- ---------------------------------------------------------------- network
local function receive(protocol, code, buffer)
  local ok, data = pcall(json.decode, buffer)
  if not ok or type(data) ~= 'table' then return end
  local k = data.kind
  if k == 'defs' then
    if data.page == 1 then pendingDefs = {} end
    pendingDefs = pendingDefs or {}
    for _, d in ipairs(data.list or {}) do pendingDefs[#pendingDefs + 1] = d end
    if data.page == data.pages then defs = pendingDefs; pendingDefs = nil end
  elseif k == 'buffdefs' then buffDefs = data.list or {}; caps = data.caps or {}; rankPoints = data.rankPoints or {}
  elseif k == 'state' then
    state = data; members = {}; progress = {}
    if not state.guild then renderAll() end
  elseif k == 'members' then
    if data.page == 1 then pendingMembers = {} end
    pendingMembers = pendingMembers or {}
    for _, m in ipairs(data.list or {}) do pendingMembers[#pendingMembers + 1] = m end
    if data.page == data.pages then members = pendingMembers; pendingMembers = nil end
  elseif k == 'progress' then progress = data.list or {}; renderAll()
  elseif k == 'browse' then
    if data.page == 1 then pendingBrowse = {} end
    pendingBrowse = pendingBrowse or {}
    for _, g in ipairs(data.list or {}) do pendingBrowse[#pendingBrowse + 1] = g end
    if data.page == data.pages then browse = pendingBrowse; pendingBrowse = nil; renderBrowse() end
  elseif k == 'notice' then notice(data.text or '', data.ok == 1)
  end
end

function toggle()
  if not window then return end
  if window:isVisible() then window:hide() return end
  window:show(); window:raise(); window:focus()
  send({a = 'state', defs = #defs == 0 and 1 or nil})
end
function show(tab) if window and not window:isVisible() then toggle() end; if tab then showPage(tab) end end

function init()
  window = g_ui.loadUI('guild', rootWidget)
  window:hide()
  for _, p in ipairs(PAGES) do
    ui('tab' .. p).onClick = function() showPage(p) end
  end
  ui('tabMine').onClick = function() send({a = 'state'}) end
  local cb = ui('category')
  cb:addOption('All', 'all'); cb:addOption('Mob Slayer', 'mob'); cb:addOption('Boss Slayer', 'boss'); cb:addOption('Misc', 'misc')
  cb.onOptionChange = function(w, text, data) category = data or 'all'; selAch = nil; renderAchievements() end
  ui('createButton').onClick = function() send({a = 'create', name = ui('createName'):getText()}) end
  ui('depositButton').onClick = function()
    local t = ui('depositAmount'):getText():lower():gsub('[,%s]', ''):gsub('kkk$', '000000000'):gsub('kk$', '000000'):gsub('k$', '000')
    send({a = 'deposit', amount = tonumber(t) or 0}); ui('depositAmount'):setText('')
  end
  ui('inviteButton').onClick = function() send({a = 'invite', name = ui('inviteName'):getText()}); ui('inviteName'):setText('') end
  ui('promoteButton').onClick = function() if selMember then send({a = 'promote', name = selMember}) end end
  ui('demoteButton').onClick = function() if selMember then send({a = 'demote', name = selMember}) end end
  ui('kickButton').onClick = function() if selMember then send({a = 'kick', name = selMember}) end end
  ui('leaveButton').onClick = function()
    local box
    local function yes() if box then box:destroy() end; send({a = 'leave'}) end
    local function no() if box then box:destroy() end end
    box = displayGeneralBox(tr('Leave guild'), tr('Do you really want to leave your guild?\n(A leader hands the guild over to the next member; an empty guild is disbanded.)'),
      {{text = tr('Yes'), callback = yes}, {text = tr('No'), callback = no}, anchor = AnchorHorizontalCenter}, yes, no)
  end
  ui('motdButton').onClick = function() send({a = 'motd', text = ui('motdText'):getText()}); ui('motdText'):setText('') end
  ui('searchButton').onClick = function() send({a = 'browse', q = ui('searchText'):getText()}) end
  ui('searchText').onEnter = function() send({a = 'browse', q = ui('searchText'):getText()}) end
  ui('viewButton').onClick = function() if selBrowse then page = 'Overview'; send({a = 'state', id = selBrowse}) end end
  ProtocolGame.registerExtendedOpcode(OPCODE, receive)
  if modules.client_topmenu and modules.client_topmenu.addRightGameButton then
    button = modules.client_topmenu.addRightGameButton('myotsGuild', 'Guild', '/images/topbuttons/myots_guild', toggle)
  end
  connect(g_game, {onGameEnd = function() if window then window:hide() end; state = nil; defs = {} end})
  showPage('Overview')
end

function terminate()
  pcall(ProtocolGame.unregisterExtendedOpcode, OPCODE)
  if button then button:destroy() end
  if window then window:destroy() end
  window = nil
end
