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

local function render()
  if not window or not data then return end
  local promoted=data.promoted
  ui('title'):setText((data.vocation or '')..'  -  Level '..tostring(data.level or 0)..(promoted and '' or '  (get your promotion to unlock the trees)'))
  ui('free'):setText(tostring(data.free or 0))
  local nextLevel=tonumber(data.nextLevel) or 20
  ui('progress'):setText('Earned: '..tostring(data.earned or 0)..' points\nNext point at level '..nextLevel..'\n(1 point at level 20, then 1 every 10 levels)')
  local totals=data.totals or {}
  ui('bonuses'):setText(#totals>0 and table.concat(totals,'\n') or 'No talents chosen yet.')
  ui('gold'):setText(money(data.gold)..' gp')
  ui('reset'):setText('Reset ('..money(data.resetCost)..' gp)')
  ui('reset'):setTooltip('Resets all talent points. Costs as much as all five blessings.\nOnly in a protection zone or out of combat.')
  local any=0;for _,v in ipairs(data.spent or {}) do any=any+(tonumber(v) or 0) end
  ui('reset'):setEnabled(any>0)
  ui('status'):setText(promoted and '' or 'Talent trees unlock after the promotion (level 20).')
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
        local tip=node.name..'  ('..rank..'/'..node.max..')\nPer rank: '..node.per
        if st=='locked' then tip=tip..'\n\nLocked: needs '..need..' points in '..tree.name..' (you have '..spent..').'
        elseif st=='max' then tip=tip..'\n\nMaximum rank.'
        else tip=tip..'\n\nClick to spend a point.' end
        b:setTooltip(tip)
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
    cw:setOpacity(capRank>0 and 1 or (capOpen and 0.9 or 0.3))
    w:getChildById('capRank'):setText(capRank..'/1')
    w:getChildById('capName'):setText(cap.name or '')
    w:getChildById('capLine'):setBackgroundColor(capOpen and '#e0b040' or '#403010')
    cw:setTooltip((cap.name or '')..'  - final perk ('..capRank..'/1)\n'..'Bonus: '..(cap.per or '')..'\n\n'..
      (capRank>0 and 'Unlocked.' or (capOpen and 'Click to unlock (1 point).' or ('Needs '..(cap.need or 20)..' points in '..tree.name..' (you have '..spent..').'))))
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
function hide() if window then window:hide() end end
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
  button:setTooltip('Talent Trees (Ctrl+I)'..(free>0 and ('\n'..free..' free talent point'..(free==1 and '' or 's')..' - click to spend') or ''))
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
