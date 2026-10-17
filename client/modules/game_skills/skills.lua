local myotsAttributesShown=false
skillController = Controller:new()

skillsWindow = nil
skillsButton = nil
skillsSettings = nil
local ExpRating = {}
local smallSkillsCache = {}

-- Cache for stats data when UI elements are hidden
local statsCache = {
    flatDamageHealing = 0,
    attackValue = 0,
    attackElement = 0,
    convertedDamage = 0,
    convertedElement = 0,
    lifeLeech = 0,
    manaLeech = 0,
    critChance = 0,
    critDamage = 0,
    onslaught = 0,
    defense = 0,
    armor = 0,
    mantra = 0,
    mitigation = 0,
    dodge = 0,
    damageReflection = 0,
    combatAbsorbValues = {
        [0] = 0, -- physicalResist
        [1] = 0, -- fireResist
        [2] = 0, -- earthResist
        [3] = 0, -- energyResist
        [4] = 0, -- IceResist
        [5] = 0, -- HolyResist
        [6] = 0, -- deathResist
        [7] = 0, -- HealingResist
        [8] = 0, -- drowResist
        [9] = 0, -- lifedrainResist
        [10] = 0 -- manadRainResist
    },
    momentum = 0,
    transcendence = 0,
    amplification = 0
}

local function setupUIButtons()
    local toggleFilterButton = skillsWindow:recursiveGetChildById('toggleFilterButton')
    if toggleFilterButton then
        toggleFilterButton:setVisible(false)
        toggleFilterButton:setOn(false)
    end
    
    local contextMenuButton = skillsWindow:recursiveGetChildById('contextMenuButton')
    local minimizeButton = skillsWindow:recursiveGetChildById('minimizeButton')
    if contextMenuButton and minimizeButton then
        contextMenuButton:addAnchor(AnchorTop, minimizeButton:getId(), AnchorTop)
        contextMenuButton:addAnchor(AnchorRight, minimizeButton:getId(), AnchorLeft)
        contextMenuButton:setMarginRight(7)
        contextMenuButton.onClick = function(widget, mousePos, mouseButton)
            return showSkillsContextMenu(widget, mousePos, mouseButton)
        end
    end
    
    local newWindowButton = skillsWindow:recursiveGetChildById('newWindowButton')
    if newWindowButton then
        newWindowButton.onClick = function()
            if modules.game_cyclopedia then
                modules.game_cyclopedia.show("character")
            end
        end
    end
end

function skillController:onInit()
    skillController:registerEvents(LocalPlayer, {
        onExperienceChange = onExperienceChange,
        onLevelChange = onLevelChange,
        onHealthChange = onHealthChange,
        onManaChange = onManaChange,
        onSoulChange = onSoulChange,
        onFreeCapacityChange = onFreeCapacityChange,
        onTotalCapacityChange = onTotalCapacityChange,
        onBaseCapacityChange = onBaseCapacityChange,
        onStaminaChange = onStaminaChange,
        onOfflineTrainingChange = onOfflineTrainingChange,
        onRegenerationChange = onRegenerationChange,
        onSpeedChange = onSpeedChange,
        onBaseSpeedChange = onBaseSpeedChange,
        onStatesChange = onOurStatesChange,
        onMagicLevelChange = onMagicLevelChange,
        onBaseMagicLevelChange = onBaseMagicLevelChange,
        onSkillChange = onSkillChange,
        onBaseSkillChange = onBaseSkillChange,
        -- 14.12
        onFlatDamageHealingChange = onFlatDamageHealingChange,
        onAttackInfoChange = onAttackInfoChange,
        onConvertedDamageChange = onConvertedDamageChange,
        onImbuementsChange = onImbuementsChange,
        onDefenseInfoChange = onDefenseInfoChange,
        onCombatAbsorbValuesChange = onCombatAbsorbValuesChange,
        onForgeBonusesChange = onForgeBonusesChange,
        onExperienceRateChange = onExperienceRateChange,
        -- 15.24
        onMultiOfflineTrainingDialog = onMultiOfflineTrainingDialog
    })
    skillsButton = modules.game_mainpanel.addToggleButton('skillsButton', tr('Skills') .. ' (Alt+S)',
                                                                   '/images/options/button_skills', toggle, false, 1)
    skillsButton:setOn(true)
    skillsWindow = g_ui.loadUI('skills')
    skillsWindow:setContentMinimumHeight(80)

    Keybind.new("Windows", "Show/hide skills windows", "Alt+S", "")
    Keybind.bind("Windows", "Show/hide skills windows", {
      {
        type = KEY_DOWN,
        callback = toggle,
      }
    })

    skillSettings = g_settings.getNode('skills-hide')
    if not skillSettings then
        skillSettings = {}
    end

    ProtocolGame.registerExtendedOpcode(101, function(protocol, opcode, buffer) myotsStats(buffer) end)
    ProtocolGame.registerExtendedJSONOpcode(108, function(protocol, opcode, rows)
        if type(rows) == 'table' then myotsAttributes(rows) end
    end)
    setupUIButtons()
    pcall(ourPinTabs)
    skillsWindow:setup()
end

-- 16.10.2026 (Tobeto): "Skills" / "Attributes" and "Only non-zero values" stay at the top,
-- only the rows scroll
function ourPinTabs()
    local tabs = skillsWindow:recursiveGetChildById('myotsTabs')
    local contents = skillsWindow:getChildById('contentsPanel')
    if not tabs or not contents then return end
    tabs:setParent(skillsWindow); tabs:breakAnchors()
    tabs:addAnchor(AnchorTop, 'miniwindowHeader', AnchorBottom)
    tabs:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    tabs:addAnchor(AnchorRight, 'miniwindowScrollBar', AnchorLeft)
    tabs:setMarginTop(3); tabs:setMarginLeft(8); tabs:setMarginRight(6)
    local nz = g_ui.createWidget('CheckBox', skillsWindow)
    nz:setId('myotsNonZero'); nz:setText('Only non-zero values'); nz:setHeight(18); nz:setColor('#c0c0c0')
    nz:setFocusable(false); nz:setTooltip('Hide the attributes you do not have (value 0).')
    nz:addAnchor(AnchorTop, 'myotsTabs', AnchorBottom)
    nz:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    nz:addAnchor(AnchorRight, 'miniwindowScrollBar', AnchorLeft)
    nz:setMarginLeft(8); nz:setMarginRight(6)
    nz:hide()
    -- 17.10.2026 (Tobeto): the line under the fixed elements does not scroll either
    local line = g_ui.createWidget('HorizontalSeparator', skillsWindow)
    line:setId('myotsStaticLine')
    line:addAnchor(AnchorTop, 'myotsNonZero', AnchorBottom)
    line:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    line:addAnchor(AnchorRight, 'miniwindowScrollBar', AnchorLeft)
    line:setMarginLeft(8); line:setMarginRight(6); line:setMarginTop(3)
    line:hide()
    ourTabsOffset()
end
function ourTabsOffset()
    local contents = skillsWindow and skillsWindow:getChildById('contentsPanel')
    local nz = skillsWindow and skillsWindow:getChildById('myotsNonZero')
    if not contents then return end
    contents:setMarginTop(3 + 20 + 3 + ((nz and nz:isVisible()) and (18 + 6) or 0))
end

function skillController:onTerminate()
    ProtocolGame.unregisterExtendedOpcode(101)
    ProtocolGame.unregisterExtendedJSONOpcode(108)
    Keybind.delete("Windows", "Show/hide skills windows")
    skillsWindow:destroy()
    skillsButton:destroy()

    skillsWindow = nil
    skillsButton = nil
end

local SKILL_GROUPS = {
    offence = {
        'damageHealing', 'attackValue', 'convertedDamage', 'convertedElement',
        'lifeLeech', 'manaLeech', 'criticalChance', 'criticalExtraDamage', 'onslaught'
    },
    defence = {
        'physicalResist', 'fireResist', 'earthResist', 'energyResist', 'IceResist', 
        'HolyResist', 'deathResist', 'HealingResist', 'drowResist', 'lifedrainResist', 
        'manadRainResist', 'defenceValue', 'armorValue', 'mantraValue', 'mitigation', 'dodge', 
        'damageReflection'
    },
    misc = {
        'momentum', 'transcendence', 'amplification'
    },
    individual = {
        'level', 'regenerationTime', 'stamina', 'offlineTraining', 'magiclevel', 'skillId0', 
        'skillId2', 'skillId4', 'skillId5', 'skillId6'
    },
    GameAdditionalSkills = {
        'skillId7', 'skillId8', 'skillId9', 'skillId10', 'skillId11', 'skillId12'
    },
    GameForgeSkillStats = {
        'skillId13', 'skillId14', 'skillId15'
    },
    GameForgeSkillStats1332 = {
        'skillId16'
    }
}

local function setSkillGroupVisibility(groupName, visible)
    local skills = SKILL_GROUPS[groupName]
    if not skills then return end

    for _, skillId in pairs(skills) do
        local skill = skillsWindow:recursiveGetChildById(skillId)
        if skill then
            if visible then
                local valueWidget = skill:getChildById('value')
                local text = valueWidget and valueWidget:getText() or ""
                if g_game.getClientVersion() >= 1410 then
                    skill:setVisible(text ~= "" and text ~= "0" and text ~= "0%" and
                        text ~= "+ 0%" and text ~= "0.0%" and text ~= "+ 0.0%")
                else
                    skill:setVisible(true)
                end
            else
                skill:setVisible(false)
            end
        end
    end

    if groupName == 'offence' then
        local criticalHitWidget = skillsWindow:recursiveGetChildById('criticalHit')
        if criticalHitWidget then
            local hasCritValue = math.abs(statsCache.critChance or 0) > 0.0001 or
                                 math.abs(statsCache.critDamage or 0) > 0.0001
            criticalHitWidget:setVisible(visible and hasCritValue)
        end
    end
end

local function areStatsVisible(groupName)
    if g_game.getClientVersion() < 1412 and groupName ~= 'individual' then
        return false
    end
    
    local skills = SKILL_GROUPS[groupName]
    if not skills then 
        return false
    end
    
    for _, skillId in pairs(skills) do
        local skill = skillsWindow:recursiveGetChildById(skillId)
        if skill and skill:isVisible() then
            return true
        end
    end
    return false
end

local function refreshGroupData(groupName)
    -- When stats are made visible, apply cached data to the UI elements
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end
    
    scheduleEvent(function()
        if groupName == 'offence' then
            -- Apply cached offence data
            onFlatDamageHealingChange(player, statsCache.flatDamageHealing)
            onAttackInfoChange(player, statsCache.attackValue, statsCache.attackElement)
            onConvertedDamageChange(player, statsCache.convertedDamage, statsCache.convertedElement)
            onImbuementsChange(player, statsCache.lifeLeech, statsCache.manaLeech, statsCache.critChance, statsCache.critDamage, statsCache.onslaught)
        elseif groupName == 'defence' then
            -- Apply cached defence data
            onDefenseInfoChange(player, statsCache.defense, statsCache.armor, statsCache.mantra, statsCache.mitigation, statsCache.dodge, statsCache.damageReflection)
            onCombatAbsorbValuesChange(player, statsCache.combatAbsorbValues)
        elseif groupName == 'misc' then
            -- Apply cached misc data
            onForgeBonusesChange(player, statsCache.momentum, statsCache.transcendence, statsCache.amplification)
        end
    end, 50)
end

