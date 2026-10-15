-- MyOTS Game Store (Claude, 01.10.2026): Mythibia-style layout. Opcode 103 (chunked).
local window,data,selected
local category='Featured'
local sub={}
-- 13.10.2026 (Tobeto): clearer sort names; 'Bonus Tier N' lists the outfits and mounts of that tier (120/240/360 coins)
local SORTS={'Price asc. (0-9)','Price desc. (9-0)','Name asc. (A-Z)','Name desc. (Z-A)','Bonus Tier 1','Bonus Tier 2','Bonus Tier 3'}
local TIER_PRICE={['Bonus Tier 1']=120,['Bonus Tier 2']=240,['Bonus Tier 3']=360}
local sortMode=SORTS[1]
local historyMode=false
local search=''
local bonusFilter='Any bonus' -- OurTibia (03.10.2026): outfit/mount bonus search
-- OurTibia (04.10.2026): several bonus filters at once (chips), any or all of them.
local bonusPicks={} -- ordered list of picked bonus labels
local matchAll=false
local function picked() return #bonusPicks>0 end
local showOwned,canAfford=true,false
local parts={}
local TABS={'Featured','Items','Cosmetics','Gameplay','Extras','Loyalty'}
local SUBS={Items={'Various','Backpacks','Taming Items'},Cosmetics={'Mounts','Retro Outfits','Outfits'},Gameplay={'Premium Time & Coins','Boosts','Quests & Access'},Extras={'Services'},Loyalty={'Miscellaneous','Shaders'}}
local FEATURED={'allboosts','stonesack','regeneration','lastinglight','trainingscroll','dismantler','energydrink','junglequiver','trainingspear','multitool','keyring','experienceboost','lootboost','skillboost','blessings','lootslots','templeteleport','bluedjinn','banuta','yalahar','outfitbox','mountbox'}

local function send(text) if g_game.isOnline() then g_game.getProtocolGame():sendExtendedOpcode(103,text) end end
local function money(n) n=math.floor(tonumber(n) or 0);local s=tostring(n):reverse():gsub('(%d%d%d)','%1,'):reverse();return (s:gsub('^,','')) end
local function ui(id) return window:recursiveGetChildById(id) end

local function setArt(item,creature,icon,offer,big)
  item:hide();creature:hide();icon:hide()
  local art=offer.art or {}
  if art.item and art.item>0 then item:setItemId(art.item);item:show()
  elseif art.outfit then
    pcall(function() creature:setCenter(true) end) -- 15.10.2026: outfits centred like mounts
    local female=data and data.sex==0
    creature:setOutfit({type=female and art.outfit.female or art.outfit.male,head=78,body=106,legs=58,feet=76,addons=art.outfit.addons or 3});creature:show()
    local c=creature:getCreature()
    if c then pcall(function() c:setShader(art.shader or 'Default') end) end
  -- 15.10.2026 (Tobeto): mounts centred horizontally (Black Stag, Coralripper, Copper Fly...)
  elseif art.mount then creature:setOutfit({type=art.mount});pcall(function() creature:setCenter(true) end);creature:show()
  elseif art.icon then icon:setImageSource(art.icon);icon:show() end
