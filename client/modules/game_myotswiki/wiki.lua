local window,button,catalog,itemPage
local sourcesByItem,npcsByName={},{}
local tab='items'
local filtered,page,pageSize={},1,21
local selected,detailMode,changing
local cardCellWidth=200
local mapIndex=1
local markers={}
local referenceMapActive=false
local allSpawns=false
local markersHidden=false
local mapGroup="Monsters"
local mapRefreshEvent
local lootSort="Chance"
local lootDescending=true
local filterIds={'search','category','sort','direction','obtaining','resistance','tier','weapon','hands','element','weakness','spawnFilter','minimum','maximum','resetFilters'}
local tabStates={}
local itemFilters={obtaining=true,resistance=true,tier=true,weapon=true,hands=true,element=true}
local creatureFilters={weakness=true,spawnFilter=true}
local elements={'Physical','Energy','Earth','Fire','Ice','Holy','Death'}
WikiFilters={}
function WikiFilters.prepare(row,sources)
  local m={resist={},sources=sources or {}}
  for _,line in ipairs(type(row.desc)=='table' and row.desc or {}) do
    local attack=line:match('^Atk:%s*([%d%-]+)') or line:match('^attack:%s*([%d%-]+)')
    m.Attack=m.Attack or tonumber(attack and attack:match('(%d+)$'))
    m.Defense=m.Defense or tonumber(line:match('^Def:%s*(%d+)')) or tonumber(line:match('^defense:%s*(%d+)'))
    m.Armor=m.Armor or tonumber(line:match('^Arm:%s*(%d+)')) or tonumber(line:match('^armor:%s*(%d+)'))
    m.Weight=m.Weight or tonumber(line:match('weighs%s+([%d%.]+)'))
    for _,element in ipairs(elements) do
      local value=line:match('^Protection '..element..'%s+([%+%-]?[%d%.]+)%%') or line:match('^'..element..'%s+([%+%-]?[%d%.]+)%%')
      if value then m.resist[element]=tonumber(value) end
    end
  end
  m.Strength=math.max(m.Attack or 0,m.Defense or 0,m.Armor or 0,tonumber(row.maxDmg) or 0)
  for _,price in pairs(type(row.buyFrom)=='table' and row.buyFrom or {}) do
    price=tonumber(price);if price then m['NPC buy price']=math.min(m['NPC buy price'] or price,price) end
  end
  for _,price in pairs(type(row.sellTo)=='table' and row.sellTo or {}) do
    price=tonumber(price);if price then m['NPC sell price']=math.max(m['NPC sell price'] or price,price) end
  end
  for _,source in ipairs(m.sources) do
    if (source.chance or -1)>=0 then m['Drop chance']=math.max(m['Drop chance'] or 0,source.chance) end
    if (source.tier or 0)>0 then m.Tier=math.max(m.Tier or 0,source.tier) end
  end
  for _,q in ipairs(type(row.questSources)=='table' and row.questSources or {}) do
    if (q.tier or 0)>0 then m.Tier=math.max(m.Tier or 0,q.tier) end
  end
  row.wikiFilters=m;return m
end
function WikiFilters.matches(row,source,resistance,tier)
  local m=row.wikiFilters;source=source or 'All';resistance=resistance or 'All';tier=tonumber(tier)
  if resistance~='All' and (m.resist[resistance] or 0)<=0 then return false end
  local matched=false
  for _,entry in ipairs(m.sources) do
    if (source=='All' or source==(entry.kind=='Boss' and 'Bosses' or 'Monsters')) and (not tier or entry.tier==tier) then matched=true end
  end
  if source=='All' or source=='Quests' then
    for _,q in ipairs(type(row.questSources)=='table' and row.questSources or {}) do if not tier or q.tier==tier then matched=true end end
    if source=='Quests' and not tier and row.questReward then matched=true end
  end
  if tier then return matched end
  if source=='All' then return true end
  if source=='NPC sellers' then return m['NPC buy price']~=nil end
  if source=='NPC buyers' then return m['NPC sell price']~=nil end
  return matched
end
function WikiFilters.less(a,b,key,descending)
  local function value(r)
    if key=='Power' then return r.exp end
    if key=='Strongest hit' then local hit=0;for _,a in ipairs(r.attacks or {})do hit=math.max(hit,math.abs(a.max or 0),math.abs(a.min or 0))end;return r.exp and hit end
    if key=='Locations' then return #(r.spawns or {}) end
    if key=='Name' then return r.name:lower() end
    if key=='Experience' then return r.exp end
    if key=='Hitpoints' then return r.hp end
    if key=='Speed' then return r.speed end
    return r.wikiFilters and r.wikiFilters[key]
  end
  local x,y=value(a),value(b)
  if x==nil or y==nil then if x~=y then return x~=nil end
  elseif x~=y then if descending then return x>y end;return x<y end
  if key=='Power' and (a.hp or 0)~=(b.hp or 0) then if descending then return (a.hp or 0)>(b.hp or 0) end;return (a.hp or 0)<(b.hp or 0) end
  if a.name~=b.name then return a.name<b.name end
  return (a.sid or 0)<(b.sid or 0)
end
function WikiFilters.extra(row,f,isItem)
  if isItem then
    local subtype=(row.weaponSubType or ''):gsub('2h','')
    if f.weapon~='All' and subtype~=f.weapon:lower() then return false end
    if f.hands~='All' and row.hand~=(f.hands=='One-handed' and 'one' or 'two') then return false end
    if f.element~='All' then
      local text=(table.concat(row.desc or {},' ')..' '..(row.shortinfo or '')):lower()
      if not text:find(f.element:lower(),1,true) then return false end
    end
  else
    if f.weakness~='All' and ((row.resist or {})[f.weakness:lower()] or 0)>=0 then return false end
    local count=#(row.spawns or {})
    if f.spawnFilter=='With spawns' and count==0 or f.spawnFilter=='Without spawns' and count>0 then return false end
  end
  local metric=f.sort
  local value=(row.wikiFilters or {})[metric]
  if metric=='Power' or metric=='Experience' then value=row.exp
  elseif metric=='Hitpoints' then value=row.hp
  elseif metric=='Speed' then value=row.speed
  elseif metric=='Locations' then value=#(row.spawns or {})
  elseif metric=='Strongest hit' then value=0;for _,a in ipairs(row.attacks or {})do value=math.max(value,math.abs(a.max or 0),math.abs(a.min or 0))end end
  local lo,hi=tonumber(f.minimum),tonumber(f.maximum)
  if (lo or hi) and (value==nil or lo and value<lo or hi and value>hi) then return false end
  return true
end
local function filterVisibility(visible)
  for _,id in ipairs(filterIds) do
    local w=window:recursiveGetChildById(id)
    local show=visible and (not itemFilters[id] or tab=='items') and (not creatureFilters[id] or tab=='monsters' or tab=='bosses' or tab=='map')
    w:setVisible(show)
    local label=window:recursiveGetChildById(id..'Label');if label then label:setVisible(show) end
  end
end
local function restoreMap()
  referenceMapActive=false
end
local tabs={{'items','Items & Loot'},{'monsters','Bestiary'},{'bosses','Bosstiary'},{'knowledge','Knowledge'},{'map','Map & Spawns'}}
local function ui(id) return window:recursiveGetChildById(id) end
local function title(s) return (s:gsub('(%a)([%w\']*)',function(a,b)return a:upper()..b end)) end
local function list(value) return type(value)=='table' and value or {} end
local function number(n) return tostring(n or 0):reverse():gsub('(%d%d%d)','%1,'):reverse():gsub('^,','') end
local iconRoot='/game_cyclopedia/images/bestiary/icons/monster-icon-'
local damageColors={physical='#cccccc',fire='#ff9900',ice='#70d8ff',earth='#70c850',energy='#c080ef',holy='#ffdc60',death='#aa7bce'}
local function heading(parent,text)
  local w=g_ui.createWidget('Label',parent);w:setText(text);w:setHeight(26);w:setColor('#dddddd');return w
end
local function statRow(parent,name,value,icon,color)
  local w=g_ui.createWidget('WikiStatRow',parent)
  w:getChildById('icon'):setImageSource(iconRoot..icon)
  w:getChildById('name'):setText(name)
  w:getChildById('value'):setText(value);w:getChildById('value'):setColor(color or '#dddddd')
  return w
end
local function attackElement(attack)
  local name=(attack.name or ''):lower()
  for element in pairs(damageColors) do if name:find(element,1,true) then return element end end
  if name=='melee' then return 'physical' end
  return nil
