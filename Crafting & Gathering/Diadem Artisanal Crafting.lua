--[=====[
[[SND Metadata]]
author: baanderson40
version: 0.1.2
description: |
  Monitor Diadem gathering materials, approve them in the Firmament, craft a selected Grade 4 Artisanal Skybuilders' item with Artisan, then turn it in to Potkin.
  Requires an existing GatherBuddy Reborn auto-gather list with the required ingredients already enabled.
plugin_dependencies:
- GatherBuddyReborn
- vnavmesh
- Artisan
- PandorasBox
configs:
  Craft Item:
    description: Grade 4 Artisanal Skybuilders' craft to make and turn in
    default: "Grade 4 Artisanal Skybuilders' Icebox"
    is_choice: true
    choices: ["Grade 4 Artisanal Skybuilders' Icebox", "Grade 4 Artisanal Skybuilders' Chocobo Weathervane", "Grade 4 Artisanal Skybuilders' Company Chest", "Grade 4 Artisanal Skybuilders' Astroscope", "Grade 4 Artisanal Skybuilders' Tool Belt", "Grade 4 Artisanal Skybuilders' Vest", "Grade 4 Artisanal Skybuilders' Tincture", "Grade 4 Artisanal Skybuilders' Sorbet"]
  Target Amount:
    description: Number of selected crafted items to make this run
    default: 10
    min: 1
    max: 999
  Turn-in Cycles:
    description: Number of full gather, craft, and turn-in cycles to perform; 0 repeats indefinitely
    default: 1
    min: 0
    max: 999
  Follow-up script:
    description: SND script to run after this Diadem script completes successfully
    default: ""
  Enable AutoRetainer multi-mode after completion?:
    description: Turn on AutoRetainer multi-mode when this script finishes successfully
    default: false
[[End Metadata]]
--]=====]

import("System.Numerics")

math.randomseed(os.time())

local PREFIX = "[Diadem Craft]"

local DIADEM_TERRITORY_ID = 939
local FIRMAMENT_TERRITORY_ID = 886

local FLOTPASSANT = {
    name = "Flotpassant",
    ids = { 1031693, 1035538 },
    fallbackPosition = Vector3(-21.26, -16.00, 138.93),
}

local POTKIN = {
    name = "Potkin",
    ids = { 1031677, 1031690, 1035536 },
    fallbackPosition = Vector3(52.750366, -16.0, 168.9325),
}

local CRAFT_POSITION = Vector3(37.868, -16.000, 164.464)
local CRAFT_POSITION_RADIUS = 15.0
local POTKIN_TARGET_COMMAND = '/target "Potkin"'

local CHARACTER_CONDITION = {
    mounted = 4,
    crafting = 5,
    occupiedMateriaExtractionAndRepair = 39,
    executingCraftingAction = 40,
    preparingToCraft = 41,
    betweenAreas = 45,
    betweenAreasForDuty = 51,
}

local TIME = {
    POLL = 0.2,
    SHORT = 0.5,
    MEDIUM = 1.0,
    LONG = 2.0,
}

local FLOTPASSANT_CALLBACK_DELAY = 1.0
local POTKIN_TURNIN_DELAY = 1.0

local MINIMUM_COLLECTABILITY = 1

local CRAFT_CHOICES = {
    ["Grade 4 Artisanal Skybuilders' Icebox"] = { recipeId = 34473, outputItemId = 31953, inventoryItemId = 531953 },
    ["Grade 4 Artisanal Skybuilders' Chocobo Weathervane"] = { recipeId = 34474, outputItemId = 31954, inventoryItemId = 531954 },
    ["Grade 4 Artisanal Skybuilders' Company Chest"] = { recipeId = 34475, outputItemId = 31955, inventoryItemId = 531955 },
    ["Grade 4 Artisanal Skybuilders' Astroscope"] = { recipeId = 34476, outputItemId = 31956, inventoryItemId = 531956 },
    ["Grade 4 Artisanal Skybuilders' Tool Belt"] = { recipeId = 34477, outputItemId = 31957, inventoryItemId = 531957 },
    ["Grade 4 Artisanal Skybuilders' Vest"] = { recipeId = 34478, outputItemId = 31958, inventoryItemId = 531958 },
    ["Grade 4 Artisanal Skybuilders' Tincture"] = { recipeId = 34479, outputItemId = 31959, inventoryItemId = 531959 },
    ["Grade 4 Artisanal Skybuilders' Sorbet"] = { recipeId = 34480, outputItemId = 31960, inventoryItemId = 531960 },
}

local CLASS_CONFIG = {
    miner = { callbackIndex = 0 },
    botanist = { callbackIndex = 1 },
    fisher = { callbackIndex = 2 },
}

local DIRECT_REAGENT_RANGES = {
    { first = 2, last = 19 },
}

local APPROVED_RANGES = {
    { first = 31991, last = 32004 },
    { first = 32926, last = 32933 },
}

local NON_APPROVED_RANGES = {
    { first = 32035, last = 32048 },
    { first = 32900, last = 32907 },
}

local function sleep(seconds)
    local value = tonumber(seconds) or 0
    if value < 0 then
        value = 0
    end
    value = math.floor(value * 10 + 0.5) / 10
    yield(string.format("/wait %.1f", value))
end

local function log(message)
    local text = string.format("%s %s", PREFIX, tostring(message))
    Dalamud.Log(text)
end

local function fail(message)
    log("ERROR: " .. tostring(message), true)
    return nil, message
end

local function trimString(value)
    if type(value) ~= "string" then
        return value
    end
    return value:match("^%s*(.-)%s*$") or value
end

local function normalizeConfigCommand(value)
    local trimmed = trimString(value)
    if type(trimmed) ~= "string" or trimmed == "" then
        return nil
    end
    return trimmed
end

