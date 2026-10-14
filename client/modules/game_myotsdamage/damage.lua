-- OurTibia (14.10.2026, owner): Damage Calculator - the damage range of every attack spell and rune
-- the character can use now and of the weapon, without and with a critical hit.
-- Server: scripts/myots/27_damage_calc.lua (opcode 127, chunked JSON).
local OPCODE = 127
local window, button, data
local parts = {}
local filter = 'all'
-- 14.10.2026 (owner): sorting
local SORTS = {'Strongest first', 'Weakest first', 'Element', 'Name (A-Z)', 'Mana cost'}
local sortMode = SORTS[1]
local function critLabel(cm) return string.format('Critical +%g%%', math.floor(((tonumber(cm) or 130) - 100) * 10 + .5) / 10) end
local function power(s) return (tonumber(s.max) or 0) * (s.ticks or 1) end
local function sorted(list)
  local out = {}
  for _, s in ipairs(list or {}) do out[#out + 1] = s end
  table.sort(out, function(a, b)
    local pa, pb = power(a), power(b)
    if sortMode == 'Weakest first' then if pa ~= pb then return pa < pb end
    elseif sortMode == 'Element' then
      local ea, eb = a.heal and 'zz' or tostring(a.type), b.heal and 'zz' or tostring(b.type)
      if ea ~= eb then return ea < eb end
      if pa ~= pb then return pa > pb end
    elseif sortMode == 'Name (A-Z)' then return tostring(a.name) < tostring(b.name)
    elseif sortMode == 'Mana cost' then
      local ma, mb = tonumber(a.mana) or 0, tonumber(b.mana) or 0
      if ma ~= mb then return ma < mb end
    elseif pa ~= pb then return pa > pb end
    return tostring(a.name) < tostring(b.name)
  end)
  return out
end
local TABS = {{'all', 'All'}, {'instant', 'Spells'}, {'rune', 'Runes'}}
-- 14.10.2026 (owner): attack and healing spells / runes in one list, the name coloured by element
local function matches(s, f)
  return f == 'all' or s.kind == f
end
local ELEMENT_COLORS = {
  physical = '#d6d6d6', fire = '#ff8a3d', ice = '#8fdcff', energy = '#c792ff', earth = '#7fdc6f',
  holy = '#ffe680', death = '#b9a0ff', lifedrain = '#ff6b8b', manadrain = '#7fa8ff', drown = '#6fd8d8',
  healing = '#7dff8a',
}

local function ui(id) return window:recursiveGetChildById(id) end
local function money(n)
  n = math.floor(tonumber(n) or 0)
  local s = tostring(n):reverse():gsub('(%d%d%d)', '%1,'):reverse()
  return (s:gsub('^,', ''))
end
local function title(s) return (tostring(s or ''):gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end)) end
local function send(text)
  if g_game.isOnline() then
    local p = g_game.getProtocolGame()
    if p then p:sendExtendedOpcode(OPCODE, text) end
  end
end

local function setRange(widget, caption, lo, hi, color)
  widget:getChildById('caption'):setText(caption)
  local v = widget:getChildById('value')
  v:setText(money(lo) .. ' - ' .. money(hi))
  v:setColor(color or '#ffffff')
end

local function stat(caption, value, color)
  local w = g_ui.createWidget('DmgStat', ui('stats'))
  w:getChildById('caption'):setText(caption)
  w:getChildById('value'):setText(value)
  if color then w:getChildById('value'):setColor(color) end
  return w
end

local function renderTabs()
  local tabs = ui('tabs'); tabs:destroyChildren()
  local sort = ui('sort')
  if sort and not sort.ourFilled then
    sort.ourFilled = true
    for _, o in ipairs(SORTS) do sort:addOption(o) end
    sort:setCurrentOption(sortMode, true)
    sort.onOptionChange = function(_, t) sortMode = t; renderList() end
  end
  for _, t in ipairs(TABS) do
    local b = g_ui.createWidget('DmgTab', tabs)
    local count = 0
    for _, s in ipairs(data and data.spells or {}) do if matches(s, t[1]) then count = count + 1 end end
    b:setText(t[2] .. ' (' .. count .. ')')
    b:setOn(filter == t[1])
    b.onClick = function() filter = t[1]; render() end
  end
