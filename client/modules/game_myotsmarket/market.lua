-- OurTibia Market (07.10.2026). Server: data/scripts/myots/91_market.lua, extended opcode 122.
-- Only two tabs: BUY (catalog of every obtainable item, filters for all bonuses, offers)
-- and SELL (your backpack, offer builder for gold or Tibia Coins, your offers, history).
local OPCODE = 122
local window
local depotPos = nil
local parts = {}
local tab = 'buy'
local catalog, cats = nil, {}
local filterDefs, rarityNames = {}, {'Common', 'Rare', 'Epic', 'Legendary', 'Mythical', 'World Ending'}
local selectedItem, selectedOffer, offerRows = nil, nil, {}
local current = {page = 1, pages = 1}
local sellRows, selectedSell = {}, nil
local queue, queueEvent = {}, nil
local catalogEvent = nil
local catalogRequested = false
local attrSel, pickerIndex = {}, nil

local RARITY_COLORS = {[0] = '#a0a0a0', [1] = '#ffffff', [2] = '#4fa8ff', [3] = '#b05cff', [4] = '#ffa020', [5] = '#ff4848', [6] = '#40ffd0'}

-- 11.10.2026: keep the window inside small game windows (default 1020x644)
local function fitToScreen(w, fullW, fullH)
  if not w then return end
  local root = rootWidget or g_ui.getRootWidget()
  local rw, rh = root:getWidth(), root:getHeight()
  w:setWidth(math.min(fullW, rw - 10))
  w:setHeight(math.min(fullH, rh - 10))
  local pos = w:getPosition()
  w:setPosition({x = math.max(0, math.min(pos.x, rw - w:getWidth())), y = math.max(0, math.min(pos.y, rh - w:getHeight()))})
end