local function setAutoRetainerMultiMode(enabled)
    if not IPC or not IPC.AutoRetainer or not IPC.AutoRetainer.SetMultiModeEnabled then
        log("Unable to set AutoRetainer multi-mode; IPC unavailable")
        return false
    end

    local ok, result = pcall(function()
        return IPC.AutoRetainer.SetMultiModeEnabled(enabled)
    end)
    if not ok then
        log("Failed to set AutoRetainer multi-mode: " .. tostring(result))
        return false
    end
    return result ~= false
end

local function runFollowUpScript(scriptName)
    local trimmed = normalizeConfigCommand(scriptName)
    if trimmed == nil then
        return false
    end

    local sanitized = trimmed:gsub('"', '\\"')
    log(string.format("Running follow-up script '%s'", trimmed))
    yield(string.format('/snd run "%s"', sanitized))
    return true
end

local function runCompletionFollowUp()
    local followUp = normalizeConfigCommand(Config and Config.Get and Config.Get("Follow-up script") or nil)
    if followUp ~= nil then
        return runFollowUpScript(followUp)
    end

    local enableMultiMode = Config and Config.Get and Config.Get("Enable AutoRetainer multi-mode after completion?") == true
    if enableMultiMode then
        log("Enabling AutoRetainer multi-mode")
        return setAutoRetainerMultiMode(true)
    end

    return true
end

local function toInteger(value, defaultValue, minValue, maxValue)
    local parsed = tonumber(value)
    if parsed == nil then
        return defaultValue
    end

    parsed = math.floor(parsed)
    if minValue ~= nil and parsed < minValue then
        parsed = minValue
    end
    if maxValue ~= nil and parsed > maxValue then
        parsed = maxValue
    end
    return parsed
end

local function normalizeName(value)
    local text = tostring(value or ""):lower()
    text = text:gsub("approved%s+", "")
    text = text:gsub("[^%w]", "")
    return text
end

local function isDirectReagentName(value)
    local text = tostring(value or ""):lower()
    return text:find("shard", 1, true) ~= nil
        or text:find("crystal", 1, true) ~= nil
        or text:find("cluster", 1, true) ~= nil
end

local function itemCount(itemId)
    if not (Inventory and Inventory.GetItemCount) then
        return 0
    end

    local ok, count = pcall(Inventory.GetItemCount, itemId)
    if not ok then
        return 0
    end
    return math.max(0, math.floor(tonumber(count) or 0))
end

local function getCraftedItemCount(craftConfig)
    if craftConfig == nil then
        return 0
    end

    if Inventory and Inventory.GetCollectableItemCount and craftConfig.outputItemId ~= nil then
        local okCollectable, collectableCount = pcall(Inventory.GetCollectableItemCount, craftConfig.outputItemId, MINIMUM_COLLECTABILITY)
        if okCollectable then
            local parsed = math.max(0, math.floor(tonumber(collectableCount) or 0))
            if parsed > 0 then
                return parsed
            end
        end
    end

    if craftConfig.inventoryItemId ~= nil then
        local inventoryCount = itemCount(craftConfig.inventoryItemId)
        if inventoryCount > 0 then
            return inventoryCount
        end
    end

    return itemCount(craftConfig.outputItemId)
end

local function currentTerritory()
    return Svc and Svc.ClientState and Svc.ClientState.TerritoryType or nil
end

local function isBusyZoning()
    if not (Svc and Svc.Condition) then
        return false
    end
    return Svc.Condition[CHARACTER_CONDITION.betweenAreas] == true
        or Svc.Condition[CHARACTER_CONDITION.betweenAreasForDuty] == true
end

local function isCraftingActive()
    if not (Svc and Svc.Condition) then
        return false
    end
    return Svc.Condition[CHARACTER_CONDITION.preparingToCraft] == true
        or Svc.Condition[CHARACTER_CONDITION.executingCraftingAction] == true
        or Svc.Condition[CHARACTER_CONDITION.occupiedMateriaExtractionAndRepair] == true
        or Svc.Condition[CHARACTER_CONDITION.crafting] == true
end

local function waitUntil(predicate, timeoutSec, pollSec, stableSec)
    timeoutSec = tonumber(timeoutSec) or 10
    pollSec = tonumber(pollSec) or TIME.POLL
    stableSec = tonumber(stableSec) or 0

    local startTime = os.clock()
    local holdStart = nil

    while (os.clock() - startTime) < timeoutSec do
        local ok, result = pcall(predicate)
        if ok and result then
            if holdStart == nil then
                holdStart = os.clock()
            end
            if (os.clock() - holdStart) >= stableSec then
                return true
            end
        else
            holdStart = nil
        end
        sleep(pollSec)
    end

    return false
end

local function isLifestreamBusy()
    if IPC and IPC.Lifestream and IPC.Lifestream.IsBusy then
        local ok, busy = pcall(IPC.Lifestream.IsBusy)
        return ok and busy == true
    end
    return false
end

local function waitForLifestreamIdle(timeoutSec)
    return waitUntil(function()
        return not isLifestreamBusy()
    end, timeoutSec or 30, TIME.POLL, 0.5)
end

local function waitForTerritoryStable(targetTerritoryId, holdSeconds, timeoutSeconds)
    return waitUntil(function()
        local zoneMatches = currentTerritory() == targetTerritoryId
        local moving = (Player and Player.IsMoving) or false
        return zoneMatches and not moving and not isBusyZoning()
    end, timeoutSeconds or 60, TIME.POLL, holdSeconds or 1.5)
end

local function getAddon(name)
    local ok, addon = pcall(Addons.GetAddon, name)
    if ok then
        return addon
    end
    return nil
end

local function isAddonReady(name)
    local addon = getAddon(name)
    if not addon then
        return false
    end
    return addon.Ready == true and addon.Exists == true
end

local function waitAddonReady(name, timeoutSec)
    return waitUntil(function()
        return isAddonReady(name)
    end, timeoutSec or 10, TIME.POLL, 0.2)
end