end
-- 13.10.2026 (Tobeto): outfits and mounts list their bonus one per line
function offerTooltip(offer)
  local head=offer.name..'\n'..offer.price..(offer.currency=='tokens' and ' loyalty tokens' or ' coins')
  if offer.category=='Cosmetics' and type(offer.bonus)=='table' and #offer.bonus>0 then
    local lines={head,'',offer.sub=='Mounts' and 'Bonus while riding:' or 'Bonus while worn (both addons):'}
    for _,b in ipairs(offer.bonus) do lines[#lines+1]=tostring(b.t or (b.l..' '..tostring(b.v))) end
    return table.concat(lines,'\n')
  end
  return head..'\n\n'..(offer.description or '')
end
local function balanceFor(offer) return offer.currency=='tokens' and (data.tokens or 0) or (data.coins or 0) end

local function bonusOf(offer,label)
  for _,b in ipairs(offer.bonus or {}) do if b.l==label then return tonumber(b.v) or 0 end end
end
local function pickScore(offer)
  local n,sum=0,0
  for _,l in ipairs(bonusPicks) do local v=bonusOf(offer,l);if v then n=n+1;sum=sum+v end end
  return n,sum
end
local function matches(offer)
  if TIER_PRICE[sortMode] then
    if offer.category~='Cosmetics' or offer.price~=TIER_PRICE[sortMode] then return false end
    if search~='' and not offer.name:lower():find(search,1,true) then return false end
    return true
  end
  if search~='' then
    if offer.name:lower():find(search,1,true) then return true end
    for _,b in ipairs(offer.bonus or {}) do if tostring(b.t or b.l):lower():find(search,1,true) then return true end end
    return false
  end
  if category=='Featured' then return false end
  if offer.category~=category then return false end
  if category=='Cosmetics' and picked() then
    local n=pickScore(offer)
    if n==0 or (matchAll and n<#bonusPicks) then return false end
  elseif sub[category] and offer.sub~=sub[category] then return false end
  if not showOwned and offer.owned then return false end
  if canAfford and balanceFor(offer)<offer.price then return false end
  return true
end
function refresh()
  if not data or not window then return end
  local panel=ui('products');panel:destroyChildren()
  -- 07.10.2026: the tiles fill the whole row (no empty column on the right)
  pcall(function()
    local layout=panel:getLayout()
    local inner=panel:getWidth()-panel:getPaddingLeft()-panel:getPaddingRight()-2
    if inner>200 then
      -- 10.10.2026: bigger tiles (visual rework)
      local cols=math.max(1,math.floor((inner+6)/(122+6)))
      local w=math.floor((inner-(cols-1)*6)/cols)
      layout:setNumColumns(cols);layout:setCellSize({width=w,height=140})
    end
  end)
  local list={}
  if historyMode then return end
  if category=='Featured' and search=='' and not TIER_PRICE[sortMode] then
    local byId={};for _,o in ipairs(data.products) do byId[o.id]=o end
    for _,id in ipairs(FEATURED) do if byId[id] then list[#list+1]=byId[id] end end
  else
    for _,o in ipairs(data.products) do if matches(o) then list[#list+1]=o end end
    table.sort(list,function(a,b)
      if category=='Cosmetics' and picked() and search=='' then
        local na,sa=pickScore(a);local nb,sb=pickScore(b)
        if na~=nb then return na>nb end
        if sa~=sb then return sa>sb end
      end
      -- OurTibia (05.10.2026): Premium Time offers first, then the Tibia Coin offers
      -- (a full key, so the sort stays consistent when other offers are mixed in)
      local ra=tostring(a.id):find('^premium') and 1 or (tostring(a.id):find('^coins') and 2) or 3
      local rb=tostring(b.id):find('^premium') and 1 or (tostring(b.id):find('^coins') and 2) or 3
      if ra~=rb then return ra<rb end
      if sortMode=='Name asc. (A-Z)' or TIER_PRICE[sortMode] then return a.name:lower()<b.name:lower() end
      if sortMode=='Name desc. (Z-A)' then return a.name:lower()>b.name:lower() end
      if a.price==b.price then return a.name<b.name end
      if sortMode=='Price desc. (9-0)' then return a.price>b.price end
      return a.price<b.price end)
  end
  for _,offer in ipairs(list) do
    local tile=g_ui.createWidget('StoreTile',panel)
    tile:getChildById('name'):setText(offer.name)
    setArt(tile:getChildById('itemIcon'),tile:getChildById('creatureIcon'),tile:getChildById('serviceIcon'),offer)
    tile:getChildById('price'):setText(offer.price)
    tile:getChildById('coin'):setItemId(offer.currency=='tokens' and 22721 or 22118) -- 11.10.2026: Tibia Coins, not gold
    if offer.currency~='tokens' then local c=tile:getChildById('coin');pcall(function() c:setShowCount(false) end);c:setItemCount(10) end
    local badge=tile:getChildById('badge')
    if offer.owned then badge:setText('OWNED');badge:setBackgroundColor('#4a4a8a');badge:show();tile:getChildById('name'):setColor('#a0a0a0')
    elseif offer.promo then badge:setText('PROMO');badge:setBackgroundColor('#c0561a');badge:show()
    elseif offer.new then badge:setText('NEW');badge:setBackgroundColor('#2e8b2e');badge:show() end
    -- 14.10.2026 (Tobeto): the frame fits the text with the same space on both sides
    if badge:isVisible() then badge:setWidth(badge:getTextSize().width+8) end
    if not offer.enabled then tile:setOpacity(0.5) end
    if category=='Cosmetics' and picked() then
      local tags={}
      for _,l in ipairs(bonusPicks) do for _,b in ipairs(offer.bonus or {}) do if b.l==l then tags[#tags+1]=(tostring(b.t or ''):match('^(%S+)') or '') end end end
      if #tags>0 then tile:getChildById('name'):setText(offer.name..' '..table.concat(tags,' ')) end
    end
    tile:setTooltip(offerTooltip(offer))
    tile.onClick=function() openConfirm(offer) end
  end
  for _,b in ipairs(ui('tabs'):getChildren()) do b:setOn(b.tabName==category) end
end
-- 15.10.2026 (Tobeto): bonus filter dropdown (max 7 rows, scrollable, grouped by kind)
local function ourGroupLabels(labels)
  local byLast={}
  for _,l in ipairs(labels) do
    local first,last=l:match('^(.-)%s+(%S+)$')
    if first and first~='' then byLast[last:lower()]=byLast[last:lower()] or {};table.insert(byLast[last:lower()],{label=l,short=first}) end
  end
  local entries,used={},{}
  for last,list in pairs(byLast) do
    if #list>=2 then
      table.sort(list,function(a,b) return a.short:lower()<b.short:lower() end)
      entries[#entries+1]={text=last:sub(1,1):upper()..last:sub(2),children=list}
      for _,c in ipairs(list) do used[c.label]=true end
    end
  end
  for _,l in ipairs(labels) do if not used[l] then entries[#entries+1]={text=l,label=l} end end
  table.sort(entries,function(a,b) return a.text:lower()<b.text:lower() end)
  table.insert(entries,1,{text='(none)',none=true})
  return entries
end
function ourCloseBonusMenu()
  local m=rootWidget:getChildById('ourBonusMenuShade');if m then m:destroy() end
end
local ROWH,ROWS=20,7
local function ourMenuList(shade,x,y,w,entries,onPick,onGroup)
  local box=g_ui.createWidget('UIWidget',shade);box:setPhantom(false)
  box:setBackgroundColor('#1e1e1e');box:setBorderWidth(1);box:setBorderColor('#6a6a6a')
  local n=math.min(ROWS,#entries);box:setSize({width=w,height=n*ROWH+4});box:setPosition({x=x,y=y})
  local list=g_ui.createWidget('UIScrollArea',box);list:fill('parent');list:setMargin(2)
  list:setPaddingRight(#entries>ROWS and 12 or 0)
  local layout=UIVerticalLayout.create(list);list:setLayout(layout)
  if #entries>ROWS then
    local sb=g_ui.createWidget('VerticalScrollBar',box)
    sb:addAnchor(AnchorTop,'parent',AnchorTop);sb:addAnchor(AnchorBottom,'parent',AnchorBottom);sb:addAnchor(AnchorRight,'parent',AnchorRight)
    sb:setMargin(2);sb:setStep(ROWH);pcall(function() sb:setPixelsScroll(true) end)
    list:setVerticalScrollBar(sb)
  end
  for _,e in ipairs(entries) do
    local r=g_ui.createWidget('UIButton',list);r:setHeight(ROWH);r:setFont('verdana-11px-rounded')
    r:setText(e.children and (e.text..'  >') or e.text);r:setTextAlign(AlignLeft);r:setTextOffset({x=6,y=0})
    r:setColor((e.label and e.label==bonusPicks[1]) and '#ffd35a' or '#d8d8d8')
    r.onHoverChange=function(self,h) self:setBackgroundColor(h and '#3a3a3a' or '#00000000');if h and e.children then onGroup(e,self) end end
    r.onClick=function() if e.children then onGroup(e,r) else onPick(e) end end
  end
  return box
end
function ourOpenBonusMenu(bf,labels)
  ourCloseBonusMenu()
  local shade=g_ui.createWidget('UIWidget',rootWidget);shade:setId('ourBonusMenuShade');shade:fill('parent');shade:setPhantom(false)
  shade.onMousePress=function(self,pos,button)
    for _,c in ipairs(self:getChildren()) do if c:containsPoint(pos) then return false end end
    ourCloseBonusMenu();return true
  end
  local entries=ourGroupLabels(labels)
  local side
  local function pick(e)
    bonusPicks=e.none and {} or {e.label};ourCloseBonusMenu()
    scheduleEvent(function() buildLeft();refresh();ui('productScroll'):setValue(0) end,1)
  end
  local main
  local function group(e,row)
    if side then side:destroy();side=nil end
    local subs={};for _,c in ipairs(e.children) do subs[#subs+1]={text=c.short,label=c.label} end
    side=ourMenuList(shade,main:getX()+main:getWidth()-1,row:getY()-2,130,subs,pick,function() end)
  end
  main=ourMenuList(shade,bf:getX(),bf:getY()+bf:getHeight(),bf:getWidth(),entries,pick,group)
  shade:raise()
end
function buildLeft()
  local left=ui('left');left:destroyChildren()
  -- 11.10.2026 (Tobeto's mockup): sub-categories are a second row of tabs under
  -- the main tabs; the left panel only holds search, sorting and filters.
  ui('leftTitle'):setText('SEARCH')
  local subtabs=ui('subtabs');subtabs:destroyChildren()
  -- 14.10.2026 (Tobeto): the sub-category row is centred under the main tabs
  local spacer=SUBS[category] and g_ui.createWidget('UIWidget',subtabs) or nil
  if spacer then spacer:setPhantom(true);spacer:setWidth(0) end
  local rowWidth=0
  for _,name in ipairs(SUBS[category] or {}) do
    local b=g_ui.createWidget('StoreSubTab',subtabs);b:setText(name);b:setOn((sub[category] or SUBS[category][1])==name)
    b:setWidth(b:getTextSize().width+28);rowWidth=rowWidth+b:getWidth()+4
    b.onClick=function() sub[category]=name;search='';buildLeft();refresh();ui('productScroll'):setValue(0) end
  end
  if spacer then spacer:setWidth(math.max(0,math.floor((subtabs:getWidth()-rowWidth)/2)-4)) end
  if not SUBS[category] then
    local hint=g_ui.createWidget('Label',subtabs);hint:setText(category=='Featured' and 'Popular offers from every category' or '')
    hint:setColor('#8a8a8a');hint:setWidth(400);hint:setTextOffset({x=4,y=4})
  end
  if SUBS[category] and not sub[category] then sub[category]=SUBS[category][1] end
  -- 14.10.2026 (Tobeto): typed text centred in the box and limited
  -- 15.10.2026 (Tobeto): text starts at the left like the search box of Set Outfit (cursor and text in one place)
  local s=g_ui.createWidget('TextEdit',left);s:setHeight(22);s:setTooltip('Search product...');pcall(function() s:setMaxLength(20) end);s:setText(search)
  pcall(function() s:setPlaceholder('Search products...') end)
  s.onTextChange=function(_,t) search=t:lower();refresh() end
  local sort=g_ui.createWidget('ComboBox',left);sort:setHeight(22)
  -- 15.10.2026 (Tobeto): Bonus Tier 1-3 only in Cosmetics
  if TIER_PRICE[sortMode] and category~='Cosmetics' then sortMode=SORTS[1] end
  for _,o in ipairs(SORTS) do if category=='Cosmetics' or not TIER_PRICE[o] then sort:addOption(o) end end
  sort:setTextAlign(AlignCenter);sort:setTextOffset({x=-1,y=0}) -- 14.10.2026 (Tobeto): centred in the whole box, equal space above and below
  sort:setCurrentOption(sortMode,true);sort.onOptionChange=function(_,t) sortMode=t;if historyMode then setHistory(false) end;refresh();ui('productScroll'):setValue(0) end
  -- the options of the list are centred too
  local press=sort.onMousePress
  sort.onMousePress=function(self,...)
    local r=UIComboBox.onMousePress(self,...)
    local menu=rootWidget:recursiveGetChildById(self:getId()..'PopupMenu')
    if menu then for _,c in ipairs(menu:getChildren()) do pcall(function() c:setTextAlign(AlignCenter) end) end end
    return r
  end
  if category=='Cosmetics' then
    -- every bonus found on outfits and mounts; picking one lists all
    -- outfits AND mounts with it, the strongest first
    local labels,seen={},{}
    for _,o in ipairs(data and data.products or {}) do
      for _,b in ipairs(o.bonus or {}) do if b.l and not seen[b.l] then seen[b.l]=true;labels[#labels+1]=b.l end end
    end
    table.sort(labels)
    -- 15.10.2026 (Tobeto): ONE bonus filter. The dropdown shows the picked bonus (or "+ Add bonus
    -- filter"), lists at most 7 entries (scroll for more), groups bonuses of one kind (Damage ->
    -- Earth, Energy, Fire ...) in a side list and has "(none)" to reset it.
    for i=#bonusPicks,1,-1 do if not seen[bonusPicks[i]] then table.remove(bonusPicks,i) end end
    while #bonusPicks>1 do table.remove(bonusPicks) end
    matchAll=false
    local bf=g_ui.createWidget('ComboBox',left);bf:setId('ourBonusFilter');bf:setHeight(22)
    bf:setTooltip('Show only outfits and mounts with this bonus, the strongest first.')
    local current=bonusPicks[1] or '+ Add bonus filter'
    bf:addOption(current);bf:setCurrentOption(current,true)
    bf:setTextAlign(AlignCenter);bf:setTextOffset({x=-1,y=0})
    if bonusPicks[1] then bf:setColor('#ffd35a') end
    bf.onMousePress=function(self,mousePos,button)
      if button~=MouseLeftButton then return false end
      ourOpenBonusMenu(self,labels);return true
    end
  end
  local owned=g_ui.createWidget('CheckBox',left);owned:setText('Show Owned');owned:setChecked(showOwned);owned.onCheckChange=function(_,v) showOwned=v;refresh() end
  local afford=g_ui.createWidget('CheckBox',left);afford:setText('Can Afford');afford:setChecked(canAfford);afford.onCheckChange=function(_,v) canAfford=v;refresh() end
  -- 13.10.2026 (Tobeto): global boosts as icons (like the boost bar in the game window)
  -- 14.10.2026 (Tobeto): "ACTIVE BOOSTS", bigger icons, 2 per row; inactive ones grey
  local offers={}
  for _,o in ipairs(data and data.products or {}) do if o.sub=='Boosts' and o.id~='allboosts' then offers[#offers+1]=o end end
  if #offers>0 then
    local title=g_ui.createWidget('Label',left);title:setText('ACTIVE BOOSTS');title:setColor('#c8a040');title:setHeight(16);title:setMarginTop(8);title:setTextAlign(AlignCenter)
    local grid=g_ui.createWidget('UIWidget',left);grid:setHeight(math.ceil(#offers/2)*74)
    local layout=UIGridLayout.create(grid);layout:setCellSize({width=76,height=70});layout:setCellSpacing(4);layout:setNumColumns(2);layout:setFlow(true);grid:setLayout(layout)
    for _,o in ipairs(offers) do
      local active
      for _,b in ipairs(data.boosts or {}) do local n=tostring(b.name or ''):lower();local on=o.name:lower() if n==on or on:find(n,1,true) or n:find(on,1,true) then active=b end end
      local cell=g_ui.createWidget('UIButton',grid);cell:setSize({width=76,height=70})
      cell:setBackgroundColor(active and '#2d2a1c' or '#1a1a1a');cell:setBorderWidth(1);cell:setBorderColor(active and '#c8a040' or '#333333')
      local icon=g_ui.createWidget('UIWidget',cell);icon:setSize({width=44,height=44});icon:setPhantom(true)
      icon:addAnchor(AnchorTop,'parent',AnchorTop);icon:addAnchor(AnchorHorizontalCenter,'parent',AnchorHorizontalCenter);icon:setMarginTop(6)
      local art=o.art or {};if art.icon then icon:setImageSource(art.icon);icon:setImageSmooth(true) end
      if active then icon:setOpacity(1) else icon:setOpacity(0.3);icon:setImageColor('#808080') end
      local lab=g_ui.createWidget('Label',cell);lab:setPhantom(true);lab:setFont('verdana-11px-rounded');lab:setColor(active and '#ffe08a' or '#6a6a6a')
      lab:addAnchor(AnchorBottom,'parent',AnchorBottom);lab:addAnchor(AnchorHorizontalCenter,'parent',AnchorHorizontalCenter);lab:setMarginBottom(5);lab:setTextAutoResize(true)
      lab:setText(active and (math.ceil((active.left or 0)/60)..' min') or 'inactive')
      cell:setTooltip(o.name..'\n'..o.price..' coins - lasts 1 hour'..(active and ('\nActive now: '..math.ceil((active.left or 0)/60)..' min left (buying extends it by 1 hour)') or '\nNot active')..'\n\nClick to buy it for everyone.')
      cell.onClick=function() openConfirm(o) end
    end
  end
  -- 14.10.2026 (Tobeto): respawn fund (every 1,000,000 gp = 1 hour of Spawn Boost for everyone)
  if data then
    local step=tonumber(data.fundStep) or 1000000;local fund=tonumber(data.fund) or 0
    -- 14.10.2026 (Tobeto): the [i] box stands next to the RESPAWN FUND title, the bar uses the whole row
    local trow=g_ui.createWidget('UIWidget',left);trow:setHeight(16);trow:setMarginTop(8)
    local title=g_ui.createWidget('Label',trow);title:setId('fundTitle');title:setText('RESPAWN FUND');title:setColor('#c8a040');title:setTextAutoResize(true)
    title:addAnchor(AnchorHorizontalCenter,'parent',AnchorHorizontalCenter);title:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter);title:setMarginLeft(-10)
    local info=g_ui.createWidget('Label',trow);info:setId('fundInfo');info:setPhantom(false);info:setSize({width=16,height=16});info:setText('i');info:setTextAlign(AlignCenter)
    info:setFont('verdana-11px-rounded');info:setTextOffset({x=0,y=-2});info:setColor('#c8c8c8');info:setBackgroundColor('#0a0a0a');info:setBorderWidth(1);info:setBorderColor('#4a4a4a')
    info:addAnchor(AnchorLeft,'fundTitle',AnchorRight);info:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter);info:setMarginLeft(5)
    info:setTooltip('Respawn fund: '..money(fund)..' / '..money(step)..' gp.\nEvery 1,000,000 gp donated by the players starts 1 hour of Spawn Boost (10% faster respawns) for everyone.\nDonating 1,000,000 gp in total gives the achievement "Areas of Effect" (Hall of Legends).\n\nYour lifetime donations: '..money(tonumber(data.fundMine) or 0)..' gp')
    local row=g_ui.createWidget('UIWidget',left);row:setHeight(36)
    local gold=g_ui.createWidget('UIItem',row);gold:setVirtual(true);gold:setPhantom(true);gold:setSize({width=32,height=32})
    gold:addAnchor(AnchorLeft,'parent',AnchorLeft);gold:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter)
    gold:setItemId(3043);pcall(function() gold:setShowCount(false) end);gold:setItemCount(100)
    local bar=g_ui.createWidget('UIProgressBar',row);bar:setPhantom(true);bar:setHeight(16)
    bar:addAnchor(AnchorLeft,'parent',AnchorLeft);bar:addAnchor(AnchorRight,'parent',AnchorRight);bar:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter);bar:setMarginLeft(36)
    bar:setBackgroundColor('#b08a20');bar:setBorderWidth(1);bar:setBorderColor('#8a7030');bar:setFont('verdana-11px-rounded');bar:setColor('#ffffff');bar:setTextOffset({x=0,y=-2})
    bar:setPercent(math.max(0,math.min(100,math.floor(fund*100/step))))
    -- 14.10.2026: short text so it fits next to the [i] box
    local function short(n) if n>=1000000 and n%1000000==0 then return (n/1000000)..'M' end return money(n) end
    bar:setText(money(fund)..' / '..short(step))
    local donateRow=g_ui.createWidget('UIWidget',left);donateRow:setHeight(22)
    -- 14.10.2026 (Tobeto): empty field, digits only, at most 1,000,000 (more jumps back to 1,000,000)
    local amount=g_ui.createWidget('TextEdit',donateRow);amount:setId('fundAmount');amount:setHeight(22);amount:setWidth(84);
    amount:addAnchor(AnchorLeft,'parent',AnchorLeft);amount:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter)
    pcall(function() amount:setMaxLength(7) end)
    pcall(function() amount:setPlaceholder('gp') end)
    amount:setText(window.ourFundAmount or '')
    amount.onTextChange=function(_,t)
      local d=t:gsub('%D','')
      if tonumber(d) and tonumber(d)>1000000 then d='1000000' end
      if d~=t then amount:setText(d);pcall(function() amount:setCursorPos(#d) end) end
      window.ourFundAmount=d
    end
    local btn=g_ui.createWidget('Button',donateRow);btn:setText('Donate');btn:setHeight(22);btn:setTextOffset({x=0,y=1})
    btn:addAnchor(AnchorLeft,'prev',AnchorRight);btn:addAnchor(AnchorRight,'parent',AnchorRight);btn:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter);btn:setMarginLeft(4)
    btn:setTooltip('Donate gold (backpack first, then bank) to the respawn fund. At least 1,000 gp, in whole thousands.')
    btn.onClick=function()
      local n=tonumber(amount:getText()) or 0
      if n<1000 then showDonateInfo('Donate at least 1,000 gp.');return end
      if data and data.nonce then send('donate:'..data.nonce..':'..math.floor(n)) end
    end
  end
end
function selectTab(name) category=name;search='';if TIER_PRICE[sortMode] and name~='Cosmetics' then sortMode=SORTS[1] end;setHistory(false);buildLeft();refresh();ui('productScroll'):setValue(0) end
function setHistory(on)
  historyMode=on and true or false
  ui('historyList'):setVisible(historyMode);ui('products'):setVisible(not historyMode)
  ui('productScroll'):setValue(0)
  pcall(function() ui('products'):setVerticalScrollBar(nil) end)
  if historyMode then pcall(function() ui('historyList'):setVerticalScrollBar(ui('productScroll')) end)
  else pcall(function() ui('products'):setVerticalScrollBar(ui('productScroll')) end) end
end

function openConfirm(offer)
  selected=offer
  local c=ui('confirm')
  ui('cName'):setText(offer.name)
  ui('cPrice'):setText(offer.price..(offer.currency=='tokens' and ' loyalty tokens' or ' coins'))
  ui('cDesc'):setText(offer.description or '')
  setArt(ui('cItem'),ui('cCreature'),ui('cIcon'),offer)
  ui('cAnonymous'):setVisible(offer.anonymous and true or false);ui('cAnonymous'):setChecked(false)
  local yes=ui('cYes')
  yes:setEnabled(offer.enabled and not offer.owned and balanceFor(offer)>=offer.price)
  yes:setText(offer.owned and 'Owned' or 'Yes')
  c:show();c:raise()
end
function closeConfirm() ui('confirm'):hide();selected=nil end
function showDonateInfo(text)
  if not window then return end
  -- 14.10.2026 (Tobeto): only the answer (the achievement is in the [i] tooltip); the window
  -- is moved by its title bar and blocks the store behind it
  ui('dText'):setText(tostring(text))
  local box,title=ui('donateInfo'),ui('dTitle')
  if not title.ourDrag then
    title.ourDrag=true;title:setDraggable(true)
    title.onDragEnter=function(self,mousePos) box:breakAnchors();self.ourRef={x=mousePos.x-box:getX(),y=mousePos.y-box:getY()};return true end
    title.onDragMove=function(self,mousePos) if self.ourRef then box:setPosition({x=mousePos.x-self.ourRef.x,y=mousePos.y-self.ourRef.y}) end;return true end
    title.onDragLeave=function(self) self.ourRef=nil;return true end
  end
  pcall(g_tooltip.hide)
  ui('donateShade'):show();ui('donateShade'):raise();box:show();box:raise();box:focus()
end
function closeDonateInfo() if window then ui('donateInfo'):hide();ui('donateShade'):hide() end end
function confirmBuy()
  if not selected or not data then return end
  send('buy:'..selected.id..':'..data.nonce..(ui('cAnonymous'):isChecked() and ':anon' or ''))
  ui('cYes'):setEnabled(false)
end
function openTransfer()
  closeConfirm()
  local coins=math.floor(tonumber(data and data.coins) or 0)
  ui('tBalance'):setText('Transferable Premium Points: '..money(coins))
  local tc=ui('tCoin');tc:setItemId(22118);pcall(function() tc:setShowCount(false) end);tc:setItemCount(100)
  -- 14.10.2026 (Tobeto): the gift window can be moved (drag it), a click on it no longer closes it
  local t=ui('transfer')
  if not t.ourDrag then
    t.ourDrag=true
    t.onDragEnter=function(self,mousePos) self:breakAnchors();self.ourRef={x=mousePos.x-self:getX(),y=mousePos.y-self:getY()};return true end
    t.onDragMove=function(self,mousePos) if self.ourRef then self:setPosition({x=mousePos.x-self.ourRef.x,y=mousePos.y-self.ourRef.y}) end;return true end
    t.onDragLeave=function(self) self.ourRef=nil;return true end
  end
  local slider=ui('tSlider')
  slider:setMinimum(coins>0 and 1 or 0);slider:setMaximum(math.max(coins,0));slider:setValue(coins>0 and math.min(10,coins) or 0)
  local function show(v) ui('tAmountLabel'):setText('Amount to gift: '..money(v)) end
  slider.onValueChange=function(_,v) show(v) end
  show(slider:getValue())
  ui('tStatus'):setText(coins>0 and '' or 'You have no Premium Points to gift.')
  ui('tName'):setText('')
  ui('transferShade'):show();ui('transferShade'):raise();ui('transfer'):show();ui('transfer'):raise();ui('tName'):focus()
end
function closeTransfer() ui('transfer'):hide();ui('transferShade'):hide() end
function confirmTransfer()
  if not data then return end
  local name=ui('tName'):getText():gsub('^%s+',''):gsub('%s+$','');local amount=math.floor(tonumber(ui('tSlider'):getValue()) or 0)
  if name=='' then ui('tStatus'):setText('Enter the name of the recipient.');return end
  if amount<1 then ui('tStatus'):setText('Choose how many Premium Points to gift.');return end
  if amount>(data.coins or 0) then ui('tStatus'):setText('You do not have that many Premium Points.');return end
  send('transfer:'..data.nonce..':'..amount..':'..name);closeTransfer()
end
function history()
  closeConfirm();pcall(closeTransfer)
  setHistory(true)
  for _,b in ipairs(ui('tabs'):getChildren()) do b:setOn(false) end
  local subtabs=ui('subtabs');subtabs:destroyChildren()
  local hint=g_ui.createWidget('Label',subtabs);hint:setText('Purchase history - pick a category above to go back to the offers')
  hint:setColor('#8a8a8a');hint:setWidth(500);hint:setTextOffset({x=4,y=4})
  local list=ui('historyList');list:destroyChildren()
  local rows=data and data.history or {}
  -- 14.10.2026 (Tobeto): columns Date / Description / Amount / Balance; spending red, income green
  local function cell(parent,text,x,w,align,color)
    local l=g_ui.createWidget('Label',parent);l:setPhantom(true);l:setFont('verdana-11px-rounded');l:setText(text);l:setColor(color or '#d8d8d8')
    l:addAnchor(AnchorTop,'parent',AnchorTop);l:addAnchor(AnchorBottom,'parent',AnchorBottom);l:addAnchor(AnchorLeft,'parent',AnchorLeft)
    l:setMarginLeft(x);l:setWidth(w);l:setTextAlign(align or AlignLeft);return l
  end
  local width=math.max(400,list:getWidth()-20)
  -- 14.10.2026 (Tobeto): thin lines between the columns, more room after the date
  local DATE_W,AMOUNT_W,BAL_W=124,96,110
  local descW=width-DATE_W-AMOUNT_W-BAL_W-36
  local SEP1=DATE_W+10;local DESC_X=DATE_W+16;local SEP2=DESC_X+descW+4;local AMT_X=SEP2+6;local SEP3=AMT_X+AMOUNT_W+2;local BAL_X=SEP3+6
  local function lines(parent)
    for _,x in ipairs({SEP1,SEP2,SEP3}) do
      local l=g_ui.createWidget('UIWidget',parent);l:setPhantom(true);l:setWidth(1);l:setBackgroundColor('#3a3a3a')
      l:addAnchor(AnchorTop,'parent',AnchorTop);l:addAnchor(AnchorBottom,'parent',AnchorBottom);l:addAnchor(AnchorLeft,'parent',AnchorLeft);l:setMarginLeft(x)
    end
  end
  local head=g_ui.createWidget('UIWidget',list);head:setHeight(20);head:setBackgroundColor('#262626')
  cell(head,'Date',6,DATE_W,AlignLeft,'#c8a040');cell(head,'Description',DESC_X,descW,AlignLeft,'#c8a040')
  cell(head,'Amount',AMT_X,AMOUNT_W-4,AlignRight,'#c8a040');cell(head,'Balance',BAL_X,BAL_W-4,AlignRight,'#c8a040');lines(head)
  if #rows==0 then local l=g_ui.createWidget('Label',list);l:setText('No purchases yet.');l:setColor('#a0a0a0') end
  -- running balance for old rows without a saved one (coins only)
  local running=data and tonumber(data.coins) or nil
  for index,h in ipairs(rows) do
    local price=tonumber(h.price) or 0
    local tokens=h.currency=='tokens'
    local bal=tonumber(h.bal)
    if not tokens then
      if bal then running=bal end
      bal=bal or running
      if running then running=running+price end
    end
    local r=g_ui.createWidget('UIWidget',list);r:setHeight(18);r:setBackgroundColor(index%2==0 and '#1e1e1e' or '#00000000')
    cell(r,os.date('%d.%m.%Y %H:%M',h.time),6,DATE_W)
    local d=cell(r,tostring(h.product),DESC_X,descW);d:setTooltip(tostring(h.product))
    local change=-price
    local amountText=(change>0 and '+' or '')..money(math.abs(change))
    if change<0 then amountText='-'..money(math.abs(change)) end
    cell(r,amountText,AMT_X,AMOUNT_W-24,AlignRight,change<0 and '#ff7b7b' or '#8fe08f')
    local icon=g_ui.createWidget('UIItem',r);icon:setVirtual(true);icon:setPhantom(true);icon:setSize({width=16,height=16})
    icon:addAnchor(AnchorLeft,'parent',AnchorLeft);icon:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter);icon:setMarginLeft(AMT_X+AMOUNT_W-20)
    icon:setItemId(tokens and 22721 or 22118);if not tokens then pcall(function() icon:setShowCount(false) end);icon:setItemCount(100) end
    cell(r,bal and (money(bal)..(tokens and ' tokens' or ' coins')) or '-',BAL_X,BAL_W-4,AlignRight,'#e8e8e8');lines(r)
  end
end
local function receive(protocol,opcode,buffer)
  local i,total,piece=buffer:match('^(%d+)/(%d+)|(.*)$')
  if not i then return end
  i,total=tonumber(i),tonumber(total);if i==1 then parts={} end;parts[i]=piece;if i<total then return end
  local ok,result=pcall(json.decode,table.concat(parts));parts={}
  if not ok or type(result)~='table' then return end
  data=result
  ui('coins'):setText(money(data.coins)..' coins');ui('gold'):setText(money(data.gold)..' gp');ui('tokens'):setText(money(data.tokens)..' tokens')
  for _,b in ipairs({{'coinsBox',22118,money(data.coins)..' coins','#ffd35a'},{'goldBox',3043,money(data.gold)..' gp','#e8e8e8'},{'tokensBox',22721,money(data.tokens)..' tokens','#9fd0ff'}}) do
    local box=ui(b[1]);box:getChildById('icon'):setItemId(b[2]);if b[2]~=22721 then local ic=box:getChildById('icon');pcall(function() ic:setShowCount(false) end);ic:setItemCount(100) end;box:getChildById('value'):setText(b[3]);box:getChildById('value'):setColor(b[4])
  end
  local msg=data.message or ''
  if msg:lower():find('donat',1,true) or msg:lower():find('respawn fund',1,true) then showDonateInfo(msg);msg='' end
  ui('status'):setText(msg)
  buildLeft();refresh()
  if selected then
    for _,o in ipairs(data.products) do if o.id==selected.id then
      if data.message and data.message~='' then closeConfirm() else openConfirm(o) end
    break end end
  end
end
-- Outfit shaders bought in the Loyalty store (server 87_shaders.lua, opcode 113).
local SHADERS={'Outfit - Rainbow','Outfit - Ghost','Outfit - Jelly','Outfit - Fragmented','Outfit - Outline','Outfit - cyclopedia-black','Outfit - ForgeDonor','Outfit - ForgeSuccess','Outfit - ForgeFailed',
  'Outfit - Blood Moon','Outfit - Toxic','Outfit - Golden Glow','Outfit - Frost','Outfit - Inferno','Outfit - Storm','Outfit - Void','Outfit - Holy Light','Outfit - Aurora'}
local function applyShader(c,i)
  if not c then return end
  -- 11.10.2026: "none" (0) clears the shader - there is no shader called 'Default' in this client
  local name=SHADERS[i]
  pcall(function() c:setDrawOutfitColor(i~=2) end)
  if name then pcall(function() c:setShader(name) end)
  elseif not pcall(function() c:setShader('') end) then pcall(function() c:setShader('Default') end) end
end
local function onShader(protocol,opcode,buffer)
  -- 11.10.2026: owned shaders for the Set Outfit window
  local sel,list=buffer:match('^o:(%d+):(.*)$')
  if sel then
    local owned={}
    for i,cname,dname in list:gmatch('(%d+)=([^=;]+)=([^;]+)') do owned[#owned+1]={tonumber(i),cname,dname} end
    local outfit=modules.game_outfit
    if outfit and outfit.ourSetShaders then pcall(outfit.ourSetShaders,owned,tonumber(sel)) end
    return
  end
  local cid,i=buffer:match('^s:(%d+):(%d+)$')
  if cid then applyShader(g_map.getCreatureById(tonumber(cid)),tonumber(i)) end
end
local function onCreatureAppear(c)
  if c and c:isPlayer() and g_game.isOnline() then g_game.getProtocolGame():sendExtendedOpcode(113,'q:'..c:getId()) end
end
function hide() if window then window:hide();closeConfirm();pcall(closeTransfer);pcall(closeDonateInfo) end end
function show() send('catalog');window:show();window:raise();window:focus() end
function toggle() if window:isVisible() then hide() else show() end end
function init()
  window=g_ui.displayUI('store');window:hide()
  for _,name in ipairs(TABS) do
    local b=g_ui.createWidget('StoreTab',ui('tabs'));b:setText(name);b.tabName=name;b:setWidth(142)
    b.onClick=function() selectTab(name) end
  end
  ProtocolGame.registerExtendedOpcode(103,receive);connect(g_game,{onGameEnd=hide})
  ProtocolGame.registerExtendedOpcode(113,onShader);connect(Creature,{onAppear=onCreatureAppear})
end
function terminate() ProtocolGame.unregisterExtendedOpcode(103);pcall(ProtocolGame.unregisterExtendedOpcode,113);disconnect(Creature,{onAppear=onCreatureAppear});disconnect(g_game,{onGameEnd=hide});if window then window:destroy() end end
function testCatalog() return data end
