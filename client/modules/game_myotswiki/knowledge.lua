-- Game Wiki: Knowledge tab (Claude, 01.10.2026), Mythibia-style.
-- Data comes from the server (opcode 112, data/scripts/myots/83_knowledge.lua).
WikiKnowledge={}
local K=WikiKnowledge
local OPCODE=112
local win,data,current
local history={}
local expanded={}
local DIFF={{'Easy','#3fbf3f'},{'Medium','#e0b030'},{'Hard','#e04040'}}

local function ui(id) return win:recursiveGetChildById(id) end
local function money(n) n=math.floor(tonumber(n) or 0);local s=tostring(n):reverse():gsub('(%d%d%d)','%1,'):reverse();return (s:gsub('^,','')) end
local function content() return ui('knowledgeContent') end
local function label(text,font,color,height)
  local w=g_ui.createWidget('Label',content());w:setText(text);w:setFont(font or 'verdana-11px-monochrome');w:setColor(color or '#dcdcdc')
  w:setTextWrap(true);w:setTextAutoResize(true);if height then w:setHeight(height) end;return w
end
local function h1(t) local w=label(t,'Verdana Bold-13px','#ffffff');w:setMarginTop(2);return w end
local function h2(t) local w=label(t,'Verdana Bold-11px','#e8d9a8');w:setMarginTop(8);return w end
local function body(t) return label(t) end
local function bullet(t) return label('- '..t) end
-- 10.10.2026: the text of a note box is centered in the box (it stuck to the top edge)
local function note(t)
  local box=g_ui.createWidget('UIWidget',content());box:setBackgroundColor('#3a3a3a');box:setBorderWidth(1);box:setBorderColor('#5a5a5a')
  box:setMarginTop(4);box:setPadding(6);box:setPaddingLeft(10);box:setPaddingRight(10)
  local layout=UIVerticalLayout.create(box);layout:setFitChildren(true);box:setLayout(layout)
  local w=g_ui.createWidget('Label',box);w:setText(t);w:setFont('verdana-11px-monochrome');w:setColor('#ffffff');w:setTextWrap(true);w:setTextAutoResize(true)
  return w
end
local function row(height)
  local w=g_ui.createWidget('Panel',content());w:setHeight(height or 60);w:setLayout(UIHorizontalLayout.create(w));w:getLayout():setSpacing(6);return w
end
local function collapsible(title,fill)
  local header=g_ui.createWidget('Button',content());header:setHeight(22);header:setFont('verdana-11px-rounded');header:setText('+  '..title);header:setTextAlign(AlignLeft);header:setTextOffset({x=8,y=0})
  local box=g_ui.createWidget('Panel',content());box:setLayout(UIVerticalLayout.create(box));box:getLayout():setFitChildren(true);box:setMarginLeft(10);box:hide()
  header.onClick=function()
    local open=not box:isVisible();box:setVisible(open);header:setText((open and '-  ' or '+  ')..title)
    if open and #box:getChildren()==0 then fill(box) end
  end
  return header,box
end
local function boxLabel(parent,text,color)
  local w=g_ui.createWidget('Label',parent);w:setText(text);w:setColor(color or '#dcdcdc');w:setTextWrap(true);w:setTextAutoResize(true);return w
end

local pages={}
local nav={
  {key='home',name='Home'},
  {key='item_attributes',name='Item Attributes',children={{key='item_attributes/overview',name='Overview & rarities'},{key='item_attributes/by_type',name='By item type'}}},
  {key='boosted',name='Boosted Creatures'},
  {key='rare_monsters',name='Rare Monsters'},
  {key='kill_tracker',name='Kill Tracker'},
  {key='world_bosses',name='World Bosses & Raids'},
  {key='daily_bosses',name='Daily Bosses'},
  {key='nemesis',name='Nemesis & Bosstiary'},
  {key='bewitched',name='Event: Bewitched'},
  {key='quest_access',name='Quest Access (islands)'},
  {key='oramond',name='Oramond Quests'},
  {key='item_forge',name='Item Forge'},
  {key='autoloot',name='Autoloot'},
  {key='proficiency',name='Weapon Proficiency'},
  {key='talents',name='Talent Trees',children={{key='talents/overview',name='How it works'},{key='talents/1',name='Master Sorcerer'},{key='talents/2',name='Elder Druid'},{key='talents/3',name='Royal Paladin'},{key='talents/4',name='Elite Knight'}}},
  {key='outfits',name='Outfits',children={{key='outfits/quest',name='Quest outfits'},{key='outfits/store',name='Store outfits'}}},
  {key='mounts',name='Mounts',children={{key='mounts/taming',name='Tameable mounts'},{key='mounts/store',name='Store mounts'}}},
  {key='coin_exchange',name='Coin Exchange (USDT)'},
  {key='news',name='New in October 2026',children={{key='news/combat',name='Combat changes'},{key='news/quests',name='Quests & world'},{key='news/client',name='Client & website'}}},
}