local function toggleGroupVisibility(groupName)
    if g_game.getClientVersion() < 1412 and groupName ~= 'individual' then
        return
    end
    
    local shouldShow = not areStatsVisible(groupName)
    setSkillGroupVisibility(groupName, shouldShow)
    
    -- If we're showing stats, refresh the data
    if shouldShow then
        refreshGroupData(groupName)
    end
    
    local char = g_game.getCharacterName()
    if not skillSettings[char] then
        skillSettings[char] = {}
    end
    skillSettings[char][groupName .. 'Stats_visible'] = shouldShow
    g_settings.setNode('skills-hide', skillSettings)
end

local function hideOldClientStats()
    local features = {
        newAppearance = g_game.getFeature(GameEnterGameShowAppearance),
        charSkills = g_game.getFeature(GameCharacterSkillStats),
        additionalSkills = g_game.getFeature(GameAdditionalSkills),
        forgeSkills = g_game.getFeature(GameForgeSkillStats)
    }
    if features.newAppearance then
        skillsWindow:recursiveGetChildById('regenerationTime'):getChildByIndex(1):setText('Fullness')
        skillsWindow:recursiveGetChildById('experience'):getChildByIndex(1):setText('XP')
    end
    local version = g_game.getClientVersion()
    setSkillGroupVisibility('offence', features.charSkills)
    setSkillGroupVisibility('defence', features.charSkills)
    setSkillGroupVisibility('misc', features.charSkills)
    setSkillGroupVisibility('GameAdditionalSkills', features.additionalSkills)
    setSkillGroupVisibility('GameForgeSkillStats1332', features.forgeSkills and version >= 1332)
    setSkillGroupVisibility('GameForgeSkillStats', features.forgeSkills)
end

local function hideMenuOptionsForOldClients(menu)
    if not g_game.getFeature(GameOfflineTrainingTime) then
        local offlineTrainingOption = menu:getChildById('showOfflineTraining')
        if offlineTrainingOption then
            offlineTrainingOption:setVisible(false)
        end
    end
    
    if g_game.getClientVersion() < 1412 then
        local statsOptions = {'showOffenceStats', 'showDefenceStats', 'showMiscStats'}
        for _, optionId in pairs(statsOptions) do
            local option = menu:getChildById(optionId)
            if option then
                option:setVisible(false)
            end
        end
    end
end

function showSkillsContextMenu(widget, mousePos, mouseButton)
    local menu = g_ui.createWidget('SkillsListSubMenu')
    menu:setGameMenu(true)

    hideMenuOptionsForOldClients(menu)

    for _, choice in ipairs(menu:getChildren()) do
        local choiceId = choice:getId()
        if choiceId and choiceId ~= 'HorizontalSeparator' then
            if choiceId == 'resetExperienceCounter' then
                choice.onClick = function()
                    onSkillsMenuAction(choiceId)
                    menu:destroy()
                end
            else
                local currentState = getSkillVisibilityState(choiceId)
                choice:setChecked(currentState)
                choice.onCheckChange = function()
                    onSkillsMenuAction(choiceId)
                    menu:destroy()
                end
            end
        end
    end
    
    local buttonPos = widget:getPosition()
    local buttonSize = widget:getSize()
    local menuWidth = menu:getWidth()
    
    local buttonCenterX = buttonPos.x + buttonSize.width / 2
    local buttonCenterY = buttonPos.y + buttonSize.height / 2
    
    local menuX = buttonCenterX - menuWidth
    local menuY = buttonCenterY
    
    menu:display({x = menuX, y = menuY})
    return true
end

-- 13.10.2026 (Tobeto): rows that can be hidden completely from the skills panel
-- 14.10.2026 (Tobeto): HP / MP regen and speed moved to the Attributes tab
local OUR_ROWS = {rowLevel = {'level'}, rowStamina = {'stamina'}, -- 14.10.2026 (Tobeto): every position in one list
    rowExperience = {'experience', 'xpGainRate'}, rowHealth = {'health'}, rowMana = {'mana'},
    rowSoul = {'soul'}, rowCapacity = {'capacity'}, rowRegenTime = {'regenerationTime'},
    -- 13.10.2026 (Tobeto): skills and offline training can be hidden completely too
    rowOfflineTraining = {'offlineTraining'}, rowMagic = {'magiclevel'}, rowFist = {'skillId0'},
    rowMelee = {'skillId2'}, rowDistance = {'skillId4'}, rowShielding = {'skillId5'}, rowFishing = {'skillId6'}, rowCooking = {'skillCooking'}}
-- 15.10.2026 (Tobeto): Hit Points, Mana, Soul Points and Capacity moved to the Attributes tab
local OUR_MOVED = {'health', 'mana', 'soul', 'capacity'}
function ourApplyRowHides()
    if not skillsWindow or not g_game.isOnline() then return end
    for _, id in ipairs(OUR_MOVED) do
        local w = skillsWindow:recursiveGetChildById(id)
        if w then w:setVisible(false); w.myotsPreviousVisible = nil end
    end
    local char = g_game.getCharacterName()
    local set = skillSettings and skillSettings[char] or {}
    for opt, ids in pairs(OUR_ROWS) do
        for _, id in ipairs(ids) do
            local w = skillsWindow:recursiveGetChildById(id)
            if w and set['row_' .. opt] == false then w:setVisible(false)
            elseif w and set[id] == 1 and w:getChildById('percent') then
                -- 14.10.2026 (Tobeto): "progress bars only" is gone - bars hidden with it come back
                set[id] = 0; pcall(showPercentBar, w, true)
            end
        end
    end
end
local function ourToggleRow(opt)
    local char = g_game.getCharacterName(); if not char then return end
    skillSettings[char] = skillSettings[char] or {}
    local hidden = skillSettings[char]['row_' .. opt] == false
    skillSettings[char]['row_' .. opt] = hidden and true or false
    g_settings.setNode('skills-hide', skillSettings)
    -- 14.10.2026 (Tobeto): showing a row again also brings back its progress bar
    -- (a row could stay invisible: Melee Fighting could not be turned on again)
    if hidden then skillSettings[char]['row_' .. opt] = nil end
    for _, id in ipairs(OUR_ROWS[opt]) do
        local w = skillsWindow:recursiveGetChildById(id)
        if w then
            w:setVisible(hidden)
            if hidden and w:getChildById('percent') and skillSettings[char][id] == 1 then
                skillSettings[char][id] = 0; showPercentBar(w, true)
            end
        end
    end
    g_settings.setNode('skills-hide', skillSettings)
    if hidden then pcall(refresh) end
    ourApplyRowHides(); pcall(updateHeight)
end

-- 13.10.2026 (Tobeto): after any option the window keeps fitting its rows - a window
-- stretched to the full height stays full (it was shrunk and cut the bottom rows)
local function ourRefit(wasAtMax)
    pcall(updateHeight)
    local max = skillsWindow:getMaximumHeight()
    if max and max > 0 and (wasAtMax or skillsWindow:getHeight() > max) then skillsWindow:setHeight(max) end
end
function onSkillsMenuAction(actionId)
    local max = skillsWindow:getMaximumHeight()
    local wasAtMax = max and max > 0 and skillsWindow:getHeight() >= max - 1
    ourSkillsMenuAction(actionId)
    ourRefit(wasAtMax)
end
function ourSkillsMenuAction(actionId)
    if OUR_ROWS[actionId] then return ourToggleRow(actionId) end
    if actionId == 'resetExperienceCounter' then
        resetExperienceCounter()
    elseif actionId == 'showOffenceStats' then
        toggleGroupVisibility('offence')
    elseif actionId == 'showDefenceStats' then
        toggleGroupVisibility('defence')
    elseif actionId == 'showMiscStats' then
        toggleGroupVisibility('misc')
    elseif actionId == 'showAllSkillBars' then
        toggleAllSkillBars()
    else
        local skillMap = {
            showLevel = 'level',
            showFullness = 'regenerationTime',
            showStamina = 'stamina',
            showOfflineTraining = 'offlineTraining',
            showMagic = 'magiclevel',
            showFist = 'skillId0',
            showSword = 'skillId2',
            showDistance = 'skillId4',
            showShielding = 'skillId5',
            showFishing = 'skillId6'
        }
        local skillId = skillMap[actionId]
        if skillId then
            toggleSkillProgressBar(skillId)
        end
    end
end

function getSkillVisibilityState(actionId)
    local skillMap = {
        showLevel = 'level',
        showFullness = 'regenerationTime',
        showStamina = 'stamina',
        showOfflineTraining = 'offlineTraining',
        showMagic = 'magiclevel',
        showFist = 'skillId0',
        showSword = 'skillId2',
        showDistance = 'skillId4',
        showShielding = 'skillId5',
        showFishing = 'skillId6'
    }
    
    local groupMap = {
        showOffenceStats = 'offence',
        showDefenceStats = 'defence',
        showMiscStats = 'misc'
    }
    
    local skillId = skillMap[actionId]
    if skillId then
        return isSkillPercentBarVisible(skillId)
    end
    
    local groupName = groupMap[actionId]
    if groupName then
        return areStatsVisible(groupName)
    end
    
    if actionId == 'showAllSkillBars' then
        return areAllSkillBarsVisible()
    end
    if OUR_ROWS and OUR_ROWS[actionId] then
        local char = g_game.getCharacterName()
        return not (skillSettings and skillSettings[char] and skillSettings[char]['row_' .. actionId] == false)
    end
    
    return false
end

function isSkillVisible(skillId)
    local skill = skillsWindow:recursiveGetChildById(skillId)
    return skill and skill:isVisible()
end

function isSkillPercentBarVisible(skillId)
    local skill = skillsWindow:recursiveGetChildById(skillId)
    if skill then
        local percentBar = skill:getChildById('percent')
        return percentBar and percentBar:isVisible()
    end
    return false
end

function toggleSkillProgressBar(skillId)
    local skill = skillsWindow:recursiveGetChildById(skillId)
    if skill then
        local percentBar = skill:getChildById('percent')
        local skillIcon = skill:getChildById('icon')
        
        if percentBar then
            local isVisible = percentBar:isVisible()
            percentBar:setVisible(not isVisible)
            
            -- Also toggle skill icon if it exists
            if skillIcon then
                skillIcon:setVisible(not isVisible)
            end
            
            -- Adjust skill button height
            if not isVisible then
                skill:setHeight(21) -- Show progress bar
            else
                skill:setHeight(15) -- Hide progress bar
            end
            
            -- Save the setting
            local char = g_game.getCharacterName()
            if not skillSettings[char] then
                skillSettings[char] = {}
            end
            skillSettings[char][skillId] = isVisible and 1 or 0  -- 1 = hidden, 0 = visible
            g_settings.setNode('skills-hide', skillSettings)
        end
    end
end

function toggleSkillVisibility(skillId)
    local skill = skillsWindow:recursiveGetChildById(skillId)
    if skill then
        local percentBar = skill:getChildById('percent')
        local skillIcon = skill:getChildById('icon')
        
        if percentBar then
            local isVisible = percentBar:isVisible()
            percentBar:setVisible(not isVisible)
            
            -- Also toggle skill icon if it exists
            if skillIcon then
                skillIcon:setVisible(not isVisible)
            end
            
            -- Adjust skill button height
            if not isVisible then
                skill:setHeight(21) -- Show progress bar
            else
                skill:setHeight(15) -- Hide progress bar
            end
            
            -- Save the setting
            local char = g_game.getCharacterName()
            if not skillSettings[char] then
                skillSettings[char] = {}
            end
            skillSettings[char][skillId] = isVisible and 1 or 0  -- 1 = hidden, 0 = visible
            g_settings.setNode('skills-hide', skillSettings)
        end
    end
end

function resetExperienceCounter()
    local player = g_game.getLocalPlayer()
    if player then
        modules.game_textmessage.displayGameMessage('Experience counter has been reset.')
    end
