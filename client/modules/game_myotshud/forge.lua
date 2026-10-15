local upgradeToken
-- Item Forge window (Claude, 30.09.2026). Server: data/scripts/myots/82_forge.lua, opcode 111.
ItemForge={}
local F=ItemForge
local OPCODE=111
local window,state,selected,upgradePos,stoneMode

local openPos
-- 04.10.2026: the item put into the upgrade slot stayed there (and the window
-- stayed open) after walking away from the forge. Clear it when the window is
-- closed, reopened, or the player walks away.
local function clearSlot()
 if not window then return end
 upgradePos=nil;upgradeToken=nil
 local slot=window:recursiveGetChildById('upgradeSlot');if slot then slot:setItem(nil) end
 local hint=window:recursiveGetChildById('slotHint');if hint then hint:setText('Drag an item here to upgrade it') end
 local text=window:recursiveGetChildById('upgradeText');if text then text:setText('') end
 local button=window:recursiveGetChildById('upgradeButton');if button then button:setEnabled(false) end
end
F.clearSlot=clearSlot
local function onWalk(player,newPos)
 if not window or not window:isVisible() or not openPos or not newPos then return end
 if newPos.z~=openPos.z or math.max(math.abs(newPos.x-openPos.x),math.abs(newPos.y-openPos.y))>1 then window:hide() end
end
local function send(data) if g_game.isOnline() then g_game.getProtocolGame():sendExtendedOpcode(OPCODE,json.encode(data)) end end
local function money(n) n=math.floor(n or 0);local s=tostring(n):reverse():gsub('(%d%d%d)','%1,'):reverse();return (s:gsub('^,','')) end
local function setItem(widget,clientId,count)
 widget:setImageSource('')
 -- 15.10.2026 (Tobeto): magical stone fragments get their own picture (the item looks like a small amethyst)
 if state and clientId and clientId==state.fragcid then widget:setItem(nil);widget:setImageSource('/game_myotshud/images/fragments');return end
 if not clientId or clientId==0 then widget:setItem(nil);return end
 local item=Item.create(clientId,count or 1);widget:setItem(item)
end

local function recipe(key) for _,r in ipairs(state and state.recipes or {}) do if r.key==key then return r end end end
local function maxCraft(r)
 if not r or not state then return 0 end
 local byFrag=r.frag>0 and math.floor(state.fragments/r.frag) or 100
 local byGold=r.gold>0 and math.floor(state.gold/r.gold) or 100
 -- 11.10.2026: recipes made of other items (Super Rarity Infuser: 10 Rarity Infusers)
 local byNeed=r.need and math.floor((tonumber(r.need.have) or 0)/math.max(1,tonumber(r.need.count) or 1)) or 100
 return math.max(0,math.min(100,byFrag,byGold,byNeed))
end
local function refreshDetails()
 local r=recipe(selected);local box=window:recursiveGetChildById('detailBox')
 if not r then return end
 setItem(box:getChildById('detailIcon'),r.cid)
 box:getChildById('detailName'):setText(r.name)
 box:getChildById('detailDesc'):setText(r.desc)
 local qty=box:getChildById('quantity');local can=maxCraft(r)
 qty:setMaximum(math.max(1,can));if qty:getValue()>math.max(1,can) then qty:setValue(1) end
 local n=qty:getValue()
 -- 07.10.2026: shown with the needed amount (a single fragment looked like a small gem)
 box:getChildById('quantityValue'):setText(n)
 if r.need then
  setItem(box:getChildById('ingredientIcon'),r.need.cid,1)
  box:getChildById('ingredientCount'):setText(r.need.count*n..'x '..r.need.name)
  box:getChildById('fragLabel'):setText(r.need.name..': '..r.need.count*n..' / '..(r.need.have or 0))
 else
  setItem(box:getChildById("ingredientIcon"),state.fragcid,100)
  box:getChildById('ingredientCount'):setText(r.frag*n..'x magical stone fragment')
  box:getChildById('fragLabel'):setText('Fragments: '..r.frag*n..' / '..state.fragments)
 end
 box:getChildById('goldLabel'):setText('Gold: '..money(r.gold*n)..' / '..money(state.gold))
 box:getChildById('canCraftLabel'):setText('You can craft: '..can)
 box:getChildById('craftButton'):setEnabled(can>=n and can>0)
end
local function buildRecipes()
 local list=window:recursiveGetChildById('recipes');list:destroyChildren()
 for _,r in ipairs(state.recipes) do
  local row=g_ui.createWidget('ForgeRow',list)
  setItem(row:getChildById('icon'),r.cid)
  row:getChildById('name'):setText(r.name)
  if r.need then
   setItem(row:getChildById('fragIcon'),r.need.cid,1)
   row:getChildById('frag'):setText(r.need.count)
  else
   setItem(row:getChildById("fragIcon"),state.fragcid,100)
   row:getChildById('frag'):setText(r.frag)
  end
  row:getChildById('gold'):setText(money(r.gold)..' gp')
  row.onClick=function() selected=r.key;list:focusChild(row,MouseFocusReason);refreshDetails() end
  if (selected or state.recipes[1].key)==r.key then selected=r.key;list:focusChild(row,MouseFocusReason) end
 end
 refreshDetails()
