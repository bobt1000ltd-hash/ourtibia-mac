-- Bosstiary window (11.10.2026). Server: data/scripts/myots/99d_nemesis.lua, opcode 125.
NemesisUI = NemesisUI or {}
local N = NemesisUI
local OPCODE = 125
local window, data, button
local parts = {}
local STAGES = {[0] = 'not met', 'Prowess', 'Expertise', 'Mastery'}
local CATCOLOR = {'#9fd0ff', '#c9a0ff', '#ff9a6a'}

local function ui(id) return window:recursiveGetChildById(id) end
local function send(text) if g_game.isOnline() then g_game.getProtocolGame():sendExtendedOpcode(OPCODE, text) end end

local CATS = {'Bane', 'Archfoe', 'Nemesis'}
local filter, selected = 0, nil
local tabs = {}

local function stars(panel, stage, size)
  panel:destroyChildren()
  for s = 1, 3 do
    local st = g_ui.createWidget('NemesisStar', panel)
    st:setImageSource(s <= stage and '/images/game/prey/prey_star' or '/images/game/prey/prey_nostar')
    st:setImageSize({width = size or 16, height = size or 16})
  end
end

local function art(widget, r)
  if not r.outfit then return end
  if OurTibiaArt and OurTibiaArt.creature then pcall(OurTibiaArt.creature, widget, r.outfit, r.name)
  else pcall(function() widget:setOutfit(r.outfit) end) end
end

local function info(panel, text, color)
  local l = g_ui.createWidget('NemesisInfoRow', panel)
  l:setText(text); if color then l:setColor(color) end
end

local function catData(cat) return data and data.categories and data.categories[cat] end

local function renderDetail()
  local r = selected
  local d = ui('detail')
  if not r then d:hide(); return end
  d:show()
  ui('dName'):setText(r.name)
  ui('dCat'):setText(r.catName .. ' boss  -  ' .. r.region); ui('dCat'):setColor(CATCOLOR[r.cat] or '#ffffff')
  stars(ui('dStars'), r.stage)
  ui('dStatus'):setText(r.alive == 1 and 'ALIVE now - hurry to ' .. r.region .. '!' or (r.cat == 3 and ('Appears at random in ' .. r.region .. ' - the whole world is told when it rises.') or ('Appears at random in ' .. r.region .. ' - nobody is told, go and check its place.')))
  ui('dStatus'):setColor(r.alive == 1 and '#ff6060' or '#c8c8c8')
  art(ui('dOutfit'), r)
  local p = ui('dInfo'); p:destroyChildren()
  info(p, string.format('Your kills: %d  -  stage: %s', r.kills, STAGES[r.stage] or ''), '#ffffff')
  for s = 1, 3 do
    local done = r.stage >= s
    info(p, string.format('%s %s: %d kill%s  (+%d points)', done and '[x]' or '[ ]', STAGES[s], r.stages[s], r.stages[s] == 1 and '' or 's', r.points[s]), done and '#7dff7d' or '#9a9a9a')
  end
  local c = catData(r.cat)
  if c then
    info(p, 'Rewards (5%+ damage):', '#ffd35a')
    info(p, string.format('%d loyalty tokens, %d-%d stone fragments, upgrade stones', c.tokens, c.frag[1], c.frag[2]))
    info(p, string.format('Unidentified boss item (tier %d-%d)', c.tier[1], c.tier[2]))
    info(p, string.format('Chance: Rarity Infuser %d%%, Super Rarity Infuser %g%%', c.infuser, c.super))
  end
  local map = ui('bossMap')
  if r.pos and r.pos.x then
    ui('mapTitle'):setText(string.format('Spawn area: %s  (%d, %d, %d)', r.region, r.pos.x, r.pos.y, r.pos.z))
    map:setCameraPosition({x = r.pos.x, y = r.pos.y, z = r.pos.z})
    pcall(function() map:setZoom(1) end)
    local mark = map:getChildById('nemesisMark')
    if not mark then
      mark = g_ui.createWidget('UIWidget', map); mark:setId('nemesisMark'); mark:setPhantom(true)
      mark:setSize({width = 30, height = 30}); mark:setBorderWidth(2); mark:setBorderColor('#ff4040')
      local face = g_ui.createWidget('UICreature', mark); face:setId('face'); face:setPhantom(true); face:fill('parent')
    end
    art(mark:getChildById('face'), r)
    mark:setBorderColor(CATCOLOR[r.cat] or '#ff4040')
    pcall(function() map:centerInPosition(mark, {x = r.pos.x, y = r.pos.y, z = r.pos.z}) end)
  end
end