local function ui(id) return window and window:recursiveGetChildById(id) end
local function money(n)
  n = math.floor(tonumber(n) or 0)
  local s = tostring(math.abs(n)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
  return (n < 0 and '-' or '') .. s
end
local function curName(c) return c == 'coins' and 'Tibia Coins' or 'gold' end
local function duration(s)
  s = math.max(0, math.floor(tonumber(s) or 0))
  local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
  if d > 0 then return d .. 'd ' .. h .. 'h' end
  if h > 0 then return h .. 'h ' .. m .. 'm' end
  return m .. 'm'
end
local function list(t) return type(t) == 'table' and t or {} end

-- The server ignores commands sent faster than every 150 ms, so they go through a queue.
local function flush()
  queueEvent = nil
  if #queue == 0 then return end
  local text = table.remove(queue, 1)
  if g_game.isOnline() then g_game.getProtocolGame():sendExtendedOpcode(OPCODE, text) end
  if #queue > 0 then queueEvent = scheduleEvent(flush, 220) end
end
local function send(text)
  -- a newer request of the same kind replaces a waiting one
  local kind = text:match('^(%a+)')
  for i = #queue, 1, -1 do
    if queue[i]:match('^(%a+)') == kind and (kind == 'search' or kind == 'stats' or kind == 'detail' or kind == 'inv' or kind == 'mine') then table.remove(queue, i) end
  end
  queue[#queue + 1] = text
  if not queueEvent then queueEvent = scheduleEvent(flush, 1) end
end

local function status(text, ok)
  local l = ui('status'); if not l then return end
  l:setText(text or '')
  l:setColor(ok == true and '#60e060' or ok == false and '#ff7060' or '#e0e0e0')
end
-- 10.10.2026: Tibia Coin value in USDT from the website coin exchange (micro-USDT per coin)
local usdRate
local function usd(tc)
  if not usdRate or usdRate <= 0 then return '' end
  return string.format(' (~%.2f USDT)', (tonumber(tc) or 0) * usdRate / 1000000)
end
local function setBalance(bal)
  if type(bal) ~= 'table' then return end
  usdRate = tonumber(bal.usd)
  local text = 'Gold: ' .. money(bal.gold) .. '     Tibia Coins: ' .. money(bal.coins)
  if tonumber(bal.trad) and tonumber(bal.trad) > 0 then text = text .. ' (' .. money(bal.trad) .. ' sellable)' end
  if usdRate and usdRate > 0 then text = text .. string.format('     1 TC ~ %.4f USDT', usdRate / 1000000) end
  ui('balance'):setText(text)
end

local function rarityText(r)
  local st, tier, up, rar = r.st, tonumber(r.t), tonumber(r.u), tonumber(r.r)
  if not st and not tier then return '' end
  if st == 'u' then return 'Unidentified' .. (tier and tier > 0 and ('  |  Tier ' .. tier) or '') end
  local out = {}
  if rar and rar > 0 then out[#out + 1] = rarityNames[rar] or ('Rarity ' .. rar) end
  if tier and tier > 0 then out[#out + 1] = 'Tier ' .. tier end
  if up and up > 0 then out[#out + 1] = 'Upgrade +' .. up end
  return table.concat(out, '  |  ')
end
local function nameColor(r)
  if r.st == 'u' then return RARITY_COLORS[0] end
  return RARITY_COLORS[tonumber(r.r) or 1] or '#ffffff'
end

-- ------------------------------------------------------------------ BUY: catalog
local function categoryIndex()
  local opt = ui('category'):getCurrentOption()
  return opt and tonumber(opt.data) or 0
end
function refreshCatalog()
  if catalogEvent then removeEvent(catalogEvent) end
  catalogEvent = scheduleEvent(function()
    catalogEvent = nil
    if not window or not catalog then return end
    local text = ui('search'):getText():lower()
    local cat = categoryIndex()
    local listW = ui('catalogList'); listW:destroyChildren()
    local shown, total = 0, 0
    for _, it in ipairs(catalog) do
      if (cat == 0 or it.k == cat) and (text == '' or it.n:lower():find(text, 1, true)) then
        total = total + 1
        if shown < 250 then
          shown = shown + 1
          local row = g_ui.createWidget('MarketRow', listW)
          row:getChildById('item'):setItemId(it.c)
          row:getChildById('name'):setText(it.n)
          row:getChildById('info'):setText(cats[it.k] or '')
          row.itemId = it.i
          row:setOn(selectedItem == it.i)
          row.onClick = function() selectCatalogItem(it) end
        end
      end
    end
    ui('catCaption'):setText('Items (' .. total .. (total > shown and (', first ' .. shown .. ' shown - type to search') or '') .. ')')
  end, 150)
end

function selectCatalogItem(it)
  selectedItem = it.i
  for _, w in ipairs(ui('catalogList'):getChildren()) do w:setOn(w.itemId == it.i) end
  selectedOffer = nil
  ui('dItem'):setItemId(it.c)
  detailTexts = {}
  ui('dText'):setText(it.n .. '\n' .. (cats[it.k] or ''))
  ui('dStats'):setText('')
  ui('buyTotal'):setText('')
  ui('buyButton'):setEnabled(false)
  search(1)
  send('stats:' .. it.i .. ':' .. (ui('fCur'):getCurrentOption().data == 'coins' and 'coins' or 'gold'))
end

function showAllOffers()
  selectedItem = nil
  for _, w in ipairs(ui('catalogList'):getChildren()) do w:setOn(false) end
  search(1)
end

-- ------------------------------------------------------------------ BUY: filters and search
local function num(id) return tonumber(ui(id):getText()) end
local function filters(page)
  local f = {page = page or 1}
  if selectedItem then f.item = selectedItem
  else
    local cat = categoryIndex(); if cat > 0 then f.cat = cat end
    local q = ui('search'):getText(); if q ~= '' then f.q = q end
  end
  local cur = ui('fCur'):getCurrentOption(); if cur and cur.data ~= '' then f.cur = cur.data end
  if num('fTmin') then f.tmin = num('fTmin') end
  if num('fTmax') then f.tmax = num('fTmax') end
  if num('fUmin') then f.umin = num('fUmin') end
  local rar = ui('fRar'):getCurrentOption(); if rar and tonumber(rar.data) and tonumber(rar.data) > 0 then f.rmin = tonumber(rar.data) end
  local attrs = {}
  for i = 1, 3 do
    local d = attrSel[i]
    if d then
      local v = tonumber(ui('fV' .. i):getText()) or 0
      if d.u == '%' then v = math.floor(v * 100 + 0.5) end
      attrs[#attrs + 1] = {d.k, v}
    end
  end
  if #attrs > 0 then f.attrs = attrs end
  local sort = ui('fSort'):getCurrentOption(); f.sort = sort and sort.data or 'newest'
  if ui('fDesc'):isChecked() then f.desc = true end
  return f
end
function search(page)
  current.filters = filters(page)
  send('search:' .. json.encode(current.filters))
end
function page(d)
  local p = math.max(1, math.min(current.pages or 1, (current.page or 1) + d))
  if p ~= current.page then search(p) end
end
function resetFilters()
  ui('fCur'):setCurrentIndex(1); ui('fRar'):setCurrentIndex(1); ui('fSort'):setCurrentIndex(1)
  for _, id in ipairs({'fTmin', 'fTmax', 'fUmin', 'fV1', 'fV2', 'fV3'}) do ui(id):setText('') end
  attrSel = {}; updateAttrButtons(); closePicker()
  ui('fDesc'):setChecked(false)
  search(1)
end

-- 07.10.2026: "Ranges" shows the min-max value of every bonus (text dr from the server)
local detailTexts, sellTexts = {}, {}
local function rangesOn() local c = ui('dRanges') return c and c:isChecked() end
local function showDetailText()
  if not detailTexts.d then return end
  ui('dText'):setText((rangesOn() and detailTexts.dr) or detailTexts.d)
end
local function showSellText()
  if not sellTexts.d then return end
  ui('sText'):setText((rangesOn() and sellTexts.dr) or sellTexts.d)
end
function toggleRanges(box)
  local on = box:isChecked()
  for _, id in ipairs({'dRanges', 'sRanges'}) do
    local c = ui(id)
    if c and c ~= box and c:isChecked() ~= on then c:setChecked(on) end
  end
  showDetailText(); showSellText()
end

local function selectOffer(r)
  selectedOffer = r
  for _, w in ipairs(ui('offerList'):getChildren()) do w:setOn(w.offerId == r.id) end
  ui('dItem'):setItemId(r.c)
  detailTexts = {}
  ui('dText'):setText(r.n)
  ui('buyAmount'):setText('1')
  updateBuyTotal()
  send('detail:' .. r.id)
end
local function renderOffers(data)
  current.page, current.pages = tonumber(data.page) or 1, tonumber(data.pages) or 1
  offerRows = list(data.rows)
  local listW = ui('offerList'); listW:destroyChildren()
  for _, r in ipairs(offerRows) do
    local w = g_ui.createWidget('OfferRow', listW)
    w.offerId = r.id
    w:getChildById('item'):setItemId(r.c)
    if (tonumber(r.a) or 1) > 1 then w:getChildById('item'):setItemCount(r.a) end
    w:getChildById('name'):setText(r.n); w:getChildById('name'):setColor(nameColor(r))
    w:getChildById('info'):setText(rarityText(r))
    w:getChildById('amount'):setText(tostring(r.a))
    w:getChildById('price'):setText(money(r.p) .. (r.cur == 'coins' and ' TC' or ' gp'))
    w:getChildById('price'):setColor(r.cur == 'coins' and '#7fd0ff' or '#ffd75a')
    if r.cur == 'coins' and usdRate then w:getChildById('price'):setTooltip('~' .. string.format('%.2f', r.p * usdRate / 1000000) .. ' USDT each at the coin exchange price') end
    w:getChildById('seller'):setText(r.mine and (r.s .. ' (you)') or r.s)
    w:getChildById('ends'):setText(duration(r.e))
    w:setOn(selectedOffer and selectedOffer.id == r.id)
    w.onClick = function() selectOffer(r) end
    -- 07.10.2026: right click -> "Link to chat" (the same item link as from the backpack)
    w.onMouseRelease = function(self, mousePos, button)
      if button ~= MouseRightButton then return false end
      local menu = g_ui.createWidget('PopupMenu')
      menu:setGameMenu(true)
      menu:addOption(tr('Link to chat'), function() send('link:' .. r.id) end)
      menu:display(mousePos)
      return true
    end
  end
  ui('oCaption'):setText('Offers (' .. (tonumber(data.total) or #offerRows) .. ')')
  ui('pageLabel'):setText('Page ' .. current.page .. ' / ' .. current.pages)
  ui('prev'):setEnabled(current.page > 1); ui('next'):setEnabled(current.page < current.pages)
  if #offerRows == 0 then
    local l = g_ui.createWidget('Label', listW)
    l:setText(selectedItem and 'Nobody sells this item right now.' or 'No offers match these filters.')
    l:setColor('#909090'); l:setHeight(24); l:setTextAlign(AlignCenter)
  end
  -- keep the selected offer only if it is still listed
  if selectedOffer then
    local still = false
    for _, r in ipairs(offerRows) do if r.id == selectedOffer.id then still = true; selectedOffer = r end end
    if not still then selectedOffer = nil end
  end
  updateBuyTotal()
end

function updateBuyTotal()
  if not window then return end
  local r = selectedOffer
  if not r then ui('buyTotal'):setText(''); ui('buyButton'):setEnabled(false); return end
  local n = math.floor(tonumber(ui('buyAmount'):getText()) or 0)
  local okAmount = n >= 1 and n <= (tonumber(r.a) or 1)
  ui('buyTotal'):setText(okAmount and ('Total: ' .. money(n * r.p) .. ' ' .. (r.cur == 'coins' and ('TC' .. usd(n * r.p)) or curName(r.cur))) or ('Amount 1 - ' .. r.a))
  ui('buyButton'):setEnabled(okAmount and not r.mine)
  ui('buyButton'):setText(r.mine and 'Your own offer' or 'Buy')
end
function buyMaxAmount()
  if selectedOffer then ui('buyAmount'):setText(tostring(selectedOffer.a)) end
end
function buy()
  local r = selectedOffer; if not r then return end
  local n = math.floor(tonumber(ui('buyAmount'):getText()) or 0)
  if n < 1 or n > (tonumber(r.a) or 1) then return status('Choose an amount between 1 and ' .. r.a .. '.', false) end
  local text = 'Buy ' .. n .. 'x ' .. r.n .. ' for ' .. money(n * r.p) .. ' ' .. curName(r.cur) .. (r.cur == 'coins' and usd(n * r.p) or '') .. '?'
  local box
  local function yes() if box then box:destroy() end; send('buy:' .. r.id .. ':' .. n) end
  local function no() if box then box:destroy() end end
  box = displayGeneralBox('Market', text, {{text = 'Buy', callback = yes}, {text = 'Cancel', callback = no}, anchor = AnchorHorizontalCenter}, yes, no)
end

local function renderStats(d)
  local lines = {}
  local unit = d.cur == 'coins' and ' TC' or ' gp'
  lines[#lines + 1] = 'Lowest: ' .. (d.low and money(d.low) .. unit or '-')
  lines[#lines + 1] = 'Highest: ' .. (d.high and money(d.high) .. unit or '-')
  lines[#lines + 1] = 'Average sold: ' .. (d.avg and money(d.avg) .. unit or '-')
  lines[#lines + 1] = 'Last sold: ' .. (d.last and money(d.last) .. unit or '-')
  local text = table.concat(lines, '\n')
  if tab == 'buy' then ui('dStats'):setText(text) else ui('sStats'):setText(table.concat(lines, '   ')) end
end

-- ------------------------------------------------------------------ SELL
function refreshSell() send('inv'); send('mine') end
local function selectSell(r)
  selectedSell = r
  for _, w in ipairs(ui('invList'):getChildren()) do w:setOn(w.sellIndex == r.x and w.sellF == r.f) end
  ui('sItem'):setItemId(r.c)
  if (tonumber(r.a) or 1) > 1 then ui('sItem'):setItemCount(r.a) else ui('sItem'):setItemCount(1) end
  sellTexts = {d = r.d or r.n, dr = r.dr}
  showSellText()
  ui('sAmount'):setText(tostring(r.a or 1))
  ui('sAmount'):setEnabled((tonumber(r.a) or 1) > 1)
  updateSellTotal()
  send('stats:' .. r.i .. ':' .. (ui('sCur'):getCurrentOption().data or 'gold'))
end
local function renderInventory(data)
  sellRows = list(data.rows)
  local listW = ui('invList'); listW:destroyChildren()
  local keep = nil
  for _, r in ipairs(sellRows) do
    local w = g_ui.createWidget('MarketRow', listW)
    w.sellIndex, w.sellF = r.x, r.f
    w:getChildById('item'):setItemId(r.c)
    if (tonumber(r.a) or 1) > 1 then w:getChildById('item'):setItemCount(r.a) end
    w:getChildById('name'):setText(r.n); w:getChildById('name'):setColor(nameColor(r))
    local info = rarityText(r)
    w:getChildById('info'):setText(info ~= '' and info or ((tonumber(r.a) or 1) > 1 and (r.a .. ' pieces') or ''))
    if r.d then w:setTooltip(r.d) end
    w.onClick = function() selectSell(r) end
    if selectedSell and selectedSell.f == r.f and selectedSell.i == r.i then keep = r end
  end
  if #sellRows == 0 then
    local l = g_ui.createWidget('Label', listW)
    l:setText('Nothing in your backpack can be sold.'); l:setColor('#909090'); l:setHeight(24)
  end
  ui('invCaption'):setText('Your backpack (' .. #sellRows .. ' items)')
  if keep then selectSell(keep)
  else
    selectedSell = nil
    sellTexts = {}; ui('sItem'):setItemId(0); ui('sText'):setText('Choose an item from your backpack.'); ui('sStats'):setText('')
    updateSellTotal()
  end
end
function updateSellTotal()
  if not window then return end
  local r = selectedSell
  if not r then ui('sTotal'):setText(''); ui('sButton'):setEnabled(false); return end
  local price = math.floor(tonumber(ui('sPrice'):getText()) or 0)
  local n = math.floor(tonumber(ui('sAmount'):getText()) or 0)
  local cur = ui('sCur'):getCurrentOption().data
  local ok = price >= 1 and n >= 1 and n <= (tonumber(r.a) or 1)
  ui('sTotal'):setText(ok and ('Total: ' .. money(price * n) .. ' ' .. (cur == 'coins' and ('TC' .. usd(price * n)) or curName(cur))) or (price < 1 and 'Enter a price.' or ('Amount 1 - ' .. r.a)))
  ui('sButton'):setEnabled(ok)
end
function sell()
  local r = selectedSell; if not r then return end
  local price = math.floor(tonumber(ui('sPrice'):getText()) or 0)
  local n = math.floor(tonumber(ui('sAmount'):getText()) or 0)
  local cur = ui('sCur'):getCurrentOption().data
  local days = tonumber(ui('sDur'):getCurrentOption().data) or 7
  local text = 'Sell ' .. n .. 'x ' .. r.n .. ' for ' .. money(price) .. ' ' .. curName(cur) .. ' each (total ' .. money(price * n) .. (cur == 'coins' and usd(price * n) or '') .. ') for ' .. days .. ' days?\nThe item leaves your backpack until it is sold or you cancel the offer.'
  local box
  local function yes()
    if box then box:destroy() end
    send('sell:' .. json.encode({x = r.x, f = r.f, p = price, cur = cur, a = n, d = days}))
  end
  local function no() if box then box:destroy() end end
  box = displayGeneralBox('Market', text, {{text = 'Sell', callback = yes}, {text = 'Cancel', callback = no}, anchor = AnchorHorizontalCenter}, yes, no)
end
local function renderMine(data)
  local listW = ui('mineList'); listW:destroyChildren()
  local rows = list(data.rows)
  for _, r in ipairs(rows) do
    local w = g_ui.createWidget('MyOfferRow', listW)
    w:getChildById('item'):setItemId(r.c)
    if (tonumber(r.a) or 1) > 1 then w:getChildById('item'):setItemCount(r.a) end
    w:getChildById('name'):setText(r.a .. 'x ' .. r.n); w:getChildById('name'):setColor(nameColor(r))
    local extra = rarityText(r)
    w:getChildById('info'):setText(money(r.p) .. ' ' .. curName(r.cur) .. (r.cur == 'coins' and usd(r.p) or '') .. ' each   |   ends in ' .. duration(r.e) .. (extra ~= '' and ('   |   ' .. extra) or ''))
    w:getChildById('cancel').onClick = function()
      local box
      local function yes() if box then box:destroy() end; send('cancel:' .. r.id) end
      local function no() if box then box:destroy() end end
      box = displayGeneralBox('Market', 'Cancel your offer of ' .. r.a .. 'x ' .. r.n .. '? The item comes back to your backpack.', {{text = 'Yes', callback = yes}, {text = 'No', callback = no}, anchor = AnchorHorizontalCenter}, yes, no)
    end
  end
  if #rows == 0 then
    local l = g_ui.createWidget('Label', listW); l:setText('You have no active offers.'); l:setColor('#909090'); l:setHeight(24)
  end
  ui('mCaption'):setText('Your offers (' .. #rows .. ' / ' .. (data.max or 40) .. ')')
  local hl = ui('historyList'); hl:destroyChildren()
  for _, h in ipairs(list(data.history)) do
    local w = g_ui.createWidget('HistoryRow', hl)
    w:setText(os.date('%d.%m %H:%M', tonumber(h.t) or 0) .. '  ' .. (h.sold and 'Sold ' or 'Bought ') .. h.a .. 'x ' .. h.n .. ' - ' .. money((tonumber(h.p) or 0) * (tonumber(h.a) or 1)) .. (h.cur == 'coins' and ' TC' or ' gp'))
    w:setColor(h.sold and '#80e080' or '#e0c070')
    w:setTooltip((h.sold and 'Buyer: ' or 'Seller: ') .. tostring(h.w))
  end
end

-- ------------------------------------------------------------------ bonus picker
-- 07.10.2026: a small list with a search field and a scroll bar instead of a drop-down
-- that ran off the screen.
local function defText(d) return d.l .. (d.u ~= '' and (' (' .. d.u .. ')') or '') end
function updateAttrButtons()
  if not window then return end
  for i = 1, 3 do
    local b = ui('fA' .. i)
    b:setText(attrSel[i] and defText(attrSel[i]) or ('Bonus ' .. i .. ': any'))
    b:setTooltip(attrSel[i] and defText(attrSel[i]) or 'Click to choose a bonus')
  end
end
function closePicker()
  pickerIndex = nil
  local p = ui('picker'); if p then p:hide() end
end
function fillPicker()
  local p = ui('picker'); if not p or not pickerIndex then return end
  local q = ui('pickerSearch'):getText():lower()
  local listW = ui('pickerList'); listW:destroyChildren()
  local function addRow(text, d)
    local b = g_ui.createWidget('Button', listW)
    b:setHeight(20); b:setText(text); b:setTextAlign(AlignLeft)
    b.onClick = function()
      if pickerIndex then attrSel[pickerIndex] = d end
      updateAttrButtons(); closePicker()
    end
  end
  addRow('Any (no filter)', nil)
  local used = {}
  for i = 1, 3 do if i ~= pickerIndex and attrSel[i] then used[attrSel[i].k] = true end end
  for _, d in ipairs(filterDefs) do
    if not used[d.k] and (q == '' or d.l:lower():find(q, 1, true)) then addRow(defText(d), d) end
  end
end
function openPicker(i)
  local p = ui('picker'); if not p then return end
  if pickerIndex == i and p:isVisible() then return closePicker() end
  pickerIndex = i
  local b = ui('fA' .. i)
  local x = math.min(b:getX(), window:getX() + window:getWidth() - p:getWidth() - 10)
  p:setPosition({x = x, y = b:getY() + b:getHeight() + 2})
  ui('pickerTitle'):setText('Bonus ' .. i .. ' - choose a bonus')
  ui('pickerSearch'):setText('')
  p:show(); p:raise(); p:focus()
  fillPicker()
  ui('pickerSearch'):focus()
end

-- ------------------------------------------------------------------ tabs
function setTab(name)
  tab = name
  ui('tabBuy'):setOn(name == 'buy'); ui('tabSell'):setOn(name == 'sell')
  ui('buyPanel'):setVisible(name == 'buy'); ui('sellPanel'):setVisible(name == 'sell')
  if name == 'buy' then search(current.page or 1) else refreshSell() end
end

-- ------------------------------------------------------------------ network
local function fillFilters(data)
  filterDefs = list(data.attrs)
  if type(data.rarities) == 'table' and #data.rarities > 0 then rarityNames = data.rarities end
  ui('fRar'):clearOptions(); ui('fRar'):addOption('Any', 0)
  for i, n in ipairs(rarityNames) do ui('fRar'):addOption(n, i) end
  attrSel = {}; updateAttrButtons()
  setBalance(data.bal)
end
local function receive(protocol, opcode, buffer)
  local i, total, piece = buffer:match('^(%d+)/(%d+)|(.*)$')
  if not i then return end
  i, total = tonumber(i), tonumber(total); if i == 1 then parts = {} end; parts[i] = piece; if i < total then return end
  local ok, data = pcall(json.decode, table.concat(parts)); parts = {}
  if not ok or type(data) ~= 'table' or not window then return end
  if data.bal then setBalance(data.bal) end
  local k = data.kind
  if k == 'open' then
    if type(data.pos) == 'table' then depotPos = {x = data.pos[1], y = data.pos[2], z = data.pos[3]} end
    if not window:isVisible() then show() end
    return
  end
  if k == 'close' then hide() return end
  if k == 'catalog' then
    catalog = list(data.items); cats = list(data.cats)
    local c = ui('category'); c:clearOptions(); c:addOption('All categories', 0)
    for idx, n in ipairs(cats) do c:addOption(n, idx) end
    refreshCatalog()
  elseif k == 'filters' then fillFilters(data)
  elseif k == 'offers' then renderOffers(data)
  elseif k == 'detail' then
    if selectedOffer and selectedOffer.id == data.id then
      detailTexts = {d = data.d or selectedOffer.n, dr = data.dr}
      showDetailText()
      if type(data.row) == 'table' then selectedOffer = data.row; updateBuyTotal() end
    end
  elseif k == 'stats' then renderStats(data)
  elseif k == 'inv' then renderInventory(data)
  elseif k == 'mine' then renderMine(data)
  elseif k == 'msg' then
    status(data.text, data.ok)
    if data.ok and tab == 'buy' then
      search(current.page or 1)
      if selectedItem then send('stats:' .. selectedItem .. ':' .. (ui('fCur'):getCurrentOption().data == 'coins' and 'coins' or 'gold')) end
    end
  end
end

-- ------------------------------------------------------------------ window
function show()
  if not g_game.isOnline() then return end
  window:show(); fitToScreen(window, 980, 650); window:raise(); window:focus()
  if not catalogRequested then catalogRequested = true; send('catalog') end
  setTab(tab or 'buy')
end
function hide()
  closePicker()
  if window then window:hide() end
  queue = {}
  if queueEvent then removeEvent(queueEvent); queueEvent = nil end
end
-- 07.10.2026: the Market opens only from the depot locker and closes when you walk away.
local function onPositionChange(creature, newPos)
  if not window or not window:isVisible() or not depotPos or not newPos then return end
  if creature ~= g_game.getLocalPlayer() then return end
  if newPos.z ~= depotPos.z or math.abs(newPos.x - depotPos.x) > 1 or math.abs(newPos.y - depotPos.y) > 1 then hide() end
end

local function onGameEnd()
  hide()
  catalogRequested = false; catalog = nil
  selectedItem, selectedOffer, selectedSell = nil, nil, nil
end

function init()
  window = g_ui.displayUI('market'); window:hide()
  local fc = ui('fCur'); fc:addOption('Any', ''); fc:addOption('Gold', 'gold'); fc:addOption('Tibia Coins', 'coins')
  local fs = ui('fSort'); fs:addOption('Newest', 'newest'); fs:addOption('Price', 'price'); fs:addOption('Name', 'name'); fs:addOption('Amount', 'amount'); fs:addOption('Tier', 'tier'); fs:addOption('Ends soonest', 'expires')
  local sc = ui('sCur'); sc:addOption('Gold', 'gold'); sc:addOption('Tibia Coins', 'coins')
  local sd = ui('sDur'); sd:addOption('3 days', 3); sd:addOption('7 days', 7); sd:addOption('30 days', 30); sd:setCurrentIndex(2)
  sc.onOptionChange = function() updateSellTotal(); if selectedSell then send('stats:' .. selectedSell.i .. ':' .. (sc:getCurrentOption().data or 'gold')) end end
  ui('category').onOptionChange = function() refreshCatalog() end
  ui('fRar'):addOption('Any', 0)
  for i = 1, 3 do local idx = i; ui('fA' .. i).onClick = function() openPicker(idx) end end
  updateAttrButtons()
  ProtocolGame.registerExtendedOpcode(OPCODE, receive)
  connect(g_game, {onGameEnd = onGameEnd})
  connect(LocalPlayer, {onPositionChange = onPositionChange})
end
function terminate()
  pcall(ProtocolGame.unregisterExtendedOpcode, OPCODE)
  disconnect(g_game, {onGameEnd = onGameEnd})
  disconnect(LocalPlayer, {onPositionChange = onPositionChange})
  if queueEvent then removeEvent(queueEvent) end
  if catalogEvent then removeEvent(catalogEvent) end
  if window then window:destroy() end
end
