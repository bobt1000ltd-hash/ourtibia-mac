-- OurTibia: Discord Rich Presence. Starts bin/OurTibiaPresence.exe once per client run
-- and keeps a small status file (character / level) that the helper sends to Discord.
local APP_ID = '1558366553668452352'         -- Application ID from discord.com/developers
local STATUS = '/discord_presence.txt'
local started = false
local startTime = os.time()
local updateEvent


local function writeStatus(details, state)
  pcall(g_resources.writeFileContents, STATUS, (details or '') .. '\n' .. (state or '') .. '\n' .. startTime .. '\n')
end

local function startHelper()
  if started or APP_ID == 'DISCORD_APP_ID' then return end
  if g_app.getOs and g_app.getOs() ~= 'windows' then return end
  started = true
  local ok, err = pcall(function()
    local file = g_resources.getWriteDir() .. STATUS:sub(2)
    local args = { APP_ID, tostring(g_platform.getProcessId()), file }
    -- helper ships in data/discord/; a second copy would just exit (one per client process)
    for _, rel in ipairs({ 'data/discord/OurTibiaPresence.exe', 'bin/OurTibiaPresence.exe' }) do
      pcall(g_platform.spawnProcess, g_resources.getWorkDir() .. rel, args)
    end
  end)
  if not ok then g_logger.warning('[discord] ' .. tostring(err)) end
end

local function update()
  local p = g_game.isOnline() and g_game.getLocalPlayer()
  if p then
    local voc = (vocationNamesByClientId and vocationNamesByClientId[p:getVocation()]) or ''
    if voc == 'No Vocation' then voc = '' end
    writeStatus(p:getName() .. ' - Level ' .. p:getLevel() .. (voc ~= '' and (' ' .. voc) or ''), 'Playing on OurTibia')
  else
    writeStatus('In menu', 'OurTibia')
  end
end

local function onLevel() scheduleEvent(update, 100) end

function init()
  writeStatus('In menu', 'OurTibia')
  startHelper()
  connect(g_game, { onGameStart = update, onGameEnd = update })
  connect(LocalPlayer, { onLevelChange = onLevel })
  updateEvent = cycleEvent(update, 60000)
  if g_game.isOnline() then update() end
end

function terminate()
  disconnect(g_game, { onGameStart = update, onGameEnd = update })
  disconnect(LocalPlayer, { onLevelChange = onLevel })
  if updateEvent then removeEvent(updateEvent) updateEvent = nil end
end
