--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.0.0
description: Wait for a configured number of minutes, then enable AutoRetainer MultiMode.
configs:
  Minutes Before Enabling MultiMode:
    description: Minutes to wait before enabling AutoRetainer MultiMode
    default: 5
    min: 1
    max: 1440
[[End Metadata]]
--]=====]

local PREFIX = "[MultiMode Timer]"

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

local waitMinutes = 5
if Config and Config.Get then
    local configured = tonumber(Config.Get("Minutes Before Enabling MultiMode"))
    if configured ~= nil then
        waitMinutes = math.max(1, math.floor(configured))
    end
end

if not hasAutoRetainerIpc() then
    log("AutoRetainer IPC unavailable; exiting.")
    return
end

local waitSeconds = waitMinutes * 60

log(string.format("Countdown started for %d minute(s).", waitMinutes))
sleep(waitSeconds)
enableMultiMode()
log("Exiting.")