end

function areOffenceStatsVisible()
    return areStatsVisible('offence')
end

function toggleOffenceStatsVisibility()
    toggleGroupVisibility('offence')
end

function areDefenceStatsVisible()
    return areStatsVisible('defence')
end

function toggleDefenceStatsVisibility()
    toggleGroupVisibility('defence')
end

function areMiscStatsVisible()
    return areStatsVisible('misc')
end

function toggleMiscStatsVisibility()
    toggleGroupVisibility('misc')
end

function areAllSkillBarsVisible()
    for _, skillId in pairs(SKILL_GROUPS.individual) do
        local skill = skillsWindow:recursiveGetChildById(skillId)
        if skill then
            local percentBar = skill:getChildById('percent')
            if percentBar and not percentBar:isVisible() then
                return false
            end
        end
    end
    return true
end

function toggleAllSkillBars()
    local shouldShow = not areAllSkillBarsVisible()
    
    for _, skillId in pairs(SKILL_GROUPS.individual) do
        local skill = skillsWindow:recursiveGetChildById(skillId)
        if skill then
            local percentBar = skill:getChildById('percent')
            local skillIcon = skill:getChildById('icon')
            
            if percentBar then
                percentBar:setVisible(shouldShow)
                
                if skillIcon then
                    skillIcon:setVisible(shouldShow)
                end
                
                skill:setHeight(shouldShow and 21 or 15)
                
                local char = g_game.getCharacterName()
                if not skillSettings[char] then
                    skillSettings[char] = {}
                end
                skillSettings[char][skillId] = shouldShow and 0 or 1
            end
        end
    end
    
    g_settings.setNode('skills-hide', skillSettings)
end

function expForLevel(level)
    return math.floor((50 * level * level * level) / 3 - 100 * level * level + (850 * level) / 3 - 200)
end

function expToAdvance(currentLevel, currentExp)
    return expForLevel(currentLevel + 1) - currentExp
end

function resetSkillColor(id)
    local skill = skillsWindow:recursiveGetChildById(id)
    if not skill then return end
    local widget = skill:getChildById('value')
    widget:setColor('#bbbbbb')
end

function toggleSkill(id, state)
    local skill = skillsWindow:recursiveGetChildById(id)
    if skill then skill:setVisible(state) end
end

function setSkillBase(id, value, baseValue)
    if baseValue <= 0 or value < 0 then
        return
    end
    local skill = skillsWindow:recursiveGetChildById(id)
    if not skill then return end
    local widget = skill:getChildById('value')

    if value > baseValue then
        widget:setColor('#008b00') -- green
        skill:setTooltip(baseValue .. ' +' .. (value - baseValue))
    elseif value < baseValue then
        widget:setColor('#b22222') -- red
        skill:setTooltip(baseValue .. ' ' .. (value - baseValue))
    else
        widget:setColor('#bbbbbb') -- default
        skill:removeTooltip()
    end
end

function setSkillValue(id, value)
    local skill = skillsWindow:recursiveGetChildById(id)
    if not skill then
        return
    end
    local widget = skill:getChildById('value')
    local GameAdditionalSkills = isSkillInGroups(id, {'GameAdditionalSkills'})
    if GameAdditionalSkills then
        local usePercentage = g_game.getFeature(GameEnterGameShowAppearance)
        if usePercentage then
            local needsDecimals = (id == 'skillId10' or id == 'skillId12')
            local displayValue = needsDecimals and (value / 100) or value
            local text = needsDecimals
                and string.format("%.2f%%", displayValue)
                or (displayValue .. "%")
        
            widget:setText(text)
            local color = (displayValue > 0 and 'green')
                or (displayValue == 0 and '#C0C0C0')
                or 'red'
            widget:setColor(color)
        else
            widget:setText(((id == 'skillId8') and "+" or "") .. value .. "%")
        end
    else
        widget:setText(value)
        widget:setColor('#C0C0C0')
    end

    if id == 'capacity' then
        local player = g_game.getLocalPlayer()
        if player then
            local totalCap = player:getTotalCapacity()
            local baseCap = player:getBaseCapacity()
            local freeCap = player:getFreeCapacity()
            if freeCap == 0 then
                widget:setColor('#b22222')
            elseif totalCap > 0 and baseCap > 0 and baseCap ~= 4294967295 and totalCap ~= baseCap then
                widget:setColor('#44ad25')
            else
                local ratio = totalCap > 0 and (freeCap / totalCap * 100) or 100
                widget:setColor(ratio <= 20 and '#b22222' or '#C0C0C0')
            end
            if totalCap > 0 then
                skill:setTooltip(tr('You have %s of %s capacity left', comma_value(freeCap), comma_value(totalCap)))
            end
        end
    end
end

function isSkillInGroups(skillId, groupNames)
    if smallSkillsCache[skillId] ~= nil then
        return smallSkillsCache[skillId]
    end
    for _, groupName in ipairs(groupNames) do
        local skills = SKILL_GROUPS[groupName]
        if skills then
            for _, id in ipairs(skills) do
                if id == skillId then
                    smallSkillsCache[skillId] = true
                    return true
                end
            end
        end
    end
    smallSkillsCache[skillId] = false
    return false
end

function setSkillColor(id, value)
    local skill = skillsWindow:recursiveGetChildById(id)
    if skill then
        local widget = skill:getChildById('value')
        widget:setColor(value)
    end
end

function setSkillTooltip(id, value)
    local skill = skillsWindow:recursiveGetChildById(id)
    if skill then
        if value then
            skill:setTooltip(value)
        else
            skill:removeTooltip()
        end
    end
end

function setSkillPercent(id, percent, tooltip, color)
    local skill = skillsWindow:recursiveGetChildById(id)
    if skill then
        local widget = skill:getChildById('percent')
        if widget then
            widget:setPercent(math.floor(percent))

            if tooltip then
                widget:setTooltip(tooltip)
            end

            if color then
                widget:setBackgroundColor(color)
            end
        end
    end
end

function checkAlert(id, value, maxValue, threshold, greaterThan)
    if greaterThan == nil then
        greaterThan = false
    end
    local alert = false

    -- maxValue can be set to false to check value and threshold
    -- used for regeneration checking
    if type(maxValue) == 'boolean' then
        if maxValue then
            return
        end

        if greaterThan then
            if value > threshold then
                alert = true
            end
        else
            if value < threshold then
                alert = true
            end
        end
    elseif type(maxValue) == 'number' then
        if maxValue < 0 then
            return
        end

        local percent = math.floor((value / maxValue) * 100)
        if greaterThan then
            if percent > threshold then
                alert = true
            end
        else
            if percent < threshold then
                alert = true
            end
        end
    end

    if alert then
        setSkillColor(id, '#b22222') -- red
    else
        resetSkillColor(id)
    end
end

function update()
    -- 14.10.2026 (Tobeto): the Attributes tab shows only the attribute list - Fullness,
    -- Offline Training and Experience Rate were switched back on by this refresh.
    if myotsAttributesShown then return end
    local offlineTraining = skillsWindow:recursiveGetChildById('offlineTraining')
    if not g_game.getFeature(GameOfflineTrainingTime) then
        offlineTraining:setVisible(false)
    else
        offlineTraining:show()
    end

    local regenerationTime = skillsWindow:recursiveGetChildById('regenerationTime')
    if not g_game.getFeature(GamePlayerRegenerationTime) then
        regenerationTime:setVisible(false)
    else
        regenerationTime:show()
    end
    local xpBoostButton = skillsWindow:recursiveGetChildById('xpBoostButton')
    local xpGainRate = skillsWindow:recursiveGetChildById('xpGainRate')
    if g_game.getFeature(GameExperienceBonus) then
        xpBoostButton:show()
        xpGainRate:show()
    else
        xpBoostButton:setVisible(false)
        xpGainRate:setVisible(false)
    end
end

function skillController:onGameStart()
    ourPinSyncAsked=nil
    scheduleEvent(function() pcall(ourRefreshPinned) end, 1500)
    skillsWindow:setupOnStart()
    scheduleEvent(function()
        local p = g_game.getProtocolGame()
        if p then p:sendExtendedOpcode(101, "get") end
    end, 500)
    refresh()

    local newWindowButton = skillsWindow:recursiveGetChildById('newWindowButton')
    if g_game.getClientVersion() < 1310 and newWindowButton then
        newWindowButton:setVisible(false)
        local sepForge = skillsWindow:recursiveGetChildById('separadorOnForgeBonusesChange')
        if sepForge and sepForge:isVisible() then
            sepForge:setVisible(false)
        end
        local sepDefense = skillsWindow:recursiveGetChildById('separadorOnDefenseInfoChange')
        if sepDefense and sepDefense:isVisible() then
            sepDefense:setVisible(false)
        end

        local lockButton = skillsWindow:recursiveGetChildById('lockButton')
        local contextMenuButton = skillsWindow:recursiveGetChildById('contextMenuButton')
        
        if lockButton and contextMenuButton then
            lockButton:breakAnchors()
            lockButton:addAnchor(AnchorTop, contextMenuButton:getId(), AnchorTop)
            lockButton:addAnchor(AnchorRight, contextMenuButton:getId(), AnchorLeft)
            lockButton:setMarginRight(2)
            lockButton:setMarginTop(0)
        end
    end
    
    scheduleEvent(function() 
        loadSkillsVisibilitySettings() 
    end, 100)
    hideOldClientStats()
    updateHeight()
end

function refresh()
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    if expSpeedEvent then
        expSpeedEvent:cancel()
        expSpeedEvent = nil
    end
    expSpeedEvent = cycleEvent(checkExpSpeed, 30 * 1000)

    onExperienceChange(player, player:getExperience())
    onLevelChange(player, player:getLevel(), player:getLevelPercent())
    onHealthChange(player, player:getHealth(), player:getMaxHealth())
    onManaChange(player, player:getMana(), player:getMaxMana())
    onSoulChange(player, player:getSoul())
    onFreeCapacityChange(player, player:getFreeCapacity())
    onStaminaChange(player, player:getStamina())
    onMagicLevelChange(player, player:getMagicLevel(), player:getMagicLevelPercent())
    onOfflineTrainingChange(player, player:getOfflineTrainingTime())
    onRegenerationChange(player, player:getRegenerationTime())
    onSpeedChange(player, player:getSpeed())

    for i = Skill.Fist, Skill.Transcendence do
        onSkillChange(player, i, player:getSkillLevel(i), player:getSkillLevelPercent(i))
    end
    update()
    updateHeight()
    if g_game.getClientVersion() >= 1410 then
        onFlatDamageHealingChange(player, statsCache.flatDamageHealing)
        onAttackInfoChange(player, statsCache.attackValue, statsCache.attackElement)
        onConvertedDamageChange(player, statsCache.convertedDamage, statsCache.convertedElement)
        onImbuementsChange(player, statsCache.lifeLeech, statsCache.manaLeech, statsCache.critChance, statsCache.critDamage, statsCache.onslaught)
        onDefenseInfoChange(player, statsCache.defense, statsCache.armor, statsCache.mantra, statsCache.mitigation, statsCache.dodge, statsCache.damageReflection)
        onCombatAbsorbValuesChange(player, statsCache.combatAbsorbValues)
        onForgeBonusesChange(player, statsCache.momentum, statsCache.transcendence, statsCache.amplification)
    end
end

