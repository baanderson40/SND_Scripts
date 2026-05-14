--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.0.0
description: Wait for gathering to finish, then enable AutoRetainer MultiMode.
configs:
  Idle Seconds After Gather:
    description: Seconds continuously in normal condition before considering gathering complete
    default: 300
    min: 1
    max: 1800
[[End Metadata]]
--]=====]

local PREFIX = "[Gather Monitor]"

local CharacterCondition = {
    normalConditions = 1,
    gathering = 6,
    executingGatheringAction = 42,
}

local function sleep(seconds)
    yield(string.format("/wait %.1f", tonumber(seconds) or 0))
end

local function log(message)
    local text = string.format("%s %s", PREFIX, tostring(message))
    Dalamud.Log(text)
end

local function announceStart(message)
    local text = string.format("%s %s", PREFIX, tostring(message))
    Dalamud.Log(text)
    yield(string.format("/echo %s", text))
end

local function hasAutoRetainerIpc()
    return IPC
        and IPC.AutoRetainer
        and IPC.AutoRetainer.SetMultiModeEnabled
end

local function isGatheringActive()
    if not (Svc and Svc.Condition) then
        return false
    end

    return Svc.Condition[CharacterCondition.gathering] == true
        or Svc.Condition[CharacterCondition.executingGatheringAction] == true
end

local function isNormalConditionActive()
    if not (Svc and Svc.Condition) then
        return false
    end

    return Svc.Condition[CharacterCondition.normalConditions] == true
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

local idleSeconds = 300
if Config and Config.Get then
    local configured = tonumber(Config.Get("Idle Seconds After Gather"))
    if configured ~= nil then
        idleSeconds = math.max(1, math.floor(configured))
    end
end

if not hasAutoRetainerIpc() then
    log("AutoRetainer IPC unavailable; exiting.")
    return
end

announceStart("Started. Waiting for gathering activity.")

while not isGatheringActive() do
    sleep(1)
end

log("Gather activity detected.")

local idleFor = 0

while idleFor < idleSeconds do
    if isNormalConditionActive() then
        if idleFor == 0 then
            log("Normal condition detected; idle timer started.")
        end
        idleFor = idleFor + 1
    else
        if idleFor > 0 then
            log("Condition changed; idle timer reset.")
            idleFor = 0
        end
    end

    if idleFor >= idleSeconds then
        break
    end

    sleep(1)
end

enableMultiMode()
log("Exiting.")
