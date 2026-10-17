-- Rarity frames: Mythibia look (30.09.2026): flat 2px border in the rarity
-- colour; unidentified items get a diagonal light sweep over the sprite
-- (shimmer.frag) instead of a frame. World Ending: orange frame + gold inner line.
-- Tooltip is ItemTooltip.
RarityFrames={fresh={},quick={},before={},closed={},closedOrder={},ground={},groundAttached={},colors={[1]='#b4b4b4',[2]='#6464d2',[3]='#b43cc8',[4]='#c8c832',[5]='#e11c1c',[6]='#ff8a00'},views={},widgets=setmetatable({},{__mode='k'})}
local F=RarityFrames
local original
local originalItemChange
local originalHoverChange
local originalDestroy
local pending
local function recordFor(item)
 -- Only equipped/container items have rarity records. Map items return nil
 -- (never false): callers test the record type before indexing it.
 if not item or type(item.getPosition)~='function' then return nil end
 local pos=item:getPosition()
 if not pos then return nil end
 if pos.x~=65535 then
  local g=F.ground[pos.x..':'..pos.y..':'..pos.z..':'..item:getId()]
  return g
 end
 local view=pos.y>=64 and pos.y or 0
 local record=F.views[view] and F.views[view][pos.y..':'..pos.z]
 if record and record.cid==item:getId() then return record end
 return nil
end
F.record=recordFor
function isUnidentifiedRarityItem(item)
 local record=recordFor(item)
 return type(record)=='table' and record.r==0
end
-- 10.10.2026: sent at once (no 10 ms timer). 'sync' = everything (game start),
-- 'syncv:<view>' = the records of one view (a container window was opened).
function F.request(kind)
 if not g_game.isOnline()then return end
 local p=g_game.getProtocolGame();if p then p:sendExtendedOpcode(107,type(kind)=='string' and kind or 'sync')end