end
local function setTab(upgrade)
 window:getChildById('craftPanel'):setVisible(not upgrade)
 window:getChildById('upgradePanel'):setVisible(upgrade)
 window:getChildById('tabCraft'):setBackgroundColor(upgrade and '#262626' or '#3a3a3a')
 window:getChildById('tabUpgrade'):setBackgroundColor(upgrade and '#3a3a3a' or '#262626')
end
local rarityNames={'Common','Rare','Epic','Legendary','Mythical','World Ending'}
local function showUpgrade(d)
 upgradeToken=d and d.token or nil -- 03.10.2026: one click = one attempt (server checks the token)
 local text=window:recursiveGetChildById('upgradeText');local button=window:recursiveGetChildById('upgradeButton')
 if stoneMode then
  local check=window:recursiveGetChildById('protectorCheck');if check then check:setVisible(false) end
  button:setText('Apply '..stoneMode.name);button:setEnabled(upgradePos~=nil and not d.error)
  local lines={stoneMode.name,stoneMode.desc,''}
  if d.error then lines[#lines+1]=d.error elseif d.name then lines[#lines+1]=d.name;lines[#lines+1]='Tier '..d.tier..' | '..(rarityNames[d.rarity or 1] or '')..' | Upgrade +'..d.level else lines[#lines+1]='Drag the item you want to use the stone on into the slot.' end
  text:setText(table.concat(lines,'\n'));return
 end
 button:setText('Upgrade')
 -- OurTibia (03.10.2026): optional Astral Protector (tick box) instead of using it on the item.
 local check=window:recursiveGetChildById('protectorCheck')
 if check then
  check:setVisible(true)
  local n=tonumber(d.protectors) or 0
  check:setText('Use Astral Protector ('..n..' in backpack)')
  check:setEnabled(n>0)
  if n<=0 then check:setChecked(false) end
 end
 if d.error then text:setText(d.error);button:setEnabled(false);return end
 local lines={d.name,'Tier '..d.tier..' | '..(rarityNames[d.rarity or 1] or '')..' | Upgrade +'..d.level..' / +'..d.max,''}
 if d.cost then
  lines[#lines+1]='Next: +'..d.level..' -> +'..(d.level+1)
  lines[#lines+1]='Success chance: '..d.chance..'%'
  lines[#lines+1]='Cost: '..money(d.cost)..' gold (you have '..money(d.gold)..')'
  lines[#lines+1]='On failure: 50% to drop one level'..(d.level==0 and ' (not at +0)' or '')
  if d.protected then lines[#lines+1]='Astral Protector: already bound to this item - no downgrade' end
  lines[#lines+1]='Bonus: '..d.bonus
  lines[#lines+1]='Each level also widens attribute ranges (+5%) for Stones of Power.'
  button:setEnabled(d.gold>=d.cost)
 else
  lines[#lines+1]='Maximum upgrade reached for this tier.';button:setEnabled(false)
 end
 text:setText(table.concat(lines,'\n'))
 window:getChildById('goldBalance'):setText(money(d.gold)..' gp')
end
-- OurTibia (03.10.2026): "Link to chat" - puts an item link into the chat line;
-- everybody who clicks it in the chat sees the item with all its stats.
F.linkCache={}
local linkWait
function F.requestLink(id,widget)
 id=tonumber(id);if not id then return end
 local c=F.linkCache[id]
 if c and widget and ItemTooltip and ItemTooltip.showData then
  if c.error then return end
  ItemTooltip.showData(widget,c);return
 end
 linkWait={id=id,widget=widget}
 send({a='linkinfo',id=id})
end
function F.hoverLink(widget,id,hovered)
 if not hovered then linkWait=nil;if ItemTooltip then ItemTooltip.hide(widget) end;return end
 if ItemTooltip and ItemTooltip.isShowingFor and ItemTooltip.isShowingFor(widget) then return end
 if linkWait and linkWait.widget==widget and linkWait.id==tonumber(id) then return end
 F.requestLink(id,widget)
end
function F.insertLink(text)
 local c=modules.game_console;local edit=c and c.consoleTextEdit
 if not edit or not text then return end
 local cur=edit:getText() or ''
 if #cur+#text+1>255 then return end
 edit:setText((cur~='' and cur:sub(-1)~=' ') and (cur..' '..text..' ') or (cur..text..' '))
 pcall(function() edit:setCursorPos(-1) end)
 pcall(function() edit:focus() end)
end
local linkWindow
function F.showLink(d)
 local id=tonumber(d.id)
 if id then F.linkCache[id]={cid=d.cid,count=d.count or 1,record=d.record,footer=d.footer,error=d.error} end
 if linkWait and id==linkWait.id then
  local w=linkWait.widget;linkWait=nil
  if w then
   if not d.error and w:isHovered() and ItemTooltip and ItemTooltip.showData then ItemTooltip.showData(w,F.linkCache[id]) end
   return
  end
 end
 if linkWindow then linkWindow:destroy();linkWindow=nil end
 if d.error then modules.game_textmessage.displayFailureMessage(d.error);return end
 local ok,w=pcall(function() return displayInfoBox(d.name or 'Item',d.desc or '') end)
 if ok then linkWindow=w;if w then w.onDestroy=function() if linkWindow==w then linkWindow=nil end end end end
end
local function onPacket(protocol,code,buffer)
 local ok,d=pcall(json.decode,buffer);if not ok or type(d)~='table' or not window then return end
 if d.kind=='state' then state=d;window:getChildById('goldBalance'):setText(money(d.gold)..' gp');buildRecipes()
 elseif d.kind=='stone' then clearSlot();openPos=nil;stoneMode=d;upgradePos=nil;window:recursiveGetChildById('upgradeSlot'):setItem(nil);setTab(true);showUpgrade({})
 elseif d.kind=='open' then clearSlot();openPos=type(d.pos)=='table' and d.pos.x and d.pos or nil;if d.tab~='stone' then stoneMode=nil;window:recursiveGetChildById('upgradeButton'):setText('Upgrade') end;window:show();window:raise();window:focus()
 elseif d.kind=='link' then F.insertLink(d.text)
 elseif d.kind=='linkinfo' then F.showLink(d)
 elseif d.kind=='upgrade' then
  -- follow the item when its slot changed (change coins after paying)
  if type(d.pos)=='table' and upgradePos and d.pos.x then upgradePos={x=d.pos.x,y=d.pos.y,z=d.pos.z,cid=d.pos.cid or upgradePos.cid} end
  showUpgrade(d)
 end
end
function F.init()
 window=g_ui.displayUI('forge');window:hide()
 window.onVisibilityChange=function(w,visible) if not visible then clearSlot() end end
 connect(LocalPlayer,{onPositionChange=onWalk})
 window:getChildById('tabCraft').onClick=function() setTab(false) end
 window:getChildById('tabUpgrade').onClick=function() stoneMode=nil;window:recursiveGetChildById('upgradeButton'):setText('Upgrade');setTab(true) end
 local qty=window:recursiveGetChildById('quantity')
 qty.onValueChange=function() refreshDetails() end
 window:recursiveGetChildById('craftButton').onClick=function() if selected then send({a='craft',key=selected,qty=qty:getValue()}) end end
 local slot=window:recursiveGetChildById('upgradeSlot')
 slot.onDrop=function(self,widget,mousePos)
  local thing=widget and widget.currentDragThing;if not thing or not thing:isItem() then return false end
  local pos=thing:getPosition();if not pos or pos.x~=65535 then return false end
  upgradePos={x=pos.x,y=pos.y,z=pos.z,cid=thing:getId()}
  self:setItem(Item.create(thing:getId(),1))
  window:recursiveGetChildById('slotHint'):setText('Drop another item to switch')
  send({a='info',pos=upgradePos});return true
 end
 window:recursiveGetChildById('upgradeButton').onClick=function() if not upgradePos then return end;if stoneMode then send({a='apply',key=stoneMode.key,pos=upgradePos}) else local check=window:recursiveGetChildById('protectorCheck');if not upgradeToken then return end;local btn=window:recursiveGetChildById('upgradeButton');btn:setEnabled(false);send({a='upgrade',pos=upgradePos,token=upgradeToken,protect=(check and check:isVisible() and check:isEnabled() and check:isChecked()) or false});upgradeToken=nil end end
 ProtocolGame.registerExtendedOpcode(OPCODE,onPacket)
 F.hookMenus()
 connect(g_game,{onGameStart=F.hookMenus})
end
-- "Toggle protection" on items in the inventory (blocks NPC sale, upgrades and stones).
-- OurTibia (03.10.2026): registered again on every login (a reloaded
-- game_interface drops its menu hooks).
function F.hookMenus()
 if modules.game_interface and modules.game_interface.addMenuHook then
  modules.game_interface.addMenuHook('myotsProtection','Toggle protection',function(pos,look,use)
   local thing=use or look;local p=thing and thing:getPosition()
   if p then send({a='protect',pos={x=p.x,y=p.y,z=p.z,cid=thing:getId()}}) end
  end,function(pos,look,use) local thing=use or look;return thing and thing:isItem() and thing:getPosition() and thing:getPosition().x==65535 end)
  modules.game_interface.addMenuHook('myotsLink','Link to chat',function(pos,look,use)
   local thing=use or look;local p=thing and thing:getPosition()
   if p then send({a='link',pos={x=p.x,y=p.y,z=p.z,cid=thing:getId()}}) end
  end,function(pos,look,use) local thing=use or look;return thing and thing:isItem() and thing:getPosition() and thing:getPosition().x==65535 end)
 end
end
function F.terminate()
 disconnect(LocalPlayer,{onPositionChange=onWalk})
 disconnect(g_game,{onGameStart=F.hookMenus})
 ProtocolGame.unregisterExtendedOpcode(OPCODE)
 if modules.game_interface and modules.game_interface.removeMenuHook then modules.game_interface.removeMenuHook('myotsProtection');modules.game_interface.removeMenuHook('myotsLink') end
 if window then window:destroy();window=nil end
end
