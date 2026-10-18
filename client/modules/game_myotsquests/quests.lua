-- Quest Log with a quest guide and a quest tracker (18.10.2026, owner: "players should know
-- where to go, what to do and what to say to finish a quest, what it gives and which spawns
-- it opens"). Server: data/scripts/myots/27_quest_guide.lua, extended opcode 133.
local OPCODE = 133
local window, tracker
local parts, trackerParts = {}, {}
local quests = {}          -- list from the server
local current              -- detail of the selected quest
local selectedId
local filter = 'all'
local tracked = {}         -- quest ids shown in the tracker (per character)
local sayIndex = 1
local refreshEvent, trackerEvent

local COLORS = {[0] = '#6f6f6f', [1] = '#ffb03a', [2] = '#3fbf3f'}
local STATUS = {[0] = 'Not started', [1] = 'In progress', [2] = 'Completed'}

local function ui(id) return window and window:recursiveGetChildById(id) end
local function send(text) if g_game.isOnline() then g_game.getProtocolGame():sendExtendedOpcode(OPCODE, text) end end

-- ---------------------------------------------------------------- settings
local function charKey() return g_game.getCharacterName() or '' end
local function loadTracked()
  tracked = {}
  local node = g_settings.getNode('myots-quests') or {}
  for _, id in ipairs(node[charKey()] or {}) do tracked[#tracked + 1] = tonumber(id) end
end
local function saveTracked()
  local node = g_settings.getNode('myots-quests') or {}
  node[charKey()] = tracked
  g_settings.setNode('myots-quests', node)
end
local function isTracked(id) for _, t in ipairs(tracked) do if t == id then return true end end return false end

-- ---------------------------------------------------------------- list
local function questMatches(q)
  if filter == 'active' and q.s ~= 1 then return false end
  if filter == 'done' and q.s ~= 2 then return false end
  if filter == 'new' and q.s ~= 0 then return false end
  local text = ui('search') and ui('search'):getText():lower() or ''
  if text ~= '' and not q.n:lower():find(text, 1, true) then return false end
  return true
end

function refreshList()
  if not window then return end
  local list = ui('list')
  list:destroyChildren()
  local sorted = {}
  for _, q in ipairs(quests) do if questMatches(q) then sorted[#sorted + 1] = q end end
  -- in progress first, then not started, then completed; inside by level, then name
  local order = {[1] = 0, [0] = 1, [2] = 2}
  table.sort(sorted, function(a, b)
    if order[a.s] ~= order[b.s] then return order[a.s] < order[b.s] end
    if (a.l or 0) ~= (b.l or 0) then return (a.l or 0) < (b.l or 0) end
    return a.n < b.n
  end)
  local active, done = 0, 0
  for _, q in ipairs(quests) do if q.s == 1 then active = active + 1 elseif q.s == 2 then done = done + 1 end end
  for _, q in ipairs(sorted) do
    local row = g_ui.createWidget('QuestRow', list)
    row.questId = q.i
    row:getChildById('name'):setText(q.n)
    row:getChildById('dot'):setBackgroundColor(COLORS[q.s] or '#6f6f6f')
    local info = (q.l and q.l > 0) and ('Level ' .. q.l .. '+') or ''
    info = info .. (info ~= '' and '  -  ' or '') .. STATUS[q.s]
    if isTracked(q.i) then info = info .. '  -  tracked' end
    row:getChildById('info'):setText(info)
    local bar = row:getChildById('progress')
    bar:setPercent(q.t > 0 and math.floor(q.d * 100 / q.t) or 0)
    bar:setTooltip(q.d .. ' / ' .. q.t .. ' missions')
    if q.s == 2 then row:getChildById('name'):setColor('#9fd89f') end
    row:setOn(q.i == selectedId)
    row.onClick = function() selectQuest(q.i) end
  end
  ui('counter'):setText(('%d quests  |  %d in progress  |  %d completed'):format(#quests, active, done))
end

function setFilter(name)
  filter = name
  for _, b in ipairs(ui('filters'):getChildren()) do b:setOn(b.filterName == name) end
  refreshList()
end

function selectQuest(id)
  selectedId = id
  for _, row in ipairs(ui('list'):getChildren()) do row:setOn(row.questId == id) end
  ui('status'):setText('Loading...')
  send('q:' .. id)
end

-- ---------------------------------------------------------------- detail
local function section(parent, text)
  local s = g_ui.createWidget('QuestSection', parent); s:setText(text); return s
end
local function textLine(parent, text, color)
  local w = g_ui.createWidget('QuestText', parent)
  -- the width is known before the text is set, so the wrap fits the panel
  w:setWidth(math.max(100, parent:getWidth() - 4))
  w:setText(text); if color then w:setColor(color) end
  return w
end
local function bullet(parent, text, color)
  return textLine(parent, '-  ' .. text, color)
end

local function npcNear(name)
  local player = g_game.getLocalPlayer(); if not player or not name then return false end
  local low = name:lower()
  for _, c in ipairs(g_map.getSpectators(player:getPosition(), false) or {}) do
    if c:getName():lower() == low then
      local a, b = c:getPosition(), player:getPosition()
      return a.z == b.z and math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) <= 4
    end
  end
  return false
end

local function sayWord(step, index)
  local word = step.say[index]
  if not word then return end
  if not npcNear(step.npc) then
    ui('status'):setText('Go to ' .. step.npc .. ' first - then the words are said for you.')
    return false
  end
  if word == 'hi' then g_game.talk('hi')
  else g_game.talkChannel(MessageModes.NpcTo, 0, word) end
  sayIndex = index + 1
  ui('status'):setText('You said "' .. word .. '".' .. (step.say[sayIndex] and ('  Next: "' .. step.say[sayIndex] .. '"') or '  That was the last word.'))
  return true
end

local function stepCard(parent, step, title)
  local card = g_ui.createWidget('QuestStepCard', parent)
  card:getChildById('title'):setText(title)
  local where = step.town and ('near ' .. step.town) or ''
  if step.x then where = where .. (where ~= '' and '  -  ' or '') .. step.x .. ', ' .. step.y .. ', ' .. step.z end
  card:getChildById('where'):setText(where ~= '' and where or 'Position unknown')
  -- NPC outfit from the wiki
  local wiki = modules.game_myotswiki
  local row = wiki and wiki.findCreature and wiki.findCreature(step.npc)
  local art = card:getChildById('npc')
  if row and OurTibiaArt and OurTibiaArt.creature then pcall(OurTibiaArt.creature, art, row.outfit or row.look, row.name) end
  local sayPanel = card:getChildById('say')
  sayIndex = 1
  for i, w in ipairs(step.say or {}) do
    local chip = g_ui.createWidget('QuestChip', sayPanel)
    chip:setText(w)
    chip:setWidth(math.max(26, chip:getTextSize().width + 12))
    chip:setTooltip('Click: say "' .. w .. '" (when you stand next to ' .. step.npc .. ')')
    chip.onClick = function() sayWord(step, i) end
  end
  local mapButton = card:getChildById('mapButton')
  mapButton:setEnabled(step.x ~= nil and wiki ~= nil)
  mapButton.onClick = function()
    if wiki and wiki.showMapAt then wiki.showMapAt({name = step.npc, x = step.x, y = step.y, z = step.z}) end
  end
  card:getChildById('talkButton').onClick = function() sayWord(step, sayIndex) end
  card:getChildById('hint'):setText('Click the words next to the NPC')
  return card
end

local function renderDetail()
  if not window or not current then return end
  local q = current
  ui('empty'):hide()
  ui('questName'):setText(q.n)
  local info = {}
  if q.l and q.l > 0 then info[#info + 1] = 'Level ' .. q.l .. '+' end
  info[#info + 1] = STATUS[q.s]
  info[#info + 1] = q.d .. ' / ' .. q.t .. ' missions'
  ui('questInfo'):setText(table.concat(info, '   |   '))
  ui('questInfo'):setColor(COLORS[q.s])
  ui('trackButton'):setText(isTracked(q.i) and 'Stop tracking' or 'Track quest')
  ui('trackButton'):setEnabled(q.s ~= 2 or isTracked(q.i))

  local d = ui('detail')
  d:destroyChildren()
  if q.summary and q.summary ~= '' then textLine(d, q.summary, '#bdbdbd') end

  -- next step
  local nx = q.next
  if q.s == 2 then
    section(d, 'Completed')
    textLine(d, 'You have finished this quest.', '#9fd89f')
  elseif nx then
    section(d, q.s == 0 and 'How to start' or 'Next step')
    if nx.mission and nx.mission ~= '' then textLine(d, nx.mission, '#ffd35a') end
    if nx.text and nx.text ~= '' and nx.text ~= q.summary then textLine(d, nx.text) end
    if nx.step then
      stepCard(d, nx.step, 'Talk to ' .. nx.step.npc)
    else
      textLine(d, 'This step is done in the world (an item, a place or a creature) - follow the mission text above.', '#9a9a9a')
    end
  end

  -- missions
  if #(q.missions or {}) > 0 then
    section(d, 'Missions')
    for _, m in ipairs(q.missions) do
      local row = g_ui.createWidget('QuestMissionRow', d)
      row:getChildById('name'):setText(m.n)
      row:getChildById('mark'):setBackgroundColor(COLORS[m.s] or '#6f6f6f')
      if m.s == 2 then row:getChildById('name'):setColor('#8fbf8f')
      elseif m.s == 1 then row:getChildById('name'):setColor('#ffd35a') end
      if m.text and m.text ~= '' then row:setTooltip(m.text) end
    end
    if (q.hidden or 0) > 0 then textLine(d, q.hidden .. ' more missions appear when you start them.', '#7f7f7f') end
  end

  -- rewards / unlocks / spawns
  if #(q.rewards or {}) > 0 then
    section(d, 'Rewards')
    for _, r in ipairs(q.rewards) do bullet(d, r, '#e8d8a8') end
  end
  if #(q.unlocks or {}) > 0 then
    section(d, 'Unlocks')
    for _, r in ipairs(q.unlocks) do bullet(d, r, '#a8d8ff') end
  end
  if #(q.spawns or {}) > 0 then
    section(d, 'Hunting grounds you get access to')
    local box = g_ui.createWidget('QuestChipGrid', d)
    box:setHeight(math.ceil(#q.spawns / 3) * 22)
    for _, name in ipairs(q.spawns) do
      local chip = g_ui.createWidget('QuestChip', box)
      chip:setText(name)
      chip:setTooltip('Open ' .. name .. ' in the wiki (spawns on the map)')
      chip.onClick = function()
        local wiki = modules.game_myotswiki
        if wiki and wiki.openLink then wiki.openLink('monsters', name) end
      end
    end
  end
  if q.s == 0 and q.start and not (nx and nx.step and nx.step.npc == q.start.npc) then
    section(d, 'Quest giver')
    stepCard(d, {npc = q.start.npc, x = q.start.x, y = q.start.y, z = q.start.z, town = q.start.town, say = {'hi', 'mission'}}, q.start.npc)
  end
  ui('status'):setText('')
end

-- ---------------------------------------------------------------- tracker
local function updateTrackerButton() end

local function renderTracker(list)
  if not tracker then return end
  local content = tracker:getChildById('contentsPanel')
  content:destroyChildren()
  if #tracked == 0 then
    local l = g_ui.createWidget('QuestText', content)
    l:setText('No quest tracked. Open the Quest Log and press "Track quest".'); l:setColor('#8f8f8f')
    return
  end
  for _, q in ipairs(list or {}) do
    local e = g_ui.createWidget('QuestTrackerEntry', content)
    e:getChildById('name'):setText(q.n .. '  (' .. q.d .. '/' .. q.t .. ')')
    local text
    if q.s == 2 then text = 'Completed!'
    elseif q.next and q.next.step then text = q.next.step.npc .. (q.next.step.town and (' (' .. q.next.step.town .. ')') or '') .. ': ' .. table.concat(q.next.step.say or {}, ' > ')
    elseif q.next then text = q.next.text or q.next.mission or ''
    else text = '' end
    e:getChildById('step'):setText(text)
    e:setTooltip((q.next and q.next.mission and (q.next.mission .. '\n') or '') .. (q.next and q.next.text or '') .. '\n\nClick: open in the Quest Log')
    e.onClick = function() show(); selectQuest(q.i) end
  end
end

function requestTracker()
  if trackerEvent then removeEvent(trackerEvent); trackerEvent = nil end
  if not g_game.isOnline() then return end
  if #tracked == 0 then renderTracker({}) return end
  local ids = {}
  for _, id in ipairs(tracked) do ids[#ids + 1] = tostring(id) end
  send('t:' .. table.concat(ids, ','))
end

function toggleTrack()
  if not current then return end
  local id = current.i
  if isTracked(id) then
    for k, t in ipairs(tracked) do if t == id then table.remove(tracked, k) break end end
  else
    if #tracked >= 5 then table.remove(tracked, 1) end
    tracked[#tracked + 1] = id
    if tracker and not tracker:isVisible() then tracker:open() end
  end
  saveTracked()
  renderDetail(); refreshList(); requestTracker()
end

local function createTracker()
  if tracker then return end
  local panel = modules.game_interface.getRightPanel()
  tracker = g_ui.createWidget('QuestTrackerWindow', panel)
  tracker:setId('myotsQuestTracker')
  tracker:setText('Quest Tracker')
  tracker:getChildById('miniwindowTitle'):setText('Quest Tracker')
  tracker:setContentMinimumHeight(40)
  for _, name in ipairs({'newWindowButton', 'contextMenuButton', 'toggleFilterButton'}) do
    local b = tracker:getChildById(name); if b then b:hide() end
  end
  tracker:setup()
end

function toggleTracker()
  if not tracker then createTracker() end
  if tracker:isVisible() then tracker:close() else tracker:open(); requestTracker() end
end

-- ---------------------------------------------------------------- protocol
local function receive(protocol, opcode, buffer)
  local i, total, piece = buffer:match('^(%d+)/(%d+)|(.*)$')
  if not i then return end
  i, total = tonumber(i), tonumber(total)
  if i == 1 then parts = {} end
  parts[i] = piece
  if i < total then return end
  local ok, data = pcall(json.decode, table.concat(parts)); parts = {}
  if not ok or type(data) ~= 'table' then return end
  if data.kind == 'list' then
    quests = data.quests or {}
    if ui('status'):getText() == 'Loading...' then ui('status'):setText('') end
    refreshList()
    if not selectedId then
      -- open the first quest in progress
      for _, q in ipairs(quests) do if q.s == 1 then selectedId = q.i break end end
      if selectedId then selectQuest(selectedId) end
    end
  elseif data.kind == 'quest' then
    if data.i == selectedId then current = data; renderDetail() end
    if isTracked(data.i) and tracker and tracker:isVisible() then requestTracker() end
  elseif data.kind == 'tracker' then
    renderTracker(data.quests)
  end
end

-- "Your questlog has been updated." -> refresh the open window and the tracker
local function onTextMessage(mode, text)
  if type(text) ~= 'string' or not text:find('questlog has been updated', 1, true) then return end
  if refreshEvent then removeEvent(refreshEvent) end
  refreshEvent = scheduleEvent(function()
    refreshEvent = nil
    if window and window:isVisible() then send('list'); if selectedId then send('q:' .. selectedId) end end
    if tracker and tracker:isVisible() then requestTracker() end
  end, 400)
end

-- ---------------------------------------------------------------- window
function show()
  if not g_game.isOnline() then return end
  window:show(); window:raise(); window:focus()
  local root = rootWidget or g_ui.getRootWidget()
  window:setWidth(math.min(820, root:getWidth() - 10)); window:setHeight(math.min(580, root:getHeight() - 10))
  ui('status'):setText('Loading...')
  send('list')
  if selectedId then send('q:' .. selectedId) end
end
function hide() if window then window:hide() end end
function toggle() if window and window:isVisible() then hide() else show() end end

-- the tracker follows the quest also without the quest log message (every 20 seconds)
local pollEvent
local function poll()
  pollEvent = scheduleEvent(poll, 20000)
  if g_game.isOnline() and tracker and tracker:isVisible() and #tracked > 0 then requestTracker() end
end

local function onGameStart()
  if not pollEvent then pollEvent = scheduleEvent(poll, 20000) end
  loadTracked()
  createTracker()
  if #tracked > 0 then
    if not tracker:isVisible() then tracker:open() end
    trackerEvent = scheduleEvent(requestTracker, 2500)
  else
    renderTracker({})
  end
end
local function onGameEnd()
  hide()
  if pollEvent then removeEvent(pollEvent); pollEvent = nil end
  selectedId, current, quests = nil, nil, {}
  if tracker then tracker:destroy(); tracker = nil end
end

function init()
  window = g_ui.displayUI('quests')
  window:hide()
  for _, f in ipairs({{'all', 'All'}, {'active', 'Active'}, {'new', 'New'}, {'done', 'Done'}}) do
    local b = g_ui.createWidget('QuestFilter', ui('filters'))
    b:setText(f[2]); b.filterName = f[1]
    b.onClick = function() setFilter(f[1]) end
  end
  setFilter('all')
  ProtocolGame.registerExtendedOpcode(OPCODE, receive)
  connect(g_game, {onGameStart = onGameStart, onGameEnd = onGameEnd, onTextMessage = onTextMessage})
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  if pollEvent then removeEvent(pollEvent); pollEvent = nil end
  pcall(ProtocolGame.unregisterExtendedOpcode, OPCODE)
  disconnect(g_game, {onGameStart = onGameStart, onGameEnd = onGameEnd, onTextMessage = onTextMessage})
  if tracker then tracker:destroy(); tracker = nil end
  if window then window:destroy(); window = nil end
end