local function waitAddonClosed(name, timeoutSec)
    return waitUntil(function()
        return not isAddonReady(name)
    end, timeoutSec or 10, TIME.POLL, 0.2)
end

local function isAddonVisible(name)
    local addon = getAddon(name)
    if not addon then
        return false
    end

    return addon.Exists == true
        or addon.Visible == true
        or addon.IsVisible == true
        or addon.IsOpen == true
        or addon.Ready == true
end

local function handleTalkIfOpen()
    if not isAddonVisible("Talk") then
        return false
    end

    log("Advancing Talk addon.")
    Engines.Native.Run("/click Talk Click")
    sleep(TIME.SHORT)
    return true
end

local function handleSelectYesnoIfOpen()
    if not isAddonReady("SelectYesno") then
        return false
    end

    log("Confirming SelectYesno.")
    yield("/callback SelectYesno true 0")
    sleep(TIME.SHORT)
    waitAddonClosed("SelectYesno", 3)
    return true
end

local function getPandoraTurninAutomationState()
    if not (IPC and IPC.PandorasBox) then
        return nil
    end

    if not (IPC.PandorasBox.GetFeatureEnabled and IPC.PandorasBox.GetConfigEnabled) then
        return nil
    end

    local okFeature, featureEnabled = pcall(function()
        return IPC.PandorasBox.GetFeatureEnabled("Auto-select Turn-ins")
    end)
    local okConfig, configEnabled = pcall(function()
        return IPC.PandorasBox.GetConfigEnabled("Auto-select Turn-ins", "AutoConfirm")
    end)

    if not okFeature or not okConfig then
        return nil
    end

    return {
        featureEnabled = featureEnabled == true,
        configEnabled = configEnabled == true,
        changedFeature = false,
        changedConfig = false,
    }
end

local function enablePandoraTurninAutomation()
    local state = getPandoraTurninAutomationState()
    if state == nil then
        log("Pandora turn-in automation unavailable; continuing without Pandora support.")
        return nil
    end

    if state.featureEnabled and state.configEnabled then
        log("Pandora Auto-select Turn-ins and AutoConfirm already enabled.")
    else
        log("Ensuring Pandora Auto-select Turn-ins and AutoConfirm are enabled.")
    end

    if not state.featureEnabled and IPC.PandorasBox.SetFeatureEnabled then
        local ok = pcall(function()
            IPC.PandorasBox.SetFeatureEnabled("Auto-select Turn-ins", true)
        end)
        if ok then
            state.changedFeature = true
            log("Enabled Pandora Auto-select Turn-ins.")
        end
    end

    if not state.configEnabled and IPC.PandorasBox.SetConfigEnabled then
        local ok = pcall(function()
            IPC.PandorasBox.SetConfigEnabled("Auto-select Turn-ins", "AutoConfirm", true)
        end)
        if ok then
            state.changedConfig = true
            log("Enabled Pandora AutoConfirm.")
        end
    end

    return state
end

local function restorePandoraTurninAutomation(state)
    if state == nil or not (IPC and IPC.PandorasBox) then
        return
    end

    if not state.changedConfig and not state.changedFeature then
        return
    end

    log("Restoring Pandora turn-in settings.")

    if state.changedConfig and IPC.PandorasBox.SetConfigEnabled then
        pcall(function()
            IPC.PandorasBox.SetConfigEnabled("Auto-select Turn-ins", "AutoConfirm", false)
        end)
    end

    if state.changedFeature and IPC.PandorasBox.SetFeatureEnabled then
        pcall(function()
            IPC.PandorasBox.SetFeatureEnabled("Auto-select Turn-ins", false)
        end)
    end
end

local safeCallback

local function isCraftingConditionActive()
    if not (Svc and Svc.Condition) then
        return false
    end
    return Svc.Condition[CHARACTER_CONDITION.crafting] == true
end

local function closeRecipeNoteBlocking()
    local deadline = os.clock() + 15
    local closeAttempts = 0

    while os.clock() < deadline do
        local recipeNoteVisible = isAddonReady("RecipeNote")
        local craftingActive = isCraftingConditionActive()

        if recipeNoteVisible then
            closeAttempts = closeAttempts + 1
            safeCallback("RecipeNote", true, -1)
            sleep(TIME.SHORT)
        elseif not craftingActive then
            return true
        end

        if not recipeNoteVisible and craftingActive then
            sleep(TIME.POLL)
        elseif not isAddonReady("RecipeNote") and not isCraftingConditionActive() then
            return true
        end
    end

    if isCraftingConditionActive() then
        return fail("Crafting condition did not clear after crafting.")
    end

    if isAddonReady("RecipeNote") then
        return fail("Failed to close RecipeNote after crafting.")
    end

    if closeAttempts == 0 then
        return true
    end

    return true
end

local function quoteArg(value)
    local text = tostring(value or "")
    text = text:gsub("\\", "\\\\"):gsub('"', '\\"')
    return '"' .. text .. '"'
end

safeCallback = function(...)
    local args = { ... }
    local index = 1
    local addon = args[index]
    index = index + 1

    if type(addon) ~= "string" or addon == "" then
        return false
    end

    local update = args[index]
    index = index + 1
    local updateStr = "true"

    if type(update) == "boolean" then
        updateStr = update and "true" or "false"
    elseif type(update) == "string" then
        local lowered = update:lower()
        if lowered == "false" or lowered == "f" or lowered == "0" or lowered == "off" then
            updateStr = "false"
        end
    else
        index = index - 1
    end

    if not isAddonReady(addon) then
        return false
    end

    local command = "/callback " .. addon .. " " .. updateStr
    for i = index, #args do
        local value = args[i]
        local valueType = type(value)
        if valueType == "number" then
            command = command .. " " .. tostring(value)
        elseif valueType == "boolean" then
            command = command .. " " .. (value and "true" or "false")
        elseif valueType == "string" then
            command = command .. " " .. quoteArg(value)
        end
    end

    yield(command)
    return true