end

local function renderWeapon()
  local w = data and data.weapon or {}
  local icon = ui('weaponIcon')
  if w.cid then icon:setItemId(w.cid); icon:show() else icon:hide() end
  ui('weaponName'):setText(title(w.name or 'Fist'))
  local info = w.skill or ''
  if w.attack then info = info .. '   |   Attack ' .. w.attack end
  if w.ammo then info = info .. ' (with ' .. w.ammo .. ')' end
  ui('weaponInfo'):setText(info)
  local m = w.main
  if m then
    local color = ELEMENT_COLORS[m.type] or '#ffffff'
    setRange(ui('wNormal'), 'Normal hit', m.min, m.max, color)
    setRange(ui('wCrit'), critLabel(m.cmult), m.cmin, m.cmax, '#ff6b4a')
    ui('wNormal'):show(); ui('wCrit'):show()
  else
    ui('wNormal'):hide(); ui('wCrit'):hide()
  end
  local e = w.element
  if e then
    ui('weaponElement'):setText(string.format('+ %s damage: %s - %s  (critical %s - %s)', title(e.type), money(e.min), money(e.max), money(e.cmin), money(e.cmax)))
    ui('weaponElement'):setColor(ELEMENT_COLORS[e.type] or '#9a9a9a')
  else
    local mode = w.factor == 1.2 and 'balanced' or w.factor == 2 and 'defensive' or 'offensive'
    ui('weaponElement'):setText('Fight mode: ' .. mode)
    ui('weaponElement'):setColor('#8f8f8f')
  end
end

function renderList()
  local list = ui('list'); list:destroyChildren()
  local shown = 0
  for _, s in ipairs(sorted(data and data.spells)) do
    if matches(s, filter) then
      shown = shown + 1
      local c = g_ui.createWidget('DmgCard', list)
      c:getChildById('name'):setText(s.name)
      c:getChildById('name'):setColor(ELEMENT_COLORS[s.heal and 'healing' or s.type] or '#f0f0f0')
      c:getChildById('words'):setText(s.kind == 'rune' and ('Rune' .. ((s.mana or 0) > 0 and ('  |  ' .. s.mana .. ' mana') or '')) or ('"' .. tostring(s.words or '') .. '"  |  ' .. (s.mana or 0) .. ' mana'))
      local el = c:getChildById('element')
      el:setText(title(s.type)); el:setBackgroundColor(ELEMENT_COLORS[s.type] or '#d0d0d0')
      local spellIcon, runeIcon = c:getChildById('spellIcon'), c:getChildById('runeIcon')
      spellIcon:hide(); runeIcon:hide()
      if s.kind == 'rune' and (s.cid or 0) > 0 then
        runeIcon:setItemId(s.cid); runeIcon:show()
      else
        local ok, info = pcall(function() return Spells.getSpellByWords(s.words or '') end)
        local id = ok and info and tonumber(info.clientId)
        if id then
          local okFile, file = pcall(Spells.getIconFileByProfile, 'Default')
          spellIcon:setImageSource(okFile and file or '/images/game/spells/spell-icons-32x32')
          spellIcon:setImageClip(Spells.getImageClip(id, 'Default'))
          spellIcon:show()
        end
      end
      if s.heal then
        el:setText('Healing'); el:setBackgroundColor('#5fd36f')
        if s.ticks then
          setRange(c:getChildById('normal'), 'Per tick', s.min, s.max, '#7dff8a')
          setRange(c:getChildById('crit'), 'Total (' .. s.ticks .. ' ticks)', s.min * s.ticks, s.max * s.ticks, '#bfffc6')
          c:setTooltip(string.format('%s\nHeals %s - %s every %d s, %d times (%s - %s in total).', s.name, money(s.min), money(s.max), s.tickInterval or 2, s.ticks, money(s.min * s.ticks), money(s.max * s.ticks)))
        else
          setRange(c:getChildById('normal'), 'Heals', s.min, s.max, '#7dff8a')
          c:getChildById('crit'):hide()
          c:setTooltip(string.format('%s\nHeals %s - %s (healing cannot be critical).', s.name, money(s.min), money(s.max)))
        end
      else
        setRange(c:getChildById('normal'), 'Normal', s.min, s.max, ELEMENT_COLORS[s.type])
        setRange(c:getChildById('crit'), critLabel(s.cmult), s.cmin, s.cmax, '#ff6b4a')
        c:setTooltip(string.format('%s\nNormal: %s - %s\nCritical: %s - %s (x%.3f = your critical damage for this element, %.1f%% chance)', s.name, money(s.min), money(s.max), money(s.cmin), money(s.cmax), (s.cmult or 130) / 100, s.chance or 0))
      end
      -- 14.10.2026: spells with their own mechanics (Infernal Rain, Chain Spear, Mass Healing)
      if s.note then c:setTooltip(c:getTooltip() .. '\n' .. tostring(s.note)) end
    end
  end
  if shown == 0 then
    local l = g_ui.createWidget('Label', list)
    l:setText(data and 'Nothing here you can use yet.' or 'Loading...')
    l:setColor('#8f8f8f'); l:setTextAlign(AlignCenter); l:setHeight(30)
  end