function loadSkillsVisibilitySettings()
    local char = g_game.getCharacterName()
    if not char or not skillSettings[char] then
        return
    end
    
    local settings = skillSettings[char]
    
    for _, skillId in pairs(SKILL_GROUPS.individual) do
        if settings[skillId] ~= nil then
            local skill = skillsWindow:recursiveGetChildById(skillId)
            if skill then
                local percentBar = skill:getChildById('percent')
                local skillIcon = skill:getChildById('icon')
                
                if percentBar then
                    local shouldShow = settings[skillId] ~= 1
                    percentBar:setVisible(shouldShow)
                    
                    if skillIcon then
                        skillIcon:setVisible(shouldShow)
                    end
                    
                    skill:setHeight(shouldShow and 21 or 15)
                end
            end
        end
    end
    
    if g_game.getClientVersion() >= 1412 then
        local groupSettings = {
            {name = 'offence', key = 'offenceStats_visible'},
            {name = 'defence', key = 'defenceStats_visible'},
            {name = 'misc', key = 'miscStats_visible'}
        }
        
        for _, group in pairs(groupSettings) do
            if settings[group.key] == nil then
                settings[group.key] = true
                g_settings.setNode('skills-hide', skillSettings)
            end
            
            if settings[group.key] ~= nil then
                setSkillGroupVisibility(group.name, settings[group.key])
            end
        end
    end
end

function updateHeight()
    pcall(ourApplyRowHides)
    local maximumHeight = 8 -- margin top and bottom
    local minimumHeight = 80 -- ensure minimum height is maintained

    if g_game.isOnline() then
        local char = g_game.getCharacterName()

        if not skillSettings[char] then
            skillSettings[char] = {}
        end

        local skillsButtons = skillsWindow:recursiveGetChildById('experience'):getParent():getChildren()

        for _, skillButton in pairs(skillsButtons) do
            local percentBar = skillButton:getChildById('percent')

            if skillButton:isVisible() then
                if percentBar then
                    showPercentBar(skillButton, skillSettings[char][skillButton:getId()] ~= 1)
                end
                -- 10.10.2026: margin-top counts too (Level, separators...)
                maximumHeight = maximumHeight + skillButton:getMarginTop() + skillButton:getHeight() + skillButton:getMarginBottom()
            end
        end
        -- OurTibia (10.10.2026): setContentMaximumHeight adds the margins and
        -- padding of the contents panel, but not the window header the panel
        -- is anchored below (15 px). Without it the window could not be
        -- stretched far enough to show the last rows (Skills and Attributes
        -- tab) and the scrollbar never went away.
        local header = skillsWindow:getChildById('miniwindowHeader')
        if header then
            maximumHeight = maximumHeight + header:getMarginTop() + header:getHeight()
        end
        -- 16.10.2026: the pinned tabs (and the non-zero box) above the rows
        local contents = skillsWindow:getChildById('contentsPanel')
        if contents then maximumHeight = maximumHeight + math.max(0, contents:getMarginTop() - 2) end
    else
        maximumHeight = 390
    end

    local contentsPanel = skillsWindow:getChildById('contentsPanel')
    skillsWindow:setContentMinimumHeight(math.max(minimumHeight, 44))
    skillsWindow:setContentMaximumHeight(maximumHeight)
    -- 17.10.2026 (Tobeto): unpinning an attribute makes the window shorter right away
    local border = skillsWindow:getChildById('bottomResizeBorder')
    local maxH = border and tonumber(border.maximum)
    if maxH and maxH > 0 and skillsWindow:getHeight() > maxH then
        skillsWindow:setHeight(maxH)
    end
end

local function resetTable(t)
    for k, v in pairs(t) do
        if type(v) == "table" then
            resetTable(v)
        else
            t[k] = 0
        end
    end
end

function skillController:onGameEnd()
    skillsWindow:setParent(nil, true)
    if expSpeedEvent then
        expSpeedEvent:cancel()
        expSpeedEvent = nil
    end
    
    local allGroups = {'offence', 'defence', 'misc', 'GameAdditionalSkills', 'GameForgeSkillStats', 'GameForgeSkillStats1332'}
    for _, groupName in pairs(allGroups) do
        local skills = SKILL_GROUPS[groupName]
        if skills then
            for _, skillId in pairs(skills) do
                local skill = skillsWindow:recursiveGetChildById(skillId)
                if skill then
                    if not string.find(skillId, "separador") then
                        local valueWidget = skill:getChildById('value')
                        if valueWidget then
                            valueWidget:setText("0")
                        end
                        skill:setVisible(false)
                    end
                end
            end
        end
    end
    resetTable(statsCache)
    g_settings.setNode('skills-hide', skillSettings)
end

function toggle()
    if skillsButton:isOn() then
        skillsWindow:close()
        skillsButton:setOn(false)
    else
        if not skillsWindow:getParent() then
            local panel = modules.game_interface.findContentPanelAvailable(skillsWindow, skillsWindow:getMinimumHeight())
            if not panel then
                return
            end
            panel:addChild(skillsWindow)
        end
        skillsWindow:open()
        skillsButton:setOn(true)
        updateHeight()
    end
end

function checkExpSpeed()
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    local currentExp = player:getExperience()
    local currentTime = g_clock.seconds()
    
    if player.lastExps == nil then
        player.lastExps = {}
    end
    
    table.insert(player.lastExps, {currentExp, currentTime})
    if #player.lastExps > 30 then
        table.remove(player.lastExps, 1)
    end
    
    if #player.lastExps >= 2 then
        local oldestEntry = player.lastExps[1]
        local expGained = currentExp - oldestEntry[1]
        local timeElapsed = currentTime - oldestEntry[2]
        
        player.expSpeed = timeElapsed > 0 and (expGained / timeElapsed) or 0
        
        onLevelChange(player, player:getLevel(), player:getLevelPercent())
        onExperienceChange(player, player:getExperience())
    end
end

function onMiniWindowOpen()
    if skillsButton then
        skillsButton:setOn(true)
    end
end

function onMiniWindowClose()
    if skillsButton then
        skillsButton:setOn(false)
    end
end

function onSkillButtonClick(button)
    local percentBar = button:getChildById('percent')
    local skillIcon = button:getChildById('icon')
    if percentBar and skillIcon then
        showPercentBar(button, not percentBar:isVisible())
        skillIcon:setVisible(skillIcon:isVisible())

        local char = g_game.getCharacterName()
        if percentBar:isVisible() then
            skillsWindow:modifyMaximumHeight(6)
            skillSettings[char][button:getId()] = 0
        else
            skillsWindow:modifyMaximumHeight(-6)
            skillSettings[char][button:getId()] = 1
        end
    end
end

function showPercentBar(button, show)
    local percentBar = button:getChildById('percent')
    local skillIcon = button:getChildById('icon')
    if percentBar and skillIcon then
        percentBar:setVisible(show)
        skillIcon:setVisible(show)
        if show then
            button:setHeight(21)
        else
            button:setHeight(21 - 6)
        end
    end
end

local function getExperienceTooltip(localPlayer)
    local currentLevel = localPlayer:getLevel()
    local currentExp = localPlayer:getExperience()
    local nextLevelExp = expForLevel(currentLevel + 1)
    local expNeeded = nextLevelExp - currentExp
    
    if expNeeded <= 0 then
        return nil
    end
    
    if localPlayer.expSpeed and localPlayer.expSpeed > 0 then
        local expPerHour = math.floor(localPlayer.expSpeed * 3600)
        local hoursLeft = expNeeded / expPerHour
        local minutesLeft = math.floor((hoursLeft - math.floor(hoursLeft)) * 60)
        hoursLeft = math.floor(hoursLeft)
        return tr('%s of experience per hour', comma_value(expPerHour)) .. '\n' ..
               tr('Next level in %d hours and %d minutes', hoursLeft, minutesLeft)
    end
    
    local states = localPlayer:getStates()
    local isInBattle = Player.isStateActive(states, PlayerStates.Swords) or Player.isStateActive(states, PlayerStates.RedSwords)
    
    if not isInBattle then
        return tr('%s XP for next level', comma_value(expNeeded))
    end
    
    return nil
end

function onExperienceChange(localPlayer, value)
    if not localPlayer then
        return
    end
    setSkillValue('experience', comma_value(value))
    setSkillTooltip('experience', getExperienceTooltip(localPlayer))
    onLevelChange(localPlayer, localPlayer:getLevel(), localPlayer:getLevelPercent())
end

function onLevelChange(localPlayer, value, percent)
    if not localPlayer then
        return
    end
    -- The C++ onLevelChange callback passes m_levelPercent raw, which is centipercent
    -- (0-10000) once GameLevelPercentU16 is enabled (protocol >= 1520), not the 0-100 the
    -- UI expects. getLevelPercent() normalizes it, so always use the getter: otherwise the
    -- bar renders full and the tooltip reads "-5500 percent to go" at high levels.
    percent = localPlayer:getLevelPercent()
    setSkillValue('level', comma_value(value))
    local text = tr('You have %s percent to go', 100 - percent)
    setSkillPercent('level', percent, text)
end

function onHealthChange(localPlayer, health, maxHealth)
    pcall(ourUpdateLive)
    setSkillValue('health', comma_value(health) .. ' / ' .. comma_value(maxHealth))
    checkAlert('health', health, maxHealth, 30)
end

function onManaChange(localPlayer, mana, maxMana)
    pcall(ourUpdateLive)
    setSkillValue('mana', comma_value(mana) .. ' / ' .. comma_value(maxMana))
    checkAlert('mana', mana, maxMana, 30)
end

function onSoulChange(localPlayer, soul)
    pcall(ourUpdateLive)
    setSkillValue('soul', soul)
end

function onFreeCapacityChange(localPlayer, freeCapacity)
    pcall(ourUpdateLive)
    setSkillValue('capacity', comma_value(freeCapacity))
end

function onTotalCapacityChange(localPlayer, totalCapacity)
    local player = g_game.getLocalPlayer()
    if player then
        setSkillValue('capacity', comma_value(player:getFreeCapacity()))
    end
end

function onBaseCapacityChange(localPlayer, baseCapacity)
    local player = g_game.getLocalPlayer()
    if player then
        setSkillValue('capacity', comma_value(player:getFreeCapacity()))
    end
end

local function formatTime(minutes)
    local hours = math.floor(minutes / 60)
    local mins = minutes % 60
    if mins < 10 then
        mins = '0' .. mins
    end
    return hours .. ':' .. mins
end

local function getStaminaTooltip(hours, minutes, stamina)
    local timeText = tr('You have %s hours and %s minutes left', hours, minutes)
    
    if stamina > 1320 then
        return timeText .. '\n' .. tr('Now you will gain 50%% more experience')
    elseif stamina < 1320 and stamina > 240 then
        return timeText
    elseif stamina <= 240 and stamina > 0 then
        return timeText .. '\n' .. tr('You gain only 50%% experience and you don\'t may gain loot from monsters')
    elseif stamina == 0 then
        return timeText .. '\n' .. tr('You don\'t may receive experience and loot from monsters')
    end
    return timeText
end

function onStaminaChange(localPlayer, stamina)
    local hours = math.floor(stamina / 60)
    local minutes = stamina % 60
    local percent = math.floor(100 * stamina / (24 * 60))
    
    setSkillValue('stamina', formatTime(stamina))
    
    local tooltip = getStaminaTooltip(hours, minutes, stamina)
    local color = 'orange'
    
    if stamina > 1320 then
        color = 'green'
    elseif stamina <= 240 and stamina > 0 then
        color = 'red'
    elseif stamina == 0 then
        color = 'black'
    end
    
    setSkillPercent('stamina', percent, tooltip, color)
    if myotsXpRateColor then myotsXpRateColor() end
end

