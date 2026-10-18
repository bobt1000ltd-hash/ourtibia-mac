local windows,buttons={},{}
local refs,state,daily,passiveWindow,timer,trainerButton
local loading=false
local trainer={enabled=false,mana=true,runes=false,food=false,idle=false,retarget=false,manaSpell='utevo lux',runeSpell='adori gran',manaThreshold=90,runeThreshold=90}
local fields={}
local session={start=0,xp=0,loot=0,kills=0,items={}}
local lastExperience,lastTurn=0,0

function command(text)
  if g_game.isOnline() then g_game.getProtocolGame():sendExtendedOpcode(102,text) end
end
function toggleFullscreen()
  modules.client_options.setOption('fullscreen',not g_window.isFullscreen())
end
local function statusMessage(text) if modules.game_textmessage and modules.game_textmessage.displayStatusMessage then modules.game_textmessage.displayStatusMessage(text) end end
local function content(window) return window:getChildById('contentsPanel') end
-- 16.10.2026 (Tobeto): the ON / OFF button stays at the top while the rest of the window scrolls
local function pinTop(window,btn)
  local c=content(window)
  btn:setParent(window);btn:breakAnchors()
  btn:addAnchor(AnchorTop,'miniwindowHeader',AnchorBottom)
  btn:addAnchor(AnchorLeft,'parent',AnchorLeft)
  btn:addAnchor(AnchorRight,'miniwindowScrollBar',AnchorLeft)
  btn:setMarginTop(3);btn:setMarginLeft(8);btn:setMarginRight(6)
  c:setMarginTop(2+btn:getHeight()+5)
end
local function label(parent,text)
  local w=g_ui.createWidget('HudLabel',parent);w:setText(text);return w
end
local function button(parent,text,callback)
  local w=g_ui.createWidget('HudButton',parent);w:setText(text);w.onClick=callback;return w
end
local function check(parent,text,callback)
  local w=g_ui.createWidget('HudCheck',parent);w:setText(text)
  w.onCheckChange=function(_,value) if not loading then callback(value) end end;return w
end
local function panel(id,title,height,parent)
  local w=g_ui.createWidget('HudWindow',parent);w:setId(id);w:setText(title);w:setHeight(height)
  w:getChildById('miniwindowTitle'):setText(title)
  w:setContentMinimumHeight(40)
  for _,name in ipairs({'newWindowButton','contextMenuButton','toggleFilterButton'}) do local b=w:getChildById(name);if b then b:hide() end end
  w:setup();windows[id]=w;return w
end
local function toggle(w) if w:isVisible() then w:close() else w:open() end end
-- 16.10.2026 (Tobeto): Task Board -> 'Task Tracker' button
function showTaskTracker() local w=windows and windows.myotsTasks;if w then if not w:isVisible() then w:open() end;pcall(function() w:raise() end) end end
-- 17.10.2026 (Tobeto): the Task Board button switches the Task Tracker on and off
function toggleTaskTracker() local w=windows and windows.myotsTasks;if w then if w:isVisible() then w:close() else w:open();pcall(function() w:raise() end) end end end
-- 13.10.2026 (Tobeto): Autolooting and Trainer cannot be stretched past their contents
function ourCapPanels()
  for _,id in ipairs({'myotsLoot','myotsTrainer'}) do
    local w=windows[id];local cp=w and not w:isDestroyed() and w:getChildById('contentsPanel')
    if cp then
      local bottom=0
      for _,ch in ipairs(cp:getChildren()) do if ch:isVisible() then bottom=math.max(bottom,ch:getY()+ch:getHeight()+ch:getMarginBottom()-cp:getY()) end end
      if bottom>40 then
        -- 15.10.2026 (Tobeto): the panel stretches only until the scroll bar is full (nothing left
        -- to scroll) - the padding of the contents panel counts too
        local content=bottom+4+cp:getPaddingBottom()
        w:setContentMaximumHeight(content)
        local maxH=content+(cp:getY()-w:getY())+6
        if w:getHeight()>maxH then w:setHeight(maxH) end
        w.ourCapContent=content
        addEvent(function()
          if w:isDestroyed() then return end
          local sb=w:getChildById('miniwindowScrollBar')
          local extra=sb and sb:getMaximum() or 0
          if extra>0 then
            -- what is still hidden below the visible part: the full height is visible + hidden
            local need=math.max(content,cp:getHeight()+extra)
            w.ourCapContent=need
            w:setContentMaximumHeight(need)
            if w:getHeight()>=maxH-1 then w:setHeight(w:getHeight()+(need-content)) end
          end
        end)
      end
    end
  end
end
local function itemRef(serverId)
  -- Autoloot slots now arrive as {sid,cid,name} straight from the server.
  if type(serverId)=='table' then
    local cid=tonumber(serverId.cid) or 0
    if cid>0 then return {cid=cid,name=tostring(serverId.name or 'item')} end
    serverId=serverId.sid
  end
  if not refs or not refs.items then return nil end
  return refs.items[tostring(serverId)] or refs.items[tonumber(serverId)]
end
local function draggedItem(draggedWidget)
  local candidates={draggedWidget}
  if g_ui.getDraggingWidget then
    local active=g_ui.getDraggingWidget()
    if active and active~=draggedWidget then candidates[#candidates+1]=active end
  end
  for _,candidate in ipairs(candidates) do
    if candidate then
      local thing=candidate.currentDragThing
      if thing and thing.getId then return thing end
      if candidate.getItem then
        local item=candidate:getItem()
        if item and item.getId then return item end
      end
    end
  end
  return nil
end
local function saveTrainer()
  local p=g_game.getLocalPlayer();if not p then return end
  local saved={};for k,v in pairs(trainer) do saved[k]=v end -- 05.10.2026: the ON/OFF state is remembered too
  g_settings.setNode('myots-trainer-'..p:getName():gsub('[^%w]','_'),saved)
end
local function updateTrainerButton()
  trainerButton:setText(trainer.enabled and 'Trainer: ON' or 'Trainer: OFF')
  trainerButton:setColor(trainer.enabled and '#66dd44' or '#ff5555')
  -- 07.10.2026: no setOn - the icon has no 'on' frame and looked broken
  if buttons[4] then pcall(function() buttons[4]:setTooltip('Trainer') end) end
end
function showDaily()
  -- Task Board (game_myotstasks) replaces the old single daily task window.
  -- 13.10.2026 (Tobeto): the button toggles - a second click closes the Task Board
  if modules.game_myotstasks and modules.game_myotstasks.toggle then modules.game_myotstasks.toggle();return end
  if modules.game_myotstasks and modules.game_myotstasks.show then modules.game_myotstasks.show();return end
  command('state');daily:show();daily:raise();daily:focus()
end
-- Kill Tracker panel only (01.10.2026): redrawn alone on every kill, without the whole HUD.
local function drawKills()
  if not state then return end
  state.recent=type(state.recent)=='table' and state.recent or {}
  local c=content(windows.myotsKills);c:destroyChildren()
  label(c,'Recent Kills')
  for i,r in ipairs(state.recent or {}) do
    if i>5 then break end
    r=type(r)=='table' and r or {};r.name=tostring(r.name or 'Unknown');r.stars=math.max(0,math.min(8,tonumber(r.stars) or 0));r.kills=tonumber(r.kills) or 0;r.target=tonumber(r.target) or 0
    local row=g_ui.createWidget('KillEntry',c)
    -- 12.10.2026 (Tobeto): long names are cut with "..." so they fit the panel
    do local full=tostring(r.display or r.name);local lbl=row:getChildById('name');lbl:setText(full);lbl:setTooltip(full)
      -- 13.10.2026: fit to the label's real width once the row is laid out (the
      -- panel width minus a guess was too wide - the name ran under the scrollbar)
      local function fit()
        if lbl:isDestroyed() then return end
        local maxW=lbl:getWidth();if not maxW or maxW<20 then maxW=math.max(40,(c:getWidth() or 150)-64) end
        maxW=maxW-2;local nm=full;lbl:setText(nm)
        while #nm>3 and lbl:getTextSize().width>maxW do nm=nm:sub(1,#nm-1):gsub('%s+$','');lbl:setText(nm..'...') end
      end
      fit();scheduleEvent(fit,50) end
    -- 11.10.2026 (Tobeto): click a monster -> its wiki page
    do local monsterName=r.name;row.onClick=function() local w=modules.game_myotswiki;if w and w.showMonster then w.showMonster(monsterName) end end end
    row:setTooltip(string.format('%s: %d/8 stars\nBonus: +%d%% damage, +%d%% loot against this monster.\nEach new star: one reward (coins, fragments or upgrade stones).',r.name,r.stars,r.stars,r.stars*2))
    -- 17.10.2026 (owner): the 8 stars again (the stage lines were removed)
    -- OurTibia (18.10.2026, Tobeto): the stars are vertical lines (2 px, 2 px apart): reached
    -- stages are green lines on the left of the progress bar, the missing ones white lines on
    -- its right. The bar keeps its size (row width - 8 steps) and moves one step to the right
    -- for every reached stage, so a line "moves" from the right side to the left one.
    local stages=row:getChildById('stages')
    if stages then
      local LINE,STEP,MAXSTAGES=2,4,8
      local reached=math.max(0,math.min(MAXSTAGES,r.stars))
      for _,old in ipairs(stages:getChildren()) do if old:getId()~='killProgress' then old:destroy() end end
      for i=0,MAXSTAGES-1 do
        local line=g_ui.createWidget('KillStageLine',stages);line:setWidth(LINE)
        if i<reached then
          line:setBackgroundColor('#3fd04a');line:addAnchor(AnchorLeft,'parent',AnchorLeft);line:setMarginLeft(i*STEP)
        else
          local j=i-reached -- 0 = the line next to the bar
          line:setBackgroundColor('#f0f0f0');line:addAnchor(AnchorRight,'parent',AnchorRight);line:setMarginRight((MAXSTAGES-reached-1-j)*STEP)
        end
      end
      local bar=stages:getChildById('killProgress')
      if bar then bar:setMarginLeft(reached*STEP);bar:setMarginRight((MAXSTAGES-reached)*STEP) end
    end
    local progress=row:getChildById('stages'):getChildById('killProgress')
    -- 11.10.2026: the server sends the milestones of this monster (fewer kills for rare spawns)
    local previous=tonumber(r.prev)
    if not previous then
      previous=0
      for _,milestone in ipairs(type(r.milestones)=='table' and r.milestones or {100,200,400,1000,2000,4000,8000,20000}) do
        if r.kills>=milestone then previous=milestone else break end
      end
    end
    local span=math.max(1,(r.target or 20000)-previous)
    progress:setPercent(r.stars>=8 and 100 or math.max(0,math.min(100,math.floor((r.kills-previous)*100/span))))
    local k=math.floor(r.kills);local ks=tostring(k):reverse():gsub('(%d%d%d)','%1,'):reverse():gsub('^,','')
    progress:setText(ks)
    local monster=refs and refs.monsters and refs.monsters[r.name]
    -- 16.10.2026: the server sends the outfit (new monsters are not in hud.json)
    OurTibiaArt.creature(row:getChildById('outfit'),(type(r.outfit)=='table' and (tonumber(r.outfit.type) or 0)+(tonumber(r.outfit.typeex) or 0)>0) and r.outfit or (monster and monster.outfit),r.name)
    -- 17.10.2026 (Tobeto): tooltip in the "Wolf" format
    do local kills=math.floor(r.kills*100)/100
      row:setTooltip(string.format('%s\nStage: %d/8\nKills: %s\nCurrent bonus:\n+%d%% damage\n+%d%% loot\nClick to open wiki.',
        tostring(r.display or r.name),math.min(8,r.stars+(r.stars>=8 and 0 or 1)),r.stars>=8 and string.format('%g',kills) or string.format('%g/%d',kills,r.target),r.stars,r.stars*2)) end
  end
  if #(state.recent or {})==0 then label(c,'Hunt to track your first kills.') end
