-- Task Board window (Claude, 01.10.2026). Server: 21_taskboard.lua, opcode 115.
local OPCODE=115
local window,board,shop,tab,selected,amount
local parts={}
local TABS={{'daily','Daily Tasks',2815},{'weekly','Weekly Tasks',2848},{'grizzly','Grizzly Adams',5896},{'shop','Task Shop',2472}}
local KITN_OPCODE=121
local kitn,kparts=nil,{}
local CATS={'Stat points','Potions','Runes','Stones'} -- OurTibia 02.10.2026: shaders (Cosmetics) removed from the shop

-- 11.10.2026: keep the window inside small game windows (default 1020x644)
local function fitToScreen(w, fullW, fullH)
  if not w then return end
  local root = rootWidget or g_ui.getRootWidget()
  local rw, rh = root:getWidth(), root:getHeight()
  w:setWidth(math.min(fullW, rw - 10))
  w:setHeight(math.min(fullH, rh - 10))
  local pos = w:getPosition()
  w:setPosition({x = math.max(0, math.min(pos.x, rw - w:getWidth())), y = math.max(0, math.min(pos.y, rh - w:getHeight()))})
end

local function send(text) if g_game.isOnline() then g_game.getProtocolGame():sendExtendedOpcode(OPCODE,text) end end
local function ui(id) return window:recursiveGetChildById(id) end
local function money(n) n=math.floor(tonumber(n) or 0);local s=tostring(n):reverse():gsub('(%d%d%d)','%1,'):reverse();return (s:gsub('^,','')) end
local function short(n) n=tonumber(n) or 0;if n>=1000000 then return string.format('%.1fM',n/1000000) elseif n>=10000 then return string.format('%dk',math.floor(n/1000)) end;return money(n) end
local function title(s) return (tostring(s):gsub('(%a)([%w\']*)',function(a,b) return a:upper()..b end)) end
local function duration(s) s=math.max(0,math.floor(tonumber(s) or 0));local d=math.floor(s/86400);local h=math.floor(s%86400/3600);local m=math.floor(s%3600/60);if d>0 then return d..'d '..h..'h' end;return h..'h '..m..'m' end

-- 07.10.2026: the window asks again (every 2 s, up to 4 times) until the server answers,
-- so a lost answer no longer leaves an empty board.
local waiting,retryEvent=nil,nil
local function request(kind)
  waiting=kind
  if retryEvent then removeEvent(retryEvent);retryEvent=nil end
  local tries=0
  local function go()
    retryEvent=nil
    if not window or not window:isVisible() or waiting~=kind or not g_game.isOnline() then return end
    tries=tries+1
    if kind=='kitn' then g_game.getProtocolGame():sendExtendedOpcode(KITN_OPCODE,'state') else send(kind) end
    if tries<4 then retryEvent=scheduleEvent(go,2000)
    else ui('status'):setText('The server did not answer. Close the window and open it again.') end
  end
  ui('status'):setText('Loading...')
  go()
end
local function answered(kind)
  if waiting==kind then waiting=nil;if retryEvent then removeEvent(retryEvent);retryEvent=nil end;ui('status'):setText('') end
end

local function setTab(name)
  tab=name
  for _,b in ipairs(ui('tabs'):getChildren()) do b:setOn(b.tabName==name) end
  ui('boardPanel'):setVisible(name~='shop' and name~='grizzly');ui('shopPanel'):setVisible(name=='shop');ui('grizzlyPanel'):setVisible(name=='grizzly')
  if name=='grizzly' then request('kitn') elseif name=='shop' then request('shop') else request('state') end
end

-- 15.10.2026 (Tobeto): rewards as icon + number (tooltips explain)
local function rewardCell(parent,x,y,kind,value,color,tip)
  local cell=g_ui.createWidget('UIWidget',parent);cell:setSize({width=94,height=16});cell:setPhantom(false)
  cell:addAnchor(AnchorTop,'parent',AnchorTop);cell:addAnchor(AnchorLeft,'parent',AnchorLeft);cell:setMarginTop(y);cell:setMarginLeft(x)
  local icon
  if kind=='exp' then icon=g_ui.createWidget('UIWidget',cell);icon:setImageSource('/images/myots/store/boost-experience');icon:setImageSmooth(true)
  elseif kind=='boss' then icon=g_ui.createWidget('UIWidget',cell);icon:setImageSource('/game_myotstasks/boss_icon')
  else
    icon=g_ui.createWidget('UIItem',cell);icon:setVirtual(true)
    local ids={gold=3031,tokens=22721,points=22516,present=2856,boss=3114}
    icon:setItemId(ids[kind] or 3031)
    if kind=='gold' then pcall(function() icon:setShowCount(false) end);icon:setItemCount(100) end
  end
  icon:setPhantom(true);icon:setSize({width=16,height=16})
  icon:addAnchor(AnchorLeft,'parent',AnchorLeft);icon:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter)
  local l=g_ui.createWidget('Label',cell);l:setPhantom(true);l:setText(value);l:setColor(color);l:setTextAutoResize(true)
  l:addAnchor(AnchorLeft,'parent',AnchorLeft);l:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter);l:setMarginLeft(20)
  cell:setTooltip(tip)
  return cell
