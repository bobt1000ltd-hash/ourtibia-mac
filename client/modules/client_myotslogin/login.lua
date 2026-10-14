-- OurTibia start screen (Claude, 01.10.2026), modelled on the Mythibia client:
-- logo on top, Login panel on the left, Latest News on the right, today's
-- boosted creatures below, "by Bloku" in the corner and the login music.
local container, title, news, credit, siteLabel
local musicOn = false
local MUSIC = '/sounds/1098/ourtibia_login'
local NEWS_FALLBACK = 'Welcome to OurTibia!\n\nA classic Tibia 8.60 world with modern systems: item rarity and forge, weapon proficiency, talent trees, rare monsters, kill tracker, Task Board, private training and a full in-game wiki.\n\nCreate your account on ourtibia.com and join our Discord.'

local function root() return g_ui.getRootWidget() end

local function place()
  local r = root()
  local enter = r:recursiveGetChildById('enterGame')
  if enter then
    enter:setSize({width = 240, height = 292})
    enter:breakAnchors()
    enter:addAnchor(AnchorRight, 'parent', AnchorHorizontalCenter)
    enter:addAnchor(AnchorTop, 'parent', AnchorVerticalCenter)
    enter:setMarginRight(107)
    enter:setMarginTop(-170)
  end
  if news then
    news:setSize({width = 440, height = 292})
    news:breakAnchors()
    news:addAnchor(AnchorLeft, 'parent', AnchorHorizontalCenter)
    news:addAnchor(AnchorTop, 'parent', AnchorVerticalCenter)
    news:setMarginLeft(-97)
    news:setMarginTop(-170)
  end
  local boosted = r:recursiveGetChildById('myotsBoostedPanel')
  if boosted then
    boosted:breakAnchors()
    boosted:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    boosted:addAnchor(AnchorTop, 'parent', AnchorVerticalCenter)
    boosted:setMarginTop(134)
  end
end

local function setNewsText(text)
  if news then news:recursiveGetChildById('newsText'):setText(text) end
end

-- OurTibia (02.10.2026): the client fonts have no Polish letters (the news
-- came out as 'duA1/4a'). UTF-8 text is converted to plain letters here.
local utf8Map = {
  ['ą']='a',['ć']='c',['ę']='e',['ł']='l',['ń']='n',['ó']='o',['ś']='s',['ź']='z',['ż']='z',
  ['Ą']='A',['Ć']='C',['Ę']='E',['Ł']='L',['Ń']='N',['Ó']='O',['Ś']='S',['Ź']='Z',['Ż']='Z',
  ['×']='x',['–']='-',['—']='-',['’']="'",['‘']="'",['“']='"',['”']='"',['…']='...',['•']='-',['→']='->',['·']='-',
}
local function plainText(s)
  s = tostring(s or '')
  for from, to in pairs(utf8Map) do s = s:gsub(from, to) end
  -- any other multi-byte character: drop it
  s = s:gsub('[\192-\247][\128-\191]*', '')
  return s
end
local function stripHtml(s)
  s = tostring(s or '')
  s = s:gsub('<h%d[^>]*>', '\n'):gsub('</h%d>', ':\n'):gsub('<br%s*/?>', '\n'):gsub('</p>', '\n\n'):gsub('<li>', '- '):gsub('</li>', '\n'):gsub('<[^>]->', '')
  s = s:gsub('&amp;', '&'):gsub('&quot;', '"'):gsub('&#039;', "'"):gsub('&lt;', '<'):gsub('&gt;', '>'):gsub('&nbsp;', ' ')
  return (s:gsub('\n\n\n+', '\n\n'))
end

