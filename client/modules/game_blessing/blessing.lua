BlessingController = Controller:new()

local BLESSINGS_LIST = {
    { flag = Blessings.Adventurer,         name = "Adventurer's Blessing" },
    { flag = Blessings.TwistOfFate,        name = "Twist of Fate"         },
    { flag = Blessings.WisdomOfSolitude,   name = "Wisdom of Solitude"    },
    { flag = Blessings.SparkOfPhoenix,     name = "Spark of the Phoenix"  },
    { flag = Blessings.FireOfSuns,         name = "Fire of the Suns"      },
    { flag = Blessings.SpiritualShielding, name = "Spiritual Shielding"   },
    { flag = Blessings.EmbraceOfTibia,     name = "Embrace of Tibia"      },
    { flag = Blessings.HeartOfMountain,    name = "Heart of the Mountain" },
    { flag = Blessings.BloodOfMountain,    name = "Blood of the Mountain" },
}

local GLOWSTATE ={
    Disabled = 1,
    Normal = 2,
    Green = 3
}

local VISUAL_STATE_IMAGES = {
    [GLOWSTATE.Disabled] = '/images/inventory/button_blessings_grey',
    [GLOWSTATE.Normal] = '/images/inventory/button_blessings_gold',
    [GLOWSTATE.Green] = '/images/inventory/button_blessings_green',
}

function BlessingController:onInit()
    BlessingController:registerEvents(LocalPlayer, {
        onBlessingsChange = onBlessingsChange
    })
end

function BlessingController:onTerminate()
    -- BlessingController:findWidget("#blessingsWindow"):destroy()
end

function BlessingController:onGameStart()
    if g_game.getClientVersion() >= 1000 then
        BlessingController:registerEvents(g_game, {
            onUpdateBlessDialog = onUpdateBlessDialog
        })
    else
        BlessingController:scheduleEvent(function()
            g_modules.getModule("game_blessing"):unload()
        end, 100, "unloadModule")
    end
end

function BlessingController:onGameEnd()
    hide()
end

function BlessingController:close()
    hide()
end

function BlessingController:showHistory()
    local ui = BlessingController.ui
    if ui.historyPanel:isVisible() then
        BlessingController.historyButtonText = "History"
        setBlessingView()
    else
        BlessingController.historyButtonText = "Back"
        setHistoryView()
    end
end

function setHistoryView()
    local ui = BlessingController.ui
    ui.blessingsRecordPanel:hide()
    ui.promotionPanel:hide()
    ui.deathPenaltyPanel:hide()
    ui.historyPanel:show()
end

function setBlessingView()
    local ui = BlessingController.ui
    ui.blessingsRecordPanel:show()
    ui.promotionPanel:show()
    ui.deathPenaltyPanel:show()
    ui.historyPanel:hide()
end

function show()
    BlessingController.historyButtonText = "History"
    g_ui.importStyle("style.otui")
    BlessingController:loadHtml('blessing.html')
    g_game.requestBless()
    -- OurTibia (06.10.2026): the 10.98 server answers through the HUD opcode
    if modules.game_myotshud and modules.game_myotshud.command then modules.game_myotshud.command('bless') end
    BlessingController.ui:show()
    BlessingController.ui:raise()
    BlessingController.ui:focus()
    setBlessingView()
end

function hide()
    if BlessingController.ui then
        BlessingController:unloadHtml()
    end
end

function toggle()
    if BlessingController.ui and BlessingController.ui:isVisible() then
        hide()
    else
        show()
    end
end

function onUpdateBlessDialog(data)
    local ui = BlessingController.ui
    ui.blessingsRecordPanel:destroyChildren()
    for i, entry in ipairs(data.blesses) do
        local label = g_ui.createWidget("blessingTEST", ui.blessingsRecordPanel)
        local totalCount = entry.playerBlessCount + entry.store
        label.text:setText(entry.playerBlessCount .. " (" .. entry.store .. ")")
        local img = entry.img or i
        label.enabled:setImageSource(totalCount >= 1 and ("images/" .. img .. "_on") or ("images/" .. img))
    end
    local promotionText = (data.promotion ~= 0) and
                              "Your character is promoted and your account has Premium\nstatus. As a result, your XP loss is reduced by {30%, #f75f5f}." or
                              "Your character is promoted and your account has Premium\nstatus. As a result, your XP loss is reduced by {0%, #f75f5f}."
    ui.promotionPanel.promotionStatusLabel:setColoredText(promotionText)
    ui.deathPenaltyPanel.fightRulesLabel:setColoredText(
        "- Depending on the fair fight rules, you will lose between {" .. data.pvpMinXpLoss .. ", #f75f5f} and {" ..
            data.pvpMaxXpLoss .. "%, #f75f5f} less XP and skill points \nupon your next PvP death.")
    ui.deathPenaltyPanel.expLossLabel:setColoredText("- You will lose {" .. data.pveExpLoss ..
                                                         "%, #f75f5f}% less XP and skill points upon your next PvE death.")
    ui.deathPenaltyPanel.containerLossLabel:setColoredText("- There is a {" .. data.equipPvpLoss ..
                                                               "%, #f75f5f} chance that you will lose your equipped container on your next death.")

    ui.deathPenaltyPanel.equipmentLossLabel:setColoredText("- There is a {" .. data.equipPveLoss ..
                                                               "%, #f75f5f} chance that you will lose items upon your next death.")
    ui.historyPanel.historyScrollArea:destroyChildren()
    local headerRow = g_ui.createWidget("historyData", ui.historyPanel.historyScrollArea)
    headerRow:setBackgroundColor("#363636")
    headerRow:setBorderColor("#00000077")
    headerRow:setBorderWidth(1)
    headerRow.rank:setText("date")
    headerRow.name:setText("Event")
    headerRow.rank:setColor("#c0c0c0")
    headerRow.name:setColor("#c0c0c0")
    for index, entry in ipairs(data.logs) do
        local row = g_ui.createWidget("historyData", ui.historyPanel.historyScrollArea)
        local date = os.date("%Y-%m-%d, %H:%M:%S", entry.timestamp)
        row:setBackgroundColor(index % 2 == 0 and "#ffffff12" or "#00000012")
        row.rank:setText(date)
        row.name:setText(entry.historyMessage)
    end