end
function ourRewards(r,t,tall)
  r:destroyChildren()
  r:setHeight(tall and 90 or 60)
  local gap=tall and 26 or 18
  local y0=tall and 8 or 4
  rewardCell(r,6,y0,'exp',money(t.exp),'#f0f0f0','Experience')
  rewardCell(r,104,y0,'gold',money(t.gold),'#f0d060','Gold (paid to your bank)')
  rewardCell(r,6,y0+gap,'tokens',money(t.tokens),'#9fd0ff','Loyalty tokens (Task Shop, Loyalty store)')
  rewardCell(r,104,y0+gap,'points',money(t.points),'#ffd35a','Task points (Task Shop)')
  local rolls=tonumber(t.rolls) or 0
  if rolls>0 then rewardCell(r,6,y0+gap*2,'present','x'..rolls,'#ffb050',rolls..' reward'..(rolls>1 and 's' or '')..' (Kill Tracker style): platinum / crystal coins,\nmagical stone fragments or forge stones - better for stronger monsters.') end
  if t.boss then rewardCell(r,104,y0+gap*2,'boss','Boss entry','#ff9a7a',title(t.boss)) end -- 17.10.2026 (Tobeto): only the boss name
end

local function renderBoard()
  if not board or tab=='shop' then return end
  pcall(g_tooltip.hide)
  local daily=tab=='daily'
  local list=daily and board.daily or board.weekly
  local cards=ui('cards');cards:destroyChildren()
  for _,t in ipairs(list or {}) do
    local c=g_ui.createWidget('TaskCard',cards)
    if (tonumber(t.status) or -1)<0 then c:hide()
    else
      local o=t.outfit or {}
      -- 10.10.2026: the same cropped creature pictures as the wiki
      if (tonumber(o.type) or 0)>0 then OurTibiaArt.creature(c:getChildById('creature'),{type=o.type,head=o.head,body=o.body,legs=o.legs,feet=o.feet,addons=o.addons},t.name) end
      c:getChildById('name'):setText(t.display or title(t.name))
      local k=tonumber(t.status)==2 and (tonumber(t.need) or 0) or (tonumber(t.kills) or 0) -- 16.10.2026: a finished task shows full kills
      c:getChildById('kills'):setText(money(k)..' / '..money(t.need))
      c:getChildById('bar'):setPercent(math.floor(math.min(1,k/math.max(1,tonumber(t.need) or 1))*100))
      -- 16.10.2026 (Tobeto): the reward box keeps its normal size on weekly too
      ourRewards(c:getChildById('rewards'),t,false)
      local action=c:getChildById('action');local cancel=c:getChildById('cancel')
      local status=tonumber(t.status)
      local tag=c:getChildById('header')
      -- 15.10.2026 (Tobeto): no NEW / ACTIVE tags - the yellow frame shows an active task
      tag:hide()
      if status==2 then
        action:setText('Completed');action:setEnabled(false);c:setBorderColor('#3fbf3f')
      elseif status==1 then
        action:setText('In Progress...');action:setEnabled(false);c:setBorderColor('#c8a040');c:setBackgroundColor('#2a2618')
        if daily then cancel:show();cancel:setText('Pause');action:setMarginRight(68)
          cancel:setTooltip('Pause the task: the kills are kept, accept it again later to continue.')
          cancel.onClick=function() send('pause:'..t.slot) end end
      elseif status==3 then
        action:setText('Resume Task ('..money(t.kills)..' / '..money(t.need)..')')
        action:setEnabled((board.active or 0)+(board.done or 0)<3)
        action.onClick=function() send('accept:'..t.slot) end
        c:setBorderColor('#6a5a30')
      else
        action:setText('Accept Task')
        action:setEnabled((board.active or 0)+(board.done or 0)<3)
        action.onClick=function() send('accept:'..t.slot) end
      end
      -- 13.10.2026 (Tobeto): weekly tasks are always running - no accept button;
      -- 15.10.2026: the reward field uses the free space
      -- 16.10.2026 (Tobeto): weekly shows a wide "In progress" bar like the daily board
      if not daily then
        cancel:hide();action:setMarginRight(6);action:show();action:setEnabled(false)
        if status==2 then action:setText('Completed')
        else action:setText('In Progress...');c:setBorderColor('#c8a040');c:setBackgroundColor('#2a2618') end
      end
    end
  end
  ui('unlock'):setVisible((tonumber(board.rows) or 2)<3)
  if daily then
    ui('active'):show();ui('reroll'):show();ui('rerollPremium'):show()
    ui('active'):setText('Active '..(board.active or 0)..'/3')
    ui('done'):setText('Completed today '..(board.done or 0)..'/3')
    ui('reset'):setText('Daily reset in '..duration(board.dailyLeft))
    local g=tonumber(board.rerollGold) or 0
    ui('reroll'):setText(g==0 and 'Reroll (free)' or ('Reroll ('..short(g)..' gp)'))
    local pp=tonumber(board.rerollPremium) or 0
    ui('rerollPremium'):setVisible(pp>0);ui('rerollPremium'):setText('Reroll ('..pp..' pp)')
  else
    local completed=0;for _,t in ipairs(board.weekly or {}) do if tonumber(t.status)==2 then completed=completed+1 end end
    ui('active'):hide();ui('reroll'):hide();ui('rerollPremium'):hide()
    ui('done'):setText('Completed '..completed..'/'..(#(board.weekly or {})))
    ui('reset'):setText('Weekly reset in '..duration(board.weeklyLeft))
  end
end
local function renderFooter(data)
  if data.gold then ui('footGold'):setText(money(data.gold)..' gp') end
  if data.tokens then ui('footTokens'):setText(money(data.tokens)..' tokens') end
  if data.points then ui('footPoints'):setText(money(data.points)..' task points') end
  if board then ui('bossButton'):setText('Boss Access ('..#(board.bosses or {})..')');ui('bossButton'):setEnabled(#(board.bosses or {})>0) end
  if data.message and data.message~='' then ui('status'):setText(data.message) end
end

local function itemFor(o) return shop and shop.items and (function() for _,i in ipairs(shop.items) do if i.id==o then return i end end end)() end
local function price(o,n)
  if o.id=='stat' then
    local cost=0;local b=tonumber(o.bought) or 0
    for i=0,n-1 do local k=b+i;cost=cost+(k<10 and 20 or k<20 and 25 or k<30 and 30 or k<40 and 35 or 40) end
    return cost
  end
  return (tonumber(o.price) or 0)*n
end
local function renderDetail()
  local o=selected and itemFor(selected);if not o then return end
  ui('dName'):setText(o.cat=='Stat points' and 'Stat point' or o.cat)
  ui('dItem'):hide();ui('dCreature'):hide();ui('dIcon'):hide()
  if o.cid then ui('dItem'):setItemId(o.cid);ui('dItem'):show()
  elseif o.shader then ui('dCreature'):setOutfit({type=128,head=78,body=106,legs=58,feet=76});ui('dCreature'):show();local c=ui('dCreature'):getCreature();if c then pcall(function() c:setShader(o.shader) end) end
  else ui('dIcon'):setImageSource('/images/myots/store/statpoint');ui('dIcon'):show() end
  ui('dBought'):setText(o.id=='stat' and ('Bought '..o.bought..' / '..o.max) or o.name)
  ui('dDesc'):setText(o.desc or '')
  if o.id=='stat' and shop.stats then
    local lines={'Price per point'}
    for _,t in ipairs(shop.stats.tiers or {}) do lines[#lines+1]=string.format('%d - %d   %d pts',t[1],t[2],t[3]) end
    ui('dTiers'):setText(table.concat(lines,'\n'))
  else ui('dTiers'):setText(o.owned and 'You already own this shader.' or '') end
  local single=o.shader~=nil
  for _,id in ipairs({'minus','plus','max','amount','amountLabel'}) do ui(id):setVisible(not single) end
  if single then amount=1 end
  ui('amount'):setText(tostring(amount))
  local cost=price(o,amount)
  ui('dPrice'):setText('Price  '..money(cost)..' task points')
  local have=tonumber(shop.points) or 0
  ui('dMsg'):setText(have<cost and ('You need '..(cost-have)..' more task points.') or '')
  ui('buy'):setEnabled(have>=cost and not o.owned and not (o.id=='stat' and o.bought>=o.max))
end
local function renderShop()
  if not shop then return end
  local list=ui('shopList');list:destroyChildren()
  for _,cat in ipairs(CATS) do
    local header=g_ui.createWidget('Label',list);header:setText(cat);header:setColor('#d8d8d8');header:setHeight(18)
    local grid=g_ui.createWidget('UIWidget',list)
    local layout=UIGridLayout.create(grid);layout:setCellSize({width=92,height=92});layout:setCellSpacing(4);layout:setNumColumns(4);layout:setFlow(true);grid:setLayout(layout)
    local n=0
    for _,o in ipairs(shop.items or {}) do if o.cat==cat then
      n=n+1
      local t=g_ui.createWidget('ShopTile',grid)
      t:getChildById('name'):setText(o.name)
      t:getChildById('item'):hide();t:getChildById('creature'):hide();t:getChildById('icon'):hide()
      if o.cid then t:getChildById('item'):setItemId(o.cid);t:getChildById('item'):setItemCount(o.count or 1);t:getChildById('item'):show()
      elseif o.shader then local cw=t:getChildById('creature');cw:setOutfit({type=128,head=78,body=106,legs=58,feet=76});cw:show();local c=cw:getCreature();if c then pcall(function() c:setShader(o.shader) end) end
      else t:getChildById('icon'):setImageSource('/images/myots/store/statpoint');t:getChildById('icon'):show() end
      t:getChildById('price'):setText(o.owned and 'Owned' or (money(o.id=='stat' and price(o,1) or o.price)..' pts'))
      t:setOn(selected==o.id)
      t:setTooltip(o.desc or o.name)
      t.onClick=function() selected=o.id;amount=1;renderShop() end
    end end
    grid:setHeight(math.ceil(n/4)*96)
  end
  -- 13.10.2026 (Tobeto): the points are shown once (in the bottom bar), not twice
  ui('shopPoints'):setText('');ui('shopPoints'):hide()
  if shop.points then ui('footPoints'):setText(money(shop.points)..' task points') end
  if not selected then selected='stat';amount=1 end
  renderDetail()
end

function changeAmount(d)
  local o=selected and itemFor(selected);if not o then return end
  local maxN=o.id=='stat' and math.max(1,o.max-o.bought) or 100
  if d>=1000 then
    local have=tonumber(shop.points) or 0;local n=1
    while n<maxN and price(o,n+1)<=have do n=n+1 end
    amount=n
  else amount=math.max(1,math.min(maxN,(amount or 1)+d)) end
  renderDetail()
end
function buy() if selected then send('buy:'..selected..':'..(amount or 1)) end end
function history() send('history') end
function reroll(kind) send('reroll:'..kind) end
local unlockBox
function unlock()
  -- 12.10.2026 (Tobeto): ask before spending premium points on the third row
  if unlockBox then return end
  local function close() if unlockBox then unlockBox:destroy();unlockBox=nil end end
  unlockBox=displayGeneralBox(tr('Unlock third task row'),tr('Unlock a third row of daily and weekly tasks for 100 premium points?'),
    {{text=tr('Yes'),callback=function() close();send('unlock') end},{text=tr('No'),callback=close},anchor=AnchorHorizontalCenter},
    function() close();send('unlock') end,close)
end
function closePopup() ui('popup'):hide();ui('popupShade'):hide() end
-- 17.10.2026 (Tobeto): the pop-up works like the Game Store transfer window - it blocks the
-- board behind it, is dragged by its title bar and stays inside the Task Board
local function popupDrag()
  local box,bar=ui('popup'),ui('popupTitle')
  if bar.ourDrag then return end
  bar.ourDrag=true;bar:setDraggable(true);bar:setPhantom(false)
  bar.onDragEnter=function(self,mousePos) box:breakAnchors();self.ourRef={x=mousePos.x-box:getX(),y=mousePos.y-box:getY()};return true end
  bar.onDragMove=function(self,mousePos)
    if not self.ourRef then return true end
    local r=window:getRect()
    local x=math.max(r.x+2,math.min(mousePos.x-self.ourRef.x,r.x+r.width-box:getWidth()-2))
    local y=math.max(r.y+20,math.min(mousePos.y-self.ourRef.y,r.y+r.height-box:getHeight()-2))
    box:setPosition({x=x,y=y});return true
  end
  bar.onDragLeave=function(self) self.ourRef=nil;return true end
end
local function openPopup(height)
  popupDrag()
  local box=ui('popup')
  box:breakAnchors();box:addAnchor(AnchorHorizontalCenter,'parent',AnchorHorizontalCenter);box:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter)
  if height then box:setHeight(height) end
  pcall(g_tooltip.hide)
  ui('popupShade'):show();ui('popupShade'):raise();box:show();box:raise();box:focus()
end
local function popup(titleText,rows)
  ui('popupTitle'):setText(titleText)
  local list=ui('popupList');list:destroyChildren()
  for _,r in ipairs(rows) do
    local w=g_ui.createWidget('UIWidget',list);w:setHeight(24)
    local l=g_ui.createWidget('Label',w);l:setText(r.text);l:addAnchor(AnchorLeft,'parent',AnchorLeft);l:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter);l:setTextAutoResize(true);l:setColor('#e0e0e0')
    if r.button then
      local b=g_ui.createWidget('Button',w);b:setText(r.button);b:setWidth(70);b:addAnchor(AnchorRight,'parent',AnchorRight);b:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter);b.onClick=r.onClick
    end
  end
  if #rows==0 then local l=g_ui.createWidget('Label',list);l:setText('Nothing here yet.') end
  openPopup(330)
end
-- 17.10.2026 (Tobeto): "Boss Access" - one row per boss you can fight: picture, name,
-- where it is (click: wiki map) and Enter; the window is as tall as the list
function bossList()
  local bosses=board and board.bosses or {}
  if #bosses==0 then return end
  ui('popupTitle'):setText('Boss Access')
  local list=ui('popupList');list:destroyChildren()
  local wiki=modules.game_myotswiki
  for _,b in ipairs(bosses) do
    local row=g_ui.createWidget('UIWidget',list);row:setHeight(40);row:setBackgroundColor('#262626');row:setBorderWidth(1);row:setBorderColor('#3c3c3c')
    local info=wiki and wiki.findCreature and wiki.findCreature(b.name)
    local art=g_ui.createWidget('UICreature',row);art:setId('art');art:setSize({width=34,height=34});art:setPhantom(true)
    art:addAnchor(AnchorLeft,'parent',AnchorLeft);art:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter);art:setMarginLeft(4)
    if info then pcall(OurTibiaArt.creature,art,info.outfit or info.look,info.name) end
    local name=g_ui.createWidget('Label',row);name:setText(title(b.name)..'  ('..b.entries..' entr'..(b.entries==1 and 'y' or 'ies')..')')
    name:setFont('verdana-11px-rounded');name:setColor('#ffd35a');name:setTextAutoResize(true)
    name:addAnchor(AnchorTop,'parent',AnchorTop);name:addAnchor(AnchorLeft,'art',AnchorRight);name:setMarginTop(5);name:setMarginLeft(8)
    local spot=info and type(info.spawns)=='table' and info.spawns[1] or (info and info.x and info) or nil
    local loc=g_ui.createWidget('Label',row);loc:setTextAutoResize(true)
    loc:addAnchor(AnchorTop,'prev',AnchorBottom);loc:addAnchor(AnchorLeft,'art',AnchorRight);loc:setMarginTop(3);loc:setMarginLeft(8)
    if spot and spot.x then
      loc:setText(string.format('Location: %d, %d, %d (wiki map)',spot.x,spot.y,spot.z));loc:setColor('#8fb8ff');loc:setPhantom(false)
      loc:setTooltip('Click: show it on the wiki map')
      loc.onClick=function() if wiki and wiki.showMapAt then wiki.showMapAt({name=b.name,x=spot.x,y=spot.y,z=spot.z}) end end
    else loc:setText('Location: unknown');loc:setColor('#8a8a8a') end
    local enter=g_ui.createWidget('Button',row);enter:setText('Enter');enter:setWidth(64)
    enter:addAnchor(AnchorRight,'parent',AnchorRight);enter:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter);enter:setMarginRight(6)
    enter.onClick=function() closePopup();send('boss:'..b.i) end
  end
  openPopup(math.min(420,20+12+#bosses*43+42))
end

local function receive(protocol,opcode,buffer)
  local i,total,piece=buffer:match('^(%d+)/(%d+)|(.*)$')
  if not i then return end
  i,total=tonumber(i),tonumber(total);if i==1 then parts={} end;parts[i]=piece;if i<total then return end
  local ok,data=pcall(json.decode,table.concat(parts));parts={}
  if not ok or type(data)~='table' then return end
  if data.kind=='board' then answered('state');board=data;renderBoard();renderFooter(data)
  elseif data.kind=='shop' then answered('shop');shop=data;renderShop();renderFooter(data)
  elseif data.kind=='history' then
    local rows={};for _,h in ipairs(data.rows or {}) do rows[#rows+1]={text=os.date('%d.%m %H:%M',h.time)..'  '..h.amount..'x '..h.product..'  -'..h.price..' pts'} end
    popup('Task Shop history',rows)
  end
end

-- Grizzly Adams (Killing in the Name of), 07.10.2026: tasks complete by themselves and open a boss portal.
local RANKS={[0]='none','Member','Huntsman','Ranger','Big Game Hunter','Trophy Hunter','Elite Hunter'}
local function kitnSend(t) if g_game.isOnline() then g_game.getProtocolGame():sendExtendedOpcode(KITN_OPCODE,t) end end
-- 15.10.2026 (Tobeto): every task is always running; finished ones are claimed here and
-- start again. Pinned tasks stay on top (remembered per character).
local ITEM_CID={[10305]=9388,[7393]=7393}
local function kitnPins()
  local key='ourKitnPins_'..tostring(g_game.getCharacterName())
  local list=g_settings.getList(key) or {}
  local set={};for _,v in ipairs(list) do set[tonumber(v)]=true end
  return set,key
end
local function kitnTogglePin(id)
  local set,key=kitnPins()
  set[id]=not set[id] or nil
  local out={};for k in pairs(set) do out[#out+1]=tostring(k) end
  g_settings.setList(key,out)
end
local PAW_ITEM=5896 -- bear paw
local RANK_AT={{10,'Huntsman'},{20,'Ranger'},{40,'Big Game Hunter'},{70,'Trophy Hunter'},{100,'Elite Hunter'}}
local function kitnReward(parent,x,y,kind,value,color,tip)
  local cell=g_ui.createWidget('UIWidget',parent);cell:setSize({width=60,height=16})
  cell:addAnchor(AnchorTop,'parent',AnchorTop);cell:addAnchor(AnchorLeft,'parent',AnchorLeft);cell:setMarginTop(y);cell:setMarginLeft(x)
  local icon
  if kind=='exp' then icon=g_ui.createWidget('UIWidget',cell);icon:setImageSource('/images/myots/store/boost-experience');icon:setImageSmooth(true)
  elseif kind=='boss' then icon=g_ui.createWidget('UIWidget',cell);icon:setImageSource('/game_myotstasks/boss_icon')
  else icon=g_ui.createWidget('UIItem',cell);icon:setVirtual(true)
    if kind=='money' then icon:setItemId(3031);pcall(function() icon:setShowCount(false) end);icon:setItemCount(100)
    elseif kind=='points' then icon:setItemId(PAW_ITEM) -- 16.10.2026: Paw and Fur points look different from task points
    elseif kind=='boss' then icon:setItemId(3114)
    else icon:setItemId(ITEM_CID[value] or value) end
  end
  icon:setPhantom(true);icon:setSize({width=16,height=16})
  icon:addAnchor(AnchorLeft,'parent',AnchorLeft);icon:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter)
  if kind~='item' and kind~='boss' then
    local l=g_ui.createWidget('Label',cell);l:setPhantom(true);l:setText(value);l:setColor(color);l:setTextAutoResize(true)
    l:addAnchor(AnchorLeft,'parent',AnchorLeft);l:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter);l:setMarginLeft(19)
  else cell:setWidth(18) end
  cell:setTooltip(tip)
  return cell
end
local function renderKitn()
  if not kitn then return end
  pcall(g_tooltip.hide)
  -- 16.10.2026 (Tobeto): rank + points shown as a centred bar
  do
    local box=ui('kitnInfoInner');box:destroyChildren()
    local pts=tonumber(kitn.points) or 0
    local nxt;for _,r in ipairs(RANK_AT) do if pts<r[1] then nxt=r;break end end
    local x=0
    local function lbl(text,color,font)
      local l=g_ui.createWidget('Label',box);l:setText(text);l:setColor(color);if font then l:setFont(font) end;l:setTextAutoResize(true)
      l:addAnchor(AnchorLeft,'parent',AnchorLeft);l:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter);l:setMarginLeft(x)
      x=x+l:getTextSize().width;return l
    end
    lbl('Rank: ','#a8a8a8');lbl(RANKS[tonumber(kitn.rank) or 0] or '-','#ffd35a','verdana-11px-rounded')
    x=x+14;local sep=g_ui.createWidget('UIWidget',box);sep:setSize({width=1,height=16});sep:setBackgroundColor('#4a4a4a')
    sep:addAnchor(AnchorLeft,'parent',AnchorLeft);sep:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter);sep:setMarginLeft(x);x=x+14
    local ic=g_ui.createWidget('UIItem',box);ic:setVirtual(true);ic:setPhantom(true);ic:setSize({width=16,height=16});ic:setItemId(PAW_ITEM)
    ic:addAnchor(AnchorLeft,'parent',AnchorLeft);ic:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter);ic:setMarginLeft(x);x=x+20
    lbl(money(pts),'#ffd35a','verdana-11px-rounded');lbl(' Paw and Fur points','#a8a8a8')
    if nxt then x=x+10;lbl('(next rank: '..nxt[2]..' at '..nxt[1]..')','#7a7a7a') end
    box:setWidth(x)
    box:setTooltip('Paw and Fur points come from Grizzly Adams tasks and count towards the\n"Killing in the Name of..." quest ranks. They are NOT Task Shop points.')
  end
  local list=ui('kitnList');list:destroyChildren()
  local pins=kitnPins()
  local order={}
  for _,t in ipairs(kitn.tasks or {}) do order[#order+1]=t end
  table.sort(order,function(a,b)
    local pa,pb=pins[a.id] and 1 or 0,pins[b.id] and 1 or 0
    if pa~=pb then return pa>pb end
    local ra,rb=a.ready and 1 or 0,b.ready and 1 or 0
    if ra~=rb then return ra>rb end
    local la,lb=a.locked and 1 or 0,b.locked and 1 or 0
    if la~=lb then return la<lb end
    return a.id<b.id end)
  for _,t in ipairs(order) do
    local r=g_ui.createWidget('KitnRow',list)
    local o=t.outfit or {}
    if (tonumber(o.type) or 0)>0 then OurTibiaArt.creature(r:getChildById('creature'),{type=o.type,head=o.head,body=o.body,legs=o.legs,feet=o.feet,addons=o.addons},(t.creatures or {})[1] or t.name) end
    -- 17.10.2026 (Tobeto): one monster name (e.g. "Sea Serpents"); every monster is in the
    -- [i] tooltip, and there is no [i] for a task with one monster
    local shown=tostring(t.name or ''):gsub('%s+second task$',''):gsub('%s+and%s+.*$',''):gsub('%s+or%s+.*$','')
    local nameLabel=r:getChildById('name');nameLabel:setText(title(shown))
    local names={};for _,c in ipairs(t.creatures or {}) do names[#names+1]='- '..title(c) end
    local cr=r:getChildById('creatures')
    local infoBox=r:getChildById('info')
    infoBox:setTooltip('Monsters that count for this task:\n'..table.concat(names,'\n')..(t.repeats and t.repeats>0 and ('\n\nCompleted '..t.repeats..' time'..(t.repeats>1 and 's' or '')) or ''))
    if #names<=1 then infoBox:setOpacity(0);infoBox:setPhantom(true) end
    -- one line: the name sits in the middle of the row (the [i] next to it)
    if nameLabel:getTextSize().width<=nameLabel:getWidth() then
      nameLabel:breakAnchors();nameLabel:addAnchor(AnchorLeft,'artBox',AnchorRight);nameLabel:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter)
      nameLabel:setMarginLeft(8);nameLabel:setMarginTop(t.locked and -18 or 0);nameLabel:setHeight(14);nameLabel:setTextAlign(AlignLeft)
      infoBox:breakAnchors();infoBox:addAnchor(AnchorLeft,'name',AnchorRight);infoBox:addAnchor(AnchorVerticalCenter,'name',AnchorVerticalCenter);infoBox:setMarginLeft(1);infoBox:setMarginTop(0)
    end
    local kills=tonumber(t.kills) or 0
    r:getChildById('kills'):setText(money(kills)..' / '..money(t.need))
    r:getChildById('bar'):setPercent(math.floor(math.min(1,kills/math.max(1,tonumber(t.need) or 1))*100))
    local rw=r:getChildById('rewards')
    -- 16.10.2026 (Tobeto): fixed columns (experience | gold | points | items + boss), no labels
    local COLX={exp=0,money=66,points=132}
    local extra=182
    for _,rv in ipairs(t.rewards or {}) do
      local tip
      if rv.k=='exp' then tip='Experience: '..money(rv.v) elseif rv.k=='money' then tip='Gold (paid to your bank): '..money(rv.v)
      elseif rv.k=='points' then tip='Paw and Fur points: '..money(rv.v)..'\n(count towards the "Killing in the Name of..." ranks, not the Task Shop)'
      elseif rv.k=='item' then tip=(rv.v==10305 and 'Holy Icon - the way into the Demon Oak quest (first completion only)' or 'Demon trophy') end
      local val=rv.k=='item' and rv.v or short(rv.v)
      local x=COLX[rv.k];if not x then x=extra;extra=extra+20 end
      kitnReward(rw,x,17,rv.k,val,rv.k=='exp' and '#f0f0f0' or rv.k=='money' and '#f0d060' or '#ffd35a',tip)
    end
    if t.boss then
      local tip=title(t.boss) -- 17.10.2026 (Tobeto): only the boss name
      local b=kitnReward(rw,extra,17,'boss',0,'#ff9a7a',tip)
      if t.bossReady then b:setBorderWidth(1);b:setBorderColor('#3fbf3f') end
    end
    local a=r:getChildById('action')
    if t.locked then
      a:setText('Locked');a:setEnabled(false);a:setTooltip(t.locked)
      -- 17.10.2026 (Tobeto): the reason in the task-name font, in a strip added to the bottom of the row
      r:setHeight(58+18)
      cr:breakAnchors();cr:addAnchor(AnchorLeft,'parent',AnchorLeft);cr:addAnchor(AnchorRight,'parent',AnchorRight);cr:addAnchor(AnchorBottom,'parent',AnchorBottom)
      cr:setMarginLeft(8);cr:setMarginRight(8);cr:setMarginBottom(4);cr:setHeight(14);cr:setWidth(0)
      cr:setFont('verdana-11px-rounded');cr:setColor('#ffd35a');cr:setTextAlign(AlignLeft)
      cr:setText(t.locked);cr:setTooltip(t.locked);cr:show()
      local strip=g_ui.createWidget('UIWidget',r);strip:setPhantom(true);strip:setHeight(1);strip:setBackgroundColor('#3c3c3c')
      strip:addAnchor(AnchorLeft,'parent',AnchorLeft);strip:addAnchor(AnchorRight,'parent',AnchorRight);strip:addAnchor(AnchorBottom,'parent',AnchorBottom);strip:setMarginBottom(20)
      for _,id in ipairs({'artBox','action'}) do local w=r:getChildById(id);if w then w:breakAnchors();w:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter);w:setMarginTop(-18);if id=='artBox' then w:addAnchor(AnchorLeft,'parent',AnchorLeft);w:setMarginLeft(20) else w:addAnchor(AnchorRight,'parent',AnchorRight);w:setMarginRight(8) end end end
    elseif t.ready then
      a:setText('Claim reward');a:setEnabled(true);a:setColor('#8fe08f');r:setBorderColor('#3fbf3f')
      a.onClick=function() kitnSend('claim:'..t.id) end
    else
      a:setText('In progress');a:setEnabled(false);r:setBorderColor('#5a4a20')
    end
    local pin=r:getChildById('pin')
    if t.locked and not pins[t.id] then
      pin:hide() -- 17.10.2026 (Tobeto): an unavailable task can not be pinned
    else
      local function paint(hovered) pin:setImageColor((pins[t.id] or hovered) and '#44d040' or '#5a5a5a') end
      paint(false)
      pin.onHoverChange=function(_,hovered) paint(hovered) end -- 17.10.2026 (Tobeto): green on hover
      pin:setTooltip(pins[t.id] and 'Unpin this task' or 'Pin this task to the top of the list')
      pin.onClick=function() kitnTogglePin(t.id);renderKitn() end
    end
  end
  if kitn.message and kitn.message~='' then ui('status'):setText(kitn.message) end
