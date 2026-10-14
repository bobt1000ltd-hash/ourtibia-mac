-- DPS meter for training dummies (Claude, 30.09.2026). Damage comes from the
-- server's 'combat' HUD packets (opcode 102); shown bottom-right on the map.
DpsMeter={}
local D=DpsMeter
local hits={}   -- {time, damage}
local label,event
local WINDOW=10000
local function attackingDummy()
 local c=g_game.isOnline() and g_game.getAttackingCreature()
 return c and c:getName():lower():find('training dummy',1,true)~=nil
end
function D.add(damage)
 if not damage or damage<=0 then return end
 hits[#hits+1]={g_clock.millis(),damage}
end
local function update()
 if not label then return end
 local now=g_clock.millis();local total,first=0,nil
 local keep={}
 for _,h in ipairs(hits) do if now-h[1]<=WINDOW then keep[#keep+1]=h;total=total+h[2];first=first or h[1] end end
 hits=keep
 if not attackingDummy() or #hits==0 then label:hide();return end
 local seconds=math.max(1,(now-first)/1000)
 label:setText(string.format('DPS: %d  (%d dmg / %ds)',math.floor(total/seconds+.5),total,math.floor(seconds+.5)))
 label:show()
end
function D.init()
 local map=modules.game_interface and modules.game_interface.getMapPanel and modules.game_interface.getMapPanel()
 if not map then return end
 label=g_ui.createWidget('Label',map);label:setId('myotsDpsMeter')
 -- 05.10.2026 user: on the right side of the game window (middle height)
 label:addAnchor(AnchorRight,'parent',AnchorRight);label:addAnchor(AnchorBottom,'parent',AnchorBottom);label:setMarginBottom(8)
 -- OurTibia (03.10.2026): bottom-right, so the boost bar (bottom-left) does not cover it
 label:setMarginRight(8);label:setColor('#ffd35a');label:setFont('verdana-11px-rounded')
 label:setBackgroundColor('#000000aa');label:setTextAutoResize(true);label:setPhantom(true);label:hide()
 event=cycleEvent(update,500)
end
function D.terminate()
 if event then removeEvent(event);event=nil end
 if label then label:destroy();label=nil end
 hits={}
end
