-- OurTibia (16.10.2026): phone interface. Only active on mobile (Android).
-- * The top row of ~40 tiny buttons is replaced by a small bar (Menu, Chat, Zoom) and a big
--   Menu grid with every game window (the same buttons, large enough for a finger).
-- * The chat starts hidden (more map); the Chat button / the joystick panel button shows it.
-- * Windows larger than the phone screen are shrunk to fit and kept on screen.
-- * The game background around the map is black.
local bar, menu
local fitEvent
local buttons = {}

local function isMobile() return g_platform.isMobile() end

local function topToggles()
  local tm = modules.client_topmenu and modules.client_topmenu.getTopMenu and modules.client_topmenu.getTopMenu()
  if not tm then tm = rootWidget:recursiveGetChildById('topMenu') end
  return tm
end

-- the image of a top-menu button (icon or framed image)
local function iconOf(btn)
  if btn.iconPath and btn.iconPath ~= '' then return btn.iconPath, nil end
  local ok, icon = pcall(function() return btn:getIcon() end)
  if ok and icon and icon ~= '' then
    local clip
    pcall(function() local c = btn:getIconClip(); if c and c.width and c.width > 0 then clip = c end end)
    return icon, clip
  end
  local ok2, img = pcall(function() return btn:getImageSource() end)
  if ok2 and img and img ~= '' then
    local clip
    pcall(function() clip = btn:getImageClip() end)
    return img, clip
  end
  return nil
end

local function press(btn)
  if btn.onMouseRelease then
    local p = btn:getPosition()
    local ok = pcall(btn.onMouseRelease, btn, {x = p.x + 1, y = p.y + 1}, MouseLeftButton)
    if ok then return end
  end
  if btn.onClick then pcall(btn.onClick, btn) end
end

local SKIP = {debugInfoButton = true, otuiEditorButton = true, terminalButton = true}

function closeMenu() if menu then menu:hide() end end

