-- Mythibia-style item tooltip (1:1 layout taken from the live Mythibia client, 30.09.2026).
-- Normal view: title, icon + base stats + weight, tier stars, native abilities,
-- OurTibia (04.10.2026): option "Always show detailed item tooltips" - then the
-- detailed view is the default and holding Shift shows the short one.
function ourDetailed()
  local shift=g_keyboard.isShiftPressed()
  if g_settings.getBoolean('ourDetailedTooltips') then return not shift end
  return shift
end
-- rarity attributes, "Right click to identify!", SHIFT hint.
-- Shift view: adds Source, attribute ranges and the best NPC sell offer box.
ItemTooltip={}
local T=ItemTooltip
local panel,hovered,linkData
local WIDTH=250
T.rarityColors={[1]='#b4b4b4',[2]='#6464d2',[3]='#b43cc8',[4]='#c8c832',[5]='#e11c1c',[6]='#ff8a00'} -- 13.10.2026: Mythic red like the frames
local ATTR_COLOR='#f0a030'
-- Client item id -> distance fighting needed (same values as the server).
T.ammoRequirement={[3449]=70,[7363]=72,[7364]=75,[7365]=80,[761]=80,[762]=80,[763]=80,[774]=80,[14252]=80,[14251]=85,[3450]=85,[16142]=93,[16143]=95,[6528]=95,[15793]=100,[16141]=100,[23741]=100}
local RANGE_COLOR='#a8a8a8'

local function titleCase(s)
  return (tostring(s or ''):gsub("(%a)([%w']*)",function(a,b) return a:upper()..b end))
end
-- 14.10.2026 (owner): the same colours as in the Loot channel (real Tibia value bands)
local function priceColor(value)
  local band=ourValueBand and ourValueBand(value) or 'grey'
  return (ItemsDatabase and ItemsDatabase.rarityColors[band]) or '#aaaaaa'
end
function T.eligible(widget)
  if not widget or type(widget.getItem)~='function' or widget:isVirtual() then return false end
  local item=widget:getItem();if not item then return false end
  local pos=item:getPosition()
  return pos~=nil and pos.x==65535
end
local function add(parent,kind,height)
  local w=g_ui.createWidget(kind or 'UIWidget',parent)
  w:setPhantom(true);w:setFocusable(false)
  if height then w:setHeight(height) end
  return w
end
local function label(parent,text,color,font)
  local w=add(parent,'UILabel')
  w:setFont(font or 'verdana-11px-rounded');w:setColor(color or '#ffffff')
  w:setTextAlign(AlignLeft);w:setTextWrap(true);w:setWidth(WIDTH-20)
  w:setTextVerticalAutoResize(true);w:setText(text)
  return w
end
local function separator(parent)
  add(parent,'UIWidget',5)
  local line=add(parent,'UIWidget',1)
  line:setBackgroundColor('#555555');line:setWidth(WIDTH-20)
  add(parent,'UIWidget',5)
  return line
