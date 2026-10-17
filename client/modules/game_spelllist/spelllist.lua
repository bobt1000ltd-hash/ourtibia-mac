local SpelllistProfile = 'Default'

spelllistWindow = nil
spelllistButton = nil
spellList = nil
nameValueLabel = nil
formulaValueLabel = nil
vocationValueLabel = nil
groupValueLabel = nil
typeValueLabel = nil
cooldownValueLabel = nil
levelValueLabel = nil
manaValueLabel = nil
premiumValueLabel = nil
descriptionValueLabel = nil

vocationBoxAny = nil
vocationBoxSorcerer = nil
vocationBoxDruid = nil
vocationBoxPaladin = nil
vocationBoxKnight = nil
vocationBoxMonk = nil

groupBoxAny = nil
groupBoxAttack = nil
groupBoxHealing = nil
groupBoxSupport = nil

premiumBoxAny = nil
premiumBoxNo = nil
premiumBoxYes = nil

vocationRadioGroup = nil
groupRadioGroup = nil
premiumRadioGroup = nil

-- consts
FILTER_PREMIUM_ANY = 0
FILTER_PREMIUM_NO = 1
FILTER_PREMIUM_YES = 2

FILTER_VOCATION_ANY = 0
FILTER_VOCATION_SORCERER = 1
FILTER_VOCATION_DRUID = 2
FILTER_VOCATION_PALADIN = 3
FILTER_VOCATION_KNIGHT = 4
FILTER_VOCATION_MONK = 5

FILTER_GROUP_ANY = 0
FILTER_GROUP_ATTACK = 1
FILTER_GROUP_HEALING = 2
FILTER_GROUP_SUPPORT = 3

-- Filter Settings
local filters = {
    level = false,
    vocation = false,

    vocationId = FILTER_VOCATION_ANY,
    premium = FILTER_PREMIUM_ANY,
    groupId = FILTER_GROUP_ANY
}

function getSpelllistProfile()
    return SpelllistProfile
end

function setSpelllistProfile(name)
    if SpelllistProfile == name then
        return
    end

    if SpelllistSettings[name] and SpellInfo[name] then
        local oldProfile = SpelllistProfile
        SpelllistProfile = name
        changeSpelllistProfile(oldProfile)
    else
        perror('Spelllist profile \'' .. name .. '\' could not be set.')
    end
end

function online()
    if not spelllistButton then
        spelllistButton = modules.game_mainpanel.addToggleButton('spelllistButton', tr('Spell List'),
        '/images/options/button_spells', toggle, false, 4)
        spelllistButton:setOn(false)
    end

    -- Vocation is only send in newer clients
    if g_game.getClientVersion() >= 950 then
        spelllistWindow:getChildById('buttonFilterVocation'):setVisible(true)
    else
        spelllistWindow:getChildById('buttonFilterVocation'):setVisible(false)
    end
end

function offline()
    resetWindow()
end

