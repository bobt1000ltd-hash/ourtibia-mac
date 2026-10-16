-- Talent Trees window (Claude, 01.10.2026). Server: 89_talents.lua, opcode 116.
-- Look and rules after the LoL Classic masteries: three trees side by side,
-- rows unlock every 4 points spent in the tree, the final perk needs 20.
local OPCODE=116
local window,data,button,confirmBox
local parts={}
local ATLAS='/images/myots/talents'
local CAPS='/images/myots/talents_caps'

local function send(text) if g_game.isOnline() then g_game.getProtocolGame():sendExtendedOpcode(OPCODE,text) end end
local function ui(id) return window:recursiveGetChildById(id) end
local function money(n) n=math.floor(tonumber(n) or 0);local s=tostring(n):reverse():gsub('(%d%d%d)','%1,'):reverse();return (s:gsub('^,','')) end
local function clip(widget,index)
  index=tonumber(index) or 0
  widget:setImageSource(ATLAS)
  widget:setImageClip({x=(index%16)*32,y=math.floor(index/16)*32,width=32,height=32})
end
local function darker(hex,f)
  local r,g,b=hex:match('#(%x%x)(%x%x)(%x%x)')
  if not r then return hex end
  local function c(v) return string.format('%02x',math.floor(tonumber(v,16)*f)) end
  return '#'..c(r)..c(g)..c(b)
end

-- OurTibia (03.10.2026): every talent point must be confirmed before it is spent.
local function confirmSpend(title, text, command)
  if confirmBox then confirmBox:destroy();confirmBox=nil end
  local yes=function() if confirmBox then confirmBox:destroy();confirmBox=nil end;send(command) end
  local no=function() if confirmBox then confirmBox:destroy();confirmBox=nil end end
  confirmBox=displayGeneralBox(title,text,
    {{text=tr('Yes'),callback=yes},{text=tr('No'),callback=no},anchor=AnchorHorizontalCenter},yes,no)
end

local function nodeState(spent,need,rank,max)
  if rank>=max then return 'max' end
  if spent<need then return 'locked' end
  if rank>0 then return 'partial' end
  return 'open'
end
local BORDER={max='#f0c040',partial='#40d040',open='#d8d8d8',locked='#3a3a3a'}

-- 14.10.2026 (Tobeto): tooltip "Name (x/y)" + one bonus per line; Shift shows the details
local function upFirst(t) return (t:gsub('^%l',string.upper)) end
-- "Melee skill +1" / "+1% physical damage" -> sign, number, unit, name
local function parsePart(part)
  local name,sign,num,unit=part:match('^(.-)%s*([%+%-])([%d%.]+)(%%?)$')
  if name and name~='' then return sign,tonumber(num),unit,name end
  sign,num,unit,name=part:match('^([%+%-]?)([%d%.]+)(%%?)%s*(.*)$')
  if num then return (sign=='' and '+' or sign),tonumber(num),unit,name end
