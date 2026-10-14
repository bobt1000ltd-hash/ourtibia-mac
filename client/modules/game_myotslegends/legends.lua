-- Hall of Legends window (08.10.2026). Server: data/scripts/myots/93_legends.lua, opcode 123.
-- Passive tree unlocked with achievement points + the list of all achievements.
local OPCODE=123
local window,data,button
local parts={}
local filter='all'
local search='' -- 09.10.2026: search field above the list (lower case)
local ATLAS='/images/myots/talents'
local CAPS='/images/myots/talents_caps'

local function send(text) if g_game.isOnline() then g_game.getProtocolGame():sendExtendedOpcode(OPCODE,text) end end
local function ui(id) return window:recursiveGetChildById(id) end
local function clip(widget,index)
  index=tonumber(index) or 0
  widget:setImageSource(ATLAS)
  widget:setImageClip({x=(index%16)*32,y=math.floor(index/16)*32,width=32,height=32})
end

local function makeNode(holder,node,unlocked,need)
  holder:destroyChildren()
  local b=g_ui.createWidget('LegendNode',holder)
  b:addAnchor(AnchorTop,'parent',AnchorTop);b:addAnchor(AnchorHorizontalCenter,'parent',AnchorHorizontalCenter)
  clip(b:getChildById('icon'),node.icon)
  b:setBorderColor(unlocked and '#f0c040' or '#3a3a3a')
  if not unlocked then b:setOpacity(0.4) end
  local l=g_ui.createWidget('Label',holder)
  l:addAnchor(AnchorTop,'prev',AnchorBottom);l:addAnchor(AnchorLeft,'parent',AnchorLeft);l:addAnchor(AnchorRight,'parent',AnchorRight)
  l:setTextAlign(AlignCenter);l:setHeight(16);l:setMarginTop(2)
  l:setText(node.name);l:setColor(unlocked and '#ffe9a0' or '#7a7a7a')
  local tip=node.name..'\n'..node.desc..'\n\n'..(unlocked and 'Unlocked.' or ('Unlocks at '..need..' achievement points.'))
  b:setTooltip(tip);l:setTooltip(tip)
end

local function renderList()
  if not window or not data then return end
  local list=ui('list');list:destroyChildren()
  local shown=0
  for _,a in ipairs(data.list or {}) do
    local ok=filter=='all' or (filter=='earned' and a.h==1) or (filter=='missing' and a.h==0)
    if ok and search~='' then
      ok=(tostring(a.n or '')):lower():find(search,1,true)~=nil or (tostring(a.d or '')):lower():find(search,1,true)~=nil
    end
    if ok then
      shown=shown+1
      local r=g_ui.createWidget('AchievementRow',list)
      r:getChildById('name'):setText((a.h==1 and '' or '')..a.n)
      r:getChildById('name'):setColor(a.h==1 and '#ffe9a0' or (a.s==1 and '#8070a0' or '#8a8a8a'))
      r:getChildById('points'):setText(tostring(a.p)..' pt')
      r:getChildById('points'):setColor(a.h==1 and '#ffd35a' or '#6a6a6a')
      r:setTooltip(a.n..(a.s==1 and '  (secret)' or '')..'\n'..(a.d or '')..(a.how and ('\n\nHow: '..a.how) or '')..'\n\n'..(a.h==1 and 'Earned.' or 'Not earned yet.'))
      r:setBackgroundColor(shown%2==0 and '#ffffff08' or '#00000000')
    end
  end
  for _,id in ipairs({'fAll','fEarned','fMissing'}) do ui(id):setOn(false) end
  ui(({all='fAll',earned='fEarned',missing='fMissing'})[filter]):setOn(true)
end