function openMenu()
  if not menu then return end
  local grid = menu:recursiveGetChildById('grid')
  grid:destroyChildren()
  local list = {}
  local tm = topToggles()
  local function collect(panel)
    if not panel then return end
    for _, btn in ipairs(panel:getChildren()) do
      local id = btn:getId()
      if btn:isExplicitlyVisible() and not SKIP[id] and (btn.onMouseRelease or btn.onClick) then
        list[#list + 1] = btn
      end
    end
  end
  if tm then
    collect(tm:recursiveGetChildById('topLeftTogglesPanel'))
    collect(tm:recursiveGetChildById('rightGameButtonsPanel'))
    collect(tm:recursiveGetChildById('rightButtonsPanel'))
  end
  for _, btn in ipairs(list) do
    local cell = g_ui.createWidget('MobileMenuCell', grid)
    local img, clip = iconOf(btn)
    local icon = cell:getChildById('icon')
    if img then
      icon:setImageSource(img)
      if clip then icon:setImageClip(clip) end
    end
    local text = btn:getTooltip() or btn:getText() or btn:getId()
    text = tostring(text):gsub('%s*%b()', '')
    -- only the name: cut the hint after a newline or a dash
    text = text:gsub('\n.*$', ''):gsub('%s+[%-\226][%-\128\147\148]?.*$', '')
    if #text > 24 then text = text:sub(1, 22) .. '..' end
    cell:getChildById('label'):setText(text)
    cell.onClick = function()
      closeMenu()
      press(btn)
    end
  end
  menu:show(); menu:raise(); menu:focus()
end

local function zoom(delta)
  local opt = modules.client_options
  local cur = opt and opt.getOption and opt.getOption('hudScale') or 2
  local v = math.max(1, math.min(6, (tonumber(cur) or 2) + delta))
  if opt and opt.setOption then opt.setOption('hudScale', v) end
end

local function addBarButton(id, label, image, callback)
  local b = g_ui.createWidget('MobileBarButton', bar)
  b:setId(id)
  b:getChildById('label'):setText(label)
  if image then b:getChildById('icon'):setImageSource(image) end
  b.onClick = callback
  buttons[id] = b
  return b
end

local function chatHidden()
  return modules.game_shortcuts and modules.game_shortcuts.chatHidden
end
local function toggleChat()
  if modules.game_shortcuts and modules.game_shortcuts.toggleChat then modules.game_shortcuts.toggleChat() end
  if buttons.mobileChat then buttons.mobileChat:setOn(not chatHidden()) end
end

-- keeps every window inside the screen (phone screens are about 540 px high)
local function fitWindows()
  if not g_game.isOnline() then return end
  local rw, rh = rootWidget:getWidth(), rootWidget:getHeight()
  for _, w in ipairs(rootWidget:getChildren()) do
    if w:isVisible() and w ~= menu and w:getClassName() == 'UIWindow' then
      local changed = false
      if w:getHeight() > rh - 4 then w:setHeight(rh - 4); changed = true end
      if w:getWidth() > rw - 4 then w:setWidth(rw - 4); changed = true end
      local p = w:getPosition()
      if changed or p.y < 0 or p.x < 0 or p.y + w:getHeight() > rh or p.x + w:getWidth() > rw then
        local x = math.max(0, math.min(p.x, rw - w:getWidth()))
        local y = math.max(0, math.min(p.y, rh - w:getHeight()))
        pcall(function() w:breakAnchors() end)
        w:setPosition({x = x, y = y})
      end
    end
  end
end

-- wide phone screens: show more columns so the map fills the screen
-- (otherwise the 15x11 view leaves empty bars at the sides)
local lastDim = 0
local function fitMap()
  local m = modules.game_interface.getMapPanel and modules.game_interface.getMapPanel()
  if not m then return end
  local w, h = m:getWidth(), m:getHeight()
  if w <= 0 or h <= 0 then return end
  local cols = math.floor(11 * w / h)
  if cols % 2 == 0 then cols = cols - 1 end
  cols = math.max(15, math.min(17, cols)) -- server sends x-8..x+9 only
  if cols ~= lastDim then
    lastDim = cols
    m:setVisibleDimension({width = cols, height = 11})
  end
end

local function online()
  if not isMobile() then return end
  bar:show(); bar:raise()
  -- the tiny top row is replaced by the bar and the Menu grid
  scheduleEvent(function()
    if modules.client_topmenu and modules.client_topmenu.hide then modules.client_topmenu.hide() end
    local root = modules.game_interface.getRootPanel()
    if root then root:setBackgroundColor('#000000') end
    local left = modules.game_interface.getLeftPanel and modules.game_interface.getLeftPanel()
    if left then left:setMarginTop(44) end
    -- the chat starts hidden: more map on a phone
    if not chatHidden() then toggleChat() end
    if buttons.mobileChat then buttons.mobileChat:setOn(not chatHidden()) end
  end, 300)
  removeEvent(fitEvent)
  lastDim = 0
  fitEvent = cycleEvent(function() fitWindows(); fitMap() end, 400)
end

local function offline()
  if bar then bar:hide() end
  closeMenu()
  removeEvent(fitEvent); fitEvent = nil
end

function init()
  if not isMobile() then return end
  g_ui.importStyle('mobile')
  bar = g_ui.createWidget('UIWidget', rootWidget)
  bar:setId('mobileBar')
  bar:addAnchor(AnchorTop, 'parent', AnchorTop)
  bar:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  bar:setMarginTop(2); bar:setMarginLeft(2)
  bar:setSize({width = 210, height = 40})
  bar:setPhantom(true)
  local layout = UIHorizontalLayout.create(bar)
  layout:setSpacing(4)
  bar:setLayout(layout)
  addBarButton('mobileMenu', 'Menu', '/images/topbuttons/buttons', openMenu)
  addBarButton('mobileChat', 'Chat', '/images/game/mobile/chat', toggleChat)
  addBarButton('mobileZoomOut', 'UI -', '/images/topbuttons/zoomout', function() zoom(-0.5) end)
  addBarButton('mobileZoomIn', 'UI +', '/images/topbuttons/zoomin', function() zoom(0.5) end)
  bar:hide()

  menu = g_ui.displayUI('menu')
  menu:hide()
  menu:recursiveGetChildById('closeButton').onClick = closeMenu
  menu.onEscape = closeMenu
  menu.onMouseRelease = function(self, pos, button)
    local box = self:getChildById('box')
    if not box:containsPoint(pos) then closeMenu() end
    return true
  end

  connect(g_game, {onGameStart = online, onGameEnd = offline})
  if g_game.isOnline() then online() end
end

function terminate()
  if not isMobile() then return end
  disconnect(g_game, {onGameStart = online, onGameEnd = offline})
  removeEvent(fitEvent)
  if bar then bar:destroy() end
  if menu then menu:destroy() end
  bar, menu = nil, nil
  buttons = {}
end