function init()
    connect(g_game, {
        onGameStart = online,
        onGameEnd = offline
    })

    spelllistWindow = g_ui.displayUI('spelllist', modules.game_interface.getRightPanel())
    spelllistWindow:hide()

    nameValueLabel = spelllistWindow:getChildById('labelNameValue')
    formulaValueLabel = spelllistWindow:getChildById('labelFormulaValue')
    vocationValueLabel = spelllistWindow:getChildById('labelVocationValue')
    groupValueLabel = spelllistWindow:getChildById('labelGroupValue')
    typeValueLabel = spelllistWindow:getChildById('labelTypeValue')
    cooldownValueLabel = spelllistWindow:getChildById('labelCooldownValue')
    levelValueLabel = spelllistWindow:getChildById('labelLevelValue')
    manaValueLabel = spelllistWindow:getChildById('labelManaValue')
    premiumValueLabel = spelllistWindow:getChildById('labelPremiumValue')
    descriptionValueLabel = spelllistWindow:getChildById('labelDescriptionValue')

    vocationBoxAny = spelllistWindow:getChildById('vocationBoxAny')
    vocationBoxSorcerer = spelllistWindow:getChildById('vocationBoxSorcerer')
    vocationBoxDruid = spelllistWindow:getChildById('vocationBoxDruid')
    vocationBoxPaladin = spelllistWindow:getChildById('vocationBoxPaladin')
    vocationBoxKnight = spelllistWindow:getChildById('vocationBoxKnight')
    vocationBoxMonk = spelllistWindow:getChildById('vocationBoxMonk')
    -- 17.10.2026 (owner): the Monk box is used for spells without a vocation (Rookgaard)
    vocationBoxMonk:setText(tr('None'));vocationBoxMonk:show();vocationBoxMonk:setEnabled(true)

    groupBoxAny = spelllistWindow:getChildById('groupBoxAny')
    groupBoxAttack = spelllistWindow:getChildById('groupBoxAttack')
    groupBoxHealing = spelllistWindow:getChildById('groupBoxHealing')
    groupBoxSupport = spelllistWindow:getChildById('groupBoxSupport')

    premiumBoxAny = spelllistWindow:getChildById('premiumBoxAny')
    premiumBoxYes = spelllistWindow:getChildById('premiumBoxYes')
    premiumBoxNo = spelllistWindow:getChildById('premiumBoxNo')

    vocationRadioGroup = UIRadioGroup.create()
    vocationRadioGroup:addWidget(vocationBoxAny)
    vocationRadioGroup:addWidget(vocationBoxSorcerer)
    vocationRadioGroup:addWidget(vocationBoxDruid)
    vocationRadioGroup:addWidget(vocationBoxPaladin)
    vocationRadioGroup:addWidget(vocationBoxKnight)
    vocationRadioGroup:addWidget(vocationBoxMonk)

    groupRadioGroup = UIRadioGroup.create()
    groupRadioGroup:addWidget(groupBoxAny)
    groupRadioGroup:addWidget(groupBoxAttack)
    groupRadioGroup:addWidget(groupBoxHealing)
    groupRadioGroup:addWidget(groupBoxSupport)

    premiumRadioGroup = UIRadioGroup.create()
    premiumRadioGroup:addWidget(premiumBoxAny)
    premiumRadioGroup:addWidget(premiumBoxYes)
    premiumRadioGroup:addWidget(premiumBoxNo)

    premiumRadioGroup:selectWidget(premiumBoxAny)
    vocationRadioGroup:selectWidget(vocationBoxAny)
    groupRadioGroup:selectWidget(groupBoxAny)

    vocationRadioGroup.onSelectionChange = toggleFilter
    groupRadioGroup.onSelectionChange = toggleFilter
    premiumRadioGroup.onSelectionChange = toggleFilter

    spellList = spelllistWindow:getChildById('spellList')

    g_keyboard.bindKeyPress('Down', function()
        spellList:focusNextChild(KeyboardFocusReason)
    end, spelllistWindow)
    g_keyboard.bindKeyPress('Up', function()
        spellList:focusPreviousChild(KeyboardFocusReason)
    end, spelllistWindow)

    -- 11.10.2026: Escape closes the window also when the focus is on the game screen
    g_keyboard.bindKeyDown('Escape', escapeClose, spelllistWindow)
    escapeRoot = modules.game_interface.getRootPanel and modules.game_interface.getRootPanel()
    if escapeRoot then
        g_keyboard.bindKeyDown('Escape', escapeClose, escapeRoot)
    end

    initializeSpelllist()
    resizeWindow()

    if g_game.isOnline() then
        online()
    end
    Keybind.new("Windows", "Show/hide spell list", "Alt+L", "")
    Keybind.bind("Windows", "Show/hide spell list", {
      {
        type = KEY_DOWN,
        callback = toggle,
      }
    })
end

function terminate()
    disconnect(g_game, {
        onGameStart = online,
        onGameEnd = offline
    })

    pcall(g_keyboard.unbindKeyDown, 'Escape', escapeClose, spelllistWindow)
    if escapeRoot then
        pcall(g_keyboard.unbindKeyDown, 'Escape', escapeClose, escapeRoot)
        escapeRoot = nil
    end
    spelllistWindow:destroy()
    if spelllistButton then
        spelllistButton:destroy()
        spelllistButton = nil
    end
    vocationRadioGroup:destroy()
    groupRadioGroup:destroy()
    premiumRadioGroup:destroy()
    Keybind.delete("Windows", "Show/hide spell list")
end

