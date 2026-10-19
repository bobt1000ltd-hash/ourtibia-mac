local iconTopMenu = nil
-- @ Minimap
local minimapWidget = nil -- bot fix
local otmm = true
local oldPos = nil
local fullscreenWidget
local virtualFloor = 7
local currentDayTime = {
    h = 12,
    m = 0
}

local function refreshVirtualFloors()
    mapController.ui.layersPanel.layersMark:setMarginTop(((virtualFloor + 1) * 4) - 3)
    mapController.ui.layersPanel.automapLayers:setImageClip((virtualFloor * 14) .. ' 0 14 67')
end

local function onPositionChange()
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    local pos = player:getPosition()
    if not pos then
        return
    end

    local minimapWidget = mapController.ui.minimapBorder.minimap
    if not (minimapWidget) or minimapWidget:isDragging() then
        return
    end

    if not minimapWidget.fullMapView then
        minimapWidget:setCameraPosition(pos)
    end

    minimapWidget:setCrossPosition(pos)
    virtualFloor = pos.z
    refreshVirtualFloors()
end

mapController = Controller:new()
mapController:setUI('minimap', modules.game_interface.getMainRightPanel())

function onChangeWorldTime(hour, minute)
--[[ 

check 
tfs c++ (old) : void ProtocolGame::sendWorldTime()
tfs lua (new) : function Player.sendWorldTime(self, time)
Canary: void ProtocolGame::sendTibiaTime(int32_t time)
 ]]

    currentDayTime = {
        h = hour % 24,
        m = minute
    }

    mapController:scheduleEvent(function()
        local nextH = currentDayTime.h
        local nextM = currentDayTime.m + 12
        if nextM >= 60 then
            nextH = nextH + 1
            nextM = nextM - 60
        end

        onChangeWorldTime(nextH, nextM)
    end, 30000, 'dayTime')

    local position = math.floor((124 / (24 * 60)) * ((hour * 60) + minute))
    local mainWidth = 31
    local secondaryWidth = 0

    if (position + 31) >= 124 then
        secondaryWidth = ((position + 31) - 124) + 1
        mainWidth = 31 - secondaryWidth
    end

    mapController.ui.rosePanel.ambients.main:setWidth(mainWidth)
    mapController.ui.rosePanel.ambients.secondary:setWidth(secondaryWidth)

    if secondaryWidth == 0 then
        mapController.ui.rosePanel.ambients.secondary:hide()
    else
        mapController.ui.rosePanel.ambients.secondary:setImageClip('0 0 ' .. secondaryWidth .. ' 31')
        mapController.ui.rosePanel.ambients.secondary:show()
    end

    if mainWidth == 0 then
        mapController.ui.rosePanel.ambients.main:hide()
    else
        mapController.ui.rosePanel.ambients.main:setImageClip(position .. ' 0 ' .. mainWidth .. ' 31')
        mapController.ui.rosePanel.ambients.main:show()
    end
end

-- OurTibia (04.10.2026): the whole OurTibia map (made from the server map, all
-- floors) is shown to everybody. The player's own saved minimap is loaded first
-- and the full map on top, so old or wrong saved tiles are corrected.
local ourMinimapLoaded = false
function ourLoadMinimap()
    if ourMinimapLoaded then return end
    ourMinimapLoaded = true
    g_minimap.clean()
    -- OurTibia (15.10.2026): the full map file only shows places players can reach, so an
    -- older saved minimap (which still has the hidden places) is not loaded when it exists
    local full = g_resources.fileExists('/data/minimap/ourtibia1098.otmm')
    if otmm then
        if not full and g_resources.fileExists('/minimap.otmm') then pcall(g_minimap.loadOtmm, '/minimap.otmm') end
    elseif g_resources.fileExists('/minimap_1098.otcm') then
        pcall(g_map.loadOtcm, '/minimap_1098.otcm')
    end
    if g_resources.fileExists('/data/minimap/ourtibia1098.otmm') then
        g_minimap.loadOtmm('/data/minimap/ourtibia1098.otmm')
    end