end

local function stopVnav()
    if IPC and IPC.vnavmesh and IPC.vnavmesh.Stop then
        local shouldStop = false
        if IPC.vnavmesh.IsRunning then
            local okRun, running = pcall(IPC.vnavmesh.IsRunning)
            shouldStop = shouldStop or (okRun and running == true)
        end
        if IPC.vnavmesh.PathfindInProgress then
            local okPath, pathing = pcall(IPC.vnavmesh.PathfindInProgress)
            shouldStop = shouldStop or (okPath and pathing == true)
        end
        if shouldStop then
            pcall(IPC.vnavmesh.Stop)
        end
    end
end

function OnStop()
    stopVnav()
end

local function moveNear(position, stopDistance)
    stopDistance = tonumber(stopDistance) or 3.0
    if not (position and IPC and IPC.vnavmesh and IPC.vnavmesh.IsReady and IPC.vnavmesh.PathfindAndMoveTo) then
        return false
    end

    local ready = waitUntil(function()
        return IPC.vnavmesh.IsReady()
    end, 20, TIME.POLL, 0.5)
    if not ready then
        return false
    end

    local okMove, started = pcall(function()
        return IPC.vnavmesh.PathfindAndMoveTo(position, false)
    end)
    if not okMove or started == false then
        return false
    end

    local arrived = waitUntil(function()
        local player = Entity and Entity.Player
        if not (player and player.Position) then
            return false
        end
        local distance = Vector3.Distance(player.Position, position)
        if distance <= stopDistance then
            stopVnav()
            return true
        end
        return false
    end, 90, TIME.POLL, 0.2)

    stopVnav()
    return arrived
end

local function interactByName(name, timeoutSec)
    timeoutSec = tonumber(timeoutSec) or 5
    local entity = Entity and Entity.GetEntityByName and Entity.GetEntityByName(name)
    if not entity then
        return false
    end

    local startTime = os.clock()
    while (os.clock() - startTime) < timeoutSec do
        entity = Entity and Entity.GetEntityByName and Entity.GetEntityByName(name) or entity
        if not entity then
            return false
        end

        if name == POTKIN.name then
            yield(POTKIN_TARGET_COMMAND)
        else
            entity:SetAsTarget()
        end
        sleep(TIME.POLL)

        local target = Entity and Entity.Target or nil
        if target ~= nil then
            local targetName = tostring(target.Name or "")
            if targetName == name then
                local okInteract = pcall(function()
                    target:Interact()
                end)
                if okInteract then
                    return true
                end
            end
        end

        sleep(TIME.POLL)
    end
    return false
end

local function getSheetRow(sheetName, rowId)
    local sheet = Excel and Excel.GetSheet and Excel.GetSheet(sheetName)
    if not sheet then
        return nil
    end
    local ok, row = pcall(function()
        return sheet:GetRow(rowId)
    end)
    if ok then
        return row
    end
    return nil
end

local function tryField(row, key)
    if row == nil or key == nil then
        return nil
    end
    local ok, value = pcall(function()
        return row[key]
    end)
    if ok and value ~= nil then
        return value
    end
    return nil
end

local function readArrayField(row, baseName, index)
    local directKeys = {
        string.format("%s[%d]", baseName, index),
        string.format("%s%d", baseName, index),
    }
    for _, key in ipairs(directKeys) do
        local direct = tryField(row, key)
        if direct ~= nil then
            return direct
        end
    end

    local container = tryField(row, baseName)
    if container == nil then
        return nil
    end

    local indexes = { index, index + 1 }
    for _, testIndex in ipairs(indexes) do
        local okValue, value = pcall(function()
            return container[testIndex]
        end)
        if okValue and value ~= nil then
            return value
        end

        local okItem, itemValue = pcall(function()
            return container:get_Item(testIndex)
        end)
        if okItem and itemValue ~= nil then
            return itemValue
        end
    end

    return nil
end

local function extractName(value)
    if value == nil then
        return nil
    end
    if type(value) == "string" then
        local trimmed = value:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            return trimmed
        end
        return nil
    end

    local candidates = {
        function() return value.Name end,
        function() return value.Singular end,
        function() return value.Value and (value.Value.Name or value.Value.Singular) end,
        function() return value:GetText() end,
        function() return tostring(value) end,
    }
    for _, getter in ipairs(candidates) do
        local ok, result = pcall(getter)
        if ok and result ~= nil then
            local text = tostring(result):match("^%s*(.-)%s*$")
            if text ~= "" and text ~= "nil" then
                return text
            end
        end
    end
    return nil
end

local function extractNumber(value)
    if value == nil then
        return nil
    end
    if type(value) == "number" then
        return value
    end
    local direct = tonumber(value)
    if direct ~= nil then
        return direct
    end

    local candidates = {
        function() return value.RowId end,
        function() return value.Value end,
        function() return value.Amount end,
        function() return value.Count end,
    }
    for _, getter in ipairs(candidates) do
        local ok, result = pcall(getter)
        if ok then
            local parsed = tonumber(result)
            if parsed ~= nil then
                return parsed
            end
        end
    end
    return nil
end

local function getItemName(itemId)
    local row = getSheetRow("Item", itemId)
    if not row then
        return nil
    end
    return extractName(row.Name or row.Singular)
end

local function getNpcName(candidateIds, fallbackName)
    for _, id in ipairs(candidateIds or {}) do
        local row = getSheetRow("ENpcResident", id)
        if row then
            local name = extractName(row.Singular or row.Name)
            if name ~= nil then
                return name
            end
        end
    end
    return fallbackName
end

