-- CI only (android-e2e workflow): writes the game state to the log every 5 s so the test can
-- check login, entering the game, walking and the UI. Never part of a real client package.
local ticker, autologin
local function log(s) g_logger.info('[E2E] ' .. s) end

local function state()
  if not g_game.isOnline() then
    local cl = modules.client_entergame and CharacterList and CharacterList.isVisible and CharacterList.isVisible()
    return 'OFFLINE charlist=' .. tostring(cl)
  end
  local p = g_game.getLocalPlayer()
  if not p then return 'ONLINE no player' end
  local pos = p:getPosition()
  local spec = g_map.getSpectators(pos, false)
  local root = g_ui.getRootWidget()
  local vis = 0
  for _, c in ipairs(root:getChildren()) do if c:isVisible() then vis = vis + 1 end end
  return string.format('ONLINE %s pos %d,%d,%d hp %d/%d creatures %d windows %d fps %d', p:getName(), pos.x, pos.y, pos.z,
    p:getHealth(), p:getMaxHealth(), #spec, vis, g_app.getFps and g_app.getFps() or -1)
end

function init()
  connect(g_game, {
    onGameStart = function() log('GAME START') end,
    onGameEnd = function() log('GAME END') end,
    onLoginError = function(e) log('LOGIN ERROR ' .. tostring(e)) end,
    onConnectionError = function(e) log('CONNECTION ERROR ' .. tostring(e)) end,
  })
  ticker = cycleEvent(function() log(state()) end, 5000)
  -- fallback: if the touch login did not get us in after 6 minutes, log in from code
  autologin = scheduleEvent(function()
    if g_game.isOnline() then return end
    log('AUTOLOGIN fallback')
    if CharacterList and CharacterList.isVisible and CharacterList.isVisible() then
      CharacterList.doLogin(); return
    end
    local eg = g_ui.getRootWidget():recursiveGetChildById('accountNameTextEdit')
    local pw = g_ui.getRootWidget():recursiveGetChildById('accountPasswordTextEdit')
    if eg and pw then eg:setText('e2etest'); pw:setText('e2epass'); EnterGame.doLogin() end
    scheduleEvent(function() if CharacterList and CharacterList.isVisible() then CharacterList.doLogin() end end, 8000)
  end, 360000)
end

function terminate()
  if ticker then removeEvent(ticker) end
  if autologin then removeEvent(autologin) end
end
