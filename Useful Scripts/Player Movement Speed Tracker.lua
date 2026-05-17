--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.0.0
description: |
  Poll the player's position and log movement speed to the Dalamud console for travel-speed testing.
configs:
  Poll Interval:
    description: Seconds between position samples.
    default: 0.5
    min: 0.1
    max: 5
  Minimum Distance:
    description: Minimum flat distance moved before logging a sample.
    default: 0.5
    min: 0
    max: 20
  Log Only When Moving:
    description: Only print samples when the player moved at least the minimum distance.
    default: true
  Rolling Average Samples:
    description: Number of samples to include in the rolling flat-speed average.
    default: 5
    min: 1
    max: 30
[[End Metadata]]
--]=====]

import("System.Numerics")

local PREFIX = "[Speed Tracker]"

local function getConfigValue(name, fallback)
    local ok, value = pcall(function()
        return Config and Config.Get and Config.Get(name)
    end)

    if ok and value ~= nil then
        return value
    end

    return fallback
end

local POLL_INTERVAL = tonumber(getConfigValue("Poll Interval", 0.5)) or 0.5
local MINIMUM_DISTANCE = tonumber(getConfigValue("Minimum Distance", 0.5)) or 0.5
local LOG_ONLY_WHEN_MOVING = getConfigValue("Log Only When Moving", true) == true
local ROLLING_AVERAGE_SAMPLES = tonumber(getConfigValue("Rolling Average Samples", 5)) or 5

POLL_INTERVAL = math.max(0.1, math.min(5, POLL_INTERVAL))
MINIMUM_DISTANCE = math.max(0, math.min(20, MINIMUM_DISTANCE))
ROLLING_AVERAGE_SAMPLES = math.max(1, math.min(30, math.floor(ROLLING_AVERAGE_SAMPLES)))

local function sleep(seconds)
    yield(string.format("/wait %.2f", tonumber(seconds) or 0))
end

local function log(message)
    local text = string.format("%s %s", PREFIX, tostring(message))
    pcall(function()
        Dalamud.Log(text)
    end)
end

local function logf(fmt, ...)
    log(string.format(fmt, ...))
end

local function getPlayerPosition()
    if Entity and Entity.Player and Entity.Player.Position then
        return Entity.Player.Position
    end

    local ok, position = pcall(function()
        return Svc and Svc.ClientState and Svc.ClientState.LocalPlayer and Svc.ClientState.LocalPlayer.Position
    end)

    if ok then
        return position
    end

    return nil
end

local function getCondition(flag)
    if flag == nil or not (Svc and Svc.Condition) then
        return false
    end

    return Svc.Condition[flag] == true
end

local function flatDistance(a, b)
    if not (a and b) then
        return 0
    end

    local dx = a.X - b.X
    local dz = a.Z - b.Z
    return math.sqrt((dx * dx) + (dz * dz))
end

local speedHistory = {}

local function addSpeedSample(value)
    table.insert(speedHistory, value)
    while #speedHistory > ROLLING_AVERAGE_SAMPLES do
        table.remove(speedHistory, 1)
    end
end

local function getAverageSpeed()
    if #speedHistory == 0 then
        return 0
    end

    local total = 0
    for i = 1, #speedHistory do
        total = total + speedHistory[i]
    end

    return total / #speedHistory
end

local mountedCondition = 4
local flyingCondition = 77

logf(
    "Starting movement speed tracker (poll=%.2fs, minDist=%.2f, movingOnly=%s, avgSamples=%d).",
    POLL_INTERVAL,
    MINIMUM_DISTANCE,
    tostring(LOG_ONLY_WHEN_MOVING),
    ROLLING_AVERAGE_SAMPLES
)

local previousPosition = getPlayerPosition()
local previousTime = os.clock()

if previousPosition == nil then
    log("Player position unavailable at startup; waiting for first valid sample.")
end

while true do
    sleep(POLL_INTERVAL)

    local currentPosition = getPlayerPosition()
    local currentTime = os.clock()

    if previousPosition == nil then
        previousPosition = currentPosition
        previousTime = currentTime
    elseif currentPosition ~= nil then
        local deltaTime = currentTime - previousTime
        if deltaTime > 0 then
            local movedFlat = flatDistance(previousPosition, currentPosition)
            local moved3d = Vector3.Distance(previousPosition, currentPosition)
            local flatSpeed = movedFlat / deltaTime
            local speed3d = moved3d / deltaTime

            addSpeedSample(flatSpeed)

            if (not LOG_ONLY_WHEN_MOVING) or movedFlat >= MINIMUM_DISTANCE then
                logf(
                    "dt=%.2fs flatDist=%.2f flatSpeed=%.2f y/s avgFlat=%.2f y/s dist3d=%.2f speed3d=%.2f y/s mounted=%s flying=%s pos=<%.2f, %.2f, %.2f>",
                    deltaTime,
                    movedFlat,
                    flatSpeed,
                    getAverageSpeed(),
                    moved3d,
                    speed3d,
                    tostring(getCondition(mountedCondition)),
                    tostring(getCondition(flyingCondition)),
                    currentPosition.X,
                    currentPosition.Y,
                    currentPosition.Z
                )
            end
        end

        previousPosition = currentPosition
        previousTime = currentTime
    end
end
