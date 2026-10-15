gameRootPanel = nil
gameMapPanel = nil
gameMainRightPanel = nil
gameRightPanel = nil
gameRightExtraPanel = nil
gameLeftPanel = nil
gameLeftExtraPanel = nil
gameSelectedPanel = nil
panelsList = {}
panelsRadioGroup = nil
gameTopPanel = nil
gameBottomStatsBarPanel = nil
gameBottomPanel = nil
showTopMenuButton = nil
logoutButton = nil
logOutMainButton = nil
mouseGrabberWidget = nil
countWindow = nil
logoutWindow = nil
exitWindow = nil
bottomSplitter = nil
-- timestamp of the last manual keyboard walk, refreshed by game_walk and read
-- by consumers (e.g. game_bot) to pause automation while the player walks;
-- defined here so it is always present whenever this module is loaded
lastManualWalk = 0
limitedZoom = false
currentViewMode = 0
leftIncreaseSidePanels = nil
leftDecreaseSidePanels = nil
rightIncreaseSidePanels = nil
rightDecreaseSidePanels = nil

gameBottomActionPanel = nil
gameLeftActionPanel = nil
gameRightActionPanel = nil
gameBottomLockPanel = nil
gameRightLockPanel = nil
gameLeftLockPanel = nil

hookedMenuOptions = {}
focusReason = {}
local lastStopAction = 0
local mobileConfig = {
    mobileWidthJoystick = 0,
    mobileWidthShortcuts = 0,
    mobileHeightJoystick = 0,
    mobileHeightShortcuts = 0
}
local isExtendedViewActive = false

local function updateSidePanelButtons()
    leftIncreaseSidePanels:setEnabled(not modules.client_options.getOption('showLeftExtraPanel'))
    if g_platform.isMobile() then
        leftDecreaseSidePanels:setEnabled(false)
    else
        leftDecreaseSidePanels:setEnabled(
            modules.client_options.getOption('showLeftPanel') or
            modules.client_options.getOption('showLeftExtraPanel'))
    end
    rightIncreaseSidePanels:setEnabled(not modules.client_options.getOption('showRightExtraPanel'))
    rightDecreaseSidePanels:setEnabled(modules.client_options.getOption('showRightExtraPanel'))
end

local function applyMobileMargins()
    if g_platform.isMobile() then
        gameRightPanel:setMarginBottom(mobileConfig.mobileHeightShortcuts)
        gameLeftPanel:setMarginBottom(mobileConfig.mobileHeightJoystick)
    end
end

function init()
    g_ui.importStyle('styles/countwindow')
    g_ui.importStyle('styles/countStashWindow')

    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd,
        onLoginAdvice = onLoginAdvice
    }, true)

    -- Call load AFTER game window has been created and
    -- resized to a stable state, otherwise the saved
    -- settings can get overridden by false onGeometryChange
    -- events
    if g_app.hasUpdater() then
        connect(g_app, {
            onUpdateFinished = load,
        })
    else
        connect(g_app, {
            onRun = load,
        })
    end

    connect(g_app, {
        onExit = save
    })

    gameRootPanel = g_ui.displayUI('gameinterface')
    gameRootPanel:hide()
    gameRootPanel:lower()
    gameRootPanel.onGeometryChange = updateStretchShrink

    mouseGrabberWidget = gameRootPanel:getChildById('mouseGrabber')
    mouseGrabberWidget.onMouseRelease = onMouseGrabberRelease

    bottomSplitter = gameRootPanel:getChildById('bottomSplitter')
    gameMapPanel = gameRootPanel:getChildById('gameMapPanel')
    gameMainRightPanel = gameRootPanel:getChildById('gameMainRightPanel')
    -- OurTibia (04.10.2026): windows (e.g. a backpack) can be dropped under the
    -- equipment; the main panel grows/shrinks with what is in it.
    if not ourMainFitEvent then
        ourMainFitEvent = cycleEvent(function()
            local p = gameMainRightPanel
            if not p or p:isDestroyed() or not p:isVisible() or p:getHeight() == 0 then return end
            local extra = false
            local sum = 0
            for _, ch in ipairs(p:getChildren()) do
                if ch:isVisible() then sum = sum + ch:getHeight() + ch:getMarginTop() + ch:getMarginBottom() end
                if ch:getClassName() == 'UIMiniWindow' or (ch.getId and ch:getId():find('^container')) then extra = true end
            end
            if extra or p.ourGrown then
                local h = sum + p:getPaddingTop() + p:getPaddingBottom() + 1
                if p:getHeight() ~= h then p:setHeight(h); p.ourGrown = extra end
            end
        end, 300)
    end
    gameRightPanel = gameRootPanel:getChildById('gameRightPanel')
    gameRightExtraPanel = gameRootPanel:getChildById('gameRightExtraPanel')
    gameLeftExtraPanel = gameRootPanel:getChildById('gameLeftExtraPanel')
    gameLeftPanel = gameRootPanel:getChildById('gameLeftPanel')
    gameBottomPanel = gameRootPanel:getChildById('gameBottomPanel')
    -- OurTibia (01.10.2026): the chat did not follow the splitter (its anchor
    -- layout was not refreshed when the bottom panel moved). Re-fill it.
    connect(gameBottomPanel, { onGeometryChange = function(self)
        local c = self:getChildById('consolePanel')
        if c and (c:getY() ~= self:getY() or c:getHeight() ~= self:getHeight()) then
            c:breakAnchors()
            c:fill('parent')
        end
    end })
    gameTopPanel = gameRootPanel:getChildById('gameTopPanel')
    gameBottomStatsBarPanel = gameRootPanel:getChildById('gameBottomStatsBarPanel')

    leftIncreaseSidePanels = gameRootPanel:getChildById('leftIncreaseSidePanels')
    leftDecreaseSidePanels = gameRootPanel:getChildById('leftDecreaseSidePanels')
    rightIncreaseSidePanels = gameRootPanel:getChildById('rightIncreaseSidePanels')
    rightDecreaseSidePanels = gameRootPanel:getChildById('rightDecreaseSidePanels')

    gameBottomActionPanel = gameRootPanel:getChildById('gameBottomActionPanel')
    gameRightActionPanel = gameRootPanel:getChildById('gameRightActionPanel')
    gameLeftActionPanel = gameRootPanel:getChildById('gameLeftActionPanel')
    gameBottomLockPanel = gameRootPanel:recursiveGetChildById('bottomLock')
    gameRightLockPanel = gameRootPanel:recursiveGetChildById('rightLock')
    gameLeftLockPanel = gameRootPanel:recursiveGetChildById('leftLock')

    updateSidePanelButtons()
    applyMobileMargins()

    panelsList = { {
        panel = gameRightPanel,
        checkbox = gameRootPanel:getChildById('gameSelectRightColumn')
    }, {
        panel = gameRightExtraPanel,
        checkbox = gameRootPanel:getChildById('gameSelectRightExtraColumn')
    }, {
        panel = gameLeftPanel,
        checkbox = gameRootPanel:getChildById('gameSelectLeftColumn')
    }, {
        panel = gameLeftExtraPanel,
        checkbox = gameRootPanel:getChildById('gameSelectLeftExtraColumn')
    } }

    panelsRadioGroup = UIRadioGroup.create()
    for k, v in pairs(panelsList) do
        panelsRadioGroup:addWidget(v.checkbox)
        connect(v.checkbox, {
            onCheckChange = onSelectPanel
        })
    end
    panelsRadioGroup:selectWidget(panelsList[1].checkbox)

    logoutButton = modules.client_topmenu.addTopRightToggleButton('logoutButton', tr('Exit'), '/images/topbuttons/logout',
        tryLogout, true)

    gameMapPanel.onClick = toggleInternalFocus
    gameRightPanel.onClick = toggleInternalFocus
    gameRightExtraPanel.onClick = toggleInternalFocus
    gameLeftExtraPanel.onClick = toggleInternalFocus
    gameLeftPanel.onClick = toggleInternalFocus
    gameBottomPanel.onClick = toggleInternalFocus

    showTopMenuButton = gameMapPanel:getChildById('showTopMenuButton')
    showTopMenuButton.onClick = function()
        modules.client_topmenu.toggle()
    end

    bindKeys()

    if g_game.isOnline() then
        show()
    end

    StatsBar.init()
end

function bindKeys()
    gameRootPanel:setAutoRepeatDelay(50)

    g_keyboard.bindKeyPress('Ctrl+=', function()
        if g_game.getClientVersion()==1098 then return end
        gameMapPanel:zoomIn()
    end, gameRootPanel)
    g_keyboard.bindKeyPress('Ctrl+-', function()
        if g_game.getClientVersion()==1098 then return end
        gameMapPanel:zoomOut()
    end, gameRootPanel)

    Keybind.new("Movement", "Stop All Actions", "Escape", "", true)
    Keybind.bind("Movement", "Stop All Actions", {
        {
            type = KEY_PRESS,
            callback = function()
                if lastStopAction + 50 > g_clock.millis() then return end
                lastStopAction = g_clock.millis()
                local clearClick = OurClearMapClick or (modules.game_walk and modules.game_walk.OurClearMapClick)
                if clearClick then clearClick() end
                g_game.cancelAttackAndFollow()
            end,
        }
    }, gameRootPanel)

    Keybind.new("Misc", "Logout", "Ctrl+L", "Ctrl+Q")
    Keybind.bind("Misc", "Logout", {
        {
            type = KEY_PRESS,
            callback = function() tryLogout(false) end,
        }
    }, gameRootPanel)

    Keybind.new("UI", "Clear All Texts", "Ctrl+W", "")
    Keybind.bind("UI", "Clear All Texts", {
        {
            type = KEY_DOWN,
            callback = function()
                g_map.cleanTexts()
                modules.game_textmessage.clearMessages()
            end,
        }
    }, gameRootPanel)

    g_keyboard.bindKeyDown('Ctrl+.', nextViewMode, gameRootPanel)