end

function render()
  if not window then return end
  local stats = ui('stats'); stats:destroyChildren()
  if data then
    local crit = data.weapon and data.weapon.main
    local voc = title(data.vocation)
    for _, prefix in ipairs({'Master ', 'Elder ', 'Royal ', 'Elite '}) do if voc:sub(1, #prefix) == prefix then voc = voc:sub(#prefix + 1) end end
    stat('Vocation', voc)
    stat('Level', money(data.level))
    stat('Magic level', money(data.mlvl))
    stat('Strength', money(data.str), '#ff9c6a')
    stat('Intelligence', money(data.int), '#8fb8ff')
    stat('Crit chance', string.format('%.1f%%', crit and crit.chance or 0), '#ff6b4a')
    -- 14.10.2026: healing bonus (Intelligence x equipment, multiplied)
    local hi, hg = tonumber(data.healInt) or 0, tonumber(data.healGear) or 0
    local h = stat('Healing', string.format('+%.1f%%', ((1 + hi) * (1 + hg) - 1) * 100), '#7dff8a')
    h:setTooltip(string.format('Healing bonus: +%.1f%%\nFrom Intelligence: +%.2f%%\nFrom equipment, talents and outfits: +%.2f%%\nBoth are multiplied: (1 + %.4f) x (1 + %.4f).\nAlready included in every healing value below.', ((1 + hi) * (1 + hg) - 1) * 100, hi * 100, hg * 100, hi, hg))
  end
  renderWeapon()
  renderTabs()
  renderList()
  ui('footer'):setText('Against a monster without resistances. Included: Strength / Intelligence, rarity element damage, Monster Slayer, healing bonus and critical damage of your items. Only spells and runes you can use now. Not included: kill tracker stars, Blood Pact.')
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
  if window and window:isVisible() then render() end
end

function request() send('get') end
function show()
  if not window then return end
  window:show(); window:raise(); window:focus()
  render(); request()
  if button then button:setOn(true) end
end
function hide()
  if window then window:hide() end
  if button then button:setOn(false) end
end
function toggle() if window and window:isVisible() then hide() else show() end end

function init()
  window = g_ui.displayUI('damage'); window:hide()
  ProtocolGame.registerExtendedOpcode(OPCODE, receive)
  if modules.client_topmenu and modules.client_topmenu.addRightGameButton then
    button = modules.client_topmenu.addRightGameButton('myotsDamage', 'Damage Calculator', '/images/topbuttons/myots_damage', toggle)
  end
  connect(g_game, {onGameEnd = hide})
end
function terminate()
  pcall(ProtocolGame.unregisterExtendedOpcode, OPCODE)
  disconnect(g_game, {onGameEnd = hide})
  if button then button:destroy(); button = nil end
  if window then window:destroy(); window = nil end
end
