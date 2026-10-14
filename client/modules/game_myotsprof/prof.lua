-- Weapon Proficiency window (Claude, 01.10.2026). Server: 88_proficiency.lua, opcode 114.
local OPCODE=114
local window,data
local pending={}
local parts={}
weaponCids={}
local COLORS={fire='#e0602a',ice='#5fb4ff',energy='#c070ff',earth='#4fc04f',holy='#f0dc70',death='#9050b0',physical='#c8c8c8'}

local function send(text) if g_game.isOnline() then g_game.getProtocolGame():sendExtendedOpcode(OPCODE,text) end end
local function ui(id) return window:recursiveGetChildById(id) end
local function money(n) n=math.floor(tonumber(n) or 0);local s=tostring(n):reverse():gsub('(%d%d%d)','%1,'):reverse();return (s:gsub('^,','')) end
-- Perk icons: official RL Tibia proficiency icon strips (32x32 cells), /images/myots/prof/.
local ELI={physical=0,fire=1,energy=2,earth=3,ice=4,death=5,holy=6}
local SML={fire=0,ice=1,earth=2,energy=3,death=4,holy=5,physical=6}
local CLS={sword=0,axe=1,club=2,wand=4,rod=4,bow=6,throw=7}
local WM={critical=4,lifeleech=10,manaleech=11,manaregen=15,hpkill=19,hp=1,guardian=2,resilience=21,
  status_bleed=3,paralyze=14,attackspeed_flat=18,doubleattack=12,multishot=17}
local function perkIcon(key,el)
  local cls=CLS[data.class] or 0
  local e=ELI[el] or ELI[data.element] or 0
  if key=='melee' or key=='distance' then return 'offensiveBonusSkill',cls end
  if key=='shielding' then return 'offensiveBonusSkill',5 end
  if key=='magic' then return 'specializedMagicLevel',SML[data.element] or 6 end
  if key=='healing' then return 'gainExtraHealingSpells',cls end
  if key=='monsterslayer' then return 'damagaAgainstBestiary',4 end
  if key:find('^critdmg_') then return 'criticalExtraDamageElement',e end
  if key:find('^crit_') then return 'criticalHitChanceElement',e end
  if key:find('^damage_') then
    if el=='physical' or el=='' then return 'gainExtraDamageAutoAttack',cls end
    return 'elementalPiercing',e
  end
  if WM[key] then return 'weaponmastery',WM[key] end
  return 'weaponmastery',0
end
local function split(label)
  local name,value=label:match('^(.-)%s+([%+%-][%d%.]+%%?m?s?)$')
  return name or label,value or ''
end

