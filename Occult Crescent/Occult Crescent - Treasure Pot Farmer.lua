--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.3.0
description: >-
  Farm the Occult Crescent Persistent Pot FATE cycle, wait at the next predicted spawn,
  and solve the post-FATE treasure hunt with mapped coffer groups plus local hint refinement.
plugin_dependencies:
- vnavmesh
- Lifestream
configs:
    Autorotation Preset Name:
        default: "Occult"
        description: BossMod/BMR autorotation preset to enable during pot FATE combat. Leave blank to disable.
    Starting FATE:
        description: Which pot FATE to wait at on a fresh start before the first cycle is known.
        is_choice: true
        choices:
          - Auto
          - Persistent Pots (North)
          - Pleading Pots (South)
        default: Auto
    Spawn Lead Minutes:
        default: 5
        description: Minutes before the predicted spawn to move to the next pot FATE location.
        min: 1
        max: 15
    Spawn Arrival Radius:
        default: 18
        description: Radius used to pick a random wait point around the pot FATE location before spawn.
        min: 10
        max: 35
    Enable Dangerous Coffer Areas:
        description: Allow the script to visit known dangerous coffer areas that can aggro hostile mobs.
        is_choice: true
        choices:
          - Disabled
          - Enabled
        default: Disabled
[[End Metadata]]
--]=====]

import("System.Numerics")

local PREFIX = "[OC Pot Farmer]"

local SOUTH_HORN_TERRITORY_ID = 1252
local GENERAL_ACTION_RETURN = 8
local GENERAL_ACTION_MOUNT = 24
local CACHE_ME_IF_YOU_CAN_STATUS_ID = 1531
local MAGICAL_ELIXIR_EVENT_ITEM_ID = 2003296
local MAGICAL_ELIXIR_NAME = "Magical Elixir"
local POT_NAME = "Persistent Pot"
local AUTOROTATION_PRESET_NAME = tostring(Config.Get("Autorotation Preset Name") or "Occult")

local POLL_INTERVAL = 0.25
local SPAWN_LEAD_MINUTES = math.max(1, math.min(15, tonumber(Config.Get("Spawn Lead Minutes")) or 5))
local SPAWN_ARRIVAL_RADIUS = math.max(10, math.min(35, tonumber(Config.Get("Spawn Arrival Radius")) or 18))
local STARTING_FATE_CONFIG = tostring(Config.Get("Starting FATE") or "Auto")
local ENABLE_DANGEROUS_COFFER_AREAS = tostring(Config.Get("Enable Dangerous Coffer Areas") or "Disabled") == "Enabled"
local INITIAL_SPAWN_WAIT_MINUTES = 35
local STEP_BEYOND_FAR = 100
local STEP_FAR = 40
local STEP_CLOSE = 20
local STEP_IMMEDIATE = 8
local COFFER_SCAN_RADIUS = 28
local COFFER_TRACKING_FILE = "D:/Coding/lua/SND_Scripts/Occult Crescent/Gold Coffer Tracking Notes.md"

local ARRIVAL_DISTANCE = 2.5
local WAIT_POINT_FALLBACK_DISTANCE = 4.0
local TRANSITION_STABLE_SECONDS = 0.75
local TRANSITION_TIMEOUT = 10.0
local AETHERNET_TIMEOUT = 6.0
local MOUNT_TIMEOUT = 8.0
local MOVE_TIMEOUT_PADDING = 15.0
local WAIT_POLL = 0.5
local RAISE_TIMEOUT = 300.0
local IDLE_LOG_INTERVAL = 10.0
local WAIT_COUNTDOWN_INTERVAL = 60.0
local TREASURE_HINT_TIMEOUT = 4.0
local TREASURE_MOVE_SETTLE = 1.0
local TREASURE_MAX_STEPS = 30
local TREASURE_ELIXIR_RETRY_DELAY = 1.0
local POT_CYCLE_SECONDS = 30 * 60
local ENABLE_KEEP_ALIVE = false
local KEEP_ALIVE_INTERVAL = 8 * 60
local KEEP_ALIVE_MIN_RADIUS = 15.0
local KEEP_ALIVE_MAX_RADIUS = 20.0
local TREASURE_STALL_MIN_MOVE = 5.0
local TREASURE_MAX_CONSECUTIVE_STALLS = 2
local TREASURE_MOVE_START_TIMEOUT = 3.0
local TREASURE_PROGRESS_CHECK_INTERVAL = 5.0
local TREASURE_PROGRESS_MIN_MOVE = 2.0
local TREASURE_CANDIDATE_STOP_DISTANCE = 10.0
local TREASURE_LOCAL_MAX_STEPS = 12
local TREASURE_REVEAL_ACQUIRE_TIMEOUT = 5.0
local TREASURE_REVEAL_SCAN_INTERVAL = 0.25
local TREASURE_REVEAL_SCAN_RADIUS = 12.0
local TREASURE_SEARCH_RADII = { 20.0, 50.0, 100.0, 200.0 }
local TREASURE_NAVMESH_HALF_EXTENT_XZ = 6.0
local TREASURE_NAVMESH_HALF_EXTENT_Y = 8.0

local TREASURE_CANDIDATE_TRAVEL = {
    nearEnoughRadius = 35.0,
    maxAttempts = 2,
    hardTimeout = 180.0,
    progressTimeout = 5.0,
    progressMinMove = 2.0,
}

local CharacterCondition = {
    dead = 2,
    mounted = 4,
    inCombat = 26,
    casting = 27,
    occupiedInQuestEvent = 32,
    betweenAreas = 45,
    mounting57 = 57,
    mounting64 = 64,
}

local metadata = {
    territoryTypeId = 1252,
    aethernetInteractDistanceMin = 3.15,
    aethernetInteractDistance = 4.5,
    mountedTravelSpeed = 14.13,
    aethernets = {
        BaseCamp = {
            name = "BaseCamp",
            placeNameId = 4927,
            position = Vector3(830.7468, 72.98389, -695.97925),
            destination = Vector3(852.51874, 73.22737, -702.8938),
            interactDistanceMin = 3.15,
            interactDistanceMax = 4.5,
        },
        Eldergrowth = {
            name = "Eldergrowth",
            placeNameId = 4930,
            position = Vector3(306.93518, 105.18042, 305.65344),
            destination = Vector3(302.0557, 103.03691, 304.74838),
            interactDistanceMin = 3.15,
            interactDistanceMax = 4.5,
        },
        Stonemarsh = {
            name = "Stonemarsh",
            placeNameId = 4942,
            position = Vector3(-384.11542, 99.19885, 281.42212),
            destination = Vector3(-384.38, 97.44333, 276.6886),
            interactDistanceMin = 3.15,
            interactDistanceMax = 4.5,
        },
    },
}

local POT_FATES = {
    ["Persistent Pots"] = {
        name = "Persistent Pots",
        short = "north",
        location = Vector3(200.00, 111.73, -215.00),
        preferredAethernet = "Eldergrowth",
    },
    ["Pleading Pots"] = {
        name = "Pleading Pots",
        short = "south",
        location = Vector3(-481.00, 75.00, 528.00),
        preferredAethernet = "Stonemarsh",
    },
}

local COFFER_GROUPS = {
    ["Persistent Pots"] = {
        north = {
            { label = "N1", general = Vector3(331.65, 5.67, -665.71) },
        },
        northeast = {
            { label = "NE1", general = Vector3(582.79, 70.14, -558.88) },
            { label = "NE2", general = Vector3(568.83, 51.50, -816.60), precise = Vector3(571.584, 51.451, -813.164) },
        },
        east = {
            { label = "E1", general = Vector3(805.76, 96.10, -360.63) },
            { label = "E2", general = Vector3(683.41, 96.10, -166.44) },
            { label = "E3", general = Vector3(875.50, 108.33, -94.30) },
            { label = "E4", general = Vector3(885.93, 120.00, -23.25) },
        },
        southeast = {
            { label = "SE1", general = Vector3(666.93, 120.00, 163.87) },
            { label = "SE2", general = Vector3(601.56, 108.15, 182.32) },
            { label = "SE3", general = Vector3(569.10, 64.40, 275.10) },
            { label = "SE4", general = Vector3(700.66, 68.31, 359.77) },
        },
        south = {
            { label = "S1", general = Vector3(331.47, 96.00, 185.22) },
            { label = "S2", general = Vector3(250.53, 102.50, 310.78) },
            { label = "S3", general = Vector3(46.03, 102.40, 373.00) },
            { label = "S4", general = Vector3(242.52, 58.84, 535.85) },
        },
        southwest = {
            { label = "SW1", general = Vector3(-53.38, 99.47, 404.55) },
            { label = "SW2", general = Vector3(-186.85, 95.79, 435.96) },
            { label = "SW3", general = Vector3(-330.78, 121.00, 195.48) },
            { label = "SW4", general = Vector3(-321.46, 107.80, 75.47), precise = Vector3(-313.291, 108.110, 70.762) },
        },
        west = {
            { label = "W1", general = Vector3(-464.78, 94.36, 4.18), precise = Vector3(-459.173, 93.574, 5.054) },
            { label = "W2", general = Vector3(-322.48, 103.89, -27.85) },
            { label = "W3", general = Vector3(-473.32, 101.95, -70.80) },
            { label = "W4", general = Vector3(-673.05, 103.36, -231.06) },
            { label = "W5", general = Vector3(-385.05, 109.24, -373.93) },
        },
        northwest = {
            { label = "NW1", general = Vector3(16.11, 26.14, -421.60) },
            { label = "NW2", general = Vector3(-222.16, 5.46, -504.77) },
            { label = "NW3", general = Vector3(-384.35, 0.88, -455.43), precise = Vector3(-386.5904, -0.13994062, -461.0976) },
            { label = "NW4", general = Vector3(-517.87, -0.30, -633.71) },
            { label = "NW5", general = Vector3(-326.17, 3.00, -855.72) },
            { label = "NW6", general = Vector3(-169.66, 5.00, -716.07) },
        },
    },
    ["Pleading Pots"] = {
        north = {
            { label = "N1", general = Vector3(-187.14, 109.66, -298.45) },
            { label = "N2", general = Vector3(-387.09, 98.74, -237.71) },
            { label = "N3", general = Vector3(-551.93, 98.87, -305.47) },
            { label = "N4", general = Vector3(-676.88, 128.99, 15.86) },
            { label = "N5", general = Vector3(-632.01, 135.28, -72.60) },
            { label = "N6", general = Vector3(-729.29, 108.69, -387.27), dangerous = true, note = "hostile mob aggro" },
        },
        northeast = {
            { label = "NE1", general = Vector3(89.72, 111.57, -385.31) },
            { label = "NE2", general = Vector3(113.73, 111.53, -219.07) },
            { label = "NE3", general = Vector3(-55.11, 101.03, -192.67) },
            { label = "NE4", general = Vector3(396.06, 104.00, -129.01) },
            { label = "NE5", general = Vector3(303.61, 103.75, 76.93), precise = Vector3(301.874, 103.784, 70.599) },
            { label = "NE6", general = Vector3(104.58, 105.46, 148.65) },
        },
        east = {
            { label = "E1", general = Vector3(8.90, 65.44, 664.74) },
            { label = "E2", general = Vector3(68.32, 69.43, 742.59) },
            { label = "E3", general = Vector3(205.27, 56.00, 622.03) },
            { label = "E4", general = Vector3(395.23, 57.80, 850.46) },
            { label = "E5", general = Vector3(438.17, 70.30, 874.09) },
            { label = "E6", general = Vector3(822.07, 70.00, 770.42), precise = Vector3(825.9521, 70.0, 772.4054) },
            { label = "E7", general = Vector3(780.22, 70.00, 560.87) },
            { label = "E8", general = Vector3(420.23, 70.30, 574.40) },
        },
        southeast = {
            { label = "SE1", general = Vector3(-57.69, 69.79, 823.02) },
        },
        south = {
            { label = "S1", general = Vector3(-598.99, 139.00, 856.82), dangerous = true, note = "aggro" },
        },
        southwest = {
            { label = "SW1", general = Vector3(-730.99, 139.00, 833.63) },
            { label = "SW2", general = Vector3(-741.50, 171.50, 689.72) },
            { label = "SW3", general = Vector3(-707.70, 203.00, 702.15) },
            { label = "SW4", general = Vector3(-848.56, 107.00, 751.23) },
        },
        west = {
            { label = "W1", general = Vector3(-837.49, 107.00, 599.90) },
        },
        northwest = {
            { label = "NW1", general = Vector3(-811.84, 114.07, -225.39), dangerous = true, note = "aggro" },
            { label = "NW2", general = Vector3(-803.60, 84.13, 4.45), dangerous = true, note = "aggro" },
            { label = "NW3", general = Vector3(-829.00, 62.55, 69.85) },
        },
    },
}