end
function mapController:onInit()
    -- load the map while the client starts (before login)
    scheduleEvent(function() pcall(ourLoadMinimap) end, 300)
    pcall(ourSetupMinimapResize)
    self.ui.minimapBorder.minimap:getChildById('floorUpButton'):hide()
    self.ui.minimapBorder.minimap:getChildById('floorDownButton'):hide()
    self.ui.minimapBorder.minimap:getChildById('zoomInButton'):hide()
    self.ui.minimapBorder.minimap:getChildById('zoomOutButton'):hide()
    self.ui.minimapBorder.minimap:getChildById('resetButton'):hide()
end

function mapController:onGameStart()
    mapController:registerEvents(g_game, {
        onChangeWorldTime = onChangeWorldTime
    })

    mapController:registerEvents(LocalPlayer, {
        onPositionChange = onPositionChange
    }):execute()

    -- Load Map (04.10.2026): loaded once when the client starts (ourLoadMinimap in
    -- onInit), not on every login - the 4 MB full map made the login lag.
    ourLoadMinimap()
    -- OurTibia (04.10.2026): movable to any panel, saved size and panel
    mapController.ui.moveOnlyToMain = false
    scheduleEvent(function()
        local ui = mapController.ui
        local target = ourSavedPanel()
        if target and ui:getParent() ~= target then
            local parent = ui:getParent(); if parent then parent:removeChild(ui) end
            target:insertChild(1, ui)
        end
        ourApplyMinimapSize()
        -- 19.10.2026: the HUD option decides if the minimap is shown
        local co = modules.client_options
        if co and co.getOption and co.getOption('showMinimap') == false then pcall(setVisible, false) end
    end, 500)

    self.ui.minimapBorder.minimap:load()
end

function mapController:onGameEnd()
    pcall(function()
        local parent = mapController.ui:getParent()
        if parent and parent:getClassName() == 'UIMiniWindowContainer' then g_settings.set('ourMinimapPanel', parent:getId()) end
        g_settings.set('ourMinimapHeight', mapController.ui:getHeight())
    end)
    -- Save Map
    if otmm then
        g_minimap.saveOtmm('/minimap.otmm')
    else
        g_map.saveOtcm('/minimap_' .. g_game.getClientVersion() .. '.otcm')
    end

    self.ui.minimapBorder.minimap:save()
end

function mapController:onTerminate()
    if iconTopMenu then
        iconTopMenu:destroy()
        iconTopMenu = nil
    end
end

function zoomIn()
    mapController.ui.minimapBorder.minimap:zoomIn()
end

function zoomOut()
    mapController.ui.minimapBorder.minimap:zoomOut()
end

function openCyclopediaMap()
    -- OurTibia (04.10.2026): the map button next to the minimap opens the wiki map
    -- (Map & Spawns) centred on the player instead of the full-screen minimap.
    local wiki = modules.game_myotswiki
    if wiki and wiki.show and wiki.changeTab and g_game.isOnline() then
        wiki.show()
        wiki.changeTab('map')
        for _, delay in ipairs({200, 600}) do scheduleEvent(function() if wiki.mapPlayer then pcall(wiki.mapPlayer) end end, delay) end
        return
    end
    if g_game.getClientVersion() >= 1310 then
        modules.game_cyclopedia.toggle('map')
    else
        return fullscreen()
    end
end

