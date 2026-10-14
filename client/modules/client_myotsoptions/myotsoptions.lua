-- OurTibia simple Options window (Claude, 01.10.2026), laid out like the
-- Mythibia client: Game / Interface / Console / Graphics / Audio / Custom.
-- Every switch maps to an existing client option (modules.client_options), so
-- the full "Advanced options" window stays in sync.
local window, tabList, content
local current = 1
local TAB_ICONS = '/images/topbuttons/myots_options_tabs'

local function opt(key) local o = modules.client_options; return o and o.getOption and o.getOption(key) end
local function setOpt(key, v) local o = modules.client_options; if o and o.setOption then o.setOption(key, v) end end

local function wasd()
  local c = modules.game_console
  return c and c.isEnabledWASD and c.isEnabledWASD() or false
end
local function setWasd(v)
  local c = modules.game_console
  if c and c.isEnabledWASD and c.toggleChat and c.isEnabledWASD() ~= v then pcall(c.toggleChat) end
end

-- {type, label, key|getter, setter, min, max, fmt}
local TABS = {
  {name = 'Game', items = {
    {'check', 'Classic control', 'classicControl'},
    {'check', 'Smart left click (use / attack with left click)', 'smartLeftClick'},
    {'check', 'Highlight things under cursor', 'enableHighlightMouseTarget'},
    {'slider', 'Hotkey delay: %d ms', 'hotkeyDelay', nil, 0, 300},
    {'slider', 'Walk delay after turn: %d ms', 'walkTurnDelay', nil, 0, 500},
    {'slider', 'Walk delay after floor change: %d ms', 'walkStairsDelay', nil, 0, 500},
    {'slider', 'Walk delay after teleport: %d ms', 'walkTeleportDelay', nil, 0, 500},
  }},
  {name = 'Interface', items = {
    {'check', 'Display creature names', 'displayNames'},
    {'check', 'Display creature health bars', 'displayHealth'},
    {'check', 'Display player mana bar', 'displayMana'},
    {'check', 'Display text messages', 'displayText'},
    {'check', 'Show left panel', 'showLeftPanel'},
    {'check', 'Show second left panel', 'showLeftExtraPanel'},
    {'check', 'Show second right panel', 'showRightExtraPanel'},
    {'check', 'Show item expiry in containers', 'showExpiryInContainers'},
    {'check', 'Always show detailed item tooltips (Shift shows the short one)', function() return g_settings.getBoolean('ourDetailedTooltips') end, function(v) g_settings.set('ourDetailedTooltips', v) end},
    {'check', 'Fixed 15x11 game window (no stretch)', 'dontStretchShrink'},
  }},
  {name = 'Console', items = {
    {'check', 'Show spell group cooldowns', 'showSpellGroupCooldowns'},
    {'check', 'Show action bar tooltips', 'actionTooltip'},
    {'info', 'Default chat tabs: Local Chat, Server Log, NPCs and Loot open automatically when you log in.'},
    {'info', 'The size of the chat can be changed by dragging the bar between the game window and the chat.'},
  }},
  {name = 'Graphics', items = {
    {'check', 'Fullscreen', 'fullscreen'},
    {'check', 'Enable vertical synchronization', 'vsync'},
    {'check', 'Show frame rate', 'showFps'},
    {'check', 'Show connection ping', 'showPing'},
    {'check', 'Optimize FPS', 'optimizeFps'},
    {'slider', 'Game framerate limit: %d', 'backgroundFrameRate', nil, 10, 201},
  }},
  {name = 'Audio', items = {
    {'check', 'Enable audio', 'enableAudio'},
    {'check', 'Enable music sound (start screen music)', 'enableMusicSound'},
    {'slider', 'Music volume: %d', 'musicSoundVolume', nil, 0, 100},
  }},
  {name = 'Custom', items = {
    {'check', 'Item rarity frames', 'framesRarity'},
    {'info', 'More settings (hotkeys, keybinds, effects, action bars) are in the advanced options.'},
    {'button', 'Advanced options...', function() hide(); if modules.client_options then modules.client_options.show() end end},
  }},
}

local function getValue(item)
  if type(item[3]) == 'function' then return item[3]() end
  return opt(item[3])
end
local function setValue(item, v)
  if item[4] then item[4](v) elseif type(item[3]) == 'string' then setOpt(item[3], v) end
end

local function render()
  if not window then return end
  content:destroyChildren()
  for _, item in ipairs(TABS[current].items) do
    local t = item[1]
    if t == 'check' then
      local w = g_ui.createWidget('CheckBox', content)
      w:setText(item[2]); w:setHeight(18)
      w:setChecked(getValue(item) == true)
      w.onCheckChange = function(_, checked) setValue(item, checked) end
    elseif t == 'slider' then
      local l = g_ui.createWidget('Label', content); l:setHeight(16)
      local s = g_ui.createWidget('HorizontalScrollBar', content); s:setHeight(14)
      s:setMinimum(item[5]); s:setMaximum(item[6]); s:setStep(1)
      local v = tonumber(getValue(item)) or item[5]
      s:setValue(v); l:setText(string.format(item[2], v))
      s.onValueChange = function(_, value) l:setText(string.format(item[2], value)); setValue(item, value) end
    elseif t == 'info' then
      local l = g_ui.createWidget('Label', content)
      l:setText(item[2]); l:setTextWrap(true); l:setTextAutoResize(true); l:setColor('#b8b8b8')
    elseif t == 'button' then
      local b = g_ui.createWidget('Button', content)
      b:setText(item[2]); b:setHeight(22); b.onClick = item[3]
    end
  end
  for i, b in ipairs(tabList:getChildren()) do b:setOn(i == current) end
end

function selectTab(i) current = i; render() end

function show()
  if not window then return end
  render(); window:show(); window:raise(); window:focus()
end
function hide() if window then window:hide() end end
function toggle() if window and window:isVisible() then hide() else show() end end

-- OurTibia (02.10.2026): one-time switch of floor fading to 0 for players
-- with the old 500 ms setting (fading made the light flicker near holes).
local function floorFadeMigration()
  if g_settings.getBoolean('ourtibiaNoFloorFade') then return end
  local o = modules.client_options
  if o and o.setOption then
    o.setOption('floorFading', 0)
    g_settings.set('ourtibiaNoFloorFade', true)
  end
end

function init()
  connect(g_game, { onGameStart = floorFadeMigration })
  window = g_ui.displayUI('myotsoptions')
  window:hide()
  tabList = window:getChildById('tabList')
  content = window:getChildById('content')
  for i, tab in ipairs(TABS) do
    local b = g_ui.createWidget('MyotsOptionsTab', tabList)
    b:setText(tab.name)
    b:getChildById('icon'):setImageSource(TAB_ICONS)
    b:getChildById('icon'):setImageClip({x = (i - 1) * 32, y = 0, width = 32, height = 32})
    b.onClick = function() selectTab(i) end
  end
end

function terminate()
  disconnect(g_game, { onGameStart = floorFadeMigration })
  if window then window:destroy(); window = nil end
end