local function renderRaids()
  -- 13.10.2026 (Tobeto): announced bosses (world boss, Gaz'haragoth, a living
  -- Nemesis boss) above "All bosses": when they come or that they are alive.
  local box = ui('raidBox'); box:destroyChildren()
  local rows = (filter == 0 and data and data.raids) or {}
  for _, r in ipairs(rows) do
    local l = g_ui.createWidget('NemesisRaidRow', box); l:setText(r.text)
    if r.alive == 1 then l:setColor('#ff6060') end
  end
  box:setHeight(#rows > 0 and (#rows * 17 + 4) or 0)
  box:setVisible(#rows > 0)
end

local function renderBonuses()
  local pts = tonumber(data and data.points) or 0
  local b = ui('bonusList'); b:destroyChildren()
  ui('bonusPopup'):setHeight(42 + #(data and data.thresholds or {}) * 25)
  for _, t in ipairs(data and data.thresholds or {}) do
    local row = g_ui.createWidget('NemesisBonus', b)
    local got = pts >= t.points
    row:getChildById('pts'):setText(t.points .. ' pts'); row:getChildById('pts'):setColor(got and '#7dff7d' or '#ffd35a')
    row:getChildById('text'):setText(t.text); row:getChildById('text'):setColor(got and '#7dff7d' or '#a0a0a0')
    if got then row:setBorderColor('#2f6b2f') end
  end
end

local function render()
  if not window or not data then return end
  local pts = tonumber(data.points) or 0
  local nextT
  for _, t in ipairs(data.thresholds or {}) do if pts < t.points then nextT = t; break end end
  ui('pointsLabel'):setText('Nemesis points: ' .. pts .. (nextT and ('   -   next bonus at ' .. nextT.points) or '   -   all bonuses unlocked'))
  for i, t in pairs(tabs) do t:setOn(i == filter) end
  local list = ui('list'); list:destroyChildren()
  local first
  for _, r in ipairs(data.bosses or {}) do
    if filter == 0 or r.cat == filter then
      local tile = g_ui.createWidget('NemesisTile', list)
      tile:getChildById('stripe'):setBackgroundColor(CATCOLOR[r.cat] or '#888888')
      tile:getChildById('name'):setText(r.name)
      tile:getChildById('alive'):setText(r.alive == 1 and 'ALIVE' or '') -- only Nemesis bosses (server)
      stars(tile:getChildById('stars'), r.stage)
      do -- 12.10.2026 (Tobeto): progress bar to the next stage, like the Kill Tracker
        local nextKills = r.stages[math.min(3, r.stage + 1)] or 1
        local prevKills = r.stage > 0 and r.stages[r.stage] or 0
        local bar = tile:getChildById('bar')
        if r.stage >= 3 then bar:setPercent(100); bar:setText(r.kills .. ' kills')
        else bar:setPercent(math.max(0, math.min(100, math.floor((r.kills - prevKills) * 100 / math.max(1, nextKills - prevKills)))))
          bar:setText(r.kills .. ' / ' .. nextKills) end
      end
      art(tile:getChildById('outfit'), r)
      tile:setTooltip(r.catName .. ' - ' .. r.region .. '\n' .. r.kills .. ' kills')
      local entry = r
      tile.onClick = function() selected = entry; render() end
      if selected and selected.name == r.name then selected = r; tile:setOn(true) end
      first = first or r
    end
  end
  if not selected or (filter ~= 0 and selected.cat ~= filter) then
    selected = first
    if selected then for _, w in ipairs(list:getChildren()) do if w:getChildById('name'):getText() == selected.name then w:setOn(true) end end end
  end
  renderDetail(); renderBonuses(); renderRaids()
end

function N.openWiki()
  local w = modules.game_myotswiki
  -- 13.10.2026 (Tobeto): the Nemesis window closes when the wiki opens
  if selected and w and w.showMonster then N.hide(); w.showMonster(selected.name) end
end

function N.toggleBonuses()
  local p = ui('bonusPopup'); p:setVisible(not p:isVisible()); if p:isVisible() then p:raise() end
end

local function buildTabs()
  local box = ui('tabs'); box:destroyChildren(); tabs = {}
  local names = {[0] = 'All bosses', 'Bane', 'Archfoe', 'Nemesis'}
  for i = 0, 3 do
    local t = g_ui.createWidget('NemesisTab', box); t:setText(names[i]); t:setWidth(i == 0 and 120 or 100)
    if i > 0 then t:setColor(CATCOLOR[i]) end
    local idx = i
    t.onClick = function() filter = idx; render() end
    tabs[i] = t
  end
end

local function receive(protocol, opcode, buffer)
  local i, total, piece = buffer:match('^(%d+)/(%d+)|(.*)$')
  if not i then return end
  i, total = tonumber(i), tonumber(total)
  if i == 1 then parts = {} end
  parts[i] = piece
  if i < total then return end
  local ok, result = pcall(json.decode, table.concat(parts)); parts = {}
  if not ok or type(result) ~= 'table' then return end
  data = result
  if result.open then
    window:show(); window:raise(); window:focus()
    local root = rootWidget or g_ui.getRootWidget()
    window:setWidth(math.min(940, root:getWidth() - 10)); window:setHeight(math.min(640, root:getHeight() - 10))
  end
  if window:isVisible() then pcall(render) end
end

function N.show() send('open') end
function N.hide() if window then window:hide() end end
function N.toggle() if window and window:isVisible() then N.hide() else N.show() end end
local function escapeClose() if window and window:isVisible() then N.hide(); return true end return false end
local function onGameEnd() N.hide(); data = nil end

function N.init()
  window = g_ui.displayUI('nemesis'); window:hide(); buildTabs()
  pcall(function() ui('bossMap'):disableAutoWalk() end)
  g_keyboard.bindKeyDown('Escape', escapeClose, window)
  ProtocolGame.registerExtendedOpcode(OPCODE, receive)
  connect(g_game, {onGameEnd = onGameEnd})
  if modules.client_topmenu and modules.client_topmenu.addRightGameButton then
    button = modules.client_topmenu.addRightGameButton('myotsNemesis', 'Nemesis Bosses (!bosstiary)', '/images/topbuttons/prey', N.toggle)
  end
end
function N.terminate()
  pcall(ProtocolGame.unregisterExtendedOpcode, OPCODE)
  if window then pcall(g_keyboard.unbindKeyDown, 'Escape', escapeClose, window) end
  disconnect(g_game, {onGameEnd = onGameEnd})
  if button then button:destroy(); button = nil end
  if window then window:destroy(); window = nil end
end
