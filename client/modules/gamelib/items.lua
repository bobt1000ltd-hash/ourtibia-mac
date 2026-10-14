-- to-do
-- change to ItemsDatabase.setTier(UIitem) to UIitem:setTier()
ItemsDatabase = {}

ItemsDatabase.rarityColors = {
    ["yellow"] = '#ffff00',
    ["purple"] = '#d65cff',
    ["blue"] = '#7aa7ff',
    ["green"] = '#00eb00',
    ["grey"] = '#aaaaaa',
}
-- 14.10.2026 (owner): RL-like colours with lower bands (item value = best NPC buy price), so that
-- items worth 40,000+ (dragon scale mail...) are already yellow:
-- 1-999 grey, 1,000-4,999 green, 5,000-14,999 blue, 15,000-39,999 purple, 40,000+ yellow.
function ourValueBand(value)
    value = tonumber(value) or 0
    if value >= 40000 then
        return "yellow"
    elseif value >= 15000 then
        return "purple"
    elseif value >= 5000 then
        return "blue"
    elseif value >= 1000 then
        return "green"
    elseif value >= 1 then
        return "grey"
    end
    return "white"
end
local getColorForValue = ourValueBand
-- Same source model as the OTC/RL loot-color implementation: one price per
-- item, derived from all available NPC purchase offers. No NPC name changes
-- a colour; thresholds below decide it for frames and Loot Channel alike.
local function getNpcSellValue(itemId)
    local hud = modules.game_myotshud
    local prices = hud and hud.OurNpcSellPrices
    if not prices or not itemId then return 0 end
    local entry = prices[itemId]
    if not entry or not entry.offers or #entry.offers == 0 then return 0 end
    local best = 0
    for _, offer in ipairs(entry.offers) do
        local price = tonumber(offer.price) or 0
        if price > 0 then best = math.max(best, price) end
    end
    return best
end
local function getClipForRarity(rarity)
    local clips = {
        yellow = '128 0 32 32', purple = '96 0 32 32', blue = '64 0 32 32',
        green = '32 0 32 32', grey = '0 0 32 32'
    }
    return clips[rarity] or ''
end
function ItemsDatabase.getClipAndImagePath(item)
    if not item then
        return nil, nil, nil
    end

    local frameOption = modules.client_options.getOption('framesRarity')
    -- 12.10.2026 (owner): no value/rarity frames on item slots anywhere; the
    -- colours are only used in the Loot channel and loot messages.
    if true or frameOption == "none" then
        return nil, nil, nil
    end
    local imagePath = '/images/ui/item'
    local clip = nil

    -- Several legacy UI lists pass a server-side item number.  If it has a
    -- generated NPC price, no DAT lookup is needed to render its value frame.
    -- Avoiding that lookup also prevents invalid legacy ids from being logged
    -- (or destabilising the client) during panel startup.
    local numericItemId = type(item) == "number" and item or nil
    local numericPrice = numericItemId and getNpcSellValue(numericItemId) or 0
    if numericItemId and numericPrice <= 0 then
        -- Numeric callers are catalog/market rows, not live items. They have
        -- no safe DAT identity in this mixed 10.98 asset set, so leave them
        -- unframed instead of querying an invalid id.
        return nil, nil, nil
    end

    if not item then
        return nil, nil, nil
    end

    if item then
        -- 11.10.2026: the server's NPC purchase price first (same order as the loot
        -- message colours); the DAT mean price of this mixed 10.98 asset set is
        -- wrong for many classic items (a dragon scale mail was not yellow).
        local price = numericPrice
        if price <= 0 and type(item) ~= "number" and item and item.getId then
            price = getNpcSellValue(item:getId())
        end
        if price <= 0 and type(item) ~= "number" and item and item.getMeanPrice then
            price = item:getMeanPrice() or 0
        end
        local itemId = type(item) == "number" and numericItemId or (item.getId and item:getId() or nil)
        local itemRarity = getColorForValue(price)
        if itemRarity then
            clip = getClipForRarity(itemRarity)
            if clip ~= "" then
                if frameOption == "frames" then
                    imagePath = "/images/ui/rarity_frames"
                elseif frameOption == "corners" then
                    imagePath = "/images/ui/containerslot-coloredges"
                end
            else
                clip = nil
            end
        end
    end

    local clipObject = nil
    if clip then
        local x, y, w, h = clip:match("(%d+) (%d+) (%d+) (%d+)")
        clipObject = { x = tonumber(x), y = tonumber(y), width = tonumber(w), height = tonumber(h) }
    end

    return clip, imagePath, clipObject