function initializeSpelllist()
    local spells = {}
    for spellName, info in pairs(SpellInfo[SpelllistProfile]) do
        table.insert(spells, spellName)
    end
    table.sort(spells)
    for _, spellName in ipairs(spells) do
        local info = SpellInfo[SpelllistProfile][spellName]
        if info then
            local tmpLabel = g_ui.createWidget('SpellListLabel', spellList)
            tmpLabel:setId(spellName)
            tmpLabel:setText(spellName .. '\n\'' .. info.words .. '\'')
            tmpLabel:setPhantom(false)

            local iconId = tonumber(info.clientId)
            if not iconId then
                perror('Spell icon \'' .. info.icon .. '\' not found.')
            end

            tmpLabel:setHeight(SpelllistSettings[SpelllistProfile].iconSize.height + 4)
            tmpLabel:setTextOffset(topoint((SpelllistSettings[SpelllistProfile].iconSize.width + 10) .. ' ' ..
                                               (SpelllistSettings[SpelllistProfile].iconSize.height - 32) / 2 + 3))
            tmpLabel:setImageSource(SpelllistSettings[SpelllistProfile].iconFile)
            tmpLabel:setImageClip(Spells.getImageClip(iconId, SpelllistProfile))
            tmpLabel:setImageSize(tosize(SpelllistSettings[SpelllistProfile].iconSize.width .. ' ' ..
                                             SpelllistSettings[SpelllistProfile].iconSize.height))
            tmpLabel.onClick = updateSpellInformation
            setupSpellDrag(tmpLabel)
        end
    end

    connect(spellList, {
        onChildFocusChange = function(self, focusedChild)
            if focusedChild == nil then
                return
            end
            updateSpellInformation(focusedChild)
        end
    })
end

function changeSpelllistProfile(oldProfile)
    -- Delete old labels
    for spellName, info in pairs(SpellInfo[oldProfile]) do
        local tmpLabel = spellList:getChildById(spellName)

        tmpLabel:destroy()
    end

    -- Create new spelllist and ajust window
    initializeSpelllist()
    resizeWindow()
    resetWindow()
end

local function vocationMatches(vocations, filterId)
    if filterId == FILTER_VOCATION_ANY then
        return true
    end
    if filterId == FILTER_VOCATION_MONK then
        return table.find(vocations, 0) -- 17.10.2026: "None" (no vocation)
    end
    return table.find(vocations, filterId) or table.find(vocations, filterId + 4)
end

-- OurTibia (03.10.2026): the protocol sends the client vocation id (11 = Elite
-- Knight ...), the spell data uses server ids (8 = Elite Knight ...).
local CLIENT_TO_SERVER_VOC = {[1] = 4, [2] = 3, [3] = 1, [4] = 2, [11] = 8, [12] = 7, [13] = 5, [14] = 6}
function serverVocation(id) return CLIENT_TO_SERVER_VOC[id] or id end

function updateSpelllist()
    if not spellList or not SpellInfo or not SpellInfo[SpelllistProfile] then return end
    -- 14.10.2026 (Tobeto): search box above the list (name or words)
    local searchBox = spelllistWindow and spelllistWindow:getChildById('spellSearch')
    local query = searchBox and searchBox:getText():lower() or ''
    for spellName, info in pairs(SpellInfo[SpelllistProfile]) do
        local tmpLabel = spellList:getChildById(spellName)
        local localPlayer = g_game.getLocalPlayer()
        local found = query == '' or spellName:lower():find(query, 1, true) or (info.words and info.words:lower():find(query, 1, true))
        if not tmpLabel or not localPlayer then
        elseif found and (not (filters.level) or (info.maglevel or 0) <= localPlayer:getMagicLevel()) and
            (not (filters.vocation) or table.find(info.vocations, serverVocation(localPlayer:getVocation()))) and
            (filters.vocationId == FILTER_VOCATION_ANY or vocationMatches(info.vocations, filters.vocationId)) and
            (filters.groupId == FILTER_GROUP_ANY or info.group[filters.groupId]) and
            (filters.premium == FILTER_PREMIUM_ANY or (info.premium and filters.premium == FILTER_PREMIUM_YES) or
                (not (info.premium) and filters.premium == FILTER_PREMIUM_NO)) then
            tmpLabel:setVisible(true)
        else
            tmpLabel:setVisible(false)
        end
    end
end