end
local function tooltips() return ItemTooltip end
function F.apply(widget)
 if not widget or type(widget.getItem)~='function' then return end
 local item=widget:getItem();local record=recordFor(item)
 local color=record and item and record.cid==item:getId() and F.colors[record.r]
 local T=tooltips()
 if T and T.eligible(widget) then
  -- The custom tooltip replaces the plain text tooltip for bag/equipment items.
  if widget.tooltip then widget:removeTooltip() end
 else
  local itemTooltip=item and item:getTooltip() or ''
  local hud=modules.game_myotshud
  local sellerTooltip=item and hud and hud.getOurNpcSellTooltip and hud.getOurNpcSellTooltip(item:getId()) or nil
  if sellerTooltip then itemTooltip=(itemTooltip~='' and itemTooltip..'\n' or '')..sellerTooltip end
  if itemTooltip~='' then widget:setTooltip(itemTooltip);widget.ourtibiaTooltip=true
  elseif widget.ourtibiaTooltip then widget:setTooltip(nil);widget.ourtibiaTooltip=nil end
 end
 -- OurTibia (03.10.2026): items in containers get an outline in the rarity
 -- colour around their shape; equipped items keep the flat 2px slot border.
 local equipped=false
 if item then local ok,pos=pcall(function() return item:getPosition() end);equipped=ok and pos and pos.x==65535 and pos.y<64 or false end
 if item then
  local want=''
  if record and record.r==0 then want=F.shimmer
  elseif record and record.b then want=F.boundShimmer
  -- 09.10.2026: in backpacks the square slot frame is used (Mythibia look), not the sprite outline
  end
  if (item.ourShimmer or '')~=want then item:setShader(want);item.ourShimmer=want~='' and want or nil end
 end
 -- Toggle protection: small white lock in the top-left corner.
 if not widget or not widget.getChildById or (widget.isDestroyed and widget:isDestroyed()) then return end
 local guard=widget:getChildById('ourtibiaGuard')
 if record and record.g and item and record.cid==item:getId() then
  if not guard then
   guard=g_ui.createWidget('UIWidget',widget);guard:setId('ourtibiaGuard');guard:setPhantom(true);guard:setFocusable(false)
   -- 09.10.2026: Mythibia-like small white shield inside the frame
   guard:setSize({width=9,height=11});guard:addAnchor(AnchorTop,'parent',AnchorTop);guard:addAnchor(AnchorLeft,'parent',AnchorLeft)
   guard:setMarginTop(2);guard:setMarginLeft(2);guard:setImageSource('/game_myotshud/images/protected')
  end
  guard:show();guard:raise()
 elseif guard then guard:hide() end
 -- 13.10.2026 (Tobeto): time left of items with a duration (ring of regeneration...) in backpacks
 local durLabel=widget:getChildById('ourDuration')
 local showDur=record and record.dur and item and record.cid==item:getId() and not equipped
 if showDur then
  local opt=modules.client_options and modules.client_options.getOption and modules.client_options.getOption('showExpiryInContainers')
  if opt==false then showDur=false end
 end
 if showDur then
  if not durLabel then
   durLabel=g_ui.createWidget('UILabel',widget);durLabel:setId('ourDuration');durLabel:setPhantom(true);durLabel:setFocusable(false)
   durLabel:addAnchor(AnchorBottom,'parent',AnchorBottom);durLabel:addAnchor(AnchorLeft,'parent',AnchorLeft);durLabel:addAnchor(AnchorRight,'parent',AnchorRight)
   durLabel:setHeight(12);durLabel:setTextAlign(AlignCenter);durLabel:setFont('verdana-11px-rounded');durLabel:setColor('#ffffff')
  end
  local sec=math.max(0,math.floor(tonumber(record.dur) or 0))
  local text=sec>=3600 and string.format('%dh%02d',math.floor(sec/3600),math.floor(sec%3600/60)) or sec>=60 and string.format('%d:%02d',math.floor(sec/60),sec%60) or (sec..'s')
  durLabel:setText(text);durLabel:show();durLabel:raise()
 elseif durLabel then durLabel:hide() end
 local frame=widget:getChildById('ourtibiaRarityBorder')
 local inner=widget:getChildById('ourtibiaRarityInner')
 if inner then inner:hide() end
 -- 12.10.2026 (owner): rarity frames (Common ... World Ending) stay on items in
 -- backpacks and on equipped items. Only the value frames (NPC price colours on
 -- items without a rarity) are gone - those colours are in the Loot channel.
 -- 13.10.2026 (owner): the frame is drawn BEHIND the item (Mythibia look): it is
 -- the widget's own image (slot background + frame), not a child drawn on top.
 if frame then frame:hide() end
 if widget.ourValueFrame then widget:setImageClip(nil);widget:setImageSource('/images/ui/item');widget.ourValueFrame=nil end
 if not color then
  if (widget:getImageSource() or ''):find('_frame_') then widget:setImageSource(widget.ourFrameOrig or '/images/ui/item') end
  if widget.ourFramePad then widget:setPadding(widget.ourFramePad);widget.ourFramePad=nil end
  widget.ourFrameSrc=nil
  widget.ourtibiaRarity=nil;return
 end
 if widget.ourFrameOrig==nil then
  local cur=widget:getImageSource() or ''
  if cur:find('_frame_') then cur='/images/ui/item' end
  widget.ourFrameOrig=cur
 end
 local source=(widget.ourFrameOrig=='' and '/game_myotshud/images/eq_frame_' or '/game_myotshud/images/slot_frame_')..record.r
 if (widget:getImageSource() or '')~=source then widget:setImageClip(nil);widget:setImageSource(source) end
 -- 14.10.2026 (GM Nobody): the item is drawn a bit smaller inside the frame, so big sprites
 -- (armors, shields...) no longer cover the 3px rarity border.
 if widget.ourFramePad==nil and widget:getWidth()>=30 then
  widget.ourFramePad=widget:getPaddingTop() or 1
  widget:setPadding(3)
 end
 widget.ourFrameSrc=source
 if guard and guard:isVisible() then guard:raise() end;widget.ourtibiaRarity=record.r
end
-- Skip widgets that were destroyed (e.g. a closed container) and forget them.
local function applyAll() for widget in pairs(F.widgets)do if widget and widget.getChildById and not (widget.isDestroyed and widget:isDestroyed()) then F.apply(widget) else F.widgets[widget]=nil end end end
function F.receive(protocol,code,data)
 if type(data)~='table'then return end
 if data.attributes then modules.game_skills.myotsAttributes(data.attributes);return end
 if data.ground then F.receiveGround(data.ground);return end
 if not data.view or type(data.items)~='table'then return end
 local entries={}
 if data.q then
  -- OurTibia (10.10.2026): rarity colour from the engine, sent right before the
  -- item packet of this view (container open/add/update/remove, equipment slot).
  -- Only the records are stored here: the item packet that follows sets the
  -- widget's item, and the onItemChange hook applies the frame in that same
  -- frame. Nothing is applied to the old widgets and there are no timers or
  -- slot guessing any more (that made frames lag or jump to a neighbour).
  -- The full records (tooltip, lock, bound) of a player's own change arrive in
  -- the same packet batch from the server script.
  local old=F.views[data.view] or {}
  F.before[data.view]={views=F.views[data.view],quick=F.quick[data.view]}
  for _,e in ipairs(data.items)do
   local key=e.y..':'..e.z;local prev=old[key]
   if prev and prev.cid==e.cid and prev.r==e.r then entries[key]=prev
   elseif e.r==0 or F.colors[e.r] then entries[key]=e
   elseif prev and prev.cid==e.cid and prev.r==nil and (prev.g or prev.b or prev.cw or prev.t or prev.dur) then entries[key]=prev end
  end
  F.views[data.view]=entries
  F.quick[data.view]=data.items
  return
 end
 F.fresh[data.view]=nil
 for _,e in ipairs(data.items)do if e.r==0 or F.colors[e.r] or e.g or e.b or e.cw or e.t or e.dur then entries[e.y..':'..e.z]=e end end
 F.views[data.view]=entries
 applyAll()
 local T=tooltips();if T then T.refresh() end
