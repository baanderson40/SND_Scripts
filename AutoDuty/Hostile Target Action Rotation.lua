--[=====[
[[SND Metadata]]
author: baanderson40
version: 2.0.0
description: |
  Finds matching BattleNpcs, moves within capture range, captures them, and
  repeats the damage rotation until manually stopped.
configs:
  Target Name Contains:
    description: Case-insensitive partial name used to find targets.
    default: ""
[[End Metadata]]
--]=====]

local ACTIONS = { 44879, 44883, 44885 }
local ACTION_NAMES = {
    [44879] = "Smash Axe",
    [44883] = "Axeblade Bite",
    [44885] = "Shieldsplitter",
}

local CAPTURE_ACTION = "Capture"
local CAPTURE_DISTANCE = 5.0
local ACTION_DELAY_SECONDS = 2.5
local SCAN_DELAY_SECONDS = 1.0
local MOVE_TIMEOUT_SECONDS = 60.0
local POLL_SECONDS = 0.1

local function sleep(seconds)
    yield(string.format("/wait %.1f", seconds))
end

local function log(message)
    Dalamud.Log("[Hostile Rotation] " .. tostring(message))
end

local function safeCall(callback)
    local ok, value = pcall(callback)
    return ok and value or nil
end

local function getTargetName(target)
    return tostring(safeCall(function() return target and target.Name end) or "")
end

local function getTargetType(target)
    return tostring(safeCall(function() return target and target.Type end) or "")
end

local function getPlayerPosition()
    return safeCall(function() return Player and Player.Entity and Player.Entity.Position end)
end

local function distanceFlat(a, b)
    if not a or not b then return math.huge end
    local dx = (a.X or 0) - (b.X or 0)
    local dz = (a.Z or 0) - (b.Z or 0)
    return math.sqrt(dx * dx + dz * dz)
end

local function getConfiguredName()
    local configured = safeCall(function()
        return Config and Config.Get and Config.Get("Target Name Contains")
    end)
    return string.lower(tostring(configured or ""))
end

local function getObjectName(object)
    return tostring(
        safeCall(function() return object.Name.TextValue end)
            or safeCall(function() return object.Name:GetText() end)
            or safeCall(function() return object.Name end)
            or ""
    )
end

local function getObjectKind(object)
    return tostring(safeCall(function() return object.ObjectKind end) or "")
end

local function getEntityAt(index)
    return safeCall(function() return Entity and Entity[index] end)
end

local function findNearestTarget(partialName)
    if partialName == "" or not (Svc and Svc.Objects and Entity) then
        return nil
    end

    local playerPosition = getPlayerPosition()
    local objectCount = tonumber(safeCall(function() return Svc.Objects.Length end)) or 0
    local nearest = nil

    for index = 0, math.max(0, objectCount - 1) do
        local object = safeCall(function() return Svc.Objects[index] end)
        local entity = getEntityAt(index)
        if object and entity then
            local name = getObjectName(object)
            local position = safeCall(function() return object.Position end)
            local hp = tonumber(safeCall(function() return object.CurrentHp end) or 0) or 0
            local targetable = safeCall(function() return entity.IsTargetable end) == true
            local kind = getObjectKind(object)

            if position
                and string.find(string.lower(name), partialName, 1, true)
                and string.find(kind, "BattleNpc", 1, true) == 1
                and targetable
                and hp > 0 then
                local candidate = {
                    entity = entity,
                    name = name,
                    position = position,
                    distance = distanceFlat(playerPosition, position),
                }
                if nearest == nil or candidate.distance < nearest.distance then
                    nearest = candidate
                end
            end
        end
    end

    return nearest
end

local function stopMovement()
    if IPC and IPC.vnavmesh and IPC.vnavmesh.Stop then
        pcall(function() IPC.vnavmesh.Stop() end)
    end
end

local function moveToTarget(candidate)
    if not (IPC and IPC.vnavmesh and IPC.vnavmesh.PathfindAndMoveTo) then
        log("vnavmesh PathfindAndMoveTo is unavailable.")
        return false
    end

    if candidate.distance <= CAPTURE_DISTANCE then
        return true
    end

    log(string.format("Moving to %s at %.1f yalms.", candidate.name, candidate.distance))
    local ok, started = pcall(function()
        return IPC.vnavmesh.PathfindAndMoveTo(candidate.position, false)
    end)
    if not ok or started == false then
        log("vnavmesh failed to start movement.")
        return false
    end

    local deadline = os.clock() + MOVE_TIMEOUT_SECONDS
    while os.clock() < deadline do
        local playerPosition = getPlayerPosition()
        local distance = distanceFlat(playerPosition, candidate.position)
        if distance <= CAPTURE_DISTANCE then
            stopMovement()
            return true
        end
        sleep(POLL_SECONDS)
    end

    stopMovement()
    log("Movement timed out before reaching capture range.")
    return false
end

local function targetCandidate(candidate)
    if not candidate.entity or not candidate.entity.SetAsTarget then
        log("Target entity cannot be selected.")
        return false
    end

    local ok = pcall(function() candidate.entity:SetAsTarget() end)
    if not ok then
        log("Failed to target " .. candidate.name .. ".")
        return false
    end

    local deadline = os.clock() + 3.0
    while os.clock() < deadline do
        local target = safeCall(function() return Player.Entity.Target end)
        if getTargetName(target) == candidate.name then
            return true
        end
        sleep(POLL_SECONDS)
    end

    log("Target verification timed out for " .. candidate.name .. ".")
    return false
end

local function isLiveTarget(candidateName)
    local target = safeCall(function() return Player.Entity.Target end)
    if target == nil or getTargetName(target) ~= candidateName then
        return false
    end

    local hp = tonumber(safeCall(function() return target.CurrentHp end) or 0) or 0
    local targetable = safeCall(function() return target.IsTargetable end) == true
    local targetType = getTargetType(target)
    return hp > 0 and targetable and string.find(targetType, "BattleNpc", 1, true) == 1
end

local function executeDamageRotation(candidateName)
    while isLiveTarget(candidateName) do
        for _, actionId in ipairs(ACTIONS) do
            if not isLiveTarget(candidateName) then
                return
            end
            log(string.format("Attempting %s (%d).", ACTION_NAMES[actionId], actionId))
            yield(string.format('/ac "%s" <t>', ACTION_NAMES[actionId]))
            sleep(ACTION_DELAY_SECONDS)
        end
    end
end

local partialName = getConfiguredName()
if partialName == "" then
    log("No Target Name Contains configuration was provided; stopping.")
    return
end

log("v2.0.0 started. Searching for targets containing: " .. partialName)

while true do
    local candidate = findNearestTarget(partialName)
    if candidate == nil then
        sleep(SCAN_DELAY_SECONDS)
    elseif moveToTarget(candidate) and targetCandidate(candidate) then
        log("Capturing " .. candidate.name .. ".")
        yield(string.format('/ac "%s" <t>', CAPTURE_ACTION))
        sleep(ACTION_DELAY_SECONDS)
        executeDamageRotation(candidate.name)
        log("Target defeated or lost: " .. candidate.name)
    else
        sleep(SCAN_DELAY_SECONDS)
    end
end