local function boostedCards()
  local r=row(62)
  local list=data and data.boosted or {}
  -- 10.10.2026: the cards share the width of the page (they were left-aligned)
  local width=math.floor(((content():getWidth()-content():getPaddingLeft()-content():getPaddingRight())-6*(#list-1))/math.max(1,#list))
  if width<150 then width=196 end
  for _,b in ipairs(list) do
    local card=g_ui.createWidget('UIWidget',r);card:setWidth(width);card:setHeight(60)
    card:setBackgroundColor('#2a2a2a');card:setBorderWidth(1);card:setBorderColor('#4a4a4a')
    local c=g_ui.createWidget('UICreature',card);c:setSize({width=48,height=48});c:addAnchor(AnchorLeft,'parent',AnchorLeft);c:addAnchor(AnchorVerticalCenter,'parent',AnchorVerticalCenter);c:setMarginLeft(4);c:setPhantom(true)
    c:setId('boostedCreature')
    local o=b.outfit or {};if (tonumber(o.type) or 0)>0 then OurTibiaArt.creature(c,{type=tonumber(o.type),head=o.head,body=o.body,legs=o.legs,feet=o.feet,addons=o.addons},b.name) end
    local n=g_ui.createWidget('Label',card);n:setText((tostring(b.name):gsub('^%l',string.upper)));n:setFont('Verdana Bold-11px');n:setColor('#ffffff')
    n:addAnchor(AnchorLeft,'boostedCreature',AnchorRight);n:addAnchor(AnchorRight,'parent',AnchorRight);n:addAnchor(AnchorTop,'parent',AnchorTop);n:setMarginTop(5);n:setMarginLeft(6);n:setMarginRight(4);n:setHeight(14);n:setClipping(true)
    n:setTooltip(n:getText())
    n.ourFull=n:getText();fitCardText(n,n.ourFull,width-66)
    local d=DIFF[tonumber(b.difficulty) or 1] or DIFF[1]
    -- 10.10.2026: fixed-size tag with the word centered in it
    local tag=g_ui.createWidget('Label',card);tag:setText(d[1]);tag:setColor(d[2]);tag:setBorderWidth(1);tag:setBorderColor(d[2]);tag:setTextAutoResize(false);tag:setSize({width=58,height=15});tag:setTextAlign(AlignCenter)
    -- 10.10.2026: the difficulty goes under the name (a long name ran into it)
    tag:addAnchor(AnchorLeft,'parent',AnchorLeft);tag:addAnchor(AnchorTop,'parent',AnchorTop);tag:setMarginTop(22);tag:setMarginLeft(58)
    local v=g_ui.createWidget('Label',card);v:setText(string.format('Exp %+d%%   Loot +%d%%',b.experience or 0,b.loot or 0));v:setColor('#ffd35a')
    v:addAnchor(AnchorLeft,'parent',AnchorLeft);v:setMarginLeft(58);v:addAnchor(AnchorBottom,'parent',AnchorBottom);v:setMarginBottom(4);v:setTextAutoResize(true)
    card:setTooltip(string.format('Experience %+d%%\nLoot +%d%%\nDamage resistance %+d%%',b.experience or 0,b.loot or 0,b.resistance or 0))
  end
  -- the page width is known only after the layout: stretch the cards then
  scheduleEvent(function()
    if r:isDestroyed() or #list==0 then return end
    local w=math.floor((r:getWidth()-6*(#list-1))/#list)
    if w<150 then return end
    for _,card in ipairs(r:getChildren()) do
      card:setWidth(w)
      for _,child in ipairs(card:getChildren()) do if child.ourFull then fitCardText(child,child.ourFull,w-66) end end
    end
  end,30)
end

pages['home']=function()
  h1('Knowledge')
  h2("Today's boosted creatures")
  if data and #(data.boosted or {})>0 then boostedCards() else body('Loading...') end
  if data and data.worldBoss then
    h2("Today's world boss")
    local wb=data.worldBoss
    local w=body(wb.alive and (wb.name..' is alive right now!') or (wb.name..' appears today at '..(wb.time or '21:00')..' (server time).'))
    w:setColor('#ff6060')
  end
  h2('Rare monsters')
  if data and data.rareAverage then
    body(string.format('On average 1 of every %d monsters spawns as a rare version (Rare, Epic, Legendary, Mythic or World Ending) with an element. They hit harder, have more HP and give more experience and loot.',data.rareAverage))
  end
  h2('Kill Tracker')
  body('Every monster type has its own Kill Tracker with 8 stars. Common monsters need 200 kills for the first star and 20,000 for the last; rarer monsters need fewer kills. Each star gives one reward (coins, stone fragments or upgrade stones) and permanently +1% damage and +2% loot against that monster.')
  note('Use the categories on the left to read more.')
end

-- 10.10.2026: the USDT coin exchange and the October update
pages['coin_exchange']=function()
  h1('Coin Exchange (USDT)')
  body('On ourtibia.com/exchange players trade OurTibia Coins with each other for USDT (a dollar stablecoin) on the Solana network. You can earn real money by playing: sell what you find for coins, then sell the coins for USDT.')
  h2('How to earn')
  bullet('Sell items on the in-game Market for coins, a character on the Char Bazaar, or Tibia Coins (items) to other players.')
  bullet('On the website, place a sell order. When a buyer takes it, you get the price minus a 5% fee.')
  bullet('Withdraw the USDT you earned to your linked wallet. An admin checks every withdrawal.')
  h2('How to buy coins cheaper')
  bullet('Link a Solana wallet (Phantom, Solflare, Binance Wallet, Backpack, OKX, Trust ...) and deposit USDT with one click, or from an exchange like Binance.')
  bullet('Coins on the exchange are always at least 10% cheaper than in the official shop. Bought coins are on your account at once and can be used in the Game Store.')
  h2('Which coins can be sold?')
  body('Only coins that were bought for USDT - or received from players who bought them (transfers, Market, Char Bazaar, Tibia Coins) - can be sold. Coins from the beta, gifts, rewards, events and gamemasters can never be sold or withdrawn; they stay usable in the Game Store.')
  bullet('Paying for something uses your non-sellable coins first, so your sellable coins are kept.')
  bullet('Tibia Coins made from sellable coins say so in their description and give sellable coins back when used.')
  bullet('Deposited USDT is for buying coins; only USDT earned by selling coins can be withdrawn.')
  note('Type !exchange in the game to see the current price, the best offers and how many of your coins you can sell.')
end
pages['news']=function() pages['news/combat']() end
pages['news/combat']=function()
  h1('New in October 2026 - Combat')
  bullet('Damage over time can now be critical: bleeding, burning, poison, curse and other status ticks use your critical chance (Luck, items, talents) and critical damage.')
  bullet('Spells no longer have a minimum hit - only melee attacks keep the minimum hit from Strength.')
  bullet('Area spells and runes still hit players without the PvP fist - the server is PvP.')
end
pages['news/quests']=function()
  h1('New in October 2026 - Quests & world')
  bullet('The First Dragon quest and its bosses are in the game.')
  bullet("Ferumbras' Ascension is complete, including Mazarius and the soul splinter.")
  bullet('Explorer Society: the astral portals work like in real Tibia.')
  bullet('Many quests were tested and fixed: doors, levers, chests, NPC missions (Djinn, Riddler, Tereban and more).')
  bullet('The Exchanger NPC was removed. Creature products for addons are traded with the real NPCs: Haroun and Yaman (Djinn), A Sweaty Cyclops (steel and iron) and Marina (yarn).')
  bullet('Beds outside houses can be used too: you fall asleep (log out) and regain health and mana for the time you were offline.')
  bullet('Say "where is <NPC name>" (or !where Rashid) - the server tells you the town and coordinates and gives a map link.')
  note('Quest chests in the Wiki now show the town and the position of the chest instead of "Somewhere...".')
end
pages['news/client']=function()
  h1('New in October 2026 - Client & website')
  bullet('Loyalty Shop: 9 new shaders (Blood Moon, Toxic, Golden, Frost, Inferno, Storm, Void, Holy, Aurora) for 50-150 loyalty tokens.')
  bullet('Action bar: an Equip button now works both ways - press it again to take the item off (e.g. an energy ring).')
  bullet('Rarity frames show at once when items are crafted, looted or moved.')
  bullet('Hall of Legends has its own button in the top bar.')
  bullet('Discord shows "Playing OurTibia" with your character and level while the client runs (Windows, Discord app open).')
  bullet('The website can be translated (EN, PL, BR, ES, NL, SV - menu at the top) and works on phones and tablets.')
  bullet('Coin Exchange (USDT) on the website - see its own page in this Wiki.')
end

pages['item_attributes']=function() pages['item_attributes/overview']() end
pages['item_attributes/overview']=function()
  h1('Item attributes')
  h2('Attributes')
  body(string.format('Equipment can drop with magical attributes. Each looted item has a %g%% chance to be Unidentified - once identified it gets a rarity, and a number of random attributes drawn from a pool that depends on the item type and slot.',data and data.unidentified or 15))
  h2('Rarities')
  body('Higher rarity = more attribute slots. Identify roll distribution:')
  for _,r in ipairs(data and data.rarities or {}) do
    if r.special then bullet(r.name..' - up to '..r.slots..' attributes, strongest rolls (special sources only)')
    else bullet(string.format('%s - up to %d attribute%s (about %g%%)',r.name,r.slots,r.slots>1 and 's' or '',r.chance)) end
  end
  note("Two-handed weapons, bows and crossbows roll one extra attribute (up to 6).")
  note("An attribute's value also scales with the item tier (T1-T15).")
end
pages['item_attributes/by_type']=function()
  h1('Attributes by item type')
  h2('Informations')
  body('Which attributes an item can roll depends on its type/slot. Pick a type below to see its full pool. Only one attribute per category is drawn per item. Values: maximum at T10 / T15.')
  for _,pool in ipairs(data and data.pools or {}) do
    collapsible(pool.name,function(box)
      for _,a in ipairs(pool.attrs or {}) do boxLabel(box,string.format('%s   (T10: %s, T15: %s)',a.label,a.t10,a.t15)) end
    end)
  end
end
pages['boosted']=function()
  h1('Boosted Creatures')
  body('Randomized creatures with changed experience, loot and resistances.')
  body('Every day three creatures are boosted - one easy (up to 500 experience), one medium (up to 2,000) and one hard (above 2,000). The list changes at 09:00.')
  h2('Today')
  if data and #(data.boosted or {})>0 then boostedCards() else body('Loading...') end
  h2('Creature benefits')
  bullet('Experience: Easy +10% to +40%, Medium 0% to +30%, Hard -10% to +20%.')
  bullet('Loot: 0% to +40% drop rate (an extra loot roll).')
  note('Smart boost: a creature with a big experience bonus becomes tougher (up to +10% damage resistance) and gets a smaller loot bonus; one with a low experience roll is easier to kill (up to -15% resistance) and drops more.')
end
pages['rare_monsters']=function()
  h1('Rare Monsters')
  body(string.format('Any monster can spawn as a rare version - on average 1 in %d. The rarer the tier, the stronger the monster and the better the reward. The spawn is announced and the monster gets an element with its own attacks.',data and data.rareAverage or 90))
  h2('Tiers')
  for _,t in ipairs(data and data.rare or {}) do
    bullet(string.format('%s - about 1 in %s spawns: +%d%% damage and HP, +%d%% experience and loot, dropped items +%d tier',t.name,money(t.oneIn),t.power,t.loot,t.tier))
  end
  h2('Elements')
  body(table.concat(data and data.rareElements or {},', '))
  note('Rare monsters also drop magical stone fragments and sometimes crafting stones.')
end
pages['kill_tracker']=function()
  h1('Kill Tracker')
  body('Each monster type has 8 stars. For common monsters (150+ spawns on the map) the stars are reached at 200, 400, 800, 2,000, 4,000, 8,000, 16,000 and 20,000 kills.')
  body('Monsters with fewer spawns on the map need fewer kills: 80-149 spawns from 100 kills for the 1st star to 20,000 for the 8th, 40-79 spawns from 50 to 10,000, 15-39 spawns from 20 to 4,000, fewer than 15 spawns and raid monsters from 10 to 2,000. Never more than 20,000. The Kill Tracker window shows the next milestone of every monster.')
  h2('Star bonuses')
  bullet(string.format('+%d%% damage against that monster per star.',data and data.killStarDamage or 1))
  bullet(string.format('+%d%% loot from that monster per star.',data and data.killStarLoot or 2))
  h2('Star rewards')
  body('Each new star gives experience and ONE reward. The stronger the monster and the higher the star, the better the reward:')
  bullet('Platinum coins - or crystal coins for a very large number of kills of strong monsters.')
  bullet('Magical stone fragments.')
  bullet('Random minor upgrade stone (1-3, depending on the star).')
  bullet('Random major upgrade stone (1-3) - strong monsters and higher stars only.')
end
pages['quest_access']=function()
  h1('Quest Access (islands)')
  body('Some islands and hunting areas need finished quests. The captain, the NPC or the door tells you which quests are still missing.')
  h2('Requirements')
  bullet('Oramond (surface and glooth hunts): The Black Knight Quest - the captains sail to Oramond only after it.')
  bullet('Quirefang: Pits of Inferno - the vortex on Gray Island lets you through only after it.')
  bullet('Oramond demon dungeon and Roshamuul: The Black Knight Quest, Pits of Inferno and The Inquisition.')
  bullet('Issavi, True Asuras (Asura Palace vaults) and the Cobra Bastion: all of the above and Wrath of the Emperor. The door in the Asura Palace and the Cobra NPC tell you what is missing.')
  h2('Done when')
  bullet('The Black Knight Quest: you took the reward (Crown Armor or Crown Shield).')
  bullet('Pits of Inferno: you took a weapon reward from the throne room.')
  bullet('The Inquisition: Henricus gave you the last mission as done.')
  bullet('Wrath of the Emperor: you finished the last mission with the Awareness of the Emperor.')
  note('Beta tests: the Game Store offer "All Quest Access (Beta)" (Gameplay - Quests & Access) opens all of these places without the quests. It exists only during the beta.')
end
pages['oramond']=function()
  h1('Oramond Quests')
  body('Rathleton and Oramond have their own quest lines. Most tasks give votes for the magistrate - you need them for the Dark Trails and for the outfit addons.')
  note('Important: for Dark Trails mission 13 (Sholley, "friend") you need at least 15 votes. Every task below gives 1 vote and can be repeated.')
  h2('Votes (repeatable tasks)')
  bullet('To Take Roots - harvest juicy roots outside Rathleton and bring 5 to Chavis (say "food").')
  bullet('The Ancient Sewers - Elliott or Jacob ("mission"): repair 20 broken pipes and generators (smoking) in the sewers, then report ("mission", "ok").')
  bullet('Probing - Doubleday ("experiment"): use the mono detector in the sewers (levels 10-11), drop the probing device at the right place and use it, report ("probe").')
  bullet('The Powder of the Stars - Barnabas Dee ("mission"): harvest 15 blue pollen from peppermoon bells in the caves.')
  h2('Dark Trails')
  bullet('1-2: Ezebeth (magistrate) "mission", "assistance", "strange" - A Beggar "want", "yes".')
  bullet('3: The Beggar King "mission" (needs the juicy roots task done once).')
  bullet('4-6: Glooth Brothers - repair the sewers, "abandoned sewers"; find the ritual site in the abandoned sewers (level 10) and "report" to Elliott.')
  bullet('7-9: Barazbaz "ritual" - vote for the archives at Marvin ("funding") - Barazbaz "abandoned sewers".')
  bullet('10: Jondrin "necrometer" (after one probing task for Doubleday). Step on the ritual site with the necrometer.')
  bullet('11: The Ravager - stand on the switches next to the lever (1-4 players) and pull it. Afterwards: the chest and the small notebook in the box.')
  bullet('12-14: Barazbaz "notebook" - Sholley "friend" (needs 15 votes) - Roswitha "Harsin" - Quandon\'s house: look at his body - Sholley "quandon".')
  bullet('15-17: Barnabas Dee "seance" (15 blue pollen) - Quandon\'s ghost - Terrence "manway", "effort".')
  bullet('18: through the barred sewer duct under the minotaur front to Death Priest Shargon (lever, 1-5 players). Then Ezebeth "outfit" / "addon" (Glooth Engineer).')
  h2('Hero of Rathleton')
  bullet('Glooth factory (teleport in the city) - down to the Strange Pipe. Talk to it, then use the pipe wall next to it.')
  bullet('Turn on all 8 strange machines to power the teleport: Deep Terror - Glooth Horror - lava flow (throw magma chunks of the raging fires into the crucibles) - Professor Maxxen.')
  bullet('Each next part opens after talking to the next Strange Pipe. Maxxen\'s chest gives the secret fast ways.')
end
pages['world_bosses']=function()
  h1('World Bosses')
  body('Every day at 21:00 (server time) a world boss appears - always as a rare+ monster (Rare to World Ending). It is announced 15 and 5 minutes before.')
  h2('Schedule')
  local wb=data and data.worldBoss
  if wb and type(wb.schedule)=='table' then
    for _,e in ipairs(wb.schedule) do
      local w=bullet(string.format('%s %s - %s%s',e.day,wb.time or '21:00',e.name,e.today and (wb.alive and '   (TODAY - alive now!)' or '   (TODAY)') or ''))
      if e.today then w:setColor('#ff6060') end
    end
  else
    bullet('Monday 21:00 - Verminor')
    bullet('Tuesday 21:00 - Lizard Abomination')
    bullet('Wednesday 21:00 - Bazir')
    bullet('Thursday 21:00 - Orshabaal')
    bullet('Friday 21:00 - Morgaroth')
    bullet('Saturday 21:00 - Ghazbaran')
    bullet('Sunday 21:00 - Ferumbras')
  end
  h2('Rewards')
  body('The loot is shared like in Tibia: every player who damaged the boss or healed a fighter gets his own rewards - the bigger your share of damage and healing, the better your rolls. On top of the boss loot everybody receives major upgrade stones of random kinds (many more on the weekend bosses).')
  body('After the kill, collect your rewards from the reward chest in any town temple. If you lack capacity or room, open the chest again later - nothing is lost.')
  h1('Raids')
  body('All classic raids (rats and orcs in Thais, undead armies, pirates, dragons, barbarians, beetles and many more) start every few hours somewhere in the world - always one at a time and announced to everyone.')
  body('Raid monsters drop magical stone fragments, upgrade stones, Astral Protectors and Rarity Infusers like Rare monsters, but 4 times less often.')
end
pages['daily_bosses']=function()
  h1('Daily Bosses - Group Finder')
  body('Open the Group Finder with its button on the right panel (group of three figures) or with Ctrl+F. Choose a boss and your role, then join the queue. Groups are formed automatically: 1 Tank, 1 Healer and 2 DPS.')
  bullet('Knights can only join as Tank, paladins only as DPS. Sorcerers and druids can join as DPS or Healer.')
  bullet('You cannot join while you have a protection zone block (PZ).')
  bullet('Full group: everybody gets a ready check. When all are ready, the whole group is moved to the arena.')
  bullet('2-3 players: every member must agree to start without a full group. Alone: you must confirm a warning first.')
  bullet('Only one group can fight a boss at a time. If the arena is occupied you have to wait (at most 15 minutes).')
  bullet('You have 15 minutes. If the boss is not dead by then, everybody is moved back to where they started.')
  bullet('The leader can leave at any moment - another member becomes the leader.')
  bullet('Every boss can be defeated once per day (reset at the server save, 10:00). A failed attempt can be repeated.')
  h2('Bosses')
  bullet('Level 25 - Grimbold Ironwarden (20,000 HP) - 4-star plate set, bow, crossbow, barbarian axe, dwarven shield, necrotic rod, wand of decay.')
  bullet('Level 50 - Hydrakis the Venomcoil (80,000 HP) - 5-star knight armor and legs, warrior helmet, tower shield, war hammer, wand of cosmic energy, terra rod, elvish bow.')
  bullet('Level 75 - Sir Malthor the Oathbreaker (150,000 HP) - 6-star crown set, crusader helmet, crown shield, noble axe, wand of inferno, hailstorm rod, silkweaver bow.')
  bullet('Level 100 - Zathrak, Chosen of the Coil (300,000 HP) - 7-star zaoan helmet, armor, legs and shoes, guardian halberd, modified crossbow, wand of starstorm, springsprout rod.')
  bullet('Level 150 - Azhereth the Rift Warden (500,000 HP) - 8-star prismatic armor, legs, boots, helmet and shield, thaian sword, mycological bow, underworld rod, wand of voodoo.')
  bullet('Level 200 - Vexmortis the Hellbound (1,000,000 HP) - 9-star wand of everblazing, muck rod, demon armor, legs and helmet, guardian boots, rift lance, chain bolter.')
  note('The boss always has its full health. Its damage is adjusted to the size of your group (alone about 60% of the damage).')
  h2('Mechanics')
  body('Every boss turns the whole arena red from time to time. Several tiles stay unmarked (green) - stand on one of them before the blast, or lose most of your health. While the arena glows red the boss stands still. Daily bosses hit very hard (three times as hard as a normal boss of the same level), so bring a healer or plenty of potions. Each boss also has its own tricks: rockfall and a shield wall, acid breath and healing sprouts, a pull to the boss, the serpent coil, the void pull, and an enrage near death.')
  h2('Rewards')
  body('Only players alive in the arena when the boss dies get rewards. Each of them is rolled separately: 1-2 unidentified items of the boss set (with the boss star tier), many magical stone fragments, minor upgrade stones (major stones for the level 75+ bosses), and a chance for a Rarity Infuser and an Astral Protector.')
  body('Collect the rewards from the reward chest in any town temple.')
end
pages['nemesis']=function()
  h1('Nemesis Bosses & Bosstiary')
  body('15 bosses appear at random places in their region - no fixed time. Bane (Yeti, The Horned Fox, Necropharus, Fernfang, Man in the Cave, Dharalion) about every 6 hours, Archfoe (Demodras, the vampire lords, The Old Widow) about every 12 hours, Nemesis (Zulazza the Corruptor, Zushuka, The Pale Count) about every 3 days - announced on the whole server.')
  h2('Rewards')
  body('Everyone who dealt at least 5% of the boss hit points gets extra rewards in the reward chest (any town temple): loyalty tokens, magical stone fragments, upgrade stones, a chance for a Rarity Infuser or Super Rarity Infuser and an unidentified item of the boss (Bane T4-T6, Archfoe T6-T8, Nemesis T8-T11). The most damage gives one more roll.')
  h2('Bosstiary')
  body('Kills give stages for each boss - Prowess, Expertise and Mastery - and Bosstiary points. Points unlock permanent bonuses: 100 boss damage +2%, 250 boss loot +5%, 500 one more reward roll, 1000 boss damage +5% and loot +10% in total, 2000 Trophy Hunter outfit, 3000 +1% experience.')
  note('Open the Bosstiary with the button on the top bar or !bosstiary.')
end
pages['bewitched']=function()
  h1('Event: Bewitched')
  body('Every weekend from Friday 18:00 to Sunday 18:00 (server time) the swamp witches brew a protective potion in their cauldron on the clearing east of Venore (33010, 32010, 7).')
  h2('How it works')
  body('Every 8 hours a new phase asks for one ingredient (the first phase always for lumps of dirt). The whole server has to bring 60 of it - use the item on the cauldron or tell Minzy "ingredients". Dry pieces of wood feed the fire at any time. When a phase is completed everyone gets 2 hours of the Experience Boost and Bane Bringers attack the clearing. If a phase fails, the brew is spoiled and the event ends until the next weekend.')
  h2('Favour points')
  body('5 points: lump of dirt, goblin ear, spider fangs. 10 points: bat wing, centipede leg, scorpion tail, marsh stalker beak. 15 points: minotaur horn, tarantula egg, sulphurous stone, lancet, small flask of eyedrops. 1 point: dry piece of wood.')
  body('Minzy trades favour points for potions and tamed ravens (Emerald, Mystic, Radiant Raven - 1000 points each). Achievements: Banebringers\' Bane (300 points earned), Honorary Witch (1500 points).')
  note('!bewitched shows the current phase and your favour points.')
end
pages['item_forge']=function()
  h1('Item Forge')
  body('Use a crafting station (one at every depot) to craft stones from magical stone fragments, or to upgrade equipment. Minor stones work on tiers 1-6, major stones on tier 7+. The item must be in your backpack and must not be protected.')
  h2('Stone recipes')
  for _,r in ipairs(data and data.recipes or {}) do
    if (tonumber(r.frag) or 0)>0 then bullet(string.format('%s - %d fragments + %s gold. %s',r.name,r.frag,money(r.gold),r.desc or ''))
    else bullet(string.format('%s - %s gold. %s',r.name,money(r.gold),r.desc or '')) end
  end
  h2('Upgrading')
  body('An item can be upgraded up to +its tier. Each level adds +5% to the attribute ranges (wands and rods +5% damage).')
  local line={};for i,c in ipairs(data and data.success or {}) do line[#line+1]='+'..(i-1)..': '..c..'%' end
  body('Success chance: '..table.concat(line,', '))
  local prices={};for _,u in ipairs(data and data.upgrade or {}) do prices[#prices+1]='T'..u.tier..': '..money(u.first) end
  body('First upgrade price: '..table.concat(prices,', '))
  note('On failure there is a 50% chance to lose one level. Tick "Use Astral Protector" in the crafting station to prevent it (one protector is used per attempt).')
end
pages['autoloot']=function()
  h1('Autoloot')
  body('Streamline your hunting with smart automatic looting.')
  bullet('Customizable lists: choose exactly which items are picked up ([+] Add an item, or click an empty slot and then the item).')
  bullet('4 presets with 8 items each (12 with the store upgrade).')
  bullet('Gold, valuables and creature products are looted by their own options and do not take item slots.')
  bullet('Auto conversion changes looted coins into the highest coins right away.')
  note('Gold, items and valuables each go to the container you assign to them.')
end

-- Outfits & mounts: cards with the creature, how to get it and the bonus.
local function cosmeticCards(list,isMount)
  local r,count
  for _,e in ipairs(list) do
    if not r or count==3 then r=row(96);count=0 end
    count=count+1
    local card=g_ui.createWidget('UIWidget',r);card:setWidth(176);card:setHeight(94)
    card:setBackgroundColor('#2a2a2a');card:setBorderWidth(1);card:setBorderColor('#4a4a4a')
    local c=g_ui.createWidget('UICreature',card);c:setSize({width=56,height=56});c:addAnchor(AnchorLeft,'parent',AnchorLeft);c:addAnchor(AnchorTop,'parent',AnchorTop);c:setMarginLeft(2);c:setMarginTop(2);c:setPhantom(true)
    if isMount then c:setOutfit({type=e.look}) else c:setOutfit({type=e.male,head=78,body=106,legs=58,feet=76,addons=3}) end
    local n=g_ui.createWidget('Label',card);n:setText(e.name);n:setFont('Verdana Bold-11px');n:setColor('#ffffff');n:setTextAutoResize(true)
    n:addAnchor(AnchorLeft,'parent',AnchorLeft);n:addAnchor(AnchorTop,'parent',AnchorTop);n:setMarginLeft(60);n:setMarginTop(6)
    local src=g_ui.createWidget('Label',card);src:setColor(e.source=='store' and '#f0d060' or '#8fd08f');src:setTextAutoResize(true)
    src:setText(e.source=='store' and (e.price..' coins') or (isMount and 'Taming' or 'Quest'))
    src:addAnchor(AnchorLeft,'parent',AnchorLeft);src:addAnchor(AnchorTop,'parent',AnchorTop);src:setMarginLeft(60);src:setMarginTop(22)
    local hp=g_ui.createWidget('Label',card);hp:setColor('#a0a0a0');hp:setTextAutoResize(true);hp:setText('~'..e.hp..' HP value')
    hp:addAnchor(AnchorLeft,'parent',AnchorLeft);hp:addAnchor(AnchorTop,'parent',AnchorTop);hp:setMarginLeft(60);hp:setMarginTop(36)
    local b=g_ui.createWidget('Label',card);b:setColor('#9fe09f');b:setTextWrap(true)
    b:setText(isMount and e.bonus or (e.stages and e.stages[3] or ''))
    b:addAnchor(AnchorLeft,'parent',AnchorLeft);b:addAnchor(AnchorRight,'parent',AnchorRight);b:addAnchor(AnchorBottom,'parent',AnchorBottom);b:setMarginLeft(4);b:setMarginRight(4);b:setMarginBottom(3);b:setHeight(28)
    local tip={e.name,'How to get: '..(e.how or '?'),''}
    if isMount then tip[#tip+1]='Bonus while riding: '..(e.bonus or '')
    else
      tip[#tip+1]='Bonus while worn:'
      tip[#tip+1]='  No addons: '..(e.stages and e.stages[1] or '')
      tip[#tip+1]='  Addon 1 or 2: '..(e.stages and e.stages[2] or '')
      tip[#tip+1]='  Both addons: '..(e.stages and e.stages[3] or '')
    end
    card:setTooltip(table.concat(tip,'\n'))
  end
end
local function filtered(list,source) local out={};for _,e in ipairs(list or {}) do if e.source==source then out[#out+1]=e end end;table.sort(out,function(a,b) if a.hp==b.hp then return a.name<b.name end;return a.hp<b.hp end);return out end
pages['outfits']=function() pages['outfits/quest']() end
pages['outfits/quest']=function()
  h1('Quest outfits')
  body('Every outfit gives a unique bonus, but only the outfit you are wearing counts. The bonus grows with addons: 50% without addons, 75% with one addon and 100% with both. Harder outfits give more (up to a 60 HP value).')
  note('Hover a card to see how to get the outfit and the bonus with no addons, one addon and both addons.')
  if not data or not data.outfits then body('Loading...') return end
  cosmeticCards(filtered(data.outfits,'quest'),false)
end
pages['outfits/store']=function()
  h1('Store outfits')
  body('Outfits that could not be obtained in Tibia 8.6 are sold in the Game Store (Cosmetics) for 120, 240 or 360 coins, always with both addons. The bonus is worth a 10, 20 or 30 HP value.')
  note('Hover a card for details. Only the worn outfit gives its bonus.')
  if not data or not data.outfits then body('Loading...') return end
  cosmeticCards(filtered(data.outfits,'store'),false)
end
pages['mounts']=function() pages['mounts/taming']() end
pages['mounts/taming']=function()
  h1('Tameable mounts')
  body('Mounts you can tame with a taming item (Game Store > Items > Taming Items, or found in the game). Only the mount you are riding gives its bonus; harder mounts give more (up to a 60 HP value).')
  if not data or not data.mounts then body('Loading...') return end
  cosmeticCards(filtered(data.mounts,'taming'),true)
end
pages['mounts/store']=function()
  h1('Store mounts')
  body('Mounts sold in the Game Store (Cosmetics) for 120, 240 or 360 coins. The bonus is worth a 10, 20 or 30 HP value and only counts while riding.')
  if not data or not data.mounts then body('Loading...') return end
  cosmeticCards(filtered(data.mounts,'store'),true)
end

pages['proficiency']=function()
  h1('Weapon Proficiency')
  body('Every weapon has its own tree of perks with 7 stars. While you wield a weapon, all experience you get from monsters is also added to that weapon type. Each new star unlocks one perk to choose from its column.')
  h2('How it works')
  bullet('Right-click a weapon and choose "Weapon Proficiency" to see its experience, stars and perks.')
  bullet('Pick one perk per reached star and press Apply (or Confirm). Only the perks of the weapon you are wielding are active.')
  bullet('Reset clears all chosen perks of that weapon for gold (2,000 gp x star number of every chosen perk).')
  bullet('Every item page in the Wiki has a "Show proficiency" button for weapons, so you can check a tree before you hunt for the weapon.')
  h2('Trees')
  bullet('Swords: melee skill, critical chance and damage, attack speed, double attack, bleeding, life leech.')
  bullet('Axes: critical damage, bleeding, Max HP, HP on kill, double attack.')
  bullet('Clubs: paralyze, shielding, guardian, PvP Mastery, Max HP, physical damage.')
  bullet('Bows and crossbows: distance skill, multi shot, critical, attack speed, Monster Slayer and holy perks (holy damage, holy crit chance and damage).')
  bullet('Throwing weapons: distance skill, critical, HP on kill, bleeding, attack speed.')
  bullet('Wands and rods: magic level and the elemental damage, crit chance and crit damage of their element (rods also healing).')
  bullet('Enchanted melee weapons (fiery, icy, earth and energy versions) hit physically, so their perks are physical too.')
  bullet('Elemental melee weapons (e.g. fire sword) use their element for the damage and crit perks.')
  h2('Experience needed')
  body('Stronger weapons need more experience and have stronger perks: from about 300,000 experience for all 7 stars of the weakest weapons to about 85,000,000 for the strongest.')
  note('Perk values scale with the weapon: weak weapons get about 55% of the values shown on the strongest ones.')
end

pages['talents']=function() pages['talents/overview']() end
pages['talents/overview']=function()
  h1('Talent Trees')
  body('Every promoted vocation has three talent trees, like the masteries of League of Legends Classic: an offensive, a defensive and a utility tree. Each vocation has its own trees and perks.')
  h2('Talent points')
  bullet('At level 20 you get a message that you can get your promotion (King Tibianus in Thais and the other promotion NPCs).')
  bullet('After the promotion the Talent Trees unlock: you get 1 point at level 20 and then 1 more point every 10 levels (30, 40, 50 ...).')
  bullet('Open the trees with the Talent Trees button in the top bar or with Ctrl+I. Click a talent to spend a point.')
  h2('Rows and the final perk')
  bullet('Every tree has 5 rows. A row unlocks when you have spent 4 more points in that tree (0, 4, 8, 12, 16).')
  bullet('The final perk at the bottom costs 1 point and needs 20 points spent in the same tree - it is the strongest bonus of the tree.')
  bullet('All three trees can be developed at the same time; the first rows hold the small bonuses, the last rows and the final perk the strongest ones.')
  h2('Reset')
  body('All talent points can be reset for the price of all five blessings (it grows with your level). A reset is only possible in a protection zone or out of combat.')
  note('Talent bonuses are added to your item attributes (same stats as rarity items) and show up in the Skills window.')
  note('Multi shot (bows and crossbows) is an AoE volley: the extra arrow also hits up to 2 more monsters within 2 tiles of your target.')
end
local function talentPage(base)
  local v=data and data.talents and data.talents[base]
  if not v then h1('Talent Trees');body('Loading...');return end
  h1(v.vocation..' - Talent Trees')
  for _,tree in ipairs(v.trees or {}) do
    h2(tree.name..' ('..tree.kind..')')
    body(tree.desc or '')
    collapsible(tree.name..' - all talents',function(box)
      for ri,rw in ipairs(tree.rows or {}) do
        boxLabel(box,'Row '..ri..(rw.need>0 and ('  (needs '..rw.need..' points in this tree)') or '  (open from the start)'),'#e8d9a8')
        for _,node in ipairs(rw.nodes or {}) do boxLabel(box,'   '..node.name..'  (max '..node.max..' ranks): '..node.per..' per rank') end
      end
      local cap=tree.cap or {}
      boxLabel(box,'Final perk: '..(cap.name or '')..'  (needs 20 points in this tree, costs 1)','#ffd35a')
      boxLabel(box,'   '..(cap.desc or ''))
    end)
  end
end
for base=1,4 do pages['talents/'..base]=function() talentPage(base) end end

local navButtons={}
local function buildNav()
  local panel=ui('knowledgeNav');local sb=ui('knowledgeNavScroll');local keep=sb and sb:getValue() or 0
  panel:destroyChildren();navButtons={}
  local function add(entry,indent)
    -- 10.10.2026: own style - the "on" state of a normal button moved the text of the open page to the left
    local b=g_ui.createWidget(indent>0 and 'WikiNavSub' or 'WikiNavButton',panel)
    local text=entry.name
    if entry.children then text=text..'   '..(expanded[entry.key] and '-' or '+') end
    b:setText(text);b:setOn(current==entry.key)
    b.onClick=function()
      -- 12.10.2026 (Tobeto): only one group is open at a time, the list scrolls
      if entry.children then local open=not expanded[entry.key];expanded={};expanded[entry.key]=open end
      K.go(entry.children and entry.children[1].key or entry.key)
    end
    navButtons[entry.key]=b
    if entry.children and expanded[entry.key] then for _,c in ipairs(entry.children) do add(c,10) end end
  end
  for _,entry in ipairs(nav) do add(entry,0) end
  -- keep the list where it was and show the open page (12.10.2026)
  addEvent(function()
    if sb and not sb:isDestroyed() then sb:setValue(keep) end
    local b=navButtons[current];if b and not b:isDestroyed() and panel.ensureChildVisible then panel:ensureChildVisible(b) end
  end)
end

function K.render()
  if not win then return end
  local c=content();c:destroyChildren()
  local page=pages[current] or pages.home
  local ok,err=pcall(page)
  if not ok then g_logger.error('[wiki knowledge] '..tostring(err)) end
  ui('address'):setText('wiki://knowledge/'..current)
  ui('knowledgeScroll'):setValue(0)
  buildNav()
end
function K.go(key,noHistory)
  if current and current~=key and not noHistory then history[#history+1]=current end
  current=key;K.render()
end
function K.back()
  local prev=table.remove(history);if prev then K.go(prev,true) end
end
local parts={}
local function onData(protocol,code,buffer)
  local i,total,piece=buffer:match('^(%d+)/(%d+)|(.*)$')
  if not i then return end
  i,total=tonumber(i),tonumber(total)
  if i==1 then parts={} end
  parts[i]=piece
  if i<total then return end
  local text=table.concat(parts);parts={}
  local ok,d=pcall(json.decode,text);if not ok or type(d)~='table' then return end
  data=d;if win and win:isVisible() and ui('knowledge'):isVisible() then K.render() end
end
function K.open(window)
  win=window
  if g_game.isOnline() then g_game.getProtocolGame():sendExtendedOpcode(OPCODE,'knowledge') end
  K.go(current or 'home',true)
end
pcall(ProtocolGame.unregisterExtendedOpcode,OPCODE)
ProtocolGame.registerExtendedOpcode(OPCODE,onData)
function K.terminate() pcall(ProtocolGame.unregisterExtendedOpcode,OPCODE) end
