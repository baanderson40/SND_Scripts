--[=====[
[[SND Metadata]]
author: baanderson40
version: 0.0.1
description: Start Henchman's On A Boat workflow and enable AutoRetainer MultiMode.
[[End Metadata]]
--]=====]

local PREFIX = "[Ocean Fishing Starter]"
local AUTODUTY_SETTLE_SECONDS = 10
local BUSY_TIMEOUT_SECONDS = 15
local POLL_INTERVAL_SECONDS = 1

local function log(message)
    local text = string.format("%s %s", PREFIX, tostring(message))
    Dalamud.Log(text)
    yield(string.format("/echo %s", text))
end

local function sleep(seconds)
    yield(string.format("/wait %.1f", seconds))
end

local function hasRequiredIpc()
    return IPC
        and IPC.Henchman
        and IPC.Henchman.IsBusy
        and IPC.Henchman.StartOnABoat
        and IPC.AutoRetainer
        and IPC.AutoRetainer.SetMultiModeEnabled
        and IPC.AutoRetainer.GetMultiModeEnabled
end

-- AutoDuty runs termination commands from its own task queue. Let its loop
-- shutdown and duty transition settle before starting another automation task.
sleep(AUTODUTY_SETTLE_SECONDS)
log(string.format("AutoDuty settle delay complete (%d seconds).", AUTODUTY_SETTLE_SECONDS))

local function invoke(description, callback)
    local ok, result = pcall(callback)
    if not ok then
        log(string.format("%s failed: %s", description, tostring(result)))
        return false, nil
    end

    return true, result
end

if not hasRequiredIpc() then
    log("Required Henchman or AutoRetainer IPC unavailable; exiting.")
    return
end

local ok, isBusy = invoke("Checking Henchman task state", function()
    return IPC.Henchman.IsBusy()
end)
if not ok then
    return
end

if isBusy then
    log("Henchman is already busy; not starting another task.")
    return
end

ok = invoke("Starting Henchman On A Boat", function()
    return IPC.Henchman.StartOnABoat()
end)
if not ok then
    return
end

ok = invoke("Enabling AutoRetainer MultiMode", function()
    return IPC.AutoRetainer.SetMultiModeEnabled(true)
end)
if not ok then
    return
end

local modeEnabled = false
ok, modeEnabled = invoke("Verifying AutoRetainer MultiMode", function()
    return IPC.AutoRetainer.GetMultiModeEnabled()
end)
if not ok then
    return
end

if not modeEnabled then
    log("AutoRetainer MultiMode did not report enabled; exiting.")
    return
end

local henchmanStarted = false
for _ = 1, BUSY_TIMEOUT_SECONDS do
    ok, isBusy = invoke("Checking Henchman task state", function()
        return IPC.Henchman.IsBusy()
    end)
    if not ok then
        return
    end

    if isBusy then
        henchmanStarted = true
        break
    end

    sleep(POLL_INTERVAL_SECONDS)
end

if not henchmanStarted then
    log(string.format("Henchman did not report a running task within %d seconds.", BUSY_TIMEOUT_SECONDS))
    return
end

log("Henchman On A Boat started and AutoRetainer MultiMode is enabled. Exiting.")