local function showNews(data)
  if type(data) ~= 'table' or type(data.news) ~= 'table' or #data.news == 0 then return false end
  local parts = {}
  for _, n in ipairs(data.news) do
    parts[#parts + 1] = plainText((n.date and (n.date .. '\n') or '') .. tostring(n.title or '') .. '\n\n' .. stripHtml(n.body))
  end
  setNewsText(table.concat(parts, '\n----------------------------------------\n\n'))
  return true
end

function refreshNews()
  local cached = g_settings.getString('ourtibiaNewsJson')
  if cached and cached ~= '' then
    local ok, d = pcall(json.decode, cached)
    if not (ok and showNews(d)) then setNewsText(NEWS_FALLBACK) end
  else
    setNewsText(NEWS_FALLBACK)
  end
  local url = Services and Services.news
  if not url or not HTTP or not HTTP.get then return end
  pcall(HTTP.get, url, function(message, err)
    if err or not message then return end
    local s = message:match('{.*}'); if not s then return end
    local ok, d = pcall(json.decode, s)
    if ok and showNews(d) then g_settings.set('ourtibiaNewsJson', s) end
  end)
end

-- Login music (option "Enable music sound" in Options -> Audio).
function startMusic()
  if musicOn or g_game.isOnline() or not g_sounds or not SoundChannels then return end
  if g_settings.getBoolean('enableMusicSound') == false and g_settings.getString('enableMusicSound') ~= '' then return end
  local ok = pcall(function()
    local channel = g_sounds.getChannel(SoundChannels.Music)
    channel:setEnabled(true)
    channel:play(MUSIC, 2.0, 0.6)
  end)
  musicOn = ok
end

function stopMusic()
  if not musicOn or not g_sounds or not SoundChannels then return end
  pcall(function() g_sounds.getChannel(SoundChannels.Music):stop(1.5) end)
  musicOn = false
end

-- OurTibia (02.10.2026): follow the audio settings live on the start screen.
-- Muting stops the sound channel by itself, so the music never came back
-- after unmuting.
local musicWatch
local function musicWanted()
  if g_sounds and g_sounds.isAudioEnabled and not g_sounds.isAudioEnabled() then return false end
  local o = modules.client_options
  if o and o.getOption and (o.getOption('enableAudio') == false or o.getOption('enableMusicSound') == false) then return false end
  return true
end
local function watchMusic()
  if g_game.isOnline() then return end
  if musicWanted() then
    if not musicOn then startMusic() end
  elseif musicOn then
    stopMusic()
  end
end

-- OurTibia (02.10.2026): once the password is accepted and the character
-- list opens, only the character list stays on screen (logo, news and the
-- boosted creatures are hidden, like in Mythibia). Cancel brings them back.
local extrasEvent
local hiddenByCharList = {}
local function syncExtras()
  if g_game.isOnline() then return end
  -- Hidden while the character list (or the message of the day / connecting
  -- box shown before it) is open, i.e. whenever the login window is hidden.
  local enter = root():recursiveGetChildById('enterGame')
  local charOpen = (CharacterList and CharacterList.isVisible and CharacterList.isVisible()) or (enter ~= nil and not enter:isVisible())
  local boosted = root():recursiveGetChildById('myotsBoostedPanel')
  for key, w in pairs({title = title, news = news, boosted = boosted}) do
    if w then
      if charOpen then
        if w:isVisible() then w:hide(); hiddenByCharList[key] = true end
      elseif hiddenByCharList[key] then
        w:show(); hiddenByCharList[key] = nil
      end
    end
  end
end

local function showScreen()
  if title then title:show() end
  if news then news:show() end
  if credit then credit:show() end
  if siteLabel then siteLabel:show() end
  if modules.client_bottommenu and modules.client_bottommenu.hide then pcall(modules.client_bottommenu.hide) end
  if modules.client_background and modules.client_background.hideVersionLabel then pcall(modules.client_background.hideVersionLabel) end
  -- Mythibia-like top bar on the start screen: only Discord + audio/options.
  local r = root()
  for _, id in ipairs({'topLeftYoutube', 'topLeftOnlinePlayers', 'topLeftDiscordStreamersLabel'}) do
    local w = r:recursiveGetChildById(id); if w then w:hide() end
  end
  local dc = r:recursiveGetChildById('discordIcon')
  if dc then dc.onClick = function() g_platform.openUrl((Services and Services.discord) or 'https://discord.gg/acXk9UZ8m') end end
  place()
  scheduleEvent(place, 300)
  hiddenByCharList = {}
  if not extrasEvent then extrasEvent = cycleEvent(syncExtras, 150) end
  scheduleEvent(startMusic, 3000)
  -- start watching only after the delayed first start (music right at startup crashed the client)
  scheduleEvent(function() if not musicWatch and not g_game.isOnline() then musicWatch = cycleEvent(watchMusic, 1000) end end, 4000)
end

local function hideScreen()
  if extrasEvent then removeEvent(extrasEvent); extrasEvent = nil end
  hiddenByCharList = {}
  if title then title:hide() end
  if news then news:hide() end
  if credit then credit:hide() end
  if siteLabel then siteLabel:hide() end
  if musicWatch then removeEvent(musicWatch); musicWatch = nil end
  stopMusic()
end

function init()
  container = g_ui.loadUI('login', root())
  title = container:getChildById('ourtibiaTitle')
  news = container:getChildById('ourtibiaNews')
  credit = container:getChildById('ourtibiaCredit')
  siteLabel = container:getChildById('ourtibiaSite')
  connect(g_game, {onGameStart = hideScreen, onGameEnd = showScreen})
  refreshNews()
  if g_game.isOnline() then hideScreen() else showScreen() end
end

function terminate()
  disconnect(g_game, {onGameStart = hideScreen, onGameEnd = showScreen})
  if musicWatch then removeEvent(musicWatch); musicWatch = nil end
  if extrasEvent then removeEvent(extrasEvent); extrasEvent = nil end
  stopMusic()
  if container then container:destroy() end
  container, title, news, credit, siteLabel = nil, nil, nil, nil, nil
end
