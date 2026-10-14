-- Today's boosted creatures on the start screen (Claude, 01.10.2026).
-- The game server writes update-feed/boosted.json; update-router.php serves it
-- on port 8081. The last answer is cached so the panel also works offline.
local panel,retryEvent,lastData
local DIFFICULTY={'Easy','Medium','Hard'}

local function show(data)
  if not panel or type(data)~='table' or type(data.creatures)~='table' then return end
  lastData=data
  local list=panel:getChildById('list');list:destroyChildren()
  for _,c in ipairs(data.creatures) do
    local box=g_ui.createWidget('BoostedCreatureBox',list)
    local o=type(c.outfit)=='table' and c.outfit or {}
    local lt=tonumber(o.type) or 0
    -- Only set an outfit once the .dat is loaded and has that looktype
    -- (an invalid thing type on the start screen crashes the client).
    local valid=lt>0 and g_things.isDatLoaded and g_things.isDatLoaded() and (not g_things.isValidDatId or g_things.isValidDatId(lt,ThingCategoryCreature))
    if valid then
      box:getChildById('outfit'):setOutfit({type=tonumber(o.type),head=tonumber(o.head) or 0,body=tonumber(o.body) or 0,legs=tonumber(o.legs) or 0,feet=tonumber(o.feet) or 0,addons=tonumber(o.addons) or 0})
    end
    local name=tostring(c.name or '?');name=name:gsub('^%l',string.upper)
    box:getChildById('name'):setText(name)
    box:getChildById('bonus'):setText(string.format('Exp %+d%%\nLoot +%d%%',tonumber(c.experience) or 0,tonumber(c.loot) or 0))
    box:setTooltip(string.format('%s (%s)\nExperience %+d%%\nLoot +%d%%\nDamage resistance %+d%%',name,DIFFICULTY[tonumber(c.difficulty) or 1] or '',tonumber(c.experience) or 0,tonumber(c.loot) or 0,tonumber(c.resistance) or 0))
  end
  -- OurTibia (04.10.2026): today's world boss next to the boosted creatures.
  local wb=type(data.worldBoss)=='table' and data.worldBoss or nil
  if wb and wb.name then
    local box=g_ui.createWidget('BoostedCreatureBox',list)
    local o=type(wb.outfit)=='table' and wb.outfit or {}
    local lt=tonumber(o.type) or 0
    local valid=lt>0 and g_things.isDatLoaded and g_things.isDatLoaded() and (not g_things.isValidDatId or g_things.isValidDatId(lt,ThingCategoryCreature))
    if valid then
      box:getChildById('outfit'):setOutfit({type=lt,head=tonumber(o.head) or 0,body=tonumber(o.body) or 0,legs=tonumber(o.legs) or 0,feet=tonumber(o.feet) or 0,addons=tonumber(o.addons) or 0})
    end
    box:getChildById('name'):setText(tostring(wb.name))
    box:getChildById('name'):setColor('#ff6060')
    box:getChildById('bonus'):setText('World boss\ntoday '..tostring(wb.time or '21:00'))
    local lines={'World boss of the day: '..tostring(wb.name)..' at '..tostring(wb.time or '21:00')..' (server time).',''}
    for _,e in ipairs(type(wb.schedule)=='table' and wb.schedule or {}) do lines[#lines+1]=(e.today and '> ' or '   ')..tostring(e.day)..' - '..tostring(e.name) end
    box:setTooltip(table.concat(lines,'\n'))
  end
  if not (g_things.isDatLoaded and g_things.isDatLoaded()) then
    if not retryEvent then retryEvent=scheduleEvent(function() retryEvent=nil;show(lastData) end,2000) end
  end
  panel:getChildById('title'):setText("Today's boosted creatures"..((type(data.worldBoss)=='table' and data.worldBoss.name) and ' and world boss' or '')..(data.date and (' ('..data.date..')') or ''))
  if not g_game.isOnline() then panel:show() end
end

local function host()
  local h=g_settings.get('host')
  if not h or h=='' then
    for key in pairs(Servers_init or {}) do h=key;break end
  end
  return h
end

function refresh()
  -- Cached as a JSON string: g_settings nodes turn arrays into string keys.
  local cached=g_settings.getString('myotsBoostedJson')
  if cached and cached~='' then local ok,d=pcall(json.decode,cached);if ok then show(d) end end
  local h=host();if not h or h=='' or not HTTP or not HTTP.get then return end
  local ok=pcall(HTTP.get,'http://'..h..':8081/boosted.json',function(message,err)
    if err or not message then return end
    local s=message:match('{.*}');if not s then return end
    local okDecode,data=pcall(json.decode,s)
    if okDecode and type(data)=='table' then g_settings.set('myotsBoostedJson',s);show(data) end
  end)
  if not ok then return end
end

local function onGameStart() if panel then panel:hide() end end
local function onGameEnd() if panel then panel:show();refresh() end end

function init()
  panel=g_ui.loadUI('boosted',rootWidget)
  panel:hide()
  -- The stock bottom-menu boosted slot needs a canary webservice; ours replaces it.
  local w=rootWidget:recursiveGetChildById('boostedWindow');if w then w:hide() end
  connect(g_game,{onGameStart=onGameStart,onGameEnd=onGameEnd})
  if not g_game.isOnline() then refresh() end
  -- Preload the 10.98 assets on the start screen (as Redemption does for its
  -- own boosted panel) so the creature outfits can be drawn.
  scheduleEvent(function()
    if not g_game.isOnline() and g_game.getClientVersion()==0 then
      pcall(function() g_game.setClientVersion(1098);g_game.setProtocolVersion(g_game.getClientProtocolVersion(1098)) end)
    end
  end,300)
end

function terminate()
  if retryEvent then removeEvent(retryEvent);retryEvent=nil end
  disconnect(g_game,{onGameStart=onGameStart,onGameEnd=onGameEnd})
  if panel then panel:destroy();panel=nil end
end
