-- OurTibia automatic client update (Claude, 02.10.2026).
--
-- Runs from init.lua before the game modules are loaded, so every file can
-- still be replaced (nothing holds Tibia.spr open yet). The update feed is
-- the same signed manifest the website release uses:
--   <update-url>/manifest.json + manifest.sig (RSA-SHA256, update-public-key.xml)
--   <update-url>/files/<sha256>
-- A file is installed only when the manifest signature and the file's SHA-256
-- both match. Files in bin/ and bin_dx/ (exe, DLLs) are locked while the client
-- runs, so they are written as *.new and swapped by Ourtibia_gl.exe /
-- Ourtibia_dx.exe on the next start.
OurUpdater = {}

local STATE_FILE = 'ourupdate-state.json'
local SAFE_PATH = '^[%w_ %./%(%)@%+#%[%]%-]+$'
local RESTART_PATTERNS = { '^init%.lua$', '^modules/corelib/', '^modules/gamelib/', '^modules/modulelib/',
  '^modules/startup/', '^modules/client_styles/', '^modules/client_ourupdater/', '^modules/game_shaders/', '^bin[%w_]*/' }

local continueFn, window, watchdog
local finished = false

local function log(text) g_logger.info('[OurUpdater] ' .. text) end

local function readWork(path)
  local ok, data = pcall(g_resources.readFileContentsFromWorkDir, path)
  if ok then return data end
  return nil
end

local function finish()
  if finished then return end
  finished = true
  if watchdog then removeEvent(watchdog); watchdog = nil end
  if window then window:destroy(); window = nil end
  local fn = continueFn
  continueFn = nil
  if fn then fn() end
end

local function ui(id) return window and window:recursiveGetChildById(id) end

local function showWindow()
  if window then return end
  local ok, w = pcall(g_ui.displayUI, 'ourupdater')
  if ok and w then
    window = w
    window:show(); window:raise(); window:focus()
  end
end

local function setStatus(text, detail, percent)
  if not window then return end
  if text then ui('status'):setText(text) end
  if detail then ui('detail'):setText(detail) end
  if percent then ui('progress'):setPercent(math.max(0, math.min(100, math.floor(percent)))) end
end

local function publicModulus()
  local xml = readWork('update-public-key.xml')
  if not xml then return nil end
  local modulus = xml:match('<Modulus>%s*(.-)%s*</Modulus>')
  local exponent = xml:match('<Exponent>%s*(.-)%s*</Exponent>')
  if not modulus or exponent ~= 'AQAB' then return nil end
  local ok, bytes = pcall(base64.decode, modulus)
  if not ok or type(bytes) ~= 'string' then return nil end
  bytes = bytes:gsub('^%z+', '')
  return bytes
end

local function needsRestart(path)
  for _, pattern in ipairs(RESTART_PATTERNS) do
    if path:find(pattern) then return true end
  end
  return false
end

local function restartClient(binaryChanged)
  log('restarting after update')
  -- OurTibia (03.10.2026): always restart through the launcher. It brings the
  -- new window to the front with keyboard focus; g_app.restart() left it in
  -- the background until the player clicked it. The starter is Ourtibia.exe
  -- now (OpenGL only); older installs still have Ourtibia_gl.exe.
  for _, name in ipairs({'Ourtibia.exe', 'Ourtibia_gl.exe'}) do
    local launcher = g_resources.getWorkDir() .. '../' .. name
    if g_platform.spawnProcess(launcher, {}) then
      g_app.exit()
      return
    end
  end
  g_app.restart()
end