local COFFER_EOBJ_IDS = {
    2014741,
    2014742,
    2014743,
}

local COFFER_NAME_FALLBACKS = {
    [2014741] = "Gold Coffer",
    [2014742] = "Silver Coffer",
    [2014743] = "Bronze Coffer",
}

local DIRECTION_ALIASES = {
    northeast = "northeast",
    ["north-east"] = "northeast",
    northwest = "northwest",
    ["north-west"] = "northwest",
    southeast = "southeast",
    ["south-east"] = "southeast",
    southwest = "southwest",
    ["south-west"] = "southwest",
    north = "north",
    south = "south",
    east = "east",
    west = "west",
}

local DIRECTION_VECTORS = {
    north = { x = 0, z = -1 },
    south = { x = 0, z = 1 },
    east = { x = 1, z = 0 },
    west = { x = -1, z = 0 },
    northeast = { x = math.sqrt(0.5), z = -math.sqrt(0.5) },
    northwest = { x = -math.sqrt(0.5), z = -math.sqrt(0.5) },
    southeast = { x = math.sqrt(0.5), z = math.sqrt(0.5) },
    southwest = { x = -math.sqrt(0.5), z = math.sqrt(0.5) },
}

local SENTENCE_PATTERN = "^you sense something (.+) to the (.+)$"
local SENTENCE_DIRECTION_ONLY_PATTERN = "^you sense something to the (.+)$"

local lastIdleLogAt = 0
local lastPotScanLogAt = 0
local latestTreasureEventRevision = 0
local latestTreasureEvent = nil
local latestTreasureMessage = nil
local lastTreasureSummary = nil
local lastCompletedFateName = nil
local lastCompletedAt = nil
local lastKeepAliveAt = 0
local TREASURE_RUNTIME = {
    trackingActive = false,
    resolvedCofferNames = nil,
    resolvedCofferNameLookup = nil,
    currentContext = nil,
    lastLoggedCaptureKey = nil,
}

local function sleep(seconds)
    yield(string.format("/wait %.2f", tonumber(seconds) or 0))
end

local function log(message)
    local line = string.format("%s %s", PREFIX, tostring(message))
    pcall(function()
        Dalamud.Log(line)
    end)
end

local function logf(fmt, ...)
    log(string.format(fmt, ...))
end