local function resolveNpc(runtime)
    local name = getNpcName(runtime.ids, runtime.name)
    local entity = Entity and Entity.GetEntityByName and Entity.GetEntityByName(name) or nil
    if entity then
        local entityId = tonumber(entity.DataId)
        for _, id in ipairs(runtime.ids or {}) do
            if entityId == tonumber(id) then
                return {
                    name = name,
                    entity = entity,
                    position = entity.Position or runtime.fallbackPosition,
                }
            end
        end
        return {
            name = name,
            entity = entity,
            position = entity.Position or runtime.fallbackPosition,
        }
    end

    return {
        name = name,
        entity = nil,
        position = runtime.fallbackPosition,
    }
end

local function classifyNonApprovedItem(itemId)
    itemId = tonumber(itemId)
    if not itemId then
        return nil
    end
    if (itemId >= 32035 and itemId <= 32039) or itemId == 32045 or itemId == 32046 then
        return "botanist"
    end
    if (itemId >= 32040 and itemId <= 32044) or itemId == 32047 or itemId == 32048 then
        return "miner"
    end
    if itemId >= 32900 and itemId <= 32907 then
        return "fisher"
    end
    return nil
end

local function deriveNonApprovedId(approvedId)
    approvedId = tonumber(approvedId)
    if not approvedId then
        return nil
    end
    if approvedId >= 31991 and approvedId <= 32004 then
        return 32035 + (approvedId - 31991)
    end
    if approvedId >= 32926 and approvedId <= 32933 then
        return 32900 + (approvedId - 32926)
    end
    return nil
end

local function scanMatchingItemId(targetName, startId, endId)
    local wanted = normalizeName(targetName)
    for itemId = startId, endId do
        local itemName = getItemName(itemId)
        if itemName ~= nil and normalizeName(itemName) == wanted then
            return itemId, itemName
        end
    end
    return nil, nil
end

local function resolveDirectItemId(ingredientName)
    if not isDirectReagentName(ingredientName) then
        return nil, nil
    end

    for _, range in ipairs(DIRECT_REAGENT_RANGES) do
        local itemId, itemName = scanMatchingItemId(ingredientName, range.first, range.last)
        if itemId ~= nil then
            return itemId, itemName
        end
    end

    return nil, nil
end

local function resolveApprovedItemId(ingredientName)
    for _, range in ipairs(APPROVED_RANGES) do
        local itemId, itemName = scanMatchingItemId(ingredientName, range.first, range.last)
        if itemId ~= nil then
            return itemId, itemName
        end
    end

    return nil, nil
end

local function buildRecipeMaterials(recipeId, quantity)
    local recipeRow = getSheetRow("Recipe", recipeId)
    if not recipeRow then
        return fail("Recipe row not found for id " .. tostring(recipeId))
    end

    local materials = {}
    for index = 0, 9 do
        local ingredientValue = readArrayField(recipeRow, "Ingredient", index)
        local ingredientName = extractName(ingredientValue)
        if ingredientName ~= nil and ingredientName ~= "" then
            local amountValue = readArrayField(recipeRow, "AmountIngredient", index)
            local amountPerCraft = toInteger(extractNumber(amountValue), 0, 0)
            if amountPerCraft > 0 then
                local directItemId, directItemName = resolveDirectItemId(ingredientName)
                if directItemId ~= nil then
                    table.insert(materials, {
                        ingredientName = ingredientName,
                        approvedItemId = directItemId,
                        approvedItemName = directItemName or ingredientName,
                        nonApprovedItemId = nil,
                        nonApprovedItemName = nil,
                        gatherClass = nil,
                        amountPerCraft = amountPerCraft,
                        totalRequired = amountPerCraft * quantity,
                        requiresApproval = false,
                    })
                    goto continue_ingredient
                end

                local approvedId, approvedName = resolveApprovedItemId(ingredientName)
                if approvedId == nil then
                    return fail("Could not resolve approved item id for ingredient '" .. ingredientName .. "'.")
                end

                local nonApprovedId = deriveNonApprovedId(approvedId)
                if nonApprovedId == nil then
                    return fail("Could not derive non-approved item id for ingredient '" .. ingredientName .. "'.")
                end

                local gatherClass = classifyNonApprovedItem(nonApprovedId)
                if gatherClass == nil then
                    return fail("Could not classify non-approved item id " .. tostring(nonApprovedId) .. ".")
                end

                table.insert(materials, {
                    ingredientName = ingredientName,
                    approvedItemId = approvedId,
                    approvedItemName = approvedName or ingredientName,
                    nonApprovedItemId = nonApprovedId,
                    nonApprovedItemName = getItemName(nonApprovedId) or ingredientName,
                    gatherClass = gatherClass,
                    amountPerCraft = amountPerCraft,
                    totalRequired = amountPerCraft * quantity,
                    requiresApproval = true,
                })
            end
        end
        ::continue_ingredient::
    end

    if #materials == 0 then
        return fail("Recipe " .. tostring(recipeId) .. " had no readable ingredients.")
    end

    return materials
end

local function materialReady(material)
    local approved = itemCount(material.approvedItemId)
    if material.requiresApproval == false then
        return approved >= material.totalRequired, approved, 0, approved
    end

    local nonApproved = itemCount(material.nonApprovedItemId)
    local total = approved + nonApproved
    return total >= material.totalRequired, approved, nonApproved, total
end

local function materialsFullyReady(materials)
    for _, material in ipairs(materials) do
        local ready = materialReady(material)
        if not ready then
            return false
        end
    end
    return true
end

local function buildMaterialSnapshot(materials)
    local parts = {}
    for _, material in ipairs(materials) do
        local approved = itemCount(material.approvedItemId)
        if material.requiresApproval == false then
            table.insert(parts, string.format("%s %d/%d", material.approvedItemName, approved, material.totalRequired))
        else
            local nonApproved = itemCount(material.nonApprovedItemId)
            table.insert(parts, string.format("%s A:%d N:%d/%d", material.approvedItemName, approved, nonApproved, material.totalRequired))
        end
    end
    return table.concat(parts, " | ")
end