end
local function art(w,row)
  local item=w:getChildById('item');local creature=w:getChildById('creature')
  for _,id in ipairs({'itemMissingArt','creatureMissingArt','creatureReferenceArt','creatureReferenceObject'}) do
    local overlay=w:getChildById(id);if overlay then overlay:hide() end
  end
  item:hide();creature:hide()
  if not row.sid then
    if row.outfit or row.look then OurTibiaArt.creature(creature,row.outfit or row.look,row.name) end
    return
  end
  local cid=tonumber(row.cid) or 0
  local thing=cid>0 and g_things.getThingType(cid,ThingCategoryItem)
  local itemValid=thing and thing:getId()==cid
  if itemValid then
    item:setItemId(cid);item:show()
    local missing=w:getChildById('itemMissingArt');if missing then missing:hide() end
  else
    item:hide();OurTibiaArt.placeholder(item)
  end
end
-- 10.10.2026: card lines that are wider than the card are shortened with "..."
-- (e.g. "Atk: 95-130 Death, Magic Level +3" ran out of the card); the full
-- text is in the tooltip.
local measure
function fitCardText(widget,text,room)
  if not measure then measure=g_ui.createWidget('Label',rootWidget);measure:hide() end
  measure:setFont(widget:getFont())
  room=room or (widget:getWidth()-62)
  local lines={}
  for line in (text..'\n'):gmatch('(.-)\n') do
    measure:setText(line)
    if measure:getTextSize().width>room then
      local cut=line
      while #cut>3 do
        cut=cut:sub(1,#cut-1):gsub('[%s,]+$','')
        measure:setText(cut..'...')
        if measure:getTextSize().width<=room then break end
      end
      line=cut..'...'
    end
    lines[#lines+1]=line
  end
  widget:setText(table.concat(lines,'\n'))
end
local function card(row,text,action)
  local w=g_ui.createWidget('WikiCard',ui('cards'));fitCardText(w,text,(cardCellWidth or 200)-60);art(w,row)
  w:setTooltip(title(row.name or '')..(text:find('\n') and ('\n'..text:match('\n(.*)$')) or ''));w.onClick=action;return w
end
-- 10.10.2026: Loot / Attacks look like the Drop / Quest tabs of an item page
NEMESIS_BOSSES={['yeti']=true,['the horned fox']=true,['necropharus']=true,['fernfang']=true,['man in the cave']=true,['dharalion']=true,['demodras']=true,['arachir the ancient one']=true,['diblis the fair']=true,['sir valorcrest']=true,['zevelon duskbringer']=true,['the old widow']=true,['zulazza the corruptor']=true,['zushuka']=true,['the pale count']=true}
local function detailButton(text,action,on)
  local w=g_ui.createWidget('Button',ui('detailTabs'));w:setSize({width=96,height=20});w:setMarginTop(4);w:setText(text);w.onClick=action
  w:setColor(on and '#ffd35a' or '#a0a0a0');w:setOn(on and true or false)
end
local function grid(columns)
  cardCellWidth=columns==2 and 300 or 200
  local panel=ui('cards');panel:setLayout(UIGridLayout.create(panel))
  panel:getLayout():setNumColumns(columns);panel:getLayout():setCellSize({width=columns==2 and 300 or 200,height=55});panel:getLayout():setCellSpacing(3)
end
local function resetView()
  if itemPage then itemPage:hide() end;ui('sidebar'):show();ui('right'):show()
  ui('detailHero'):hide();ui('sidebar'):setMarginTop(10);ui('right'):setMarginTop(10)
  ui('mapBrowser'):hide();ui('sidebar'):show();ui('filterScroll'):show();ui('lootControls'):hide();ui('descriptionScroll'):hide();ui('scrollbar'):show()
  ui('cards'):destroyChildren();ui('detailTabs'):destroyChildren()
  ui('itemPortrait'):hide();ui('portrait'):hide()
  local reference=ui('detailHeader'):getChildById('portraitReferenceArt');if reference then reference:hide() end
  local object=ui('detailHeader'):getChildById('portraitReferenceObject');if object then object:hide() end
  ui('cards'):show();ui('description'):hide();ui('worldmap'):hide();ui('mapControls'):hide()
  ui('statRows'):destroyChildren();ui('statRows'):hide();ui('stats'):show();ui('locate'):hide();ui('stats'):setText('');ui('scrollbar'):setValue(0)
  ui('detailHeader'):setHeight(0);ui('detailHeader'):hide();ui('detailTabs'):setHeight(0)
  filterVisibility(true)
  ui('stats'):setWidth(185);ui('sidebarTitle'):setWidth(185)
  ui('cards'):setMarginTop(0);ui('scrollbar'):setMarginTop(0)
  ui('sidebarTitle'):setText('Filters');grid(3)
end
function hide() restoreMap();if window then window:hide() end end
function show() if g_game.isOnline() then if #ui('cards'):getChildren()==0 and tab~='knowledge' then changeTab('items',true)end;window:show();window:raise();window:focus() end end
function toggle() if window:isVisible() then hide() else show() end end
local function merchantText(value)
  local rows={};for name,price in pairs(list(value)) do rows[#rows+1]=title(tostring(name))..' - '..number(price)..' gold' end
  table.sort(rows);return #rows>0 and table.concat(rows,'\n') or 'None'
end

local function detailUI(id) return itemPage:recursiveGetChildById(id) end
-- 09.10.2026: item sources in two tabs - "Drop" (monsters/bosses) and "Quest"
local sourceTab='drop'
function setSourceTab(tabName) sourceTab=tabName=='quest' and 'quest' or 'drop';renderItemSources() end
function renderItemSources()
  if not selected then return end
  local panel=detailUI('sources');panel:destroyChildren()
  local filter=detailUI('sourceFilter'):getCurrentOption().text
  local sort=detailUI('sourceSort'):getCurrentOption().text
  local descending=detailUI('sourceOrder'):getCurrentOption().text=='Descending'
  local drops,quests=sourcesByItem[selected.sid] or {},list(selected.questSources)
  local dropTab,questTab=detailUI('dropTab'),detailUI('questTab')
  if dropTab then dropTab:setText('Drop ('..#drops..')');dropTab:setColor(sourceTab=='drop' and '#ffd35a' or '#a0a0a0');dropTab:setOn(sourceTab=='drop') end
  if questTab then questTab:setText('Quest ('..#quests..')');questTab:setColor(sourceTab=='quest' and '#ffd35a' or '#a0a0a0');questTab:setOn(sourceTab=='quest') end
  detailUI('sourceFilter'):setEnabled(sourceTab=='drop')
  local rows={}
  if sourceTab=='drop' then
    for _,source in ipairs(drops) do if filter=='All' or source.kind==filter then rows[#rows+1]=source end end
  else
    for _,quest in ipairs(quests) do rows[#rows+1]={name=quest.name,tier=quest.tier,kind='Quest',chance=-1,quest=true} end
  end
  table.sort(rows,function(a,b)
    local x,y=a.name,b.name
    if sort=='Chance' then x,y=a.chance,b.chance elseif sort=='Tier' then x,y=a.tier or 0,b.tier or 0 end
    if x==y then return a.name<b.name end
    if descending then return x>y else return x<y end
  end)
  for _,source in ipairs(rows) do
    local entry=source
    local w=g_ui.createWidget('WikiCard',panel)
    local tier=(entry.tier or 0)>0 and ('T'..entry.tier) or 'No tier'
    local chance=entry.chance>=0 and string.format(' %.2f%%',entry.chance) or ''
    fitCardText(w,title(entry.name)..'\n'..entry.kind..'  '..tier..chance,136)
    w:setTooltip(title(entry.name)..'\n'..tier..chance)
    art(w,entry.creature or {name=entry.name})
    if entry.quest then
      -- 09.10.2026: a quest has no creature/item picture - show the quest log icon
      local q=g_ui.createWidget('UIWidget',w);q:setId('questIcon');q:setPhantom(true);q:setSize({width=32,height=32})
      q:addAnchor(AnchorLeft,'parent',AnchorLeft);q:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter);q:setMarginLeft(7)
      q:setImageSource('/images/topbuttons/questlog');q:setImageFixedRatio(true)
    end
    if entry.creature then w.onClick=function()changeTab(entry.section);selected=entry.creature;renderDetail()end end
  end
  if #rows==0 then local w=g_ui.createWidget('Label',panel);w:setText(sourceTab=='quest' and 'No known quest' or 'No known drops');w:setSize({width=190,height=30}) end
end
function renderItemPage(row)
  ui('sidebar'):hide();ui('right'):hide();ui('filterScroll'):hide();itemPage:show()
  local icon=detailUI('icon');local cid=tonumber(row.cid) or 0
  local prof=detailUI('profButton')
  if prof then
    local mod=modules.game_myotsprof
    prof:setVisible(mod~=nil and mod.isWeapon~=nil and mod.isWeapon(cid))
    prof.onClick=function() if modules.game_myotsprof then modules.game_myotsprof.open(cid,true) end end
  end
  -- 07.10.2026: the Drop Tracker sends players here to pick the item to track
  local track=detailUI('trackButton')
  if track then
    local function tracked() local a=modules.game_analyser;local d=a and a.DropTrackerAnalyser;return d and d.trackedItems and d.trackedItems[cid] end
    track:setText(tracked() and 'Stop tracking drop' or 'Track drop')
    track:setEnabled(cid>0)
    track.onClick=function()
      local a=modules.game_analyser;local d=a and a.DropTrackerAnalyser
      if not d or not d.managerDropItem then return end
      local on=not tracked()
      d:managerDropItem(cid,on)
      track:setText(on and 'Stop tracking drop' or 'Track drop')
      if modules.game_textmessage then modules.game_textmessage.displayStatusMessage(title(row.name)..(on and ' is now in the Drop Tracker.' or ' was removed from the Drop Tracker.')) end
    end
  end
  local thing=cid>0 and g_things.getThingType(cid,ThingCategoryItem)
  if thing and thing:getId()==cid then
    icon:setItemId(cid);icon:show()
    local missing=icon:getParent():getChildById('iconMissingArt');if missing then missing:hide() end
  else
    icon:hide();OurTibiaArt.placeholder(icon)
  end
  detailUI('name'):setText(title(row.name)..'\n'..(row.shortinfo or row.category or ''))
  detailUI('stats'):setText('Base stats\n\n'..table.concat(list(row.desc),'\n'))
  sourceTab=(#(sourcesByItem[row.sid] or {})==0 and #list(row.questSources)>0) and 'quest' or 'drop'
  renderItemSources()
  for _,group in ipairs({{'buy',row.buyFrom},{'sell',row.sellTo}}) do
    local panel=detailUI(group[1]);panel:destroyChildren();local rows={}
    for name,price in pairs(list(group[2])) do rows[#rows+1]={name=name,price=price} end
    table.sort(rows,function(a,b)return a.name<b.name end)
    for _,merchant in ipairs(rows) do
      local npc=npcsByName[merchant.name:lower()]
      local w=g_ui.createWidget('WikiCard',panel);w:setHeight(44)
      w:setText(title(merchant.name)..'     '..number(merchant.price)..' gp');art(w,npc or {name=merchant.name})
      if npc then w.onClick=function()changeTab('map');selected=npc;locate() end end
    end
    if #rows==0 then local w=g_ui.createWidget('Label',panel);w:setText(group[1]=='buy' and 'No known seller' or 'No known buyer');w:setHeight(40) end
  end
end

function renderDetail(mode)
  local row=selected;if not row then return end
  resetView();detailMode=mode or 'loot';ui('address'):setText('wiki://'..tab..'/'..row.name:gsub(' ','_'))
  filterVisibility(false)
  ui('sidebarTitle'):setText('Details')
  -- 07.10.2026: the arrows switch to the previous / next entry of the list
  local at;for i,r in ipairs(filtered) do if r==row then at=i;break end end
  ui('page'):setText(title(row.name)..(at and ('   ('..at..' / '..#filtered..')') or ''));ui('previousPage'):setEnabled(at~=nil and at>1);ui('nextPage'):setEnabled(at~=nil and at<#filtered)
  if tab=='items' then
    renderItemPage(row)
    return
  end
  ui('stats'):hide();ui('statRows'):show();ui('sidebarTitle'):setText('Monster details')
  local stats=ui('statRows')
  heading(stats,'Base stats')
  statRow(stats,'Hitpoints',number(row.hp),'hitpoints')
  statRow(stats,'Experience',number(row.exp),'experience')
  statRow(stats,'Speed',number(row.speed),'speed')
  heading(stats,'Resistances')
  for _,element in ipairs({'physical','energy','earth','fire','ice','holy','death'}) do
    local resist=tonumber(list(row.resist)[element]) or 0
    statRow(stats,title(element),(resist>0 and '+' or '')..resist..'%',element..'-resist',resist>0 and '#ef6666' or resist<0 and '#70d878' or '#888888')
  end
  ui('locate'):show()
  ui('detailHero'):show();ui('sidebar'):setMarginTop(80);ui('right'):setMarginTop(80)
  ui('heroName'):setText(title(row.name)..(row.taskBoss and '  [Task boss]' or ''))
  ui('heroSpawns'):setText(#list(row.spawns)>0 and #list(row.spawns)..' spawn locations' or 'No fixed spawns')
  OurTibiaArt.creature(ui('heroPortrait'),row.outfit,row.name)
  ui('detailHeader'):hide();ui('detailHeader'):setHeight(0);ui('detailTabs'):setHeight(28)
  -- 10.10.2026: the monster details fit without the filter scrollbar (it ran through the header)
  ui('filterScroll'):hide();ui('cards'):setMarginTop(6);ui('scrollbar'):setMarginTop(6)
  ui('creatureTitle'):setText(title(row.name)..'\n'..#list(row.spawns)..' spawn locations')
  OurTibiaArt.creature(ui('portrait'),row.outfit,row.name)
  detailButton('Loot ('..#list(row.loot)..')',function()renderDetail('loot')end,detailMode~='attacks');detailButton('Attacks ('..#list(row.attacks)..')',function()renderDetail('attacks')end,detailMode=='attacks')
  -- 13.10.2026 (Tobeto): Nemesis bosses link to the Nemesis Bosses window (wiki closes)
  if NEMESIS_BOSSES[tostring(row.name):lower()] then
    local w=g_ui.createWidget('Button',ui('detailTabs'));w:setSize({width=110,height=20});w:setMarginTop(4);w:setText('Nemesis window');w:setColor('#ff9a6a')
    w.onClick=function() hide();local L=modules.game_myotslegends;if L and L.NemesisUI then L.NemesisUI.show() end end
  end
  if detailMode=='attacks' then
    ui('cards'):setLayout(UIVerticalLayout.create(ui('cards')))
    local maximum=1;for _,attack in ipairs(list(row.attacks)) do maximum=math.max(maximum,math.abs(attack.max or 0)) end
    heading(ui('cards'),'STRONGEST HIT   '..number(maximum))
    for _,attack in ipairs(list(row.attacks)) do
      local element=attackElement(attack)
      local color=damageColors[element] or '#cccccc'
      local name=attack.script and 'Special ability' or title(attack.name or 'Attack')
      if name=='' then name='Attack' end
      if attack.length then name=name..' wave' elseif attack.radius then name=name..' burst' elseif attack.range then name=name..' attack  (range '..attack.range..')' end
      local a=g_ui.createWidget('WikiAttack',ui('cards'))
      a:getChildById('icon'):setImageSource(iconRoot..(element and element..'-resist' or 'spellcaster'))
      a:getChildById('name'):setText(name);a:getChildById('name'):setColor(color)
      a:getChildById('range'):setText(number(math.abs(attack.min or 0))..' - '..number(math.abs(attack.max or 0)))
      a:getChildById('range'):setColor(color)
      a:getChildById('bar'):setBackgroundColor(color)
      a:getChildById('bar'):setPercent(math.abs(attack.max or 0)/maximum*100)
      a:setTooltip(name..' | Damage range; strongest attack: '..number(maximum))
    end

  else
    local loot={};for _,drop in ipairs(list(row.loot)) do loot[#loot+1]=drop end
    ui('lootControls'):show()
    table.sort(loot,function(a,b)
      local x,y
      if lootSort=='Tier' then x,y=tonumber(a.tier) or 0,tonumber(b.tier) or 0 elseif lootSort=='Name' then x,y=a.name,b.name else x,y=tonumber(a.chance) or 0,tonumber(b.chance) or 0 end
      if x==y then return a.name<b.name end
      if lootDescending then return x>y end;return x<y
    end)
    for _,drop in ipairs(loot) do
      local item=drop
      local count=(item.maxCount or 1)>1 and tostring(item.minCount or 1)..'-'..item.maxCount..'x  ' or ''
      local tier=(tonumber(item.tier) or 0)>0 and 'T'..item.tier..'  ' or ''
      local w=card(item,title(item.name)..'\n'..tier..count..tostring(item.chance)..'%',function()showReferenceItem(item.sid)end)
      w:setTooltip(title(item.name)..((tonumber(item.tier) or 0)>0 and ('\nDrop tier: '..item.tier) or '\nNo tier (cannot be upgraded)')..'\nChance: '..tostring(item.chance)..'%\n\nRight click (or Ctrl + right click): add to autoloot')
      -- OurTibia (03.10.2026): right click / Ctrl + right click adds the item to
      -- the autoloot list (the server refuses gold, valuables and products,
      -- which have their own autoloot options).
      local cid=tonumber(item.cid)
      w.onMouseRelease=function(self,mousePos,mouseButton)
        if mouseButton~=MouseRightButton or not cid then return false end
        if g_game.isOnline() then g_game.getProtocolGame():sendExtendedOpcode(102,'item:add:'..cid) end
        return true
      end
    end
  end
  addEvent(function() if ui('cards') and ui('cards').updateScrollBars then ui('cards'):updateScrollBars() end end)
end
-- 11.10.2026: spawn markers are pooled (hidden, not destroyed) and spawns are
-- indexed once per floor in 128x128 cells, so dragging/zooming the wiki map
-- only looks at the spawns near the camera.
local markerPool={}
local spawnIndex={}
local INDEX_CELL=128
local function clearMarkers()
  for _,marker in ipairs(markers) do marker:hide();markerPool[#markerPool+1]=marker end;markers={}
end
local function getMarker(map)
  local marker=table.remove(markerPool)
  if marker and not marker:isDestroyed() then marker:show();marker:setText('');return marker end
  marker=g_ui.createWidget('UIWidget',map);marker:setSize({width=32,height=36});marker:setPhantom(true)
  local portrait=g_ui.createWidget('UICreature',marker);portrait:setId('mapPortrait');portrait:setPhantom(true)
  for _,edge in ipairs({AnchorLeft,AnchorTop,AnchorRight,AnchorBottom})do portrait:addAnchor(edge,'parent',edge)end
  return marker
end
-- 12.10.2026 (Tobeto): Monsters / Bosses / NPCs are separate groups on the map
local function groupKeys(group)
  if group=='NPCs' then return {'npcs'} elseif group=='Bosses' then return {'bosses'} end
  return {'monsters'}
end
local function buildSpawnIndex(group)
  if spawnIndex[group] then return spawnIndex[group] end
  local index={}
  for _,key in ipairs(groupKeys(group))do
    for _,row in ipairs(catalog[key] or {})do
      for _,spawn in ipairs(row.spawns or (row.x and {row} or {}))do
        if spawn.x and spawn.y and spawn.z then
          local floor=index[spawn.z] or {};index[spawn.z]=floor
          local k=math.floor(spawn.x/INDEX_CELL)*100000+math.floor(spawn.y/INDEX_CELL)
          local list=floor[k] or {};floor[k]=list
          list[#list+1]={row=row,spawn=spawn}
        end
      end
    end
  end
  spawnIndex[group]=index
  return index
end
-- 12.10.2026 (Tobeto): "My position" marks the player on the map
local showPlayerPos=false
local playerMarker
local function updatePlayerMarker()
  local map=ui('worldmap');local p=g_game.getLocalPlayer();local pos=map:getCameraPosition()
  if not showPlayerPos or not p or not pos or p:getPosition().z~=pos.z then if playerMarker then playerMarker:hide() end return end
  if not playerMarker or playerMarker:isDestroyed() then
    playerMarker=g_ui.createWidget('UIWidget',map);playerMarker:setSize({width=34,height=38});playerMarker:setPhantom(true)
    playerMarker:setBorderWidth(1);playerMarker:setBorderColor('#ffd35a')
    local c=g_ui.createWidget('UICreature',playerMarker);c:setId('me');c:setPhantom(true)
    for _,edge in ipairs({AnchorLeft,AnchorTop,AnchorRight,AnchorBottom})do c:addAnchor(edge,'parent',edge)end
  end
  playerMarker:getChildById('me'):setOutfit(p:getOutfit())
  playerMarker:show();playerMarker:raise();map:centerInPosition(playerMarker,p:getPosition())
end
function refreshMapMarkers()
  if not referenceMapActive or not ui('worldmap'):isVisible() then return end
  clearMarkers();updatePlayerMarker()
  if markersHidden and not allSpawns then ui('location'):setText('Spawns hidden');return end
  local map=ui('worldmap');local pos=map:getCameraPosition();if not pos then return end
  local radius=math.max(map:getWidth(),map:getHeight()) / math.max(0.125,2^map:getZoom())
  -- One portrait per monster per map cell (a cell is about one portrait wide),
  -- and never more than 300 on the map.
  local cell=math.max(1,math.floor(36/math.max(0.0625,2^map:getZoom())))
  local seen,count={},0
  local function place(row,spawn)
    local key=row.name..':'..math.floor(spawn.x/cell)..':'..math.floor(spawn.y/cell)
    if count<300 and not seen[key] and spawn.z==pos.z and math.abs(spawn.x-pos.x)<radius and math.abs(spawn.y-pos.y)<radius then
      seen[key]=true;count=count+1
      local marker=getMarker(map)
      local portrait=marker:getChildById('mapPortrait')
      if not OurTibiaArt.creature(portrait,row.outfit or row.look,row.name)then marker:setText('*');marker:setColor('#ffcc33')end
      map:centerInPosition(marker,spawn);markers[#markers+1]=marker
    end
  end
  if allSpawns then
    local floor=buildSpawnIndex(mapGroup)[pos.z] or {}
    local x1,x2=math.floor((pos.x-radius)/INDEX_CELL),math.floor((pos.x+radius)/INDEX_CELL)
    local y1,y2=math.floor((pos.y-radius)/INDEX_CELL),math.floor((pos.y+radius)/INDEX_CELL)
    for cx=x1,x2 do for cy=y1,y2 do
      for _,e in ipairs(floor[cx*100000+cy] or {})do place(e.row,e.spawn) if count>=300 then break end end
    end end
  elseif selected then
    for _,spawn in ipairs(selected.spawns or (selected.x and {selected} or {}))do place(selected,spawn) end
  end
  ui('location'):setText((allSpawns and 'All spawns' or title(selected and selected.name or ''))..' | Floor '..pos.z)
end
function scheduleMapRefresh()
  if mapRefreshEvent then removeEvent(mapRefreshEvent)end
  mapRefreshEvent=scheduleEvent(function()mapRefreshEvent=nil;refreshMapMarkers()end,150)
end
function showAllSpawns(force)
  -- 05.10.2026: the button switches the spawns on and off
  if force==nil then allSpawns=not allSpawns else allSpawns=force end
  local b=ui('showAllSpawnsButton');if b then b:setText(allSpawns and 'Hide all spawns' or 'Show all spawns') end
  -- 11.10.2026 (Tobeto): "Hide all spawns" hides everything, also the monster
  -- that was selected before (its markers stayed, e.g. Sight of Surrender)
  if allSpawns then markersHidden=false;refreshMapMarkers() else markersHidden=true;clearMarkers() end
end
function mapStep(delta)
  if not selected then return end
  local positions=selected.spawns or (selected.x and {selected} or {})
  if #positions==0 then ui('location'):setText('No fixed spawns');clearMarkers();return end
  markersHidden=false
  mapIndex=((mapIndex-1+delta)%#positions)+1
  local pos=positions[mapIndex];if not pos.x then return end
  allSpawns=false;do local b=ui('showAllSpawnsButton');if b then b:setText('Show all spawns') end end
  ui('address'):setText('wiki://map/'..selected.name:gsub(' ','_'))
  ui('worldmap'):setCameraPosition({x=pos.x,y=pos.y,z=pos.z});ui('worldmap'):setZoom(1);refreshMapMarkers()
end
function mapList(group)
  if group then mapGroup=group end
  local panel=ui('mapList');panel:destroyChildren()
  local query=ui('mapSearch'):getText():lower();local rows={}
  for _,b in ipairs({'mapGroupMonsters','mapGroupBosses','mapGroupNPCs'})do local w=ui(b);if w then w:setOn(b=='mapGroup'..mapGroup) end end
  for _,key in ipairs(groupKeys(mapGroup))do
    for _,row in ipairs(catalog[key])do if (#(row.spawns or {})>0 or row.x) and (query=='' or row.name:lower():find(query,1,true))then rows[#rows+1]=row end end
  end
  -- 13.10.2026 (Tobeto): NPCs and bosses alphabetically, every name once (spawns merged),
  -- the whole list (no "N more"), "N spawns" only when there is more than one,
  -- long names end with "..." before the scrollbar and show the full name as a tooltip.
  if mapGroup=='NPCs' or mapGroup=='Bosses' then
    local byName,unique={},{}
    for _,row in ipairs(rows) do
      local key=row.name:lower()
      local spots=row.spawns or (row.x and {row} or {})
      local have=byName[key]
      if not have then
        have={row=row,spawns={}};byName[key]=have;unique[#unique+1]=have
      end
      for _,sp in ipairs(spots) do have.spawns[#have.spawns+1]=sp end
    end
    rows={}
    for _,u in ipairs(unique) do
      local r=u.row
      if #u.spawns~=#(r.spawns or (r.x and {r} or {})) then
        local copy={};for k,v in pairs(r) do copy[k]=v end;copy.spawns=u.spawns;r=copy
      end
      rows[#rows+1]=r
    end
    table.sort(rows,function(a,b) return a.name:lower()<b.name:lower() end)
  else
    table.sort(rows,function(a,b)return WikiFilters.less(a,b,'Power',true)end)
  end
  local measure=g_ui.createWidget('UILabel',panel);measure:setVisible(false);measure:setFont('verdana-11px-monochrome');measure:setTextAutoResize(true)
  local function fitName(text,width)
    measure:setText(text);if measure:getTextSize().width<=width then return text,false end
    local cut=text
    while #cut>1 do cut=cut:sub(1,#cut-1):gsub('%s+$','');measure:setText(cut..'...');if measure:getTextSize().width<=width then break end end
    return cut..'...',true
  end
  local width=math.max(60,(panel:getWidth()>0 and panel:getWidth() or 198)-57-8)
  for _,row in ipairs(rows)do
    local entry=row;local w=g_ui.createWidget('WikiCard',panel);w:setHeight(48)
    local count=#(row.spawns or (row.x and {row} or {}))
    local name,cut=fitName(title(row.name),width)
    if count>1 then w:setText(name..'\n'..count..' spawns') else w:setText(name) end
    if cut then w:setTooltip(title(row.name)) end
    art(w,row)
    w.onClick=function()selected=entry;mapIndex=1;mapStep(0)end
  end
  measure:destroy()
  if allSpawns then refreshMapMarkers()end
end
function mapPlayer()
  local p=g_game.getLocalPlayer();if not p then return end
  showPlayerPos=true
  ui('worldmap'):setCameraPosition(p:getPosition());updatePlayerMarker()
end
function locate()
  if not selected then return end
  if not referenceMapActive then
    -- 04.10.2026: the game minimap is already the full OurTibia map (loaded once
    -- at login), so the wiki uses it directly - no more swapping a 4 MB map file
    -- (that was slow and made the client lag) and no more Mythibia map.
    -- The flag now only means "the wiki map view is open" (spawn markers).
    referenceMapActive=true
  end
  resetView();ui('cards'):hide();ui('worldmap'):show();ui('mapControls'):show()
  filterVisibility(false)
  ui('sidebar'):hide();ui('filterScroll'):hide();ui('scrollbar'):hide();ui('mapBrowser'):show();mapList()
  ui('sidebarTitle'):setText('OurTibia map')
  ui('stats'):setText(title(selected.name)..'\n\n'..#(selected.spawns or {selected})..' known locations\n\nDrag to move the map.\nMouse wheel to zoom.\nUse arrows to switch locations.');mapIndex=1;mapStep(0);ui('page'):setText('Map & Spawns')
end
function renderPage()
  restoreMap()
  resetView();selected=nil;detailMode=nil;ui('address'):setText('wiki://'..tab)
  ui('stats'):hide()
  grid((tab=='monsters' or tab=='bosses') and 2 or 3)
  local first=(page-1)*pageSize+1
  for index=first,math.min(first+pageSize-1,#filtered) do
    local row=filtered[index];local subtitle=row.shortinfo or row.category or row.race or ''
    if row.hp then subtitle='XP '..number(row.exp)..'  HP '..number(row.hp) end
    if tab=='map' then subtitle=#(row.spawns or {row})..' locations' end
    card(row,title(row.name)..'\n'..subtitle,function()selected=row;if tab=='map' then locate() else renderDetail() end end)
  end
  local pages=math.max(1,math.ceil(#filtered/pageSize))
  ui('page'):setText('Page '..page..' / '..pages..' | '..#filtered..' entries')
  ui('previousPage'):setEnabled(page>1);ui('nextPage'):setEnabled(page<pages)
end
-- Must be declared before filter(): as a later `local function` it was an
-- undefined global inside filter() and every wiki page failed to open.
local artCatalogPruned=false
local function pruneCreaturesWithoutArt()
  if artCatalogPruned then return end
  artCatalogPruned=true
  for _,key in ipairs({'monsters','bosses'}) do
    local rows=catalog[key]
    for i=#rows,1,-1 do
      local row=rows[i]
      if not OurTibiaArt.hasCreatureArt(row.outfit or row.look,row.name) then table.remove(rows,i) end
    end
  end
end
function filter()
  if changing or not catalog then return end
  local query=ui('search'):getText():lower();local category=ui('category'):getCurrentOption().text
  pruneCreaturesWithoutArt()
  local source=catalog[tab]
  if tab=='items' then
    source={}
    local gear={Weapons=true,Armors=true,Shields=true,Helmets=true,Legs=true,Boots=true,Amulets=true,Rings=true,['Distance Weapons']=true,Ammunition=true,['Wands and Rods']=true,Equipment=true}
    for _,row in ipairs(catalog.items) do
      local name=(row.name or ''):lower()
      local desc=(table.concat(list(row.desc),' ')..' '..(row.shortinfo or '')):lower()
      local hasStat=desc:find('atk%s*[:+%-]') or desc:find('attack%s*[:+%-]') or desc:find('def%s*[:+%-]') or desc:find('defense%s*[:+%-]') or desc:find('arm%s*[:+%-]') or desc:find('armor%s*[:+%-]') or desc:find('protection%s+') or desc:find('magic level%s*[%+%-]') or desc:find('skill%s+[%a%s]*[%+%-]') or desc:find('speed%s*[%+%-]') or desc:find('capacity%s*[%+%-]') or desc:find('leech%s*[%+%-]') or desc:find('critical%s*[%+%-]') or desc:find('max%s+hp%s*[%+%-]') or desc:find('max%s+mana%s*[%+%-]') or desc:find('hitpoints%s*[%+%-]') or desc:find('mana points%s*[%+%-]')
      if name~='throwing star of sula' and row.category~='Equipment' and (not gear[row.category or ''] or hasStat) then source[#source+1]=row end
    end
  elseif tab=='map' then
    source={};for _,key in ipairs({'monsters','bosses','npcs'}) do for _,r in ipairs(catalog[key]) do source[#source+1]=r end end
  elseif tab=='monsters' or tab=='bosses' then
    source={}
    for _,row in ipairs(catalog[tab]) do if OurTibiaArt.hasCreatureArt(row.outfit or row.look,row.name) then source[#source+1]=row end end
  end
  filtered={}
  local obtaining=ui('obtaining'):getCurrentOption().text
  local resistance=ui('resistance'):getCurrentOption().text
  local tier=ui('tier'):getCurrentOption().text:match('^T(%d+)$')
  local extra={}
  for _,id in ipairs({'weapon','hands','element','weakness','spawnFilter','sort'})do extra[id]=ui(id):getCurrentOption().text end
  extra.minimum=ui('minimum'):getText();extra.maximum=ui('maximum'):getText()
  for _,row in ipairs(source) do
    if (query=='' or row.name:lower():find(query,1,true)) and
      (category=='All' or category==(tab=='map' and row.mapGroup or row.category or row.race or 'NPC')) and
      (tab~='items' or WikiFilters.matches(row,obtaining,resistance,tier)) and WikiFilters.extra(row,extra,tab=='items') then filtered[#filtered+1]=row end
  end
  local sort=ui('sort'):getCurrentOption().text;local descending=ui('direction'):getCurrentOption().text=='Descending'
  table.sort(filtered,function(a,b)return WikiFilters.less(a,b,sort,descending)end)
  page=1;renderPage()
end
local function remember()
  if not catalog or not ui('sort'):getCurrentOption() then return end
  local state={page=page}
  for _,id in ipairs(filterIds)do
    if id~='resetFilters' then state[id]=(id=='search' or id=='minimum' or id=='maximum') and ui(id):getText() or ui(id):getCurrentOption().text end
  end
  tabStates[tab]=state
end
function changeTab(name,reset)
  -- 12.10.2026 (Tobeto): the open tab stays highlighted
  for _,b in ipairs(ui('tabs'):getChildren())do if b.tabKey then b:setOn(b.tabKey==name) end end
  if name=='knowledge' then
    if tab~='knowledge' then remember() end
    restoreMap();tab='knowledge';clearMarkers()
    if itemPage then itemPage:hide() end
    for _,id in ipairs({'sidebar','filterScroll','right','mapBrowser','detailHero','previousPage','nextPage','page'}) do ui(id):hide() end
    ui('knowledge'):show();ui('address'):setText('wiki://knowledge/home')
    WikiKnowledge.open(window)
    return
  end
  ui('knowledge'):hide();ui('previousPage'):show();ui('nextPage'):show();ui('page'):show()
  local fromKnowledge=tab=='knowledge'
  if not reset and not fromKnowledge then remember() end
  changing=true;tab=name;clearMarkers();ui('search'):setText('')
  pageSize=(tab=='monsters' or tab=='bosses') and 14 or 21
  local category=ui('category');category:clearOptions();category:addOption('All')
  local groups={};for _,row in ipairs(catalog[tab] or {}) do groups[row.category or row.race or 'NPC']=true end
  if tab=='map' then groups={Monsters=true,Bosses=true,NPCs=true} end
  local names={};for name in pairs(groups) do names[#names+1]=name end;table.sort(names);for _,name in ipairs(names) do category:addOption(name) end
  local sort=ui('sort');sort:clearOptions()
  local options=tab=='items' and {'Strength','Name','Attack','Defense','Armor','NPC buy price','NPC sell price','Drop chance','Tier','Weight'} or ((tab=='monsters' or tab=='bosses' or tab=='map') and {'Power','Name','Experience','Hitpoints','Strongest hit','Speed','Locations'} or {'Name'})
  for _,option in ipairs(options) do sort:addOption(option) end
  for _,id in ipairs({'obtaining','resistance','tier','weapon','hands','element','weakness','spawnFilter'}) do ui(id):setCurrentOption('All') end
  ui('minimum'):setText('');ui('maximum'):setText('')
  local creatures=tab=='monsters' or tab=='bosses' or tab=='map'
  if tab=='map' then category:setCurrentOption('Monsters') end
  ui('sort'):setCurrentOption(tab=='items' and 'Strength' or creatures and 'Power' or 'Name')
  ui('direction'):setCurrentOption((tab=='items' or creatures) and 'Descending' or 'Ascending')
  local saved=not reset and tabStates[tab]
  if saved then
    for _,id in ipairs(filterIds)do
      if saved[id] then
        if id=='search' or id=='minimum' or id=='maximum' then ui(id):setText(saved[id]) else ui(id):setCurrentOption(saved[id]) end
      end
    end
  end
  changing=false;filter()
  if saved then page=math.max(1,math.min(saved.page,math.max(1,math.ceil(#filtered/pageSize))));renderPage() end
  if tab=='map' then
    for _,row in ipairs(filtered)do if #(row.spawns or {})>0 or row.x then selected=row;locate();showAllSpawns(false);mapPlayer();break end end
    ui('location'):setText('Pick a monster or press Show all spawns')
  end
end
function resetFilters() tabStates[tab]=nil;changeTab(tab,true) end
function back() if tab=='knowledge' then WikiKnowledge.back() else renderPage() end end
function movePage(delta)
  -- 12.10.2026 (Tobeto): on the map the arrows switch the spawn locations
  if tab=='map' and selected and ui('worldmap'):isVisible() then mapStep(delta);return end
  -- on a detail page: go to the previous / next entry
  if selected and detailMode and tab~='map' then
    local at;for i,r in ipairs(filtered) do if r==selected then at=i;break end end
    local nextRow=at and filtered[at+delta]
    if nextRow then selected=nextRow;page=math.floor((at+delta-1)/pageSize)+1;renderDetail(detailMode) end
    return
  end
  page=math.max(1,math.min(math.max(1,math.ceil(#filtered/pageSize)),page+delta));renderPage()
end
-- OurTibia (03.10.2026): open the window first, then the item page. show()
-- rebuilt the item list when it saw no cards (the item page has none), so the
-- page of a newly chosen item was replaced by the list / the previous item.
local function openOn(row)
  if not row or not g_game.isOnline() then return end
  if tab~='items' then changeTab('items') end
  selected=row
  window:show();window:raise();window:focus()
  renderDetail()
end
-- 11.10.2026 (Tobeto): Kill Tracker / Task window -> monster page
function showMonster(name)
  if not name or not g_game.isOnline() then return end
  name=tostring(name):lower()
  for _,key in ipairs({'monsters','bosses'}) do
    for _,r in ipairs(catalog[key] or {}) do
      if tostring(r.name):lower()==name then
        if tab~=key then changeTab(key) end
        selected=r
        window:show();window:raise();window:focus()
        renderDetail()
        return true
      end
    end
  end
  return false
end
-- 12.10.2026 (Tobeto): wiki links in chat. "Link to chat" puts "[w:<tab>:<name>]"
-- into the chat line; a click on it in the chat opens the same wiki page.
function linkToChat()
  local kind,name=tab,selected and selected.name
  if kind=='knowledge' then return end
  if not name then return end
  if kind=='map' then kind=(selected.mapGroup=='NPCs') and 'npc' or 'map' end
  local token='[w:'..kind..':'..title(name)..']'
  local f=modules.game_myotshud and modules.game_myotshud.ItemForge
  if f and f.insertLink then f.insertLink(token) else g_window.setClipboardText(token) end
end
function openLink(kind,name)
  if not kind or not name or not g_game.isOnline() then return end
  local low=tostring(name):lower()
  if kind=='monsters' or kind=='bosses' then return showMonster(low) end
  local function findIn(key) for _,r in ipairs(catalog[key] or {}) do if tostring(r.name):lower()==low then return r end end end
  if kind=='items' then
    local r=findIn('items');if r then openOn(r) end;return
  end
  local r=(kind=='npc') and findIn('npcs') or (findIn('monsters') or findIn('bosses') or findIn('npcs'))
  if not r then return end
  window:show();window:raise();window:focus()
  if tab~='map' then changeTab('map') end
  selected=r;mapIndex=1;locate()
end
-- 13.10.2026 (Tobeto): short info shown when the mouse is on a wiki / map link in the chat
function linkSummary(link)
  if type(link)~='table' or not catalog then return nil end
  local low=tostring(link.name or ''):lower()
  local function findIn(key) for _,r in ipairs(catalog[key] or {}) do if tostring(r.name):lower()==low then return r end end end
  if link.map then
    return title(link.name or '')..'\nPosition: '..link.x..', '..link.y..', '..link.z..'\nClick: show it on the wiki map'
  end
  local kind=link.wiki
  if kind=='items' then
    local r=findIn('items');if not r then return nil end
    local lines={title(r.name)}
    if r.category then lines[#lines+1]=r.category end
    for _,d in ipairs(list(r.desc)) do lines[#lines+1]=d end
    local best;for npc,price in pairs(list(r.sellTo)) do if not best or price>best[2] then best={npc,price} end end
    if best then lines[#lines+1]='Sell to '..best[1]..': '..number(best[2])..' gold' end
    local drops=#list(r.droppedBy);if drops>0 then lines[#lines+1]='Dropped by '..drops..' creature'..(drops==1 and '' or 's') end
    lines[#lines+1]='Click: open the wiki page';return table.concat(lines,'\n')
  end
  local r=findIn('monsters') or findIn('bosses')
  if r and kind~='npc' then
    return title(r.name)..'\nHitpoints: '..number(r.hp)..'   Experience: '..number(r.exp)..'\n'..(#list(r.spawns)>0 and (#list(r.spawns)..' spawn locations') or 'No fixed spawns')..'\nClick: open the wiki page'
  end
  r=findIn('npcs')
  if r then return title(r.name)..'\nNPC'..(tostring(r.traveling)=='true' and ' (travels between towns)' or '')..'\nClick: show on the wiki map' end
  return nil
end
-- 12.10.2026: "where is <npc>" chat link -> the wiki map at the NPC's place
function showMapAt(link)
  if not link or not link.x or not g_game.isOnline() then return end
  local name=tostring(link.name or ''):lower()
  local base
  for _,r in ipairs(catalog.npcs or {}) do if tostring(r.name):lower()==name then base=r;break end end
  local row={name=link.name,x=link.x,y=link.y,z=link.z,look=base and base.look,outfit=base and base.outfit,mapGroup='NPCs'}
  window:show();window:raise();window:focus()
  if tab~='map' then changeTab('map') end
  selected=row;mapIndex=1;locate()
  return true
end
function showReferenceItem(sid)
  if not sid then return end
  for _,r in ipairs(catalog.items) do if r.sid==sid then openOn(r);return end end
end
function showItem(cid)
  if not cid or cid==0 then return end
  for _,r in ipairs(catalog.items) do if r.cid==cid then openOn(r);return end end
end
local preloadEvent
local function onWikiGameStart()
  -- Do not build item cards during the login transition. At that point the
  -- 10.98 DAT can still be loading, which permanently leaves placeholder
  -- thumbnails in cards created too early. `show` builds the page after the
  -- player opens the wiki, when item sprites are available.
  tabStates={};filtered={};page=1
  if window then ui('cards'):destroyChildren() end
  -- OurTibia (02.10.2026): build the wiki in the background shortly after
  -- login (the 10.98 sprites are loaded by then), so opening it is instant
  -- instead of building every card on the first click.
  if preloadEvent then removeEvent(preloadEvent) end
  preloadEvent=scheduleEvent(function()
    preloadEvent=nil
    if not g_game.isOnline() or not window or window:isVisible() then return end
    if #ui('cards'):getChildren()==0 and tab~='knowledge' then pcall(changeTab,'items',true) end
  end,4000)
end
function counts() local result={};for key,rows in pairs(catalog) do result[key]=#rows end;return result end
function init()
  catalog=json.decode(g_resources.readFileContents('/data/myots/compendium.json'));spawnIndex={}
  for key,name in pairs({monsters='Monsters',bosses='Bosses',npcs='NPCs'}) do for _,row in ipairs(catalog[key]) do row.mapGroup=name end end
  window=g_ui.displayUI('wiki');window:hide()
  for _,npc in ipairs(catalog.npcs) do npcsByName[npc.name:lower()]=npc end
  for _,section in ipairs({'monsters','bosses'}) do
    for _,creature in ipairs(catalog[section]) do
      for _,drop in ipairs(list(creature.loot)) do
        sourcesByItem[drop.sid]=sourcesByItem[drop.sid] or {}
        table.insert(sourcesByItem[drop.sid],{name=creature.name,creature=creature,section=section,kind=section=='bosses' and 'Boss' or 'Monster',tier=drop.tier,chance=tonumber(drop.chance) or -1})
      end
    end
  end
  -- OurTibia (02.10.2026): distance fighting needed for ammunition (server ids).
  local ammoRequirement={[2546]=70,[7363]=72,[7364]=75,[7365]=80,[7838]=80,[7839]=80,[7840]=80,[7850]=80,[15649]=80,[15648]=85,[2547]=85,[18436]=93,[18437]=95,[6529]=95,[18304]=100,[18435]=100,[28413]=100}
  for _,row in ipairs(catalog.items) do
    local need=ammoRequirement[row.sid]
    if need and row.category=='Ammunition' then
      row.desc=list(row.desc);table.insert(row.desc,1,'Requires distance fighting '..need..' (equipment bonuses count).')
      row.shortinfo=((row.shortinfo or '')~='' and row.shortinfo..', ' or '')..'Dist '..need..'+'
    end
  end
  for _,row in ipairs(catalog.items) do WikiFilters.prepare(row,sourcesByItem[row.sid]) end
  itemPage=g_ui.loadUI('itemdetail',window);itemPage:hide()
  for _,entry in ipairs({{'sourceFilter',{'All','Monster','Boss'}},{'sourceSort',{'Chance','Tier','Name'}},{'sourceOrder',{'Descending','Ascending'}}}) do
    local combo=detailUI(entry[1]);for _,option in ipairs(entry[2]) do combo:addOption(option) end;combo.onOptionChange=renderItemSources
  end

  local tabIcons={items='/images/icons/icon_sword',monsters=iconRoot..'melee',bosses='/images/icons/icon-bosstracker-widget',knowledge='/images/topbuttons/spelllist',map='/images/topbuttons/questlog'}
  for _,entry in ipairs(tabs) do local key=entry[1];local b=g_ui.createWidget('WikiTab',ui('tabs'));b:setWidth(164);b:setHeight(36);b:setText(entry[2]);b:setTextOffset({x=12,y=0});local icon=g_ui.createWidget('UIWidget',b);icon:setSize({width=22,height=22});icon:addAnchor(AnchorLeft,'parent',AnchorLeft);icon:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter);icon:setMarginLeft(7);icon:setImageSource(tabIcons[key]);icon:setPhantom(true);b.tabKey=key;b.onClick=function()changeTab(key)end end
  for _,name in ipairs({'All','Monsters','Bosses','Quests','NPC sellers','NPC buyers'}) do ui('obtaining'):addOption(name) end
  ui('resistance'):addOption('All');for _,name in ipairs(elements) do ui('resistance'):addOption(name) end
  ui('tier'):addOption('All');for n=1,15 do ui('tier'):addOption('T'..n) end
  ui('sort'):setTooltip('NPC buy price: cheapest purchase from an NPC. NPC sell price: best sale to an NPC. Drop chance: highest known source chance. Missing values stay last.')
  ui('tier'):setTooltip('Tier available from the selected monster, boss or quest source. Tier belongs to the drop source, not permanently to the item type.')
  ui('resistance'):setTooltip('Positive base resistance. Random rarity bonuses are not base item properties.')
  ui('obtaining').onOptionChange=filter;ui('resistance').onOptionChange=filter;ui('tier').onOptionChange=filter

  for _,name in ipairs({'Ascending','Descending'}) do ui('direction'):addOption(name) end
  ui('search').onTextChange=filter;ui('category').onOptionChange=filter;ui('sort').onOptionChange=filter;ui('direction').onOptionChange=filter
  for _,entry in ipairs({{'weapon',{'All','Sword','Axe','Club','Bow','Crossbow','Wand','Rod'}},{'hands',{'All','One-handed','Two-handed'}},{'element',{'All','Fire','Ice','Earth','Energy','Holy','Death'}},{'weakness',{'All','Physical','Energy','Earth','Fire','Ice','Holy','Death'}},{'spawnFilter',{'All','With spawns','Without spawns'}}})do
    for _,option in ipairs(entry[2])do ui(entry[1]):addOption(option)end
    ui(entry[1]).onOptionChange=filter
  end
  ui('minimum').onTextChange=filter;ui('maximum').onTextChange=filter
  ui('minimum'):setTooltip('Minimum value of the selected Sort by statistic. Leave empty for no limit.')
  ui('maximum'):setTooltip('Maximum value of the selected Sort by statistic. Leave empty for no limit.')
  -- 10.10.2026: the tooltip describes the statistic that is selected now (it always said "Power").
  local sortTips={
    Power='Power: experience, then hitpoints.',Name='Name: alphabetical order.',Experience='Experience the creature gives.',
    Hitpoints='Hitpoints of the creature.',['Strongest hit']='The strongest attack of the creature.',Speed='Movement speed of the creature.',
    Locations='Number of spawn locations on the map.',Strength='Strength: overall power of the item (attack, defense, armor and bonuses).',
    Attack='Attack of the weapon.',Defense='Defense of the item.',Armor='Armor of the item.',['NPC buy price']='Price an NPC sells the item for.',
    ['NPC sell price']='Price an NPC pays for the item.',['Drop chance']='Best drop chance from a monster.',Tier='Item tier (T1-T15).',Weight='Weight of the item.'}
  local function updateSortTip()
    local option=ui('sort'):getCurrentOption();local name=option and option.text or ''
    ui('sort'):setTooltip((sortTips[name] or name)..' Numeric filters (minimum / maximum) use this statistic. Missing values are last.')
  end
  ui('sort').onOptionChange=function(...) updateSortTip();return filter(...) end
  updateSortTip()
  ui('category').onOptionChange=function()
    if not changing and tab=='items' then
      changing=true
      local c=ui('category'):getCurrentOption().text
      local attackCategories={Weapons=true,['Distance Weapons']=true,Ammunition=true,['Wands and Rods']=true}
      ui('sort'):setCurrentOption(attackCategories[c] and 'Attack' or c=='Shields' and 'Defense' or (c=='Armors' or c=='Helmets' or c=='Legs' or c=='Boots') and 'Armor' or 'Strength')
      ui('direction'):setCurrentOption('Descending');changing=false
    end
    filter()
  end
  for _,option in ipairs({'Chance','Tier','Name'})do ui('lootSort'):addOption(option)end
  for _,option in ipairs({'Descending','Ascending'})do ui('lootOrder'):addOption(option)end
  ui('lootSort').onOptionChange=function()lootSort=ui('lootSort'):getCurrentOption().text;if selected then renderDetail('loot')end end
  ui('lootOrder').onOptionChange=function()lootDescending=ui('lootOrder'):getCurrentOption().text=='Descending';if selected then renderDetail('loot')end end
  ui('mapSearch').onTextChange=function() if mapListEvent then removeEvent(mapListEvent) end;mapListEvent=scheduleEvent(function() mapListEvent=nil;mapList() end,250) end
  connect(ui('worldmap'),{onCameraPositionChange=scheduleMapRefresh,onZoomChange=scheduleMapRefresh})
  ui('worldmap'):disableAutoWalk()
  button=modules.client_topmenu.addRightGameButton('myotsWiki','Game Wiki','/images/topbuttons/myots_wiki',toggle)
  connect(g_game,{onGameEnd=hide,onGameStart=onWikiGameStart})
  modules.game_interface.addMenuHook('myotsWiki','Show in Wiki',function(_,lookThing,useThing)local item=useThing or lookThing;if item then showItem(item:getId()) end end,function(_,lookThing,useThing,creatureThing)if creatureThing then return false end;local item=useThing or lookThing;return item and item:isItem() and not item:isGround() and item:isPickupable()end)
end
function terminate()
  if preloadEvent then removeEvent(preloadEvent);preloadEvent=nil end
  if WikiKnowledge and WikiKnowledge.terminate then WikiKnowledge.terminate() end
  if mapRefreshEvent then removeEvent(mapRefreshEvent)end
  disconnect(ui("worldmap"),{onCameraPositionChange=scheduleMapRefresh,onZoomChange=scheduleMapRefresh})
  restoreMap()
  modules.game_interface.removeMenuHook('myotsWiki','Show in Wiki');disconnect(g_game,{onGameEnd=hide,onGameStart=onWikiGameStart});clearMarkers()
  if button then button:destroy() end;if window then window:destroy() end
end
-- 13.10.2026 (Tobeto): a map link in the chat ("where is <npc>") shows a small map of the place
-- as its tooltip (name on top, the spot marked in the middle) - like the item tooltip.
local linkMapTip
function showLinkMap(link,mousePos)
  if type(link)~='table' or not link.map or not tonumber(link.x) then return hideLinkMap() end
  if not linkMapTip or linkMapTip:isDestroyed() then
    linkMapTip=g_ui.createWidget('UIWidget',rootWidget);linkMapTip:setId('ourLinkMapTip')
    linkMapTip:setPhantom(true);linkMapTip:setFocusable(false);linkMapTip:setSize({width=240,height=214})
    linkMapTip:setBackgroundColor('#1c1c1cf2');linkMapTip:setBorderWidth(1);linkMapTip:setBorderColor('#5a5a5a')
    local name=g_ui.createWidget('UILabel',linkMapTip);name:setId('name');name:setPhantom(true)
    name:addAnchor(AnchorTop,'parent',AnchorTop);name:addAnchor(AnchorLeft,'parent',AnchorLeft);name:addAnchor(AnchorRight,'parent',AnchorRight)
    -- 14.10.2026 (Tobeto): looks like the item tooltip - name, a line, then the map (no coordinates)
    name:setMarginTop(8);name:setMarginLeft(10);name:setMarginRight(10);name:setHeight(14);name:setFont('Verdana Bold-11px');name:setColor('#ffffff')
    local line=g_ui.createWidget('UIWidget',linkMapTip);line:setId('line');line:setPhantom(true);line:setHeight(1);line:setBackgroundColor('#555555')
    line:addAnchor(AnchorTop,'name',AnchorBottom);line:addAnchor(AnchorLeft,'parent',AnchorLeft);line:addAnchor(AnchorRight,'parent',AnchorRight)
    line:setMarginTop(5);line:setMarginLeft(10);line:setMarginRight(10)
    local map=g_ui.createWidget('UIMinimap',linkMapTip);map:setId('map');map:setPhantom(true)
    map:addAnchor(AnchorTop,'line',AnchorBottom);map:addAnchor(AnchorLeft,'parent',AnchorLeft);map:addAnchor(AnchorRight,'parent',AnchorRight);map:addAnchor(AnchorBottom,'parent',AnchorBottom)
    map:setMarginTop(6);map:setMarginLeft(10);map:setMarginRight(10);map:setMarginBottom(22)
    map:setBorderWidth(1);map:setBorderColor('#000000')
    local mark=g_ui.createWidget('UIWidget',linkMapTip);mark:setId('mark');mark:setPhantom(true);mark:setSize({width=11,height=11})
    mark:addAnchor(AnchorHorizontalCenter,'map',AnchorHorizontalCenter);mark:addAnchor(AnchorVerticalCenter,'map',AnchorVerticalCenter)
    mark:setBorderWidth(2);mark:setBorderColor('#ffff00');mark:setSize({width=13,height=13})
    -- 14.10.2026 (GM Nobody): an NPC is shown with its outfit (the yellow square only when there is no outfit)
    local who=g_ui.createWidget('UICreature',linkMapTip);who:setId('who');who:setPhantom(true);who:setSize({width=40,height=40})
    who:addAnchor(AnchorHorizontalCenter,'map',AnchorHorizontalCenter);who:addAnchor(AnchorVerticalCenter,'map',AnchorVerticalCenter)
    who:setMarginLeft(-8);who:setMarginTop(-8);who:hide()
    local pos=g_ui.createWidget('UILabel',linkMapTip);pos:setId('pos');pos:setPhantom(true)
    pos:addAnchor(AnchorBottom,'parent',AnchorBottom);pos:addAnchor(AnchorLeft,'parent',AnchorLeft);pos:addAnchor(AnchorRight,'parent',AnchorRight)
    pos:setMarginBottom(6);pos:setMarginLeft(10);pos:setHeight(12);pos:setFont('verdana-9px-rounded');pos:setColor('#8fb8ff')
  end
  local key=link.x..':'..link.y..':'..link.z
  if linkMapTip.ourKey~=key then
    linkMapTip.ourKey=key
    linkMapTip:getChildById('name'):setText(title(link.name or ''))
    linkMapTip:getChildById('pos'):setText('Click: open the wiki map')
    local map=linkMapTip:getChildById('map')
    pcall(function() map:setCameraPosition({x=tonumber(link.x),y=tonumber(link.y),z=tonumber(link.z)}) end)
    pcall(function() map:setZoom(1) end)
    local look
    local low=tostring(link.name or ''):lower()
    for _,r in ipairs(catalog and catalog.npcs or {}) do if tostring(r.name):lower()==low then look=r.outfit or r.look;break end end
    local who=linkMapTip:getChildById('who');local mark=linkMapTip:getChildById('mark')
    if look and tonumber(look.type) and look.type>0 then
      local ok=pcall(function() who:setOutfit({type=look.type,head=look.head or 0,body=look.body or 0,legs=look.legs or 0,feet=look.feet or 0,addons=look.addons or 0}) end)
      if ok then who:show();mark:hide() else who:hide();mark:show() end
    else who:hide();mark:show() end
  end
  local m=mousePos or g_window.getMousePosition()
  local size=linkMapTip:getSize();local root=rootWidget:getSize()
  local x=m.x+14;local y=m.y-size.height-8
  if x+size.width>root.width then x=m.x-size.width-14 end
  if y<0 then y=m.y+18 end
  linkMapTip:setPosition({x=x,y=y});linkMapTip:show();linkMapTip:raise()
  return true
end
function hideLinkMap()
  if linkMapTip and not linkMapTip:isDestroyed() then linkMapTip:hide() end
end