local function safeCall(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

local function getObjectName(object)
    if object == nil then
        return ""
    end
    local textValue = safeCall(function()
        return object.Name.TextValue
    end)
    if textValue ~= nil and tostring(textValue) ~= "" then
        return tostring(textValue)
    end
    local text = safeCall(function()
        return object.Name:GetText()
    end)
    if text ~= nil and tostring(text) ~= "" then
        return tostring(text)
    end
    local name = safeCall(function()
        return object.Name
    end)
    if name ~= nil and tostring(name) ~= "" then
        return tostring(name)
    end
    return ""
end

local function getEObjNameByRowId(rowId)
    local numericId = tonumber(rowId)
    if numericId == nil or not (Excel and Excel.GetSheet) then
        return nil
    end
    local sheet = Excel.GetSheet("EObjName")
    if sheet == nil then
        return nil
    end
    local row = safeCall(function()
        return sheet:GetRow(numericId)
    end)
    if row == nil then
        return nil
    end
    local textSource = safeCall(function() return row.Singular end)
        or safeCall(function() return row.Name end)
        or safeCall(function() return row.Unknown0 end)
    if textSource == nil then
        textSource = safeCall(function() return row.Text end)
    end
    if textSource == nil then
        return nil
    end
    local text = textSource
    local hasGetText = safeCall(function()
        return textSource.GetText ~= nil
    end)
    if type(textSource) ~= "string" and hasGetText then
        text = safeCall(function()
            return textSource:GetText()
        end)
    end
    text = tostring(text or "")
    if text == "" then
        return nil
    end
    return text
end

local function getResolvedCofferNames()
    if TREASURE_RUNTIME.resolvedCofferNames ~= nil and TREASURE_RUNTIME.resolvedCofferNameLookup ~= nil then
        return TREASURE_RUNTIME.resolvedCofferNames, TREASURE_RUNTIME.resolvedCofferNameLookup
    end

    TREASURE_RUNTIME.resolvedCofferNames = {}
    TREASURE_RUNTIME.resolvedCofferNameLookup = {}
    for _, dataId in ipairs(COFFER_EOBJ_IDS) do
        local name = getEObjNameByRowId(dataId) or COFFER_NAME_FALLBACKS[dataId]
        if name ~= nil and name ~= "" then
            table.insert(TREASURE_RUNTIME.resolvedCofferNames, name)
            TREASURE_RUNTIME.resolvedCofferNameLookup[string.lower(name)] = true
        end
    end
    return TREASURE_RUNTIME.resolvedCofferNames, TREASURE_RUNTIME.resolvedCofferNameLookup
end

local function stopScriptWithError(message)
    log(string.format("Stopping: %s", tostring(message)))
    error(tostring(message))
end

local function getCondition(flag)
    return flag ~= nil and Svc and Svc.Condition and Svc.Condition[flag] == true
end

local function isDead()
    return getCondition(CharacterCondition.dead)
end

local function isMounted()
    return getCondition(CharacterCondition.mounted)
end

local function isMounting()
    return getCondition(CharacterCondition.mounting57) or getCondition(CharacterCondition.mounting64)
end

local function isInCombat()
    return getCondition(CharacterCondition.inCombat)
end

local function isPlayerAvailable()
    return Player ~= nil and Player.Available == true
end

local function isLifestreamBusy()
    if IPC and IPC.Lifestream and IPC.Lifestream.IsBusy then
        local ok, busy = pcall(IPC.Lifestream.IsBusy)
        return ok and busy == true
    end
    return false
end

local function isVnavAvailable()
    return IPC and IPC.vnavmesh and IPC.vnavmesh.IsReady and IPC.vnavmesh.PathfindAndMoveTo
end

local function isLifestreamAvailable()
    return IPC and IPC.Lifestream and IPC.Lifestream.AethernetTeleportByPlaceNameId and IPC.Lifestream.IsBusy
end

local function isBossModAvailable()
    return IPC and IPC.BossMod and IPC.BossMod.SetActive and IPC.BossMod.GetActive and IPC.BossMod.ClearActive
end

local function getPlayerPosition()
    return safeCall(function()
        return Player.Entity.Position
    end)
end

local function getTerritoryType()
    return tonumber(safeCall(function()
        return Svc.ClientState.TerritoryType
    end))
end

local function isInSouthHorn()
    return getTerritoryType() == SOUTH_HORN_TERRITORY_ID
end

local function formatVector3(position)
    if position == nil then
        return "nil"
    end
    return string.format("(%.3f, %.3f, %.3f)", position.X, position.Y, position.Z)
end

local function formatPositionFields(position)
    if position == nil then
        return "x=? y=? z=?"
    end
    return string.format("x=%.3f y=%.3f z=%.3f", tonumber(position.X) or 0, tonumber(position.Y) or 0, tonumber(position.Z) or 0)
end

local function getCaptureFilePath()
    local path = tostring(COFFER_TRACKING_FILE or "")
    if path == "" then
        return nil
    end
    return path
end

local function distanceFlat(a, b)
    if a == nil or b == nil then
        return math.huge
    end
    local dx = a.X - b.X
    local dz = a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

local function distance3d(a, b)
    if a == nil or b == nil then
        return math.huge
    end
    local dx = a.X - b.X
    local dy = a.Y - b.Y
    local dz = a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function normalizeFlat(fromPos, toPos)
    local dx = toPos.X - fromPos.X
    local dz = toPos.Z - fromPos.Z
    local len = math.sqrt(dx * dx + dz * dz)
    if len <= 0.001 then
        return nil
    end
    return dx / len, dz / len
end

local function randomPointInRing(center, minRadius, maxRadius)
    local angle = math.random() * math.pi * 2
    local radius = minRadius + (math.random() * (maxRadius - minRadius))
    return Vector3(
        center.X + math.cos(angle) * radius,
        center.Y,
        center.Z + math.sin(angle) * radius
    )
end

local function waitUntil(predicate, timeoutSec, stableSec)
    local deadline = os.clock() + (timeoutSec or 5)
    local stableStart = nil
    while os.clock() < deadline do
        if predicate() then
            if not stableSec or stableSec <= 0 then
                return true
            end
            stableStart = stableStart or os.clock()
            if (os.clock() - stableStart) >= stableSec then
                return true
            end
        else
            stableStart = nil
        end
        sleep(POLL_INTERVAL)
    end
    return false
end

local function pathfindTo(position)
    if not isVnavAvailable() then
        log("vnavmesh unavailable while attempting pathfind.")
        return false
    end
    local ok, result = pcall(function()
        return IPC.vnavmesh.PathfindAndMoveTo(position, false)
    end)
    if not ok or result == false then
        logf("Pathfind command failed for %s.", formatVector3(position))
        return false
    end
    return true
end

local function stopPathing()
    if IPC and IPC.vnavmesh and IPC.vnavmesh.Stop then
        pcall(IPC.vnavmesh.Stop)
        return
    end
    yield("/vnav stop")
end

local function isVnavRunning()
    local running = safeCall(function()
        return IPC.vnavmesh.IsRunning()
    end)
    return running == true
end

local function getNearestNavmeshPoint(position, halfExtentXZ, halfExtentY)
    if position == nil or not (IPC and IPC.vnavmesh and IPC.vnavmesh.NearestPoint) then
        return nil
    end
    return safeCall(function()
        return IPC.vnavmesh.NearestPoint(position, halfExtentXZ or TREASURE_NAVMESH_HALF_EXTENT_XZ, halfExtentY or TREASURE_NAVMESH_HALF_EXTENT_Y)
    end)
end

local function getPointOnFloor(position, halfExtentXZ)
    if position == nil or not (IPC and IPC.vnavmesh and IPC.vnavmesh.PointOnFloor) then
        return nil
    end
    return safeCall(function()
        return IPC.vnavmesh.PointOnFloor(position, false, halfExtentXZ or TREASURE_SEARCH_RADII[1])
    end)
end

local function getTreasureNavmeshPoint(position, halfExtentXZ)
    local extent = halfExtentXZ or TREASURE_SEARCH_RADII[1]

    local floorPoint = getPointOnFloor(position, extent)
    if floorPoint ~= nil then
        return floorPoint, "PointOnFloor"
    end

    local nearestPoint = getNearestNavmeshPoint(position, extent, math.max(TREASURE_NAVMESH_HALF_EXTENT_Y, extent * 0.4))
    if nearestPoint ~= nil then
        return nearestPoint, "NearestPoint"
    end

    return nil, nil
end

local function pathfindRoute(fromPosition, toPosition)
    if fromPosition == nil or toPosition == nil or not (IPC and IPC.vnavmesh and IPC.vnavmesh.Pathfind) then
        return nil, false
    end
    local waypoints = safeCall(function()
        return IPC.vnavmesh.Pathfind(fromPosition, toPosition, false)
    end)
    return waypoints, waypoints ~= nil
end

local function moveToPosition(targetPosition, stopDistance, timeoutSec)
    if targetPosition == nil then
        return false
    end
    local playerPosition = getPlayerPosition()
    if distanceFlat(playerPosition, targetPosition) <= (stopDistance or ARRIVAL_DISTANCE) then
        return true
    end
    if not pathfindTo(targetPosition) then
        return false
    end

    local timeout = timeoutSec or (((distanceFlat(playerPosition, targetPosition) / (metadata.mountedTravelSpeed or 14.13)) + MOVE_TIMEOUT_PADDING))
    local reached = waitUntil(function()
        return distanceFlat(getPlayerPosition(), targetPosition) <= (stopDistance or ARRIVAL_DISTANCE)
    end, timeout, 0.5)
    stopPathing()
    return reached
end

local ensureMounted

local function moveToCandidatePositionWithRetry(targetPosition, stopDistance, contextLabel)
    local desiredStopDistance = stopDistance or TREASURE_CANDIDATE_STOP_DISTANCE

    for attempt = 1, TREASURE_CANDIDATE_TRAVEL.maxAttempts do
        local startPosition = getPlayerPosition()
        if distanceFlat(startPosition, targetPosition) <= desiredStopDistance then
            return true, getPlayerPosition(), attempt, "already_near"
        end

        ensureMounted()
        if not pathfindTo(targetPosition) then
            logf("%s candidate travel attempt %d/%d failed to start vnav movement.", tostring(contextLabel), attempt, TREASURE_CANDIDATE_TRAVEL.maxAttempts)
        else
            local started = waitUntil(function()
                return isVnavRunning()
            end, TREASURE_MOVE_START_TIMEOUT, 0)

            if not started then
                logf("%s candidate travel attempt %d/%d never entered a running state.", tostring(contextLabel), attempt, TREASURE_CANDIDATE_TRAVEL.maxAttempts)
            else
                local deadline = os.clock() + TREASURE_CANDIDATE_TRAVEL.hardTimeout
                local lastProgressPosition = startPosition
                local lastProgressAt = os.clock()

                while os.clock() < deadline do
                    local currentPosition = getPlayerPosition()
                    if distanceFlat(currentPosition, targetPosition) <= desiredStopDistance then
                        stopPathing()
                        return true, currentPosition, attempt, "arrived"
                    end

                    local progressDistance = distanceFlat(lastProgressPosition, currentPosition)
                    if progressDistance >= TREASURE_CANDIDATE_TRAVEL.progressMinMove then
                        lastProgressPosition = currentPosition
                        lastProgressAt = os.clock()
                    elseif (os.clock() - lastProgressAt) >= TREASURE_CANDIDATE_TRAVEL.progressTimeout then
                        stopPathing()
                        logf("%s candidate travel attempt %d/%d stalled after %.1fs with no meaningful progress.", tostring(contextLabel), attempt, TREASURE_CANDIDATE_TRAVEL.maxAttempts, TREASURE_CANDIDATE_TRAVEL.progressTimeout)
                        break
                    end

                    if not isVnavRunning() then
                        stopPathing()
                        currentPosition = getPlayerPosition()
                        if distanceFlat(currentPosition, targetPosition) <= desiredStopDistance then
                            return true, currentPosition, attempt, "arrived_after_stop"
                        end
                        logf("%s candidate travel attempt %d/%d stopped before arrival.", tostring(contextLabel), attempt, TREASURE_CANDIDATE_TRAVEL.maxAttempts)
                        break
                    end

                    sleep(POLL_INTERVAL)
                end

                if os.clock() >= deadline then
                    stopPathing()
                    logf("%s candidate travel attempt %d/%d hit hard timeout after %.0fs.", tostring(contextLabel), attempt, TREASURE_CANDIDATE_TRAVEL.maxAttempts, TREASURE_CANDIDATE_TRAVEL.hardTimeout)
                end
            end
        end

        stopPathing()
        local endPosition = getPlayerPosition()
        local remainingDistance = distanceFlat(endPosition, targetPosition)
        logf("%s candidate travel attempt %d/%d ended at %s (remaining %.1fy).", tostring(contextLabel), attempt, TREASURE_CANDIDATE_TRAVEL.maxAttempts, formatVector3(endPosition), remainingDistance)
        if attempt < TREASURE_CANDIDATE_TRAVEL.maxAttempts then
            sleep(1.0)
        end
    end

    return false, getPlayerPosition(), TREASURE_CANDIDATE_TRAVEL.maxAttempts, "failed"
end

local function executeGeneralAction(id)
    if not (Actions and Actions.ExecuteGeneralAction) then
        return false
    end
    return pcall(function()
        Actions.ExecuteGeneralAction(id)
    end)
end

ensureMounted = function()
    if isMounted() and not isMounting() then
        return true
    end
    local deadline = os.clock() + MOUNT_TIMEOUT
    local lastAttempt = -math.huge
    while os.clock() < deadline do
        if isMounted() and not isMounting() then
            return true
        end
        if isInCombat() then
            sleep(1.0)
        elseif not isMounted() and not isMounting() and (os.clock() - lastAttempt) >= 1.0 then
            executeGeneralAction(GENERAL_ACTION_MOUNT)
            lastAttempt = os.clock()
        end
        sleep(POLL_INTERVAL)
    end
    return false
end

local function ensureDismounted(timeoutSec)
    if not isMounted() and not isMounting() then
        return true
    end
    local deadline = os.clock() + (timeoutSec or 5.0)
    local lastAttempt = -math.huge
    while os.clock() < deadline do
        if not isMounted() and not isMounting() then
            return true
        end
        if not isInCombat() and (os.clock() - lastAttempt) >= 1.0 then
            yield("/generalaction dismount")
            lastAttempt = os.clock()
        end
        sleep(POLL_INTERVAL)
    end
    return not isMounted()
end

local function getAddon(name)
    local ok, addon = pcall(Addons.GetAddon, name)
    return ok and addon or nil
end

local function isAddonReady(name)
    local addon = getAddon(name)
    return addon ~= nil and addon.Ready == true and addon.Exists == true
end

local function hasRaiseStatus()
    local list = Player.Status
    if not list or not list.Count then
        return false
    end
    for i = 0, list.Count - 1 do
        local s = list[i]
        if s and (s.StatusId == 148 or s.StatusId == 1140) then
            return true
        end
    end
    return false
end

local function handleDeathState()
    if not isDead() then
        return true
    end
    log("Player is dead. Waiting up to 5 min for raise.")
    local deadline = os.clock() + RAISE_TIMEOUT
    local raiseDetected = false
    while os.clock() < deadline do
        if not isDead() then
            log("Player revived.")
            return true
        end
        if hasRaiseStatus() and not raiseDetected then
            log("Raise status detected.")
            raiseDetected = true
        end
        if raiseDetected and isAddonReady("SelectYesno") then
            sleep(1.0)
            yield("/callback SelectYesno true 0")
            waitUntil(function()
                return not isDead()
            end, 3.0, 0.5)
            if not isDead() then
                return true
            end
            raiseDetected = false
        end
        sleep(POLL_INTERVAL)
    end

    log("No raise received; attempting release.")
    if isAddonReady("SelectYesno") then
        yield("/callback SelectYesno true 0")
        waitUntil(function()
            return not isDead()
        end, 5.0, 0)
    end
    return not isDead()
end

local function waitForTransitionCompletion(startCondition, timeoutSec, label)
    local deadline = os.clock() + (timeoutSec or TRANSITION_TIMEOUT)
    local sawStart = false
    local sawBetweenAreas = false
    local stableStart = nil
    while os.clock() < deadline do
        local started = getCondition(startCondition)
        local betweenAreas = getCondition(CharacterCondition.betweenAreas)
        if started then
            sawStart = true
        end
        if betweenAreas then
            sawBetweenAreas = true
            stableStart = nil
        end
        local complete = sawStart and sawBetweenAreas and not betweenAreas and not getCondition(CharacterCondition.casting) and not isLifestreamBusy() and isPlayerAvailable()
        if complete then
            stableStart = stableStart or os.clock()
            if (os.clock() - stableStart) >= TRANSITION_STABLE_SECONDS then
                return true
            end
        else
            stableStart = nil
        end
        sleep(POLL_INTERVAL)
    end
    logf("%s transition timed out.", tostring(label))
    return false
end

local function useReturn()
    if isDead() or isInCombat() then
        return false, "cannot use Return right now"
    end
    if not executeGeneralAction(GENERAL_ACTION_RETURN) then
        return false, "failed to trigger Return"
    end
    local deadline = os.clock() + 3.0
    local castingStarted = false
    while os.clock() < deadline do
        if isAddonReady("SelectYesno") then
            yield("/callback SelectYesno true 0")
            castingStarted = waitUntil(function()
                return getCondition(CharacterCondition.casting) or getCondition(CharacterCondition.betweenAreas)
            end, 3.0, 0)
            break
        end
        if getCondition(CharacterCondition.casting) then
            castingStarted = true
            break
        end
        sleep(POLL_INTERVAL)
    end
    if not castingStarted then
        return false, "return did not start casting"
    end
    if not waitForTransitionCompletion(CharacterCondition.casting, TRANSITION_TIMEOUT, "Return") then
        return false, "return transition did not complete"
    end
    return true, nil
end

local function getAethernetByName(name)
    return metadata and metadata.aethernets and metadata.aethernets[name] or nil
end

local function getNearestConfiguredAethernet(position)
    local closest = nil
    local closestDistance = math.huge
    for _, aethernet in pairs(metadata.aethernets or {}) do
        local candidate = distanceFlat(position, aethernet.position)
        if candidate < closestDistance then
            closestDistance = candidate
            closest = aethernet
        end
    end
    return closest, closestDistance
end

local function getBossModActive()
    local active = safeCall(function()
        return IPC.BossMod.GetActive()
    end)
    return active and tostring(active) or ""
end

local function clearBossModPreset()
    if not isBossModAvailable() then
        log("BossMod IPC unavailable while clearing preset.")
        return false
    end
    pcall(IPC.BossMod.ClearActive)
    return waitUntil(function()
        return getBossModActive() == ""
    end, 2.5, 0.25)
end

local function applyBossModPreset(preset)
    if not isBossModAvailable() then
        log("BossMod IPC unavailable while applying preset.")
        return false
    end
    pcall(function()
        IPC.BossMod.SetActive(preset)
    end)
    return waitUntil(function()
        return getBossModActive() == preset
    end, 2.5, 0.25)
end

local function validateAutorotationPreset()
    local preset = tostring(AUTOROTATION_PRESET_NAME or "")
    if preset == "" then
        return false, "Autorotation disabled"
    end
    if not isBossModAvailable() then
        return false, "BossMod IPC is unavailable"
    end
    if not applyBossModPreset(preset) then
        return false, string.format("Failed to activate BossMod preset '%s'", preset)
    end
    if not clearBossModPreset() then
        return false, string.format("Failed to clear BossMod preset '%s' after validation", preset)
    end
    return true, nil
end

local function applyBossModForFate()
    local preset = tostring(AUTOROTATION_PRESET_NAME or "")
    if preset == "" then
        return false
    end
    if applyBossModPreset(preset) then
        log("Autorotation enabled for FATE.")
        return true
    end
    log("Autorotation preset activation failed for FATE; continuing without it.")
    return false
end

local function isWithinAethernetBand(position, aethernet)
    local distance = distanceFlat(position, aethernet.position)
    local minDistance = tonumber(aethernet.interactDistanceMin or metadata.aethernetInteractDistanceMin) or 3.15
    local maxDistance = tonumber(aethernet.interactDistanceMax or metadata.aethernetInteractDistance) or 4.5
    return distance >= minDistance and distance <= maxDistance, distance, minDistance, maxDistance
end

local function aethernetApproachDistance(playerPosition, aethernet)
    if playerPosition == nil or aethernet == nil then
        return math.huge
    end
    local dist = distanceFlat(playerPosition, aethernet.position)
    local minR = tonumber(aethernet.interactDistanceMin or metadata.aethernetInteractDistanceMin) or 3.15
    local maxR = tonumber(aethernet.interactDistanceMax or metadata.aethernetInteractDistance) or 4.5
    if dist < minR then return minR - dist end
    if dist > maxR then return dist - maxR end
    return 0
end

local function getDirectionalApproachPoint(playerPosition, aethernet)
    local minDistance = tonumber(aethernet.interactDistanceMin or metadata.aethernetInteractDistanceMin) or 3.15
    local nx, nz = normalizeFlat(aethernet.position, playerPosition)
    if nx == nil then
        return randomPointInRing(aethernet.position, minDistance, tonumber(aethernet.interactDistanceMax or metadata.aethernetInteractDistance) or 4.5)
    end
    return Vector3(
        aethernet.position.X + nx * minDistance,
        aethernet.position.Y,
        aethernet.position.Z + nz * minDistance
    )
end

local function getRandomAethernetBandPoint(aethernet)
    local minDistance = tonumber(aethernet.interactDistanceMin or metadata.aethernetInteractDistanceMin) or 3.15
    local maxDistance = tonumber(aethernet.interactDistanceMax or metadata.aethernetInteractDistance) or 4.5
    return randomPointInRing(aethernet.position, minDistance, maxDistance)
end

local function moveIntoAethernetBand(aethernet)
    local playerPosition = getPlayerPosition()
    if isWithinAethernetBand(playerPosition, aethernet) then
        return true
    end
    local attempts = { getDirectionalApproachPoint(playerPosition, aethernet) }
    for _ = 1, 5 do
        table.insert(attempts, getRandomAethernetBandPoint(aethernet))
    end
    for _, approachPoint in ipairs(attempts) do
        if approachPoint ~= nil and moveToPosition(approachPoint, WAIT_POINT_FALLBACK_DISTANCE) then
            if isWithinAethernetBand(getPlayerPosition(), aethernet) then
                return true
            end
        end
    end
    return false
end

local function waitForArrivalNearDestination(aethernet, timeoutSec)
    return waitUntil(function()
        return distanceFlat(getPlayerPosition(), aethernet.destination) <= 30.0
    end, timeoutSec or 4.0, 0.5)
end

local function useOccultAethernet(preferredAethernet)
    if not isLifestreamAvailable() then
        return false, "Lifestream IPC unavailable"
    end
    local playerPosition = getPlayerPosition()
    local currentAethernet = nil
    for _, aethernet in pairs(metadata.aethernets or {}) do
        if isWithinAethernetBand(playerPosition, aethernet) then
            currentAethernet = aethernet
            break
        end
    end
    if currentAethernet == nil then
        currentAethernet = getNearestConfiguredAethernet(playerPosition)
        currentAethernet = currentAethernet or preferredAethernet
        if currentAethernet == nil or not moveIntoAethernetBand(currentAethernet) then
            return false, "failed to reach aethernet interaction band"
        end
    end

    local ok = safeCall(function()
        return IPC.Lifestream.AethernetTeleportByPlaceNameId(preferredAethernet.placeNameId)
    end)
    if ok ~= true then
        return false, "AethernetTeleportByPlaceNameId returned false"
    end
    if not waitForTransitionCompletion(CharacterCondition.occupiedInQuestEvent, AETHERNET_TIMEOUT, "Aethernet") then
        return false, "aethernet transition did not complete"
    end
    if not waitForArrivalNearDestination(preferredAethernet, 4.0) then
        return false, "did not arrive near aethernet destination"
    end
    return true, nil
end

local function getBaseCampWaitPoint()
    local baseCamp = getAethernetByName("BaseCamp")
    if baseCamp == nil then
        return nil
    end
    local minDistance = tonumber(baseCamp.interactDistanceMin or metadata.aethernetInteractDistanceMin) or 3.15
    local maxDistance = tonumber(baseCamp.interactDistanceMax or metadata.aethernetInteractDistance) or 4.5
    return randomPointInRing(baseCamp.position, minDistance, maxDistance)
end

local function getRandomSpawnWaitPoint(targetPosition, radius)
    if targetPosition == nil then
        return nil
    end
    local maxRadius = math.max(10.0, tonumber(radius) or SPAWN_ARRIVAL_RADIUS)
    local minRadius = math.max(3.0, math.min(maxRadius * 0.35, maxRadius - 1.0))
    return randomPointInRing(targetPosition, minRadius, maxRadius)
end

local function returnToBaseAndWait()
    local baseCamp = getAethernetByName("BaseCamp")
    local playerPosition = getPlayerPosition()
    if baseCamp ~= nil and distanceFlat(playerPosition, baseCamp.position) > 120 then
        local ok, err = useReturn()
        if not ok then
            return false, err
        end
    end
    local waitPoint = getBaseCampWaitPoint()
    if waitPoint ~= nil then
        moveToPosition(waitPoint, WAIT_POINT_FALLBACK_DISTANCE)
    end
    ensureDismounted(5.0)
    return true, nil
end

local function getStatusEntry(statusId)
    local list = Player.Status
    if not list or not list.Count then
        return nil
    end
    for i = 0, list.Count - 1 do
        local status = list[i]
        if status and tonumber(status.StatusId) == tonumber(statusId) then
            return status
        end
    end
    return nil
end

local function getStatusRemaining(statusId)
    local status = getStatusEntry(statusId)
    if status == nil then
        return -1
    end
    return tonumber(safeCall(function()
        return status.RemainingTime
    end)) or -1
end

local function hasTreasureBuff()
    return getStatusEntry(CACHE_ME_IF_YOU_CAN_STATUS_ID) ~= nil
end

local function normalizeMessage(message)
    local normalized = tostring(message or ""):lower()
    normalized = normalized:gsub("[%.,!%%?;:]", " ")
    normalized = normalized:gsub("%s+", " ")
    return normalized:match("^%s*(.-)%s*$") or ""
end

local function findDirection(message)
    local normalized = normalizeMessage(message)
    local ordered = {
        "north-east", "north-west", "south-east", "south-west",
        "northeast", "northwest", "southeast", "southwest",
        "north", "south", "east", "west",
    }
    for _, raw in ipairs(ordered) do
        if normalized:find(raw, 1, true) then
            return DIRECTION_ALIASES[raw] or raw
        end
    end
    return nil
end

local function parseDistanceAndDirection(message)
    local normalized = normalizeMessage(message)
    local _, _, distanceText, directionText = normalized:find(SENTENCE_PATTERN)
    if not distanceText then
        local _, _, directionOnlyText = normalized:find(SENTENCE_DIRECTION_ONLY_PATTERN)
        if not directionOnlyText then
            return nil, nil, nil
        end
        return "close", nil, findDirection(directionOnlyText)
    end
    local distanceBucket
    local doubled = distanceText:match("^(%w+)%s+%1$")
    if doubled then
        distanceBucket = "beyond_" .. doubled
    else
        distanceBucket = distanceText
    end
    return distanceBucket, distanceText, findDirection(directionText)
end

local function classifyHintMessage(message)
    local normalized = normalizeMessage(message)
    if normalized == "" then
        return nil
    end
    local result = {
        raw = message,
        normalized = normalized,
    }
    if normalized:find("guide you to another treasure coffer", 1, true)
        or normalized:find("willing to guide you to another treasure coffer", 1, true)
        or normalized:find("find another treasure", 1, true) then
        result.kind = "bonus_offer"
        return result
    end
    if normalized:find("seems to be thirsty for elixir", 1, true)
        or normalized:find("use a magical elixir", 1, true) then
        result.kind = "elixir_prompt"
        return result
    end
    if normalized:find("you discover a treasure coffer", 1, true) then
        result.kind = "coffer_reveal"
        return result
    end
    local distanceBucket, distanceText, direction = parseDistanceAndDirection(message)
    if distanceBucket ~= nil or direction ~= nil then
        result.kind = "hint"
        result.direction = direction
        result.distanceBucket = distanceBucket
        result.distanceText = distanceText
        return result
    end
    if normalized:find("treasure coffer", 1, true) then
        result.kind = "coffer_message"
        return result
    end
    return nil
end

local function formatTreasureEvent(event)
    if event == nil then
        return nil
    end
    if event.kind == "hint" then
        return string.format("Treasure hint direction=%s distance=%s raw=%q.", tostring(event.direction or "?"), tostring(event.distanceBucket or "?"), tostring(event.raw or ""))
    end
    if event.kind == "coffer_message" then
        return string.format("Treasure coffer message: %q.", tostring(event.raw or ""))
    end
    if event.kind == "coffer_reveal" then
        return string.format("Treasure coffer reveal: %q.", tostring(event.raw or ""))
    end
    if event.kind == "elixir_prompt" then
        return string.format("Treasure prompt: %q.", tostring(event.raw or ""))
    end
    if event.kind == "bonus_offer" then
        return string.format("Bonus offer seen but ignored: %q.", tostring(event.raw or ""))
    end
    return nil
end

local function resetTreasureEvents()
    latestTreasureEventRevision = 0
    latestTreasureEvent = nil
    latestTreasureMessage = nil
    lastTreasureSummary = nil
end

local function getStepSize(distanceBucket)
    if distanceBucket == "beyond_far" then
        return STEP_BEYOND_FAR
    elseif distanceBucket == "far" then
        return STEP_FAR
    elseif distanceBucket == "immediately" then
        return STEP_IMMEDIATE
    end
    return STEP_CLOSE
end

local function isLocalTreasureDistance(distanceBucket)
    return distanceBucket == "close" or distanceBucket == "immediately"
end

local function cloneCandidate(candidate)
    return {
        label = candidate.label,
        general = candidate.general,
        precise = candidate.precise,
        dangerous = candidate.dangerous == true,
        note = candidate.note,
    }
end

local function getOrderedTreasureCandidates(fateName, direction)
    local fateInfo = POT_FATES[fateName]
    local groupsForFate = COFFER_GROUPS[fateName]
    local group = groupsForFate and groupsForFate[direction or ""] or nil
    if fateInfo == nil or group == nil or #group == 0 then
        return nil, nil, "no coffer group configured"
    end

    local eligible = {}
    local skippedDangerous = 0
    for _, candidate in ipairs(group) do
        if candidate.dangerous and not ENABLE_DANGEROUS_COFFER_AREAS then
            skippedDangerous = skippedDangerous + 1
        else
            table.insert(eligible, cloneCandidate(candidate))
        end
    end

    if #eligible == 0 then
        return nil, skippedDangerous, "all candidates were filtered as dangerous"
    end

    local ordered = {}
    local remaining = eligible
    local currentPoint = fateInfo.location
    while #remaining > 0 do
        local bestIndex = 1
        local bestDistance = math.huge
        for index, candidate in ipairs(remaining) do
            local destination = candidate.precise or candidate.general
            local dist = distanceFlat(currentPoint, destination)
            if dist < bestDistance then
                bestDistance = dist
                bestIndex = index
            end
        end
        local chosen = table.remove(remaining, bestIndex)
        table.insert(ordered, chosen)
        currentPoint = chosen.precise or chosen.general
    end

    return ordered, skippedDangerous, nil
end

local function getPotTargetByName(name)
    return POT_FATES[name]
end

local function getOppositePotName(name)
    if name == "Persistent Pots" then
        return "Pleading Pots"
    elseif name == "Pleading Pots" then
        return "Persistent Pots"
    end
    return nil
end

local function isValidWorldPosition(position)
    if position == nil then
        return false
    end
    local x = tonumber(position.X)
    local y = tonumber(position.Y)
    local z = tonumber(position.Z)
    if x == nil or y == nil or z == nil then
        return false
    end
    if math.abs(x) < 0.01 and math.abs(y) < 0.01 and math.abs(z) < 0.01 then
        return false
    end
    return true
end

local function resolvePotFateLocation(fateName, runtimeLocation)
    if isValidWorldPosition(runtimeLocation) then
        return runtimeLocation, false
    end
    local fallback = POT_FATES[fateName]
    return fallback and fallback.location or runtimeLocation, true
end

local function getStartingPotGuess()
    if STARTING_FATE_CONFIG == "Persistent Pots" or STARTING_FATE_CONFIG == "Persistent Pots (North)" then
        return "Persistent Pots"
    end
    if STARTING_FATE_CONFIG == "Pleading Pots" or STARTING_FATE_CONFIG == "Pleading Pots (South)" then
        return "Pleading Pots"
    end
    return nil
end

local function shouldSkipInitialBaseReturn()
    local guessedName = getStartingPotGuess()
    if guessedName == nil then
        return false
    end

    local target = getPotTargetByName(guessedName)
    local playerPosition = getPlayerPosition()
    if target == nil or playerPosition == nil then
        return false
    end

    local arrivalDistance = math.max(SPAWN_ARRIVAL_RADIUS, 40.0)
    if distanceFlat(playerPosition, target.location) <= arrivalDistance then
        return true
    end

    local preferredAethernet = getAethernetByName(target.preferredAethernet)
    if preferredAethernet ~= nil and distanceFlat(playerPosition, preferredAethernet.destination) <= 30.0 then
        return true
    end

    return false
end

local function scanPotFates()
    local result = {}
    local activeFates = safeCall(function()
        return Fates.GetActiveFates()
    end)
    if activeFates == nil then
        return result
    end
    local count = tonumber(safeCall(function() return activeFates.Count end)) or 0
    for i = 0, math.max(0, count - 1) do
        local fate = safeCall(function() return activeFates[i] end)
        if fate ~= nil then
            local name = tostring(safeCall(function() return fate.Name end) or "")
            local potInfo = POT_FATES[name]
            if potInfo ~= nil then
                local runtimeLocation = safeCall(function() return fate.Location end)
                local resolvedLocation, usedFallbackLocation = resolvePotFateLocation(name, runtimeLocation)
                local snapshot = {
                    id = tonumber(safeCall(function() return fate.Id end)) or 0,
                    name = name,
                    location = resolvedLocation,
                    radius = tonumber(safeCall(function() return fate.Radius end)) or 0,
                    progress = tonumber(safeCall(function() return fate.Progress end)) or 0,
                    distance = distanceFlat(getPlayerPosition(), resolvedLocation),
                    state = tonumber(safeCall(function() return fate.State end)) or 0,
                    preferredAethernet = potInfo.preferredAethernet,
                }
                table.insert(result, snapshot)
                if (os.clock() - lastPotScanLogAt) >= IDLE_LOG_INTERVAL then
                    lastPotScanLogAt = os.clock()
                    logf("scanPotFates: '%s' id=%d state=%d progress=%.1f dist=%.1f loc=%s.", snapshot.name, snapshot.id, snapshot.state, snapshot.progress, snapshot.distance, formatVector3(snapshot.location))
                    if usedFallbackLocation then
                        logf("scanPotFates: '%s' reported invalid runtime location %s; using fallback %s.", snapshot.name, formatVector3(runtimeLocation), formatVector3(resolvedLocation))
                    end
                end
            end
        end
    end
    return result
end

local function getFateSnapshot(fateId)
    local fate = safeCall(function()
        return Fates.GetFateById(fateId)
    end)
    if fate == nil then
        return nil
    end
    local name = tostring(safeCall(function() return fate.Name end) or "")
    local runtimeLocation = safeCall(function() return fate.Location end)
    local resolvedLocation = resolvePotFateLocation(name, runtimeLocation)
    return {
        id = tonumber(safeCall(function() return fate.Id end)) or 0,
        name = name,
        state = tonumber(safeCall(function() return fate.State end)) or 0,
        inFate = safeCall(function() return fate.InFate end) == true,
        progress = tonumber(safeCall(function() return fate.Progress end)) or 0,
        radius = tonumber(safeCall(function() return fate.Radius end)) or 0,
        location = resolvedLocation,
    }
end

local function getBestActivePotFate(expectedName)
    local fates = scanPotFates()
    if #fates == 0 then
        return nil
    end
    if expectedName ~= nil then
        for _, fate in ipairs(fates) do
            if fate.name == expectedName then
                return fate
            end
        end
    end
    table.sort(fates, function(a, b)
        return a.distance < b.distance
    end)
    return fates[1]
end

local function chooseRouteToPoint(targetPosition, preferredAethernetName)
    local playerPosition = getPlayerPosition()
    local speed = metadata.mountedTravelSpeed or 14.13
    local directTime = distanceFlat(playerPosition, targetPosition) / speed
    local preferred = getAethernetByName(preferredAethernetName)
    local nearestToPlayer = getNearestConfiguredAethernet(playerPosition)
    if preferred == nil or nearestToPlayer == nil then
        return { kind = "direct", reason = "no_aethernet" }
    end

    local approachDist = aethernetApproachDistance(playerPosition, nearestToPlayer)
    local shardRideDist = distanceFlat(preferred.destination, targetPosition)
    local shardTime = (approachDist / speed) + 3.0 + (shardRideDist / speed)
    local returnTeleportPenalty = (preferred.name == "BaseCamp") and 0 or 3.0
    local returnRideDist = distanceFlat(preferred.destination, targetPosition)
    local returnTime = 7.0 + returnTeleportPenalty + (returnRideDist / speed)

    if directTime <= shardTime and directTime <= returnTime then
        return { kind = "direct", reason = "faster_direct", preferred = preferred }
    end
    if returnTime < shardTime then
        return { kind = "return", reason = "faster_return", preferred = preferred }
    end
    return { kind = "aethernet", reason = "faster_shard", preferred = preferred }
end

local function travelToPoint(targetPosition, preferredAethernetName, stopDistance)
    local route = chooseRouteToPoint(targetPosition, preferredAethernetName)
    logf("Traveling to %s via %s (%s).", formatVector3(targetPosition), route.kind, route.reason)
    if route.kind == "return" then
        local ok, err = useReturn()
        if not ok then return false, err end
        if route.preferred and route.preferred.name ~= "BaseCamp" then
            local aethOk, aethErr = useOccultAethernet(route.preferred)
            if not aethOk then return false, aethErr end
        end
    elseif route.kind == "aethernet" then
        local aethOk, aethErr = useOccultAethernet(route.preferred)
        if not aethOk then return false, aethErr end
    end

    if not ensureMounted() then
        return false, "failed to mount"
    end
    if not moveToPosition(targetPosition, stopDistance or SPAWN_ARRIVAL_RADIUS) then
        return false, "failed to reach target position"
    end
    return true, nil
end

local function isFateActive(fateId)
    local activeFates = safeCall(function() return Fates.GetActiveFates() end)
    if activeFates == nil then return false end
    local count = tonumber(safeCall(function() return activeFates.Count end)) or 0
    for i = 0, math.max(0, count - 1) do
        local f = safeCall(function() return activeFates[i] end)
        if f ~= nil then
            local id = tonumber(safeCall(function() return f.Id end)) or 0
            if id == fateId then
                return true
            end
        end
    end
    return false
end

local function waitForFateToAppear(expectedName, timeoutSec)
    local deadline = os.clock() + timeoutSec
    while os.clock() < deadline do
        local active = getBestActivePotFate(expectedName)
        if active ~= nil then
            return active
        end
        if isDead() and not handleDeathState() then
            return nil
        end
        sleep(WAIT_POLL)
    end
    return nil
end

local function waitAtSpawnForFate(targetName, timeoutSec)
    ensureDismounted(5.0)
    logf("Waiting at %s spawn for up to %.1f minutes.", targetName, timeoutSec / 60.0)
    local deadline = os.clock() + timeoutSec
    local lastCountdownLog = os.clock()
    while os.clock() < deadline do
        local active = getBestActivePotFate(targetName)
        if active ~= nil then
            logf("Detected active pot FATE '%s' while waiting at spawn.", active.name)
            return active
        end
        if isDead() and not handleDeathState() then
            return nil
        end
        if (os.clock() - lastCountdownLog) >= WAIT_COUNTDOWN_INTERVAL then
            local remainingMinutes = math.max(0, math.ceil((deadline - os.clock()) / 60.0))
            logf("Waiting at %s spawn. %d minute(s) remaining.", targetName, remainingMinutes)
            lastCountdownLog = os.clock()
        end
        sleep(WAIT_POLL)
    end
    return nil
end

local function getRandomNearbyKeepAlivePoint()
    local playerPosition = getPlayerPosition()
    if playerPosition == nil then
        return nil
    end
    local angle = math.random() * math.pi * 2
    local radius = KEEP_ALIVE_MIN_RADIUS + (math.random() * (KEEP_ALIVE_MAX_RADIUS - KEEP_ALIVE_MIN_RADIUS))
    return Vector3(
        playerPosition.X + math.cos(angle) * radius,
        playerPosition.Y,
        playerPosition.Z + math.sin(angle) * radius
    )
end

local function performKeepAliveMove()
    local target = getRandomNearbyKeepAlivePoint()
    if target == nil then
        return false
    end
    logf("Keep-alive move toward %s.", formatVector3(target), false)
    ensureMounted()
    moveToPosition(target, 3.0, 20.0)
    lastKeepAliveAt = os.clock()
    return true
end

local function monitorPotFate(fate)
    local autorotationActive = false
    logf("Monitoring pot FATE '%s' (id=%d).", fate.name, fate.id)
    while true do
        if not isFateActive(fate.id) then
            logf("Pot FATE '%s' left the active list.", fate.name)
            break
        end
        local snapshot = getFateSnapshot(fate.id)
        if snapshot == nil then
            logf("Pot FATE '%s' vanished during monitoring.", fate.name)
            break
        end
        if isInCombat() or snapshot.inFate then
            if not autorotationActive then
                autorotationActive = applyBossModForFate()
            end
        elseif autorotationActive then
            logf("Combat ended for pot FATE %s; clearing autorotation.", fate.name)
            clearBossModPreset()
            autorotationActive = false
        end
        if isDead() and not handleDeathState() then
            return false, "failed to recover from death"
        end
        if (os.clock() - lastIdleLogAt) >= IDLE_LOG_INTERVAL then
            logf("Still monitoring '%s'. inFate=%s inCombat=%s progress=%.1f buff=%s.", fate.name, tostring(snapshot.inFate), tostring(isInCombat()), snapshot.progress or 0, tostring(hasTreasureBuff()))
            lastIdleLogAt = os.clock()
        end
        sleep(POLL_INTERVAL)
    end
    if autorotationActive then
        logf("Final combat clear for pot FATE %s. Clearing autorotation.", fate.name)
        clearBossModPreset()
    end
    lastCompletedFateName = fate.name
    lastCompletedAt = os.clock()
    return true, nil
end

local function getPredictedNextFateName()
    if lastCompletedFateName == nil then
        return nil
    end
    return getOppositePotName(lastCompletedFateName)
end

local function waitForPredictedWindow()
    local nextName = getPredictedNextFateName()
    if nextName == nil or lastCompletedAt == nil then
        return true
    end
    local departAt = lastCompletedAt + POT_CYCLE_SECONDS - (SPAWN_LEAD_MINUTES * 60)
    while os.clock() < departAt do
        local active = getBestActivePotFate(nil)
        if active ~= nil then
            return true
        end
        if isDead() and not handleDeathState() then
            return false
        end
        if ENABLE_KEEP_ALIVE and (lastKeepAliveAt <= 0 or (os.clock() - lastKeepAliveAt) >= KEEP_ALIVE_INTERVAL) then
            performKeepAliveMove()
        end
        local remaining = departAt - os.clock()
        if (os.clock() - lastIdleLogAt) >= WAIT_COUNTDOWN_INTERVAL then
            logf("Waiting at base until it is time to leave %.1f minute(s) early for predicted %s.", remaining / 60.0, nextName)
            lastIdleLogAt = os.clock()
        end
        sleep(1.0)
    end
    return true
end

local function createCofferMatch(entity, source, meta)
    return {
        entity = entity,
        source = source or "unknown",
        name = meta and meta.name or tostring(safeCall(function() return entity.Name end) or "?"),
        position = meta and meta.position or safeCall(function() return entity.Position end),
        distance = meta and meta.distance or nil,
        dataId = meta and meta.dataId or nil,
        gameObjectId = meta and meta.gameObjectId or nil,
        objectKind = meta and meta.objectKind or nil,
        objectIndex = meta and meta.objectIndex or nil,
    }
end

local function logCofferMatch(prefix, match)
    if match == nil then
        return
    end
    logf("%s name=%s dataId=%s gameObjectId=%s kind=%s index=%s pos=%s dist=%.1f source=%s.",
        tostring(prefix or "Coffer"),
        tostring(match.name or "?"),
        tostring(match.dataId or "?"),
        tostring(match.gameObjectId or "?"),
        tostring(match.objectKind or "?"),
        tostring(match.objectIndex or "?"),
        formatVector3(match.position),
        tonumber(match.distance) or -1,
        tostring(match.source or "unknown")
    )
end

local function getCurrentTargetMetadata()
    local target = safeCall(function()
        return Svc.Targets.Target
    end)
    if target == nil then
        return nil
    end
    return {
        name = getObjectName(target),
        dataId = tonumber(safeCall(function() return target.DataId end)),
        gameObjectId = safeCall(function() return target.GameObjectId end),
        objectKind = safeCall(function() return target.ObjectKind end),
        position = safeCall(function() return target.Position end),
    }
end

local function buildCofferCaptureKey(context, match)
    local fateName = context and context.fateName or "?"
    local group = context and context.group or "?"
    local candidate = context and context.candidateLabel or "?"
    local pos = match and match.position or nil
    if pos == nil then
        return string.format("%s|%s|%s|nil", tostring(fateName), tostring(group), tostring(candidate))
    end
    return string.format("%s|%s|%s|%.1f|%.1f|%.1f", tostring(fateName), tostring(group), tostring(candidate), pos.X, pos.Y, pos.Z)
end

local function getNextCaptureIndex(filePath)
    if io == nil or io.open == nil then
        return 1
    end
    local file = io.open(filePath, "r")
    if file == nil then
        return 1
    end
    local content = file:read("*a") or ""
    file:close()

    local maxIndex = 0
    for number in content:gmatch("## Capture%s+(%d+)") do
        local numeric = tonumber(number)
        if numeric ~= nil and numeric > maxIndex then
            maxIndex = numeric
        end
    end
    return maxIndex + 1
end

local function appendRuntimeCofferCapture(match, noteLines)
    local filePath = getCaptureFilePath()
    if filePath == nil or TREASURE_RUNTIME.currentContext == nil or match == nil or match.position == nil then
        return false
    end
    if io == nil or io.open == nil then
        log("Lua file IO is unavailable; skipping runtime coffer capture append.")
        return false
    end

    local captureKey = buildCofferCaptureKey(TREASURE_RUNTIME.currentContext, match)
    if TREASURE_RUNTIME.lastLoggedCaptureKey == captureKey then
        return true
    end

    local playerPosition = getPlayerPosition()
    local captureIndex = getNextCaptureIndex(filePath)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local lines = {
        "",
        string.format("## Capture %d", captureIndex),
        "",
        string.format("- Timestamp: `%s`", timestamp),
        "- Source: `Occult Crescent - Treasure Pot Farmer.lua runtime capture`",
        string.format("- TerritoryType: `%s`", tostring(getTerritoryType() or "?")),
        string.format("- FATE: `%s`", tostring(TREASURE_RUNTIME.currentContext.fateName or "?")),
        string.format("- Group: `%s`", tostring(TREASURE_RUNTIME.currentContext.group or "?")),
        string.format("- Candidate: `%s`", tostring(TREASURE_RUNTIME.currentContext.candidateLabel or "?")),
        string.format("- Coffer type: `%s`", tostring(match.name or "?")),
        string.format("- Detection source: `%s`", tostring(match.source or "unknown")),
        string.format("- Dangerous candidate: `%s`", tostring(TREASURE_RUNTIME.currentContext.dangerous == true)),
        string.format("- Player position: `%s`", formatPositionFields(playerPosition)),
        string.format("- Coffer position: `%s`", formatPositionFields(match.position)),
        string.format("- Distance from player: `%.3f`", tonumber(match.distance) or distance3d(playerPosition, match.position)),
        string.format("- DataId: `%s`", tostring(match.dataId or "?")),
        string.format("- GameObjectId: `%s`", tostring(match.gameObjectId or "?")),
        string.format("- ObjectKind: `%s`", tostring(match.objectKind or "?")),
    }
    if TREASURE_RUNTIME.currentContext.note ~= nil then
        table.insert(lines, string.format("- Candidate note: `%s`", tostring(TREASURE_RUNTIME.currentContext.note)))
    end
    if noteLines ~= nil then
        for _, noteLine in ipairs(noteLines) do
            table.insert(lines, string.format("- Note: `%s`", tostring(noteLine)))
        end
    end

    local file, openErr = io.open(filePath, "a")
    if file == nil then
        logf("Failed to append coffer capture to %s: %s.", tostring(filePath), tostring(openErr))
        return false
    end
    local ok, writeErr = pcall(function()
        file:write(table.concat(lines, "\n"))
        file:write("\n")
        file:close()
    end)
    if not ok then
        logf("Failed to write coffer capture to %s: %s.", tostring(filePath), tostring(writeErr))
        pcall(function() file:close() end)
        return false
    end

    TREASURE_RUNTIME.lastLoggedCaptureKey = captureKey
    logf("Appended coffer capture to %s for %s %s %s.", tostring(filePath), tostring(TREASURE_RUNTIME.currentContext.fateName or "?"), tostring(TREASURE_RUNTIME.currentContext.group or "?"), tostring(TREASURE_RUNTIME.currentContext.candidateLabel or "?"))
    return true
end

local function findNearbyCofferByName(radius, quiet)
    local playerPosition = getPlayerPosition()
    if playerPosition == nil then
        return nil
    end
    local cofferNames = getResolvedCofferNames()
    local best = nil
    local bestDistance = math.huge
    for _, name in ipairs(cofferNames) do
        local entity = safeCall(function()
            return Entity.GetEntityByName(name)
        end)
        if entity ~= nil then
            local position = safeCall(function() return entity.Position end)
            local distance = distance3d(playerPosition, position)
            if position ~= nil and distance <= radius and distance < bestDistance then
                best = createCofferMatch(entity, "name_lookup", {
                    name = tostring(safeCall(function() return entity.Name end) or name),
                    position = position,
                    distance = distance,
                })
                bestDistance = distance
            end
        end
    end
    if best == nil and not quiet then
        logf("Coffer scan: nothing found within radius %.0f.", radius)
    end
    return best
end

local function findNearbyCofferByObjectScan(radius, logDetails, contextLabel)
    local playerPosition = getPlayerPosition()
    if playerPosition == nil or not (Svc and Svc.Objects and Entity) then
        return nil
    end

    local _, nameLookup = getResolvedCofferNames()
    local best = nil
    local bestDistance = math.huge
    local nearbyEntries = {}

    local objectCount = tonumber(safeCall(function()
        return Svc.Objects.Length
    end)) or 0
    for i = 0, math.max(0, objectCount - 1) do
        local object = safeCall(function()
            return Svc.Objects[i]
        end)
        if object ~= nil then
            local position = safeCall(function() return object.Position end)
            local distance = distance3d(playerPosition, position)
            if position ~= nil and distance <= radius then
                local name = getObjectName(object)
                local lowerName = string.lower(name or "")
                local dataId = tonumber(safeCall(function() return object.DataId end))
                local gameObjectId = safeCall(function() return object.GameObjectId end)
                local objectKind = safeCall(function() return object.ObjectKind end)
                local entry = {
                    index = i,
                    name = name,
                    dataId = dataId,
                    gameObjectId = gameObjectId,
                    objectKind = objectKind,
                    position = position,
                    distance = distance,
                }
                table.insert(nearbyEntries, entry)

                if COFFER_NAME_FALLBACKS[dataId] ~= nil or nameLookup[lowerName] == true then
                    local entity = safeCall(function()
                        return Entity[i]
                    end)
                    if entity ~= nil and distance < bestDistance then
                        bestDistance = distance
                        best = createCofferMatch(entity, "object_scan", {
                            name = name,
                            position = position,
                            distance = distance,
                            dataId = dataId,
                            gameObjectId = gameObjectId,
                            objectKind = objectKind,
                            objectIndex = i,
                        })
                    end
                end
            end
        end
    end

    if logDetails then
        logf("%s object scan within %.0fy found %d nearby object(s).", tostring(contextLabel or "Reveal fallback"), radius, #nearbyEntries)
        table.sort(nearbyEntries, function(a, b)
            return (a.distance or math.huge) < (b.distance or math.huge)
        end)
        local limit = math.min(#nearbyEntries, 20)
        if limit == 0 then
            logf("%s object scan found no nearby objects.", tostring(contextLabel or "Reveal fallback"))
        end
        for idx = 1, limit do
            local entry = nearbyEntries[idx]
            logf("%s object[%d]: name=%s dataId=%s gameObjectId=%s kind=%s pos=%s dist=%.1f.",
                tostring(contextLabel or "Reveal fallback"),
                tonumber(entry.index) or -1,
                tostring(entry.name ~= "" and entry.name or "<empty>"),
                tostring(entry.dataId or "?"),
                tostring(entry.gameObjectId or "?"),
                tostring(entry.objectKind or "?"),
                formatVector3(entry.position),
                tonumber(entry.distance) or -1
            )
        end
    end

    return best
end

local function findNearbyCoffer(radius, quiet)
    return findNearbyCofferByName(radius, quiet)
end

local function targetEntity(entity)
    if entity == nil then
        return false
    end
    local ok = pcall(function()
        entity:SetAsTarget()
    end)
    if ok then
        return true
    end
    local name = tostring(safeCall(function() return entity.Name end) or "")
    if name ~= "" then
        yield(string.format('/target "%s"', name))
        sleep(0.25)
        return true
    end
    return false
end

local function interactWithEntity(entityOrMatch)
    if entityOrMatch == nil then
        return false
    end
    local match = entityOrMatch.entity and entityOrMatch or createCofferMatch(entityOrMatch, "direct_wrapper", nil)
    local entity = match.entity
    local name = tostring(match.name or safeCall(function() return entity.Name end) or "?")
    local position = match.position or safeCall(function() return entity.Position end)
    logCofferMatch("Found coffer entity", match)
    if position ~= nil then
        moveToPosition(position, 4.5, 15.0)
    end
    if not targetEntity(entity) then
        return false
    end
    sleep(0.1)
    local targetMetadata = getCurrentTargetMetadata()
    if targetMetadata ~= nil then
        if match.dataId == nil then
            match.dataId = targetMetadata.dataId
        end
        if match.gameObjectId == nil then
            match.gameObjectId = targetMetadata.gameObjectId
        end
        if match.objectKind == nil then
            match.objectKind = targetMetadata.objectKind
        end
        if match.position == nil then
            match.position = targetMetadata.position
        end
        if (match.name == nil or match.name == "?" or match.name == "") and targetMetadata.name ~= nil and targetMetadata.name ~= "" then
            match.name = targetMetadata.name
        end
        if match.distance == nil and match.position ~= nil then
            match.distance = distance3d(getPlayerPosition(), match.position)
        end
    end
    name = tostring(match.name or name)
    position = match.position or position
    appendRuntimeCofferCapture(match, nil)
    logf("Interacting with %s at %s.", name, formatVector3(position))
    yield("/interact")
    sleep(1.0)
    waitUntil(function()
        return findNearbyCoffer(12) == nil
    end, 8.0, 0.5)
    return true
end

local function acquireRevealedCoffer(contextLabel)
    local revealRadius = TREASURE_REVEAL_SCAN_RADIUS
    logf("%s reveal detected at player position %s.", tostring(contextLabel), formatVector3(getPlayerPosition()))

    local deadline = os.clock() + TREASURE_REVEAL_ACQUIRE_TIMEOUT
    local fallbackLogged = false
    while os.clock() < deadline do
        local namedMatch = findNearbyCofferByName(revealRadius, true)
        if namedMatch ~= nil then
            logCofferMatch(string.format("%s named coffer scan hit", tostring(contextLabel)), namedMatch)
            interactWithEntity(namedMatch)
            return true
        end

        local objectMatch = findNearbyCofferByObjectScan(revealRadius, not fallbackLogged, contextLabel)
        if not fallbackLogged then
            fallbackLogged = true
            logf("%s reveal fallback scan engaged; named coffer lookup failed.", tostring(contextLabel))
        end
        if objectMatch ~= nil then
            logCofferMatch(string.format("%s fallback object-scan hit", tostring(contextLabel)), objectMatch)
            interactWithEntity(objectMatch)
            return true
        end

        sleep(TREASURE_REVEAL_SCAN_INTERVAL)
    end

    logf("%s reveal acquisition timed out after %.1fs.", tostring(contextLabel), TREASURE_REVEAL_ACQUIRE_TIMEOUT)
    return false
end

local function useMagicalElixir()
    if not (Inventory and Inventory.GetInventoryItem) then
        log("Inventory module unavailable for Magical Elixir use.")
        return false
    end
    local item = safeCall(function()
        return Inventory.GetInventoryItem(MAGICAL_ELIXIR_EVENT_ITEM_ID)
    end)
    if item == nil then
        logf("Could not resolve %s event item id=%d.", MAGICAL_ELIXIR_NAME, MAGICAL_ELIXIR_EVENT_ITEM_ID)
        return false
    end
    local ok, err = pcall(function()
        item:Use()
    end)
    if not ok then
        logf("Magical Elixir use failed: %s", tostring(err))
        return false
    end
    return true
end

local function waitForTreasureEvent(previousRevision, timeoutSec)
    local deadline = os.clock() + timeoutSec
    while os.clock() < deadline do
        if latestTreasureEventRevision > previousRevision and latestTreasureEvent ~= nil then
            local summary = formatTreasureEvent(latestTreasureEvent)
            if summary ~= nil and summary ~= lastTreasureSummary then
                log(summary)
                lastTreasureSummary = summary
            end
            return latestTreasureEventRevision, latestTreasureEvent
        end
        if not hasTreasureBuff() and not TREASURE_RUNTIME.trackingActive then
            return latestTreasureEventRevision, nil
        end
        sleep(POLL_INTERVAL)
    end
    return latestTreasureEventRevision, nil
end

local function buildTreasureTarget(position, direction, step)
    local vector = DIRECTION_VECTORS[direction]
    if position == nil or vector == nil then
        return nil
    end
    return Vector3(
        position.X + (vector.x * step),
        position.Y,
        position.Z + (vector.z * step)
    )
end

local function getTreasureMoveTimeout(step)
    local speed = metadata.mountedTravelSpeed or 14.13
    return math.max(12.0, math.min(45.0, ((step / speed) * 2.0) + 15.0))
end

local function resolveTreasureMove(position, direction, baseStep)
    local stepMultipliers = { 1.0, 0.5, 0.25 }
    for _, radius in ipairs(TREASURE_SEARCH_RADII) do
        for _, multiplier in ipairs(stepMultipliers) do
            local step = baseStep * multiplier
            local rawTarget = buildTreasureTarget(position, direction, step)
            if rawTarget ~= nil then
                local snappedTarget, snapMethod = getTreasureNavmeshPoint(rawTarget, radius)
                if snappedTarget ~= nil then
                    local waypoints, hasRoute = pathfindRoute(position, snappedTarget)
                    if hasRoute then
                        return {
                            rawTarget = rawTarget,
                            snappedTarget = snappedTarget,
                            snapMethod = snapMethod,
                            snapRadius = radius,
                            step = step,
                            multiplier = multiplier,
                        }
                    end
                    logf("Treasure target %s resolved via %s(r=%.0f) to %s but pathfind returned no route.", formatVector3(rawTarget), tostring(snapMethod), radius, formatVector3(snappedTarget))
                else
                    logf("Treasure target %s could not be resolved to navmesh via PointOnFloor or NearestPoint at radius %.0f.", formatVector3(rawTarget), radius)
                end
            end
        end
    end
    return nil
end

local function performTreasureMove(event, contextLabel, stepIndex, consecutiveStalls)
    local playerPosition = getPlayerPosition()
    local moveStep = getStepSize(event.distanceBucket)
    local movePlan = resolveTreasureMove(playerPosition, event.direction, moveStep)
    if movePlan == nil then
        logf("%s move %d: no valid navmesh route for %s %s. Holding position and retrying elixir.", contextLabel, stepIndex, tostring(event.distanceBucket), tostring(event.direction))
        return false, consecutiveStalls or 0, "retry"
    end

    local target = movePlan.snappedTarget
    if target == nil then
        logf("%s move %d: hint parse incomplete. direction=%s distance=%s raw=%q", contextLabel, stepIndex, tostring(event.direction), tostring(event.distanceBucket), tostring(event.raw))
        return false, consecutiveStalls or 0, "retry"
    end

    local targetDistance = distanceFlat(playerPosition, target)
    logf("%s move %d: %s %s -> raw=%s resolved=%s via %s(r=%.0f) step=%.1f actualTarget=%.1fy.", contextLabel, stepIndex, tostring(event.distanceBucket), tostring(event.direction), formatVector3(movePlan.rawTarget), formatVector3(target), tostring(movePlan.snapMethod), tonumber(movePlan.snapRadius) or 0, movePlan.step, targetDistance)
    if targetDistance <= math.max(STEP_IMMEDIATE / 2, movePlan.step * 0.5) then
        logf("%s move %d resolved to current position (%.1fy away). Holding position and retrying elixir.", contextLabel, stepIndex, targetDistance)
        return false, 0, "retry"
    end

    ensureMounted()
    local moveStarted = pathfindTo(target)
    local moveReached = false
    local pathUnsuitable = false
    if moveStarted then
        moveStarted = waitUntil(function()
            return isVnavRunning()
        end, TREASURE_MOVE_START_TIMEOUT, 0)
    end
    if moveStarted then
        local lastProgressPosition = playerPosition
        local lastProgressCheckAt = os.clock()
        moveReached = waitUntil(function()
            local currentPosition = getPlayerPosition()
            if distanceFlat(currentPosition, target) <= math.max(2.5, STEP_IMMEDIATE / 2) then
                return true
            end
            if (os.clock() - lastProgressCheckAt) >= TREASURE_PROGRESS_CHECK_INTERVAL then
                local progressDistance = distanceFlat(lastProgressPosition, currentPosition)
                if progressDistance < TREASURE_PROGRESS_MIN_MOVE then
                    pathUnsuitable = true
                    stopPathing()
                    return true
                end
                lastProgressPosition = currentPosition
                lastProgressCheckAt = os.clock()
            end
            return false
        end, getTreasureMoveTimeout(movePlan.step), 0.5)
    else
        logf("%s move %d failed to start vnav movement.", contextLabel, stepIndex)
    end

    stopPathing()
    local movedTo = getPlayerPosition()
    local movedDistance = distanceFlat(playerPosition, movedTo)
    if pathUnsuitable then
        logf("%s move %d path made no progress for %.1fs (moved %.1fy). Retrying elixir from current position.", contextLabel, stepIndex, TREASURE_PROGRESS_CHECK_INTERVAL, movedDistance)
        sleep(TREASURE_MOVE_SETTLE)
        return false, 0, "retry"
    end
    if not moveReached and movedDistance < TREASURE_STALL_MIN_MOVE then
        local newStalls = (consecutiveStalls or 0) + 1
        logf("%s movement stalled (reached=%s moved=%.1fy, stall %d/%d).", contextLabel, tostring(moveReached), movedDistance, newStalls, TREASURE_MAX_CONSECUTIVE_STALLS)
        if newStalls >= TREASURE_MAX_CONSECUTIVE_STALLS then
            return false, newStalls, "stalled"
        end
        return false, newStalls, "retry"
    end

    logf("%s move %d completed: traveled %.1fy toward %s (step target %.1fy).", contextLabel, stepIndex, movedDistance, tostring(event.direction), movePlan.step)
    sleep(TREASURE_MOVE_SETTLE)
    local afterMoveCoffer = findNearbyCoffer(COFFER_SCAN_RADIUS)
    if afterMoveCoffer ~= nil then
        interactWithEntity(afterMoveCoffer)
        log("Treasure coffer found after movement.")
        return true, 0, "found"
    end

    return false, 0, "moved"
end

local function probeTreasureAtCurrentPosition(contextLabel, attemptIndex)
    local coffer = findNearbyCoffer(COFFER_SCAN_RADIUS)
    if coffer ~= nil then
        interactWithEntity(coffer)
        log("Primary treasure coffer interaction attempted. Bonus handling disabled; ending treasure phase.")
        return true, nil, "found"
    end

    local revisionBefore = latestTreasureEventRevision
    if not useMagicalElixir() then
        sleep(TREASURE_ELIXIR_RETRY_DELAY)
    else
        logf("%s used %s (attempt %d).", contextLabel, MAGICAL_ELIXIR_NAME, attemptIndex or 1)
    end

    local _, event = waitForTreasureEvent(revisionBefore, TREASURE_HINT_TIMEOUT)
    if event == nil then
        local revealedAfterDelay = findNearbyCoffer(COFFER_SCAN_RADIUS)
        if revealedAfterDelay ~= nil then
            interactWithEntity(revealedAfterDelay)
            log("Coffer detected after delayed reveal.")
            return true, nil, "found"
        end
        logf("%s no new treasure hint arrived.", contextLabel)
        return false, nil, "no_event"
    end

    if event.kind == "coffer_reveal" then
        if acquireRevealedCoffer(contextLabel) then
            log("Treasure coffer found after reveal message.")
            return true, event, "found"
        end
        logf("%s received reveal message but no chest entity was acquired.", contextLabel)
    elseif event.kind == "coffer_message" then
        sleep(0.5)
        local revealed = findNearbyCoffer(COFFER_SCAN_RADIUS)
        if revealed ~= nil then
            interactWithEntity(revealed)
            log("Treasure coffer found after reveal message.")
            return true, event, "found"
        end
        logf("%s received coffer message but no chest entity was found nearby.", contextLabel)
    elseif event.kind == "bonus_offer" then
        log("Bonus chest offer detected, but bonus handling is disabled for this version.")
        return true, event, "bonus"
    elseif event.kind == "elixir_prompt" then
        logf("%s treasure prompt detected; elixir will be retried if needed.", contextLabel)
    end

    return false, event, "event"
end

local function refineTreasureNearCandidate(candidate, initialEvent)
    local contextLabel = string.format("Candidate %s", tostring(candidate.label or "?"))
    local consecutiveStalls = 0
    local currentEvent = initialEvent

    for stepIndex = 1, TREASURE_LOCAL_MAX_STEPS do
        if not hasTreasureBuff() then
            return false, "treasure buff expired"
        end

        local coffer = findNearbyCoffer(COFFER_SCAN_RADIUS)
        if coffer ~= nil then
            interactWithEntity(coffer)
            log("Primary treasure coffer interaction attempted. Bonus handling disabled; ending treasure phase.")
            return true, nil
        end

        if currentEvent == nil then
            local probeFound, probeEvent, probeReason = probeTreasureAtCurrentPosition(contextLabel, stepIndex)
            if probeFound then
                return true, nil
            end
            if probeReason == "no_event" then
                sleep(TREASURE_ELIXIR_RETRY_DELAY)
                goto continue_refine
            end
            currentEvent = probeEvent
        end

        if currentEvent == nil then
            goto continue_refine
        end

        if currentEvent.kind == "hint" then
            if not isLocalTreasureDistance(currentEvent.distanceBucket) then
                logf("%s returned a non-local hint (%s %s). Trying next candidate.", contextLabel, tostring(currentEvent.distanceBucket), tostring(currentEvent.direction))
                return false, "candidate_mismatch"
            end
            local moveFound, newStalls, moveReason = performTreasureMove(currentEvent, contextLabel, stepIndex, consecutiveStalls)
            consecutiveStalls = newStalls or 0
            if moveFound then
                return true, nil
            end
            if moveReason == "stalled" then
                return false, "candidate_stalled"
            end
        elseif currentEvent.kind == "bonus_offer" then
            return true, nil
        end

        currentEvent = nil

        ::continue_refine::
    end

    return false, "candidate_refinement_exceeded"
end

local function runTreasureHunt(fateName)
    if not hasTreasureBuff() then
        return false, "treasure buff missing"
    end

    local function finishTreasureHunt(ok, err)
        TREASURE_RUNTIME.trackingActive = false
        TREASURE_RUNTIME.currentContext = nil
        return ok, err
    end

    TREASURE_RUNTIME.trackingActive = true
    TREASURE_RUNTIME.lastLoggedCaptureKey = nil
    TREASURE_RUNTIME.currentContext = {
        fateName = fateName,
        group = nil,
        candidateLabel = nil,
        dangerous = false,
        note = nil,
    }
    resetTreasureEvents()
    logf("Starting treasure hunt for %s with buff remaining %.1fs.", tostring(fateName), getStatusRemaining(CACHE_ME_IF_YOU_CAN_STATUS_ID))

    local initialFound, initialEvent, initialReason = probeTreasureAtCurrentPosition("Initial treasure hint", 1)
    if initialFound then
        return finishTreasureHunt(true, nil)
    end
    if initialReason == "no_event" or initialEvent == nil then
        return finishTreasureHunt(false, "failed to get first treasure hint")
    end
    if initialEvent.kind ~= "hint" then
        return finishTreasureHunt(false, string.format("first treasure event was %s, not a hint", tostring(initialEvent.kind)))
    end

    local orderedCandidates, skippedDangerous, groupErr = getOrderedTreasureCandidates(fateName, initialEvent.direction)
    if orderedCandidates == nil then
        return finishTreasureHunt(false, string.format("treasure group unavailable for %s %s: %s", tostring(fateName), tostring(initialEvent.direction), tostring(groupErr)))
    end
    TREASURE_RUNTIME.currentContext.group = initialEvent.direction
    logf("Selected %d coffer candidate(s) for %s %s; skipped dangerous=%d.", #orderedCandidates, tostring(fateName), tostring(initialEvent.direction), skippedDangerous or 0)

    for index, candidate in ipairs(orderedCandidates) do
        if not hasTreasureBuff() then
            return finishTreasureHunt(false, "treasure buff expired")
        end

        local destination = candidate.precise or candidate.general
        local suffix = candidate.dangerous and string.format(" [%s]", tostring(candidate.note or "dangerous")) or ""
        TREASURE_RUNTIME.currentContext.candidateLabel = candidate.label
        TREASURE_RUNTIME.currentContext.dangerous = candidate.dangerous == true
        TREASURE_RUNTIME.currentContext.note = candidate.note
        logf("Checking coffer candidate %d/%d: group=%s label=%s.", index, #orderedCandidates, tostring(initialEvent.direction), tostring(candidate.label or "?"))
        logf("Candidate %d/%d %s: moving to %s%s.", index, #orderedCandidates, tostring(candidate.label or "?"), formatVector3(destination), suffix)
        local candidateContextLabel = string.format("Candidate %s", tostring(candidate.label or "?"))
        local moved, endPosition = moveToCandidatePositionWithRetry(destination, TREASURE_CANDIDATE_STOP_DISTANCE, candidateContextLabel)
        if not moved then
            local remainingDistance = distanceFlat(endPosition, destination)
            logf("Candidate %s: failed to reach general area %s after %d attempt(s); final remaining distance %.1fy.", tostring(candidate.label or "?"), formatVector3(destination), TREASURE_CANDIDATE_TRAVEL.maxAttempts, remainingDistance)
            if remainingDistance > TREASURE_CANDIDATE_TRAVEL.nearEnoughRadius then
                goto continue_candidate
            end
            logf("Candidate %s: ended within %.1fy of target; probing candidate anyway.", tostring(candidate.label or "?"), remainingDistance)
        end

        local foundAfterMove = findNearbyCoffer(COFFER_SCAN_RADIUS)
        if foundAfterMove ~= nil then
            interactWithEntity(foundAfterMove)
            log("Treasure coffer found after candidate travel.")
            return finishTreasureHunt(true, nil)
        end

        local probeFound, probeEvent, probeReason = probeTreasureAtCurrentPosition(candidateContextLabel, index + 1)
        if probeFound then
            return finishTreasureHunt(true, nil)
        end
        if probeReason == "no_event" or probeEvent == nil then
            logf("Candidate %s produced no usable hint. Trying next candidate.", tostring(candidate.label or "?"))
            goto continue_candidate
        end
        if probeEvent.kind ~= "hint" then
            logf("Candidate %s produced non-hint event %s. Trying next candidate.", tostring(candidate.label or "?"), tostring(probeEvent.kind))
            goto continue_candidate
        end
        if not isLocalTreasureDistance(probeEvent.distanceBucket) then
            logf("Candidate %s is not local yet (%s %s). Trying next candidate.", tostring(candidate.label or "?"), tostring(probeEvent.distanceBucket), tostring(probeEvent.direction))
            goto continue_candidate
        end

        local refined, refineErr = refineTreasureNearCandidate(candidate, probeEvent)
        if refined then
            return true, nil
        end
        logf("Candidate %s refinement ended without success: %s. Trying next candidate.", tostring(candidate.label or "?"), tostring(refineErr))

        ::continue_candidate::
    end

    return finishTreasureHunt(false, string.format("treasure candidates exhausted for %s %s", tostring(fateName), tostring(initialEvent.direction)))
end

local function waitForSouthHorn()
    while not isInSouthHorn() do
        logf("Waiting for South Horn territoryTypeId=%d.", SOUTH_HORN_TERRITORY_ID)
        sleep(1.0)
    end
end

local function handlePotFate(activeFate)
    local targetInfo = getPotTargetByName(activeFate.name)
    local targetLocation = resolvePotFateLocation(activeFate.name, activeFate.location)
    if targetInfo ~= nil and activeFate.distance > SPAWN_ARRIVAL_RADIUS then
        local travelOk, travelErr = travelToPoint(targetLocation or targetInfo.location, targetInfo.preferredAethernet, math.max(10, activeFate.radius))
        if not travelOk then
            return false, travelErr
        end
    end

    local monitorOk, monitorErr = monitorPotFate(activeFate)
    if not monitorOk then
        return false, monitorErr
    end

    local buffWaitOk = waitUntil(function()
        return hasTreasureBuff() or getBestActivePotFate(nil) ~= nil
    end, 5.0, 0)
    if buffWaitOk and hasTreasureBuff() then
        local treasureOk, treasureErr = runTreasureHunt(activeFate.name)
        if not treasureOk then
            if hasTreasureBuff() then
                logf("Treasure hunt ended without success: %s.", tostring(treasureErr))
            else
                logf("Treasure hunt ended after buff loss: %s.", tostring(treasureErr))
            end
        end
    else
        log("No Cache Me If You Can buff detected after pot FATE; skipping treasure phase.")
    end

    local returnOk, returnErr = returnToBaseAndWait()
    if not returnOk then
        logf("Return to base failed after pot cycle: %s.", tostring(returnErr))
    end
    return true, nil
end

local function runBootstrapCycle()
    local active = getBestActivePotFate(nil)
    if active ~= nil then
        return active
    end

    local guessedName = getStartingPotGuess()
    if guessedName == nil then
        if (os.clock() - lastIdleLogAt) >= IDLE_LOG_INTERVAL then
            log("No known pot cycle yet. Waiting at base and scanning for the first active pot FATE.")
            lastIdleLogAt = os.clock()
        end
        sleep(WAIT_POLL)
        return nil
    end

    local guessedTarget = getPotTargetByName(guessedName)
    if guessedTarget == nil then
        sleep(WAIT_POLL)
        return nil
    end
    local waitPoint = getRandomSpawnWaitPoint(guessedTarget.location, SPAWN_ARRIVAL_RADIUS) or guessedTarget.location

    logf("Bootstrapping with configured starting FATE guess '%s'.", guessedName)
    logf("Selected random spawn wait point %s for '%s'.", formatVector3(waitPoint), guessedName)
    local ok, err = travelToPoint(waitPoint, guessedTarget.preferredAethernet, WAIT_POINT_FALLBACK_DISTANCE)
    if not ok then
        logf("Bootstrap travel failed: %s.", tostring(err))
        returnToBaseAndWait()
        sleep(2.0)
        return nil
    end

    active = waitAtSpawnForFate(guessedName, INITIAL_SPAWN_WAIT_MINUTES * 60)
    if active ~= nil then
        return active
    end

    logf("Initial wait at '%s' timed out. Returning to base and continuing scan-only fallback.", guessedName)
    returnToBaseAndWait()
    sleep(1.0)
    return nil
end

local function runPredictedCycle()
    local immediate = getBestActivePotFate(nil)
    if immediate ~= nil then
        return immediate
    end

    local nextName = getPredictedNextFateName()
    if nextName == nil then
        return nil
    end

    if not waitForPredictedWindow() then
        return nil
    end

    immediate = getBestActivePotFate(nil)
    if immediate ~= nil then
        return immediate
    end

    local target = getPotTargetByName(nextName)
    if target == nil then
        return nil
    end
    local waitPoint = getRandomSpawnWaitPoint(target.location, SPAWN_ARRIVAL_RADIUS) or target.location

    logf("Leaving base now to arrive %.1f minute(s) early for predicted pot FATE '%s'.", SPAWN_LEAD_MINUTES, nextName)
    logf("Selected random spawn wait point %s for predicted '%s'.", formatVector3(waitPoint), nextName)
    local travelOk, travelErr = travelToPoint(waitPoint, target.preferredAethernet, WAIT_POINT_FALLBACK_DISTANCE)
    if not travelOk then
        logf("Predicted spawn travel failed: %s.", tostring(travelErr))
        return nil
    end

    return waitAtSpawnForFate(nextName, INITIAL_SPAWN_WAIT_MINUTES * 60)
end

function OnChatMessage()
    if not hasTreasureBuff() and not TREASURE_RUNTIME.trackingActive then
        return
    end
    local message = tostring(TriggerData and TriggerData.message or "")
    if message == "" then
        return
    end
    local parsed = classifyHintMessage(message)
    if parsed == nil then
        return
    end
    latestTreasureMessage = message
    latestTreasureEvent = parsed
    latestTreasureEventRevision = latestTreasureEventRevision + 1
end

local function main()
    math.randomseed(os.time())
    log("Starting Occult Crescent Treasure Pot Farmer.")
    if not isVnavAvailable() then
        stopScriptWithError("vnavmesh IPC is unavailable")
    end
    if not isLifestreamAvailable() then
        stopScriptWithError("Lifestream IPC is unavailable")
    end

    do
        local ok, err = validateAutorotationPreset()
        if ok then
            logf("Autorotation preset %q validated successfully.", AUTOROTATION_PRESET_NAME)
        elseif tostring(AUTOROTATION_PRESET_NAME or "") ~= "" then
            logf("Autorotation validation warning: %s.", tostring(err))
        else
            log("Autorotation disabled; no preset configured.", false)
        end
    end

    do
        local names = getResolvedCofferNames()
        logf("Resolved coffer names: %s.", table.concat(names, ", "))
        if getCaptureFilePath() ~= nil then
            logf("Runtime coffer captures will append to %s.", tostring(getCaptureFilePath()))
        else
            log("Runtime coffer capture file is disabled.")
        end
    end

    waitForSouthHorn()
    logf("Entered South Horn at position %s.", formatVector3(getPlayerPosition()))

    if shouldSkipInitialBaseReturn() then
        log("Skipping initial return-to-base because player is already staged near the configured starting FATE.")
    else
        local baseOk, baseErr = returnToBaseAndWait()
        if not baseOk then
            logf("Initial return-to-base step failed: %s.", tostring(baseErr))
        end
    end

    while true do
        if isDead() and not handleDeathState() then
            stopScriptWithError("Failed to recover from death")
        end

        local active = getBestActivePotFate(nil)
        if active == nil then
            if lastCompletedFateName ~= nil then
                active = runPredictedCycle()
            else
                active = runBootstrapCycle()
            end
        end

        if active ~= nil then
            local ok, err = handlePotFate(active)
            if not ok then
                logf("Pot cycle failed: %s.", tostring(err))
                returnToBaseAndWait()
                sleep(1.0)
            end
        else
            if (os.clock() - lastIdleLogAt) >= IDLE_LOG_INTERVAL then
                log("Idle: no active pot FATE detected yet.")
                lastIdleLogAt = os.clock()
            end
            sleep(WAIT_POLL)
        end
    end
end

main()
