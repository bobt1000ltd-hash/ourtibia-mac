-- OurTibia (16.10.2026): Cooking window. Server: data/scripts/myots/70_cooking.lua, opcode 130.
-- Every recipe is known; you only need the cooking level and the ingredients (no fire needed)
-- (anywhere, out of a fight - 16.10.2026). The cooking skill is also shown in Skills.
local OPCODE = 130
local window, button, state, selected
local skill = {level = 10, percent = 0}
local active = {}
local pendingDishes

local function send(data) if g_game.isOnline() then g_game.getProtocolGame():sendExtendedOpcode(OPCODE, json.encode(data)) end end
local function ui(id) return window and window:recursiveGetChildById(id) end
local function cap(s) return (tostring(s):gsub('(%a)([%w\']*)', function(a, b) return a:upper() .. b end)) end
local function setItem(w, cid, count) if cid and cid > 0 then w:setItem(Item.create(cid, count or 1)) else w:setItem(nil) end end

-- Skills window row (game_skills: skillCooking)
local function updateSkillRow()
  local sk = modules.game_skills
  local w = sk and sk.skillsWindow
  local row = w and w:recursiveGetChildById('skillCooking')
  if not row then return end
  local v = row:getChildById('value'); if v then v:setText(skill.level) end
  local p = row:getChildById('percent')
  if p then p:setPercent(skill.percent or 0); p:setTooltip((skill.percent or 0) .. '% to the next cooking level') end
end

local function dish(key) for _, d in ipairs(state and state.dishes or {}) do if d.key == key then return d end end end
local function canCook(d)
  if not d or not state or (state.level or 10) < d.lvl then return 0 end
  local n = 100
  for _, i in ipairs(d.ing) do n = math.min(n, math.floor((tonumber(i.have) or 0) / math.max(1, i.n))) end
  return math.max(0, n)
end

local function refreshDetails()
  local d = dish(selected); if not d then return end
  setItem(ui('detailIcon'), d.cid)
  ui('detailName'):setText(cap(d.name))
  ui('detailDesc'):setText(d.text or '')
  local lvlOk = (state.level or 10) >= d.lvl
  ui('detailLevel'):setText('Cooking level: ' .. d.lvl .. (lvlOk and '' or '  (yours: ' .. state.level .. ')') ..
    ((d.double or 0) > 0 and ('\nChance for an extra meal: ' .. d.double .. '%') or ''))
  ui('detailLevel'):setColor(lvlOk and '#dcdcdc' or '#ff7070')
  local qty = ui('quantity'); local can = canCook(d)
  qty:setMaximum(math.max(1, can)); if qty:getValue() > math.max(1, can) then qty:setValue(1) end
  local n = qty:getValue()
  ui('quantityValue'):setText(n)
  local box = ui('ingredients'); box:destroyChildren()
  for _, i in ipairs(d.ing) do
    local w = g_ui.createWidget('CookIngredient', box)
    setItem(w:getChildById('icon'), i.cid, i.n)
    local t = w:getChildById('text')
    t:setText(i.n * n .. 'x ' .. i.name .. ' (' .. (i.have or 0) .. ')')
    t:setColor((i.have or 0) >= i.n * n and '#c8e8c8' or '#ff8080')
  end
  ui('canLabel'):setText(lvlOk and ('You can cook: ' .. can) or 'Your cooking level is too low.')
  ui('cookButton'):setEnabled(can >= n and can > 0 and state.near)
end

local function buildList()
  local list = ui('dishes'); list:destroyChildren()
  for _, d in ipairs(state.dishes) do
    local row = g_ui.createWidget('CookRow', list)
    setItem(row:getChildById('icon'), d.cid)
    row:getChildById('name'):setText(cap(d.name))
    local can = canCook(d)
    local ok = (state.level or 10) >= d.lvl
    row:getChildById('name'):setColor(ok and (can > 0 and '#90e090' or '#e8e8e8') or '#808080')
    row:getChildById('info'):setText('Level ' .. d.lvl .. (can > 0 and ('  -  can cook ' .. can) or ''))
    row.onClick = function() selected = d.key; list:focusChild(row, MouseFocusReason); refreshDetails() end
    if (selected or (state.dishes[1] or {}).key) == d.key then selected = d.key; list:focusChild(row, MouseFocusReason) end
  end
  refreshDetails()