function updateSpellInformation(widget)
    local spell = widget:getId()

    local name = ''
    local formula = ''
    local vocation = ''
    local group = ''
    local type = ''
    local cooldown = ''
    local level = ''
    local mana = ''
    local premium = ''
    local description = ''

    if SpellInfo[SpelllistProfile][spell] then
        local info = SpellInfo[SpelllistProfile][spell]

        name = spell
        formula = info.words .. (info.parameterText and info.parameterText ~= '' and (' ' .. info.parameterText) or '')

        for i = 1, #info.vocations do
            local vocationId = info.vocations[i]
            if vocationId <= 4 or not (table.find(info.vocations, (vocationId - 4))) then
                vocation = vocation .. (vocation:len() == 0 and '' or ', ') .. VocationNames[vocationId]
            end
        end

        -- 15.10.2026 (Tobeto): the details fit the compact window - all four vocations
        -- are "All", three or more use short names
        local count = select(2, vocation:gsub(',', ',')) + (vocation ~= '' and 1 or 0)
        if count >= 4 then vocation = table.find(info.vocations, 0) and 'All + no vocation' or 'All vocations'
        elseif #vocation > 22 then
            for long, short in pairs({['Master Sorcerer'] = 'MS', ['Elder Druid'] = 'ED', ['Royal Paladin'] = 'RP', ['Elite Knight'] = 'EK'}) do
                vocation = vocation:gsub(long, short)
            end
            if #vocation > 22 then
                vocation = vocation:gsub('Sorcerer', 'Sorc.'):gsub('Paladin', 'Pal.'):gsub('Knight', 'Kn.')
            end
        end

        cooldown = (info.exhaustion / 1000) .. 's'
        for groupId, groupName in ipairs(SpellGroups) do
            if info.group[groupId] then
                group = group .. (group:len() == 0 and '' or ' / ') .. groupName
                cooldown = cooldown .. ' / ' .. (info.group[groupId] / 1000) .. 's'
            end
        end

        type = info.type
        level = tostring(info.maglevel or 0)
        mana = info.mana .. ' / ' .. info.soul
        premium = (info.premium and 'yes' or 'no')
        description = info.description or '-'
    end

    nameValueLabel:setText(name)
    formulaValueLabel:setText(formula)
    vocationValueLabel:setText(vocation)
    groupValueLabel:setText(group)
    typeValueLabel:setText(type)
    cooldownValueLabel:setText(cooldown)
    levelValueLabel:setText(level)
    manaValueLabel:setText(mana)
    premiumValueLabel:setText(premium)
    descriptionValueLabel:setText(description)
end

function selectDefaultVocation()
    local player = g_game.getLocalPlayer()
    if not player then 
        return
    end
    local vocation = player:getVocation()
    local widget = vocationBoxAny
    if vocation == VocationsClient.Knight or vocation == VocationsClient.EliteKnight then
        widget = vocationBoxKnight
    elseif vocation == VocationsClient.Paladin or vocation == VocationsClient.RoyalPaladin then
        widget = vocationBoxPaladin
    elseif vocation == VocationsClient.Sorcerer or vocation == VocationsClient.MasterSorcerer then
        widget= vocationBoxSorcerer
    elseif vocation == VocationsClient.Druid or vocation == VocationsClient.ElderDruid then
        widget = vocationBoxDruid
    elseif vocation == VocationsClient.Monk or vocation == VocationsClient.ExaltedMonk then
        widget = vocationBoxMonk
    end
    vocationRadioGroup:selectWidget(widget)
end

function toggle()
    if spelllistWindow:isVisible() then
        hideSpelllist()
    else
        showSpelllist()
    end
end

function toggleFilter(widget, selectedWidget)
    if widget == vocationRadioGroup then
        local boxId = selectedWidget:getId()
        if boxId == 'vocationBoxAny' then
            filters.vocationId = FILTER_VOCATION_ANY
        elseif boxId == 'vocationBoxSorcerer' then
            filters.vocationId = FILTER_VOCATION_SORCERER
        elseif boxId == 'vocationBoxDruid' then
            filters.vocationId = FILTER_VOCATION_DRUID
        elseif boxId == 'vocationBoxPaladin' then
            filters.vocationId = FILTER_VOCATION_PALADIN
        elseif boxId == 'vocationBoxKnight' then
            filters.vocationId = FILTER_VOCATION_KNIGHT
        elseif boxId == 'vocationBoxMonk' then
            filters.vocationId = FILTER_VOCATION_MONK
        end
    elseif widget == groupRadioGroup then
        local boxId = selectedWidget:getId()
        if boxId == 'groupBoxAny' then
            filters.groupId = FILTER_GROUP_ANY
        elseif boxId == 'groupBoxAttack' then
            filters.groupId = FILTER_GROUP_ATTACK
        elseif boxId == 'groupBoxHealing' then
            filters.groupId = FILTER_GROUP_HEALING
        elseif boxId == 'groupBoxSupport' then
            filters.groupId = FILTER_GROUP_SUPPORT
        end
    elseif widget == premiumRadioGroup then
        local boxId = selectedWidget:getId()
        if boxId == 'premiumBoxAny' then
            filters.premium = FILTER_PREMIUM_ANY
        elseif boxId == 'premiumBoxNo' then
            filters.premium = FILTER_PREMIUM_NO
        elseif boxId == 'premiumBoxYes' then
            filters.premium = FILTER_PREMIUM_YES
        end
    else
        local id = widget:getId()
        if id == 'buttonFilterLevel' then
            filters.level = not (filters.level)
            widget:setOn(filters.level)
        elseif id == 'buttonFilterVocation' then
            filters.vocation = not (filters.vocation)
            widget:setOn(filters.vocation)
        end
    end

    updateSpelllist()
