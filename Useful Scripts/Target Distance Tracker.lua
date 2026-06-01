--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.0.0
description: |
  Poll the current target every 0.25 seconds and echo flat and 3D distance to chat.
[[End Metadata]]
--]=====]

import("System.Numerics")

local PREFIX = "[Target Dist]"
local POLL_INTERVAL = 0.25

local function sleep(seconds)
    yield(string.format("/wait %.2f", tonumber(seconds) or 0))
end

local function echo(message)
    yield(string.format("/echo %s %s", PREFIX, tostring(message)))
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

local function distanceBetweenFlat(a, b)
    if not (a and b) then
        return math.huge
    end

    local dx = a.X - b.X
    local dz = a.Z - b.Z
    return math.sqrt((dx * dx) + (dz * dz))
end

echo("Starting target distance tracker.")

while true do
    local target = Entity and Entity.Target or nil
    local playerPosition = getPlayerPosition()

    if target and target.Position and playerPosition then
        local flatDistance = distanceBetweenFlat(playerPosition, target.Position)
        local distance3d = Vector3.Distance(playerPosition, target.Position)
        local targetName = tostring(target.Name or "<unknown>")

        echo(string.format("%s | flat=%.2f | 3d=%.2f", targetName, flatDistance, distance3d))
    else
        echo("No target")
    end

    sleep(POLL_INTERVAL)
end
