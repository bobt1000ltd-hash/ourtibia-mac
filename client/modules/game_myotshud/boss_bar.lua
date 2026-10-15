-- OurTibia (13.10.2026, owner): boss health bar at the top of the game window
-- (world boss, daily boss, Nemesis boss, event boss and every other boss on the
-- screen). Portrait, name and hit points - no timer. Data from the server
-- (HUD opcode, kind = 'bossbar').
OurBossBar={}
local BB=OurBossBar
local panel,portrait,nameLabel,fill,hpLabel
local cur={}
local BAR_W=236

local function fmt(n)
  local s=tostring(math.floor(n or 0))
  while true do local k;s,k=s:gsub('^(%d+)(%d%d%d)','%1,%2');if k==0 then break end end
  return s
end

local function make(class,parent)
  local w=g_ui.createWidget(class,parent);w:setPhantom(true);w:setFocusable(false);return w
end

local function ensure()
  if panel and not panel:isDestroyed() then return panel end
  local map=modules.game_interface and modules.game_interface.getMapPanel and modules.game_interface.getMapPanel()
  if not map then return nil end
  panel=make('UIWidget',map);panel:setId('ourBossBar')
  panel:addAnchor(AnchorTop,'parent',AnchorTop);panel:addAnchor(AnchorHorizontalCenter,'parent',AnchorHorizontalCenter)
  panel:setMarginTop(8);panel:setSize({width=BAR_W+74,height=58})
  panel:setBackgroundColor('#151210ee');panel:setBorderWidth(1);panel:setBorderColor('#8c7444')
  -- portrait
  local frame=make('UIWidget',panel);frame:setSize({width=50,height=50})
  frame:addAnchor(AnchorLeft,'parent',AnchorLeft);frame:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter)
  frame:setMarginLeft(4);frame:setBackgroundColor('#050505');frame:setBorderWidth(2);frame:setBorderColor('#c8a04a')
  portrait=make('UICreature',frame);portrait:setSize({width=46,height=46})
  portrait:addAnchor(AnchorHorizontalCenter,'parent',AnchorHorizontalCenter);portrait:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter)
  portrait:setId('ourBossPortrait')
  -- name plate
  local plate=make('UIWidget',panel);plate:setSize({width=BAR_W,height=18})
  plate:addAnchor(AnchorTop,'parent',AnchorTop);plate:addAnchor(AnchorRight,'parent',AnchorRight)
  plate:setMarginTop(4);plate:setMarginRight(8);plate:setBackgroundColor('#2a241c');plate:setBorderWidth(1);plate:setBorderColor('#6a5634')
  nameLabel=make('UILabel',plate);nameLabel:fill('parent');nameLabel:setTextAlign(AlignCenter)
  nameLabel:setFont('Verdana Bold-11px');nameLabel:setColor('#f2e2b4')
  -- health bar
  local back=make('UIWidget',panel);back:setId('back');back:setSize({width=BAR_W,height=24})
  back:addAnchor(AnchorBottom,'parent',AnchorBottom);back:addAnchor(AnchorRight,'parent',AnchorRight)
  back:setMarginBottom(6);back:setMarginRight(8)
  back:setBackgroundColor('#2b0606');back:setBorderWidth(1);back:setBorderColor('#000000')
  fill=make('UIWidget',back);fill:addAnchor(AnchorTop,'parent',AnchorTop);fill:addAnchor(AnchorBottom,'parent',AnchorBottom)
  fill:addAnchor(AnchorLeft,'parent',AnchorLeft);fill:setMargin(1);fill:setWidth(BAR_W-2);fill:setBackgroundColor('#b51818')
  local shine=make('UIWidget',fill);shine:addAnchor(AnchorTop,'parent',AnchorTop);shine:addAnchor(AnchorLeft,'parent',AnchorLeft)
  shine:addAnchor(AnchorRight,'parent',AnchorRight);shine:setHeight(8);shine:setBackgroundColor('#ff5a5a40')
  hpLabel=make('UILabel',back);hpLabel:fill('parent');hpLabel:setTextAlign(AlignCenter)
  hpLabel:setFont('Verdana Bold-11px');hpLabel:setColor('#ffffff')
  panel:setVisible(false)
  return panel
end

local function render()
  if not ensure() then return end
  local max=math.max(1,tonumber(cur.max) or 1);local hp=math.max(0,math.min(max,tonumber(cur.hp) or 0))
  nameLabel:setText(cur.name or 'Boss')
  hpLabel:setText(fmt(hp)..' / '..fmt(max))
  local w=math.floor((BAR_W-2)*hp/max)
  fill:setWidth(math.max(0,w));fill:setVisible(w>0)
  panel:setTooltip((cur.tag and (cur.tag..': ') or '')..(cur.name or 'Boss')..'\n'..fmt(hp)..' / '..fmt(max)..' hit points ('..math.floor(hp*100/max)..'%)')
  panel:setVisible(true);panel:raise()
end

function BB.set(data)
  if type(data)~='table' then return end
  if data.hide then BB.hide();return end
  if data.name or tonumber(data.id)~=cur.id then
    cur={id=tonumber(data.id),name=data.name or cur.name,tag=data.tag,max=data.max,hp=data.hp}
    if ensure() and type(data.outfit)=='table' then
      local o=data.outfit
      local outfit={type=o.type or 0,head=o.head or 0,body=o.body or 0,legs=o.legs or 0,feet=o.feet or 0,addons=o.addons or 0,typeex=o.typeEx or 0}
      portrait:show();pcall(function() portrait:setOutfit(outfit) end)
      if OurTibiaArt and OurTibiaArt.creature then pcall(OurTibiaArt.creature,portrait,outfit,cur.name) end
    end
  else
    cur.hp=data.hp;cur.max=data.max or cur.max
  end
  render()
end

function BB.hide()
  cur={}
  if panel and not panel:isDestroyed() then panel:setVisible(false) end
end

function BB.clear()
  cur={}
  if panel and not panel:isDestroyed() then panel:destroy() end
  panel=nil
end