end

function resizeWindow()
    -- 15.10.2026 (Tobeto): compact window (470 px) instead of 550
    spelllistWindow:setWidth(470 + SpelllistSettings[SpelllistProfile].iconSize.width - 32)
    spellList:setWidth(
        SpelllistSettings['Default'].spellListWidth + SpelllistSettings[SpelllistProfile].iconSize.width - 32)
end

function resetWindow()
    hideSpelllist()
    if spelllistButton then
        spelllistButton:setOn(false)
    end

    -- Resetting filters
    filters.level = false
    filters.vocation = false

    local buttonFilterLevel = spelllistWindow:getChildById('buttonFilterLevel')
    buttonFilterLevel:setOn(filters.level)

    local buttonFilterVocation = spelllistWindow:getChildById('buttonFilterVocation')
    buttonFilterVocation:setOn(filters.vocation)

    vocationRadioGroup:selectWidget(vocationBoxAny)
    groupRadioGroup:selectWidget(groupBoxAny)
    premiumRadioGroup:selectWidget(premiumBoxAny)

    updateSpelllist()
end


-- =============================================
-- 11.10.2026 (Tobeto): Escape, drag & drop to the action bar,
-- "Assign Spell" pick mode
-- =============================================
local pickCallback = nil
escapeRoot = nil

local function setPickMode(on, title)
    local assignButton = spelllistWindow:getChildById('buttonAssign')
    local param = spelllistWindow:getChildById('pickParam')
    if assignButton then assignButton:setVisible(on) end
    -- 15.10.2026 (Tobeto): no "Parameter (name)" box in the Assign Spell window
    if param then
        param:setVisible(false)
        param:clearText()
    end
    spelllistWindow:setText(on and (title or tr('Assign Spell')) or tr('Spell List'))
end

function showSpelllist()
    if spelllistButton then spelllistButton:setOn(true) end
    selectDefaultVocation()
    spelllistWindow:show()
    spelllistWindow:raise()
    spelllistWindow:focus()
end

function hideSpelllist()
    if spelllistButton then spelllistButton:setOn(false) end
    spelllistWindow:hide()
    if pickCallback then
        pickCallback = nil
        setPickMode(false)
    end
end

function escapeClose()
    if spelllistWindow and spelllistWindow:isVisible() then
        hideSpelllist()
        return true
    end
    return false
end

local function spellWordsFor(widget, param)
    local info = widget and SpellInfo[SpelllistProfile][widget:getId()]
    if not info or not info.words then return nil end
    local words = info.words
    if info.parameter and param and param ~= '' then
        words = words .. ' "' .. param:gsub('"', '') .. '"'
    end
    return words
end

function assignPicked(widget)
    if not pickCallback then return end
    widget = widget or spellList:getFocusedChild()
    local param = spelllistWindow:getChildById('pickParam')
    local words = spellWordsFor(widget, param and param:getText() or '')
    if not words then
        modules.game_textmessage.displayFailureMessage(tr('Select a spell first.'))
        return
    end
    local callback = pickCallback
    hideSpelllist()
    callback(words)
end

function openForAssign(title, callback)
    pickCallback = callback
    setPickMode(true, title)
    showSpelllist()
end

function setupSpellDrag(label)
    label:setDraggable(true)
    label.onDragEnter = function(self, mousePos)
        g_mouse.pushCursor('target')
        return true
    end
    label.onDragLeave = function(self, droppedWidget, mousePos)
        g_mouse.popCursor('target')
        local actionbar = modules.game_actionbar
        local words = spellWordsFor(self)
        if words and actionbar and actionbar.assignSpellWordsAt then
            actionbar.assignSpellWordsAt(mousePos, words)
        end
        return true
    end
    label.onDoubleClick = function(self)
        if pickCallback then
            assignPicked(self)
            return true
        end
    end
end
