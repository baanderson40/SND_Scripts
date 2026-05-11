--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.0.0
description: Wait for crafting to finish, then enable AutoRetainer MultiMode.
configs:
  Idle Seconds After Craft:
    description: Seconds with no crafting or repair conditions before considering crafting complete
    default: 60
    min: 1
    max: 600
[[End Metadata]]
--]=====]

local PREFIX = "[Craft Monitor]"

local CharacterCondition = {
    occupiedMateriaExtractionAndRepair = 39,
    executingCraftingAction = 40,
    preparingToCraft = 41,
}

local function sleep(seconds)
    yield(string.format("/wait %.1f", tonumber(seconds) or 0))
end

local function log(message)
    local text = string.format("%s %s", PREFIX, tostring(message))
    Dalamud.Log(text)
    yield(string.format("/echo %s", text))
end

local function hasAutoRetainerIpc()
    return IPC
        and IPC.AutoRetainer
        and IPC.AutoRetainer.SetMultiModeEnabled
end

local function isCraftFlowActive()
    if not (Svc and Svc.Condition) then
        return false
    end

    return Svc.Condition[CharacterCondition.executingCraftingAction] == true
        or Svc.Condition[CharacterCondition.preparingToCraft] == true
        or Svc.Condition[CharacterCondition.occupiedMateriaExtractionAndRepair] == true
end

local function isCraftingActive()
    if not (Svc and Svc.Condition) then
        return false
    end

    return Svc.Condition[CharacterCondition.executingCraftingAction] == true
        or Svc.Condition[CharacterCondition.preparingToCraft] == true
end

local function enableMultiMode()
    local ok, result = pcall(function()
        return IPC.AutoRetainer.SetMultiModeEnabled(true)
    end)

    if not ok then
        log("Failed to enable AutoRetainer MultiMode: " .. tostring(result))
        return false
    end

    if result == false then
        log("AutoRetainer MultiMode call returned false.")
        return false
    end

    log("AutoRetainer MultiMode enabled.")
    return true
end

local idleSeconds = 60
if Config and Config.Get then
    local configured = tonumber(Config.Get("Idle Seconds After Craft"))
    if configured ~= nil then
        idleSeconds = math.max(1, math.floor(configured))
    end
end

if not hasAutoRetainerIpc() then
    log("AutoRetainer IPC unavailable; exiting.")
    return
end

log("Waiting for crafting activity.")

while not isCraftingActive() do
    sleep(1)
end

log("Craft activity detected.")

local idleFor = 0

while idleFor < idleSeconds do
    if isCraftFlowActive() then
        if idleFor > 0 then
            log("Craft activity resumed; idle timer reset.")
            idleFor = 0
        end
    else
        if idleFor == 0 then
            log("No craft activity detected; idle timer started.")
        end
        idleFor = idleFor + 1
    end

    if idleFor >= idleSeconds then
        break
    end

    sleep(1)
end

enableMultiMode()
log("Exiting.")