end
local function receiveKitn(protocol,opcode,buffer)
  local i,total,piece=buffer:match('^(%d+)/(%d+)|(.*)$')
  if not i then return end
  i,total=tonumber(i),tonumber(total);if i==1 then kparts={} end;kparts[i]=piece;if i<total then return end
  local ok,data=pcall(json.decode,table.concat(kparts));kparts={}
  if not ok or type(data)~='table' then return end
  if data.kind=='kitn' then answered('kitn');kitn=data;renderKitn() end
end
function show() window:show();fitToScreen(window,700,660);window:raise();window:focus();setTab(tab or 'daily') end
function hide() waiting=nil;if retryEvent then removeEvent(retryEvent);retryEvent=nil end;if window then window:hide() end end
function toggle() if window:isVisible() then hide() else show() end end
function init()
  window=g_ui.displayUI('tasks');window:hide()
  -- 17.10.2026 (Tobeto): the locked third row looks like three locked task cards
  local u=ui('unlock');u:setText('');u:setBorderWidth(0);u:setPadding(0);u:setImageSource('')
  local row=g_ui.createWidget('UIWidget',u);row:fill('parent');row:setPhantom(true)
  local lay=UIHorizontalLayout.create(row);lay:setSpacing(6);row:setLayout(lay)
  for i=1,3 do
    local c=g_ui.createWidget('UIWidget',row);c:setSize({width=212,height=166});c:setPhantom(true)
    c:setBackgroundColor('#1c1a14');c:setBorderWidth(1);c:setBorderColor('#6a5a30')
    local icon=g_ui.createWidget('UIWidget',c);icon:setSize({width=24,height=24});icon:setPhantom(true)
    icon:addAnchor(AnchorTop,'parent',AnchorTop);icon:addAnchor(AnchorHorizontalCenter,'parent',AnchorHorizontalCenter);icon:setMarginTop(34)
    icon:setImageSource('/images/store/icon-tibiacoin');icon:setImageSmooth(true);icon:setImageColor('#c8a040')
    local t=g_ui.createWidget('Label',c);t:setPhantom(true);t:setTextAlign(AlignCenter);t:setTextWrap(true)
    t:addAnchor(AnchorTop,'prev',AnchorBottom);t:addAnchor(AnchorLeft,'parent',AnchorLeft);t:addAnchor(AnchorRight,'parent',AnchorRight)
    t:setMarginTop(10);t:setMarginLeft(8);t:setMarginRight(8);t:setHeight(80)
    t:setColor('#ffd35a');t:setText(i==2 and 'Locked task slot\n\nClick to unlock the third row\n(100 premium points)' or 'Locked task slot')
  end
  u:setTooltip('Unlock a third row of tasks (daily and weekly board) - 100 premium points')
  for _,t in ipairs(TABS) do
    local b=g_ui.createWidget('TaskTab',ui('tabs'));b:setText(t[2]);b.tabName=t[1];b:setWidth(164)
    b:getChildById('icon'):setItemId(t[3])
    b.onClick=function() setTab(t[1]) end
    -- 15.10.2026 (Tobeto): icon + text centred together in the tab
    local total=32+8+b:getTextSize().width
    local left=math.max(4,math.floor((164-total)/2))
    b:getChildById('icon'):setMarginLeft(left);b:setTextOffset({x=left+40,y=0})
  end
  -- 15.10.2026 (Tobeto): icons in the gold / tokens / task points counters
  for _,f in ipairs({{'footGold',3031},{'footTokens',22721},{'footPoints',22516}}) do
    local lbl=ui(f[1]);local ic=g_ui.createWidget('UIItem',lbl);ic:setVirtual(true);ic:setPhantom(true);ic:setSize({width=16,height=16})
    ic:addAnchor(AnchorLeft,'parent',AnchorLeft);ic:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter);ic:setMarginLeft(5)
    ic:setItemId(f[2]);if f[2]==3031 then pcall(function() ic:setShowCount(false) end);ic:setItemCount(100) end
    lbl:setTextOffset({x=9,y=0})
  end
  ProtocolGame.registerExtendedOpcode(OPCODE,receive)
  ProtocolGame.registerExtendedOpcode(KITN_OPCODE,receiveKitn)
  connect(g_game,{onGameEnd=hide})
end
function terminate()
  pcall(ProtocolGame.unregisterExtendedOpcode,OPCODE)
  pcall(ProtocolGame.unregisterExtendedOpcode,KITN_OPCODE)
  disconnect(g_game,{onGameEnd=hide})
  if window then window:destroy() end
end
