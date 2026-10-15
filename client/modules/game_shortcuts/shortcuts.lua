local shortcutsWindow
local shortcuts
local shortcutIcons

function init()
  if not g_platform.isMobile() then return end

  shortcutsWindow = g_ui.displayUI('shortcuts')
  shortcuts = shortcutsWindow.shortcuts
  shortcutIcons = shortcuts.shortcutIcons

  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd 
  })
  
  setupShortcuts()
  setupQuickButtons()
end

function terminate()
  if not g_platform.isMobile() then return end

  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd 
  })

  shortcutsWindow:destroy()
  shortcutsWindow = nil
end

function onGameStart()
  shortcuts:show()
  chatHidden = false
end

function onGameEnd()
  shortcuts:hide()
end

function hide()
  shortcutsWindow:hide()
end

function show()
  shortcutsWindow:show()
end

function setupShortcuts()
  if not g_platform.isMobile() then return end
  for _, widget in ipairs(shortcutIcons:getChildren()) do
    widget.image:setChecked(false)
    widget.lastClicked = 0
    widget.onClick = function()
      if widget.image:isChecked() then
        widget.image:setChecked(false)
        return
      end
      resetShortcuts()
      widget.image:setChecked(true)
      widget.lastClicked = g_clock.millis()
    end
  end
end

function resetShortcuts()
  for _, widget in ipairs(shortcutIcons:getChildren()) do
    widget.image:setChecked(false)
    widget.lastClicked = 0
  end
end

function getShortcut()
  for _, widget in ipairs(shortcutIcons:getChildren()) do
    if widget.image:isChecked() then
      return widget:getId()
    end
  end
  return ""
end

function getPanel()
  return shortcuts
end

-- OurTibia (15.10.2026): TARGET attacks the next monster (same as the
-- "Attack next" hotkey), CHAT hides or shows the chat panel so the whole
-- map is visible on a small screen.
chatHidden = false

function toggleChat()
  local panel = modules.game_interface.getBottomPanel and modules.game_interface.getBottomPanel()
  if not panel then return end
  chatHidden = not chatHidden
  panel:setVisible(not chatHidden)
  -- the action bar follows the splitter: put it at the bottom while the chat is hidden
  local splitter = modules.game_interface.getRootPanel():getChildById('bottomSplitter')
  if splitter then
    if chatHidden then
      chatMargin = splitter:getMarginBottom()
      splitter:setMarginBottom(42)
    else
      splitter:setMarginBottom(math.max(chatMargin or 160, 120))
    end
  end
  local chat = shortcuts.quickIcons.chat
  chat.image:setChecked(chatHidden)
end

function setupQuickButtons()
  local quick = shortcuts.quickIcons
  quick.target.onClick = function()
    if modules.game_battle and modules.game_battle.attackNext then
      modules.game_battle.attackNext()
    end
  end
  quick.chat.onClick = toggleChat
end
