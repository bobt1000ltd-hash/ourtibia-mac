local window
local button
local OPCODE = 100

function request(text)
  if not g_game.isOnline() then return end
  local protocol = g_game.getProtocolGame()
  if protocol then protocol:sendExtendedOpcode(OPCODE, text or 'journal') end
end

function show()
  if not g_game.isOnline() then return end
  window:show()
  window:raise()
  window:focus()
  request('journal')
end

function hide() if window then window:hide() end end

function toggle()
  if window:isVisible() then hide() else show() end
end

function submit()
  local field = window:getChildById('command')
  local text = field:getText():gsub('^!', '')
  request(text)
end

function init()
  window = g_ui.displayUI('myots')
  window:hide()
  button = modules.client_topmenu.addRightGameButton('myotsJournal', 'MyOTS journal (Ctrl+J)', '/images/topbuttons/myots_journal', toggle)
  ProtocolGame.registerExtendedOpcode(OPCODE, function(protocol, code, buffer)
    window:getChildById('journal'):setText(buffer)
  end)
  g_keyboard.bindKeyDown('Ctrl+J', toggle)
  connect(g_game, {onGameEnd = hide})
end

function terminate()
  disconnect(g_game, {onGameEnd = hide})
  g_keyboard.unbindKeyDown('Ctrl+J')
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if button then button:destroy() end
  if window then window:destroy() end
end
