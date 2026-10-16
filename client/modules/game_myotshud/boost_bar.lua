-- Global boost bar (02.10.2026): active store boosts (experience, loot, skill,
-- spawn, loot rarity, monster rarity) shown in the bottom-left corner of the
-- game window, right above the chat, with the time left (like on Mythibia).
BoostBar={list={},widgets={}}
local B=BoostBar
local bar,ticker
local function fmt(s)
  s=math.max(0,math.floor(s))
  local h=math.floor(s/3600);local m=math.floor(s/60)%60;local sec=s%60
  -- 04.10.2026: long boosts as "1h49" - "1:49:47" was wider than the icon and overlapped the next timer
  if h>0 then return string.format('%dh%02d',h,m) end
  return string.format('%d:%02d',m,sec)
end
local function ensureBar()
  if bar and not bar:isDestroyed() then return bar end
  local map=modules.game_interface and modules.game_interface.getMapPanel and modules.game_interface.getMapPanel()
  if not map then return nil end
  bar=g_ui.createWidget('UIWidget',map);bar:setId('ourtibiaBoostBar')
  bar:addAnchor(AnchorLeft,'parent',AnchorLeft);bar:addAnchor(AnchorBottom,'parent',AnchorBottom)
  bar:setMarginLeft(6);bar:setMarginBottom(6);bar:setHeight(52);bar:setWidth(10)
  bar:setBackgroundColor('#00000099');bar:setBorderWidth(1);bar:setBorderColor('#c8a04a')
  bar:setPadding(3);bar:setFocusable(false)
  local layout=UIHorizontalLayout.create(bar);layout:setSpacing(4);bar:setLayout(layout)
  return bar
end
function B.redraw()
  local w=ensureBar();if not w then return end
  w:destroyChildren();B.widgets={}
  local now=g_clock.seconds()
  local shown=0
  for _,b in ipairs(B.list) do
    local left=(b.until_ or 0)-now
    if left>0 then
      shown=shown+1
      local cell=g_ui.createWidget('UIWidget',w);cell:setSize({width=44,height=44});cell:setFocusable(false)
      local icon=g_ui.createWidget('UIWidget',cell);icon:setSize({width=32,height=32})
      icon:addAnchor(AnchorTop,'parent',AnchorTop);icon:addAnchor(AnchorHorizontalCenter,'parent',AnchorHorizontalCenter)
      icon:setImageSource('/images/myots/store/boost-'..tostring(b.name));icon:setImageSmooth(true);icon:setPhantom(true)
      local label=g_ui.createWidget('Label',cell);label:setFont('verdana-11px-rounded');label:setColor('#ffe08a')
      label:addAnchor(AnchorBottom,'parent',AnchorBottom);label:addAnchor(AnchorHorizontalCenter,'parent',AnchorHorizontalCenter)
      label:setText(fmt(left));label:setTextAutoResize(true);label:setPhantom(true)
      cell:setTooltip((b.title or b.name)..'\n'..(b.effect or '')..'\nActive for everyone - '..string.format('%d:%02d:%02d',math.floor(left/3600),math.floor(left/60)%60,math.floor(left)%60)..' left')
      B.widgets[#B.widgets+1]={label=label,cell=cell,b=b}
    end
  end
  -- 13.10.2026 (Tobeto): respawn fund tile - always visible, amount in the tooltip
  if B.fund then
    shown=shown+1
    local step=B.fundStep or 1000000
    local pct=math.floor(B.fund*100/math.max(1,step))
    local cell=g_ui.createWidget('UIWidget',w);cell:setSize({width=44,height=44});cell:setFocusable(false)
    local icon=g_ui.createWidget('UIWidget',cell);icon:setSize({width=32,height=32})
    icon:addAnchor(AnchorTop,'parent',AnchorTop);icon:addAnchor(AnchorHorizontalCenter,'parent',AnchorHorizontalCenter)
    icon:setImageSource('/images/myots/store/boost-spawn');icon:setImageSmooth(true);icon:setPhantom(true);icon:setOpacity(0.55)
    local label=g_ui.createWidget('Label',cell);label:setFont('verdana-11px-rounded');label:setColor('#9fd0ff')
    label:addAnchor(AnchorBottom,'parent',AnchorBottom);label:addAnchor(AnchorHorizontalCenter,'parent',AnchorHorizontalCenter)
    label:setText(pct..'%');label:setTextAutoResize(true);label:setPhantom(true)
    local function f(n) local s=tostring(math.floor(n));while true do local k;s,k=s:gsub('^(%d+)(%d%d%d)','%1.%2');if k==0 then break end end;return s end
    cell:setTooltip('Respawn fund: '..f(B.fund)..' / '..f(step)..' gold\nEvery full million starts 1 hour of Experience Boost\n(+10% exp) and Loot Boost (+30% loot) for everyone.\nDonate with !donate <amount>')
  end
  if shown==0 then w:hide() else w:setWidth(shown*48+6);w:show();w:raise() end
end
local function tick()
  local now=g_clock.seconds();local expired=false
  for _,e in ipairs(B.widgets) do
    local left=(e.b.until_ or 0)-now
    if left<=0 then expired=true else e.label:setText(fmt(left)) end
  end
  if expired then B.redraw() end
end
function B.set(list,fund,step)
  local now=g_clock.seconds();B.list={}
  B.fund=tonumber(fund);B.fundStep=tonumber(step)
  for _,b in ipairs(list or {}) do b.until_=now+(tonumber(b.left) or 0);B.list[#B.list+1]=b end
  B.redraw()
  if not ticker then ticker=cycleEvent(tick,1000) end
end
function B.clear()
  B.list={};B.widgets={}
  if ticker then removeEvent(ticker);ticker=nil end
  if bar and not bar:isDestroyed() then bar:destroy() end;bar=nil
end