local function waitForMaterials(materials)
    log("Waiting for required Diadem materials.", true)
    local lastSnapshot = ""
    while true do
        if materialsFullyReady(materials) then
            log("All required materials detected.", true)
            return true
        end

        local snapshot = buildMaterialSnapshot(materials)
        if snapshot ~= lastSnapshot then
            log(snapshot)
            lastSnapshot = snapshot
        end
        sleep(60)
    end
end

local function runGatherBuddyAuto(enabled)
    local command = enabled and "/gbr auto on" or "/gbr auto off"
    log("Running " .. command, true)
    yield(command)
end

local function ensureMaterialsReadyForCycle(materials)
    if materialsFullyReady(materials) then
        log("Materials already ready for this cycle; skipping GatherBuddy start.")
        return true
    end

    runGatherBuddyAuto(true)
    sleep(TIME.MEDIUM)
    return waitForMaterials(materials)
end

local function leaveDiademIfNeeded()
    if currentTerritory() ~= DIADEM_TERRITORY_ID then
        return true
    end

    if not (InstancedContent and InstancedContent.LeaveCurrentContent) then
        return fail("InstancedContent.LeaveCurrentContent unavailable.")
    end

    log("Leaving Diadem instance.", true)
    local okLeave = pcall(function()
        InstancedContent.LeaveCurrentContent()
    end)
    if not okLeave then
        return fail("Failed to call InstancedContent.LeaveCurrentContent().")
    end

    local left = waitUntil(function()
        return currentTerritory() ~= DIADEM_TERRITORY_ID and not isBusyZoning()
    end, 120, TIME.MEDIUM, 2.0)
    if left then
        return true
    end

    log("First leave attempt timed out; retrying once.", true)
    pcall(function()
        InstancedContent.LeaveCurrentContent()
    end)

    local retried = waitUntil(function()
        return currentTerritory() ~= DIADEM_TERRITORY_ID and not isBusyZoning()
    end, 60, TIME.MEDIUM, 2.0)
    if retried then
        return true
    end

    return fail("Failed to leave Diadem.")
end

local function ensureFirmament()
    local territory = currentTerritory()
    if territory == FIRMAMENT_TERRITORY_ID then
        log("Firmament territory confirmed.")
        return true
    end

    if territory == DIADEM_TERRITORY_ID then
        return fail("Expected to have left Diadem before Firmament travel.")
    end

    if not (IPC and IPC.Lifestream and IPC.Lifestream.ExecuteCommand) then
        return fail("IPC.Lifestream.ExecuteCommand unavailable.")
    end

    log("Not in Diadem or Firmament; traveling to Firmament via Lifestream.")
    stopVnav()

    if not waitForLifestreamIdle(5) then
        return fail("Lifestream did not become idle before Firmament travel.")
    end

    local okTravel, travelResult = pcall(function()
        return IPC.Lifestream.ExecuteCommand("Firmament")
    end)
    if not okTravel then
        return fail("Lifestream Firmament command failed: " .. tostring(travelResult))
    end

    sleep(TIME.SHORT)
    if not waitForTerritoryStable(FIRMAMENT_TERRITORY_ID, 1.5, 60) then
        return fail("Failed to arrive in Firmament via Lifestream.")
    end

    log("Firmament territory confirmed.")
    return true
end

local function moveToNpc(runtime, stopDistance)
    local npc = resolveNpc(runtime)
    if npc.entity ~= nil then
        npc.position = npc.entity.Position or npc.position
    end
    log("Moving to " .. npc.name .. ".")
    if not moveNear(npc.position, stopDistance or 3.5) then
        return fail("Failed to move near " .. npc.name .. ".")
    end
    return npc
end

local function openNpcAddon(runtime, addonName)
    local npc = moveToNpc(runtime, 3.5)
    if npc == nil then
        return nil
    end

    stopVnav()
    if isAddonReady(addonName) then
        return npc
    end

    for attempt = 1, 5 do
        if interactByName(npc.name, 3) then
            local opened = waitUntil(function()
                if isAddonReady(addonName) then
                    return true
                end
                if handleTalkIfOpen() then
                    return false
                end
                return false
            end, 6, TIME.POLL, 0.2)
            if opened then
                return npc
            end
        end
        sleep(1)
    end

    return fail("Failed to open addon '" .. addonName .. "' from " .. npc.name .. ".")
end

local function getEligibleNonApprovedInventoryByClass()
    local grouped = {
        miner = {},
        botanist = {},
        fisher = {},
    }

    for _, range in ipairs(NON_APPROVED_RANGES) do
        for itemId = range.first, range.last do
            local current = itemCount(itemId)
            if current >= 5 then
                local gatherClass = classifyNonApprovedItem(itemId)
                if gatherClass ~= nil and grouped[gatherClass] ~= nil then
                    table.insert(grouped[gatherClass], itemId)
                end
            end
        end
    end

    return grouped
end

local function hasEligibleNonApprovedInventory()
    local grouped = getEligibleNonApprovedInventoryByClass()
    for _, itemIds in pairs(grouped) do
        if #itemIds > 0 then
            return true, grouped
        end
    end
    return false, grouped
end

local function eligibleSignature(itemIds)
    local parts = {}
    for _, itemId in ipairs(itemIds) do
        table.insert(parts, tostring(itemId) .. ":" .. tostring(itemCount(itemId)))
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