end

function terminate()
    StatsBar.terminate()

    hide()
    if g_app.hasUpdater() then
        disconnect(g_app, {
            onUpdateFinished = load,
        })
    else
        disconnect(g_app, {
            onRun = load,
        })
    end
    disconnect(g_app, {
        onExit = save,
    })

    hookedMenuOptions = {}

    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd,
        onLoginAdvice = onLoginAdvice
    })

    for k, v in pairs(panelsList) do
        disconnect(v.checkbox, {
            onCheckChange = onSelectPanel
        })
    end

    logoutButton:destroy()
    gameRootPanel:destroy()
    Keybind.delete("Movement", "Stop All Actions")
    Keybind.delete("Misc", "Logout")
    Keybind.delete("UI", "Clear All Texts")
end

function onGameStart()
    show()
    updateSidePanelButtons()
    applyMobileMargins()
    -- OurTibia (15.10.2026): phones get a low chat panel (more map); the
    -- player can still drag the splitter up
    if g_platform.isMobile() and not mobileSplitterSet then
        mobileSplitterSet = true
        addEvent(function() bottomSplitter:setMarginBottom(160) end)
    end
end

function onGameEnd()
    hide()
end

function show()
    connect(g_app, {
        onClose = tryExit
    })
    modules.client_background.hide()
    gameRootPanel:show()
    gameRootPanel:focus()
    gameMapPanel:followCreature(g_game.getLocalPlayer())

    updateStretchShrink()
    logoutButton:setTooltip(tr('Logout'))

    if g_platform.isMobile() then
        mobileConfig.mobileWidthJoystick = modules.game_joystick.getPanel():getWidth()
        mobileConfig.mobileWidthShortcuts = modules.game_shortcuts.getPanel():getWidth()
        mobileConfig.mobileHeightJoystick = modules.game_joystick.getPanel():getHeight()
        mobileConfig.mobileHeightShortcuts = modules.game_shortcuts.getPanel():getHeight()
    end

    setupViewMode(0)
    if g_platform.isMobile() or g_gameConfig.isExtendedViewUI() then
        setupViewMode(1)
        setupViewMode(2)
    end

    addEvent(function()
        if not limitedZoom or g_game.isGM() then
            gameMapPanel:setMaxZoomOut(513)
            gameMapPanel:setLimitVisibleRange(false)
        else
            gameMapPanel:setMaxZoomOut(11)
            gameMapPanel:setLimitVisibleRange(true)
        end
    end)
end

function hide()
    setupViewMode(0)

    disconnect(g_app, {
        onClose = tryExit
    })
    logoutButton:setTooltip(tr('Exit'))

    if logoutWindow then
        logoutWindow:destroy()
        logoutWindow = nil
    end
    if exitWindow then
        exitWindow:destroy()
        exitWindow = nil
    end
    if countWindow then
        countWindow:destroy()
        countWindow = nil
    end
    gameRootPanel:hide()
    modules.client_background.show()
end

function save()
    local settings = {}
    settings.splitterMarginBottom = bottomSplitter:getMarginBottom()
    g_settings.setNode('game_interface', settings)
end

function load()
    local settings = g_settings.getNode('game_interface')
    if settings then
        if settings.splitterMarginBottom then
            bottomSplitter:setMarginBottom(settings.splitterMarginBottom)
        end
    end
end

function onLoginAdvice(message)
    displayInfoBox(tr('For Your Information'), message)
end

function forceExit()
    g_game.cancelLogin()
    scheduleEvent(exit, 10)
    return true
end

function tryExit()
    if exitWindow then
        return true
    end

    local exitFunc = function()
        g_game.safeLogout()
        forceExit()
    end
    local logoutFunc = function()
        g_game.safeLogout()
        exitWindow:destroy()
        exitWindow = nil
    end
    local cancelFunc = function()
        exitWindow:destroy()
        exitWindow = nil
    end

    exitWindow = displayGeneralBox(tr('Exit'), tr(
            'If you shut down the program, your character might stay in the game.\nClick on \'Logout\' to ensure that you character leaves the game properly.\nClick on \'Exit\' if you want to exit the program without logging out your character.'),
        {
            {
                text = tr('Cancel'),
                callback = cancelFunc
            },
            {
                text = tr('Logout'),
                callback = logoutFunc
            },
            {
                text = tr('Force Exit'),
                callback = exitFunc
            },
            anchor = AnchorHorizontalCenter
        }, logoutFunc, cancelFunc)

    return true
end

function tryLogout(prompt)
    if type(prompt) ~= 'boolean' then
        prompt = true
    end
    if not g_game.isOnline() then
        exit()
        return
    end

    if logoutWindow then
        return
    end

    local msg, yesCallback
    if not g_game.isConnectionOk() then
        msg =
        'Your connection is failing, if you logout now your character will be still online, do you want to force logout?'

        yesCallback = function()
            g_game.forceLogout()
            if logoutWindow then
                logoutWindow:destroy()
                logoutWindow = nil
            end
        end
    else
        msg = 'Are you sure you want to logout?'

        yesCallback = function()
            g_game.safeLogout()
            if logoutWindow then
                logoutWindow:destroy()
                logoutWindow = nil
            end
        end
    end

    local noCallback = function()
        logoutWindow:destroy()
        logoutWindow = nil
    end

    if prompt then
        logoutWindow = displayGeneralBox(tr('Logout'), tr(msg), {
            {
                text = tr('No'),
                callback = noCallback
            },
            {
                text = tr('Yes'),
                callback = yesCallback
            },
            anchor = AnchorHorizontalCenter
        }, yesCallback, noCallback)
    else
        yesCallback()
    end
end

function updateStretchShrink()
    if modules.client_options.getOption('dontStretchShrink') and not alternativeView then
        gameMapPanel:setVisibleDimension({
            width = 15,
            height = 11
        })

        -- Set gameMapPanel size to height = 11 * 32 + 2
        bottomSplitter:setMarginBottom(bottomSplitter:getMarginBottom() + (gameMapPanel:getHeight() - 32 * 11) - 10)
    end
    -- Update action bar layout when window geometry changes
    if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
        addEvent(function()
            modules.game_actionbar.updateVisibleWidgetsExternal()
        end)
    end
end

function onMouseGrabberRelease(self, mousePosition, mouseButton)
    if selectedThing == nil then
        return false
    end
    if mouseButton == MouseLeftButton then
        local clickedWidget = gameRootPanel:recursiveGetChildByPos(mousePosition, false)
        if clickedWidget then
            if selectedType == 'use' then
                onUseWith(clickedWidget, mousePosition)
            elseif selectedType == 'trade' then
                onTradeWith(clickedWidget, mousePosition)
            elseif selectedType == 'selectItem' and selectedCallback then
                local item, mapWidget = nil, clickedWidget
                -- Resolve overlay children back to the actual inventory or map widget.
                local widget = clickedWidget
                while widget and widget ~= gameRootPanel do
                    local className = widget:getClassName()
                    if not item and widget.getItem then
                        local ok, found = pcall(widget.getItem, widget)
                        if ok and found then item = found end
                    end
                    if className == 'UIGameMap' then mapWidget = widget; break end
                    widget = widget:getParent()
                end
                if not item and gameRootPanel.recursiveGetChildrenByPos then
                    -- Inventory/container slots can have overlay widgets above the item.
                    for _, w in ipairs(gameRootPanel:recursiveGetChildrenByPos(mousePosition) or {}) do
                        if w.getItem and w:getClassName() == 'UIItem' then
                            local ok, found = pcall(w.getItem, w)
                            if ok and found then item = found; break end
                        end
                    end
                end
                if not item and mapWidget and mapWidget:getClassName() == 'UIGameMap' then
                    local tile = mapWidget:getTile(mousePosition)
                    if tile then
                        local useItem, lookItem = tile:getTopUseThing(), tile:getTopLookThing()
                        if useItem and useItem:isContainer() then item = useItem
                        elseif lookItem and lookItem:isContainer() then item = lookItem
                        elseif selectedAnyItem then
                            -- Autoloot "[+] Add an item": any item on the ground.
                            if useItem and useItem:isItem() and not useItem:isGround() then item = useItem
                            elseif lookItem and lookItem:isItem() and not lookItem:isGround() then item = lookItem end
                        end
                    end
                end
                local ok, err = pcall(selectedCallback, item)
                if not ok then g_logger.error('item selection callback: ' .. tostring(err)) end
            end
        end
    end

    selectedThing = nil
    selectedType = nil
    selectedCallback = nil
    -- Restore cursor
    if modules.client_options and modules.client_options.getOption('nativeCursor') then
        g_window.restoreMouseCursor()
    else
        g_mouse.popCursor('target')
    end
    self:ungrabMouse()
    return true
end

function onUseWith(clickedWidget, mousePosition)
    if clickedWidget:getClassName() == 'UIGameMap' then
        local tile = clickedWidget:getTile(mousePosition)
        if tile then
            if selectedThing:isFluidContainer() or selectedThing:isMultiUse() then
                g_game.useWith(selectedThing, tile:getTopMultiUseThing())
            else
                g_game.useWith(selectedThing, tile:getTopUseThing())
            end
        end
    elseif clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
        g_game.useWith(selectedThing, clickedWidget:getItem())
    elseif clickedWidget:getClassName() == 'UICreatureButton' then
        local creature = clickedWidget:getCreature()
        if creature then
            g_game.useWith(selectedThing, creature)
        end
    end