end

function ItemsDatabase.setRarityItem(widget, item, style)
    if not g_game.getFeature(GameColorizedLootValue) or not widget then
        return
    end

    local clip, imagePath = ItemsDatabase.getClipAndImagePath(item)

    if not imagePath then
        -- no frame applies (empty slot or frames disabled): clear a frame left by a previous item,
        -- but only if this widget is currently showing one, to avoid clobbering custom backgrounds
        local currentSource = widget:getImageSource()
        if currentSource == "/images/ui/rarity_frames" or currentSource == "/images/ui/containerslot-coloredges" then
            widget:setImageClip(nil)
            widget:setImageSource('/images/ui/item')
        end
        return
    end

    widget:setImageClip(clip)
    widget:setImageSource(imagePath)
    if style then
        widget:setStyle(style)
    end
end

function ItemsDatabase.getColorForRarity(rarity)
    return ItemsDatabase.rarityColors[rarity] or TextColors.white
end

function ItemsDatabase.setColorLootMessage(text)
    local function coloringLootName(match)
        local id, itemName = match:match("(%d+)|(.+)")
        if not id or not itemName then
            -- If pattern doesn't match itemId|itemName format, return the original match with braces
            return "{" .. match .. "}"
        end

        local name = itemName:lower()
        local color
        if name:find('unidentified ', 1, true) then color = '#ff3030'
        elseif name:find('world ending ', 1, true) then color = '#ff3030'
        elseif name:find('mythical ', 1, true) then color = '#35ded2'
        elseif name:find('legendary ', 1, true) then color = '#ffd700'
        elseif name:find('epic ', 1, true) then color = '#b34dff'
        elseif name:find('rare ', 1, true) then color = '#3388ff'
        elseif name:find('common ', 1, true) then color = '#b1b1b1' end
        if color then return '{' .. itemName .. ', ' .. color .. '}' end

        local itemId = tonumber(id)
        if not itemId then
            return itemName or match
        end

        -- Consult seller data before the local DAT. The server loot id is valid
        -- even when an older DAT does not expose that historical client id.
        local itemInfo = getNpcSellValue(itemId)
        if not itemInfo or itemInfo <= 0 then
            local thingType = g_things.getThingType(itemId, ThingCategoryItem)
            itemInfo = thingType and thingType:getMeanPrice() or 0
        end
        if itemInfo then
            local color = ItemsDatabase.getColorForRarity(getColorForValue(itemInfo))
            return "{" .. itemName .. ", " .. color .. "}"
        else
            return itemName
        end
    end
    return text:gsub("{(.-)}", coloringLootName)
end

function ItemsDatabase.getTierClip(tier)
    local xOffset = (math.min(math.max(tier, 1), 10) - 1) * 9
    return {
        x = xOffset,
        y = 0,
        width = 10,
        height = 9
    }
end

function ItemsDatabase.setTier(widget, item, isSmall)
    if not g_game.getFeature(GameThingUpgradeClassification) or not widget or not widget.tier then
        return
    end
    if isSmall == nil then
        isSmall = true
    end
    local tier = type(item) == "number" and item or (item and item:getTier()) or 0
    if tier <= 0 then
        widget.tier:setVisible(false)
        return
    end
    local config
    if isSmall then
        local normalizedTier = math.min(math.max(tier, 1), 10)
        config = {
            xOffset = (normalizedTier - 1) * 9,
            width = 10,
            height = 9,
            size = "10 9",
            source = '/images/inventory/tiers-strip'
        }
    else
        local normalizedTier = math.min(math.max(tier, 1), 18)
        local xOffset = (normalizedTier - 1) * 18 + 1
        config = {
            xOffset = xOffset,
            width = 18,
            height = 16,
            size = "18 16",
            source = '/images/inventory/tiers-strip-big'
        }
    end

    widget.tier:setImageClip({
        x = config.xOffset,
        y = 0,
        width = config.width,
        height = config.height
    })
    widget.tier:setSize(config.size)
    widget.tier:setImageSource(config.source)
    widget.tier:setImageSize(config.size)
    widget.tier:setVisible(true)
end