end
-- OurTibia (18.10.2026, Tobeto): draw the Kill Tracker from a given list (testing the look
-- without killing): modules.game_myotshud.previewKills({{name='dragon',stars=3,kills=950,target=2000}})
function previewKills(recent)
  state=state or {};state.recent=recent or {};drawKills()
end
-- OurTibia (06.10.2026): auto-loot exclusions (right-click item -> "Exclude from auto-loot").
local exclWindow
-- 13.10.2026: the right-click option is only for creature products (list from the server, once per login)
lootProducts=nil
local productsAsked=false
function isLootProduct(cid)
  cid=tonumber(cid);if not cid then return false end
  if not lootProducts then
    if not productsAsked and g_game.isOnline() then productsAsked=true;command('products') end
    return false
  end
  return lootProducts[cid]==true
end
function isLootExcluded(cid)
  cid=tonumber(cid);if not cid or not state or type(state.loot)~='table' then return false end
  for _,e in ipairs(type(state.loot.excluded)=='table' and state.loot.excluded or {}) do
    if type(e)=='table' and tonumber(e.cid)==cid then return true end
  end
  return false
end
function setLootExcluded(cid,on)
  command('excl:'..(on and 'add' or 'remove')..':'..tostring(tonumber(cid) or 0))
end
function pickLootExclusion()
  scheduleEvent(function() modules.game_interface.startItemSelection(function(item)
    if not item or not item.getId then statusMessage('Select an item.');return end
    setLootExcluded(item:getId(),true)
  end,true) end,50)