end

function BlessingController:onClickSendStore()
    modules.game_store.toggle()
    g_game.sendRequestStorePremiumBoost()
end

function onBlessingsChange(player, blessings, oldBlessings, blessVisualState)
    local hasAdventurerBlessing = Bit.hasBit(blessings, Blessings.Adventurer)
    if hasAdventurerBlessing ~= Bit.hasBit(oldBlessings, Blessings.Adventurer) then
        modules.game_inventory.toggleAdventurerStyle(hasAdventurerBlessing)
    end
    local blessedButton = modules.game_inventory.getButtonBlessings()
    if not blessedButton then
        return
    end
    if blessings == Blessings.None then
        blessedButton:setTooltip('You are currently not protected by any blessing.')
    else
        local lines = {'You are protected by the following blessings:'}
        for _, blessing in ipairs(BLESSINGS_LIST) do
            if Bit.hasBit(blessings, blessing.flag) then
                lines[#lines + 1] = '- ' .. blessing.name
            end
        end
        blessedButton:setTooltip(table.concat(lines, '\n'))
    end
    local image = VISUAL_STATE_IMAGES[blessVisualState]
    if image then
        blessedButton:setImageSource(image)
    end
end

-- OurTibia (06.10.2026): fill the dialog from the server's HUD opcode (TFS bless ids 1-6)
-- dialog order: Twist of Fate, Wisdom of Solitude, Spark of the Phoenix, Fire of the Suns,
-- Spiritual Shielding, Embrace of Tibia
function ourBless(d)
    local b0 = type(d.b) == 'table' and d.b or {}
    local names = {[1]='Spiritual Shielding',[2]='Embrace of Tibia',[3]='Fire of the Suns',[4]='Spark of the Phoenix',[5]='Wisdom of Solitude',[6]='Twist of Fate'}
    local lines, any = {'You are protected by the following blessings:'}, false
    -- 07.10.2026: Twist of Fate is not used on OurTibia; the icon glows green with all 5 blessings
    local have = 0
    for i = 1, 5 do if tonumber(b0[i]) == 1 then any = true; have = have + 1; lines[#lines + 1] = '- ' .. names[i] end end
    local button = modules.game_inventory and modules.game_inventory.getButtonBlessings and modules.game_inventory.getButtonBlessings()
    if button then
        button:setTooltip(any and (table.concat(lines, '\n') .. (have == 5 and '\n\nAll blessings - you are fully protected.' or '')) or 'You are currently not protected by any blessing.')
        local state = have == 5 and GLOWSTATE.Green or (any and GLOWSTATE.Normal or GLOWSTATE.Disabled)
        button:setImageSource(VISUAL_STATE_IMAGES[state])
    end
    if not BlessingController.ui then return end
    -- dialog slots (images 2-6): Wisdom of Solitude, Spark of the Phoenix, Fire of the Suns,
    -- Spiritual Shielding, Embrace of Tibia (slot 1 = Twist of Fate is left out)
    local order = {5, 4, 3, 1, 2}
    local b = type(d.b) == 'table' and d.b or {}
    local blesses, count = {}, 0
    for slot, id in ipairs(order) do
        local has = tonumber(b[id]) == 1 and 1 or 0
        count = count + has
        blesses[#blesses + 1] = {playerBlessCount = has, store = 0, img = slot + 1}
    end
    local promoted = tonumber(d.promoted) == 1 and tonumber(d.premium) == 1
    onUpdateBlessDialog({
        blesses = blesses,
        promotion = promoted and 1 or 0,
        pvpMinXpLoss = count * 8, pvpMaxXpLoss = count * 8,
        pveExpLoss = count * 8 + (promoted and 30 or 0),
        equipPvpLoss = count >= 5 and 0 or 100,
        equipPveLoss = count >= 5 and 0 or 10,
        logs = {}
    })
end