end

local function fmtLeft(s)
  s = math.max(0, math.floor(s or 0))
  if s >= 3600 then return math.floor(s / 3600) .. 'h ' .. math.floor(s % 3600 / 60) .. 'm' end
  if s >= 60 then return math.floor(s / 60) .. ' min' end
  return s .. ' s'
end
local function renderActive()
  if not window then return end
  local parts = {}
  for _, a in ipairs(active) do parts[#parts + 1] = cap(a.name) .. ' (' .. fmtLeft(a.left) .. ')' end
  ui('activeText'):setText(#parts > 0 and table.concat(parts, ',  ') or 'No meal effect is active. Eat a cooked meal to get its bonus (one of each kind at a time).')
end

local function render()
  if not window or not state then return end
  skill.level, skill.percent = state.level, state.percent
  ui('skillText'):setText('Cooking level ' .. state.level)
  ui('skillBar'):setPercent(state.percent or 0)
  ui('skillBar'):setTooltip((state.percent or 0) .. '% to the next level')
  ui('fireText'):setText(state.near and 'You can cook anywhere while you are out of a fight.' or 'You are in a fight - wait until the battle sign is gone to cook.')
  ui('fireText'):setColor(state.near and '#90e090' or '#e0a060')
  buildList(); renderActive(); updateSkillRow()
end

local function receive(protocol, code, buffer)
  local ok, data = pcall(json.decode, buffer)
  if not ok or type(data) ~= 'table' then return end
  if data.kind == 'skill' then
    skill.level, skill.percent = data.level, data.percent; updateSkillRow()
    if state then state.level, state.percent = data.level, data.percent; if window and window:isVisible() then ui('skillText'):setText('Cooking level ' .. data.level); ui('skillBar'):setPercent(data.percent or 0) end end
  elseif data.kind == 'dishes' then
    if data.page == 1 then pendingDishes = {} end
    pendingDishes = pendingDishes or {}
    for _, d in ipairs(data.list or {}) do pendingDishes[#pendingDishes + 1] = d end
  elseif data.kind == 'state' then state = data; state.dishes = pendingDishes or (state and state.dishes) or {}; render()
  elseif data.kind == 'active' then
    active = data.list or {}
    local t = g_clock.seconds(); for _, a in ipairs(active) do a.until_ = t + (a.left or 0) end
    renderActive()
  end
end

function toggle()
  if not window then return end
  if window:isVisible() then window:hide() return end
  window:show(); window:raise(); window:focus()
  send({a = 'state'})
end

local ticker
function init()
  window = g_ui.loadUI('cook', rootWidget)
  window:hide()
  ui('quantity').onValueChange = function() refreshDetails() end
  ui('cookButton').onClick = function() if selected then send({a = 'cook', key = selected, qty = ui('quantity'):getValue()}) end end
  ProtocolGame.registerExtendedOpcode(OPCODE, receive)
  if modules.client_topmenu and modules.client_topmenu.addRightGameButton then
    button = modules.client_topmenu.addRightGameButton('myotsCooking', 'Cooking', '/images/topbuttons/myots_cooking', toggle)
  end
  connect(g_game, {onGameEnd = function() if window then window:hide() end; state = nil end, onGameStart = function() updateSkillRow() end})
  ticker = cycleEvent(function()
    if window and window:isVisible() and #active > 0 then
      local t = g_clock.seconds()
      for _, a in ipairs(active) do a.left = (a.until_ or t) - t end
      renderActive()
    end
  end, 1000)
end

function terminate()
  pcall(ProtocolGame.unregisterExtendedOpcode, OPCODE)
  if ticker then removeEvent(ticker) end
  if button then button:destroy() end
  if window then window:destroy() end
  window = nil
end