-- OurTibia (03.10.2026): built-in list of every weapon with a proficiency tree,
-- so the menu entry is there even before (or without) the server's list.
local STATIC={};for _,c in ipairs({660,661,662,663,664,665,666,667,668,669,670,671,672,673,674,679,680,681,682,683,684,685,686,687,688,689,690,691,692,693,779,780,781,782,783,784,785,786,787,788,789,790,791,792,793,794,795,796,797,798,801,802,803,804,805,806,807,808,809,810,860,1781,2992,3065,3066,3067,3069,3070,3071,3072,3073,3074,3075,3208,3264,3265,3266,3267,3268,3269,3270,3271,3272,3273,3274,3275,3276,3277,3278,3279,3280,3281,3282,3283,3284,3285,3286,3287,3288,3289,3290,3291,3292,3293,3294,3295,3296,3297,3298,3299,3300,3301,3302,3303,3304,3305,3306,3307,3308,3309,3310,3311,3312,3313,3314,3315,3316,3317,3318,3319,3320,3321,3322,3323,3324,3325,3326,3327,3328,3329,3330,3331,3332,3333,3334,3335,3336,3337,3338,3339,3340,3341,3342,3343,3344,3345,3346,3347,3348,3349,3350,3453,5803,6101,6527,6553,7366,7367,7368,7378,7379,7380,7381,7382,7383,7384,7385,7386,7387,7388,7389,7390,7391,7392,7402,7403,7404,7405,7406,7407,7408,7409,7410,7411,7412,7413,7414,7415,7416,7417,7418,7419,7420,7421,7422,7423,7424,7425,7426,7427,7428,7429,7430,7431,7432,7433,7434,7435,7436,7437,7438,7449,7450,7451,7452,7453,7454,7455,7456,7773,7774,8021,8022,8023,8024,8025,8026,8027,8028,8029,8030,8082,8083,8084,8092,8093,8094,8096,8097,8098,8099,8100,8101,8102,8103,8104,9373,9375,9376,9378,9384,9385,9386,9387,9396,10388,10389,10390,10391,10392,10406,11657,11692,11693,12510,12603,12673,12683,12731,12732,12733,12741,13987,13991,14001,14040,14043,14089,14246,14247,14250,14768,16096,16115,16117,16118,16160,16161,16162,16163,16164,16175,17109,17110,17111,17812,17813,17824,17828,17859,19356,19362,20064,20065,20066,20067,20068,20069,20070,20071,20072,20073,20074,20075,20076,20077,20078,20079,20080,20081,20082,20083,20084,20085,20086,20087,20341,21158,21171,21172,21173,21174,21176,21177,21178,21179,21180,21219,21348,21350,22171,22172,22183,22727,22759,22760,22762,22764,22765,22766,22866,22867,22870,23223,23224,23225,23226,23227,23228,23229,23230}) do STATIC[c]=true end
function isWeapon(cid) cid=tonumber(cid) or 0;return weaponCids[cid]==true or STATIC[cid]==true end

local function render()
  if not window or not data then return end
  ui('icon'):setItemId(data.cid)
  ui('name'):setText((tostring(data.name):gsub('(%a)([%w\']*)',function(a,b) return a:upper()..b end)))
  local level=tonumber(data.level) or 0
  local t=data.thresholds or {}
  local exp=tonumber(data.exp) or 0
  local prev=level>0 and (t[level] or 0) or 0
  local nextT=t[level+1]
  if nextT then
    ui('expText'):setText('Exp  '..money(exp-prev)..' / '..money(nextT-prev))
    ui('bar'):setPercent(math.floor((exp-prev)*100/math.max(1,nextT-prev)))
  else
    ui('expText'):setText('Exp  '..money(exp)..' (max)')
    ui('bar'):setPercent(100)
  end
  ui('levelText'):setText('Level  '..level..'/7')
  ui('stats'):setText(data.stats or '')
  local info=(data.desc~='' and (data.desc..'\n\n') or '')
  -- OurTibia (05.10.2026): shorter text (it ran out of the frame), full text in the tooltip
  info=info..'7 stars: '..money(t[7] or 0)..' exp from monsters while wielded.'
  if data.view then info=info..'\n(Preview from the Wiki.)' end
  ui('info'):setText(info)
  ui('info'):setTooltip(info..'\nEach star unlocks one perk of its column; only the wielded weapon\'s perks are active.')
  ui('gold'):setText(money(data.gold)..' gp')
  local cols=ui('columns');cols:destroyChildren()
  for star=1,7 do
    local col=g_ui.createWidget('ProfColumn',cols)
    local reached=star<=level
    col:getChildById('stars'):setText(string.rep('*',star))
    col:getChildById('stars'):setBackgroundColor(reached and '#1b4a1b' or '#333333')
    col:setBackgroundColor(reached and '#1f3a1f' or '#262626')
    local picked=tonumber(data.picks and data.picks[star]) or 0
    local chosenText
    for option,perk in ipairs(data.tree[star] or {}) do
      local b=g_ui.createWidget('ProfPerk',col:getChildById('perks'))
      local name,value=split(perk.label)
      b:setText(value~='' and value or name)
      local strip,index=perkIcon(tostring(perk.key or ''),tostring(perk.el or ''))
      local icon=b:getChildById('icon')
      icon:setImageSource('/images/myots/prof/'..strip)
      icon:setImageClip({x=index*32,y=0,width=32,height=32})
      local color=COLORS[perk.el] or '#a0a0a0'
      b:setColor(color)
      local need=star>1 and t[star-1] or 0
      b:setTooltip(perk.label..'\n\n'..(reached and (picked>0 and (picked==option and 'Chosen.' or 'Another perk of this star is chosen (Reset to change).') or 'Click to choose, then Apply.') or ('Unlocks at '..money(t[star] or 0)..' experience ('..star..' stars).')))
      if picked==option then
        b:setBorderColor('#3fdf3f');b:setBackgroundColor('#245a24ee');chosenText=perk.label
      elseif pending[star]==option then
        b:setBorderColor('#ffd35a');b:setBackgroundColor('#4a4220ee');chosenText=perk.label..' (pending)'
      elseif not reached or picked>0 then
        b:setOpacity(0.45)
      end
      b.onClick=function()
        if data.view or not reached or picked>0 then return end
        pending[star]=(pending[star]==option) and nil or option
        render()
      end
    end
    col:getChildById('chosen'):setText(chosenText or (reached and 'Choose a perk' or 'Locked'))
  end
  local any=false;for _ in pairs(pending) do any=true end
  ui('apply'):setEnabled(any and not data.view);ui('confirm'):setEnabled(not data.view)
  ui('reset'):setEnabled(not data.view and (tonumber(data.resetCost) or 0)>0)
  ui('reset'):setTooltip('Reset all chosen perks of this weapon for '..money(data.resetCost)..' gold.')