function onOfflineTrainingChange(localPlayer, offlineTrainingTime)
    if not g_game.getFeature(GameOfflineTrainingTime) then
        return
    end
    local percent = 100 * offlineTrainingTime / (12 * 60)
    setSkillValue('offlineTraining', formatTime(offlineTrainingTime))
    setSkillPercent('offlineTraining', percent, tr('You have %s percent', percent))
end

function onRegenerationChange(localPlayer, regenerationTime)
    if not g_game.getFeature(GamePlayerRegenerationTime) or regenerationTime < 0 then
        return
    end
    local hours = math.floor(regenerationTime / 3600)
    local minutes = math.floor(regenerationTime / 60)
    local seconds = regenerationTime % 60
    if seconds < 10 then
        seconds = '0' .. seconds
    end
    if minutes < 10 then
        minutes = '0' .. minutes
    end
    if hours < 10 then
        hours = '0' .. hours
    end
    local fmt = ""
    local alert = 300
    if g_game.getFeature(GameEnterGameShowAppearance) then
        fmt = string.format("%02d:%02d:%02d", hours, minutes, seconds)
        alert = 0
    else
        fmt = string.format("%02d:%02d", minutes, seconds)
    end
    setSkillValue('regenerationTime', fmt)
    checkAlert('regenerationTime', regenerationTime, false, alert)
    -- 14.10.2026 (Tobeto): "Fullness" with a bar like Stamina - food lasts up to 1 hour
    -- (server cap 3600 s): green over 70%, orange 70% or less, red 20% or less.
    local full = math.max(0, math.min(100, regenerationTime * 100 / 3600))
    local color = full > 70 and 'green' or (full > 20 and 'orange' or 'red')
    local tip = string.format('Fullness: %d%%\nTo become full, eat food.', math.floor(full + 0.5))
    setSkillPercent('regenerationTime', full, tip, color)
    local row = skillsWindow and skillsWindow:recursiveGetChildById('regenerationTime')
    if row then row:setTooltip(tip) end
    if g_game.getFeature(GameEnterGameShowAppearance) then
        modules.game_interface.StatsBar.onHungryChange(regenerationTime, alert)
    end
end

function onSpeedChange(localPlayer, speed)
    setSkillValue('speed', comma_value(speed))

    onBaseSpeedChange(localPlayer, localPlayer:getBaseSpeed())
end

function onBaseSpeedChange(localPlayer, baseSpeed)
    -- 13.10.2026 (Tobeto): speed is green only while hasted (haste spell, potion...)
    -- and red only while paralysed - stat and equipment bonuses keep the normal colour
    local skill = skillsWindow and skillsWindow:recursiveGetChildById('speed')
    if not skill or not localPlayer then return end
    local widget = skill:getChildById('value')
    local speed = localPlayer:getSpeed()
    if localPlayer:hasState(PlayerStates.Paralyze) then
        widget:setColor('#b22222')
    elseif localPlayer:hasState(PlayerStates.Haste) then
        widget:setColor('#008b00')
    else
        widget:setColor('#bbbbbb')
    end
    if baseSpeed and baseSpeed > 0 and speed ~= baseSpeed then
        skill:setTooltip(baseSpeed .. ' ' .. (speed > baseSpeed and '+' or '') .. (speed - baseSpeed))
    else
        skill:removeTooltip()
    end
end
function onOurStatesChange(localPlayer, now, old)
    if localPlayer and localPlayer:isLocalPlayer() then onBaseSpeedChange(localPlayer, localPlayer:getBaseSpeed()) end
end

function onMagicLevelChange(localPlayer, magiclevel, percent)
    setSkillValue('magiclevel', magiclevel)
    setSkillPercent('magiclevel', percent, tr('You have %s percent to go', 100 - percent))

    onBaseMagicLevelChange(localPlayer, localPlayer:getBaseMagicLevel())
end

function onBaseMagicLevelChange(localPlayer, baseMagicLevel)
    setSkillBase('magiclevel', localPlayer:getMagicLevel(), baseMagicLevel)
end

function onSkillChange(localPlayer, id, level, percent)
    setSkillValue('skillId' .. id, level)
    setSkillPercent('skillId' .. id, percent, tr('You have %s percent to go', 100 - percent))

    onBaseSkillChange(localPlayer, id, localPlayer:getSkillBaseLevel(id))

    if id > Skill.ManaLeechAmount then
	    toggleSkill('skillId' .. id, level > 0)
    end
    if myotsSpecial and myotsSpecial[id] then setSkillValue('skillId'..id,myotsSpecial[id]) end
end

function onBaseSkillChange(localPlayer, id, baseLevel)
    setSkillBase('skillId' .. id, localPlayer:getSkillLevel(id), baseLevel)
end

-- 10.10.2026: Experience Rate is green, red while low stamina (4 h or less) halves it.
function myotsXpRateColor()
    if not skillsWindow then return end
    local row = skillsWindow:recursiveGetChildById('xpGainRate')
    local value = row and row:getChildById('value')
    if not value then return end
    local player = g_game.getLocalPlayer()
    local low = player and player:getStamina() <= 240
    value:setColor(low and '#ff4a4a' or '#44ad25')
end

local function updateExperienceRate(localPlayer)
    local baseRate = ExpRating[ExperienceRate.BASE] or 100
    local expRateTotal = baseRate

    for type, value in pairs(ExpRating) do
        if type ~= ExperienceRate.BASE and type ~= ExperienceRate.STAMINA_MULTIPLIER then
            expRateTotal = expRateTotal + (value or 0)
        end
    end

    local staminaMultiplier = ExpRating[ExperienceRate.STAMINA_MULTIPLIER] or 100
    expRateTotal = expRateTotal * staminaMultiplier / 100

    local xpgainrate = skillsWindow:recursiveGetChildById("xpGainRate")
    if not xpgainrate then
        return
    end

    local widget = xpgainrate:getChildById("value")
    if not widget then
        return
    end

    -- OurTibia: the server's own rate (sent with the attribute stats) wins.
    if myotsXpRateText then
        widget:setText(myotsXpRateText)
        xpgainrate:setTooltip(myotsXpTooltip)
        myotsXpRateColor()
        return
    end

    widget:setText(math.floor(expRateTotal) .. "%")

    local tooltip = string.format("Your current XP gain rate amounts to %d%%.", math.floor(expRateTotal))
    tooltip = tooltip .. string.format("\nYour XP gain rate is calculated as follows:\n- Base XP gain rate %d%%", baseRate)

    if (ExpRating[ExperienceRate.VOUCHER] or 0) > 0 then
        tooltip = tooltip .. string.format("\n- Voucher: %d%%", ExpRating[ExperienceRate.VOUCHER])
    end

    if (ExpRating[ExperienceRate.XP_BOOST] or 0) > 0 then
        tooltip = tooltip .. string.format("\n- XP Boost: %d%% (%s h remaining)", ExpRating[ExperienceRate.XP_BOOST],
            formatTimeBySeconds(localPlayer:getStoreExpBoostTime()))
    end

    if (ExpRating[ExperienceRate.LOW_LEVEL] or 0) > 0 then
        tooltip = tooltip .. string.format("\n- Low Level Bonus: %d%%", ExpRating[ExperienceRate.LOW_LEVEL])
    end

    tooltip = tooltip .. string.format("\n- Stamina multiplier: x%.1f (%s h remaining)", staminaMultiplier / 100,
        formatTimeByMinutes(math.max(0, localPlayer:getStamina() - 1320)))

    xpgainrate:setTooltip(tooltip)

    local colors = {
        [0] = "#ff4a4a",
        ["greater"] = "#00cc00",
        ["less"] = "#ff9429",
        ["equal"] = "#ffffff"
    }
    
    local colorKey = expRateTotal == 0 and 0 or 
                     (expRateTotal > 100 and "greater" or 
                      (expRateTotal < 100 and "less" or "equal"))
    
    widget:setColor(colors[colorKey])
end

function onExperienceRateChange(localPlayer, type, value)
    ExpRating[type] = value
    updateExperienceRate(localPlayer)
end

local function setSkillValueWithTooltips(id, value, tooltip, showPercentage, color)
    local skill = skillsWindow:recursiveGetChildById(id)
    if not skill then
        return
    end
    
    if g_game.getClientVersion() < 1412 then
        local oldClientStats = {
            'skillId7', 'skillId8', 'skillId9', 'skillId10', 'skillId11', 'skillId12', 
            'skillId13', 'skillId14', 'skillId15', 'skillId16',
            'damageHealing', 'attackValue', 'convertedDamage', 'convertedElement',
            'criticalHit', 'lifeLeech', 'manaLeech', 'criticalChance', 'criticalExtraDamage', 'onslaught',
            'physicalResist', 'fireResist', 'earthResist', 'energyResist', 'IceResist', 
            'HolyResist', 'deathResist', 'HealingResist', 'drowResist', 'lifedrainResist', 
            'manadRainResist', 'defenceValue', 'armorValue', 'mantraValue', 'mitigation', 'dodge', 
            'damageReflection', 'momentum', 'transcendence', 'amplification'
        }
        
        for _, statId in pairs(oldClientStats) do
            if id == statId then
                skill:setVisible(false)
                return
            end
        end
    end
    
    if g_game.getClientVersion() >= 1412 then
        local char = g_game.getCharacterName()
        if char and skillSettings and skillSettings[char] then
            local settings = skillSettings[char]
            
            for groupName, groupStats in pairs({offence = SKILL_GROUPS.offence, defence = SKILL_GROUPS.defence, misc = SKILL_GROUPS.misc}) do
                for _, statId in pairs(groupStats) do
                    if id == statId and settings[groupName .. 'Stats_visible'] == false then
                        skill:setVisible(false)
                        return
                    end
                end
            end
        end
    end
    
    if value ~= nil then
        local shouldHide = false
        if value == 0 or (type(value) == "number" and math.abs(value) < 0.0001) then
            shouldHide = true
        elseif showPercentage then
            local percentValue = math.floor(value * 10000) / 100
            shouldHide = (percentValue == 0 or math.abs(percentValue) < 0.01)
        end
        if shouldHide then
            skill:setVisible(false)
            return
        end
        
        skill:show()
        local widget = skill:getChildById('value')
        if not widget then
            return
        end
        if color then
            widget:setColor(color)
        end
        if showPercentage then
            local percentValue = math.floor(value * 10000) / 100
            local sign = percentValue > 0 and "+ " or ""
            widget:setText(sign .. percentValue .. "%")
            if percentValue < 0 then
                widget:setColor("#FF9854")
            end
        else
            widget:setText(tostring(value))
        end
        if tooltip then
            skill:setTooltip(tooltip)
        end
    elseif string.find(id, "separador") then
        -- Separators should be shown when the group is visible, regardless of value
        skill:show()
    else
        skill:setVisible(false)
    end
end

function onFlatDamageHealingChange(localPlayer, flatBonus)
    -- Cache the data regardless of visibility
    statsCache.flatDamageHealing = flatBonus or 0
    
    local char = g_game.getCharacterName()
    if char and skillSettings and skillSettings[char] and skillSettings[char]['offenceStats_visible'] ~= false then
        skillsWindow:recursiveGetChildById("separadorOnOffenceInfoChange"):setVisible(true)
    end
    local tooltips = "This flat bonus is the main source of your character's power, added \nto most of the damage and healing values you cause."
    setSkillValueWithTooltips('damageHealing', flatBonus, tooltips, false)
end

