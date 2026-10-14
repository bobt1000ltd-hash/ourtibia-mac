-- Public Mythibia creature portraits, matched by exact creature name.
OurTibiaArt = {}
local portraits
local function loadPortraits()
  if portraits then return portraits end
  local ok, data = pcall(function() return json.decode(g_resources.readFileContents('/data/myots/creature-art.json')) end)
  portraits = ok and data or {}
  return portraits
end
function OurTibiaArt.hasCreatureArt(outfit, name)
  local portrait = loadPortraits()[(name or ''):lower()]
  if portrait and portrait.image and g_resources.fileExists(portrait.image) then return true end
  local id = outfit and outfit.type or 0
  local objectId = outfit and outfit.typeex or 0
  if id > 0 then
    local thing = g_things.getThingType(id, ThingCategoryCreature)
    return thing and thing:getId() == id or false
  end
  if objectId > 0 then
    local thing = g_things.getThingType(objectId, ThingCategoryItem)
    return thing and thing:getId() == objectId or false
  end
  return false
end
-- 09.10.2026: every picture (portrait, object, placeholder) is a centered square that
-- fills the smaller side of its box, so all creatures/items show at the same size.
local function fitSquare(overlay, host)
  local w, h = host:getWidth(), host:getHeight()
  local side = math.min(w, h)
  overlay:breakAnchors()
  if side > 0 then
    overlay:addAnchor(AnchorHorizontalCenter, host:getId(), AnchorHorizontalCenter)
    overlay:addAnchor(AnchorVerticalCenter, host:getId(), AnchorVerticalCenter)
    overlay:setSize({width = side, height = side})
  else
    for _, edge in ipairs({AnchorLeft, AnchorTop, AnchorRight, AnchorBottom}) do overlay:addAnchor(edge, host:getId(), edge) end
  end
end
OurTibiaArt.fitSquare = fitSquare
function OurTibiaArt.placeholder(widget)
  local parent = widget:getParent()
  local id = widget:getId() .. 'MissingArt'
  local image = parent:getChildById(id)
  if not image then
    image = g_ui.createWidget('UIWidget', parent)
    image:setId(id)
    image:setPhantom(true)
    for _, edge in ipairs({AnchorLeft, AnchorTop, AnchorRight, AnchorBottom}) do
      image:addAnchor(edge, widget:getId(), edge)
    end
    image:setImageFixedRatio(true)
    image:setImageSource('/images/myots/wiki-item-placeholder.png')
  end
  fitSquare(image, widget)
  image:show()
  widget:hide()
  return true
end
function OurTibiaArt.creature(widget, outfit, name)
  local fallback = widget:getParent():getChildById(widget:getId() .. 'MissingArt')
  if fallback then fallback:hide() end
  local record = loadPortraits()[(name or ''):lower()]
  local parent = widget:getParent()
  local id = widget:getId() .. 'ReferenceArt'
  local image = parent:getChildById(id)
  local object = parent:getChildById(widget:getId() .. 'ReferenceObject')
  if object then object:hide() end
  if record then
    if not image then
      image = g_ui.createWidget('UIWidget', parent); image:setId(id);image:setPhantom(true)
      for _,edge in ipairs({AnchorLeft,AnchorTop,AnchorRight,AnchorBottom}) do image:addAnchor(edge,widget:getId(),edge) end
      image:setImageFixedRatio(true)
    end
    image:setImageSource(record.image)
    -- 07.10.2026: crop the portrait to the creature itself (the Mythibia images have
    -- different empty borders, so the same box showed big and tiny monsters)
    if record.clip then image:setImageClip(record.clip) else image:setImageClip('0 0 0 0') end
    -- 09.10.2026: the (square) crop is stretched over a centered square box - same size for all
    image:setImageFixedRatio(not record.clip)
    fitSquare(image, widget)
    image:show();widget:hide()
    return true
  end
  if image then image:hide() end
  local id = outfit and outfit.type or 0
  local objectId = outfit and outfit.typeex or 0
  if id == 0 and objectId > 0 then
    local thing = g_things.getThingType(objectId, ThingCategoryItem)
    if thing and thing:getId() == objectId then
      if not object then
        object = g_ui.createWidget('UIItem', parent)
        object:setId(widget:getId() .. 'ReferenceObject');object:setPhantom(true)
        for _,edge in ipairs({AnchorLeft,AnchorTop,AnchorRight,AnchorBottom}) do object:addAnchor(edge,widget:getId(),edge) end
      end
      fitSquare(object, widget)
      object:setItemId(objectId);object:show();widget:hide();return true
    end
  end
  -- Do not cache an empty DAT table before login or keep it across version changes.
  local thing = id > 0 and g_things.getThingType(id, ThingCategoryCreature)
  local valid = thing and thing:getId() == id
  widget:setVisible(valid and true or false)
  if valid then
    widget:setOutfit(outfit)
    -- 09.10.2026: scale the outfit to its real size and center it, so small and big
    -- creatures fill the box the same way (like the cropped portraits)
    pcall(function()
      local real = thing.getRealSize and thing:getRealSize() or 0
      -- 10.10.2026: setCreatureSize also resized the widget (a 64 px creature made its
      -- box 64 px wide and pushed the text next to it) - keep the box size of the layout.
      local box = widget:getSize()
      local side = math.min(box.width, box.height)
      if widget.setCreatureSize and real and real > 0 then widget:setCreatureSize(side > 0 and side or math.max(32, real)) end
      if widget.setCenter then widget:setCenter(true) end
      if box.width > 0 and box.height > 0 then widget:setSize(box) end
    end)
  end
  if valid then return true end
  return OurTibiaArt.placeholder(widget)
end