end

function onTradeWith(clickedWidget, mousePosition)
    if clickedWidget:getClassName() == 'UIGameMap' then
        local tile = clickedWidget:getTile(mousePosition)
        if tile then
            g_game.requestTrade(selectedThing, tile:getTopCreature())
        end
    elseif clickedWidget:getClassName() == 'UICreatureButton' then
        local creature = clickedWidget:getCreature()
        if creature then
            g_game.requestTrade(selectedThing, creature)
        end
    end
end

function startUseWith(thing)
    if not thing then
        return
    end
    if g_ui.isMouseGrabbed() then
        if selectedThing then
            selectedThing = thing
            selectedType = 'use'
        end
        return
    end
    selectedType = 'use'
    selectedThing = thing
    mouseGrabberWidget:grabMouse()
    -- Use native cursor when enabled, otherwise use custom cursor
    if modules.client_options and modules.client_options.getOption('nativeCursor') then
        g_window.setSystemCursor('cross')
    else
        g_mouse.pushCursor('target')
    end
end

function startItemSelection(callback, anyItem)
    if type(callback) ~= 'function' then return end
    if g_ui.isMouseGrabbed() then return end
    selectedAnyItem = anyItem and true or false
    selectedType = 'selectItem'
    selectedThing = true
    selectedCallback = callback
    mouseGrabberWidget:grabMouse()
    if modules.client_options and modules.client_options.getOption('nativeCursor') then
        g_window.setSystemCursor('cross')
    else
        g_mouse.pushCursor('target')
    end
end

function startTradeWith(thing)
    if not thing then
        return
    end
    if g_ui.isMouseGrabbed() then
        if selectedThing then
            selectedThing = thing
            selectedType = 'trade'
        end
        return
    end
    selectedType = 'trade'
    selectedThing = thing
    mouseGrabberWidget:grabMouse()
    -- Use native cursor when enabled, otherwise use custom cursor
    if modules.client_options and modules.client_options.getOption('nativeCursor') then
        g_window.setSystemCursor('cross')
    else
        g_mouse.pushCursor('target')
    end
end

function isMenuHookCategoryEmpty(category)
    if category then
        for _, opt in pairs(category) do
            if opt then
                return false
            end
        end
    end
    return true
end

function addMenuHook(category, name, callback, condition, shortcut)
    if not hookedMenuOptions[category] then
        hookedMenuOptions[category] = {}
    end
    hookedMenuOptions[category][name] = {
        callback = callback,
        condition = condition,
        shortcut = shortcut
    }
end

function removeMenuHook(category, name)
    if not name then
        hookedMenuOptions[category] = {}
    else
        hookedMenuOptions[category][name] = nil
    end
end