function onAttackInfoChange(localPlayer, attackValue, attackElement)
    -- Cache the data regardless of visibility
    statsCache.attackValue = attackValue or 0
    statsCache.attackElement = attackElement or 0
    
    local char = g_game.getCharacterName()
    if char and skillSettings and skillSettings[char] and skillSettings[char]['offenceStats_visible'] ~= false then
        skillsWindow:recursiveGetChildById("separadorOnOffenceInfoChange"):setVisible(true)
    end
    local tooltips = "This is your character's basic attack power whenever you enter a \nfight with a weapon or your fists. It does not apply to any spells \nyou cast. The attack value is calculated from the weapon's attack\n value, the corresponding weapon skill, combat tactics, the bonus \nreceived from the Revelation Perks and the player's level. The \nvalue represents the average damage you would inflict on a\ncreature which had no kind of defence or protection."
    setSkillValueWithTooltips('attackValue', attackValue, tooltips, false)
    local skill = skillsWindow:recursiveGetChildById("attackValue")
    if skill then
        local element = clientCombat[attackElement]
        if element then
            skill:getChildById('icon'):setImageSource(element.path)
            skill:getChildById('icon'):setImageSize({width = 9, height = 9})
        end
    end
end

function onConvertedDamageChange(localPlayer, convertedDamage, convertedElement)
    -- Cache the data regardless of visibility
    statsCache.convertedDamage = convertedDamage or 0
    statsCache.convertedElement = convertedElement or 0
    
    setSkillValueWithTooltips('convertedDamage', convertedDamage, false, true)
    setSkillValueWithTooltips('convertedElement', convertedElement, false, true)
end

function onImbuementsChange(localPlayer, lifeLeech, manaLeech, critChance, critDamage, onslaught)
    -- Cache the data regardless of visibility
    statsCache.lifeLeech = lifeLeech or 0
    statsCache.manaLeech = manaLeech or 0
    statsCache.critChance = critChance or 0
    statsCache.critDamage = critDamage or 0
    statsCache.onslaught = onslaught or 0
    
    local char = g_game.getCharacterName()
    if char and skillSettings and skillSettings[char] and skillSettings[char]['offenceStats_visible'] ~= false then
        skillsWindow:recursiveGetChildById("separadorOnOffenceInfoChange"):setVisible(true)
    end
    
    local tooltips = {
        lifeLeech = "You have a +11.4% chance to trigger Onslaught, granting you 60% increased damage for all attacks.",
        manaLeech = "You have a +1% chance to cause +1% extra damage.",
        critChance = "Critical Hits deal more damage than normal attacks. They have a chance to be \ntriggered during combat, inflicting additional damage beyond the standard amount.",
        critDamage = "You get +1% of the damage dealt as mana",
        onslaught = "You get +1% of the damage dealt as hit points"
    }
    
    setSkillValueWithTooltips('lifeLeech', lifeLeech, tooltips.lifeLeech, true)
    setSkillValueWithTooltips('manaLeech', manaLeech, tooltips.manaLeech, true)
    setSkillValueWithTooltips('criticalChance', critChance, tooltips.critChance, true)
    setSkillValueWithTooltips('criticalExtraDamage', critDamage, tooltips.critDamage, true)
    setSkillValueWithTooltips('onslaught', onslaught, tooltips.onslaught, true)
    local criticalHitWidget = skillsWindow:recursiveGetChildById("criticalHit")
    if criticalHitWidget then
        local hasCritValue = math.abs(critChance or 0) > 0.0001 or math.abs(critDamage or 0) > 0.0001
        local groupHidden = (function()
            local char = g_game.getCharacterName()
            return char and skillSettings and skillSettings[char] and skillSettings[char]['offenceStats_visible'] == false
        end)()
        criticalHitWidget:setVisible(hasCritValue and not groupHidden)
    end
end

local combatIdToWidgetId = {
    [0] = "physicalResist",
    [1] = "fireResist",
    [2] = "earthResist",
    [3] = "energyResist",
    [4] = "IceResist",
    [5] = "HolyResist",
    [6] = "deathResist",
    [7] = "HealingResist",
    [8] = "drowResist",
    [9] = "lifedrainResist",
    [10] = "manadRainResist"
}

function onCombatAbsorbValuesChange(localPlayer, absorbValues)
    -- Cache the data regardless of visibility
    statsCache.combatAbsorbValues = absorbValues or {}
    
    for id, widgetId in pairs(combatIdToWidgetId) do
        local skill = skillsWindow:recursiveGetChildById(widgetId)
        if skill then
                local value = absorbValues[id]
                if value ~= nil then
                    setSkillValueWithTooltips(widgetId, value, false, true, "#44AD25")
                else
                    skill:setVisible(false)
                end
        end
    end
end

function onDefenseInfoChange(localPlayer, defense, armor, mantra, mitigation, dodge, damageReflection)
    -- Cache the data regardless of visibility
    statsCache.defense = defense or 0
    statsCache.armor = armor or 0
    statsCache.mantra = mantra or 0
    statsCache.mitigation = mitigation or 0
    statsCache.dodge = dodge or 0
    statsCache.damageReflection = damageReflection or 0
    
    -- Show separator if defense stats are visible
    local char = g_game.getCharacterName()
    if char and skillSettings and skillSettings[char] and skillSettings[char]['defenceStats_visible'] ~= false then
        local separator = skillsWindow:recursiveGetChildById("separadorOnDefenseInfoChange")
        if separator then
            separator:setVisible(true)
        end
    end
    
    local tooltips = {
        defense = "When attacked, you have a +9.6% chance to trigger Dodge, which \nwill fully mitigate the damage.",
        armor = "Mitigation reduces most of the damage you take and varies based\non your shielding skill, equipped weapon, chosen combat tactics \nand any mitigation multipliers acquired in your Wheel of Destiny.",
        mantra = "Mantra is a special bonus stat granted by certain monk equipment.\nIt improves your monk-specific abilities and combat effectiveness.",
        mitigation = "This shows how well your armor protects you from all physical\nattacks.",
        dodge = "This is your protection against all physical attacks in close combat \nas well as all distance physical attacks. The higher the defence value, the less damage you will take from melee physical hits. The defence\n value is calculated from your shield and/or weapon\n defence and the corresponding skill. Careful! \nYour defence value protects you only from hits of two creatures in a single round."
    }
    
    setSkillValueWithTooltips('defenceValue', defense, tooltips.defense, false)
    setSkillValueWithTooltips('armorValue', armor, tooltips.armor, false)
    setSkillValueWithTooltips('mantraValue', mantra, tooltips.mantra, false)
    setSkillValueWithTooltips('mitigation', mitigation, tooltips.mitigation, true)
    setSkillValueWithTooltips('dodge', dodge, tooltips.dodge, true)
    setSkillValueWithTooltips('damageReflection', damageReflection, false, true)
end

function onForgeBonusesChange(localPlayer, momentum, transcendence, amplification)
    -- Cache the data regardless of visibility
    statsCache.momentum = momentum or 0
    statsCache.transcendence = transcendence or 0
    statsCache.amplification = amplification or 0
    
    local char = g_game.getCharacterName()
    if char and skillSettings and skillSettings[char] and skillSettings[char]['miscStats_visible'] ~= false then
        skillsWindow:recursiveGetChildById("separadorOnForgeBonusesChange"):setVisible(true)
    end
    
    local tooltips = {
        momentum = "During combat, you have a +" .. math.floor(momentum * 10000) / 100 .. "% chance to trigger Momentum\n, which reduces all spell cooldowns by 2 seconds.",
        transcendence = "During combat, you have a +" .. math.floor(transcendence * 10000) / 100 .. "% chance to trigger\nTranscendence, which transforms your character into a vocation-\nspecific avatar for 7 seconds. While in this form, you will benefit\nfrom a 15% damage reduction and guaranteed critical hits that \ndeal an additional 15% damage.",
        amplification = "Effects of tiered items are amplified by +" .. math.floor(amplification * 10000) / 100 .. "%."
    }

    setSkillValueWithTooltips('momentum', momentum, tooltips.momentum, true)
    setSkillValueWithTooltips('transcendence', transcendence, tooltips.transcendence, true)
    setSkillValueWithTooltips('amplification', amplification, tooltips.amplification, true)
end

-- Function to get experience rate values for other modules
function getExpRating(type)
    if type then
        return ExpRating[type] or 0
    else
        return ExpRating
    end
end

-- Function to calculate the total experience rate multiplier (excluding base rate)
function getTotalExpRateMultiplier()
    local baseRate = ExpRating[ExperienceRate.BASE] or 100
    local expRateTotal = baseRate

    for type, value in pairs(ExpRating) do
        if type ~= ExperienceRate.BASE and type ~= ExperienceRate.STAMINA_MULTIPLIER then
            expRateTotal = expRateTotal + (value or 0)
        end
    end

    local staminaMultiplier = ExpRating[ExperienceRate.STAMINA_MULTIPLIER] or 100
    expRateTotal = expRateTotal * staminaMultiplier / 100

    return expRateTotal / 100  -- Return as a decimal multiplier
end

-- Function to get just the base experience rate
function getBaseExpRate()
    return ExpRating[ExperienceRate.BASE] or 100
end

-- 10.10.2026: the "+" buttons explain the shortcuts (the stat effects are on the row).
myotsAddTip = 'Click: +1 point\nShift+click: +10 points\nCtrl+click: +100 points\n(or all your free points if you have fewer)'
-- Server-authoritative character stats, protocol extension 101.
function myotsAllocate(stat)
    local protocol = g_game.getProtocolGame()
    -- 09.10.2026: Click = +1, Shift+click = +10, Ctrl+click = +100 (clamped to the free points).
    local count = g_keyboard.isCtrlPressed() and 100 or (g_keyboard.isShiftPressed() and 10 or 1)
    -- Instant local update (01.10.2026): the click is counted against the points
    -- shown right now, so extra clicks never spend points that are already gone.
    if skillsWindow then
        local pointsRow = skillsWindow:recursiveGetChildById('myotsPoints')
        local pointsLabel = pointsRow and pointsRow:getChildById('value')
        local points = pointsLabel and tonumber((pointsLabel:getText():gsub('%D', ''))) or 0
        if points <= 0 then return end
        count = math.min(count, points)
        local row = skillsWindow:recursiveGetChildById('myots_' .. stat)
        local amount = row and row:getChildById('amount')
        if amount then amount:setText(tostring((tonumber((amount:getText():gsub('%D', ''))) or 0) + count)) end
        pointsLabel:setText(tostring(points - count))
        -- Ignore older server updates that still show the points before this click.
        myotsExpectedPoints = points - count
        myotsPendingUntil = g_clock.millis() + 3000
        if points - count <= 0 then
            for _, key in ipairs({'str', 'dex', 'int', 'con', 'wil', 'luck'}) do
                local r = skillsWindow:recursiveGetChildById('myots_' .. key)
                if r and r:getChildById('add') then r:getChildById('add'):setEnabled(false) end
            end
        end
    end
    if protocol then protocol:sendExtendedOpcode(101, 'add:' .. stat .. ':' .. count) end
end
myotsAttributesShown=false
function myotsTab(attributes)
    if not skillsWindow or myotsAttributesShown==attributes then return end
    myotsAttributesShown=attributes
    local contents=skillsWindow:getChildById('contentsPanel')
    for _,child in ipairs(contents:getChildren()) do
        if child:getId()~='myotsTabs' then
            if attributes then child.myotsPreviousVisible=child:isExplicitlyVisible();child:hide()
            elseif child.myotsPreviousVisible~=nil then child:setVisible(child.myotsPreviousVisible);child.myotsPreviousVisible=nil end
        end
    end
    skillsWindow:recursiveGetChildById('myotsDetails'):setVisible(attributes)
    local nz = skillsWindow:getChildById('myotsNonZero'); if nz then nz:setVisible(attributes) end
    local line = skillsWindow:getChildById('myotsStaticLine'); if line then line:setVisible(attributes) end
    pcall(ourTabsOffset)
    pcall(ourRefreshPinned)
    if attributes then
        local panel=skillsWindow:recursiveGetChildById('myotsDetails')
        panel:destroyChildren()
        myotsAttributesKey=nil
        if myotsAttributesPending then local pending=myotsAttributesPending;myotsAttributesPending=nil;myotsAttributes(pending) end
        if panel:getChildCount()==0 then local waiting=g_ui.createWidget('Label',panel);waiting:setText('Loading equipment attributes...') end
        if g_game.isOnline() then
            local protocol=g_game.getProtocolGame()
            if protocol then protocol:sendExtendedOpcode(107,'sync') end
        end
    end
    updateHeight()