local function install(manifest, todo, base)
  showWindow()
  local total = 0
  for _, f in ipairs(todo) do total = total + f.size end
  local doneBytes, index = 0, 0
  local downloaded = {}

  local function writeAll()
    setStatus('Installing update...', '', 100)
    local restart, binary = false, false
    for _, f in ipairs(todo) do
      local destination = f.path
      if f.path:find('^bin[%w_]*/') then destination = f.path .. '.new'; binary = true end
      if not g_resources.writeDownloadedFileToWorkDir(downloaded[f.path], destination, false) then
        log('cannot write ' .. destination)
        -- 11.10.2026: some files may already be new; forget the cached hashes so
        -- the next start compares every file on disk and finishes the update
        pcall(g_resources.writeFileContentsToWorkDir, STATE_FILE, '{}')
        setStatus('Update failed', 'Cannot write ' .. destination .. '.\nClose other OurTibia windows and start the client again.', 100)
        scheduleEvent(finish, 4000)
        return
      end
      if needsRestart(f.path) then restart = true end
    end
    local files = {}
    -- binaries are written as *.new and swapped by the launcher; they are not
    -- cached, so a failed swap is detected (hash on disk) and retried next start
    for _, f in ipairs(manifest.files) do if not f.path:find('^bin[%w_]*/') then files[f.path] = f.sha256 end end
    g_resources.writeFileContentsToWorkDir(STATE_FILE, json.encode({ version = manifest.version, files = files }))
    for _, name in pairs(downloaded) do
      if g_resources.deleteFile then pcall(g_resources.deleteFile, '/downloads/' .. name) end
    end
    log(string.format('installed %d files (version %s)', #todo, tostring(manifest.version)))
    if restart then
      setStatus('Update installed', 'Restarting the client...', 100)
      scheduleEvent(function() restartClient(binary) end, 500)
    else
      finish()
    end
  end

  local function nextFile(retries)
    index = index + (retries == 0 and 1 or 0)
    local f = todo[index]
    if not f then return writeAll() end
    local name = 'ourupd_' .. f.sha256
    setStatus(string.format('Updating client: file %d of %d', index, #todo), f.path, total > 0 and doneBytes * 100 / total or 0)
    HTTP.download(base .. '/files/' .. f.sha256, name, function(path, checksum, err)
      if not err then
        local ok, data = pcall(g_resources.readFileContents, '/downloads/' .. name)
        if not ok or #data ~= f.size or g_crypt.sha256(data) ~= f.sha256 then
          err = 'checksum mismatch'
        end
      end
      if err then
        log('download failed ' .. f.path .. ': ' .. tostring(err))
        if retries < 3 then
          return scheduleEvent(function() nextFile(retries + 1) end, 1000)
        end
        setStatus('Update failed', 'Could not download ' .. f.path .. '.\nThe client starts with the files you have.', 0)
        return scheduleEvent(finish, 4000)
      end
      downloaded[f.path] = name
      doneBytes = doneBytes + f.size
      nextFile(0)
    end, function(progress)
      if total > 0 then setStatus(nil, nil, (doneBytes + f.size * (tonumber(progress) or 0) / 100) * 100 / total) end
    end)
  end
  nextFile(0)
end

local function check(base, manifestText, signatureText)
  local modulus = publicModulus()
  local cleanSignature = (signatureText or ''):gsub('%s', '')
  local okSig, signature = pcall(base64.decode, cleanSignature)
  if not modulus or not okSig or not OurRSA.verifySha256(signature, modulus, g_crypt.sha256(manifestText)) then
    log('manifest signature is not valid - update skipped')
    return finish()
  end
  local ok, manifest = pcall(json.decode, manifestText)
  if not ok or type(manifest) ~= 'table' or manifest.format ~= 1 or type(manifest.files) ~= 'table' then
    log('unknown manifest format - update skipped')
    return finish()
  end
  local okState, state = pcall(json.decode, readWork(STATE_FILE) or '')
  if not okState or type(state) ~= 'table' then state = {} end
  local newV, oldV = tonumber(manifest.version), tonumber(state.version)
  if newV and oldV and newV < oldV then
    log('manifest is older than the installed client - update skipped')
    return finish()
  end
  local allCached = type(state.files) == 'table'
  if allCached then
    for _, f in ipairs(manifest.files) do if state.files[tostring(f.path)] == nil then allCached = false; break end end
  end
  if state.version == manifest.version and allCached then
    log('client is up to date (' .. tostring(manifest.version) .. ')')
    return finish()
  end
  local known = type(state.files) == 'table' and state.files or nil
  local todo = {}
  -- 14.10.2026: bin/ holds the Windows programs; Linux and Android clients
  -- update only data and modules
  local osName = g_platform.getOsShortName and g_platform.getOsShortName() or ''
  local windows = osName ~= 'linux' and osName ~= 'android' and osName ~= 'macos'
  local list = {}
  for _, f in ipairs(manifest.files) do
    if windows or not tostring(f.path or ''):find('^bin[%w_]*/') then list[#list + 1] = f end
  end
  manifest.files = list
  for _, f in ipairs(manifest.files) do
    local path, sha = tostring(f.path or ''), tostring(f.sha256 or '')
    if not path:match(SAFE_PATH) or path:find('%.%.') or path:find('^/') or not sha:match('^[0-9a-f]+$') or #sha ~= 64 then
      log('unsafe path in manifest - update skipped')
      return finish()
    end
    local have = known and known[path]
    if have == nil then have = g_resources.fileSha256InWorkDir(path) end
    if have ~= sha then todo[#todo + 1] = { path = path, sha256 = sha, size = tonumber(f.size) or 0 } end
  end
  if #todo == 0 then
    local files = {}
    for _, f in ipairs(manifest.files) do files[f.path] = f.sha256 end
    g_resources.writeFileContentsToWorkDir(STATE_FILE, json.encode({ version = manifest.version, files = files }))
    log('client files verified (' .. tostring(manifest.version) .. ')')
    return finish()
  end
  if watchdog then removeEvent(watchdog); watchdog = nil end
  log(string.format('%d files to update', #todo))
  install(manifest, todo, base)
end

function OurUpdater.run(continueFunction)
  continueFn = continueFunction
  local base = (readWork('update-url.txt') or ''):gsub('%s+$', ''):gsub('^%s+', ''):gsub('/+$', '')
  -- Only the new client layout (data/ + bin/) updates itself; the old
  -- layout is updated by its PowerShell launcher.
  if not base:match('^https?://') or not base:find('/v2$') then return finish() end
  -- Never keep the player waiting for an unreachable update server.
  watchdog = scheduleEvent(function() watchdog = nil; log('update server timeout'); finish() end, 8000)
  local ok = pcall(HTTP.get, base .. '/manifest.json', function(manifestText, err)
    if finished then return end
    if err or type(manifestText) ~= 'string' or manifestText == '' then
      log('update server unavailable: ' .. tostring(err))
      return finish()
    end
    pcall(HTTP.get, base .. '/manifest.sig', function(signatureText, err2)
      if finished then return end
      if err2 or type(signatureText) ~= 'string' then
        log('update signature unavailable: ' .. tostring(err2))
        return finish()
      end
      local okCheck, problem = pcall(check, base, manifestText, signatureText)
      if not okCheck then log('update error: ' .. tostring(problem)); finish() end
    end)
  end)
  if not ok then finish() end
end