end

local function selection()
  local s='';for star=1,7 do s=s..tostring(pending[star] or 0) end;return s
end
function apply() if data and not data.view then send('apply:'..data.cid..':'..selection());pending={} end end
function confirm() if data and not data.view then local any=false;for _ in pairs(pending) do any=true end;if any then apply() end end;hide() end
function reset() if data and not data.view then pending={};send('reset:'..data.cid) end end
function hide() if window then window:hide() end end
function open(cid,view)
  pending={}
  send((view and 'view:' or 'open:')..cid)
end

local function receive(protocol,opcode,buffer)
  local i,total,piece=buffer:match('^(%d+)/(%d+)|(.*)$')
  if not i then return end
  i,total=tonumber(i),tonumber(total);if i==1 then parts={} end;parts[i]=piece;if i<total then return end
  local ok,result=pcall(json.decode,table.concat(parts));parts={}
  if not ok or type(result)~='table' then return end
  if result.kind=='weapons' then
    weaponCids={};for _,c in ipairs(result.list or {}) do weaponCids[tonumber(c)]=true end
    return
  end
  if result.kind=='tree' then
    if not data or data.cid~=result.cid then pending={} end
    data=result;render();window:show();window:raise();window:focus()
  end
end
-- OurTibia (03.10.2026): the menu entry is (re)registered on every login - a
-- reloaded game_interface clears its menu hooks and the entry was lost.
local function hookMenu()
  if not (modules.game_interface and modules.game_interface.addMenuHook) then return end
  modules.game_interface.addMenuHook('myotsProficiency','Weapon Proficiency',
    function(_,lookThing,useThing) local item=useThing or lookThing;if item then open(item:getId()) end end,
    function(_,lookThing,useThing) local item=useThing or lookThing;return item and item:isItem() and isWeapon(item:getId()) end)
end
local function onGameStart() hookMenu();scheduleEvent(function() send('list') end,1500);scheduleEvent(function() if not next(weaponCids) then send('list') end end,6000) end
function init()
  window=g_ui.displayUI('prof');window:hide()
  ProtocolGame.registerExtendedOpcode(OPCODE,receive)
  connect(g_game,{onGameStart=onGameStart,onGameEnd=hide})
  if g_game.isOnline() then onGameStart() end
  hookMenu()
end
function terminate()
  pcall(ProtocolGame.unregisterExtendedOpcode,OPCODE)
  disconnect(g_game,{onGameStart=onGameStart,onGameEnd=hide})
  pcall(function() modules.game_interface.removeMenuHook('myotsProficiency','Weapon Proficiency') end)
  if window then window:destroy() end
end