end
function myotsStats(buffer)
    if not skillsWindow then return end
    local rh,rm,period=buffer:match('^regen|([%d%.]+)|([%d%.]+)|?(%d*)$')
    if rh then
        -- OurTibia (02.10.2026): character regeneration per 5 seconds (base +
        -- Constitution/Willpower). Constant: it does not change with food or rings.
        -- 03.10.2026: promoted characters regenerate every 4 seconds (sent by the server).
        local sec=tonumber(period) or 5
        local function fmt(v) return tostring(math.floor((tonumber(v) or 0)+0.5))..'/'..sec..'s' end -- 07.10.2026: whole numbers
        local hpRow=skillsWindow:recursiveGetChildById('myotsHpRegen');local mpRow=skillsWindow:recursiveGetChildById('myotsManaRegen')
        if hpRow then hpRow:getChildById('value'):setText(fmt(rh));hpRow:setTooltip('Health regenerated every '..sec..' seconds while you are fed (base + Constitution + items, talents and outfits).') end
        if mpRow then mpRow:getChildById('value'):setText(fmt(rm));mpRow:setTooltip('Mana regenerated every '..sec..' seconds while you are fed (base + Willpower + items, talents and outfits).') end
        return
    end
    local parts = {}
    for value in buffer:gmatch('[^|]+') do parts[#parts+1] = value end
    if #parts < 10 then return end
    if myotsPendingUntil and g_clock.millis() < myotsPendingUntil and (tonumber(parts[1]) or 0) > (myotsExpectedPoints or 0) then return end
    myotsPendingUntil = nil
    skillsWindow:recursiveGetChildById('myotsPoints'):getChildById('value'):setText(parts[1])
    -- 13.10.2026 (Tobeto): the Skills button glows gold while there are free stat points
    if skillsButton then
        local free = tonumber(parts[1]) or 0
        skillsButton:setTooltip(tr('Skills') .. ' (Alt+S)' .. (free > 0 and ('\n' .. free .. ' free stat point' .. (free == 1 and '' or 's') .. ' - open the skills to spend them') or ''))
        if free > 0 then skillsButton:setBorderWidth(1); skillsButton:setBorderColor('#ffd35a'); skillsButton:setImageColor('#ffe9a0')
        else skillsButton:setBorderWidth(0); skillsButton:setImageColor('#ffffff') end
    end
    -- 17.10.2026: the base vocation from the server (the client learns a new vocation from The
    -- Oracle only at the next login); used by the spell list filter
    if parts[12] then _G.OurBaseVocation = tonumber(parts[12]) end
    if parts[11] then
        myotsXpRateText = parts[11] .. '%'
        local tip = 'Your current experience rate amounts to ' .. parts[11] .. '%.'
        local b, pr, low, boost, mult = (parts[13] or ''):match('^(%d+),(%d+),(%d+),(%d+),(%d+)$')
        if b then
            tip = tip .. '\nCalculated as follows:\n- Base rate for your level: ' .. b .. '%'
            if tonumber(pr) > 0 then tip = tip .. '\n- Premium: +' .. pr .. '%' end
            if tonumber(low) > 0 then tip = tip .. '\n- Low level bonus: +' .. low .. '%' end
            if tonumber(boost) > 0 then tip = tip .. '\n- World experience boost +10% of your rate: +' .. boost .. '%' end -- 14.10.2026 (Tobeto)
            if tonumber(mult) ~= 1 then tip = tip .. '\n- Open beta multiplier: x' .. mult end
            -- 07.10.2026: stamina does change the gained experience (server: over 22 h x1.5, 14 h or less x0.5)
            local pl = g_game.getLocalPlayer()
            local st = pl and pl:getStamina() or 0
            if st > 1320 then tip = tip .. '\n- Stamina over 22 hours: x1.5 (not included above)'
            elseif st <= 240 then tip = tip .. '\n- Stamina 4 hours or less: x0.5 (not included above)'
            else tip = tip .. '\n- Stamina 14-22 hours: no bonus' end
        end
        myotsXpTooltip = tip
        local row = skillsWindow:recursiveGetChildById('xpGainRate')
        row:getChildById('value'):setText(myotsXpRateText)
        row:setTooltip(myotsXpTooltip)
        myotsXpRateColor()
    end
    skillsWindow:recursiveGetChildById('xpBoos'):hide()
    skillsWindow:recursiveGetChildById('health'):setMarginTop(0)
    local details={}
    for index, key in ipairs({'str','dex','int','con','wil','luck'}) do
        local row = skillsWindow:recursiveGetChildById('myots_' .. key)
        row:getChildById('amount'):setText(parts[index+1])
        row:getChildById('add'):setEnabled(tonumber(parts[1]) > 0)
        local value=tonumber(parts[index+1]) or 0
        local voc=tonumber(parts[12]) or 0
        local hp=({[0]=1,[1]=0.5,[2]=0.65,[3]=1,[4]=1.7})[voc] or 1
        local mp=({[0]=1,[1]=4,[2]=3.5,[3]=1.5,[4]=1})[voc] or 1
        local magic=({[1]=0.065,[2]=0.058})[voc] or 0.04
        local potion=(voc==1 or voc==2) and 0.07 or 0.055
        local function pct(v) return (string.format('%.2f',v):gsub('0+$',''):gsub('%.$','')) .. '%' end
        local function num(v) return (string.format('%.2f',v):gsub('0+$',''):gsub('%.$','')) end
        -- Wording and per-point values mirror the live Mythibia tooltips (30.09.2026).
        local tips={
          str=table.concat({
            '+ '..pct(value*0.085)..' Physical Damage',
            pct(math.min(50,10+value*0.016))..' Minimum Hit (Max. 50%)',
            '+ '..num(value*0.012)..' Armor'},'\n'),
          dex=table.concat({
            '+ '..pct(math.min(35,value*0.035))..' Attack Speed (Max. 35%)', -- 16.10.2026: max at 1000
            '+ '..pct(math.min(50,value*0.05))..' Enemy Armor ignored (Max. 50%)',
            '+ '..pct(math.min(15,value*0.015))..' Enemy Physical Resistance ignored (Max. 15%)'},'\n'),
          int=table.concat({
            '+ '..pct(value*magic)..' Magic Damage',
            '+ '..pct(value*0.035)..' Healing Power',
            '+ '..pct(value*potion)..' Mana Gained from potions',
            '+ '..pct(math.min(10,value*0.015))..' Enemy Elemental Resistance ignored (Max. 10%)'},'\n'),
          con=table.concat({
            '+ '..num(math.floor(value*hp))..' Health',
            '+ '..pct(value*0.42)..' Health regen',
            '+ '..num(value*0.25)..' Capacity'},'\n'),
          wil=table.concat({
            '+ '..num(math.floor(value*mp))..' Mana',
            '+ '..pct(value*0.26)..' Mana regen'},'\n'),
          luck=table.concat({
            '+ '..pct(value*0.05)..' Loot drop chance',
            '+ '..pct(math.min(50,value*0.06))..' Critical chance (Max. 50%)',
            '+ '..pct(math.min(20,value*0.025))..' Critical damage (Max. 20%)'},'\n')
        }
        row:setTooltip(tips[key]);row:getChildById('add'):setTooltip(myotsAddTip)
        details[#details+1]=key:upper()..': '..value..'\n'..tips[key]
    end

    updateHeight()
end

-- MyOTS: critical and leech values come from the server's attribute rows
-- (Luck + equipment), not from native 10.98 special skills.
myotsSpecial={}
local function applyMyotsSpecial()
    -- 07.10.2026: critical and leech values are in the Attributes tab - the Skills tab
    -- does not show them twice.
    for id,text in pairs(myotsSpecial) do setSkillValue('skillId'..id,text);toggleSkill('skillId'..id,false) end
end
function myotsAttributes(rows)
    if not skillsWindow then return end
    local values={}
    for _,entry in ipairs(rows or {}) do if entry.key then values[entry.key]=tonumber(entry.value) or 0 end end
    -- setSkillValue adds the % sign for these rows itself.
    local function pct(v) local t=string.format('%.2f',v or 0):gsub('0+$',''):gsub('%.$','');return t end
    myotsSpecial={[7]=pct(values.critical),[8]=pct(values.critdamage),[9]=(values.lifeleech or 0)>0 and '100' or '0',[10]=pct(values.lifeleech),[11]=(values.manaleech or 0)>0 and '100' or '0',[12]=pct(values.manaleech)}
    applyMyotsSpecial()
    local panel=skillsWindow:recursiveGetChildById('myotsDetails')
    if not panel then return end
    -- OurTibia (02.10.2026): rebuilding ~100 rows on every stat point froze the
    -- client. Only rebuild when the Attributes tab is open and the data changed.
    myotsAttributesLast=rows
    -- OurTibia (09.10.2026): optional "only non-zero values" filter (remembered).
    local onlyNonZero=g_settings.getBoolean('myotsAttrNonZero')
    local okKey,key=pcall(json.encode,rows or {})
    key=okKey and (key..(onlyNonZero and '|nz' or '')) or nil
    if not myotsAttributesShown then myotsAttributesPending=rows;return end
    if key and key==myotsAttributesKey and panel:getChildCount()>1 then return end
    myotsAttributesKey=key;myotsAttributesPending=nil
    panel:destroyChildren()
    -- 11.10.2026: the tall panel took the focus on the first click and the scroll
    -- area then scrolled to its bottom ("ensure visible") instead of toggling.
    panel:setFocusable(false)
    -- 16.10.2026 (Tobeto): the checkbox is pinned above the list (ourPinTabs)
    local toggle=skillsWindow:getChildById('myotsNonZero') or g_ui.createWidget('CheckBox',panel)
    toggle.onCheckChange=nil
    toggle:setChecked(onlyNonZero)
    toggle.onCheckChange=function(widget,checked)
        g_settings.set('myotsAttrNonZero',checked)
        myotsAttributesKey=nil
        scheduleEvent(function() myotsAttributes(myotsAttributesLast) end,10)
    end
    -- 15.10.2026 (Tobeto): character values (live) on top of the list
    local live={{section='Character'}}
    for _,k in ipairs(OUR_LIVE_KEYS) do live[#live+1]={key=k,label=OUR_LIVE_LABEL[k],value=1,unit='',live=true,tip=OUR_LIVE_TIP[k]} end
    local allRows={}
    for _,e in ipairs(live) do allRows[#allRows+1]=e end
    for _,e in ipairs(rows or {}) do allRows[#allRows+1]=e end
    local shownRows={}
    do
        local pendingHeading=nil
        for _,entry in ipairs(allRows) do
            if entry.section then pendingHeading=entry
            elseif not onlyNonZero or entry.live or (tonumber(entry.value) or 0)~=0 then
                if pendingHeading then shownRows[#shownRows+1]=pendingHeading;pendingHeading=nil end
                shownRows[#shownRows+1]=entry
            end
        end
    end
    for _,entry in ipairs(shownRows) do
        if entry.section then
            local heading=g_ui.createWidget('OurAttributeHeading',panel)
            local title=heading and heading:getChildById('title');if title then title:setText(tostring(entry.section)) end
            -- 17.10.2026 (Tobeto): the first heading uses the fixed line above the list
            if panel:getChildCount()==1 and heading then
                for _,ch in ipairs(heading:getChildren()) do if ch~=title then ch:hide() end end
                heading:setHeight(19)
            end
        else
            local widget=g_ui.createWidget('OurAttributeRow',panel)
            local key=tostring(entry.key or 'unknown')
            widget:setId('attribute_'..key)
            if entry.live then
                widget:getChildById('value'):setTextAutoResize(true)
                widget:getChildById('name'):setText(entry.label)
                widget:getChildById('name').myotsFull=entry.label
                widget:setTooltip(entry.label..'\n'..(entry.tip or ''))
                ourSetupPin(widget,key)
                goto continue
            end
            local short={critical='Critical chance',extradefense='Extra defense',lowdamage='Low HP damage',lowresist='Low HP resist',dodgephysical='Physical dodge',dodgemagic='Magic dodge',allskills='All skills',experience='Experience',potion='Potion bonus',hpregen='HP per tick',manaregen='Mana per tick',soulregen='Soul regen',speed='Bonus speed',speed_total='Speed',regen_hp='HP regen',regen_mana='Mana regen',resilience='PvP Mastery'}
            local label=tostring(entry.label or entry.key or 'Unknown')
            local name=widget and widget:getChildById('name');if name then name:setText(short[key] or label) end
            local value=tonumber(entry.value) or 0
            local unit=tostring(entry.unit or '')
            local text=unit:sub(1,2)==' /' and (string.format('%g',value)..unit) or (key=='speed_total' and string.format('%g',value)) or entry.unit=='%' and string.format('%.2f%%',value) or entry.unit=='x' and string.format('%gx',value) or entry.unit==' ms' and string.format('%g ms',value) or string.format('%+g',value)
            local valueWidget=widget and widget:getChildById('value');if valueWidget then valueWidget:setText(text);valueWidget:setColor(value==0 and '#777777' or '#ffffff') end
            if name then name.myotsFull=short[key] or label end
            widget:setTooltip(label..'\n'..(entry.tip or ''))
            if entry.icon and entry.icon~='' then
                local icon=widget and widget:getChildById('icon');if icon then icon:setImageSource('/game_cyclopedia/images/bestiary/icons/monster-icon-'..tostring(entry.icon)..'-resist');icon:show() end
                if name then name:setMarginLeft(14) end
            end
            ourSetupPin(widget,key)
        end
        ::continue::
    end
    pcall(ourUpdateLive)
    pcall(ourRefreshPinned)
    panel:setHeight(#allRows*17+10)
    local height=0;for _,w in ipairs(panel:getChildren())do height=height+w:getHeight()end;panel:setHeight(height)
    myotsFitAttributes()
    if not panel.myotsFitHooked then
        panel.myotsFitHooked=true
        connect(panel,{onGeometryChange=function() scheduleEvent(myotsFitAttributes,1) end})
    end
    updateHeight()
end

-- 10.10.2026: long names ("Elemental penetration") and wide values ("150.00%")
-- no longer run into each other: the value gets the width it needs and the
-- name is shortened with "..." when it does not fit (full name in the tooltip).
local myotsAbbrev={['Physical penetration']='Physical pen.',['Elemental penetration']='Elemental pen.',['Double attack chance']='Double attack',['Multi shot chance']='Multi shot',['Paralyze chance']='Paralyze',['Attack mana cost']='Attack spell cost',['Support mana cost']='Support spell cost',['Conjure mana cost']='Conjure spell cost'}
function myotsFitAttributes(panel)
    if not skillsWindow then return end
    panel=panel or skillsWindow:recursiveGetChildById('myotsDetails')
    if not panel or not panel:isVisible() then return end
    for _,row in ipairs(panel:getChildren()) do
        local name=row.getChildById and row:getChildById('name')
        local value=row.getChildById and row:getChildById('value')
        if name and value and name.myotsFull then
            value:setWidth(math.max(30,value:getTextSize().width+2))
            local room=row:getWidth()-value:getWidth()-4-(name:getMarginLeft() or 0)
            local text=name.myotsFull
            name:setText(text)
            if room>0 and name:getTextSize().width>room and myotsAbbrev[text] then text=myotsAbbrev[text];name:setText(text) end
            while room>0 and #text>3 and name:getTextSize().width>room do
                text=text:sub(1,#text-1):gsub('%s+$','')
                name:setText(text..'...')
            end
        end
    end
end


-- 15.10.2026 (Tobeto): live character rows and pinned attributes
OUR_LIVE_KEYS={'live_hp','live_mana','live_soul','live_cap'}
OUR_LIVE_LABEL={live_hp='Hit Points',live_mana='Mana',live_soul='Soul Points',live_cap='Capacity'}
OUR_LIVE_TIP={live_hp='Your hit points now / maximum.',live_mana='Your mana now / maximum.',live_soul='Your soul points.',live_cap='Free capacity (oz).'}
local function ourLiveText(key)
    local p=g_game.getLocalPlayer()
    if not p then return '-' end
    if key=='live_hp' then return comma_value(p:getHealth())..' / '..comma_value(p:getMaxHealth()) end
    if key=='live_mana' then return comma_value(p:getMana())..' / '..comma_value(p:getMaxMana()) end
    if key=='live_soul' then return tostring(p:getSoul()) end
    if key=='live_cap' then return comma_value(p:getFreeCapacity()) end
    return '-'
end
local function ourAttrText(entry)
    local key=tostring(entry.key or '')
    if OUR_LIVE_LABEL[key] then return ourLiveText(key),'#ffffff' end
    local value=tonumber(entry.value) or 0
    local unit=tostring(entry.unit or '')
    local text=unit:sub(1,2)==' /' and (string.format('%g',value)..unit) or (key=='speed_total' and string.format('%g',value)) or entry.unit=='%' and string.format('%.2f%%',value) or entry.unit=='x' and string.format('%gx',value) or entry.unit==' ms' and string.format('%g ms',value) or string.format('%+g',value)
    return text,(value==0 and '#777777' or '#ffffff')
end
function ourUpdateLive()
    if not skillsWindow then return end
    for _,key in ipairs(OUR_LIVE_KEYS) do
        for _,id in ipairs({'attribute_'..key,'pinned_'..key}) do
            local w=skillsWindow:recursiveGetChildById(id)
            if w then local v=w:getChildById('value');if v then v:setText(ourLiveText(key));v:setColor('#ffffff') end end
        end
    end
end
local function ourPins()
    local list=g_settings.getList('ourPinnedAttrs') or {}
    local set={};for _,k in ipairs(list) do set[k]=true end
    return list,set
end
function ourTogglePin(key)
    local list,set=ourPins()
    local out={}
    if set[key] then for _,k in ipairs(list) do if k~=key then out[#out+1]=k end end
    else for _,k in ipairs(list) do out[#out+1]=k end;out[#out+1]=key end
    g_settings.setList('ourPinnedAttrs',out)
    -- pin icons of the attribute rows follow
    if skillsWindow then
        local panel=skillsWindow:recursiveGetChildById('myotsDetails')
        if panel then for _,row in ipairs(panel:getChildren()) do if row.ourPinKey then ourPaintPin(row,false) end end end
    end
    ourRefreshPinned()
end
function ourPaintPin(row,hovered)
    local pin=row:getChildById('pin');if not pin then return end
    local _,set=ourPins()
    local pinned=set[row.ourPinKey]
    local show=pinned or hovered
    pin:setVisible(show and true or false)
    pin:setImageColor((pinned or pin:isHovered()) and '#44d040' or '#6a6a6a')
    local shift=show and 12 or 0
    local icon=row:getChildById('icon')
    local name=row:getChildById('name')
    if icon then icon:setMarginLeft(shift) end
    if name then name:setMarginLeft((icon and icon:isVisible()) and (shift+14) or shift) end
end
function ourSetupPin(row,key)
    row.ourPinKey=key
    local pin=row:getChildById('pin')
    if not pin then return end
    row.onHoverChange=function(w,hovered) ourPaintPin(w,hovered) end
    pin.onHoverChange=function(w,hovered)
        local _,set=ourPins()
        w:setTooltip(set[key] and 'Unpin it from the skills window' or 'Pin it to the skills window')
        ourPaintPin(row,true)
    end
    pin.onClick=function() ourTogglePin(key);ourPaintPin(row,true);return true end
    ourPaintPin(row,false)
end
function ourRefreshPinned()
    if not skillsWindow then return end
    local contents=skillsWindow:getChildById('contentsPanel')
    if not contents then return end
    local panel=contents:getChildById('ourPinned')
    if not panel then
        panel=g_ui.createWidget('Panel',contents)
        panel:setId('ourPinned')
        panel:setLayout(UIVerticalLayout.create(panel))
    end
    panel:destroyChildren()
    local list=ourPins()
    local byKey={}
    for _,e in ipairs(myotsAttributesLast or {}) do if e.key then byKey[tostring(e.key)]=e end end
    local n=0
    if #list>0 then
        local sep=g_ui.createWidget('HorizontalSeparator',panel);sep:setMarginTop(4);sep:setMarginBottom(3);sep:setHeight(2)
    end
    for _,key in ipairs(list) do
        local entry=byKey[key] or (OUR_LIVE_LABEL[key] and {key=key,label=OUR_LIVE_LABEL[key],tip=OUR_LIVE_TIP[key]})
        local row=g_ui.createWidget('OurAttributeRow',panel)
        row:setId('pinned_'..key)
        row:getChildById('value'):setTextAutoResize(true)
        local label=entry and tostring(entry.label or key) or key
        local short={critical='Critical chance',regen_hp='HP regen',regen_mana='Mana regen',speed_total='Speed'}
        row:getChildById('name'):setText(short[key] or label)
        -- 16.10.2026 (Tobeto): long names end with "..." (full name in the tooltip)
        row:getChildById('name').myotsFull=short[key] or label
        -- right click: unpin (one pinned row was hard to unpin with the small pin)
        row.onMouseRelease=function(w,pos,button)
            if button==MouseRightButton then
                local menu=g_ui.createWidget('PopupMenu');menu:setGameMenu(true)
                menu:addOption('Unpin',function() ourTogglePin(key) end)
                menu:display(pos);return true
            end
            return false
        end
        if entry then
            local text,color=ourAttrText(entry)
            row:getChildById('value'):setText(text);row:getChildById('value'):setColor(color)
            row:setTooltip(label..'\n'..tostring(entry.tip or ''))
        else
            row:getChildById('value'):setText('...')
        end
        ourSetupPin(row,key)
        n=n+1
    end
    -- 17.10.2026 (Tobeto): the window ends with the closing lines of the menus
    -- (after the pinned attributes, or after the last skill when nothing is pinned)
    do local finish=g_ui.createWidget('HorizontalSeparator',panel);finish:setId('ourFinish');finish:setMarginTop(4);finish:setHeight(2) end
    panel:setHeight(n>0 and (n*17+9+12) or 12)
    panel:setVisible(not myotsAttributesShown)
    if n>0 then scheduleEvent(function() if not panel:isDestroyed() then myotsFitAttributes(panel) end end,1) end
    panel.myotsPreviousVisible=nil
    if n>0 and not myotsAttributesLast and g_game.isOnline() and not ourPinSyncAsked then
        ourPinSyncAsked=true
        local protocol=g_game.getProtocolGame();if protocol then protocol:sendExtendedOpcode(107,'sync') end
    end
    updateHeight()
end