end
local function fmtNum(v) if v==math.floor(v) then return tostring(math.floor(v)) end return (string.format('%.2f',v):gsub('0+$',''):gsub('%.$','')) end
local function perLines(per,mult)
  local out={}
  for part in tostring(per or ''):gmatch('[^,]+') do
    part=part:gsub('^%s+',''):gsub('%s+$','')
    local sign,num,unit,name=parsePart(part)
    if num then out[#out+1]=sign..fmtNum(num*(mult or 1))..unit..' '..upFirst(name)
    elseif part~='' then out[#out+1]=upFirst(part) end
  end
  return out
end
-- 15.10.2026 (Tobeto): own tooltip (like the item tooltip): it follows the mouse and
-- switches to the details the moment Shift is pressed or released - no mouse move needed.
local tipLabel
local function tipPlace()
  if not tipLabel then return end
  local pos=g_window.getMousePosition();local ws=g_window.getSize();local sz=tipLabel:getSize()
  local x=pos.x+12;local y=pos.y+12
  if x+sz.width>ws.width-4 then x=pos.x-sz.width-4 end
  if y+sz.height>ws.height-4 then y=math.max(0,ws.height-sz.height-4) end
  tipLabel:setPosition({x=x,y=y})
end
local function tipShow(text)
  if not tipLabel then
    tipLabel=g_ui.createWidget('UILabel',rootWidget)
    tipLabel:setBackgroundColor('#c0c0c0ff');tipLabel:setColor('#3f3f3fff')
    tipLabel:setBorderColor('#4c4c4cff');tipLabel:setBorderWidth(1)
    tipLabel:setTextAlign(AlignLeft);tipLabel:setTextOffset({x=5,y=3})
    tipLabel:setPhantom(true);tipLabel:setFocusable(false)
  end
  tipLabel:setText(text)
  local sz=tipLabel:getTextSize()
  tipLabel:setSize({width=sz.width+12,height=sz.height+8})
  tipLabel:show();tipLabel:raise();tipPlace()
end
local function tipHide() if tipLabel then tipLabel:hide() end end
local function attachTip(w,short,long)
  w:setTooltip('')
  w.ourTipShort=short;w.ourTipLong=long
  if w.ourTipAttached then return end
  w.ourTipAttached=true
  connect(w,{onHoverChange=function(self,hovered)
    if self.ourTipEvent then removeEvent(self.ourTipEvent);self.ourTipEvent=nil end
    if not hovered then tipHide();return end
    local shown=nil
    local function check()
      self.ourTipEvent=nil
      if not self:isHovered() or not self:isVisible() then tipHide();return end
      local sh=g_keyboard.isShiftPressed()
      if sh~=shown then shown=sh;tipShow(sh and self.ourTipLong or self.ourTipShort) else tipPlace() end
      self.ourTipEvent=scheduleEvent(check,40)
    end
    check()
  end})
end

local function render()
  if not window or not data then return end
  local promoted=data.promoted
  local nextLevel=tonumber(data.nextLevel) or 20
  -- 14.10.2026 (Tobeto): free and total points in the bottom bar (the right panel is gone)
  ui('free'):setText('Talent points: '..tostring(data.free or 0)..' / '..tostring(data.earned or 0))
  ui('free'):setTooltip('Free talent points / all points of your character.\nNext point at level '..nextLevel..' (1 point at level 20, then 1 every 10 levels).')
  ui('gold'):setText(money(data.gold)..' gp')
  ui('reset'):setText('Reset ('..money(data.resetCost)..' gp)')
  ui('reset'):setTooltip('Resets all talent points. Costs as much as all five blessings.\nOnly in a protection zone or out of combat.')
  local any=0;for _,v in ipairs(data.spent or {}) do any=any+(tonumber(v) or 0) end
  ui('reset'):setEnabled(any>0)
  ui('status'):setText('')
  local holder=ui('trees');holder:destroyChildren()
  for ti,tree in ipairs(data.trees or {}) do
    local w=g_ui.createWidget('TalentTree',holder)
    local spent=tonumber(data.spent and data.spent[ti]) or 0
    local header=w:getChildById('header')
    header:setBackgroundColor(darker(tree.color or '#404040',0.55)..'ff')
    w:setBorderColor(darker(tree.color or '#505050',0.9))
    clip(header:getChildById('emblem'),tree.emblem)
    header:getChildById('name'):setText(tree.name)
    header:getChildById('kind'):setText(tree.kind)
    header:getChildById('points'):setText(tostring(spent))
    header:setTooltip(tree.name..' ('..tree.kind..')\n'..(tree.desc or ''))
    local rows=w:getChildById('rows')
    for ri,row in ipairs(tree.rows or {}) do
      local rw=g_ui.createWidget('TalentRow',rows)
      local need=tonumber(row.need) or 0
      rw:getChildById('need'):setText(need>0 and tostring(need) or '')
      rw:getChildById('need'):setColor(spent>=need and '#d0a030' or '#6a6a6a')
      rw:getChildById('need'):setTooltip(need>0 and ('Needs '..need..' points in '..tree.name) or '')
      local nodes=rw:getChildById('nodes')
      local count=#(row.nodes or {})
      nodes:setWidth(count*44+(count-1)*28)
      for ci,node in ipairs(row.nodes or {}) do
        local b=g_ui.createWidget('TalentNode',nodes)
        local rank=tonumber(data.ranks and data.ranks[ti] and data.ranks[ti][ri] and data.ranks[ti][ri][ci]) or 0
        local st=nodeState(spent,need,rank,node.max)
        if not promoted then st='locked' end
        clip(b:getChildById('icon'),node.icon)
        b:getChildById('rank'):setText(rank..'/'..node.max)
        b:getChildById('rank'):setColor(st=='max' and '#ffd35a' or (rank>0 and '#7aff7a' or '#d0d0d0'))
        b:setBorderColor(BORDER[st])
        if st=='locked' then b:setOpacity(0.38) end
        local head=node.name..' ('..rank..'/'..node.max..')'
        local short=head..'\n'..table.concat(perLines(node.per),'\n')..'\n\nPress Shift for more information.'
        -- 15.10.2026 (Tobeto): Shift tooltip layout (name, points, each point, at max, unlock, action)
        local long={head,rank..'/'..node.max..' points','','Each point adds:'}
        for _,l in ipairs(perLines(node.per)) do long[#long+1]=l end
        long[#long+1]='';long[#long+1]='At max points ('..node.max..'):'
        for _,l in ipairs(perLines(node.per,node.max)) do long[#long+1]=l end
        long[#long+1]=''
        long[#long+1]=need>0 and ('Unlock: '..need..' points spent in '..tree.name..' (you have '..math.min(spent,need)..'/'..need..')') or 'Unlock: available from the start'
        long[#long+1]=''
        if not promoted then long[#long+1]='Talent trees unlock after the promotion.'
        elseif st=='max' then long[#long+1]='Maximum rank.'
        elseif st=='locked' then long[#long+1]='Locked - spend more points in this tree first.'
        else long[#long+1]='Click to spend a point.' end
        attachTip(b,short,table.concat(long,'\n'))
        b.onClick=function()
          if not promoted or st=='locked' or st=='max' then return end
          if (tonumber(data.free) or 0)<=0 then ui('status'):setText('No free talent points. Next point at level '..nextLevel..'.');return end
          confirmSpend('Spend talent point', 'Spend 1 talent point on '..node.name..' (rank '..(rank+1)..'/'..node.max..')?\n'..
            'Per rank: '..tostring(node.per)..'\n\nFree points left after this: '..((tonumber(data.free) or 0)-1)..'.',
            'add:'..ti..':'..ri..':'..ci)
        end
      end
    end
    local cap=tree.cap or {}
    local capRank=tonumber(data.ranks and data.ranks[ti] and data.ranks[ti][6] and data.ranks[ti][6][1]) or 0
    local cw=w:getChildById('cap')
    cw:setImageSource(CAPS)
    cw:setImageClip({x=(tonumber(cap.capIcon) or 0)*64,y=0,width=64,height=64})
    local capOpen=promoted and spent>=(tonumber(cap.need) or 20)
    -- 14.10.2026 (Tobeto): no 0/1 - greyed out until it is active, full colour when active
    cw:setOpacity(capRank>0 and 1 or 0.35)
    w:getChildById('capName'):setText(cap.name or '')
    w:getChildById('capName'):setColor(capRank>0 and '#f0d080' or '#8a7a5a')
    w:getChildById('capLine'):setBackgroundColor(capOpen and '#e0b040' or '#403010')
    local capShort=(cap.name or '')..(capRank>0 and ' (active)' or '')..'\n'..table.concat(perLines(cap.per),'\n')..'\n\nPress Shift for more information.'
    -- 16.10.2026 (Tobeto): the same Shift layout as the other perks
    local capLongT={(cap.name or '')..(capRank>0 and ' (active)' or ''),(capRank>0 and 1 or 0)..'/1 point','','Final perk of '..tree.name..':'}
    for _,l in ipairs(perLines(cap.per)) do capLongT[#capLongT+1]=l end
    capLongT[#capLongT+1]=''
    capLongT[#capLongT+1]='Unlock: '..(cap.need or 20)..' points spent in '..tree.name..' (you have '..math.min(spent,tonumber(cap.need) or 20)..'/'..(cap.need or 20)..'), costs 1 point'
    capLongT[#capLongT+1]=''
    capLongT[#capLongT+1]=capRank>0 and 'Active.' or (capOpen and 'Click to unlock it.' or (promoted and 'Locked - spend more points in this tree first.' or 'Talent trees unlock after the promotion.'))
    local capLong=table.concat(capLongT,'\n')
    attachTip(cw,capShort,capLong)
    cw.onClick=function()
      if capRank>0 or not capOpen then return end
      if (tonumber(data.free) or 0)<=0 then ui('status'):setText('No free talent points. Next point at level '..nextLevel..'.');return end
      confirmSpend('Unlock final perk', 'Spend 1 talent point to unlock '..tostring(cap.name)..'?\n'..tostring(cap.per or '')..
        '\n\nFree points left after this: '..((tonumber(data.free) or 0)-1)..'.', 'add:'..ti..':6:1')
    end
    local fill=w:getChildById('bar'):getChildById('fill')
    fill:setWidth(math.floor(math.min(1,spent/20)*218))
    w:getChildById('bar'):setTooltip(spent..' / 20 points to the final perk')
  end
end

function reset()
  if not data then return end
  if confirmBox then confirmBox:destroy();confirmBox=nil end
  local yes=function() if confirmBox then confirmBox:destroy();confirmBox=nil end;send('reset') end
  local no=function() if confirmBox then confirmBox:destroy();confirmBox=nil end end
  confirmBox=displayGeneralBox(tr('Reset talents'),'Reset all talent points for '..money(data.resetCost)..' gold?',
    {{text=tr('Yes'),callback=yes},{text=tr('No'),callback=no},anchor=AnchorHorizontalCenter},yes,no)
end
function hide() tipHide();if window then window:hide() end end
function toggle()
  if window:isVisible() then hide();return end
  -- 07.10.2026: open at once with the last data, then refresh it (the window
  -- waited for the server answer and sometimes opened only minutes later)
  if data and not data.error then pcall(render);window:show();window:raise();window:focus();send('get') else send('open') end
end
function open() send('open') end

local function receive(protocol,opcode,buffer)
  local i,total,piece=buffer:match('^(%d+)/(%d+)|(.*)$')
  if not i then return end
  i,total=tonumber(i),tonumber(total);if i==1 then parts={} end;parts[i]=piece;if i<total then return end
  local ok,result=pcall(json.decode,table.concat(parts));parts={}
  if not ok or type(result)~='table' or result.kind~='talents' then return end
  if result.error then if result.open then modules.game_textmessage.displayFailureMessage(result.error) end;return end
  data=result
  ourMarkButton()
  if result.open then render();window:show();window:raise();window:focus()
  elseif window:isVisible() then render() end
end
-- 13.10.2026 (Tobeto): the button glows gold while there are free talent points
function ourMarkButton()
  if not button then return end
  local free=tonumber(data and data.free) or 0
  local promo=data and data.promoted==false and '\nRequires promotion' or ''
  button:setTooltip('Talent Trees (Ctrl+I)'..promo..(free>0 and ('\n'..free..' free talent point'..(free==1 and '' or 's')..' - click to spend') or ''))
  if free>0 then button:setBorderWidth(1);button:setBorderColor('#ffd35a');button:setImageColor('#ffe9a0')
  else button:setBorderWidth(0);button:setImageColor('#ffffff') end
end
local pollEvent
local function poll()
  if pollEvent then removeEvent(pollEvent);pollEvent=nil end
  if not g_game.isOnline() then return end
  if not (window and window:isVisible()) then send('get') end
  pollEvent=scheduleEvent(poll,60000)
end
local function onGameStart() if pollEvent then removeEvent(pollEvent) end;pollEvent=scheduleEvent(poll,5000) end
local function onGameEnd() hide();data=nil;if pollEvent then removeEvent(pollEvent);pollEvent=nil end;pcall(ourMarkButton) end
function init()
  window=g_ui.displayUI('talents');window:hide()
  ProtocolGame.registerExtendedOpcode(OPCODE,receive)
  connect(g_game,{onGameEnd=onGameEnd,onGameStart=onGameStart})
  button=modules.client_topmenu.addRightGameButton('myotsTalents','Talent Trees (Ctrl+I)','/images/topbuttons/myots_talents',toggle)
  g_keyboard.bindKeyDown('Ctrl+I',toggle)
end
function terminate()
  pcall(ProtocolGame.unregisterExtendedOpcode,OPCODE)
  disconnect(g_game,{onGameEnd=onGameEnd,onGameStart=onGameStart})
  if pollEvent then removeEvent(pollEvent);pollEvent=nil end
  g_keyboard.unbindKeyDown('Ctrl+I')
  if button then button:destroy() end
  if confirmBox then confirmBox:destroy() end
  if window then window:destroy() end
end