local function render()
  if not window or not data then return end
  local pts=tonumber(data.points) or 0
  ui('title'):setText('Achievements: '..tostring(data.earned or 0)..' / '..tostring(data.total or 0)..'   -   Achievement points: '..pts..' / '..tostring(data.maxPoints or 0))
  ui('pts'):setText(pts..' pts')
  local rows=ui('rows');rows:destroyChildren()
  local nextNeed
  for _,tier in ipairs(data.tiers or {}) do
    local r=g_ui.createWidget('LegendRow',rows)
    local need=r:getChildById('need');need:setText(tostring(tier.need))
    need:setColor(tier.unlocked and '#ffd35a' or '#6a6a6a')
    need:setTooltip('Needs '..tier.need..' achievement points')
    makeNode(r:getChildById('nodeA'),tier.nodes[1],tier.unlocked,tier.need)
    makeNode(r:getChildById('nodeB'),tier.nodes[2],tier.unlocked,tier.need)
    if not tier.unlocked and not nextNeed then nextNeed=tier.need end
  end
  local u=data.ultimate or {}
  local cap=ui('cap')
  cap:setImageSource(CAPS);cap:setImageClip({x=(tonumber(u.capIcon) or 0)*64,y=0,width=64,height=64})
  cap:setOpacity(u.unlocked and 1 or 0.35)
  ui('capLine'):setBackgroundColor(u.unlocked and '#e0b040' or '#403010')
  ui('capName'):setText((u.name or '')..'  ('..tostring(u.need or 900)..')')
  local tip=(u.name or '')..' - ultimate\n'..(u.desc or '')..'\n\n'..(u.unlocked and 'Unlocked.' or ('Unlocks at '..tostring(u.need)..' achievement points.'))
  cap:setTooltip(tip);ui('capName'):setTooltip(tip)
  if not nextNeed and not u.unlocked then nextNeed=u.need end
  local goal=nextNeed or u.need or 900
  ui('bar'):getChildById('fill'):setWidth(math.floor(math.min(1,pts/(tonumber(goal) or 900))*318))
  ui('bar'):setTooltip(nextNeed and (pts..' / '..nextNeed..' points to the next tier') or 'Everything unlocked!')
  local totals=data.totals or {}
  ui('bonuses'):setText(#totals>0 and table.concat(totals,'\n') or 'Nothing yet - the first tier unlocks at 100 achievement points.')
  ui('listTitle'):setText('Achievements')
  renderList()
end

function setFilter(f) filter=f;renderList() end
function setSearch(text) search=(tostring(text or '')):lower():gsub('^%s+',''):gsub('%s+$','');renderList() end
function hide() if window then window:hide() end;send('close') end
function toggle()
  if window:isVisible() then hide();return end
  -- 09.10.2026: open the window at once (it waited for the server answer and looked
  -- like a dead button when the answer did not come)
  if data then pcall(render) else
    ui('title'):setText('Hall of Legends')
    ui('bonuses'):setText(g_game.isOnline() and '' or 'Log in to see your achievements.')
  end
  window:show();window:raise();window:focus()
  send(data and 'get' or 'open')
end

local function receive(protocol,opcode,buffer)
  -- "id:i/total|data" (09.10.2026); the old "i/total|data" still works
  local id,i,total,piece=buffer:match('^(%d+):(%d+)/(%d+)|(.*)$')
  if not id then id='0';i,total,piece=buffer:match('^(%d+)/(%d+)|(.*)$') end
  if not i then return end
  i,total=tonumber(i),tonumber(total)
  if id=='0' and i==1 then parts[id]=nil end
  local msg=parts[id];if not msg then msg={n=0};parts[id]=msg end
  if not msg[i] then msg[i]=piece;msg.n=msg.n+1 end
  if msg.n<total then return end
  parts[id]=nil
  for k in pairs(parts) do if tonumber(k) and tonumber(k)<tonumber(id)-20 then parts[k]=nil end end
  local ok,result=pcall(json.decode,table.concat(msg,'',1,total))
  if not ok or type(result)~='table' or result.kind~='legends' then return end
  -- 09.10.2026: the server sends only the ids you have ("e"), the names come from achievements_data.lua
  if result.e and ACH_DATA then
    local have={}
    for id in tostring(result.e):gmatch('%d+') do have[tonumber(id)]=true end
    local list={}
    for id,a in pairs(ACH_DATA) do
      local h=have[id] and 1 or 0
      if h==1 or not a.s then
        list[#list+1]={n=a.n,p=a.p,h=h,s=a.s or 0,d=a.d,how=a.how}
      else
        -- 09.10.2026 (beta): secret achievements show their real name, marked (secret)
        list[#list+1]={n=a.n..' (secret)',p=a.p,h=0,s=1,d=a.d,how=a.how}
      end
    end
    table.sort(list,function(x,y) if x.h~=y.h then return x.h>y.h end return x.n<y.n end)
    result.list=list
  end
  -- a short update without the list keeps the list we already have
  if result.list==nil and data and data.list then result.list=data.list end
  data=result
  if button then button:setTooltip('Hall of Legends ('..tostring(data.points or 0)..' achievement points)') end
  if result.open then render();window:show();window:raise();window:focus()
  elseif window:isVisible() then render() end
end
local function onGameEnd() if window then window:hide() end;data=nil;parts={} end
-- 09.10.2026: Escape closes the window - also when the focus is in the search field
-- or back on the game screen (the window onEscape alone needs the window focused).
local function escapeClose()
  if window and window:isVisible() then hide();return true end
  return false
end
local escapeRoot
function init()
  window=g_ui.displayUI('legends');window:hide()
  g_keyboard.bindKeyDown('Escape',escapeClose,window)
  escapeRoot=modules.game_interface and modules.game_interface.getRootPanel and modules.game_interface.getRootPanel()
  if escapeRoot then g_keyboard.bindKeyDown('Escape',escapeClose,escapeRoot) end
  ProtocolGame.registerExtendedOpcode(OPCODE,receive)
  connect(g_game,{onGameEnd=onGameEnd})
  button=modules.client_topmenu.addRightGameButton('myotsLegends','Hall of Legends - achievements','/images/topbuttons/myots_legends',toggle)
  -- 11.10.2026: Bosstiary window (nemesis.lua)
  if NemesisUI and NemesisUI.init then pcall(NemesisUI.init) end
end
function terminate()
  pcall(ProtocolGame.unregisterExtendedOpcode,OPCODE)
  if window then pcall(g_keyboard.unbindKeyDown,'Escape',escapeClose,window) end
  if escapeRoot then pcall(g_keyboard.unbindKeyDown,'Escape',escapeClose,escapeRoot);escapeRoot=nil end
  disconnect(g_game,{onGameEnd=onGameEnd})
  if NemesisUI and NemesisUI.terminate then pcall(NemesisUI.terminate) end
  if button then button:destroy() end
  if window then window:destroy() end
end