end
function F.clear()
 F.views={};F.fresh={};F.quick={};F.before={};F.clearGround();if pending then removeEvent(pending);pending=nil end
 applyAll()
end
-- OurTibia (10.10.2026): a backpack that is opened again with exactly the same
-- contents gets its full records (tooltip, lock, bound shimmer) back at once;
-- the server answer to 'syncv:<view>' confirms them a moment later.
local function signature(itemId,quick)
 local parts={tostring(itemId or 0)}
 for _,e in ipairs(quick or {}) do parts[#parts+1]=e.z..':'..e.cid..':'..tostring(e.r) end
 return table.concat(parts,'|')
end
local function remember(itemId,records,quick)
 if not records or not quick or #quick==0 then return end
 local saved={};local any=false
 for _,record in pairs(records) do if record.tooltip or record.g or record.b or record.cw or record.t then saved[record.z]=record;any=true end end
 if not any then return end
 local key=signature(itemId,quick)
 if not F.closed[key] then F.closedOrder[#F.closedOrder+1]=key end
 F.closed[key]=saved
 while #F.closedOrder>32 do F.closed[table.remove(F.closedOrder,1)]=nil end
end
local function containerItemId(container)
 local ok,item=pcall(function() return container:getContainerItem() end)
 return ok and item and item:getId() or 0
end
local function onOpen(container,previous)
 local view=64+container:getId()
 local before=F.before[view];F.before[view]=nil
 -- the records stored for this window belonged to the previous container
 if previous and before then remember(containerItemId(previous),before.views,before.quick) end
 local quick=F.quick[view] or {}
 local entries={}
 for _,e in ipairs(quick) do if e.r==0 or F.colors[e.r] then entries[e.y..':'..e.z]=e end end
 local saved=F.closed[signature(containerItemId(container),quick)]
 if saved then
  for z,record in pairs(saved) do
   local copy={};for k,v in pairs(record) do copy[k]=v end;copy.y=view;copy.z=z
   entries[view..':'..z]=copy
  end
 end
 F.views[view]=entries
 applyAll()
 F.request('syncv:'..view)
end
-- The engine sends the layout of a container right BEFORE it takes an item out
-- (Container::removeThing notifies first and erases after), so when the remove
-- packet arrives the records still have the removed item in its old slot. Move
-- them up by one slot here - exactly what the engine did - so a frame never
-- lands on the item that slid into that slot (e.g. a second, plain sword).
local function shiftUp(list,slot)
 local out={}
 for key,e in pairs(list) do
  if e.z~=slot then
   if e.z>slot then local copy={};for k,v in pairs(e) do copy[k]=v end;copy.z=e.z-1;e=copy end
   out[#out+1]=e
  end
 end
 return out
end
local function paged(container)
 local ok,result=pcall(function() return container:hasPages() end)
 return ok and result
end
local function onRemoveItem(container,slot)
 -- containers with pages (depot) also add/remove items internally; there the
 -- records of the server (sent in the same batch) are used as they are
 if paged(container) then return end
 local view=64+container:getId()
 if F.views[view] then
  local records={}
  for _,e in ipairs(shiftUp(F.views[view],slot)) do records[view..':'..e.z]=e end
  F.views[view]=records
 end
 if F.quick[view] then
  local list=shiftUp(F.quick[view],slot);table.sort(list,function(a,b) return a.z<b.z end);F.quick[view]=list
 end
 applyAll()
 -- 17.10.2026: the container window empties its last slot after this signal and an empty
 -- slot gets no onItemChange - apply once more so no frame stays on an empty slot
 addEvent(applyAll)
end
-- An add is the other way round: the layout comes AFTER the insert. Records of
-- the items behind the new one are taken from their old slot (one up), so the
-- protection lock, tooltip and tier stay on the right item at once.
local function onAddItem(container,slot)
 if paged(container) then return end
 local view=64+container:getId()
 local before=F.before[view];local quick=F.quick[view]
 if not before or not quick then return end
 F.before[view]=nil
 local old=before.views or {}
 local entries={}
 for _,e in ipairs(quick) do
  local key=e.y..':'..e.z
  local from=(e.z<slot and e.z) or (e.z>slot and e.z-1) or nil
  local prev=from and old[e.y..':'..from]
  if prev and prev.cid==e.cid and prev.r==e.r and (prev.r~=nil or prev.g or prev.b or prev.cw or prev.t) then
   local copy={};for k,v in pairs(prev) do copy[k]=v end;copy.z=e.z;entries[key]=copy
  elseif e.r==0 or F.colors[e.r] then entries[key]=e end
 end
 F.views[view]=entries
 applyAll()
end
local function onClose(container)
 -- a new container replacing this one in the same window was handled in onOpen
 if g_game.getContainer(container:getId()) then return end
 local view=64+container:getId()
 remember(containerItemId(container),F.views[view],F.quick[view])
 F.views[view]=nil;F.quick[view]=nil;F.before[view]=nil
end
local function refreshTooltips()
 applyAll()
 local T=tooltips();if T then T.refresh() end
end

-- Rarity frames for items lying on the ground (02.10.2026): the server sends
-- {"ground":[{x,y,z,cid,r}]} for the tiles around the player; a coloured
-- border (attached effect, drawn over the item) is put on the matching item.
F.groundEffectBase=7300
function F.setupGroundEffects()
 if F.groundReady or not g_attachedEffects then return end
 F.groundReady=true
 for r=0,6 do
  local ok,eff=pcall(function() return g_attachedEffects.registerByImage(F.groundEffectBase+r,'rarity ground '..r,'/game_myotshud/images/corner_frame_'..r,false) end)
  if ok and eff then pcall(function() eff:setOffset(0,0,true) end);pcall(function() eff:setCanDrawOnUI(false) end) end
 end
end
function F.clearGround()
 for _,a in ipairs(F.groundAttached) do pcall(function() if a.shader then a.item:setShader('');a.item.ourShimmer=nil else a.item:detachEffectById(a.id) end end) end
 F.groundAttached={}
end
-- Only touches items whose border is missing or no longer valid (no detach /
-- attach every tick: that made effects flicker).
function F.applyGround()
 -- OurTibia (03.10.2026): items on the ground get the same outline shader
 -- around their shape (no square/corner effect any more).
 local keep={}
 for _,a in ipairs(F.groundAttached) do
  local ok,pos=pcall(function() return a.item:getPosition() end)
  local g=ok and pos and F.ground[pos.x..':'..pos.y..':'..pos.z..':'..a.cid]
  if g and F.groundShader(g.r or 0)==a.shader then keep[#keep+1]=a
  else pcall(function() a.item:setShader('');a.item.ourShimmer=nil end) end
 end
 F.groundAttached=keep
 for _,g in pairs(F.ground) do
  local tile=g_map.getTile({x=g.x,y=g.y,z=g.z})
  local shader=F.groundShader(g.r or 0)
  if tile and shader then
   for _,thing in ipairs(tile:getItems() or {}) do
    if thing:getId()==g.cid then
     if thing.ourShimmer~=shader then
      if pcall(function() thing:setShader(shader) end) then thing.ourShimmer=shader;F.groundAttached[#F.groundAttached+1]={item=thing,shader=shader,cid=g.cid} end
     end
     break
    end
   end
  end
 end
end
function F.receiveGround(rows)
 F.setupGroundEffects()
 local ground={}
 for _,g in ipairs(rows) do if g.r==0 or F.colors[g.r] then ground[g.x..':'..g.y..':'..g.z..':'..g.cid]=g end end
 F.ground=ground
 F.applyGround()
end
-- Map items are recreated on every tile update; put the borders back often.
-- 10.10.2026: every 60 ms (was 400 ms) - the server already sends the items
-- a few tiles outside the screen, so a frame is on the item as soon as the
-- tile appears (walking, item thrown on the floor) instead of up to ~1 s later.
local function groundTick()
 if g_game.isOnline() and next(F.ground) then F.applyGround() end
 F.groundEvent=scheduleEvent(groundTick,60)
end
F.shimmer='Item - Shimmer'
F.boundShimmer='Item - Bound Shimmer'
F.corpseGlow='Item - Corpse Glow'
F.corpseGlowRare='Item - Corpse Glow Rare'
F.outline={};for r=1,6 do F.outline[r]='Item - Rarity Outline '..r end
function F.groundShader(r) if r==0 then return F.shimmer end return F.outline[r] end
function F.setupShader()
 if F.shaderReady or not g_shaders then return end
 local ok,err=pcall(function()
  g_shaders.createFragmentShader(F.shimmer,'/game_myotshud/shimmer.frag',false)
  g_shaders.setupItemShader(F.shimmer)
  g_shaders.createFragmentShader(F.boundShimmer,'/game_myotshud/bound_shimmer.frag',false)
  g_shaders.setupItemShader(F.boundShimmer)
  g_shaders.createFragmentShader(F.corpseGlow,'/game_myotshud/corpse_glow.frag',false)
  g_shaders.setupItemShader(F.corpseGlow)
  g_shaders.createFragmentShader(F.corpseGlowRare,'/game_myotshud/corpse_glow_rare.frag',false)
  g_shaders.setupItemShader(F.corpseGlowRare)
  for r=1,6 do
   g_shaders.createFragmentShader(F.outline[r],'/game_myotshud/rarity_outline_'..r..'.frag',true)
   g_shaders.setupItemShader(F.outline[r])
  end
 end)
 if not ok then g_logger.error('RarityFrames shader: '..tostring(err)) end
 F.shaderReady=true
end
function F.init()
 F.setupShader()
 F.setupGroundEffects()
 if F.groundEvent then removeEvent(F.groundEvent) end
 F.groundEvent=scheduleEvent(groundTick,1000)
 original=ItemsDatabase.setRarityItem
 ItemsDatabase.setRarityItem=function(widget,item,style)
  if not widget then return end
  if g_game.getClientVersion()~=1098 then return original(widget,item,style)end
  -- Market backgrounds are UIWidgets, not instance-bearing UIItems.
  if type(widget.getItem)~='function' then return end
  F.widgets[widget]=true
  local source=widget:getImageSource()
  if source=='/images/ui/rarity_frames' or source=='/images/ui/containerslot-coloredges'then widget:setImageClip(nil);widget:setImageSource('/images/ui/item');widget.ourValueFrame=nil end
  -- 10.10.2026: no sync request per widget any more (the server pushes changes).
  F.apply(widget)
 end
 originalItemChange=UIItem.onItemChange
 UIItem.onItemChange=function(widget)
  if originalItemChange then originalItemChange(widget) end
  F.widgets[widget]=true
  F.apply(widget)
 end
 originalHoverChange=UIItem.onHoverChange
 UIItem.onHoverChange=function(widget,hovered)
  if originalHoverChange then originalHoverChange(widget,hovered) end
  F.widgets[widget]=true
  F.apply(widget)
  local T=tooltips()
  if T then
   if hovered and T.eligible(widget) then T.current=widget;T.show(widget)
   elseif not hovered and T.current==widget then T.current=nil;T.hide() end
  end
 end
 originalDestroy=UIItem.onDestroy
 UIItem.onDestroy=function(widget)
  F.widgets[widget]=nil
  local T=tooltips();if T and T.current==widget then T.current=nil;T.hide() end
  if originalDestroy then originalDestroy(widget) end
 end
 ProtocolGame.registerExtendedJSONOpcode(107,F.receive)
 g_keyboard.bindKeyDown('Shift',refreshTooltips)
 g_keyboard.bindKeyUp('Shift',refreshTooltips)
 connect(g_game,{onGameEnd=F.clear,onGameStart=F.request})
 connect(Container,{onOpen=onOpen,onClose=onClose,onAddItem=onAddItem,onRemoveItem=onRemoveItem})
 if ItemTooltip then ItemTooltip.init() end
end
function F.terminate()
 if F.groundEvent then removeEvent(F.groundEvent);F.groundEvent=nil end
 disconnect(g_game,{onGameEnd=F.clear,onGameStart=F.request})
 disconnect(Container,{onOpen=onOpen,onClose=onClose,onAddItem=onAddItem,onRemoveItem=onRemoveItem})
 if ItemTooltip then ItemTooltip.terminate() end
 ProtocolGame.unregisterExtendedJSONOpcode(107);F.clear()
 g_keyboard.unbindKeyDown('Shift',refreshTooltips)
 g_keyboard.unbindKeyUp('Shift',refreshTooltips)
 if original then ItemsDatabase.setRarityItem=original end
 if originalItemChange then UIItem.onItemChange=originalItemChange;originalItemChange=nil end
 if originalHoverChange then UIItem.onHoverChange=originalHoverChange;originalHoverChange=nil end
 if originalDestroy then UIItem.onDestroy=originalDestroy;originalDestroy=nil end
end