function createThingMenu(menuPosition, lookThing, useThing, creatureThing)
    if not g_game.isOnline() then
        return
    end

    local menu = g_ui.createWidget('PopupMenu')
    menu:setGameMenu(true)

    local classic = modules.client_options.getOption('classicControl')
    local smartLeftClick = modules.client_options.getOption('smartLeftClick')
    local mobile = g_platform.isMobile()
    local shortcut = nil

    if not classic and not mobile and not smartLeftClick then
        shortcut = '(Shift)'
    else
        shortcut = nil
    end
    if lookThing then
        menu:addOption(tr('Look'), function()
            g_game.look(lookThing)
        end, shortcut)
        local clientVersion = g_game.getClientVersion()
        local canInspect = lookThing:isItem() and not lookThing:isNotMoveable() and lookThing:isPickupable()
        if clientVersion >= 1281 and modules.game_inspect and (lookThing:isCreature() or canInspect) then
            menu:addOption(tr('Inspect'), function()
                if lookThing:isCreature() then
                    g_game.inspectCharacter(lookThing:getId(), InspectCreaturesTypes.INSPECT_CREATURE)
                elseif canInspect then
                    local pos = lookThing:getPosition()
                    if pos and pos.x and pos.y and pos.z then
                        g_game.inspectionNormalObject(pos)
                    else
                        g_game.inspectionObject(InspectObjectTypes.INSPECT_CYCLOPEDIA, lookThing:getId())
                    end
                end
            end, shortcut)
        end
        if clientVersion >= 1310 and canInspect and modules.game_cyclopedia and lookThing:getCyclopediaType() > 0 then
            menu:addOption(tr('Cyclopedia'), function()
                modules.game_cyclopedia.Cyclopedia.openItem(lookThing:getId())
            end, shortcut)
        end
        if clientVersion >= 1511 and modules.game_proficiency and lookThing:getProficiencyId() > 0 then
            menu:addOption(tr("Weapon Proficiency"), function()
                modules.game_proficiency.requestOpenWindow(lookThing)
            end, shortcut)
        end
    end

    if not classic and not mobile then
        shortcut = '(Ctrl)'
    else
        shortcut = nil
    end
    local identifyAdded = false
    if useThing then
        local rarityHud = modules.game_myotshud
        if useThing:isItem() and rarityHud and rarityHud.isUnidentifiedRarityItem and
           rarityHud.isUnidentifiedRarityItem(useThing) then
            menu:addOption(tr('Identify item'), function()
                identifyRarityItem(useThing)
            end)
            identifyAdded = true
        end
        if useThing:isContainer() then
            if useThing:getParentContainer() then
                menu:addOption(tr('Open'), function()
                    g_game.open(useThing, useThing:getParentContainer())
                end, shortcut)
                menu:addOption(tr('Open in new window'), function()
                    g_game.open(useThing)
                end)
            else
                menu:addOption(tr('Open'), function()
                    g_game.open(useThing)
                end, shortcut)
            end
        else
            if useThing:isMultiUse() then
                menu:addOption(tr('Use with ...'), function()
                    startUseWith(useThing)
                end, shortcut)
            else
                menu:addOption(tr('Use'), function()
                    g_game.use(useThing)
                end, shortcut)
            end
        end

        if useThing:isRotateable() then
            menu:addOption(tr('Rotate'), function()
                g_game.rotate(useThing)
            end)
        end

        local onWrapItem = function()
            g_game.wrap(useThing)
        end
        if useThing:isWrapable() then
            menu:addOption(tr('Wrap'), onWrapItem)
        end
        if useThing:isUnwrapable() then
            menu:addOption(tr('Unwrap'), onWrapItem)
        end

        if g_game.getFeature(GameBrowseField) and useThing and useThing:getPosition() and useThing:getPosition().x ~= 0xffff then
            menu:addOption(tr('Browse Field'), function()
                g_game.browseField(useThing:getPosition())
            end)
        end
        if useThing:isLyingCorpse() and g_game.getFeature(GameThingQuickLoot) and modules.game_quickloot and useThing:getPosition().x ~= 0xffff then
            menu.addOption(menu, tr("Loot corpse"), function()
                g_game.sendQuickLoot(1, useThing)
            end)
        end
    end

    -- Unidentified rarity items can also be identified on the ground.  The
    -- server action validates range and the item's unidentified state.
    local groundHud = modules.game_myotshud
    local unidentifiedGround = not identifyAdded and lookThing and lookThing:isItem() and ((groundHud and groundHud.isUnidentifiedRarityItem and groundHud.isUnidentifiedRarityItem(lookThing)) or not lookThing:isContainer() and
       not lookThing:isStackable() and ((lookThing.getActionId and lookThing:getActionId() == 45991) or
       (lookThing.getName and lookThing:getName() and lookThing:getName():lower():find('unidentified', 1, true))))
    if unidentifiedGround then
        menu:addOption(tr('Identify item'), function()
            identifyRarityItem(lookThing)
        end)
    end

    if lookThing and not lookThing:isCreature() and not lookThing:isNotMoveable() and lookThing:isPickupable() then
        menu:addSeparator()
        menu:addOption(tr('Trade with ...'), function()
            startTradeWith(lookThing)
        end)
    end

    if lookThing then
        local parentContainer = lookThing:getParentContainer()
        if parentContainer and parentContainer:hasParent() then
            menu:addOption(tr('Move up'), function()
                g_game.moveToParentContainer(lookThing, lookThing:getCount())
            end)
        end
    end

    if creatureThing then
        local localPlayer = g_game.getLocalPlayer()
        menu:addSeparator()

        if creatureThing:isLocalPlayer() then
            menu:addOption(tr("Set Outfit"), function() -- 15.10.2026 (Tobeto): was "Customise Character"
                g_game.requestOutfit()
            end)

            if g_game.getFeature(GamePrey) then
                menu:addOption(tr('Prey Dialog'), function()
                    modules.game_prey.show()
                end)
            end

            if g_game.getFeature(GamePlayerMounts) then
                if not localPlayer:isMounted() then
                    menu:addOption(tr('Mount'), function()
                        localPlayer:mount()
                    end)
                else
                    menu:addOption(tr('Dismount'), function()
                        localPlayer:dismount()
                    end)
                end
            end

            if creatureThing:isPartyMember() then
                if creatureThing:isPartyLeader() then
                    if creatureThing:isPartySharedExperienceActive() then
                        menu:addOption(tr('Disable Shared Experience'), function()
                            g_game.partyShareExperience(false)
                        end)
                    else
                        menu:addOption(tr('Enable Shared Experience'), function()
                            g_game.partyShareExperience(true)
                        end)
                    end
                end
                menu:addOption(tr('Leave Party'), function()
                    g_game.partyLeave()
                end)
            end
        else
            local localPosition = localPlayer:getPosition()
            if not classic and not mobile then
                shortcut = '(Alt)'
            else
                shortcut = nil
            end
            if creatureThing:getPosition().z == localPosition.z then
                if creatureThing:isNpc() then
                    menu:addOption(tr('Talk'), function()
                        g_game.talkPrivate(MessageModes.NpcTo, creatureThing:getName(), "@npc:"..creatureThing:getId()..":interact")
                    end)
                end

                if g_game.getAttackingCreature() ~= creatureThing then
                    menu:addOption(tr('Attack'), function()
                        g_game.attack(creatureThing)
                    end, shortcut)
                else
                    menu:addOption(tr('Stop Attack'), function()
                        g_game.cancelAttack()
                    end, shortcut)
                end

                if g_game.getFollowingCreature() ~= creatureThing then
                    menu:addOption(tr('Follow'), function()
                        g_game.follow(creatureThing)
                    end)
                else
                    menu:addOption(tr('Stop Follow'), function()
                        g_game.cancelFollow()
                    end)
                end
            end

            if creatureThing:isPlayer() then
                menu:addSeparator()
                local creatureName = creatureThing:getName()
                menu:addOption(tr('Message to %s', creatureName), function()
                    g_game.openPrivateChannel(creatureName)
                end)
                if modules.game_console.getOwnPrivateTab() then
                    menu:addOption(tr('Invite to private chat'), function()
                        g_game.inviteToOwnChannel(creatureName)
                    end)
                    menu:addOption(tr('Exclude from private chat'), function()
                        g_game.excludeFromOwnChannel(creatureName)
                    end) -- [TODO] must be removed after message's popup labels been implemented
                end
                if not localPlayer:hasVip(creatureName) then
                    menu:addOption(tr('Add to VIP list'), function()
                        g_game.addVip(creatureName)
                    end)
                end

                if modules.game_console.isIgnored(creatureName) then
                    menu:addOption(tr('Unignore') .. ' ' .. creatureName, function()
                        modules.game_console.removeIgnoredPlayer(creatureName)
                    end)
                else
                    menu:addOption(tr('Ignore') .. ' ' .. creatureName, function()
                        modules.game_console.addIgnoredPlayer(creatureName)
                    end)
                end

                local localPlayerShield = localPlayer:getShield()
                local creatureShield = creatureThing:getShield()

                if localPlayerShield == ShieldNone or localPlayerShield == ShieldWhiteBlue then
                    if creatureShield == ShieldWhiteYellow then
                        menu:addOption(tr('Join %s\'s Party', creatureThing:getName()), function()
                            g_game.partyJoin(creatureThing:getId())
                        end)
                    else
                        menu:addOption(tr('Invite to Party'), function()
                            g_game.partyInvite(creatureThing:getId())
                        end)
                    end
                elseif localPlayerShield == ShieldWhiteYellow then
                    if creatureShield == ShieldWhiteBlue then
                        menu:addOption(tr('Revoke %s\'s Invitation', creatureThing:getName()), function()
                            g_game.partyRevokeInvitation(creatureThing:getId())
                        end)
                    end
                elseif localPlayerShield == ShieldYellow or localPlayerShield == ShieldYellowSharedExp or
                    localPlayerShield == ShieldYellowNoSharedExpBlink or localPlayerShield == ShieldYellowNoSharedExp then
                    if creatureShield == ShieldWhiteBlue then
                        menu:addOption(tr('Revoke %s\'s Invitation', creatureThing:getName()), function()
                            g_game.partyRevokeInvitation(creatureThing:getId())
                        end)
                    elseif creatureShield == ShieldBlue or creatureShield == ShieldBlueSharedExp or creatureShield ==
                        ShieldBlueNoSharedExpBlink or creatureShield == ShieldBlueNoSharedExp then
                        menu:addOption(tr('Pass Leadership to %s', creatureThing:getName()), function()
                            g_game.partyPassLeadership(creatureThing:getId())
                        end)
                    else
                        menu:addOption(tr('Invite to Party'), function()
                            g_game.partyInvite(creatureThing:getId())
                        end)
                    end
                end
            end
        end

        if modules.game_ruleviolation.hasWindowAccess() and creatureThing:isPlayer() then
            menu:addSeparator()
            menu:addOption(tr('Rule Violation'), function()
                modules.game_ruleviolation.show(creatureThing:getName())
            end)
        end

        menu:addSeparator()
        menu:addOption(tr('Copy Name'), function()
            g_window.setClipboardText(creatureThing:getName())
        end)
    end

    -- hooked menu options
    for _, category in pairs(hookedMenuOptions) do
        if not isMenuHookCategoryEmpty(category) then
            menu:addSeparator()
            for name, opt in pairs(category) do
                if opt and opt.condition(menuPosition, lookThing, useThing, creatureThing) then
                    menu:addOption(name, function()
                        opt.callback(menuPosition, lookThing, useThing, creatureThing)
                    end, opt.shortcut)
                end
            end
        end
    end

    -- OurTibia (06.10.2026): auto-loot exclusions for any pickupable item.
    local exItem = useThing or lookThing
    local lootHud = modules.game_myotshud
    if not creatureThing and lootHud and lootHud.isLootExcluded and exItem and exItem.isItem and exItem:isItem()
        and exItem.isPickupable and exItem:isPickupable() then
        local exId = exItem:getId()
        -- 13.10.2026: only creature products (or items already on the list) get the option
        local exListed = lootHud.isLootExcluded(exId)
        if exListed or not lootHud.isLootProduct or lootHud.isLootProduct(exId) then
        menu:addSeparator()
        if exListed then
            menu:addOption('Allow auto-loot again', function() lootHud.setLootExcluded(exId, false) end)
        else
            menu:addOption('Exclude from auto-loot', function() lootHud.setLootExcluded(exId, true) end)
        end
        menu:addOption('Auto-loot exclusions...', function() lootHud.showLootExclusions() end)
        end
    end

    -- OurTibia (03.10.2026): Weapon Proficiency is always offered for weapons,
    -- even when its menu hook was lost (another module reloaded this one).
    local profHook = hookedMenuOptions.myotsProficiency and hookedMenuOptions.myotsProficiency['Weapon Proficiency']
    local profItem = useThing or lookThing
    if not profHook and modules.game_myotsprof and modules.game_myotsprof.isWeapon and profItem and profItem.isItem and profItem:isItem()
        and modules.game_myotsprof.isWeapon(profItem:getId()) then
        menu:addSeparator()
        menu:addOption('Weapon Proficiency', function() modules.game_myotsprof.open(profItem:getId()) end)
    end

    if modules.game_bot and useThing and useThing:isItem() then
        menu:addSeparator()
        local useThingId = useThing:getId()
        menu:addOption("ID: " .. useThingId, function() g_window.setClipboardText(useThingId) end)
    end

    if g_game.getFeature(GameThingQuickLoot) and modules.game_quickloot and lookThing and not lookThing:isCreature() and lookThing:isPickupable() then
        local quickLoot = modules.game_quickloot.QuickLoot
        menu.addSeparator(menu)

        if lookThing:isContainer() then
            menu.addOption(menu, tr("Manage Loot Containers"), function()
                quickLoot.toggle()
            end)
        end

        local lootExists = quickLoot.lootExists(lookThing:getId())
        local optionText = lootExists and "Remove from" or "Add to"
        local actionFunction = lootExists and quickLoot.removeLootList or quickLoot.addLootList

        menu.addOption(menu, tr(optionText .. " loot list"), function()
            actionFunction(lookThing:getId())
        end)
    end

    if g_game.getClientVersion() >= 1410 then
        if lookThing and not lookThing:isCreature() and not lookThing:isNotMoveable() and lookThing:isPickupable() then
            local player = g_game.getLocalPlayer()
            if player and player:isSupplyStashAvailable() then
                local itemTier = lookThing:getTier() or 0
                if itemTier <= 0 then
                    menu:addSeparator()
                    menu:addOption(tr("Stow"), function()
                        stashItem(lookThing)
                    end)
                    menu:addOption(tr("Stow all items of this type"), function()
                        g_game.stashStowItem(lookThing:getPosition(), lookThing:getId(), 0,
                            lookThing:getStackPos(), 2)
                    end)

                    local isContainer = lookThing:isContainer()
                    if isContainer then
                        menu:addOption(tr('Stow container\'s content'), function()
                            g_game.stashStowItem(lookThing:getPosition(), lookThing:getId(), 0,
                                lookThing:getStackPos(), 1)
                        end)
                    end
                end
            end
        end
    end

    menu:display(menuPosition)
end