function fullscreen()
    local minimapWidget = mapController.ui.minimapBorder.minimap
    if not minimapWidget then
        minimapWidget = fullscreenWidget
    end
    local zoom;

    if not minimapWidget then
        return
    end

    if minimapWidget.fullMapView then
        fullscreenWidget = nil
        minimapWidget:setParent(mapController.ui.minimapBorder)
        minimapWidget:fill('parent')
        mapController.ui:show()
        zoom = minimapWidget.zoomMinimap
        g_keyboard.unbindKeyDown('Escape')
        minimapWidget.fullMapView = false
    else
        fullscreenWidget = minimapWidget
        mapController.ui:hide(true)
        minimapWidget:setParent(modules.game_interface.getRootPanel())
        minimapWidget:fill('parent')
        zoom = minimapWidget.zoomFullmap
        g_keyboard.bindKeyDown('Escape', fullscreen)
        minimapWidget.fullMapView = true
    end

    local pos = oldPos or minimapWidget:getCameraPosition()
    oldPos = minimapWidget:getCameraPosition()
    minimapWidget:setZoom(zoom)
    minimapWidget:setCameraPosition(pos)
end

function upLayer()
    if virtualFloor == 0 then
        return
    end

    mapController.ui.minimapBorder.minimap:floorUp(1)
    virtualFloor = virtualFloor - 1
    refreshVirtualFloors()
end

function downLayer()
    if virtualFloor == 15 then
        return
    end

    mapController.ui.minimapBorder.minimap:floorDown(1)
    virtualFloor = virtualFloor + 1
    refreshVirtualFloors()
end

function onClickRoseButton(dir)
    if dir == 'north' then
        mapController.ui.minimapBorder.minimap:move(0, 1)
    elseif dir == 'north-east' then
        mapController.ui.minimapBorder.minimap:move(-1, 1)
    elseif dir == 'east' then
        mapController.ui.minimapBorder.minimap:move(-1, 0)
    elseif dir == 'south-east' then
        mapController.ui.minimapBorder.minimap:move(-1, -1)
    elseif dir == 'south' then
        mapController.ui.minimapBorder.minimap:move(0, -1)
    elseif dir == 'south-west' then
        mapController.ui.minimapBorder.minimap:move(1, -1)
    elseif dir == 'west' then
        mapController.ui.minimapBorder.minimap:move(1, 0)
    elseif dir == 'north-west' then
        mapController.ui.minimapBorder.minimap:move(1, 1)
    end
end

function resetMap()
    mapController.ui.minimapBorder.minimap:reset()
    local player = g_game.getLocalPlayer()
    if player then
        virtualFloor = player:getPosition().z
        refreshVirtualFloors()
    end
end

function getMiniMapUi()
    return mapController.ui.minimapBorder.minimap
end

function extendedView(extendedView)
    if extendedView then
        if not iconTopMenu then
            iconTopMenu = modules.client_topmenu.addTopRightToggleButton('miniMap', tr('Show miniMap'),
                '/images/topbuttons/minimap', toggle)
            iconTopMenu:setOn(mapController.ui:isVisible())
            mapController.ui:setBorderColor('black')
            mapController.ui:setBorderWidth(2)
        end
    else
        if iconTopMenu then
            iconTopMenu:destroy()
            iconTopMenu = nil
        end
        mapController.ui:setBorderColor('alpha')
        mapController.ui:setBorderWidth(0)
        local mainRightPanel = modules.game_interface.getMainRightPanel()
        -- OurTibia (04.10.2026): the minimap can be moved to any side panel; it
        -- goes back to the panel the player put it in last time.
        local target = ourSavedPanel() or mainRightPanel
        if not target:hasChild(mapController.ui) then
            local parent = mapController.ui:getParent()
            if parent then parent:removeChild(mapController.ui) end
            target:insertChild(1, mapController.ui)
        end
        mapController.ui:show()

    end
    -- OurTibia (04.10.2026): free to move (was only the main right panel)
    mapController.ui.moveOnlyToMain = false
    ourApplyMinimapSize()
end