end
local function drawExclusions()
  if not exclWindow then return end
  local list=exclWindow:getChildById('list');list:destroyChildren()
  local loot=state and type(state.loot)=='table' and state.loot or {}
  local entries=type(loot.excluded)=='table' and loot.excluded or {}
  for _,e in ipairs(entries) do
    if type(e)=='table' then
      local cid=tonumber(e.cid) or 0
      local row=g_ui.createWidget('ExclRow',list)
      row:getChildById('icon'):setItemId(cid)
      row:getChildById('name'):setText(tostring(e.name or 'item'))
      row:getChildById('remove').onClick=function() setLootExcluded(cid,false) end
    end
  end
  if #entries==0 then local l=g_ui.createWidget('HudLabel',list);l:setText('No excluded items.') end
  exclWindow:getChildById('count'):setText('Excluded: '..#entries..' / '..(tonumber(loot.excludedMax) or 80))
  if fields.exclButton then fields.exclButton:setText('Excluded items ('..#entries..')') end
end
function showLootExclusions()
  if not exclWindow then
    exclWindow=g_ui.displayUI('excl')
  end
  exclWindow:show();exclWindow:raise();exclWindow:focus()
  local ok,err=pcall(drawExclusions);if not ok then print('[MyOTS HUD] exclusions: '..tostring(err)) end
end
local drawStateInner
local function drawState()
  local ok,err=pcall(drawStateInner);loading=false
  if not ok then print('[MyOTS HUD] drawState: '..tostring(err)) end
end
drawStateInner=function()
  if not state then return end
  state.recent=type(state.recent)=='table' and state.recent or {}
  state.daily=type(state.daily)=='table' and state.daily or {claimed=false,used=false,active=0,offers={},rerolls=0}
  state.loot=type(state.loot)=='table' and state.loot or {enabled=false,gold=false,valuables=false,conversionUnlocked=false,preset=1,slots=0,items={}}
  state.loot.items=type(state.loot.items)=='table' and state.loot.items or {}
  loading=true
  drawKills()
  local d=state.daily
  d.offers=type(d.offers)=='table' and d.offers or {};d.active=tonumber(d.active) or 0;d.rerolls=tonumber(d.rerolls) or 0;d.progress=tonumber(d.progress) or 0
  local activeOffer=d.offers[d.active]
  local status=d.claimed and 'Reward claimed. Come back after 09:00.' or d.used and d.active==0 and 'Cancelled. A new task is available after 09:00.' or activeOffer and string.format('Active task: %s | %g kills',activeOffer.name or 'Task',d.progress) or 'Choose one of six daily tasks. Reset: 09:00.'
  daily:getChildById('status'):setText(status)
  local offers=daily:getChildById('offers');offers:destroyChildren()
  for i,o in ipairs(d.offers) do
    if type(o)~='table' then o={} end
    o.name=tostring(o.name or 'Task');o.need=tonumber(o.need) or 0;o.tokens=tonumber(o.tokens) or 0
    local index=i;local row=g_ui.createWidget('DailyOffer',offers)
    row:getChildById('name'):setText(o.name)
    row:getChildById('progress'):setText('Kills: '..(d.active==index and d.progress or 0)..' / '..o.need)
    row:getChildById('rewards'):setText('Experience: '..(o.experience or 0)..'\n\nGold: '..(o.gold or 0)..'\n\nLoyalty: '..o.tokens)
    local monster=refs and refs.monsters and refs.monsters[o.name]
    OurTibiaArt.creature(row:getChildById('outfit'),monster and monster.outfit,o.name)
    local accept=row:getChildById('accept');accept:setEnabled(not d.used);accept:setText(d.active==index and 'Active task' or 'Accept Task');accept.onClick=function()command('daily:'..index)end
  end
  local costs={0,2000,5000,10000,25000}
  daily:getChildById('reroll'):setText('Reroll: '..(costs[d.rerolls+1] or 50000)..' gp')
  daily:getChildById('reroll'):setEnabled(not d.used)
  daily:getChildById('cancelTask'):setEnabled(d.active>0 and not d.claimed)
  daily:getChildById('claim'):setEnabled(activeOffer and not d.claimed and d.progress>=tonumber(activeOffer.need or 0))
  local tb=type(state.taskboard)=='table' and state.taskboard or nil
  -- 11.10.2026 (Tobeto): rows with outfit, proper monster name and a progress bar
  -- instead of a block of lowercase text.
  local rows=fields.taskRows
  if rows then rows:destroyChildren() end
  local tasksWindow=windows.myotsTasks
  if tb and rows then
    local daily=type(tb.daily)=='table' and tb.daily or {}
    local weekly=type(tb.weekly)=='table' and tb.weekly or {}
    -- 15.10.2026 (Tobeto): section bar "Daily" / "Weekly" with the time left until the reset
    local function header(title,color,leftSeconds,weeklyFmt)
      local h=g_ui.createWidget('TaskSection',rows)
      h:getChildById('accent'):setBackgroundColor(color)
      h:getChildById('title'):setText(title);h:getChildById('title'):setColor(color)
      ourTaskTimers[#ourTaskTimers+1]={label=h:getChildById('title'),name=title,ends=g_clock.seconds()+(tonumber(leftSeconds) or 0),weekly=weeklyFmt}
      h:getChildById('left'):hide()
      return h
    end
    local function entry(t,color)
      t=type(t)=='table' and t or {}
      local name=tostring(t.display or t.name or '?')
      local kills=tonumber(t.kills) or 0;local need=math.max(1,tonumber(t.need) or 1)
      local row=g_ui.createWidget('TaskEntry',rows)
      do local monsterName=tostring(t.name or '');row.onClick=function() local w=modules.game_myotswiki;if w and w.showMonster then w.showMonster(monsterName) end end end
      row:getChildById('name'):setText(name)
      row:getChildById('name'):setTooltip(name)
      -- 13.10.2026 (Tobeto): long names end with "..." at the end of the progress bar
      do local lbl=row:getChildById('name')
        local function fit()
          if lbl:isDestroyed() then return end
          local maxW=lbl:getWidth();if not maxW or maxW<20 then return end
          maxW=maxW-4;local nm=name;lbl:setText(nm)
          while #nm>3 and lbl:getTextSize().width>maxW do nm=nm:sub(1,#nm-1):gsub('%s+$','');lbl:setText(nm..'...') end
        end
        scheduleEvent(fit,50) end
      local bar=row:getChildById('progress')
      bar:setBackgroundColor(t.done and '#4a4a4a' or color)
      if t.done then row:setOpacity(0.55);row:setTooltip('Completed') end
      bar:setPercent(math.max(0,math.min(100,math.floor(kills*100/need))))
      bar:setText(string.format('%d / %d',kills,need))
      local monster=refs and refs.monsters and refs.monsters[tostring(t.name or ''):lower()]
      OurTibiaArt.creature(row:getChildById('outfit'),(type(t.outfit)=='table' and (tonumber(t.outfit.type) or 0)+(tonumber(t.outfit.typeex) or 0)>0) and t.outfit or (monster and monster.outfit),tostring(t.name or ''))
    end
    ourTaskTimers={}
    -- active tasks first, finished ones at the bottom of their list
    local function split(list)
      local act,fin={},{}
      for _,t in ipairs(list) do if type(t)=='table' and t.done then fin[#fin+1]=t else act[#act+1]=t end end
      return act,fin
    end
    -- 16.10.2026 (Tobeto): a finished task takes its slot until the server save; all done ->
    -- "Tasks complete". Weekly: the closest to completion first, finished ones are hidden.
    local function doneNote()
      local e=g_ui.createWidget('TaskEmpty',rows)
      e:getChildById('text'):setText('Tasks complete');e:getChildById('text'):setColor('#8ac88a')
      e:setTooltip('All tasks are done - new ones after the reset.')
    end
    local dAct,dFin=split(daily)
    header('Daily','#5fc06a',tb.dailyLeft,false)
    for _,t in ipairs(dAct) do entry(t,'#2f8f3a') end
    local freeSlots=math.max(0,3-#dAct-#dFin)
    for _=1,freeSlots do
      local e=g_ui.createWidget('TaskEmpty',rows)
      e:setTooltip('Click to open the Task Board and take a task')
      e.onClick=function() showDaily() end
      e.onHoverChange=function(self,h) local b=self:getChildById('box');b:setBorderColor(h and '#7a7a7a' or '#3a3a3a');self:getChildById('text'):setColor(h and '#c8c8c8' or '#6a6a6a') end
    end
    if #dFin>=3 then doneNote() end
    local wAct,wFin=split(weekly)
    table.sort(wAct,function(a,b)
      local pa=(tonumber(a.kills) or 0)/math.max(1,tonumber(a.need) or 1)
      local pb=(tonumber(b.kills) or 0)/math.max(1,tonumber(b.need) or 1)
      return pa>pb
    end)
    header('Weekly','#a07ad8',tb.weeklyLeft,true)
    for _,t in ipairs(wAct) do entry(t,'#7a4fb0') end
    if #wAct==0 and #wFin>0 then doneNote() end
    local dFinShown,wFinShown=#dFin>=3 and 1 or 0,(#wAct==0 and #wFin>0) and 1 or 0
    ourTaskTimersTick()
    fields.dailyStatus:setVisible(false);fields.dailyStatus:setHeight(0)
    local h=24+(#dAct+freeSlots+dFinShown+#wAct+wFinShown)*36+40
    if tasksWindow and tasksWindow:getHeight()<math.min(h+30,260) then tasksWindow:setHeight(math.min(h+30,260)) end
  else
    fields.dailyStatus:setVisible(true)
    fields.dailyStatus:setText(activeOffer and string.format('%g / %d kills',d.progress,tonumber(activeOffer.need or 0)) or 'No active task')
    fields.dailyStatus:setHeight(17)
  end
  for _,name in ipairs({'enabled','gold','valuables','products','convert'}) do fields[name]:setChecked(state.loot[name] and true or false) end
  if fields.items then fields.items:setChecked(state.loot.itemsOn~=false) end
  fields.convert:setEnabled(true)
  fields.convert:setTooltip('Convert coins to the largest denomination')
  fields.lootItems:destroyChildren()
  for _,category in ipairs({'gold','valuables','items','products'}) do
    local info=type(state.loot.bags)=='table' and state.loot.bags[category] or nil
    local bag=itemRef(state.loot[category..'Bag']) or (type(info)=='table' and tonumber(info.cid) and tonumber(info.cid)>0 and {cid=tonumber(info.cid),name=tostring(info.name or 'Container')}) or nil
    local row=fields[category..'Bag']
    row:getChildById('itemIcon'):setItemId(bag and bag.cid or 0)
    row:getChildById('itemIcon'):setTooltip(bag and ('Destination: '..bag.name) or 'No container chosen: loot goes to your main backpack.')
    row:getChildById('remove'):setVisible(bag~=nil)
    local plus=row:getChildById('plus');if plus then plus:setVisible(bag==nil) end
  end
  for page=1,4 do fields['preset'..page]:setOn(page==state.loot.preset) end
  local slots=math.max(0,tonumber(state.loot.slots) or 0)
  -- 17.10.2026 (Tobeto): the 4 extra slots of the store are shown locked (coin icon) until bought
  local locked=(slots>0 and slots<12) and (12-slots) or 0
  fields.lootItems:setHeight(math.max(1,math.ceil((slots+locked)/4))*38)
  ourLootEmpty={}
  for i=1,slots do
    local slotIndex=i
    local sid=(state.loot.items or {})[slotIndex]
    local item=itemRef(sid)
    local row=g_ui.createWidget('LootSlot',fields.lootItems)
    if item then
      row:getChildById('icon'):setItemId(item.cid)
      row:getChildById('plus'):hide()
      row:getChildById('remove'):show()
      row:getChildById('remove').onClick=function() command('item:remove:'..item.cid..':'..slotIndex) end
      row:setTooltip(item.name..' (x or right-click to remove)')
      row.onMouseRelease=function(_,_,mouseButton)
        if mouseButton==MouseRightButton then command('item:remove:'..item.cid..':'..slotIndex);return true end
        return false
      end
    else
      row:setTooltip('Click, then click an item (backpack, equipment or ground) - or drag an item here - to autoloot it.')
      row.onClick=function() MyOTSHudPickItem(slotIndex) end
      -- 14.10.2026 (Tobeto): empty slots light up as soon as an item is dragged (brighter under the mouse)
      ourLootEmpty[#ourLootEmpty+1]=row
      row.onHoverChange=function(self) ourLootDragGlow(true) end
    end
    -- 14.10.2026 (Tobeto): items can be dragged onto the looting slots (backpack, equipment, ground)
    row.onDrop=function(self,widget,mousePos)
      self:setBorderWidth(0)
      local thing=widget and widget.currentDragThing
      if not thing or not thing.getId or thing:getId()<=100 then return false end
      command('item:add:'..thing:getId()..':'..slotIndex)
      return true
    end
  end
  for _=1,locked do
    local row=g_ui.createWidget('LootSlot',fields.lootItems)
    row:getChildById('plus'):hide();row:getChildById('remove'):hide()
    row:getChildById('icon'):hide()
    local coin=g_ui.createWidget('UIWidget',row);coin:setSize({width=12,height=12});coin:setPhantom(true)
    coin:addAnchor(AnchorHorizontalCenter,'parent',AnchorHorizontalCenter);coin:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter)
    coin:setImageSource('/images/store/icon-tibiacoin');coin:setImageSmooth(true)
    row:setOpacity(0.75)
    row:setTooltip('Locked slot. Unlock 4 more autoloot slots in the Game Store (Extras > Services > More Autoloot Slots). Click to open the store.')
    row.onClick=function() local st=modules.game_myotsstore;if st and st.openBuyFor then pcall(st.openBuyFor,'More Autoloot Slots') end end
  end
  pcall(drawExclusions)
  loading=false
  -- the panel may get taller (more slots) - let it stretch to the new contents
  addEvent(function() pcall(ourCapPanels) end)
end
-- 15.10.2026 (Tobeto): time left until the task reset - Daily in hours (minutes in the last
-- hour), Weekly in days (hours on the last day, minutes in the last hour)
ourTaskTimers={}
local function fmtLeft(sec,weekly)
  sec=math.max(0,math.floor(sec))
  if sec<3600 then return math.max(1,math.ceil(sec/60))..' min' end
  if weekly and sec>=86400 then local d=math.ceil(sec/86400);return d..(d==1 and ' day' or ' days') end
  return math.ceil(sec/3600)..'h'
end
function ourTaskTimersTick()
  local now=g_clock.seconds()
  for _,t in ipairs(ourTaskTimers) do
    if not t.label:isDestroyed() then
      t.label:setText(t.name..' ('..fmtLeft(t.ends-now,t.weekly)..')')
      t.label:setTooltip(t.name..' tasks reset in '..fmtLeft(t.ends-now,t.weekly))
    end
  end
end
-- 14.10.2026 (Tobeto): glow of the empty autoloot slots while any item is being dragged
ourLootEmpty={}
local glowState,glowEvent=nil,nil
function ourLootDragGlow(force)
  local ok,drag=pcall(function() return g_ui.getDraggingWidget() end)
  -- 16.10.2026 (Tobeto): only for items that can be picked up (not a chair, a creature or a wall)
  local thing=ok and drag and drag.currentDragThing
  local dragging=false
  if thing then
    local okp,pick=pcall(function() return thing:isItem() and thing:isPickupable() end)
    dragging=okp and pick and true or false
  end
  local key=tostring(dragging)
  for _,row in ipairs(ourLootEmpty) do if not row:isDestroyed() and row:isHovered() then key=key..tostring(row) end end
  if not force and key==glowState then return end
  glowState=key
  for _,row in ipairs(ourLootEmpty) do
    if not row:isDestroyed() then
      local hot=dragging and row:isHovered()
      row:setBorderWidth(dragging and 1 or 0)
      row:setBorderColor(hot and '#ffd35a' or (dragging and '#9a7a28' or '#00000000'))
      local plus=row:getChildById('plus');if plus then plus:setColor(hot and '#ffd35a' or (dragging and '#c8a040' or '#8a8a8a')) end
    end
  end
end
local glowStopped=false
function ourStopLootGlow() glowStopped=true;if glowEvent then removeEvent(glowEvent);glowEvent=nil end end
local function glowTick()
  glowEvent=nil
  if glowStopped then return end
  if #ourLootEmpty>0 then pcall(ourLootDragGlow) end
  ourTaskTick=(ourTaskTick or 0)+1;if ourTaskTick%250==0 then pcall(ourTaskTimersTick) end
  glowEvent=scheduleEvent(glowTick,120)
end
glowEvent=scheduleEvent(glowTick,1000)
-- Unlooted corpses: diagonal shimmer on the corpse sprite (server sends the list).
local corpseList,corpseTimer={},nil
local function corpseItems(pos)
  local tile=g_map.getTile(pos);local out={}
  if tile then for _,item in ipairs(tile:getItems()) do if item:isContainer() then out[#out+1]=item end end end
  return out
end
local function applyCorpseShimmer()
  -- 06.10.2026: unlooted corpses shimmer like unidentified items (user request)
  local normal=RarityFrames and RarityFrames.shimmer or 'Item - Shimmer'
  local rare=RarityFrames and RarityFrames.corpseGlowRare or 'Item - Corpse Glow Rare'
  local F=RarityFrames
  for _,pos in ipairs(corpseList) do
    -- 03.10.2026: a corpse with an unidentified item glows purple
    local shader=pos.u and rare or normal
    -- 18.10.2026 (owner): each corpse has its own animation (variant by its tile)
    if F and F.corpseVariant and F.corpseShimmer then
      local v=F.corpseVariant(pos)
      shader=pos.u and F.corpseRare[v] or F.corpseShimmer[v]
    end
    for _,item in ipairs(corpseItems(pos)) do if item.ourCorpseShimmer~=shader then item:setShader(shader);item.ourCorpseShimmer=shader end end
  end
end
local function setCorpses(list)
  for _,pos in ipairs(corpseList) do
    for _,item in ipairs(corpseItems(pos)) do if item.ourCorpseShimmer then item:setShader('');item.ourCorpseShimmer=nil end end
  end
  corpseList={}
  for _,p in ipairs(type(list)=='table' and list or {}) do
    if tonumber(p.x) then corpseList[#corpseList+1]={x=tonumber(p.x),y=tonumber(p.y),z=tonumber(p.z),u=p.u and true or nil} end
  end
  applyCorpseShimmer()
  if #corpseList>0 and not corpseTimer then
    corpseTimer=cycleEvent(function() if #corpseList==0 then removeEvent(corpseTimer);corpseTimer=nil else applyCorpseShimmer() end end,700)
  end
end
-- Mark chance: small cross next to the marked creature's name.
-- OurTibia (03.10.2026): drawn as an attached image effect above the name;
-- setIconTexture is not drawn for monsters in this client, so the cross never
-- appeared on them.
local MARK_EFFECT=7400
local markRegistered=false
local function markEffect()
  if not g_attachedEffects then return nil end
  if not markRegistered then
    local ok,e=pcall(function() return g_attachedEffects.registerByImage(MARK_EFFECT,'rarity mark','/game_myotshud/images/mark',false) end)
    if not ok or not e then return nil end
    for d=0,7 do pcall(function() e:setDirOffset(d,0,26,true) end) end
    pcall(function() e:setCanDrawOnUI(false) end)
    markRegistered=true
  end
  -- attach a copy (getById clones the registered template)
  return g_attachedEffects.getById(MARK_EFFECT)
end
local function setMark(id,on)
  local creature=g_map.getCreatureById(tonumber(id) or 0);if not creature then return end
  pcall(function() creature:detachEffectById(MARK_EFFECT) end)
  if on then local eff=markEffect();if eff then pcall(function() creature:attachEffect(eff) end) end end
end
-- OurTibia (06.10.2026): timers of utura sio / exeta res above the creature
-- (icon while the effect lasts + seconds left shown in the icon tooltip-free label)
-- 14.10.2026: Guardian (shield) and Adrenaline Rush (text, then haste icon) in the utura sio place
local CT_EFFECT={sio=7401,res=7402,guardian=7403,haste=7404,adrtext=7405}
local CT_OFFSET={sio={-10,30},res={10,30},guardian={-10,30},haste={-10,30},adrtext={23,46}}
local ctRegistered={}
local ctEvents={}
local function ctEffect(kind)
  local id=CT_EFFECT[kind];if not id or not g_attachedEffects then return nil end
  if not ctRegistered[kind] then
    local ok,e=pcall(function() return g_attachedEffects.registerByImage(id,'timer '..kind,'/game_myotshud/images/buff_'..kind,false) end)
    if not ok or not e then return nil end
    local off=CT_OFFSET[kind] or {10,30}
    for d=0,7 do pcall(function() e:setDirOffset(d,off[1],off[2],true) end) end
    pcall(function() e:setCanDrawOnUI(false) end)
    ctRegistered[kind]=true
  end
  return g_attachedEffects.getById(id)
end
local creatureTimer
local function creatureTimerRaw(id,kind,ms)
  local creature=g_map.getCreatureById(tonumber(id) or 0);if not creature then return end
  local effId=CT_EFFECT[kind];if not effId then return end
  local key=tostring(id)..kind
  if ctEvents[key] then removeEvent(ctEvents[key]);ctEvents[key]=nil end
  pcall(function() creature:detachEffectById(effId) end)
  local eff=ctEffect(kind);if eff then pcall(function() creature:attachEffect(eff) end) end
  ctEvents[key]=scheduleEvent(function()
    ctEvents[key]=nil
    local c=g_map.getCreatureById(tonumber(id) or 0)
    if c then pcall(function() c:detachEffectById(effId) end) end
  end,math.max(500,tonumber(ms) or 3000))
end
-- Adrenaline Rush: "ADRENALINE!" for 1 s, then the haste icon for the rest of the buff.
creatureTimer=function(id,kind,ms)
  if kind=='adrenaline' then
    ms=tonumber(ms) or 3000
    creatureTimerRaw(id,'adrtext',1000)
    local key=tostring(id)..'adrdelay'
    if ctEvents[key] then removeEvent(ctEvents[key]) end
    ctEvents[key]=scheduleEvent(function() ctEvents[key]=nil;creatureTimerRaw(id,'haste',math.max(500,ms-1000)) end,1000)
    return
  end
  creatureTimerRaw(id,kind,ms)
end
local catWindow
local function showCatList(data)
  -- 08.10.2026: rebuilt - an unknown scrollbar method stopped it half way
  -- (empty list and no Close button)
  -- 08.10.2026: long lists come in pages - next pages are added to the open window
  if data.page and data.page>1 and catWindow and catWindow.catList and catWindow.catKey==data.cat then
    for _,it in ipairs(data.items or {}) do catWindow.addRow(it) end
    return
  end
  if catWindow then catWindow:destroy();catWindow=nil end
  local titles={gold='Autoloot gold',valuables='Autoloot valuables',products='Creature products'}
  catWindow=g_ui.createWidget('MainWindow',rootWidget)
  catWindow:setText((titles[data.cat] or 'Autoloot')..' - '..(data.total or #(data.items or {}))..' items')
  catWindow.catKey=data.cat
  catWindow:setSize({width=300,height=420})
  local function closeIt() if catWindow then catWindow:destroy();catWindow=nil end end
  local close=g_ui.createWidget('Button',catWindow);close:setText('Close');close:setWidth(70)
  close:addAnchor(AnchorRight,'parent',AnchorRight);close:addAnchor(AnchorBottom,'parent',AnchorBottom)
  close.onClick=closeIt
  catWindow.onEscape=closeIt
  local list=g_ui.createWidget('ScrollablePanel',catWindow)
  list:addAnchor(AnchorTop,'parent',AnchorTop);list:addAnchor(AnchorLeft,'parent',AnchorLeft)
  list:addAnchor(AnchorBottom,'parent',AnchorBottom);list:setMarginBottom(28)
  local bar=g_ui.createWidget('VerticalScrollBar',catWindow)
  bar:setId('catScroll')
  bar:addAnchor(AnchorTop,'parent',AnchorTop);bar:addAnchor(AnchorRight,'parent',AnchorRight);bar:addAnchor(AnchorBottom,'parent',AnchorBottom);bar:setMarginBottom(28)
  pcall(function() bar:setStep(34) end)
  list:addAnchor(AnchorRight,'catScroll',AnchorLeft)
  pcall(function() list:setVerticalScrollBar(bar) end)
  local layout=UIVerticalLayout.create(list);layout:setSpacing(2);list:setLayout(layout)
  catWindow.catList=list
  catWindow.addRow=function(it)
    local row=g_ui.createWidget('UIWidget',list);row:setHeight(34)
    local icon=g_ui.createWidget('UIItem',row);pcall(function() icon:setVirtual(true) end)
    icon:setSize({width=32,height=32});icon:setItemId(it.c)
    icon:addAnchor(AnchorLeft,'parent',AnchorLeft);icon:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter)
    local l=g_ui.createWidget('Label',row);l:setText(it.n or '');l:setColor('#e0e0e0')
    l:addAnchor(AnchorLeft,'prev',AnchorRight);l:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter);l:setMarginLeft(8);l:setTextAutoResize(true)
  end
  for _,it in ipairs(data.items or {}) do catWindow.addRow(it) end
  catWindow:centerIn('parent');catWindow:show();catWindow:raise();catWindow:focus()
end
local function onPacket(protocol,code,buffer)
  local ok,data=pcall(json.decode,buffer);if not ok then return end
  if data.kind=='corpses' then setCorpses(data.list);return end
  if data.kind=='catlist' then showCatList(data);return end
  if data.kind=='expiry' then if modules.game_inventory and modules.game_inventory.setOurExpiry then modules.game_inventory.setOurExpiry(data.list) end;return end
  if data.kind=='mark' then setMark(data.id,data.on);return end
  if data.kind=='ctimer' then creatureTimer(data.id,data.t,data.ms);return end
  if data.kind=='potioncd' then local ab=modules.game_actionbar;if ab and ab.ourPotionCooldown then pcall(ab.ourPotionCooldown,data.ms) end;return end
  if data.kind=='bossbar' then if OurBossBar then OurBossBar.set(data) end;return end
  if data.kind=='boosts' then if BoostBar then BoostBar.set(data.list,data.fund,data.fundStep) end;return end
  if data.kind=='killtracker' then if state then state.recent=data.recent;drawKills() end;return end
  if data.kind=='bless' then if modules.game_blessing and modules.game_blessing.ourBless then pcall(modules.game_blessing.ourBless,data) end;return end
  if data.kind=='state' then
    if type(data.loot)=='table' and type(data.loot.productCids)=='table' then lootProducts={};for _,c in ipairs(data.loot.productCids) do lootProducts[tonumber(c)]=true end end
    state=data;drawState()
  elseif data.kind=='combat' then
    session.damage=(session.damage or 0)+(data.dealt or 0)
    if DpsMeter then DpsMeter.add(data.dealt) end
    session.received=(session.received or 0)+(data.received or 0)
    session.healing=(session.healing or 0)+(data.healed or 0)
    session.peak=math.max(session.peak or 0,data.dealt or 0)
  elseif data.kind=='kill' then session.kills=session.kills+data.amount
  elseif data.kind=='loot' then
    for _,item in ipairs(data.items or {}) do session.loot=session.loot+item.count;session.items[item.sid]=(session.items[item.sid] or 0)+item.count end
  end
end
local function onTrainerMessage(mode,text)
  if type(text)=='string' and text:find('magic item to cast',1,true) then trainer.noBlankUntil=os.time()+30 end
end
local function onExperience(player,experience)
  if lastExperience>0 and experience>lastExperience then session.xp=session.xp+experience-lastExperience end
  lastExperience=experience
end
function resetSession()
  session={start=os.time(),xp=0,loot=0,kills=0,items={}}
  local p=g_game.getLocalPlayer();lastExperience=p and p:getExperience() or 0
end
local function trimWords(words) return ((words or ''):lower():gsub('^%s+',''):gsub('%s+$',''):gsub('%s+',' ')) end
local function spell(words,p)
  words=trimWords(words);if words=='' then return nil end
  for _,s in pairs(refs.spells or {}) do if trimWords(s.words)==words then
    -- 17.10.2026 (Tobeto): the trainer only checks that the spell exists - the server decides the rest
    -- (catalog values like level / magic level / soul could be wrong and blocked spells you can cast)
    do return s end
    if p:getLevel()<(s.level or 0) or p:getMagicLevel()<(s.magiclevel or 0) or p:getMana()<(s.mana or 0) or p:getSoul()<(s.soul or 0) then
      -- 17.10.2026: say exactly what is missing
      local miss={}
      if p:getLevel()<(s.level or 0) then miss[#miss+1]='level '..s.level..' (you have '..p:getLevel()..')' end
      if p:getMagicLevel()<(s.magiclevel or 0) then miss[#miss+1]='magic level '..s.magiclevel..' (you have '..p:getMagicLevel()..')' end
      if p:getMana()<(s.mana or 0) then miss[#miss+1]=s.mana..' mana (you have '..p:getMana()..')' end
      if p:getSoul()<(s.soul or 0) then miss[#miss+1]=s.soul..' soul (you have '..p:getSoul()..')' end
      return nil,table.concat(miss,', ')
    end
    return s
  end end
  -- spells missing from the client catalog (it has only part of the spells) are still cast;
  -- the server decides if it is possible
  return {words=words}
end
-- Rune spells (adori/adevo/adito/adana/adeta/adura...) need a blank rune;
-- conjuring arrows/bolts/spears (exevo con...) and other spells do not.
local function needsBlankRune(words) return trimWords(words):sub(1,2)=='ad' end
function MyotsTrainerSet(k,v) trainer[k]=v;updateTrainerButton();saveTrainer() end
function trainingDecision(p,settings,hasBlankRune)
  if not settings.enabled then return nil end
  local percent=p:getMana()/math.max(1,p:getMaxMana())*100
  local runeNeed=tonumber(settings.runeThreshold or settings.threshold) or 90
  local manaNeed=tonumber(settings.manaThreshold or settings.threshold) or 90
  if settings.runes==true and percent >= runeNeed and (hasBlankRune or not needsBlankRune(settings.runeSpell)) and spell(settings.runeSpell,p) then return trimWords(settings.runeSpell) end
  if settings.mana==true and percent >= manaNeed and spell(settings.manaSpell,p) then return trimWords(settings.manaSpell) end
end
local function train(p)
  -- 05.10.2026: the client only sees items in OPEN containers, so a blank rune in a
  -- closed backpack was "missing" and the rune maker never cast. The server
  -- decides now; after "You need a magic item" the rune spell waits 30 s.
  local noBlank=(trainer.noBlankUntil or 0)>os.time()
  local words=trainingDecision(p,trainer,not noBlank)
  if words then g_game.talk(words);trainer.warned=nil
  elseif trainer.enabled and not trainer.warned and (trainer.mana or trainer.runes) then
    local sp=trimWords(trainer.mana and trainer.manaSpell or trainer.runeSpell)
    local percent=math.floor(p:getMana()/math.max(1,p:getMaxMana())*100)
    local need=tonumber(trainer.mana and trainer.manaThreshold or trainer.runeThreshold) or 90
    if percent>=need then local ok,why=spell(sp,p);if not ok then trainer.warned=true;statusMessage('Trainer: "'..sp..'" needs '..(why or 'more level or mana')..'.') end end
  end
  -- These two checkboxes are independent of the spell-training switch.
  if trainer.food and (p:getRegenerationTime() or 0)<600 then command('trainer:food') end
  if trainer.idle and os.time()-lastTurn>=60 then
    lastTurn=os.time();g_game.turn((p:getDirection()+1)%4)
  end
  -- Retarget dummy (02.10.2026): attack a training dummy in range when not
  -- attacking anything (for example after a relog or a lost target).
  if trainer.retarget and not g_game.isAttacking() then
    local pos=p:getPosition();local best,bestDist
    for _,c in ipairs(pos and g_map.getSpectators(pos,false) or {}) do
      if c:isMonster() and c:getName():lower():find('training dummy',1,true) then
        local q=c:getPosition()
        if q and q.z==pos.z then
          local d=math.max(math.abs(q.x-pos.x),math.abs(q.y-pos.y))
          if d<=7 and (not bestDist or d<bestDist) then best,bestDist=c,d end
        end
      end
    end
    if best then g_game.attack(best) end
  end
end
local tickInner
local function tick()
  local ok,err=pcall(tickInner)
  if not ok then print('[MyOTS HUD] tick: '..tostring(err)) end
  if timer~=false then timer=scheduleEvent(tick,2000) end
end
tickInner=function()
  if g_game.isOnline() then
    local p=g_game.getLocalPlayer();local elapsed=math.max(1,os.time()-session.start)
    fields.xp:setText(string.format('Session: %02d:%02d\nXP Gain: %d\nXP/h: %d\nLooted items: %d',math.floor(elapsed/3600),math.floor(elapsed/60)%60,session.xp,math.floor(session.xp*3600/elapsed),session.loot))
    fields.hunt:setText(string.format('Session: %d min\nXP Gain: %d\nXP/h: %d\nKill credit: %g\nLooted items: %d\nDamage dealt: %d\nDamage/h: %d\nDamage taken: %d\nHealing: %d\nLargest hit: %d',math.floor(elapsed/60),session.xp,math.floor(session.xp*3600/elapsed),session.kills,session.loot,session.damage or 0,math.floor((session.damage or 0)*3600/elapsed),session.received or 0,session.healing or 0,session.peak or 0))
    local lootLines={}
    for sid,count in pairs(session.items) do local item=itemRef(sid);lootLines[#lootLines+1]=(item and item.name or tostring(sid))..': '..count end
    table.sort(lootLines);fields.lootSummary:setText(#lootLines>0 and table.concat(lootLines,'\n') or 'No items looted this session.')
    local okT,errT=pcall(train,p);if not okT then print('[MyOTS HUD] trainer: '..tostring(errT)) end
  end
end
-- OurTibia (02.10.2026): the side panels are not focusable (the chat keeps
-- the keyboard), so a text field there needs to unlock them when clicked.
local editFocused=nil
local function releaseEdit()
  if not editFocused then return end
  editFocused=nil
  pcall(function() modules.game_interface.toggleFocus(false,'myotsEdit') end)
end
local mapHooked=false
local function hookMap()
  if mapHooked then return end
  local map=modules.game_interface and modules.game_interface.getMapPanel and modules.game_interface.getMapPanel()
  if map then mapHooked=true;connect(map,{onMousePress=function() releaseEdit() end}) end
end
local function editable(field)
  g_keyboard.bindKeyDown('Enter',releaseEdit,field)
  g_keyboard.bindKeyDown('Escape',releaseEdit,field)
  field.onMousePress=function(w,pos,button)
    if button==MouseLeftButton then
      pcall(function() modules.game_interface.toggleFocus(true,'myotsEdit') end)
      -- focus the whole chain (text field -> panel -> mini window -> side panel)
      local chain={};local x=w
      while x and x~=rootWidget do chain[#chain+1]=x;x=x:getParent() end
      for _,a in ipairs(chain) do
        if not a:isFocusable() then a.ourFocusRestore=true;a:setFocusable(true) end
      end
      for _,a in ipairs(chain) do pcall(function() a:focus() end) end
      editFocused=w;hookMap()
    end
    return false
  end
  field.onFocusChange=function(w,focused)
    if focused then return end
    local x=w:getParent()
    while x and x~=rootWidget do
      if x.ourFocusRestore then x.ourFocusRestore=nil;x:setFocusable(false) end
      x=x:getParent()
    end
    pcall(function() modules.game_interface.toggleFocus(false,'myotsEdit') end)
  end
  return field
end
local function start()
  scheduleEvent(function() pcall(ourCapPanels) end,3000);scheduleEvent(function() pcall(ourCapPanels) end,9000)
  -- 10.10.2026: the default layout is set only the first time; afterwards the client
  -- keeps what the player arranged (panels, window positions and sizes, closed windows).
  local firstLayout=not g_settings.getBoolean('myotsLayoutDone')
  if firstLayout then
    modules.client_options.setOption('showLeftPanel',true)
    modules.client_options.setOption('showLeftExtraPanel',true)
    modules.client_options.setOption('showRightExtraPanel',true)
    g_settings.set('myotsLayoutDone',true)
  end
  for _,w in pairs(windows) do pcall(function() w:setupOnStart() end) end
  scheduleEvent(function()
    local skills=g_game.isOnline() and modules.game_skills.skillsWindow
    if skills and not (skills.getSettings and skills:getSettings('parentId')) then
      skills:setParent(modules.game_interface.getRightExtraPanel())
      skills:setHeight(670)
      skills:show()
    end
  end,150)
  local p=g_game.getLocalPlayer();local saved=g_settings.getNode('myots-trainer-'..p:getName():gsub('[^%w]','_')) or g_settings.getNode('myots-trainer-'..p:getName()) or {}
  -- 07.10.2026: settings come back as strings ("90", "false") - the comparison with a
  -- string threw an error every tick, so the trainer never cast after a relog.
  for k,v in pairs(saved) do
    if v=='true' then v=true elseif v=='false' then v=false end
    if (k=='manaThreshold' or k=='runeThreshold' or k=='threshold') then v=tonumber(v) or 90 end
    trainer[k]=v
  end
  trainer.enabled=saved.enabled==true or saved.enabled=='true';trainer.noBlankUntil=nil
  trainer.manaThreshold=tonumber(saved.manaThreshold or saved.threshold) or 90
  trainer.runeThreshold=tonumber(saved.runeThreshold or saved.threshold) or 90
  lastTurn=0
  loading=true
  for _,k in ipairs({'mana','runes','food','idle','retarget'}) do fields['train_'..k]:setChecked(trainer[k]) end
  fields.manaSpell:setText(trainer.manaSpell);fields.runeSpell:setText(trainer.runeSpell);fields.manaThreshold:setText(tostring(trainer.manaThreshold));fields.runeThreshold:setText(tostring(trainer.runeThreshold))
  loading=false;updateTrainerButton();resetSession();command('state');scheduleEvent(function() command('bless') end,1500)
  if not timer then tick() end
end
local function stop()
  productsAsked=false
  if BoostBar then BoostBar.clear() end
  if OurBossBar then OurBossBar.clear() end
  corpseList={};if corpseTimer then removeEvent(corpseTimer);corpseTimer=nil end
  saveTrainer();updateTrainerButton()
  -- 10.10.2026: write the layout to disk at logout too (not only when the client closes normally)
  pcall(function() g_settings.save() end)
  if timer then removeEvent(timer);timer=nil end
  daily:hide();if passiveWindow then passiveWindow:hide() end
  if exclWindow then exclWindow:hide() end
end
-- 18.10.2026 (Tobeto): with the NPC trade window (or another window outside the game panel)
-- focused, the game hotkeys (mana potion...) stopped working - they are bound to the game
-- panel, which no longer got the keys. Keys nobody used are passed on to the game panel,
-- except while typing in a text field.
local keyForward={}
local function forwardKey(kind)
  return function(_,keyCode,modifiers,...)
    if not g_game.isOnline() or not gameRootPanel then return false end
    local f=rootWidget:getFocusedChild()
    if not f or f==gameRootPanel then return false end
    local deep=f
    while deep and deep:getFocusedChild() do deep=deep:getFocusedChild() end
    if deep and (deep:getClassName()=='UITextEdit' or deep:getClassName()=='UISpinBox') then return false end
    local h=gameRootPanel[kind]
    if h==nil then return false end
    return signalcall(h,gameRootPanel,keyCode,modifiers,...) and true or false
  end
end
local function hookKeyForward()
  if keyForward.on then return end
  keyForward={on=true,onKeyDown=forwardKey('onKeyDown'),onKeyPress=forwardKey('onKeyPress'),onKeyUp=forwardKey('onKeyUp')}
  connect(rootWidget,{onKeyDown=keyForward.onKeyDown,onKeyPress=keyForward.onKeyPress,onKeyUp=keyForward.onKeyUp})
end
local function unhookKeyForward()
  if not keyForward.on then return end
  disconnect(rootWidget,{onKeyDown=keyForward.onKeyDown,onKeyPress=keyForward.onKeyPress,onKeyUp=keyForward.onKeyUp})
  keyForward={}
end
function init()
  pcall(hookKeyForward)
  RarityFrames.init()
  refs=json.decode(g_resources.readFileContents('/data/myots/hud.json'))
  g_ui.importStyle('hud')
  local left=modules.game_interface.getLeftPanel();local extra=modules.game_interface.getLeftExtraPanel()
  local spells=panel('myotsCooldowns','Spell Cooldowns',75,left)
  if modules.game_cooldown and modules.game_cooldown.cooldownWindow then modules.game_cooldown.cooldownWindow:setParent(content(spells)) end
  local kills=panel('myotsKills','Kill Tracker',355,left)
  local xp=panel('myotsXp','XP Analyzer',132,left)
  fields.xp=label(content(xp),'Session: 00:00');fields.xp:setHeight(65)
  button(content(xp),'Reset session',resetSession)
  local tasks=panel('myotsTasks','Task Tracker',100,left)
  -- 18.10.2026 (Tobeto): the Task Board button is back on top of the tracker
  button(content(tasks),'Task Board',function() showDaily() end)
  -- 15.10.2026 (Tobeto): the Task Board button is on top of the tracker
  -- 15.10.2026 (Tobeto): no Task Board button any more - a click on a free task slot opens the Task Board
  fields.dailyStatus=label(content(tasks),'No active task')
  fields.taskRows=g_ui.createWidget('TaskRows',content(tasks))
  local loot=panel('myotsLoot','Autolooting',590,extra);local c=content(loot)
  -- Mythibia-like layout: a section per category with its destination
  -- container slot and "[+]" buttons; custom items are picked with a
  -- crosshair ("[+] Add an item" or a click on an empty slot).
  local function pickBag(category)
    scheduleEvent(function() modules.game_interface.startItemSelection(function(item)
      if not item or not item.isContainer or not item:isContainer() then statusMessage('Select a backpack container.');return end
      local pos=item.getPosition and item:getPosition() or nil
      if pos and pos.x~=65535 then statusMessage('Pick up the backpack and put it inside your equipped backpack first.');return end
      command('bag:'..category..':'..item:getId())
    end) end,50)
  end
  MyOTSHudPickItem=function(slotIndex)
    -- Start on the next frame: started inside onClick, the same mouse
    -- release ended the selection at once ("Select an item.").
    scheduleEvent(function() modules.game_interface.startItemSelection(function(item)
      if not item or not item.getId then statusMessage('Select an item.');return end
      command('item:add:'..item:getId()..(slotIndex and (':'..slotIndex) or ''))
    end,true) end,50)
  end
  -- 08.10.2026: compact layout (checkbox, [i], container slot on the right)
  local function section(category,title,optionName,withInfo)
    local row=g_ui.createWidget('LootCatRow',c);row:setId('bag_'..category)
    fields[category..'Bag']=row
    local box=row:getChildById('check');box:setText(title)
    local name=optionName
    box.onCheckChange=function(_,v) if not loading then command('loot:'..name..':'..(v and 1 or 0)) end end
    fields[optionName]=box
    if withInfo then
      local info=row:getChildById('info');info:setVisible(true)
      info:setTooltip('Show all items looted by this option')
      info.onClick=function() command('catlist:'..category) end
    end
    local icon=row:getChildById('itemIcon')
    icon:setTooltip('Destination container. Click to choose it.')
    icon.onMouseRelease=function(_,_,mouseButton) if mouseButton==MouseLeftButton then pickBag(category);return true end;return false end
    row:getChildById('remove').onClick=function() command('bag:'..category..':0') end
    return row
  end
  -- "Autoloot: ON / OFF" button in the same style as "Trainer: ON / OFF"
  do
    local on=false
    local b=button(c,'Autoloot: OFF',nil)
    b:setHeight(20) -- 17.10.2026 (Tobeto): 1 px less at the top, 2 px less at the bottom
    local function paint() b:setText(on and 'Autoloot: ON' or 'Autoloot: OFF');b:setColor(on and '#66dd44' or '#ff5555');b:setTooltip(on and 'Autoloot is on (click to stop)' or 'Autoloot is off (click to start)') end
    b.onClick=function() on=not on;paint();command('loot:enabled:'..(on and 1 or 0)) end
    fields.enabled={setChecked=function(_,v) on=v and true or false;paint() end,isChecked=function() return on end}
    paint()
    pinTop(loot,b)
  end
  section('gold','Autoloot gold','gold',false)
  fields.convert=check(c,'Auto conversion',function(v)command('loot:convert:'..(v and 1 or 0))end)
  section('valuables','Autoloot valuables','valuables',true)
  section('products','Creature products','products',true)
  fields.products:setTooltip('Creature products (e.g. dragon scales) are looted automatically; they cannot be added to item slots.')
  fields.exclButton=button(c,'Excluded items',function() showLootExclusions() end)
  -- 15.10.2026 (Tobeto): part of Creature products - indented under it
  fields.exclButton:setMarginLeft(18);fields.exclButton:setWidth(148);fields.exclButton:setHeight(20);fields.exclButton:setTextOffset({x=0,y=-1})
  fields.exclButton:setTooltip('Items that are never auto-looted. Right-click an item -> Exclude from auto-loot.')
  section('items','Autoloot items','items',false)
  fields.items:setTooltip('Loot the items placed in the slots below. Click an empty slot, then click an item.')
  local pages=g_ui.createWidget('LootPages',c)
  for page=1,4 do
    local number=page;local b=g_ui.createWidget('LootPageButton',pages);b:setText(tostring(page))
    b:addAnchor(AnchorTop,'parent',AnchorTop);b:addAnchor(AnchorLeft,'parent',AnchorLeft);b:setMarginLeft((page-1)*21)
    b.onClick=function() command('preset:'..number) end;fields['preset'..page]=b
  end
  fields.lootItems=g_ui.createWidget('LootSlotGrid',c)
  local training=panel('myotsTrainer','Trainer',400,extra);c=content(training)
  -- 07.10.2026: one toggle for the panel button and the top bar button
  toggleTrainer=function()
    trainer.enabled=not trainer.enabled;trainer.warned=nil;updateTrainerButton();saveTrainer()
    statusMessage(trainer.enabled and ('Trainer ON: '..(trainer.mana and (tostring(trainer.manaSpell)..' at '..tostring(trainer.manaThreshold)..'% mana') or 'mana training off')..(trainer.runes and (', runes: '..tostring(trainer.runeSpell)) or '')) or 'Trainer OFF')
    if trainer.enabled and g_game.isOnline() then pcall(train,g_game.getLocalPlayer()) end
  end
  trainerButton=button(c,'Trainer: OFF',function() toggleTrainer() end)
  trainerButton:setHeight(20) -- 17.10.2026 (Tobeto): 1 px less at the top, 2 px less at the bottom
  pinTop(training,trainerButton)
  -- 15.10.2026 (Tobeto): two separate groups, fields indented under their checkbox
  for index,entry in ipairs({{'mana','Mana training','manaSpell','manaThreshold'}, {'runes','Rune maker','runeSpell','runeThreshold'}}) do
    local key,title,spellKey,thresholdKey=entry[1],entry[2],entry[3],entry[4]
    -- 17.10.2026 (Tobeto): no line between the Trainer: ON/OFF button and the options
    if index>1 then local sep=g_ui.createWidget('HorizontalSeparator',c);sep:setMarginTop(6);sep:setMarginBottom(3) end
    -- 05.10.2026: ticking Mana Training / Rune Maker switches the trainer on (players
    -- ticked the box and never pressed "Trainer: OFF", so nothing was cast).
    fields['train_'..key]=check(c,title,function(v)trainer[key]=v;if v and not loading then trainer.enabled=true;updateTrainerButton() end;saveTrainer()end)
    -- 18.10.2026 (Tobeto): one row - spell field, then a small 0-100 mana % field with an
    -- up/down button (click or hold); no "Minimum mana (%)" label, fields as tall as the cursor
    local spellLabel=g_ui.createWidget('HudSubLabel',c);spellLabel:setText('Spell')
    local row=g_ui.createWidget('UIWidget',c);row:setHeight(16);row:setMarginLeft(18);row:setMarginRight(2)
    local spinBox=g_ui.createWidget('HudSpin',row)
    local num=editable(g_ui.createWidget('HudNumField',row))
    fields[spellKey]=editable(g_ui.createWidget('HudRowField',row))
    pcall(function() fields[spellKey]:setMaxLength(30) end) -- 16.10.2026 (Tobeto): limit
    fields[spellKey].onTextChange=function(_,v)if not loading then trainer[spellKey]=v;saveTrainer()end end
    fields[thresholdKey]=num
    num:setTooltip('Minimum mana (%) - the spell is cast when your mana is at least this high')
    pcall(function() num:setMaxLength(3) end)
    -- 16.10.2026 (Tobeto): numbers only, 0 - 100
    num.onTextChange=function(w,v)
      local d=v:gsub('%D','')
      if tonumber(d) and tonumber(d)>100 then d='100' end
      if d~=v then w:setText(d);pcall(function() w:setCursorPos(#d) end);return end
      if not loading and d~='' then trainer[thresholdKey]=math.max(0,math.min(100,tonumber(d)));saveTrainer() end
    end
    local function stepValue(delta)
      local v=math.max(0,math.min(100,(tonumber(num:getText()) or tonumber(trainer[thresholdKey]) or 90)+delta))
      num:setText(tostring(v))
    end
    for _,b in ipairs({{'up',1},{'down',-1}}) do
      local btn=spinBox:getChildById(b[1]);local delta=b[2]
      btn.onMousePress=function(_,_,button)
        if button~=MouseLeftButton then return false end
        stepValue(delta)
        if btn.repeatEvent then removeEvent(btn.repeatEvent) end
        local function again(ms) btn.repeatEvent=scheduleEvent(function() stepValue(delta);again(60) end,ms) end
        again(400);return true
      end
      btn.onMouseRelease=function() if btn.repeatEvent then removeEvent(btn.repeatEvent);btn.repeatEvent=nil end;return true end
    end
  end
  do local sep=g_ui.createWidget('HorizontalSeparator',c);sep:setMarginTop(6);sep:setMarginBottom(3) end
  fields.train_idle=check(c,'Anti-Idle',function(v)trainer.idle=v;saveTrainer()end)
  fields.train_food=check(c,'Auto-Eat Food',function(v)trainer.food=v;saveTrainer()end)
  fields.train_retarget=check(c,'Retarget dummy',function(v)trainer.retarget=v;saveTrainer()end)
  -- 18.10.2026 (Tobeto): the three options closer together
  for _,k in ipairs({'train_idle','train_food','train_retarget'}) do fields[k]:setHeight(16) end
  local hunt=panel('myotsHunt','Hunt Analyzer',250,left);fields.hunt=label(content(hunt),'');fields.hunt:setHeight(200);hunt:close()
  local lootSummary=panel('myotsLootSummary','Loot Analyzer',240,left)
  fields.lootSummary=label(content(lootSummary),'');fields.lootSummary:setHeight(600);fields.lootSummary:setTextWrap(true);lootSummary:close()
  -- 04.10.2026 user: the Analyzers & Panels window is removed from the client.
  daily=g_ui.displayUI('daily');daily:hide()
  buttons[1]=modules.client_topmenu.addRightGameButton('myotsDaily','Task Board','/images/topbuttons/myots_taskboard',showDaily)
  buttons[3]=modules.client_topmenu.addRightGameButton('ourFullscreen','Fullscreen','/images/topbuttons/zoomin',toggleFullscreen)
  -- 07.10.2026: the Kill Tracker window can be opened again after closing it
  -- 07.10.2026: 40x20 option images (same size as the other buttons, no artefact when held);
  -- Trainer and Autoloot buttons open their windows again after closing them.
  buttons[5]=modules.client_topmenu.addRightGameButton('myotsKillTracker','Kill Tracker','/images/options/bestiaryTracker',function() if windows.myotsKills then toggle(windows.myotsKills) end end)
  buttons[4]=modules.client_topmenu.addRightGameButton('myotsTrainerToggle','Trainer','/images/options/cooldowns',function() if windows.myotsTrainer then toggle(windows.myotsTrainer) end end)
  -- 14.10.2026 (owner): the Task Tracker window can be opened again with its own button
  buttons[7]=modules.client_topmenu.addRightGameButton('myotsTaskTracker','Task Tracker','/images/options/button_taskboard',function() if windows.myotsTasks then toggle(windows.myotsTasks) end end)
  buttons[6]=modules.client_topmenu.addRightGameButton('myotsAutolootWindow','Autolooting','/images/options/myots_autoloot',function() if windows.myotsLoot then toggle(windows.myotsLoot) end end)
  -- 04.10.2026: F11 no longer toggles fullscreen (free for hotkeys); use the button.
  -- OurTibia (03.10.2026): the Game Panels button became the Group Finder; the panels window was removed on 04.10.2026.
  buttons[2]=modules.client_topmenu.addRightGameButton('groupFinder','Group Finder (Ctrl+F)','/images/topbuttons/myots_groupfinder',function() if modules.game_groupfinder then modules.game_groupfinder.toggle() end end)
  ProtocolGame.registerExtendedOpcode(102,onPacket)
  ItemForge.init()
  DpsMeter.init()
  connect(g_game,{onGameStart=start,onGameEnd=stop,onTextMessage=onTrainerMessage});connect(LocalPlayer,{onExperienceChange=onExperience})
  updateTrainerButton()
end
function terminate()
  pcall(unhookKeyForward)
  pcall(ourStopLootGlow)
  RarityFrames.terminate()
  ItemForge.terminate()
  DpsMeter.terminate()
  if BoostBar then BoostBar.clear() end
  if OurBossBar then OurBossBar.clear() end
  stop();disconnect(g_game,{onGameStart=start,onGameEnd=stop,onTextMessage=onTrainerMessage});disconnect(LocalPlayer,{onExperienceChange=onExperience})
  ProtocolGame.unregisterExtendedOpcode(102)
  if modules.game_cooldown and modules.game_cooldown.cooldownWindow then modules.game_cooldown.cooldownWindow:setParent(modules.game_interface.getBottomPanel()) end
  for _,w in pairs(windows) do w:destroy() end
  for _,b in pairs(buttons) do if b and not b:isDestroyed() then b:destroy() end end
  if daily then daily:destroy() end;if passiveWindow then passiveWindow:destroy() end
  if exclWindow then exclWindow:destroy();exclWindow=nil end
end
function testState() return state end