local function processFlotpassantClass(eligibleIds, gatherClass, batchLabel)
    local config = CLASS_CONFIG[gatherClass]
    if config == nil then
        return fail("Unknown gather class '" .. tostring(gatherClass) .. "'.")
    end

    while true do
        if #eligibleIds == 0 then
            return true
        end

        if not isAddonReady("HWDGathereInspect") then
            local opened = openNpcAddon(FLOTPASSANT, "HWDGathereInspect")
            if opened == nil then
                return nil
            end
        end

        local beforeSignature = eligibleSignature(eligibleIds)
        log(string.format("Submitting %s %s batch (%d eligible items).", gatherClass, batchLabel, #eligibleIds), true)
        safeCallback("HWDGathereInspect", true, 14, config.callbackIndex)
        sleep(FLOTPASSANT_CALLBACK_DELAY)
        safeCallback("HWDGathereInspect", true, 12)
        sleep(FLOTPASSANT_CALLBACK_DELAY)
        safeCallback("HWDGathereInspect", true, 11)

        local changed = waitUntil(function()
            if handleSelectYesnoIfOpen() then
                return false
            end
            if not isAddonReady("HWDGathereInspect") then
                return true
            end
            return eligibleSignature(getEligibleNonApprovedInventoryByClass()[gatherClass]) ~= beforeSignature
        end, 12, TIME.SHORT, 0.5)
        if not changed then
            log(string.format("%s batch did not visibly change inventory; continuing cautiously.", batchLabel:gsub("^%l", string.upper)), true)
            sleep(TIME.LONG)
        end

        eligibleIds = getEligibleNonApprovedInventoryByClass()[gatherClass]
    end
end

local function approveEligibleNonApprovedInventory(batchLabel, emptyLogMessage)
    local hasEligible, grouped = hasEligibleNonApprovedInventory()
    if not hasEligible then
        log(emptyLogMessage, true)
        return true
    end

    local opened = openNpcAddon(FLOTPASSANT, "HWDGathereInspect")
    if opened == nil then
        return nil
    end

    local classOrder = { "miner", "botanist", "fisher" }
    for _, gatherClass in ipairs(classOrder) do
        local ok = processFlotpassantClass(grouped[gatherClass], gatherClass, batchLabel)
        if not ok then
            return nil
        end
    end

    if isAddonReady("HWDGathereInspect") then
        safeCallback("HWDGathereInspect", true, -1)
        waitAddonClosed("HWDGathereInspect", 3)
    end
    return true
end

local function approveMaterials(materials)
    if materials == nil then
        log("No eligible non-approved items detected; skipping Flotpassant.", true)
        return true
    end
    return approveEligibleNonApprovedInventory("approval", "No eligible non-approved items detected; skipping Flotpassant.")
end

local function approvedMaterialsReady(materials)
    for _, material in ipairs(materials) do
        if itemCount(material.approvedItemId) < material.totalRequired then
            return false, material
        end
    end
    return true, nil
end

local function hasEligibleRequiredNonApprovedMaterials(materials)
    for _, material in ipairs(materials) do
        if material.requiresApproval ~= false and itemCount(material.nonApprovedItemId) >= 5 then
            return true
        end
    end
    return false
end

local function getRequiredApprovalStateSignature(materials)
    local parts = {}
    for _, material in ipairs(materials) do
        local approved = itemCount(material.approvedItemId)
        local nonApproved = 0
        if material.requiresApproval ~= false then
            nonApproved = itemCount(material.nonApprovedItemId)
        end
        table.insert(parts, string.format("%s:%d:%d", tostring(material.approvedItemId), approved, nonApproved))
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

local function reconcileApprovedMaterials(materials)
    local passNumber = 0
    local previousSignature = nil

    while true do
        local approvedReady, blockingMaterial = approvedMaterialsReady(materials)
        if approvedReady then
            return true
        end

        if not hasEligibleRequiredNonApprovedMaterials(materials) then
            return fail(string.format(
                "Approved materials still insufficient after Flotpassant: %s (%d/%d approved).",
                tostring(blockingMaterial.approvedItemName),
                itemCount(blockingMaterial.approvedItemId),
                blockingMaterial.totalRequired
            ))
        end

        local currentSignature = getRequiredApprovalStateSignature(materials)
        if previousSignature ~= nil and currentSignature == previousSignature then
            return fail(string.format(
                "Approval state stopped progressing before crafting requirements were met: %s (%d/%d approved).",
                tostring(blockingMaterial.approvedItemName),
                itemCount(blockingMaterial.approvedItemId),
                blockingMaterial.totalRequired
            ))
        end

        previousSignature = currentSignature
        passNumber = passNumber + 1
        if passNumber > 1 then
            log(string.format("Rechecking Flotpassant approvals (pass %d).", passNumber))
        end

        if not approveMaterials(materials) then
            return nil
        end
    end
end

local function approveRemainingNonApprovedInventory()
    log("Eligible non-approved items remain; returning to Flotpassant before turn-in.", true)
    return approveEligibleNonApprovedInventory("cleanup", "No eligible non-approved items detected; skipping Flotpassant.")
end

local function getFreeInventorySlots()
    if not (Inventory and Inventory.GetFreeInventorySlots) then
        return nil
    end

    local ok, slots = pcall(Inventory.GetFreeInventorySlots)
    if not ok then
        return nil
    end

    return math.max(0, math.floor(tonumber(slots) or 0))
end

local function moveToCraftPosition()
    local angle = math.random() * (math.pi * 2)
    local radius = math.sqrt(math.random()) * CRAFT_POSITION_RADIUS
    local targetPosition = Vector3(
        CRAFT_POSITION.X + math.cos(angle) * radius,
        CRAFT_POSITION.Y,
        CRAFT_POSITION.Z + math.sin(angle) * radius
    )

    log("Moving to crafting position.")
    if not moveNear(targetPosition, 2.5) then
        return fail("Failed to move to crafting position.")
    end
    stopVnav()
    sleep(TIME.SHORT)
    return true
end

local function craftWithArtisan(craftConfig, quantity)
    if not (IPC and IPC.Artisan and IPC.Artisan.CraftItem) then
        return fail("IPC.Artisan.CraftItem unavailable.")
    end

    local recipeId = craftConfig.recipeId
    local startingCount = getCraftedItemCount(craftConfig)
    local targetCount = startingCount + quantity

    log(string.format("Starting Artisan craft for recipe %d x%d.", recipeId, quantity), true)
    local okCraft, craftResult = pcall(function()
        return IPC.Artisan.CraftItem(recipeId, quantity)
    end)
    if not okCraft then
        return fail("Artisan craft call failed: " .. tostring(craftResult))
    end

    local started = waitUntil(function()
        return isCraftingActive() or getCraftedItemCount(craftConfig) > startingCount
    end, 30, TIME.POLL, 0.5)
    if not started then
        return fail("Artisan craft did not begin.")
    end

    local lastCount = getCraftedItemCount(craftConfig)
    local lastChange = os.clock()
    while true do
        local currentCount = getCraftedItemCount(craftConfig)
        if currentCount >= targetCount then
            break
        end

        if currentCount ~= lastCount then
            log(string.format("Craft progress: %d/%d", currentCount - startingCount, quantity))
            lastCount = currentCount
            lastChange = os.clock()
        elseif isCraftingActive() then
            lastChange = os.clock()
        elseif (os.clock() - lastChange) > 120 then
            return fail("Crafting stalled before target output was reached.")
        end

        sleep(TIME.LONG)
    end

    if not closeRecipeNoteBlocking() then
        return nil
    end

    log("Crafting complete.", true)
    return true
end

local function turnInAtPotkin(craftConfig)
    local pandoraState = enablePandoraTurninAutomation()
    local function cleanupPandora()
        restorePandoraTurninAutomation(pandoraState)
    end

    local opened = openNpcAddon(POTKIN, "HWDSupply")
    if opened == nil then
        cleanupPandora()
        return nil
    end

    while getCraftedItemCount(craftConfig) > 0 do
        if not isAddonReady("HWDSupply") then
            opened = openNpcAddon(POTKIN, "HWDSupply")
            if opened == nil then
                cleanupPandora()
                return nil
            end
        end

        local before = getCraftedItemCount(craftConfig)
        log(string.format("Turning in %s at Potkin (%d remaining).", tostring(craftConfig.displayName or craftConfig.outputItemId), before))
        safeCallback("HWDSupply", true, 1, 0)

        local changed = waitUntil(function()
            if handleSelectYesnoIfOpen() then
                return false
            end
            return getCraftedItemCount(craftConfig) < before or not isAddonReady("HWDSupply")
        end, 12, TIME.SHORT, 0.5)
        if not changed then
            cleanupPandora()
            return fail("Potkin turn-in did not change inventory.")
        end

        if getCraftedItemCount(craftConfig) > 0 and isAddonReady("HWDSupply") then
            sleep(POTKIN_TURNIN_DELAY)
        end
    end

    if isAddonReady("HWDSupply") then
        safeCallback("HWDSupply", true, -1)
        waitAddonClosed("HWDSupply", 3)
    end
    cleanupPandora()
    log("All crafted items turned in.", true)
    return true
end

local function processCraftTurnInBatches(craftConfig, totalQuantity)
    local remainingToCraft = totalQuantity

    while remainingToCraft > 0 do
        local freeSlots = getFreeInventorySlots()
        if freeSlots == nil then
            return fail("Unable to determine free inventory slots before crafting.")
        end

        if freeSlots <= 0 then
            if getCraftedItemCount(craftConfig) > 0 then
                if not turnInAtPotkin(craftConfig) then
                    return nil
                end
                freeSlots = getFreeInventorySlots()
                if freeSlots == nil then
                    return fail("Unable to determine free inventory slots after turn-in.")
                end
            end

            if freeSlots == nil or freeSlots <= 0 then
                return fail(string.format(
                    "No free inventory slots available to craft remaining %d item(s).",
                    remainingToCraft
                ))
            end
        end

        local batchQuantity = math.min(remainingToCraft, freeSlots)
        log(string.format(
            "Free inventory slots: %d. Crafting batch of %d (%d remaining after batch).",
            freeSlots,
            batchQuantity,
            remainingToCraft - batchQuantity
        ))

        if not moveToCraftPosition() then
            return nil
        end

        if not craftWithArtisan(craftConfig, batchQuantity) then
            return nil
        end

        if not approveRemainingNonApprovedInventory() then
            return nil
        end

        if not turnInAtPotkin(craftConfig) then
            return nil
        end

        remainingToCraft = remainingToCraft - batchQuantity
    end

    return true
end

local craftChoice = Config and Config.Get and tostring(Config.Get("Craft Item") or "") or ""
local quantity = toInteger(Config and Config.Get and Config.Get("Target Amount") or 1, 1, 1, 999)
local totalCycles = toInteger(Config and Config.Get and Config.Get("Turn-in Cycles") or 1, 1, 0, 999)
local craftConfig = CRAFT_CHOICES[craftChoice]

if craftConfig == nil then
    fail("Invalid Craft Item config: " .. tostring(craftChoice))
    return
end

craftConfig.displayName = craftChoice

local materials, materialError = buildRecipeMaterials(craftConfig.recipeId, quantity)
if materials == nil then
    return
end

if totalCycles == 0 then
    log(string.format("Selected %s x%d for infinite cycles.", craftChoice, quantity))
else
    log(string.format("Selected %s x%d for %d cycle(s).", craftChoice, quantity, totalCycles))
end

local completedCycles = 0
while totalCycles == 0 or completedCycles < totalCycles do
    if not ensureMaterialsReadyForCycle(materials) then
        return
    end

    runGatherBuddyAuto(false)
    sleep(TIME.MEDIUM)

    if not leaveDiademIfNeeded() then
        return
    end

    if not ensureFirmament() then
        return
    end

    if not reconcileApprovedMaterials(materials) then
        return
    end

    if not processCraftTurnInBatches(craftConfig, quantity) then
        return
    end

    completedCycles = completedCycles + 1
    if totalCycles == 0 then
        log(string.format("Completed cycle %d (infinite mode).", completedCycles))
    else
        log(string.format("Completed cycle %d/%d.", completedCycles, totalCycles))
    end
end

if not runCompletionFollowUp() then
    return
end

log("Run complete.")
