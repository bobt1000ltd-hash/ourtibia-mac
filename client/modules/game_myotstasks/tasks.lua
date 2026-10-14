-- Task Board window (Claude, 01.10.2026). Server: 21_taskboard.lua, opcode 115.
local OPCODE=115
local window,board,shop,tab,selected,amount
local parts={}
local TABS={{'daily','Daily Tasks',2815},{'weekly','Weekly Tasks',2848},{'grizzly','Grizzly Adams',7397},{'shop','Task Shop',2472}}
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

local function renderBoard()
  if not board or tab=='shop' then return end
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
      c:getChildById('kills'):setText('Kills: '..money(t.kills)..' / '..money(t.need))
      c:getChildById('bar'):setPercent(math.floor(math.min(1,(tonumber(t.kills) or 0)/math.max(1,tonumber(t.need) or 1))*100))
      local r=c:getChildById('rewards')
      r:getChildById('exp'):setText(money(t.exp)..' exp')
      r:getChildById('gold'):setText(money(t.gold)..' gp')
      r:getChildById('tokens'):setText(t.tokens..' tokens')
      r:getChildById('points'):setText(t.points..' task points')
      local rw=(t.rolls or 0)>0 and ('+ '..t.rolls..' reward'..(t.rolls>1 and 's' or '')..' (coins / stones)') or ''
      r:getChildById('boss'):setText(t.boss and ('Boss entry: '..title(t.boss)..((t.rolls or 0)>0 and ('  + '..t.rolls..' reward'..(t.rolls>1 and 's' or '')) or '')) or rw)
      r:setTooltip('Reward: '..money(t.exp)..' experience, '..money(t.gold)..' gold (bank), '..t.tokens..' loyalty tokens, '..t.points..' task points'..(t.boss and (', 1 entry to '..title(t.boss)) or '')..'.\n'..((t.rolls or 0)>0 and (t.rolls..' Kill Tracker style reward'..(t.rolls>1 and 's' or '')..': platinum/crystal coins, magical stone fragments or forge stones - better for stronger monsters.') or ''))
      local action=c:getChildById('action');local cancel=c:getChildById('cancel')
      local status=tonumber(t.status)
      local tag=c:getChildById('header')
      if status==2 then
        action:setText('Completed');action:setEnabled(false);c:setBorderColor('#3fbf3f')
        tag:setText('DONE');tag:setBackgroundColor('#2e7d32')
      elseif status==1 then
        action:setText('In Progress...');action:setEnabled(false);c:setBorderColor('#c8a040');c:setBackgroundColor('#2a2618')
        tag:setText('ACTIVE');tag:setBackgroundColor('#8a6d1e')
        if daily then cancel:show();action:setMarginRight(68);cancel.onClick=function() send('cancel:'..t.slot) end end
      else
        tag:setText('NEW');tag:setBackgroundColor('#3a4a6a')
        action:setText('Accept Task')
        action:setEnabled((board.active or 0)+(board.done or 0)<3)
        action.onClick=function() send('accept:'..t.slot) end
      end
      -- 13.10.2026 (Tobeto): weekly tasks are always running - no "ACTIVE" tag and
      -- no "In Progress" button; only finished ones are marked DONE.
      if not daily then
        if status==2 then action:setText('Completed');action:setEnabled(false)
        else action:hide();tag:setText('');tag:setPadding(0);tag:setBackgroundColor('#00000000');c:setBorderColor('#3c3c3c');c:setBackgroundColor('#222222') end
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
  if board then ui('bossButton'):setText('Boss Access ('..#(board.bosses or {})..')') end
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
function closePopup() ui('popup'):hide() end
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
  ui('popup'):show();ui('popup'):raise()
end
function bossList()
  local rows={}
  for _,b in ipairs(board and board.bosses or {}) do
    rows[#rows+1]={text=title(b.name)..'  -  '..b.entries..' entr'..(b.entries==1 and 'y' or 'ies'),button='Enter',onClick=function() closePopup();send('boss:'..b.i) end}
  end
  popup('Boss Access - complete tasks on boss creatures to get entries',rows)
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
local function renderKitn()
  if not kitn then return end
  ui('kitnInfo'):setText('Kill the creatures of a task and it completes by itself: experience, gold, Paw and Fur points and - for boss tasks - the boss portal on the map opens for one fight. Active '..(kitn.active or 0)..'/'..(kitn.max or 3)..'   |   Paw and Fur points: '..(kitn.points or 0)..' ('..(RANKS[tonumber(kitn.rank) or 0] or '')..')')
  local list=ui('kitnList');list:destroyChildren()
  local order={}
  for _,t in ipairs(kitn.tasks or {}) do if t.status==1 then order[#order+1]=t end end
  for _,t in ipairs(kitn.tasks or {}) do if t.status==0 then order[#order+1]=t end end
  for _,t in ipairs(kitn.tasks or {}) do if t.status==2 then order[#order+1]=t end end
  for _,t in ipairs(order) do
    local r=g_ui.createWidget('KitnRow',list)
    local o=t.outfit or {}
    if (tonumber(o.type) or 0)>0 then OurTibiaArt.creature(r:getChildById('creature'),{type=o.type,head=o.head,body=o.body,legs=o.legs,feet=o.feet,addons=o.addons},t.name) end
    r:getChildById('name'):setText(title(t.name)..'   (level '..(t.level or 1)..'+, done '..(t.repeats or 0)..'/'..(t.maxRepeats or 3)..')')
    local kills=tonumber(t.kills) or 0
    r:getChildById('kills'):setText(t.status==1 and ('Kills: '..money(kills)..' / '..money(t.need)) or ('Kills needed: '..money(t.need)))
    r:getChildById('bar'):setPercent(t.status==1 and math.floor(math.min(1,kills/math.max(1,tonumber(t.need) or 1))*100) or 0)
    local b=''
    if t.boss then
      b='Boss: '..title(t.boss)
      if t.bossReady then b=b..' - portal OPEN' end
      if t.bossPos then b=b..'\n'..t.bossPos[1]..', '..t.bossPos[2]..', '..t.bossPos[3] end
    end
    r:getChildById('boss'):setText(b)
    local a=r:getChildById('action');local c=r:getChildById('cancel')
    if t.status==1 then
      a:setText('In progress');a:setEnabled(false);r:setBorderColor('#c8a040')
      c:show();c.onClick=function() kitnSend('cancel:'..t.id) end
    elseif t.status==2 then
      a:setText('Done');a:setEnabled(false);r:setBorderColor('#3fbf3f')
    else
      a:setText('Start task');a:setEnabled(t.canStart and true or false)
      a.onClick=function() kitnSend('start:'..t.id) end
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
  ui('unlock'):setText('Unlock a third row of tasks (daily and weekly board) - 100 premium points')
  ui('unlock'):setColor('#ffd35a')
  for _,t in ipairs(TABS) do
    local b=g_ui.createWidget('TaskTab',ui('tabs'));b:setText(t[2]);b.tabName=t[1];b:setWidth(164)
    b:getChildById('icon'):setItemId(t[3])
    b.onClick=function() setTab(t[1]) end
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
