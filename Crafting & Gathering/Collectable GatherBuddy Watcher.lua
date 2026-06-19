--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.0.0
description: Monitor a target item count, stop GatherBuddy AutoGather when the goal is met, then enable AutoRetainer MultiMode or run a follow-up script.
configs:
  Target Item ID:
    description: Item ID to monitor in inventory
    default: 0
    min: 0
    max: 9999999
  Target Count:
    description: Stop when inventory count reaches this amount
    default: 1
    min: 1
    max: 999999
  Start GatherBuddy AutoGather:
    description: Run /gbr auto on when the script starts
    default: true
  Enable AutoRetainer MultiMode After Completion:
    description: Enable AutoRetainer MultiMode after stopping GatherBuddy
    default: false
  Follow-Up Script Name:
    description: Optional script name to run with /snd run "name" after completion
    default: ""
[[End Metadata]]
--]=====]

local PREFIX = "[Collectable Watcher]"
local POLL_SECONDS = 30

local function sleep(seconds)
    yield(string.format("/wait %.1f", tonumber(seconds) or 0))
end

local function log(message, echo)
    local text = string.format("%s %s", PREFIX, tostring(message))
    Dalamud.Log(text)
    if echo ~= false then
        yield(string.format("/echo %s", text))
    end
end

local function getNumberConfig(name, defaultValue, minValue)
    if not (Config and Config.Get) then
        return defaultValue
    end

    local value = tonumber(Config.Get(name))
    if value == nil then
        return defaultValue
    end

    value = math.floor(value)
    if minValue ~= nil and value < minValue then
        value = minValue
    end
    return value
end

local function getBooleanConfig(name, defaultValue)
    if not (Config and Config.Get) then
        return defaultValue
    end

    local value = Config.Get(name)
    if value == nil then
        return defaultValue
    end

    return value == true
end

local function getStringConfig(name, defaultValue)
    if not (Config and Config.Get) then
        return defaultValue
    end

    local value = Config.Get(name)
    if value == nil then
        return defaultValue
    end

    return tostring(value)
end

local function getItemCount(itemId)
    if not (Inventory and Inventory.GetItemCount) then
        return nil, "Inventory.GetItemCount unavailable"
    end

    local ok, count = pcall(Inventory.GetItemCount, itemId)
    if not ok then
        return nil, count
    end

    return tonumber(count) or 0
end

local function hasAutoRetainerIpc()
    return IPC
        and IPC.AutoRetainer
        and IPC.AutoRetainer.SetMultiModeEnabled
end

local function enableMultiMode()
    if not hasAutoRetainerIpc() then
        log("AutoRetainer IPC unavailable; skipping MultiMode enable.")
        return false
    end

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

local function runGatherBuddyAuto(enabled)
    local command = enabled and "/gbr auto on" or "/gbr auto off"
    log("Running " .. command)
    yield(command)
end

local function quoteCommandArg(value)
    local text = tostring(value or "")
    text = text:gsub("\\", "\\\\"):gsub('"', '\\"')
    return '"' .. text .. '"'
end

local function runFollowUpScript(scriptName)
    local trimmed = tostring(scriptName or ""):match("^%s*(.-)%s*$") or ""
    if trimmed == "" then
        log("No follow-up script configured; skipping.")
        return false
    end

    local command = "/snd run " .. quoteCommandArg(trimmed)
    log("Starting follow-up script: " .. trimmed)
    yield(command)
    return true
end

local targetItemId = getNumberConfig("Target Item ID", 0, 0)
local targetCount = getNumberConfig("Target Count", 1, 1)
local startAutoGather = getBooleanConfig("Start GatherBuddy AutoGather", true)
local enableMultiModeAfterCompletion = getBooleanConfig("Enable AutoRetainer MultiMode After Completion", false)
local followUpScriptName = getStringConfig("Follow-Up Script Name", "")

if targetItemId <= 0 then
    log("Target Item ID must be greater than 0; exiting.")
    return
end

local startingCount, startingError = getItemCount(targetItemId)
if startingCount == nil then
    log("Failed to read starting inventory count: " .. tostring(startingError))
    return
end

log(string.format("Started for item %d. Current=%d, Target=%d.", targetItemId, startingCount, targetCount))

local function complete(finalCount)
    log(string.format("Target reached for item %d. Current=%d, Target=%d.", targetItemId, finalCount, targetCount))
    runGatherBuddyAuto(false)
    sleep(2)

    if enableMultiModeAfterCompletion then
        enableMultiMode()
    else
        log("AutoRetainer MultiMode disabled in config; skipping.", false)
    end

    runFollowUpScript(followUpScriptName)
    log("Exiting.")
end

if startingCount >= targetCount then
    complete(startingCount)
    return
end

if startAutoGather then
    runGatherBuddyAuto(true)
else
    log("Start GatherBuddy AutoGather disabled; monitoring only.")
end

local lastCount = startingCount

while true do
    sleep(POLL_SECONDS)

    local currentCount, currentError = getItemCount(targetItemId)
    if currentCount == nil then
        log("Failed to read inventory count: " .. tostring(currentError))
    else
        if currentCount ~= lastCount then
            log(string.format("Progress update for item %d: %d/%d.", targetItemId, currentCount, targetCount))
            lastCount = currentCount
        end

        if currentCount >= targetCount then
            complete(currentCount)
            return
        end
    end
end