end
local function spacer(parent,h) return add(parent,'UIWidget',h) end
local function baseLine(record,info)
  if record and record.dist then
    -- 07.10.2026: bows/crossbows - one total line (base + rarity bonus), taken from the server.
    local parts={'Atk +'..(tonumber(record.atk) or 0)}
    if tonumber(record.hit) then parts[#parts+1]='Hit% +'..record.hit end
    if tonumber(record.range) and tonumber(record.range)>0 then parts[#parts+1]='Range '..record.range end
    return table.concat(parts,', ')
  end
  if record then
    local parts={}
    if record.atk then parts[#parts+1]='Atk: '..record.atk end
    if record.def then parts[#parts+1]='Def: '..record.def end
    if record.arm then parts[#parts+1]='Arm: '..record.arm end
    if #parts>0 then return table.concat(parts,', ') end
  end
  return info and info.b or nil
end

function T.build(widget)
  local item=widget:getItem();if not item then return nil end
  local record=RarityFrames and RarityFrames.record and RarityFrames.record(item) or nil
  return T.buildData(item:getId(),item:getCount(),record)
end
-- OurTibia (03.10.2026): the tooltip is built from plain data so chat item
-- links ("Link to chat") show the same window as items in the backpack.
function T.buildData(itemId,count,record,footer)
  local shift=ourDetailed()
  local info=OurItemInfo and OurItemInfo[itemId] or nil
  count=count or 1
  local item={getCount=function() return count end,getId=function() return itemId end}
  if panel then panel:destroy() end
  panel=g_ui.createWidget('UIWidget',rootWidget)
  panel:setId('ourItemTooltip');panel:setPhantom(true);panel:setFocusable(false)
  panel:setBackgroundColor('#1c1c1cf2');panel:setBorderWidth(1);panel:setBorderColor('#5a5a5a')
  panel:setWidth(WIDTH);panel:setPadding(10);panel:setPaddingTop(8);panel:setPaddingBottom(8)
  local layout=UIVerticalLayout.create(panel);layout:setFitChildren(true);panel:setLayout(layout)

  local name=record and record.n or (info and info.n) or 'Item'
  if item:getCount()>1 and not record then name=item:getCount()..' '..name end
  name=name:lower() -- 07.10.2026: item names in small letters (the rarity colour stays)
  if record and tonumber(record.up) and tonumber(record.up)>0 then name=name..' +'..record.up end
  label(panel,name,'#ffffff','Verdana Bold-11px')
  spacer(panel,6)

  local head=add(panel,'UIWidget',34)
  local icon=add(head,'UIItem');icon:setVirtual(true);icon:setSize({width=34,height=34})
  icon:addAnchor(AnchorLeft,'parent',AnchorLeft);icon:addAnchor(AnchorTop,'parent',AnchorTop)
  icon:setItemId(item:getId());icon:setBackgroundColor('#2a2a2a')
  -- 13.10.2026 (Tobeto): the tooltip icon has the same rarity frame as the item in the backpack
  if record and tonumber(record.r) and record.r>=1 and record.r<=6 then
    icon:setBorderWidth(0);icon:setBackgroundColor('#00000000');icon:setImageSource('/game_myotshud/images/slot_frame_'..record.r)
  else
    icon:setBorderWidth(1);icon:setBorderColor(record and T.rarityColors[record.r] or '#6a6a6a')
  end
  local lines={}
  local base=baseLine(record,info);if base then lines[#lines+1]=base end
  local weight=record and (tonumber(record.cw) or tonumber(record.w)) or (info and info.w and info.w*math.max(1,item:getCount())) or nil
  if weight then lines[#lines+1]=string.format('%.2f oz',weight) end
  local stats=add(head,'UILabel');stats:setFont('verdana-11px-rounded');stats:setColor('#ffffff')
  -- 07.10.2026: the text next to the icon wraps inside the tooltip (long descriptions went past the frame)
  stats:setTextAlign(AlignLeft);stats:setTextWrap(true);stats:setWidth(WIDTH-20-44)
  stats:setTextVerticalAutoResize(true);stats:setText(table.concat(lines,'\n'))
  stats:addAnchor(AnchorLeft,'prev',AnchorRight);stats:setMarginLeft(10)
  stats:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter)
  head:setHeight(math.max(34,stats:getHeight()))

  if shift and record and record.src then
    spacer(panel,6);label(panel,'Source: '..titleCase(record.src),'#d8d8d8','verdana-9px-rounded')
  end
  -- 10.10.2026 (Tobeto): ordinary equipment gets its tier from the server too
  -- (drop / quest tier, record without rarity) - stars plus "Tier N".
  if record and tonumber(record.t) then
    spacer(panel,shift and record.src and 2 or 6)
    local row=add(panel,'UIWidget',12)
    -- Tier 1-10: gold stars; tier 11-15: five blue stars (tier-10 filled).
    local tier=math.max(0,math.min(15,tonumber(record.t)))
    local blue=tier>10;local slots=blue and 5 or 10;local stars=blue and tier-10 or tier
    for i=1,slots do
      local s=add(row,'UIWidget');s:setSize({width=9,height=9})
      s:setImageSource(i<=stars and '/images/game/prey/prey_star' or '/images/game/prey/prey_nostar')
      if blue and i<=stars then s:setImageColor('#4fa8ff') end
      if i==1 then s:addAnchor(AnchorLeft,'parent',AnchorLeft) else s:addAnchor(AnchorLeft,'prev',AnchorRight);s:setMarginLeft(1) end
      s:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter)
    end
    -- 14.10.2026 (GM Nobody): no "Tier N" text next to the stars - it was the same information twice
  end

  if info and info.a and #info.a>0 then
    -- with server data (record) the Atk / Hit% lines are already in the total line above
    local extra={}
    for _,line in ipairs(info.a) do
      if not (record and record.dist and (line:find('^Atk') or line:find('^Hit%%'))) then extra[#extra+1]=line end
    end
    if #extra>0 then
      separator(panel)
      for _,line in ipairs(extra) do label(panel,line,'#ffffff') end
    end
  end
  -- OurTibia (02.10.2026): distance fighting needed to shoot this ammunition.
  local ammo=T.ammoRequirement[item:getId()]
  if ammo then
    separator(panel)
    label(panel,'Requires distance fighting '..ammo..' (equipment bonuses count).','#ff9c3a')
  end
  if record and record.aff and #record.aff>0 then
    separator(panel)
    for index,a in ipairs(record.aff) do
      label(panel,tostring(a.l)..' '..tostring(a.v),ATTR_COLOR)
      if shift then
        label(panel,'('..tostring(a.rg)..')',RANGE_COLOR)
        if a.ds then label(panel,tostring(a.ds),'#8f8f8f','verdana-9px-rounded') end
        if index<#record.aff then spacer(panel,8) end
      end
    end
  end
  if record and record.r==0 then
    separator(panel)
    label(panel,'Right click to identify!','#ffff00')
  end

  if footer then separator(panel);label(panel,footer,'#8fb8ff','verdana-9px-rounded') end
  separator(panel)
  if shift then
    local offer=info and info.s
    if offer then
      local color=priceColor(tonumber(offer[2]) or 0)
      local box=add(panel,'UILabel',20)
      box:setWidth(WIDTH-20);box:setFont('verdana-11px-rounded');box:setColor('#ffffff')
      box:setTextAlign(AlignCenter);box:setBorderWidth(1);box:setBorderColor(color)
      box:setBackgroundColor(color..'55')
      box:setText('['..offer[1]..'] - '..offer[2]..' gold')
    else
      label(panel,'No NPC buys this item.','#8a8a8a')
    end
  else
    local row=add(panel,'UIWidget',16)
    local key=add(row,'UILabel');key:setFont('Verdana Bold-10px');key:setText('SHIFT')
    key:setColor('#1c1c1c');key:setBackgroundColor('#f0f0f0');key:setTextAlign(AlignCenter)
    key:setSize({width=38,height=15});key:addAnchor(AnchorLeft,'parent',AnchorLeft);key:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter)
    local text=add(row,'UILabel');text:setFont('verdana-11px-rounded');text:setColor('#ffffff')
    text:setText('Show additional information');text:setTextAutoResize(true)
    if text:getWidth()>WIDTH-20-46 then text:setFont('verdana-9px-rounded') end
    text:addAnchor(AnchorLeft,'prev',AnchorRight);text:setMarginLeft(8);text:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter)
  end
  return panel
end

function T.place()
  if not panel or not hovered then return end
  local rect=hovered:getRect();local root=rootWidget:getSize()
  local height=panel:getHeight()
  if linkData then
    -- chat link: next to the mouse, above the chat line
    local m=g_window.getMousePosition()
    local x=math.max(0,math.min(m.x+16,root.width-WIDTH))
    local y=math.max(0,math.min(m.y-height-8,root.height-height))
    panel:setPosition({x=x,y=y});panel:raise();return
  end
  local x=rect.x-WIDTH-4
  if x<0 then x=rect.x+rect.width+4 end
  x=math.max(0,math.min(x,root.width-WIDTH))
  local y=math.max(0,math.min(rect.y-4,root.height-height-4))
  panel:setPosition({x=x,y=y});panel:raise()
  -- 07.10.2026: the layout grows the panel a frame later - place it again with the real size
  if not T.replaceEvent then
    T.replaceEvent=addEvent(function()
      T.replaceEvent=nil
      if not panel or not hovered then return end
      local h=panel:getHeight();local r=rootWidget:getSize();local pos=panel:getPosition()
      local ny=math.max(0,math.min(pos.y,r.height-h-4))
      local nx=math.max(0,math.min(pos.x,r.width-panel:getWidth()))
      if ny~=pos.y or nx~=pos.x then panel:setPosition({x=nx,y=ny}) end
    end)
  end
end
local shiftWatch,shiftState
local function stopWatch() if shiftWatch then removeEvent(shiftWatch);shiftWatch=nil end end
function T.show(widget)
  if not T.eligible(widget) or g_ui.getDraggingWidget() then return T.hide() end
  hovered=widget;linkData=nil
  shiftState=ourDetailed()
  local ok,err=pcall(T.build,widget)
  if not ok then g_logger.error('ItemTooltip: '..tostring(err));return T.hide() end
  -- Layout sizes are computed on the next frame; place now and again after it.
  T.place();addEvent(T.place)
  -- Poll Shift while visible: a root key binding can be taken over by other
  -- modules (the tooltip then never expanded). Polling is independent of that.
  if not shiftWatch then
    shiftWatch=cycleEvent(function()
      if not hovered or not panel then return stopWatch() end
      if not hovered:isHovered() then return T.hide() end
      local now=ourDetailed()
      if now~=shiftState then if T.redraw then T.redraw() else T.show(hovered) end end
    end,50)
  end
end
-- Tooltip for any widget (chat link): data = {cid=, count=, record=, footer=}.
function T.showData(widget,data)
  if not widget or not data then return T.hide() end
  hovered=widget;linkData=data;data.widget=widget
  shiftState=ourDetailed()
  local ok,err=pcall(T.buildData,data.cid,data.count or 1,data.record,data.footer)
  if not ok then g_logger.error('ItemTooltip(link): '..tostring(err));return T.hide() end
  -- the height is known only after the layout ran: place it again a few times
  T.place();addEvent(T.place);scheduleEvent(T.place,30);scheduleEvent(T.place,120)
  if not shiftWatch then
    shiftWatch=cycleEvent(function()
      if not hovered or not panel then return stopWatch() end
      if not hovered:isHovered() then return T.hide() end
      local now=ourDetailed()
      if now~=shiftState then T.redraw() else T.place() end
    end,50)
  end
  data.widget=widget
end
function T.isShowingFor(widget) return panel~=nil and hovered==widget end
function T.redraw() if linkData and hovered==linkData.widget then T.showData(hovered,linkData) elseif hovered then T.show(hovered) end end
function T.hide(widget)
  if widget and widget~=hovered then return end
  hovered=nil;linkData=nil;stopWatch()
  if panel then panel:destroy();panel=nil end
end
function T.refresh() if hovered and hovered:isHovered() then T.redraw() else T.hide() end end
-- Shift key handling is bound once in rarity_frames.lua (refreshTooltips).
function T.init() connect(g_game,{onGameEnd=T.hide}) end
function T.terminate() disconnect(g_game,{onGameEnd=T.hide});T.hide() end
