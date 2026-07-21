--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.0.0
description: Pathfind to configured coordinates using vnavmesh.
plugin_dependencies:
- vnavmesh
configs:
  X Coordinate:
    description: Destination X coordinate.
    default: 0.0
  Y Coordinate:
    description: Destination Y coordinate.
    default: 0.0
  Z Coordinate:
    description: Destination Z coordinate.
    default: 0.0
[[End Metadata]]
--]=====]

import("System.Numerics")

local PREFIX = "[Go To Coordinates]"
local POLL_INTERVAL = 0.25
local VNAV_READY_TIMEOUT = 30
local MOVEMENT_START_TIMEOUT = 5
local MOVEMENT_TIMEOUT = 120
local ARRIVAL_DISTANCE = 2
local NEAREST_POINT_HALF_EXTENT_XZ = 10
local NEAREST_POINT_HALF_EXTENT_Y = 5

local function log(message)
    local text = string.format("%s %s", PREFIX, tostring(message))
    pcall(function()
        Dalamud.Log(text)
    end)
    yield("/echo " .. text)
end

local function sleep(seconds)
    yield(string.format("/wait %.2f", tonumber(seconds) or 0))
end

local function getConfigNumber(name)
    local ok, value = pcall(function()
        return Config.Get(name)
    end)

    if not ok then
        return nil
    end

    return tonumber(value)
end

local function getPlayerPosition()
    local ok, position = pcall(function()
        return Entity and Entity.Player and Entity.Player.Position
    end)

    if ok then
        return position
    end

    return nil
end

local function distanceBetween(a, b)
    if not (a and b) then
        return math.huge
    end

    return Vector3.Distance(a, b)
end

local function isVnavActive()
    local okRunning, running = pcall(function()
        return IPC.vnavmesh.IsRunning()
    end)
    local okPathfind, pathfindInProgress = pcall(function()
        return IPC.vnavmesh.PathfindInProgress()
    end)

    return (okRunning and running == true) or (okPathfind and pathfindInProgress == true)
end

local function stopVnav()
    if IPC and IPC.vnavmesh and IPC.vnavmesh.Stop then
        pcall(IPC.vnavmesh.Stop)
    end
end

local function waitForVnavReady()
    local elapsed = 0
    while elapsed < VNAV_READY_TIMEOUT do
        local ok, ready = pcall(function()
            return IPC and IPC.vnavmesh and IPC.vnavmesh.IsReady()
        end)

        if ok and ready == true then
            return true
        end

        sleep(POLL_INTERVAL)
        elapsed = elapsed + POLL_INTERVAL
    end

    return false
end

local function pathfindTo(destination)
    local ok, result = pcall(function()
        return IPC.vnavmesh.PathfindAndMoveTo(destination, false)
    end)

    return ok and result == true
end

local function findNearestPoint(destination)
    local ok, nearestPoint = pcall(function()
        return IPC.vnavmesh.NearestPoint(
            destination,
            NEAREST_POINT_HALF_EXTENT_XZ,
            NEAREST_POINT_HALF_EXTENT_Y
        )
    end)

    if ok then
        return nearestPoint
    end

    return nil
end

local function moveTo(destination)
    local effectiveDestination = destination
    local usedFallback = false

    if not pathfindTo(effectiveDestination) then
        log("Direct pathfind failed; searching for the nearest navmesh point.")
        effectiveDestination = findNearestPoint(destination)

        if not effectiveDestination then
            log("Nearest navmesh point lookup failed.")
            return false
        end

        usedFallback = true
        if not pathfindTo(effectiveDestination) then
            log("Pathfind to the nearest navmesh point failed.")
            return false
        end
    end

    if usedFallback then
        log(string.format(
            "Moving to nearest navmesh point (%.3f, %.3f, %.3f).",
            effectiveDestination.X,
            effectiveDestination.Y,
            effectiveDestination.Z
        ))
    end

    local elapsed = 0
    while elapsed < MOVEMENT_START_TIMEOUT and not isVnavActive() do
        local position = getPlayerPosition()
        if distanceBetween(position, effectiveDestination) <= ARRIVAL_DISTANCE then
            stopVnav()
            return true
        end

        sleep(POLL_INTERVAL)
        elapsed = elapsed + POLL_INTERVAL
    end

    elapsed = 0
    while elapsed < MOVEMENT_TIMEOUT do
        local position = getPlayerPosition()
        if distanceBetween(position, effectiveDestination) <= ARRIVAL_DISTANCE then
            stopVnav()
            return true
        end

        if not isVnavActive() then
            return false
        end

        sleep(POLL_INTERVAL)
        elapsed = elapsed + POLL_INTERVAL
    end

    return false
end

function OnStop()
    stopVnav()
end

local x = getConfigNumber("X Coordinate")
local y = getConfigNumber("Y Coordinate")
local z = getConfigNumber("Z Coordinate")

if not (x and y and z) then
    log("Invalid coordinates. Enter numeric X, Y, and Z values.")
    return
end

local destination = Vector3(x, y, z)
log(string.format("Destination: (%.3f, %.3f, %.3f).", x, y, z))

if not waitForVnavReady() then
    log("vnavmesh was not ready before the timeout.")
    return
end

if moveTo(destination) then
    log("Arrived at the destination.")
else
    stopVnav()
    log("Unable to reach the destination.")
end