function processMouseAction(menuPosition, mouseButton, autoWalkPos, lookThing, useThing, creatureThing, attackCreature)
    -- 06.10.2026: mouse side buttons (4/5) only fire their hotkeys.
    if mouseButton == 4 or mouseButton == 5 then return false end
    local keyboardModifiers = g_keyboard.getModifiers()
    -- 09.10.2026: Ctrl+Shift+left click is always Look (like Shift+left click), in every
    -- control mode. Before, it opened containers or fell through to nothing/autowalk.
    if mouseButton == MouseLeftButton and lookThing and not g_keyboard.isAltPressed()
        and (keyboardModifiers == KeyboardCtrlShiftModifier
            or (g_keyboard.isCtrlPressed() and g_keyboard.isShiftPressed())) then
        g_game.look(lookThing)
        return true
    end
    -- MyOTS: an unidentified rarity item is identified directly on a plain
    -- right click (also weapons; before the proficiency menu below).
    do
        local hud = modules.game_myotshud
        local thing = useThing or lookThing
        if mouseButton == MouseRightButton and keyboardModifiers == KeyboardNoModifier and not creatureThing
            and thing and hud and hud.isUnidentifiedRarityItem and hud.isUnidentifiedRarityItem(thing) then
            identifyRarityItem(thing)
            return true
        end
    end
    -- MyOTS: right-click on a weapon (inventory, backpack or ground) opens the
    -- item menu with "Weapon Proficiency" instead of using it.
    if mouseButton == MouseRightButton and keyboardModifiers == KeyboardNoModifier and useThing and not creatureThing
        and useThing.isItem and useThing:isItem() and modules.game_myotsprof and modules.game_myotsprof.isWeapon
        and modules.game_myotsprof.isWeapon(useThing:getId()) then
        createThingMenu(menuPosition, lookThing, useThing, creatureThing)
        return true
    end
    -- Right click on a tile with a monster/player: attacking has priority over
    -- opening a corpse or identifying an item lying under that creature.
    if mouseButton == MouseRightButton and keyboardModifiers == KeyboardNoModifier then
        local localPlayer = g_game.getLocalPlayer()
        local enemy = attackCreature or creatureThing
        if enemy and enemy ~= localPlayer and not enemy:isLocalPlayer() and not enemy:isNpc() then
            g_game.attack(enemy)
            return true
        end
    end
    local rarityHud = modules.game_myotshud
    local rarityThing = useThing or lookThing
    if mouseButton == MouseRightButton and keyboardModifiers == KeyboardNoModifier
        and rarityHud and rarityHud.isUnidentifiedRarityItem
        and rarityHud.isUnidentifiedRarityItem(rarityThing) then
        identifyRarityItem(rarityThing)
        return true
    end

    -- Open containers and corpses directly on an unmodified right click.
    -- Quickloot is kept on its explicit modifier/control-mode action; sending
    -- the 10.98 quickloot opcode here left corpses unopened on this server.
    if mouseButton == MouseRightButton and keyboardModifiers == KeyboardNoModifier then
        local openThing = useThing
        if not openThing or not (openThing:isContainer() or openThing:isLyingCorpse()) then
            if lookThing and (lookThing:isContainer() or lookThing:isLyingCorpse()) then
                openThing = lookThing
            else
                openThing = nil
            end
        end
        if openThing then
            if openThing:getParentContainer() then
                g_game.open(openThing, openThing:getParentContainer())
            else
                g_game.open(openThing)
            end
            return true
        end
    end

    local smartLeftClick = modules.client_options.getOption('smartLeftClick')
    local classicControls = modules.client_options.getOption('classicControl')

    -- Classic controls: right-click on NPC says "hi"
    if creatureThing and creatureThing:isNpc() and mouseButton == MouseRightButton and 
    keyboardModifiers == KeyboardNoModifier then
        -- In classic controls, always allow NPC interaction
        -- In non-classic controls, check the talkOnRightClick option
        if true then -- Direct NPC interaction is available in both control schemes.
            local player = g_game.getLocalPlayer()
            if player then
                local playerPos = player:getPosition()
                local npcPos = creatureThing:getPosition()
                if playerPos.z == npcPos.z then
                    local dist = math.max(math.abs(playerPos.x - npcPos.x), math.abs(playerPos.y - npcPos.y))
                    if dist <= 3 then
                        g_game.talkPrivate(MessageModes.NpcTo, creatureThing:getName(), "@npc:"..creatureThing:getId()..":interact")
                        return true
                    end
                end
            end
        end
    end

    if g_platform.isMobile() then
        if mouseButton == MouseRightButton then
            createThingMenu(menuPosition, lookThing, useThing, creatureThing)
            return true
        end
        local shortcut = modules.game_shortcuts.getShortcut()
        if shortcut == "look" then
            if lookThing then
                modules.game_shortcuts.resetShortcuts()
                g_game.look(lookThing)
                return true
            end
            return true
        elseif shortcut == "use" then
            if useThing then
                modules.game_shortcuts.resetShortcuts()
                if useThing:isContainer() then
                    if useThing:getParentContainer() then
                        g_game.open(useThing, useThing:getParentContainer())
                    else
                        g_game.open(useThing)
                    end
                    return true
                elseif useThing:isMultiUse() then
                    startUseWith(useThing)
                    return true
                else
                    g_game.use(useThing)
                    return true
                end
            end
            return true
        elseif shortcut == "attack" then
            if attackCreature and attackCreature ~= player then
                modules.game_shortcuts.resetShortcuts()
                g_game.attack(attackCreature)
                return true
            elseif creatureThing and creatureThing ~= player and autoWalkPos and creatureThing:getPosition().z == autoWalkPos.z then
                modules.game_shortcuts.resetShortcuts()
                g_game.attack(creatureThing)
                return true
            end
            return true
        elseif shortcut == "follow" then
            if attackCreature and attackCreature ~= player then
                modules.game_shortcuts.resetShortcuts()
                g_game.follow(attackCreature)
                return true
            elseif creatureThing and creatureThing ~= player and autoWalkPos and creatureThing:getPosition().z == autoWalkPos.z then
                modules.game_shortcuts.resetShortcuts()
                g_game.follow(creatureThing)
                return true
            end
            return true
        elseif not autoWalkPos and useThing then
            createThingMenu(menuPosition, lookThing, useThing, creatureThing)
            return true
        end
    elseif not modules.client_options.getOption('classicControl') then
        local smartLeftClick = modules.client_options.getOption('smartLeftClick')

        if smartLeftClick and mouseButton == MouseLeftButton and keyboardModifiers == KeyboardNoModifier then
            local player = g_game.getLocalPlayer()

            -- Handle NPCs first - they should not be attacked
            if creatureThing and creatureThing:isNpc() then
                local playerPos = player:getPosition()
                local npcPos = creatureThing:getPosition()
                if playerPos.z == npcPos.z then
                    local dist = math.max(math.abs(playerPos.x - npcPos.x), math.abs(playerPos.y - npcPos.y))
                    if dist <= 3 then
                        g_game.talk("hi")
                        return true
                    end
                end
            end

            -- Handle creature attacks (but not NPCs)
            if attackCreature and attackCreature ~= player and not attackCreature:isNpc() then
                g_game.attack(attackCreature)
                return true
            elseif creatureThing and creatureThing ~= player and not creatureThing:isNpc() and autoWalkPos and creatureThing:getPosition().z == autoWalkPos.z then
                g_game.attack(creatureThing)
                return true
            elseif useThing then
                -- Handle interactive items first, without looking at them
                if useThing:isUsable() then
                    -- Only use the item, don't look at it
                    if useThing:isContainer() then
                        if useThing:getParentContainer() then
                            g_game.open(useThing, useThing:getParentContainer())
                        else
                            g_game.open(useThing)
                        end
                        return true
                    elseif useThing:isMultiUse() then
                        startUseWith(useThing)
                        return true
                    else
                        g_game.use(useThing)
                        return true
                    end
                end

                -- Standard handling for other usable items
                -- For containers (including corpses), only execute quicklooting with Smart Left-Click
                -- Exception: If container has a parent container, open it instead of quicklooting
                if useThing:isContainer() or useThing:isLyingCorpse() then
                    -- Prioritize containers/corpses even if there are creatures on the same tile
                    if useThing:getParentContainer() then
                        -- For containers inside other containers, we want to open them, not quickloot
                        g_game.open(useThing, useThing:getParentContainer())
                        return true
                    elseif useThing:isPickupable() then
                        -- For pickupable containers like quivers, backpacks, etc., open them instead of quicklooting
                        g_game.open(useThing)
                        return true
                    elseif g_game.getFeature(GameThingQuickLoot) and modules.game_quickloot then
                        -- For containers in the world (not inside another container), quickloot
                        g_game.sendQuickLoot(1, useThing)
                        return true
                    end
                elseif useThing:isMultiUse() then
                    startUseWith(useThing)
                    return true
                else
                    local useResult = g_game.use(useThing)

                    if useResult ~= nil then
                        return true
                    end
                end

                -- If we couldn't use the item through any of the above methods,
                -- but it's pickupable, try to pick it up (like in Classic Control mode)
                if useThing:isPickupable() then
                    g_game.move(useThing, useThing:getPosition(), 1)
                    return true
                end

                -- If we couldn't use or pick up the item, try to walk to its position if possible
                local position = useThing:getPosition()
                if position and position.x ~= 0 and autoWalkPos then
                    local player = g_game.getLocalPlayer()
                    player:autoWalk(autoWalkPos)
                    return true
                end

                return true
            end

            -- Only look at things if no usable item was found
            if lookThing and lookThing ~= useThing then
                local lookPosition = lookThing:getPosition()
                local lookTile = nil

                if lookPosition and lookPosition.x ~= 0 then
                    lookTile = g_map.getTile(lookPosition)
                end

                -- For walkable tiles, we want to walk
                if lookTile and lookTile:isWalkable() and autoWalkPos then
                    local player = g_game.getLocalPlayer()
                    player:autoWalk(autoWalkPos)
                    return true
                else
                    -- Only look at the thing if we haven't used it already
                    g_game.look(lookThing)
                    return true
                end
            end

            if autoWalkPos then
                local player = g_game.getLocalPlayer()
                player:autoWalk(autoWalkPos)
                return true
            end
        end

        if keyboardModifiers == KeyboardNoModifier and mouseButton == MouseRightButton then
            createThingMenu(menuPosition, lookThing, useThing, creatureThing)
            return true
        elseif lookThing and keyboardModifiers == KeyboardShiftModifier and
            (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
            g_game.look(lookThing)
            return true
        elseif useThing and g_keyboard.isPrimaryModifierOnly(keyboardModifiers) and
            (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
            local smartLeftClick = modules.client_options.getOption('smartLeftClick')

            if smartLeftClick then
                local player = g_game.getLocalPlayer()
                -- For containers in the world, Ctrl+Left Click opens them even if there's a creature
                if (useThing:isContainer() or useThing:isLyingCorpse()) and not useThing:getParentContainer() then
                    g_game.open(useThing)
                    return true
                else
                    createThingMenu(menuPosition, lookThing, useThing, creatureThing)
                    return true
                end
            else
                if useThing:isContainer() then
                    if useThing:getParentContainer() then
                        g_game.open(useThing, useThing:getParentContainer())
                    else
                        g_game.open(useThing)
                    end
                    return true
                elseif useThing:isMultiUse() then
                    startUseWith(useThing)
                    return true
                else
                    g_game.use(useThing)
                    return true
                end
            end
            return true
        elseif useThing and useThing:isContainer() and g_keyboard.isPrimaryShiftModifierOnly(keyboardModifiers) and
            (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
            g_game.open(useThing)
            return true
        elseif attackCreature and not attackCreature:isNpc() and g_keyboard.isAltPressed() and
            (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
            g_game.attack(attackCreature)
            return true
        elseif creatureThing and not creatureThing:isNpc() and autoWalkPos and creatureThing:getPosition().z == autoWalkPos.z and g_keyboard.isAltPressed() and
            (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
            g_game.attack(creatureThing)
            return true
        end

        -- classic control
    else
        local lootControlMode = modules.client_options.getOption('lootControlMode')
        local player = g_game.getLocalPlayer()

        -- ###############################
        -- ### MODE 0: LOOT RIGHT CLICK ##
        -- ###############################
        if lootControlMode == 0 then
            -- Right click with no modifiers: main loot functionality
            if mouseButton == MouseRightButton and keyboardModifiers == KeyboardNoModifier then
                -- Handle NPCs first - they should not be attacked
                if creatureThing and creatureThing:isNpc() then
                    local playerPos = player:getPosition()
                    local npcPos = creatureThing:getPosition()
                    if playerPos.z == npcPos.z then
                        local dist = math.max(math.abs(playerPos.x - npcPos.x), math.abs(playerPos.y - npcPos.y))
                        if dist <= 3 then
                            g_game.talk("hi")
                            return true
                        end
                    end
                end
                
                -- Handle creature attacks (match Smart Left-Click behavior)
                if attackCreature and attackCreature ~= player then
                    g_game.attack(attackCreature)
                    return true
                elseif creatureThing and creatureThing ~= player and autoWalkPos and creatureThing:getPosition().z == autoWalkPos.z then
                    g_game.attack(creatureThing)
                    return true
                elseif useThing then
                    -- For containers/corpses
                    if useThing:isContainer() or useThing:isLyingCorpse() then
                        -- For containers inside other containers, we want to open them
                        if useThing:getParentContainer() then
                            g_game.open(useThing, useThing:getParentContainer())
                            return true
                        elseif useThing:isPickupable() then
                            -- For pickupable containers like quivers, backpacks, etc., open them instead of quicklooting
                            g_game.open(useThing)
                            return true
                        elseif table.find({ 3497, 3498, 3499, 3500, 3502, 12902 }, useThing:getId()) then
                            -- For depot chests, lockers, depot boxes, inbox, etc., always open them
                            g_game.open(useThing)
                            return true
                        elseif g_game.getFeature(GameThingQuickLoot) and modules.game_quickloot then
                            -- For containers in the world, quickloot
                            g_game.sendQuickLoot(1, useThing)
                            return true
                        else
                            g_game.open(useThing)
                            return true
                        end
                    elseif useThing:isMultiUse() then
                        startUseWith(useThing)
                        return true
                    else
                        g_game.use(useThing)
                        return true
                    end
                end

                -- Handle pickupable items if no container/corpse was handled
                if lookThing and not lookThing:isCreature() and lookThing:isPickupable() then
                    g_game.move(lookThing, lookThing:getPosition(), 1)
                    return true
                end
            end

            -- SHIFT+Right click: opens containers without quicklooting
            if mouseButton == MouseRightButton and keyboardModifiers == KeyboardShiftModifier then
                if useThing then
                    if useThing:isContainer() or useThing:isLyingCorpse() then
                        if useThing:getParentContainer() then
                            g_game.open(useThing, useThing:getParentContainer())
                        else
                            g_game.open(useThing)
                        end
                        return true
                    elseif useThing:isMultiUse() then
                        startUseWith(useThing)
                        return true
                    else
                        g_game.use(useThing)
                        return true
                    end
                end
            end

            -- #################################
            -- ### MODE 1: LOOT SHIFT+RIGHT  ###
            -- #################################
        elseif lootControlMode == 1 then
            -- Right click with no modifiers: use or open containers
            if mouseButton == MouseRightButton and keyboardModifiers == KeyboardNoModifier then
                -- Handle NPCs first - they should not be attacked
                if creatureThing and creatureThing:isNpc() then
                    local playerPos = player:getPosition()
                    local npcPos = creatureThing:getPosition()
                    if playerPos.z == npcPos.z then
                        local dist = math.max(math.abs(playerPos.x - npcPos.x), math.abs(playerPos.y - npcPos.y))
                        if dist <= 3 then
                            g_game.talk("hi")
                            return true
                        end
                    end
                end
                
                -- Handle creature attacks
                if attackCreature and attackCreature ~= player then
                    g_game.attack(attackCreature)
                    return true
                elseif creatureThing and creatureThing ~= player and autoWalkPos and creatureThing:getPosition().z == autoWalkPos.z then
                    g_game.attack(creatureThing)
                    return true
                elseif useThing then
                    -- For containers
                    if useThing:isContainer() or useThing:isLyingCorpse() then
                        if useThing:getParentContainer() then
                            g_game.open(useThing, useThing:getParentContainer())
                        else
                            g_game.open(useThing)
                        end
                        return true
                    elseif useThing:isMultiUse() then
                        startUseWith(useThing)
                        return true
                    else
                        g_game.use(useThing)
                        return true
                    end
                end
            end

            -- SHIFT+Right click: quickloot on containers
            if mouseButton == MouseRightButton and keyboardModifiers == KeyboardShiftModifier then
                if useThing and (useThing:isContainer() or useThing:isLyingCorpse()) then
                    if g_game.getFeature(GameThingQuickLoot) and modules.game_quickloot then
                        g_game.sendQuickLoot(1, useThing)
                        return true
                    end
                end

                -- Handle pickupable items
                if lookThing and not lookThing:isCreature() and lookThing:isPickupable() then
                    g_game.move(lookThing, lookThing:getPosition(), 1)
                    return true
                end
            end

            -- #############################
            -- ### MODE 2: LOOT LEFT     ###
            -- #############################
        elseif lootControlMode == 2 then
            -- Left click with no modifiers: ONLY for loot functionality
            if mouseButton == MouseLeftButton and keyboardModifiers == KeyboardNoModifier then
                -- ONLY for quicklooting and picking up items, NOT for attacking
                if useThing then
                    -- ONLY quickloot containers/corpses in the game world
                    if (useThing:isContainer() or useThing:isLyingCorpse()) and not useThing:getParentContainer() then
                        -- Only handle containers that are in the game world (not in inventory)
                        if table.find({ 3497, 3498, 3499, 3500, 3502, 12902 }, useThing:getId()) then
                            -- For depot chests, lockers, depot boxes, inbox, etc., always open them
                            g_game.open(useThing)
                            return true
                        elseif g_game.getFeature(GameThingQuickLoot) and modules.game_quickloot then
                            g_game.sendQuickLoot(1, useThing)
                            return true
                        else
                            g_game.open(useThing)
                            return true
                        end
                    end
                end

                -- Handle pickupable items in the game world
                if lookThing and not lookThing:isCreature() and lookThing:isPickupable() then
                    g_game.move(lookThing, lookThing:getPosition(), 1)
                    return true
                end
            end

            -- Right click for Loot: Left mode - use items instead of showing context menu
            if mouseButton == MouseRightButton and keyboardModifiers == KeyboardNoModifier then
                -- Handle NPCs first - they should not be attacked
                if creatureThing and creatureThing:isNpc() then
                    local playerPos = player:getPosition()
                    local npcPos = creatureThing:getPosition()
                    if playerPos.z == npcPos.z then
                        local dist = math.max(math.abs(playerPos.x - npcPos.x), math.abs(playerPos.y - npcPos.y))
                        if dist <= 3 then
                            g_game.talk("hi")
                            return true
                        end
                    end
                end
                
                -- Handle creature attacks
                if attackCreature and attackCreature ~= player then
                    g_game.attack(attackCreature)
                    return true
                elseif creatureThing and creatureThing ~= player and autoWalkPos and creatureThing:getPosition().z == autoWalkPos.z then
                    g_game.attack(creatureThing)
                    return true
                    -- Use the item if it's a container in inventory or use other items
                elseif useThing then
                    if useThing:isContainer() or useThing:isLyingCorpse() then
                        if useThing:getParentContainer() then
                            g_game.open(useThing, useThing:getParentContainer())
                            return true
                        else
                            g_game.open(useThing)
                            return true
                        end
                    elseif useThing:isMultiUse() then
                        startUseWith(useThing)
                        return true
                    else
                        g_game.use(useThing)
                        return true
                    end
                end

                -- Only show context menu when no usable item is present
                if not useThing then
                    createThingMenu(menuPosition, lookThing, useThing, creatureThing)
                    return true
                end
            end
        end

        -- Common key combinations for all Classic Control modes
        if useThing and useThing:isContainer() and g_keyboard.isPrimaryShiftModifierOnly(keyboardModifiers) and
            (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
            g_game.open(useThing)
            return true
        elseif lookThing and keyboardModifiers == KeyboardShiftModifier and
            (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
            g_game.look(lookThing)
            return true
        elseif lookThing and ((g_mouse.isPressed(MouseLeftButton) and mouseButton == MouseRightButton) or
                (g_mouse.isPressed(MouseRightButton) and mouseButton == MouseLeftButton)) then
            g_game.look(lookThing)
            return true
        elseif useThing and g_keyboard.isPrimaryModifierOnly(keyboardModifiers) and
            (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
            createThingMenu(menuPosition, lookThing, useThing, creatureThing)
            return true
        elseif attackCreature and not attackCreature:isNpc() and g_keyboard.isAltPressed() and
            (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
            g_game.attack(attackCreature)
            return true
        elseif creatureThing and not creatureThing:isNpc() and autoWalkPos and creatureThing:getPosition().z == autoWalkPos.z and g_keyboard.isAltPressed() and
            (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
            g_game.attack(creatureThing)
            return true
        end
    end

    local player = g_game.getLocalPlayer()
    player:stopAutoWalk()

    if autoWalkPos and keyboardModifiers == KeyboardNoModifier and mouseButton == MouseLeftButton then
        -- In Classic Control with Loot: Left option, we want to avoid walking when trying to loot
        local classicControl = modules.client_options.getOption('classicControl')
        local lootControlMode = modules.client_options.getOption('lootControlMode')

        if classicControl and lootControlMode == 2 then
            -- Check if there's a corpse or item we should be looting instead of walking
            -- If not, proceed with autowalk
            local isCorpseOrContainer = useThing and (useThing:isContainer() or useThing:isLyingCorpse())

            if not isCorpseOrContainer and
                not (lookThing and not lookThing:isCreature() and lookThing:isPickupable()) then
                player:autoWalk(autoWalkPos)
                if g_game.isAttacking() and g_game.getChaseMode() == ChaseOpponent then
                    g_game.setChaseMode(DontChase)
                end
            end
        else
            player:autoWalk(autoWalkPos)
            if g_game.isAttacking() and g_game.getChaseMode() == ChaseOpponent then
                g_game.setChaseMode(DontChase)
            end
        end
        return true
    end

    return false
end

local function handleItemInteraction(item, widget, callback)
    local count = item:getCount()
    widget.hotkeyBlock = modules.game_hotkeys.createHotkeyBlock("stackable_item_dialog")
    local itembox = widget:getChildById('item')
    local scrollbar = widget:getChildById('countScrollBar')
    itembox:setItemId(item:getId())
    itembox:setItemCount(count)
    scrollbar:setMaximum(count)
    scrollbar:setMinimum(1)
    scrollbar:setValue(count)

    local spinbox = widget:getChildById('spinBox')
    spinbox:setMaximum(count)
    spinbox:setMinimum(0)
    spinbox:setValue(0)
    spinbox:hideButtons()
    spinbox:focus()
    spinbox.firstEdit = true

    local spinBoxValueChange = function(self, value)
        spinbox.firstEdit = false
        scrollbar:setValue(value)
    end
    spinbox.onValueChange = spinBoxValueChange

    local check = function()
        if spinbox.firstEdit then
            spinbox:setValue(spinbox:getMaximum())
            spinbox.firstEdit = false
        end
    end
    g_keyboard.bindKeyPress('Up', function()
        check()
        spinbox:upSpin()
    end, spinbox)
    g_keyboard.bindKeyPress('Down', function()
        check()
        spinbox:downSpin()
    end, spinbox)
    g_keyboard.bindKeyPress('Right', function()
        check()
        spinbox:upSpin()
    end, spinbox)
    g_keyboard.bindKeyPress('Left', function()
        check()
        spinbox:downSpin()
    end, spinbox)
    g_keyboard.bindKeyPress('PageUp', function()
        check()
        spinbox:setValue(spinbox:getValue() + 10)
    end, spinbox)
    g_keyboard.bindKeyPress('PageDown', function()
        check()
        spinbox:setValue(spinbox:getValue() - 10)
    end, spinbox)

    scrollbar.onValueChange = function(self, value)
        itembox:setItemCount(value)
        spinbox.onValueChange = nil
        spinbox:setValue(value)
        spinbox.onValueChange = spinBoxValueChange
    end

    local okButton = widget:getChildById('buttonOk')
    local moveFunc = function()
        callback(itembox:getItemCount())
        okButton:getParent():destroy()
        widget = nil
    end
    local cancelButton = widget:getChildById('buttonCancel')
    local cancelFunc = function()
        cancelButton:getParent():destroy()
        countWindow = nil
        widget = nil
    end

    widget.onEnter = moveFunc
    widget.onEscape = cancelFunc

    okButton.onClick = moveFunc
    cancelButton.onClick = cancelFunc
end

function stashItem(item)
    local count = item:getCount()
    if count == 1 then
        g_game.stashStowItem(item:getPosition(), item:getId(), count,
            item:getStackPos(), 0)
        return
    end
    if countWindow then
        if countWindow:isDestroyed() then
            countWindow = nil
        else
            return
        end
    end
    countWindow = g_ui.createWidget('CountStashWindow', rootWidget)

    handleItemInteraction(item, countWindow, function(amount)
        g_game.stashStowItem(item:getPosition(), item:getId(), amount,
            item:getStackPos(), 0)
        countWindow = nil
    end)
end

function moveStackableItem(item, toPos)
    if countWindow then
        if countWindow:isDestroyed() then
            countWindow = nil
        else
            return
        end
    end
    if g_keyboard.isShiftPressed() then
        g_game.move(item, toPos, 1)
        return
    elseif g_keyboard.isCtrlPressed() ~= modules.client_options.getOption('moveStack') then
        g_game.move(item, toPos, item:getCount())
        return
    end

    countWindow = g_ui.createWidget('CountWindow', rootWidget)
    handleItemInteraction(item, countWindow, function(count)
        g_game.move(item, toPos, count)
        countWindow = nil
    end)
end

function onSelectPanel(self, checked)
    if checked then
        for k, v in pairs(panelsList) do
            if v.checkbox == self then
                gameSelectedPanel = v.panel
                break
            end
        end
    end
end

function getRootPanel()
    return gameRootPanel
end

function getMapPanel()
    return gameMapPanel
end

function getRightPanel()
    return gameRightPanel
end

function getMainRightPanel()
    return gameMainRightPanel
end

function getLeftPanel()
    return gameLeftPanel
end

function getRightExtraPanel()
    return gameRightExtraPanel
end

function getLeftExtraPanel()
    return gameLeftExtraPanel
end

function getSelectedPanel()
    return gameSelectedPanel
end

function getBottomPanel()
    return gameBottomPanel
end

function getShowTopMenuButton()
    return showTopMenuButton
end

function getGameTopStatsBar()
    return gameTopPanel
end

function getGameBottomStatsBar()
    return gameBottomStatsBarPanel
end

function getGameMapPanel()
    return gameMapPanel
end

function getBottomActionPanel()
    return gameBottomActionPanel
end

function getLeftActionPanel()
    return gameLeftActionPanel
end

function getRightActionPanel()
    return gameRightActionPanel
end

function getBottomLockPanel()
    return gameBottomLockPanel
end

function getRightLockPanel()
    return gameRightLockPanel
end

function getLeftLockPanel()
    return gameLeftLockPanel
end

function getBottomSplitter()
    return bottomSplitter
end

function findContentPanelAvailable(child, minContentHeight)
    if gameSelectedPanel and gameSelectedPanel:isVisible() and gameSelectedPanel:fits(child, minContentHeight, 0) >= 0 then
        return gameSelectedPanel
    end

    for k, v in pairs(panelsList) do
        if v.panel ~= gameSelectedPanel and v.panel:isVisible() and v.panel:fits(child, minContentHeight, 0) >= 0 then
            return v.panel
        end
    end

    return gameSelectedPanel
end

function nextViewMode()
    setupViewMode((currentViewMode + 1) % 3)
end

function setupViewMode(mode)
    if mode == currentViewMode then
        return
    end

    updateSidePanelButtons()

    if currentViewMode == 2 then
        gameMapPanel:addAnchor(AnchorLeft, 'gameLeftPanel', AnchorRight)
        gameMapPanel:addAnchor(AnchorRight, 'gameRightPanel', AnchorLeft)
        gameMapPanel:addAnchor(AnchorBottom, 'bottomSplitter', AnchorTop)
        gameMapPanel:addAnchor(AnchorTop, 'gameTopPanel', AnchorBottom)
        gameRootPanel:addAnchor(AnchorTop, 'parent', AnchorTop)
        gameLeftPanel:setOn(modules.client_options.getOption('showLeftPanel'))
        gameRightExtraPanel:setOn(modules.client_options.getOption('showRightExtraPanel'))
        gameLeftExtraPanel:setOn(modules.client_options.getOption('showLeftExtraPanel'))
        gameLeftPanel:setImageColor('white')
        gameRightPanel:setImageColor('white')
        gameRightExtraPanel:setImageColor('white')
        gameLeftExtraPanel:setImageColor('white')
        gameLeftPanel:setMarginTop(0)
        gameRightPanel:setMarginTop(0)
        gameRightExtraPanel:setMarginTop(0)
        gameLeftExtraPanel:setMarginTop(0)
        gameBottomPanel:setImageColor('white')
    end

    if mode == 0 then
        gameMapPanel:setKeepAspectRatio(true)
        gameMapPanel:setLimitVisibleRange(false)
        gameMapPanel:setZoom(11)
        gameMapPanel:setVisibleDimension({
            width = 15,
            height = 11
        })
    elseif mode == 1 then
        gameMapPanel:setKeepAspectRatio(false)
        gameMapPanel:setLimitVisibleRange(true)
        gameMapPanel:setZoom(11)
        gameMapPanel:setVisibleDimension({
            width = 15,
            height = 11
        })
    elseif mode == 2 then
        local limit = limitedZoom and not g_game.isGM()
        gameMapPanel:setLimitVisibleRange(limit)
        gameMapPanel:setZoom(11)
        gameMapPanel:setVisibleDimension({
            width = 15,
            height = 11
        })
        gameMapPanel:fill('parent')
        gameRootPanel:fill('parent')
        gameLeftPanel:setImageColor('alpha')
        gameRightPanel:setImageColor('alpha')
        gameRightExtraPanel:setImageColor('alpha')
        gameLeftExtraPanel:setImageColor('alpha')
        gameLeftPanel:setOn(true)
        gameLeftPanel:setVisible(true)
        gameRightPanel:setOn(true)
        gameRightExtraPanel:setOn(false)
        gameRightExtraPanel:setVisible(false)
        gameLeftExtraPanel:setOn(false)
        gameLeftExtraPanel:setVisible(false)
        gameMapPanel:setOn(true)
        gameBottomPanel:setImageColor('#ffffff88')
    end

    applyMobileMargins()
    currentViewMode = mode
    applyExtendedViewLayout(mode == 2)
end

function limitZoom()
    limitedZoom = true
end

function updateStatsBar(dimension, placement)
    StatsBar.updateCurrentStats(dimension, placement)
    StatsBar.updateStatsBarOption()
end

function onIncreaseLeftPanels()
    leftDecreaseSidePanels:setEnabled(true)
    if not modules.client_options.getOption('showLeftPanel') then
        modules.client_options.setOption('showLeftPanel', true)
        -- Update action bars when left panel is shown
        if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
            addEvent(function()
                modules.game_actionbar.updateVisibleWidgetsExternal()
            end)
        end
        return
    end

    if not modules.client_options.getOption('showLeftExtraPanel') then
        modules.client_options.setOption('showLeftExtraPanel', true)
        leftIncreaseSidePanels:setEnabled(false)
        -- Update action bars when left extra panel is shown
        if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
            addEvent(function()
                modules.game_actionbar.updateVisibleWidgetsExternal()
            end)
        end
        return
    end
end

local function movePanel(mainpanel)
    for _, widget in pairs(mainpanel:getChildren()) do
        if widget then
            local panel = modules.game_interface.findContentPanelAvailable(widget, widget:getMinimumHeight())
            if panel then
                if not panel:hasChild(widget) then
                    widget:close()
                    panel:addChild(widget)
                else
                    print("Error: Attempt to add a widget that already exists in the target panel")
                end
            else
                print("Warning: No suitable panel found for widget, unable to move")
            end
        end
    end
end

function onDecreaseLeftPanels()
    leftIncreaseSidePanels:setEnabled(true)
    if modules.client_options.getOption('showLeftExtraPanel') then
        modules.client_options.setOption('showLeftExtraPanel', false)
        movePanel(gameLeftExtraPanel)
        if g_platform.isMobile() then
            leftDecreaseSidePanels:setEnabled(false)
        end
        -- Update action bars when left extra panel is hidden
        if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
            addEvent(function()
                modules.game_actionbar.updateVisibleWidgetsExternal()
            end)
        end
        return
    end

    if not g_platform.isMobile() then
        if modules.client_options.getOption('showLeftPanel') then
            modules.client_options.setOption('showLeftPanel', false)
            movePanel(gameLeftPanel)
            leftDecreaseSidePanels:setEnabled(false)
            -- Update action bars when left panel is hidden
            if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
                addEvent(function()
                    modules.game_actionbar.updateVisibleWidgetsExternal()
                end)
            end
            return
        end
    end
end

function onIncreaseRightPanels()
    rightIncreaseSidePanels:setEnabled(false)
    rightDecreaseSidePanels:setEnabled(true)
    modules.client_options.setOption('showRightExtraPanel', true)
    -- Update action bars when right extra panel is shown
    if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
        addEvent(function()
            modules.game_actionbar.updateVisibleWidgetsExternal()
        end)
    end
end

function onDecreaseRightPanels()
    rightIncreaseSidePanels:setEnabled(true)
    rightDecreaseSidePanels:setEnabled(false)
    movePanel(gameRightExtraPanel)
    modules.client_options.setOption('showRightExtraPanel', false)
    -- Update action bars when right extra panel is hidden
    if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
        addEvent(function()
            modules.game_actionbar.updateVisibleWidgetsExternal()
        end)
    end
end

function setupOptionsMainButton()
    if logOutMainButton then
        return
    end

    logOutMainButton = modules.game_mainpanel.addSpecialToggleButton('logoutButton', tr('Exit'),
        '/images/options/button_logout',
        tryLogout)
end

function checkAndOpenLeftPanel()
    leftDecreaseSidePanels:setEnabled(true)
    if not modules.client_options.getOption('showLeftPanel') then
        modules.client_options.setOption('showLeftPanel', true)
        return
    end
end

function applyExtendedViewLayout(extendedView)
    if extendedView == isExtendedViewActive then return end
    isExtendedViewActive = extendedView

    local buttons = { leftIncreaseSidePanels, rightIncreaseSidePanels,
        rightDecreaseSidePanels, leftDecreaseSidePanels }

    if extendedView then
        for _, btn in ipairs(buttons) do
            btn:hide()
        end

        if not g_platform.isMobile() then
            gameBottomPanel:breakAnchors()
            gameBottomPanel:bindRectToParent()
            gameBottomPanel:setDraggable(true)
        else
            gameBottomPanel:setWidth(g_window.getWidth() - mobileConfig.mobileWidthJoystick -
                mobileConfig.mobileWidthShortcuts)
            gameBottomPanel:setPosition({
                x = mobileConfig.mobileWidthJoystick,
                y = gameBottomPanel:getY()
            })
        end
        gameBottomPanel:getChildById('rightResizeBorder'):setMaximum(gameBottomPanel:getWidth())
        gameBottomPanel:getChildById('bottomResizeBorder'):enable()
        gameBottomPanel:getChildById('rightResizeBorder'):enable()
        gameMainRightPanel:setHeight(0)
        gameMainRightPanel:setImageColor('alpha')
        gameBottomPanel:addAnchor(AnchorTop, 'gameBottomActionPanel', AnchorBottom)
        gameBottomPanel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        gameLeftActionPanel:setImageSource(nil)
        gameRightActionPanel:setImageSource(nil)
        gameLeftActionPanel:setBorderWidthRight(0)
        gameRightActionPanel:setBorderWidthLeft(0)
    else
        -- Reset to normal view
        gameMainRightPanel:setHeight(200)
        gameMainRightPanel:setMarginTop(0)
        gameMainRightPanel:setImageColor('white')
        gameLeftActionPanel:setImageSource('/images/ui/actionbar/actionbar_background-light')
        gameRightActionPanel:setImageSource('/images/ui/actionbar/actionbar_background-light')
        gameLeftActionPanel:setBorderWidthRight(1)
        gameRightActionPanel:setBorderWidthLeft(1)
        for _, btn in ipairs(buttons) do
            btn:setMarginTop(0)
            btn:show()
        end

        -- Reset bottom panel
        gameBottomPanel:setDraggable(false)

        -- Set anchors
        if not g_platform.isMobile() then
            gameBottomPanel:breakAnchors()
            gameBottomPanel:addAnchor(AnchorLeft, 'gameLeftExtraPanel', AnchorRight)
            gameBottomPanel:addAnchor(AnchorRight, 'gameRightExtraPanel', AnchorLeft)
            gameBottomPanel:addAnchor(AnchorTop, 'gameBottomCooldownPanel', AnchorBottom)
            gameBottomPanel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        end
        gameBottomPanel:getChildById('bottomResizeBorder'):disable()
        gameBottomPanel:getChildById('rightResizeBorder'):disable()

        -- Move children back to gameMainRightPanel
        local children = gameRightPanel:getChildren()
        for _, child in ipairs(children) do
            if child.moveOnlyToMain then
                child:setParent(gameMainRightPanel)
            end
        end
    end

    addEvent(function()
        modules.game_console.setExtendedView(extendedView)
        modules.game_minimap.extendedView(extendedView)
        modules.game_healthinfo.extendedView(extendedView)
        modules.game_inventory.extendedView(extendedView)
        modules.client_topmenu.extendedView(extendedView)
        modules.game_mainpanel.toggleExtendedViewButtons(extendedView)
    end)
end

function toggleInternalFocus()
    for reason, _ in pairs(focusReason) do
        if reason == 'bosscooldown' then
            modules.game_analyser.toggleBossCDFocus(false)
        end
    end
end

function isInternalLocked()
    if not focusReason or table.empty(focusReason) then
        return false
    end
    return true
end

function toggleFocus(value, reason)
    if not reason then
        reason = ''
    end
    if not value then
        getBottomPanel():focus()
        if not reason then
            reason = ''
        end

        focusReason[reason] = nil
    else
        focusReason[reason] = true
    end

    if not value and #focusReason ~= 0 then
        return
    end

    gameRightPanel:setFocusable(value)
    gameLeftPanel:setFocusable(value)
    gameRightExtraPanel:setFocusable(value)
    gameLeftExtraPanel:setFocusable(value)
end

-- Server validates ownership, open container index and unidentified state.
function identifyRarityItem(thing)
 local pos=thing:getPosition();local protocol=g_game.getProtocolGame()
 if not protocol or not pos then return end
 if pos.x==65535 then
  protocol:sendExtendedOpcode(104, pos.y..':'..pos.z..':'..thing:getId())
 else
  protocol:sendExtendedOpcode(104, 'g:'..pos.x..':'..pos.y..':'..pos.z..':'..thing:getStackPos()..':'..thing:getId())
 end
end