-- OurTibia (04.10.2026): resizable minimap. Drag the bottom edge of the minimap
-- panel to make it taller; it also
-- fills the whole width of a wider panel. Size and panel are remembered.
local OUR_MIN_H, OUR_MAX_H = 116, 520
function ourSavedPanel()
    local id = g_settings.getString('ourMinimapPanel')
    if not id or id == '' then return nil end
    local root = modules.game_interface.getRootPanel and modules.game_interface.getRootPanel()
    local w = root and root:recursiveGetChildById(id)
    if w and w.getClassName and w:getClassName() == 'UIMiniWindowContainer' and w:isVisible() then return w end
    return nil
end
function ourApplyMinimapSize(h)
    local ui = mapController.ui
    if not ui then return end
    h = math.max(OUR_MIN_H, math.min(OUR_MAX_H, h or tonumber(g_settings.getNumber('ourMinimapHeight')) or OUR_MIN_H))
    if h < OUR_MIN_H then h = OUR_MIN_H end
    ui:setHeight(h)
    local border = ui.minimapBorder
    border:setHeight(h - 5)
    -- width: everything left of the zoom buttons
    local w = ui:getWidth() - 8 - 4 - 20 - 4 - 20 - 7
    border:setWidth(math.max(115, w))
end
function ourSetupMinimapResize()
    local ui = mapController.ui
    if not ui or ui.ourResize then return end
    ui.moveOnlyToMain = false
    -- the empty parts next to the map (floor indicator, clock) let the panel be
    -- dragged to another place (they swallowed the mouse before)
    for _, id in ipairs({'layersPanel', 'automapLayers', 'layersMark', 'rosePanel', 'ambients', 'main', 'secondary'}) do
        local w = ui:recursiveGetChildById(id)
        if w and w:getClassName() == 'UIWidget' then w:setPhantom(true) end
    end
    ui:setTooltip('Drag here to move the minimap; drag an edge or a corner to resize it')
    -- 05.10.2026: resize from every edge and every corner (width and height at
    -- once on a corner). In a side panel the width is the panel's, so only the
    -- height changes there; on the game window everything can change.
    local function isDocked()
        local parent = ui:getParent()
        return parent and parent.getClassName and parent:getClassName() == 'UIMiniWindowContainer'
    end
    local EDGE, CORNER = 6, 14
    local grips = {
        {'T', 0, -1}, {'B', 0, 1}, {'L', -1, 0}, {'R', 1, 0},
        {'TL', -1, -1}, {'TR', 1, -1}, {'BL', -1, 1}, {'BR', 1, 1},
    }
    ui.ourGrips = {}
    for _, g in ipairs(grips) do
        local name, dx, dy = g[1], g[2], g[3]
        local w = g_ui.createWidget('UIWidget', ui)
        w:setId('ourMinimapResize' .. name)
        w:setBackgroundColor('#00000000')
        w:setFocusable(false)
        if dx ~= 0 and dy ~= 0 then
            w:setSize({width = CORNER, height = CORNER})
            w:addAnchor(dy < 0 and AnchorTop or AnchorBottom, 'parent', dy < 0 and AnchorTop or AnchorBottom)
            w:addAnchor(dx < 0 and AnchorLeft or AnchorRight, 'parent', dx < 0 and AnchorLeft or AnchorRight)
        elseif dy ~= 0 then
            w:setHeight(EDGE)
            w:addAnchor(AnchorLeft, 'parent', AnchorLeft); w:setMarginLeft(CORNER)
            w:addAnchor(AnchorRight, 'parent', AnchorRight); w:setMarginRight(CORNER)
            w:addAnchor(dy < 0 and AnchorTop or AnchorBottom, 'parent', dy < 0 and AnchorTop or AnchorBottom)
        else
            w:setWidth(EDGE)
            w:addAnchor(AnchorTop, 'parent', AnchorTop); w:setMarginTop(CORNER)
            w:addAnchor(AnchorBottom, 'parent', AnchorBottom); w:setMarginBottom(CORNER)
            w:addAnchor(dx < 0 and AnchorLeft or AnchorRight, 'parent', dx < 0 and AnchorLeft or AnchorRight)
        end
        local cursor = (dx ~= 0 and dy == 0) and 'horizontal' or (dy ~= 0 and dx == 0) and 'vertical' or nil
        w.onHoverChange = function(self, hovered)
            if dx ~= 0 and dy == 0 and isDocked() then
                self:setTooltip('Drag the minimap out of the side panel to change its width')
            else
                self:setTooltip('Drag to resize the minimap')
            end
            self:setBackgroundColor(hovered and '#c8a04a55' or '#00000000')
            if cursor then if hovered then g_mouse.pushCursor(cursor) else g_mouse.popCursor(cursor) end end
        end
        w.onMousePress = function(self, mousePos, button)
            if button ~= MouseLeftButton then return false end
            local r = ui:getRect()
            self.drag = {mx = mousePos.x, my = mousePos.y, x = r.x, y = r.y, w = r.width, h = r.height, docked = isDocked()}
            return true
        end
        w.onMouseMove = function(self, mousePos)
            local d = self.drag
            if not d then return false end
            local nw, nh = d.w, d.h
            if dx ~= 0 and not d.docked then nw = math.max(176, math.min(900, d.w + dx * (mousePos.x - d.mx))) end
            if dy ~= 0 then nh = math.max(OUR_MIN_H, math.min(OUR_MAX_H, d.h + dy * (mousePos.y - d.my))) end
            if not d.docked then
                ui:setWidth(nw)
                if dx < 0 or dy < 0 then
                    ui:setPosition({x = dx < 0 and d.x + d.w - nw or d.x, y = dy < 0 and d.y + d.h - nh or d.y})
                end
            end
            ourApplyMinimapSize(nh)
            return true
        end
        w.onMouseRelease = function(self)
            if not self.drag then return false end
            self.drag = nil
            g_settings.set('ourMinimapHeight', ui:getHeight())
            if not isDocked() then g_settings.set('ourMinimapWidth', ui:getWidth()) end
            local parent = ui:getParent(); if parent and parent.fitAll then pcall(function() parent:fitAll(ui) end) end
            return true
        end
        w:raise()
        ui.ourGrips[name] = w
    end
    ui.ourResize = ui.ourGrips.B
    ui.ourResizeW = ui.ourGrips.R
    -- remember the panel after the player drags the minimap somewhere else
    connect(ui, { onParentChange = function()
        scheduleEvent(function()
            local parent = ui:getParent()
            if parent and parent.getClassName and parent:getClassName() == 'UIMiniWindowContainer' then
                g_settings.set('ourMinimapPanel', parent:getId()); ourApplyMinimapSize()
            end
        end, 50)
    end })
    connect(ui, { onGeometryChange = function() scheduleEvent(function() ourApplyMinimapSize(ui:getHeight()) end, 1) end })
end

-- 18.10.2026: also works without the top menu icon (the Map button under PvP)
-- 19.10.2026 (Tobeto): Options -> Interface -> HUD -> "Show minimap" (instead of the Map button)
function setVisible(on)
    local ui = mapController and mapController.ui
    if not ui then return end
    if (ui:isVisible() and true or false) ~= (on and true or false) then toggle() end
    -- the minimap goes back to the top of its panel (above health / mana)
    local p = ui:getParent()
    if on and p and p.moveChildToIndex and p:getChildIndex(ui) ~= 1 then
        p:moveChildToIndex(ui, 1)
        if p.fitAll then pcall(function() p:fitAll() end) end
    end
end
function toggle()
    local ui = mapController and mapController.ui
    if not ui then return end
    local open = ui:isVisible()
    if open then
        ui:hide()
    else
        ui:show()
        if ui.open then pcall(function() ui:open() end) end
        ui:raise()
    end
    if iconTopMenu then iconTopMenu:setOn(not open) end
end
