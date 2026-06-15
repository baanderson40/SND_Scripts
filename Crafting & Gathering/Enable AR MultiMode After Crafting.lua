--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.1.0
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

local function isAddonReady(name)
    local ok, addon = pcall(Addons.GetAddon, name)
    return ok and addon and addon.Ready and addon.Exists or false
end

local function quoteArg(value)
    local text = tostring(value)
    text = text:gsub("\\", "\\\\"):gsub('"', '\\"')
    return '"' .. text .. '"'
end

local function safeCallback(...)
    local args = { ... }
    local index = 1
    local addon = args[index]
    index = index + 1

    if type(addon) ~= "string" or addon == "" then
        log("SafeCallback skipped: invalid addon name.")
        return false
    end

    local update = args[index]
    index = index + 1
    local updateStr = "true"

    if type(update) == "boolean" then
        updateStr = update and "true" or "false"
    elseif type(update) == "string" then
        local normalized = update:lower()
        if normalized == "false" or normalized == "f" or normalized == "0" or normalized == "off" then
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

local function hasAutoRetainerIpc()
    return IPC
        and IPC.AutoRetainer
        and IPC.AutoRetainer.SetMultiModeEnabled
end

local function isCraftStartActive()
    if not (Svc and Svc.Condition) then
        return false
    end

    return Svc.Condition[CharacterCondition.preparingToCraft] == true
        or Svc.Condition[CharacterCondition.executingCraftingAction] == true
end

local function isCraftFlowActive()
    if not (Svc and Svc.Condition) then
        return false
    end

    return Svc.Condition[CharacterCondition.executingCraftingAction] == true
        or Svc.Condition[CharacterCondition.occupiedMateriaExtractionAndRepair] == true
end

local function closeRecipeNote()
    if safeCallback("RecipeNote", -1) then
        log("Closed RecipeNote before enabling MultiMode.")
        sleep(2)
    end
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

while not isCraftStartActive() do
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

closeRecipeNote()
enableMultiMode()
log("Exiting.")
