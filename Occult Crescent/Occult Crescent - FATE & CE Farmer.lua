--[=====[
[[SND Metadata]]
author: baanderson40
version: 0.4.0
description: >-
  Farm South Horn Critical Encounters and FATEs, hand off to BossMod autorotation, apply self-buffs, and return to Base Camp between activities.
plugin_dependencies:
- vnavmesh
- Lifestream
configs:
    Autorotation Preset Name:
        default: "Occult"
        description: BossMod/BMR autorotation preset to validate at startup and enable during CE combat.
    Farming Mode:
        description: Choose which activities to farm.
        is_choice: true
        choices:
          - "CE & FATE"
          - "CE Only"
          - "FATE Only"
        default: "CE & FATE"
    Prioritize CE:
        default: true
        description: Abandon FATE for CE if one becomes available during travel or monitoring.
    FATE Priority:
        description: How to select which FATE to target.
        is_choice: true
        choices:
          - Lowest Progress
          - Nearest
        default: Lowest Progress
    Excluded FATEs:
        default: ""
        description: Comma-separated FATE names to skip.
    Use Return:
        default: true
        description: Use return to return to Base Camp.
    Enable Buff Rotation:
        default: true
        description: Auto apply phantom job buffs.
[[End Metadata]]
--]=====]

import("System.Numerics")

local PREFIX = "[OC CE Runner]"

local metadata = {
    territoryTypeId = 1252,
    aethernetInteractDistanceMin = 3.15,
    aethernetInteractDistance = 4.5,
    mountedTravelSpeed = 14.13,
    aethernets = {
        BaseCamp = {
            name = "BaseCamp",
            placeNameId = 4927,
            baseId = 2014664,
            position = Vector3(830.7468, 72.98389, -695.97925),
            destination = Vector3(852.51874, 73.22737, -702.8938),
            interactDistanceMin = 3.15,
            interactDistanceMax = 4.5,
        },
        Eldergrowth = {
            name = "Eldergrowth",
            placeNameId = 4930,
            baseId = 2014667,
            position = Vector3(306.93518, 105.18042, 305.65344),
            destination = Vector3(302.0557, 103.03691, 304.74838),
            interactDistanceMin = 3.15,
            interactDistanceMax = 4.5,
        },
        Stonemarsh = {
            name = "Stonemarsh",
            placeNameId = 4942,
            baseId = 2014744,
            position = Vector3(-384.11542, 99.19885, 281.42212),
            destination = Vector3(-384.38, 97.44333, 276.6886),
            interactDistanceMin = 3.15,
            interactDistanceMax = 4.5,
        },
        CrystallizedCaverns = {
            name = "CrystallizedCaverns",
            placeNameId = 4929,
            baseId = 2014666,
            position = Vector3(-358.14453, 101.97595, -120.95831),
            destination = Vector3(-353.8978, 99.99078, -120.3132),
            interactDistanceMin = 3.15,
            interactDistanceMax = 4.5,
        },
        TheWanderersHaven = {
            name = "TheWanderersHaven",
            placeNameId = 4928,
            baseId = 2014665,
            position = Vector3(-173.02203, 8.194031, -611.1391),
            destination = Vector3(-169.27321, 6.5, -609.5403),
            interactDistanceMin = 3.15,
            interactDistanceMax = 4.5,
        },
    },
    ces = {
        [33] = {
            name = "Scourge of the Mind",
            territoryTypeId = 1252,
            preferredAethernet = "Eldergrowth",
            priority = 100,
            engageRadius = 20,
            stagingPoint = Vector3(300.109, 70.000, 730.029),
        },
        [34] = {
            name = "The Black Regiment",
            territoryTypeId = 1252,
            preferredAethernet = "Eldergrowth",
            priority = 100,
            engageRadius = 20,
            stagingPoint = Vector3(449.613, 65.000, 356.860),
        },
        [35] = {
            name = "The Unbridled",
            territoryTypeId = 1252,
            preferredAethernet = "Eldergrowth",
            priority = 100,
            engageRadius = 20,
            stagingPoint = Vector3(619.864, 79.000, 799.882),
        },
        [36] = {
            name = "Crawling Death",
            territoryTypeId = 1252,
            preferredAethernet = "Eldergrowth",
            priority = 100,
            engageRadius = 20,
            stagingPoint = Vector3(680.950, 74.000, 533.939),
        },
        [37] = {
            name = "Calamity Bound",
            territoryTypeId = 1252,
            preferredAethernet = "Stonemarsh",
            priority = 100,
            engageRadius = 20,
            stagingPoint = Vector3(-340.067, 75.000, 800.320),
        },
        [38] = {
            name = "Trial by Claw",
            territoryTypeId = 1252,
            preferredAethernet = "CrystallizedCaverns",
            priority = 100,
            engageRadius = 20,
            stagingPoint = Vector3(-413.775, 92.000, 74.884),
        },
        [39] = {
            name = "From Times Bygone",
            territoryTypeId = 1252,
            preferredAethernet = "Stonemarsh",
            priority = 100,
            engageRadius = 20,
            stagingPoint = Vector3(-799.895, 44.000, 245.027),
        },
        [40] = {
            name = "Company of Stone",
            territoryTypeId = 1252,
            preferredAethernet = "BaseCamp",
            priority = 100,
            engageRadius = 20,
            stagingPoint = Vector3(679.954, 96.000, -279.855),
        },
        [41] = {
            name = "Shark Attack",
            territoryTypeId = 1252,
            preferredAethernet = "TheWanderersHaven",
            priority = 100,
            engageRadius = 20,
            stagingPoint = Vector3(-117.227, 1.000, -849.941),
        },
        [42] = {
            name = "On the Hunt",
            territoryTypeId = 1252,
            preferredAethernet = "Eldergrowth",
            priority = 100,
            engageRadius = 20,
            stagingPoint = Vector3(635.981, 108.000, -53.950),
        },
        [43] = {
            name = "With Extreme Prejudice",
            territoryTypeId = 1252,
            preferredAethernet = "TheWanderersHaven",
            priority = 100,
            engageRadius = 20,
            stagingPoint = Vector3(-351.222, 5.000, -607.909),
        },
        [44] = {
            name = "Noise Complaint",
            territoryTypeId = 1252,
            preferredAethernet = "BaseCamp",
            priority = 100,
            engageRadius = 20,
            stagingPoint = Vector3(460.949, 97.000, -362.860),
        },
        [45] = {
            name = "Cursed Concern",
            territoryTypeId = 1252,
            preferredAethernet = "TheWanderersHaven",
            priority = 100,
            engageRadius = 20,
            stagingPoint = Vector3(71.964, 20.000, -544.904),
        },
        [46] = {
            name = "Eternal Watch",
            territoryTypeId = 1252,
            preferredAethernet = "Eldergrowth",
            priority = 100,
            engageRadius = 20,
            stagingPoint = Vector3(869.891, 122.000, 180.110),
        },
        [47] = {
            name = "Flame of Dusk",
            territoryTypeId = 1252,
            preferredAethernet = "CrystallizedCaverns",
            priority = 100,
            engageRadius = 20,
            stagingPoint = Vector3(-570.087, 97.000, -160.040),
        },
    },
}

local POLL_INTERVAL = 0.25
local MINIMUM_ROUTE_SAVINGS = 0
local USE_RETURN_AFTER = Config.Get("Use Return") == true
local PRIORITIZE_CE = Config.Get("Prioritize CE") ~= false
local BASE_DIRECT_THRESHOLD = 120
local CE_WAIT_RING_MIN = 7
local AUTOROTATION_PRESET_NAME = tostring(Config.Get("Autorotation Preset Name") or "")

local RETURN_PENALTY = 7.0
local AETHERNET_TRANSITION_PENALTY = 3.0
local SOUTH_HORN_TERRITORY_ID = 1252
local GENERAL_ACTION_RETURN = 8
local GENERAL_ACTION_MOUNT = 24
local ARRIVAL_DISTANCE = 2.5
local WAIT_POINT_FALLBACK_DISTANCE = 4.0
local TRANSITION_STABLE_SECONDS = 0.75
local TRANSITION_TIMEOUT = 10.0
local AETHERNET_TIMEOUT = 6.0
local RETURN_START_TIMEOUT = 2.0
local MOUNT_TIMEOUT = 8.0
local MOVE_TIMEOUT_PADDING = 15.0
local WAIT_POINT_RETRIES = 6
local AETHERNET_APPROACH_RETRIES = 5
local DESTINATION_CONFIRM_DISTANCE = 30.0
local POST_CE_COMBAT_SETTLE_SECONDS = 2.0
local RAISE_TIMEOUT = 300.0
local CE_ATTEMPT_TIMEOUT = 30.0
local IDLE_LOG_INTERVAL = 10.0
local BUFF_SETTLE_SECONDS = 1.0
local BUFF_TIMEOUT = 3.0
local BUFF_FRESH_DURATION = 600.0
local BUFF_VERIFY_RETRIES = 3
local CE_CHECK_INTERVAL = 2.5

local BUFF_ACTIONS = {
    { jobId = 0,  name = "Freelancer", actionId = 46606, minLevel = 15, buffName = "Inquiring Mind",      appliesAll = true,  checkStatusIds = { 4233, 4239, 4244, 4799 } },
    { jobId = 1,  name = "Knight",     actionId = 41589, minLevel = 2,  buffName = "Enduring Fortitude", statusId = 4233    },
    { jobId = 3,  name = "Monk",       actionId = 41597, minLevel = 3,  buffName = "Fleetfooted",        statusId = 4239    },
    { jobId = 6,  name = "Bard",       actionId = 41609, minLevel = 2,  buffName = "Romeo's Ballad",     statusId = 4244    },
    { jobId = 15, name = "Dancer",     actionId = 41603, minLevel = 2,  buffName = "Quick Step",         statusId = 4799    },
}

local ENABLE_BUFF_ROTATION = Config.Get("Enable Buff Rotation") ~= false

local BUFF_ZONE = {
    center = Vector3(836.07, 73.12, -709.45),
    radiusMin = 2.5,
    radiusMax = 4.5,
}

local FateState = {
    None = 0, Preparing = 1, Waiting = 2, Spawning = 3,
    Running = 4, Ending = 5, Ended = 6, Failed = 7,
}

local FATE_AETHERNET_PREFERENCE = {
    [1967] = "CrystallizedCaverns",  -- Brain Dead: hill climb from nearest aethernet is slower than flat route
}

local FARMING_MODE = tostring(Config.Get("Farming Mode") or "CE & FATE")
local ENABLE_CE_FARMING = FARMING_MODE ~= "FATE Only"
local ENABLE_FATE_FARMING = FARMING_MODE ~= "CE Only"
local FATE_PRIORITY = tostring(Config.Get("FATE Priority") or "Lowest Progress")

local EXCLUDED_FATES = {}
do
    local raw = tostring(Config.Get("Excluded FATEs") or "")
    if raw ~= "" then
        for name in string.gmatch(raw, "([^,]+)") do
            local trimmed = name:match("^%s*(.-)%s*$")
            if trimmed and trimmed ~= "" then
                EXCLUDED_FATES[trimmed] = true
            end
        end
    end
end

local lastFateAt = 0
local lastFateScanLogAt = 0
local FATE_DISENGAGE_GRACE_SEC = 2

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

local ceNameToId = nil
local stopAfterCurrentCe = false
local lastIdleLogAt = 0
local lastScanSummaryAt = 0
local lastCeRadiusLogAt = 0
local lastCeBattleLogAt = 0
local lastFateMoveLogAt = 0
local lastFateMonitorLogAt = 0
local lastCeCheckAt = 0
local moveToPosition
local isMounted
local isMounting
local isInCombat
local isLifestreamBusy
local returnToBaseAndWait

local function log(message)
    pcall(function()
        Dalamud.Log(string.format("%s %s", PREFIX, tostring(message)))
    end)
end

local function logf(fmt, ...)
    log(string.format(fmt, ...))
end

local function sleep(seconds)
    yield(string.format("/wait %.2f", tonumber(seconds) or 0))
end

local function safeCall(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

local function getCondition(flag)
    return flag ~= nil and Svc and Svc.Condition and Svc.Condition[flag] == true
end

local function describeConditionState()
    local states = {}
    if isMounted() then table.insert(states, "mounted") end
    if isMounting() then table.insert(states, "mounting") end
    if isInCombat() then table.insert(states, "combat") end
    if getCondition(CharacterCondition.casting) then table.insert(states, "casting") end
    if getCondition(CharacterCondition.occupiedInQuestEvent) then table.insert(states, "occupiedInQuestEvent") end
    if getCondition(CharacterCondition.betweenAreas) then table.insert(states, "betweenAreas") end
    if isLifestreamBusy() then table.insert(states, "lifestreamBusy") end
    if #states == 0 then
        return "idle"
    end
    return table.concat(states, ",")
end

local function getAddon(name)
    local ok, addon = pcall(Addons.GetAddon, name)
    return ok and addon or nil
end

local function isAddonReady(name)
    local addon = getAddon(name)
    return addon ~= nil and addon.Ready == true and addon.Exists == true
end

local function isDead()
    return getCondition(CharacterCondition.dead)
end

local function hasStatusId(statusId)
    local list = Player.Status
    if not list or not list.Count then return false end
    for i = 0, list.Count - 1 do
        local s = list[i]
        if s and s.StatusId == statusId then
            return true
        end
    end
    return false
end

local function getStatusRemaining(statusId)
    local list = Player.Status
    if not list or not list.Count then return -1 end
    for i = 0, list.Count - 1 do
        local s = list[i]
        if s and s.StatusId == statusId then
            local ok, remaining = pcall(function() return s.RemainingTime end)
            if ok and remaining ~= nil then
                return remaining
            end
            return -1
        end
    end
    return -1
end

local function hasRaiseStatus()
    return hasStatusId(148) or hasStatusId(1140)
end

local function handleDeathState()
    if not isDead() then return false end
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
            log("Raise dialog detected; waiting 1s for settle.")
            sleep(1.0)
            log("Accepting raise.")
            yield("/callback SelectYesno true 0")
            waitUntil(function()
                return not isDead()
            end, 3.0, 0.5)
            if not isDead() then
                log("Raised successfully.")
                return true
            end
            raiseDetected = false
        end

        sleep(POLL_INTERVAL)
    end

    log("No raise within 5 min; releasing to home point.")
    if isAddonReady("SelectYesno") then
        yield("/callback SelectYesno true 0")
        waitUntil(function()
            return not isDead()
        end, 5.0, 0)
    end
    if isDead() then
        log("Release did not revive player. Giving up.")
        return false
    end
    return true
end

local function isPlayerAvailable()
    return Player ~= nil and Player.Available == true
end

isMounted = function()
    return getCondition(CharacterCondition.mounted)
end

isMounting = function()
    return getCondition(CharacterCondition.mounting57) or getCondition(CharacterCondition.mounting64)
end

isInCombat = function()
    return getCondition(CharacterCondition.inCombat)
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

isLifestreamBusy = function()
    if IPC and IPC.Lifestream and IPC.Lifestream.IsBusy then
        local ok, busy = pcall(IPC.Lifestream.IsBusy)
        return ok and busy == true
    end
    return false
end

local function isBossModAvailable()
    return IPC and IPC.BossMod and IPC.BossMod.SetActive and IPC.BossMod.GetActive and IPC.BossMod.ClearActive
end

local function isLifestreamAvailable()
    return IPC and IPC.Lifestream and IPC.Lifestream.AethernetTeleportByPlaceNameId and IPC.Lifestream.IsBusy
end

local function isVnavAvailable()
    return IPC and IPC.vnavmesh and IPC.vnavmesh.IsReady and IPC.vnavmesh.PathfindAndMoveTo
end

local function formatVector3(position)
    if position == nil then
        return "nil"
    end
    return string.format("(%.3f, %.3f, %.3f)", position.X, position.Y, position.Z)
end

local function distanceFlat(a, b)
    if a == nil or b == nil then
        return math.huge
    end
    local dx = a.X - b.X
    local dz = a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
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

local function pathfindTo(position)
    if not isVnavAvailable() then
        log("vnavmesh unavailable while attempting pathfind.")
        return false
    end
    logf("Pathfinding to %s.", formatVector3(position))
    local ok = pcall(function()
        IPC.vnavmesh.PathfindAndMoveTo(position, false)
    end)
    if not ok then
        logf("Pathfind command failed for %s.", formatVector3(position))
    end
    return ok
end

local function stopPathing()
    log("Stopping vnav pathing.")
    yield("/vnav stop")
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

    logf("waitUntil timed out after %.2fs (stableSec=%.2f).", timeoutSec or 5, stableSec or 0)
    return false
end

local function executeGeneralAction(id)
    if not (Actions and Actions.ExecuteGeneralAction) then
        logf("Actions.ExecuteGeneralAction unavailable for id=%s.", tostring(id))
        return false
    end
    logf("Executing general action id=%s.", tostring(id))
    return pcall(function()
        Actions.ExecuteGeneralAction(id)
    end)
end

local function ensureMounted()
    if isMounted() and not isMounting() then
        log("Already mounted.")
        return true
    end

    local deadline = os.clock() + MOUNT_TIMEOUT
    local lastAttempt = -math.huge
    logf("Ensuring mounted state for up to %.2fs.", MOUNT_TIMEOUT)
    while os.clock() < deadline do
        if isMounted() and not isMounting() then
            log("Mounted state confirmed.")
            return true
        end
        if isInCombat() then
            sleep(1.0)
        elseif not isMounted() and not isMounting() and (os.clock() - lastAttempt) >= 1.0 then
            log("Mount not active; attempting mount action.")
            executeGeneralAction(GENERAL_ACTION_MOUNT)
            lastAttempt = os.clock()
        end
        sleep(POLL_INTERVAL)
    end
    log("Failed to mount before timeout.")
    return false
end

local function buildCeNameResolver()
    local result = {}
    local sheet = safeCall(function()
        return Excel.GetSheet("DynamicEvent")
    end)
    if sheet == nil then
        return result
    end
    local count = tonumber(sheet.Count) or 0
    for rowId = 0, math.max(0, count - 1) do
        local row = safeCall(function()
            return sheet:GetRow(rowId)
        end)
        if row ~= nil then
            local name = safeCall(function()
                return row:GetProperty("Name")
            end)
            if type(name) == "string" and name ~= "" then
                result[name] = rowId
            end
        end
    end
    logf("Built CE name resolver with %d entries.", count)
    return result
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
    log("Clearing BossMod preset.")
    pcall(IPC.BossMod.ClearActive)
    local cleared = waitUntil(function()
        return getBossModActive() == ""
    end, 2.5, 0.25)
    logf("BossMod clear result=%s active=%q.", tostring(cleared), getBossModActive())
    return cleared
end

local function applyBossModPreset(preset)
    if not isBossModAvailable() then
        log("BossMod IPC unavailable while applying preset.")
        return false
    end
    logf("Applying BossMod preset %q.", tostring(preset))
    pcall(function()
        IPC.BossMod.SetActive(preset)
    end)
    local applied = waitUntil(function()
        return getBossModActive() == preset
    end, 2.5, 0.25)
    logf("BossMod apply result=%s active=%q.", tostring(applied), getBossModActive())
    return applied
end

local function validateAutorotationPreset()
    local preset = tostring(AUTOROTATION_PRESET_NAME or "")
    if preset == "" then
        return false, "Autorotation Preset Name config is blank"
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
    logf("Autorotation preset %q validated successfully.", preset)
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
    if closest ~= nil then
        logf("Nearest configured aethernet to %s is %s at %.2f flat yalms.", formatVector3(position), tostring(closest.name), closestDistance)
    end
    return closest, closestDistance
end

local function isWithinAethernetBand(position, aethernet)
    local distance = distanceFlat(position, aethernet.position)
    local minDistance = tonumber(aethernet.interactDistanceMin or metadata.aethernetInteractDistanceMin) or 3.15
    local maxDistance = tonumber(aethernet.interactDistanceMax or metadata.aethernetInteractDistance) or 4.5
    return distance >= minDistance and distance <= maxDistance, distance, minDistance, maxDistance
end

local function aethernetApproachDistance(playerPosition, aethernet)
    if playerPosition == nil or aethernet == nil then return math.huge end
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
        logf("Could not derive directional approach for %s; falling back to random band point.", tostring(aethernet.name))
        return randomPointInRing(aethernet.position, minDistance, tonumber(aethernet.interactDistanceMax or metadata.aethernetInteractDistance) or 4.5)
    end
    local point = Vector3(
        aethernet.position.X + nx * minDistance,
        aethernet.position.Y,
        aethernet.position.Z + nz * minDistance
    )
    logf("Directional approach point for %s is %s.", tostring(aethernet.name), formatVector3(point))
    return point
end

local function getRandomAethernetBandPoint(aethernet)
    local minDistance = tonumber(aethernet.interactDistanceMin or metadata.aethernetInteractDistanceMin) or 3.15
    local maxDistance = tonumber(aethernet.interactDistanceMax or metadata.aethernetInteractDistance) or 4.5
    return randomPointInRing(aethernet.position, minDistance, maxDistance)
end

local function getBaseCampWaitPoint()
    local baseCamp = getAethernetByName("BaseCamp")
    if baseCamp == nil then
        return nil
    end
    local minDistance = tonumber(baseCamp.interactDistanceMin or metadata.aethernetInteractDistanceMin) or 3.15
    local maxDistance = tonumber(baseCamp.interactDistanceMax or metadata.aethernetInteractDistance) or 4.5
    local point = randomPointInRing(baseCamp.position, minDistance, maxDistance)
    logf("Generated Base Camp wait point %s.", formatVector3(point))
    return point
end

local function ensureAtBaseCampWaitBand()
    local baseCamp = getAethernetByName("BaseCamp")
    if baseCamp == nil then
        return false, "BaseCamp metadata missing"
    end

    local playerPosition = getPlayerPosition()
    local inBand = isWithinAethernetBand(playerPosition, baseCamp)
    if inBand then
        log("Already inside Base Camp interaction band; skipping Return.")
        return true, nil
    end

    local distanceToBase = distanceFlat(playerPosition, baseCamp.position)
    logf("Base Camp startup distance is %.2f flat yalms.", distanceToBase)

    if distanceToBase <= BASE_DIRECT_THRESHOLD then
        local waitPoint = getBaseCampWaitPoint()
        if waitPoint ~= nil and moveToPosition(waitPoint, WAIT_POINT_FALLBACK_DISTANCE) then
            return true, nil
        end
        return false, "failed to move into Base Camp wait band"
    end

    log("Player is not near Base Camp; using Return to recover to base.")
    return returnToBaseAndWait()
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
            if not sawStart then
                logf("%s transition start detected via condition %s.", label, tostring(startCondition))
            end
            sawStart = true
        end
        if betweenAreas then
            if not sawBetweenAreas then
                logf("%s entered betweenAreas transition.", label)
            end
            sawBetweenAreas = true
            stableStart = nil
        end

        local complete = sawStart
            and sawBetweenAreas
            and not betweenAreas
            and not getCondition(CharacterCondition.casting)
            and not isLifestreamBusy()
            and isPlayerAvailable()

        if complete then
            stableStart = stableStart or os.clock()
            if (os.clock() - stableStart) >= TRANSITION_STABLE_SECONDS then
                logf("%s transition completed.", label)
                return true
            end
        else
            stableStart = nil
        end

        sleep(POLL_INTERVAL)
    end

    logf("%s transition timed out. finalConditions=%s playerPos=%s", label, describeConditionState(), formatVector3(getPlayerPosition()))
    return false
end

local function waitForConditionStart(flag, timeoutSec, label)
    logf("Waiting up to %.2fs for %s start condition %s.", timeoutSec or 2.0, label, tostring(flag))
    local started = waitUntil(function()
        return getCondition(flag)
    end, timeoutSec or 2.0, 0)
    logf("%s start condition result=%s currentConditions=%s.", label, tostring(started), describeConditionState())
    return started
end

local function waitForCombatToSettle(timeoutSec)
    logf("Waiting for combat to remain clear for %.2fs.", POST_CE_COMBAT_SETTLE_SECONDS)
    local settled = waitUntil(function()
        return not isInCombat()
    end, timeoutSec or 15.0, POST_CE_COMBAT_SETTLE_SECONDS)
    logf("Combat settle result=%s inCombat=%s.", tostring(settled), tostring(isInCombat()))
    return settled
end

moveToPosition = function(targetPosition, stopDistance, timeoutSec)
    if targetPosition == nil then
        log("moveToPosition received nil target.")
        return false
    end
    local playerPosition = getPlayerPosition()
    if distanceFlat(playerPosition, targetPosition) <= (stopDistance or ARRIVAL_DISTANCE) then
        logf("Already within %.2f of %s.", stopDistance or ARRIVAL_DISTANCE, formatVector3(targetPosition))
        return true
    end
    if not pathfindTo(targetPosition) then
        return false
    end

    local timeout = timeoutSec or (((distanceFlat(playerPosition, targetPosition) / (metadata.mountedTravelSpeed or 14.13)) + MOVE_TIMEOUT_PADDING))
    logf("Waiting up to %.2fs to reach %s within %.2f yalms.", timeout, formatVector3(targetPosition), stopDistance or ARRIVAL_DISTANCE)
    local reached = waitUntil(function()
        return distanceFlat(getPlayerPosition(), targetPosition) <= (stopDistance or ARRIVAL_DISTANCE)
    end, timeout, 0.5)
    stopPathing()
    logf("Move to %s result=%s finalDistance=%.2f.", formatVector3(targetPosition), tostring(reached), distanceFlat(getPlayerPosition(), targetPosition))
    return reached
end

local function scanEvents()
    local snapshots = {}
    local events = safeCall(function()
        return InstancedContent.OccultCrescent.Events
    end)
    if events == nil then
        return snapshots
    end
    local eventCount = tonumber(events.Count) or 0
    for eventIndex = 0, math.max(0, eventCount - 1) do
        local event = safeCall(function()
            return events[eventIndex]
        end)
        if event ~= nil then
            local name = tostring(event.Name or "")
            local ceId = ceNameToId[name]
            local ceMetadata = ceId and metadata.ces[ceId] or nil
            local stateText = tostring(event.State or "nil")
            local snapshot = {
                index = eventIndex,
                id = ceId,
                name = name,
                stateText = stateText,
                stateCode = tonumber(string.match(stateText, "(%d+)")) or 0,
                isActive = event.IsActive == true,
                progress = tonumber(event.Progress) or 0,
                secondsLeft = tonumber(event.SecondsLeft) or 0,
                metadata = ceMetadata,
            }
            table.insert(snapshots, snapshot)
        end
    end
    return snapshots
end

local function waitForSnapshotById(ceId)
    local snapshots = scanEvents()
    for _, snapshot in ipairs(snapshots) do
        if snapshot.id == ceId then
            return snapshot
        end
    end
    return nil
end

local function shouldAbortForBattleState(snapshot)
    local shouldAbort = snapshot ~= nil and snapshot.stateCode >= 3 and distanceFlat(getPlayerPosition(), snapshot.metadata.stagingPoint) > (tonumber(snapshot.metadata.engageRadius) or 20)
    if shouldAbort then
        logf("Aborting CE %s because it reached Battle before arrival. playerDistance=%.2f radius=%.2f", snapshot.name, distanceFlat(getPlayerPosition(), snapshot.metadata.stagingPoint), tonumber(snapshot.metadata.engageRadius) or 20)
    end
    return shouldAbort
end

local CeMoveResult = { Arrived = 1, Timeout = 2, BattleAbort = 3, CeAvailable = 4 }

-- Returns: CeMoveResult constant
local function ceMoveToPosition(targetPosition, stopDistance, timeoutSec, ceId)
    if targetPosition == nil then
        log("ceMoveToPosition received nil target.")
        return CeMoveResult.Timeout
    end
    local playerPosition = getPlayerPosition()
    if distanceFlat(playerPosition, targetPosition) <= (stopDistance or ARRIVAL_DISTANCE) then
        logf("Already within %.2f of %s.", stopDistance or ARRIVAL_DISTANCE, formatVector3(targetPosition))
        return CeMoveResult.Arrived
    end
    if not pathfindTo(targetPosition) then
        return CeMoveResult.Timeout
    end

    local timeout = timeoutSec or CE_ATTEMPT_TIMEOUT
    local deadline = os.clock() + timeout
    logf("CE move up to %.2fs to %s within %.2f yalms.", timeout, formatVector3(targetPosition), stopDistance or ARRIVAL_DISTANCE)
    while os.clock() < deadline do
        local current = waitForSnapshotById(ceId)
        if shouldAbortForBattleState(current) then
            stopPathing()
            logf("CE move aborted: %s entered Battle.", formatVector3(targetPosition))
            return CeMoveResult.BattleAbort
        end
        if isDead() then
            stopPathing()
            log("Player died during CE travel; handling death.")
            handleDeathState()
            local afterDeath = waitForSnapshotById(ceId)
            if shouldAbortForBattleState(afterDeath) then
                logf("CE aborted after revive: entered Battle.")
                return CeMoveResult.BattleAbort
            end
            if not pathfindTo(targetPosition) then
                return CeMoveResult.Timeout
            end
        end
        if distanceFlat(getPlayerPosition(), targetPosition) <= (stopDistance or ARRIVAL_DISTANCE) then
            stopPathing()
            logf("CE move reached %s.", formatVector3(targetPosition))
            return CeMoveResult.Arrived
        end
        sleep(POLL_INTERVAL)
    end
    stopPathing()
    logf("CE move timed out after %.2fs for %s.", timeout, formatVector3(targetPosition))
    return CeMoveResult.Timeout
end

local function moveIntoAethernetBand(aethernet)
    local playerPosition = getPlayerPosition()
    local inBand = isWithinAethernetBand(playerPosition, aethernet)
    if inBand then
        logf("Already inside %s interaction band at %.2f yalms.", tostring(aethernet.name), select(2, isWithinAethernetBand(playerPosition, aethernet)))
        return true
    end

    local attempts = {}
    if aethernet.name == "BaseCamp" then
        table.insert(attempts, getBaseCampWaitPoint())
    else
        table.insert(attempts, getDirectionalApproachPoint(playerPosition, aethernet))
    end
    for _ = 1, AETHERNET_APPROACH_RETRIES do
        table.insert(attempts, getRandomAethernetBandPoint(aethernet))
    end

    for _, approachPoint in ipairs(attempts) do
        logf("Trying %s band approach point %s.", tostring(aethernet.name), formatVector3(approachPoint))
        if approachPoint ~= nil and moveToPosition(approachPoint, WAIT_POINT_FALLBACK_DISTANCE) then
            local nowInBand = isWithinAethernetBand(getPlayerPosition(), aethernet)
            if nowInBand then
                logf("Entered %s interaction band successfully.", tostring(aethernet.name))
                return true
            end
        end
    end

    logf("Failed to enter %s interaction band.", tostring(aethernet.name))
    return false
end

local function waitForArrivalNearDestination(aethernet, timeoutSec)
    logf("Waiting for arrival near %s destination %s within %.2f yalms.", tostring(aethernet.name), formatVector3(aethernet.destination), DESTINATION_CONFIRM_DISTANCE)
    local arrived = waitUntil(function()
        return distanceFlat(getPlayerPosition(), aethernet.destination) <= DESTINATION_CONFIRM_DISTANCE
    end, timeoutSec or 4.0, 0.5)
    logf("Arrival near %s destination result=%s finalDistance=%.2f.", tostring(aethernet.name), tostring(arrived), distanceFlat(getPlayerPosition(), aethernet.destination))
    return arrived
end

local function useOccultAethernet(preferredAethernet)
    if not isLifestreamAvailable() then
        return false, "Lifestream aethernet IPC is unavailable"
    end

    local playerPosition = getPlayerPosition()
    local currentAethernet = nil
    for _, aethernet in pairs(metadata.aethernets or {}) do
        local inBand, distance = isWithinAethernetBand(playerPosition, aethernet)
        if inBand then
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

    logf(
        "Using Occult aethernet from '%s' to '%s' (placeNameId=%s).",
        tostring(currentAethernet.name),
        tostring(preferredAethernet.name),
        tostring(preferredAethernet.placeNameId)
    )

    local ok = safeCall(function()
        return IPC.Lifestream.AethernetTeleportByPlaceNameId(preferredAethernet.placeNameId)
    end)
    logf("Lifestream AethernetTeleportByPlaceNameId(%s) returned %s.", tostring(preferredAethernet.placeNameId), tostring(ok))
    if ok ~= true then
        return false, "Lifestream AethernetTeleportByPlaceNameId returned false"
    end

    if not waitForTransitionCompletion(CharacterCondition.occupiedInQuestEvent, AETHERNET_TIMEOUT, "Aethernet") then
        return false, "aethernet transition did not complete"
    end

    if not waitForArrivalNearDestination(preferredAethernet, 4.0) then
        return false, string.format("did not arrive near destination for '%s'", tostring(preferredAethernet.name))
    end

    return true, nil
end

local function useReturn()
    if isDead() then
        log("Player is dead; cannot use Return.")
        return false, "player is dead"
    end
    if isInCombat() then
        log("Player is in combat; cannot use Return.")
        return false, "player in combat"
    end
    if not executeGeneralAction(GENERAL_ACTION_RETURN) then
        return false, "failed to trigger Return"
    end
    log("Return action triggered.")

    local deadline = os.clock() + 3.0
    local castingStarted = false

    while os.clock() < deadline do
        if isAddonReady("SelectYesno") then
            log("SelectYesno detected during Return; confirming.")
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

local function isPreBattleState(snapshot)
    return snapshot ~= nil and snapshot.isActive and snapshot.stateCode > 0 and snapshot.stateCode < 3
end

local function selectTargetCe(snapshots)
    local candidates = {}
    for _, snapshot in ipairs(snapshots) do
        local ceMetadata = snapshot.metadata
        if ceMetadata ~= nil and ceMetadata.stagingPoint ~= nil and isPreBattleState(snapshot) then
            table.insert(candidates, snapshot)
        end
    end
    if #candidates == 0 then return nil end
    table.sort(candidates, function(a, b)
        return (a.metadata.priority or 0) > (b.metadata.priority or 0)
    end)
    local best = candidates[1]
    logf("Selected CE %s (%s) priority=%d state=%s active=%s progress=%d left=%d.", best.name, tostring(best.id), best.metadata.priority or 0, best.stateText, tostring(best.isActive), best.progress, best.secondsLeft)
    return best
end

local function chooseRoute(snapshot)
    local playerPosition = getPlayerPosition()
    local ceMetadata = snapshot.metadata
    local preferredAethernet = getAethernetByName(ceMetadata.preferredAethernet)
    if preferredAethernet == nil then
        return { kind = "direct", reason = "no_preferred_aethernet" }
    end

    do
        for _, ae in pairs(metadata.aethernets) do
            if isWithinAethernetBand(playerPosition, ae) and ae.name == preferredAethernet.name then
                logf("Player already at preferred aethernet %s; routing direct.", ae.name)
                return { kind = "direct", reason = "already_at_preferred_aethernet", preferred = preferredAethernet }
            end
        end
    end

    local speed = tonumber(metadata.mountedTravelSpeed) or 14.13
    local directTime = distanceFlat(playerPosition, ceMetadata.stagingPoint) / speed

    local nearestAethernet = getNearestConfiguredAethernet(playerPosition)
    local nearestApproachDistance = aethernetApproachDistance(playerPosition, nearestAethernet)
    local shardTime = (nearestApproachDistance / speed) + AETHERNET_TRANSITION_PENALTY + (distanceFlat(preferredAethernet.destination, ceMetadata.stagingPoint) / speed)
    local returnTime = RETURN_PENALTY + ((preferredAethernet.name == "BaseCamp") and 0 or AETHERNET_TRANSITION_PENALTY) + (distanceFlat(preferredAethernet.destination, ceMetadata.stagingPoint) / speed)

    local baseCamp = getAethernetByName("BaseCamp")
    local inBaseBand = baseCamp and isWithinAethernetBand(playerPosition, baseCamp)
    local nearBase = baseCamp and distanceFlat(playerPosition, baseCamp.position) <= BASE_DIRECT_THRESHOLD
    if preferredAethernet.name == "BaseCamp" and (inBaseBand or nearBase) then
        logf("Route metrics for %s: direct=%.2f shard=%.2f return=%.2f; using direct because player is already close to base.", snapshot.name, directTime, shardTime, returnTime)
        return { kind = "direct", reason = "already_close_to_base", preferred = preferredAethernet }
    end

    if (directTime + MINIMUM_ROUTE_SAVINGS) <= shardTime and (directTime + MINIMUM_ROUTE_SAVINGS) <= returnTime then
        logf("Route metrics for %s: direct=%.2f shard=%.2f return=%.2f; choosing direct.", snapshot.name, directTime, shardTime, returnTime)
        return { kind = "direct", reason = "faster_direct", preferred = preferredAethernet }
    end

    if returnTime + MINIMUM_ROUTE_SAVINGS < shardTime then
        logf("Route metrics for %s: direct=%.2f shard=%.2f return=%.2f; choosing return route.", snapshot.name, directTime, shardTime, returnTime)
        return { kind = "return", reason = "return_route", preferred = preferredAethernet }
    end

    logf("Route metrics for %s: direct=%.2f shard=%.2f return=%.2f; choosing aethernet route.", snapshot.name, directTime, shardTime, returnTime)
    return { kind = "aethernet", reason = "aethernet_route", preferred = preferredAethernet }
end

local function getCeWaitPoint(ceMetadata)
    local maxRadius = tonumber(ceMetadata.engageRadius) or 20
    local minRadius = math.min(CE_WAIT_RING_MIN, maxRadius)
    local point = randomPointInRing(ceMetadata.stagingPoint, minRadius, maxRadius)
    logf("Generated CE wait point %s around staging point %s using ring %.2f..%.2f.", formatVector3(point), formatVector3(ceMetadata.stagingPoint), minRadius, maxRadius)
    return point
end

local function ensureInsideCeRadius(snapshot)
    local distance = distanceFlat(getPlayerPosition(), snapshot.metadata.stagingPoint)
    if distance <= (tonumber(snapshot.metadata.engageRadius) or 20) then
        if (os.clock() - lastCeRadiusLogAt) >= IDLE_LOG_INTERVAL then
            logf("Player remains inside CE radius for %s at %.2f yalms.", snapshot.name, distance)
            lastCeRadiusLogAt = os.clock()
        end
        return true
    end

    logf("Player drifted outside CE radius for %s: %.2f > %.2f. Repositioning.", snapshot.name, distance, tonumber(snapshot.metadata.engageRadius) or 20)
    lastCeRadiusLogAt = os.clock()

    local fallbackPoint = getCeWaitPoint(snapshot.metadata)
    if not moveToPosition(fallbackPoint, WAIT_POINT_FALLBACK_DISTANCE) then
        return moveToPosition(snapshot.metadata.stagingPoint, tonumber(snapshot.metadata.engageRadius) or 20)
    end

    return distanceFlat(getPlayerPosition(), snapshot.metadata.stagingPoint) <= (tonumber(snapshot.metadata.engageRadius) or 20)
end

local function isWithinBuffZone(position)
    local distance = distanceFlat(position, BUFF_ZONE.center)
    return distance >= BUFF_ZONE.radiusMin and distance <= BUFF_ZONE.radiusMax, distance
end

local function getDirectionalBuffPoint(playerPosition)
    local nx, nz = normalizeFlat(BUFF_ZONE.center, playerPosition)
    if nx == nil then
        return randomPointInRing(BUFF_ZONE.center, BUFF_ZONE.radiusMin, BUFF_ZONE.radiusMax)
    end
    return Vector3(
        BUFF_ZONE.center.X + nx * BUFF_ZONE.radiusMin,
        BUFF_ZONE.center.Y,
        BUFF_ZONE.center.Z + nz * BUFF_ZONE.radiusMin
    )
end

local function getRandomBuffPoint()
    return randomPointInRing(BUFF_ZONE.center, BUFF_ZONE.radiusMin, BUFF_ZONE.radiusMax)
end

local function moveIntoBuffZone()
    local playerPosition = getPlayerPosition()
    local inBand = isWithinBuffZone(playerPosition)
    if inBand then
        logf("Already inside buff zone at %.2f yalms from center.", select(2, isWithinBuffZone(playerPosition)))
        return true
    end

    local distToBuff = distanceFlat(playerPosition, BUFF_ZONE.center)
    if distToBuff > 50 then
        logf("Buff zone is %.1f yalms away; using Return first.", distToBuff)
        useReturn()
    end

    local approachPoint = getDirectionalBuffPoint(playerPosition)
    logf("Buff zone approach point: %s.", formatVector3(approachPoint))
    if approachPoint ~= nil and moveToPosition(approachPoint, 1.0) then
        local nowInBand = isWithinBuffZone(getPlayerPosition())
        if nowInBand then
            log("Entered buff zone successfully.")
            return true
        end
    end

    for i = 1, AETHERNET_APPROACH_RETRIES do
        local point = getRandomBuffPoint()
        logf("Buff zone retry %d/%d: %s.", i, AETHERNET_APPROACH_RETRIES, formatVector3(point))
        if point ~= nil and moveToPosition(point, 1.0) then
            if isWithinBuffZone(getPlayerPosition()) then
                log("Entered buff zone on retry.")
                return true
            end
        end
    end

    log("Failed to enter buff zone.")
    return false
end

local function applyBuffRotation()
    if not ENABLE_BUFF_ROTATION then return end
    if isDead() or isInCombat() then
        log("Buff rotation skipped: player dead or in combat.")
        return
    end

    local ocState = InstancedContent.OccultCrescent.OccultCrescentState
    if ocState == nil then
        log("Buff rotation skipped: OccultCrescentState unavailable.")
        return
    end

    local levels = ocState.SupportJobLevels
    if levels == nil or levels.Length < 16 then
        logf("Buff rotation skipped: SupportJobLevels unavailable or incomplete (%s).", tostring(levels and levels.Length or "nil"))
        return
    end

    local originalJob = ocState.CurrentSupportJob
    if originalJob == nil then
        log("Buff rotation skipped: could not read current job.")
        return
    end

    logf("Starting buff rotation for originalJob=%d.", originalJob)

    -- Pre-check: are any buffs actually needed?
    local needsBuff = false
    for _, entry in ipairs(BUFF_ACTIONS) do
        local jobLevel = levels[entry.jobId]
        if jobLevel ~= nil and jobLevel >= entry.minLevel then
            if entry.appliesAll then
                local anyExpired = false
                for _, sid in ipairs(entry.checkStatusIds) do
                    if getStatusRemaining(sid) < BUFF_FRESH_DURATION then
                        anyExpired = true
                        break
                    end
                end
                if anyExpired then needsBuff = true; break end
            elseif entry.statusId then
                if getStatusRemaining(entry.statusId) < BUFF_FRESH_DURATION then
                    needsBuff = true
                    break
                end
            end
        end
    end

    if not needsBuff then
        log("Buff rotation: all buffs fresh, skipping.")
        return
    end

    if not moveIntoBuffZone() then
        log("Buff rotation: failed to reach buff zone, proceeding anyway.")
    end

    if isMounted() then
        log("Buff rotation: dismounting before casting.")
        Actions.ExecuteGeneralAction(23)
        sleep(0.5)
    end

    sleep(BUFF_SETTLE_SECONDS)

    for _, entry in ipairs(BUFF_ACTIONS) do
        local jobLevel = levels[entry.jobId]
        if jobLevel == nil or jobLevel < entry.minLevel then
            logf("Buff rotation: skipping %s (jobId=%d level=%d < %d).", entry.name, entry.jobId, jobLevel or 0, entry.minLevel)
            goto continue
        end

        if entry.statusId then
            local remaining = getStatusRemaining(entry.statusId)
            if remaining >= BUFF_FRESH_DURATION then
                logf("Buff rotation: %s still has %.0fs remaining, skipping.", entry.name, remaining)
                if entry.appliesAll then
                    log("Buff rotation: Freelancer buff still fresh, skipping all.")
                    break
                end
                goto continue
            end
        end

        if entry.jobId ~= originalJob then
            logf("Buff rotation: switching to %s (jobId=%d).", entry.name, entry.jobId)
            local ok, err = pcall(function()
                ocState:ChangeSupportJob(entry.jobId)
            end)
            if not ok then
                logf("Buff rotation: ChangeSupportJob(%d) failed: %s", entry.jobId, tostring(err))
                goto continue
            end

            waitUntil(function()
                return ocState.CurrentSupportJob == entry.jobId
            end, BUFF_TIMEOUT, BUFF_SETTLE_SECONDS)
        else
            logf("Buff rotation: already on %s (jobId=%d), skipping switch.", entry.name, entry.jobId)
        end

        local applied = false
        for attempt = 1, BUFF_VERIFY_RETRIES do
            sleep(BUFF_SETTLE_SECONDS)

            logf("Buff rotation: casting %s (actionId=%d) attempt %d/%d.", entry.buffName, entry.actionId, attempt, BUFF_VERIFY_RETRIES)
            local ok, err = pcall(function()
                Actions.ExecuteAction(entry.actionId)
            end)
            if not ok then
                logf("Buff rotation: ExecuteAction(%d) failed: %s", entry.actionId, tostring(err))
                goto skip_retry
            end

            sleep(BUFF_SETTLE_SECONDS)

            if entry.appliesAll then
                for _, sid in ipairs(entry.checkStatusIds) do
                    if hasStatusId(sid) then
                        local remain = getStatusRemaining(sid)
                        logf("Buff rotation: %s verified via status %d (%.0fs remaining).", entry.buffName, sid, remain)
                        applied = true
                        break
                    else
                        local remain = getStatusRemaining(sid)
                        logf("Buff rotation: %s status %d not found (remain=%.0f).", entry.buffName, sid, remain)
                    end
                end
            elseif entry.statusId then
                local remain = getStatusRemaining(entry.statusId)
                logf("Buff rotation: %s status %d remain=%.0fs.", entry.buffName, entry.statusId, remain)
                applied = hasStatusId(entry.statusId)
            else
                applied = true
            end

            if applied then
                break
            end

            if attempt < BUFF_VERIFY_RETRIES then
                logf("Buff rotation: %s not verified, repositioning and retrying.", entry.buffName)
                if not moveIntoBuffZone() then
                    log("Buff rotation: repositioning failed, proceeding anyway.")
                end
                sleep(BUFF_SETTLE_SECONDS)
            end
        end

        if not applied then
            logf("Buff rotation: %s failed to apply after %d attempts.", entry.buffName, BUFF_VERIFY_RETRIES)
        end

        if entry.appliesAll then
            if applied then
                log("Buff rotation: Freelancer Inquiring Mind covers all buffs, done.")
                break
            end
            log("Buff rotation: Freelancer Inquiring Mind failed, falling through to individual buffs.")
        end

        ::skip_retry::
        sleep(BUFF_SETTLE_SECONDS)
        ::continue::
        ; -- no-op for label target
    end

    if originalJob ~= nil and ocState.CurrentSupportJob ~= originalJob then
        logf("Buff rotation: restoring job %d.", originalJob)
        pcall(function()
            ocState:ChangeSupportJob(originalJob)
        end)
        waitUntil(function()
            return ocState.CurrentSupportJob == originalJob
        end, BUFF_TIMEOUT, BUFF_SETTLE_SECONDS)
    end

    log("Buff rotation complete.")
end

returnToBaseAndWait = function()
    log("Starting return-to-base flow.")
    if USE_RETURN_AFTER then
        local ok, err = useReturn()
        if not ok then
            logf("Return failed: %s", tostring(err))
            return false, err
        end
    end

    local waitPoint = getBaseCampWaitPoint()
    if waitPoint ~= nil then
        logf("Moving to Base Camp wait point %s.", formatVector3(waitPoint))
        if not moveToPosition(waitPoint, WAIT_POINT_FALLBACK_DISTANCE) then
            return false, "failed to move to Base Camp wait point"
        end
    end
    return true, nil
end

local function stopScriptWithError(message)
    logf("Fatal: %s", tostring(message))
    error(message)
end

function OnStop()
    pcall(function()
        log("OnStop cleanup starting.")
    end)

    pcall(function()
        yield("/vnav stop")
    end)

    pcall(function()
        if isBossModAvailable() then
            IPC.BossMod.ClearActive()
        end
    end)

    pcall(function()
        log("OnStop cleanup finished.")
    end)
end

local function handleAutorotationEnable(snapshot)
    if applyBossModPreset(AUTOROTATION_PRESET_NAME) then
        logf("Autorotation enabled for CE %s (%s).", snapshot.name, tostring(snapshot.id))
        return true
    end

    if snapshot.stateCode < 3 then
        log("Autorotation activation failed before Battle; returning and stopping.")
        useReturn()
        stopScriptWithError("BossMod preset activation failed before Battle")
    end

    stopAfterCurrentCe = true
    log("Autorotation activation failed during Battle; will stop after current CE.")
    return false
end

local function travelToCe(snapshot)
    local route = chooseRoute(snapshot)
    local preferredAethernet = route.preferred
    logf("Selected CE '%s' (%s) via route %s (%s).", snapshot.name, tostring(snapshot.id), route.kind, route.reason)

    if route.kind == "return" then
        logf("Travel flow for %s: Return first, then shard/direct continuation.", snapshot.name)
        local ok, err = useReturn()
        if not ok then
            return false, err
        end
        if preferredAethernet ~= nil and preferredAethernet.name ~= "BaseCamp" then
            local aethOk, aethErr = useOccultAethernet(preferredAethernet)
            if not aethOk then
                return false, aethErr
            end
        end
    elseif route.kind == "aethernet" then
        logf("Travel flow for %s: local aethernet teleport.", snapshot.name)
        local aethOk, aethErr = useOccultAethernet(preferredAethernet)
        if not aethOk then
            return false, aethErr
        end
    else
        logf("Travel flow for %s: direct mounted travel.", snapshot.name)
    end

    logf("Waiting for combat to settle before mounting for CE %s.", snapshot.name)
    while true do
        if isDead() then
            handleDeathState()
        end

        local ceSnapshot = waitForSnapshotById(snapshot.id)
        if ceSnapshot == nil then
            logf("CE %s vanished while waiting for combat to settle.", snapshot.name)
            return false, "ce_expired"
        end

        if ceSnapshot.stateCode >= 4 or shouldAbortForBattleState(ceSnapshot) then
            logf("CE %s entered Battle or later (stateCode=%d) while waiting for combat to settle.", snapshot.name, ceSnapshot.stateCode)
            return false, "ce_expired"
        end

        if not isInCombat() then
            logf("Combat settled for CE %s.", snapshot.name)
            break
        end

        sleep(POLL_INTERVAL)
    end

    if not ensureMounted() then
        return false, "failed to mount"
    end

    local waitPoint = nil
    local moved = false

    for attempt = 1, WAIT_POINT_RETRIES do
        if shouldAbortForBattleState(waitForSnapshotById(snapshot.id)) then
            local _, returnErr = useReturn()
            return false, (returnErr and ("battle-abort; return failed: " .. returnErr)) or "CE entered Battle before arrival"
        end
        waitPoint = getCeWaitPoint(snapshot.metadata)
        logf("CE wait-point attempt %d/%d: target %s.", attempt, WAIT_POINT_RETRIES, formatVector3(waitPoint))
        local result = ceMoveToPosition(waitPoint, WAIT_POINT_FALLBACK_DISTANCE, nil, snapshot.id)
        if result == CeMoveResult.Arrived then
            moved = true
            break
        end
        if result == CeMoveResult.BattleAbort then
            local _, returnErr = useReturn()
            return false, (returnErr and ("battle-abort; return failed: " .. returnErr)) or "CE entered Battle before arrival"
        end
    end

    if not moved then
        logf("All wait-point attempts exhausted; falling back to staging point for %s.", snapshot.name)
        if shouldAbortForBattleState(waitForSnapshotById(snapshot.id)) then
            local _, returnErr = useReturn()
            return false, (returnErr and ("battle-abort; return failed: " .. returnErr)) or "CE entered Battle before arrival"
        end
        local result = ceMoveToPosition(snapshot.metadata.stagingPoint, tonumber(snapshot.metadata.engageRadius) or 20, nil, snapshot.id)
        if result == CeMoveResult.Arrived then
            moved = true
            logf("Fell back to staging point for %s.", snapshot.name)
        end
        if result == CeMoveResult.BattleAbort then
            local _, returnErr = useReturn()
            return false, (returnErr and ("battle-abort; return failed: " .. returnErr)) or "CE entered Battle before arrival"
        end
    end

    if not moved then
        return false, "failed to reach CE wait area"
    end

    return true, nil
end

local function monitorCe(snapshot)
    local autorotationActive = false
    logf("Monitoring CE %s (%s).", snapshot.name, tostring(snapshot.id))

    while true do
        local current = waitForSnapshotById(snapshot.id)
        if current == nil then
            logf("CE %s disappeared from scan results.", snapshot.name)
            return true
        end

        if current.stateCode == 0 and not current.isActive then
            logf("CE %s is now inactive; ending monitor loop.", current.name)
            break
        end

        if current.stateCode >= 3 then
            if (os.clock() - lastCeBattleLogAt) >= IDLE_LOG_INTERVAL then
                logf("CE %s is in Battle state. autorotationActive=%s inCombat=%s", current.name, tostring(autorotationActive), tostring(isInCombat()))
                lastCeBattleLogAt = os.clock()
            end
            if not autorotationActive then
                autorotationActive = handleAutorotationEnable(current)
            end
        elseif isInCombat() then
            logf("Player is in combat while CE %s is pre-Battle. autorotationActive=%s", current.name, tostring(autorotationActive))
            if not autorotationActive then
                autorotationActive = handleAutorotationEnable(current)
            end
        elseif autorotationActive and not isInCombat() then
            logf("Combat ended before Battle for CE %s; clearing autorotation and rechecking radius.", current.name)
            clearBossModPreset()
            autorotationActive = false
            ensureInsideCeRadius(current)
        else
            ensureInsideCeRadius(current)
        end

        if isDead() then
            logf("Player died during CE %s.", current.name)
            handleDeathState()
            local afterDeath = waitForSnapshotById(snapshot.id)
            if afterDeath and afterDeath.isActive then
                autorotationActive = false
                if afterDeath.stateCode >= 3 or isInCombat() then
                    autorotationActive = handleAutorotationEnable(afterDeath)
                end
            else
                break
            end
        end

        sleep(POLL_INTERVAL)
    end

    waitForCombatToSettle()
    logf("Final combat clear reached for CE %s. Clearing autorotation.", snapshot.name)
    clearBossModPreset()
    return true
end

--#region FATE functions

local function isInFate()
    local cf = safeCall(function() return Fates.CurrentFate end)
    if cf ~= nil and cf.InFate then
        lastFateAt = os.clock()
        return true
    end
    if lastFateAt > 0 and (os.clock() - lastFateAt) <= FATE_DISENGAGE_GRACE_SEC then
        return true
    end
    return false
end

local function getFateSnapshot(fateId)
    local fate = safeCall(function() return Fates.GetFateById(fateId) end)
    if fate == nil then return nil end
    return {
        id = tonumber(safeCall(function() return fate.Id end)) or 0,
        name = tostring(safeCall(function() return fate.Name end) or ""),
        state = tonumber(safeCall(function() return fate.State end)) or 0,
        inFate = safeCall(function() return fate.InFate end) == true,
        progress = tonumber(safeCall(function() return fate.Progress end)) or 0,
        radius = tonumber(safeCall(function() return fate.Radius end)) or 0,
        location = safeCall(function() return fate.Location end),
    }
end

local function isFateActive(fateId)
    local activeFates = safeCall(function() return Fates.GetActiveFates() end)
    if activeFates == nil then return false end
    local count = tonumber(safeCall(function() return activeFates.Count end)) or 0
    for i = 0, math.max(0, count - 1) do
        local f = safeCall(function() return activeFates[i] end)
        if f ~= nil then
            local id = tonumber(safeCall(function() return f.Id end)) or 0
            if id == fateId then return true end
        end
    end
    return false
end

local function scanFates()
    local result = {}
    local activeFates = safeCall(function() return Fates.GetActiveFates() end)
    if activeFates == nil then
        return result
    end
    local count = tonumber(safeCall(function() return activeFates.Count end)) or 0
    local shouldLog = (os.clock() - lastFateScanLogAt) >= IDLE_LOG_INTERVAL
    if shouldLog then
        lastFateScanLogAt = os.clock()
        logf("scanFates: %d active entries.", count)
    end
    for i = 0, math.max(0, count - 1) do
        local fate = safeCall(function() return activeFates[i] end)
        if fate ~= nil then
            local state = tonumber(safeCall(function() return fate.State end)) or 0
            local name = tostring(safeCall(function() return fate.Name end) or "?")
            local id = tonumber(safeCall(function() return fate.Id end)) or 0
            local prog = tonumber(safeCall(function() return fate.Progress end)) or 0
            local radius = tonumber(safeCall(function() return fate.Radius end)) or 0
            local dist = tonumber(safeCall(function() return fate.DistanceToPlayer end)) or 0
            if shouldLog then
                logf("scanFates: [%d] '%s' id=%d state=%d progress=%.1f radius=%.1f dist=%.1f excluded=%s.", i, name, id, state, prog, radius, dist, tostring(EXCLUDED_FATES[name] == true))
            end
            if state ~= FateState.Ended and state ~= FateState.Failed and not EXCLUDED_FATES[name] then
                table.insert(result, {
                    id = id,
                    name = name,
                    location = safeCall(function() return fate.Location end),
                    radius = radius,
                    progress = prog,
                    distance = dist,
                    state = state,
                })
            end
        end
    end
    return result
end

local function selectTargetFate(fates)
    if #fates == 0 then return nil end
    if FATE_PRIORITY == "Nearest" then
        table.sort(fates, function(a, b) return a.distance < b.distance end)
    else
        table.sort(fates, function(a, b)
            if a.progress ~= b.progress then return a.progress < b.progress end
            return a.distance < b.distance
        end)
    end
    local best = fates[1]
    logf("Selected FATE '%s' (id=%d) progress=%.1f distance=%.1f radius=%.1f.", best.name, best.id, best.progress, best.distance, best.radius)
    return best
end

local function chooseFateRoute(fate)
    local playerPosition = getPlayerPosition()
    local speed = metadata.mountedTravelSpeed or 14.13
    local directTime = distanceFlat(playerPosition, fate.location) / speed

    local nearestToPlayer = getNearestConfiguredAethernet(playerPosition)
    local nearestToFate = getNearestConfiguredAethernet(fate.location)
    if nearestToFate ~= nil and FATE_AETHERNET_PREFERENCE[fate.id] then
        local preferred = getAethernetByName(FATE_AETHERNET_PREFERENCE[fate.id])
        if preferred then
            logf("FATE %s: overriding nearest aethernet (%s) with preferred (%s).", fate.name, nearestToFate.name, preferred.name)
            nearestToFate = preferred
        end
    end

    if nearestToFate == nil then
        return { kind = "direct", reason = "no_near_aethernet" }
    end

    local approachDist = aethernetApproachDistance(playerPosition, nearestToPlayer)
    local shardRideDist = distanceFlat(nearestToFate.destination, fate.location)
    local shardTime = (approachDist / speed) + AETHERNET_TRANSITION_PENALTY + (shardRideDist / speed)

    local returnTeleportPenalty = (nearestToFate.name == "BaseCamp") and 0 or AETHERNET_TRANSITION_PENALTY
    local returnRideDist = distanceFlat(nearestToFate.destination, fate.location)
    local returnTime = RETURN_PENALTY + returnTeleportPenalty + (returnRideDist / speed)

    logf("FATE route for '%s': direct=%.1fs (%.0fy) shard=%.1fs (approach=%.0fy ride=%.0fy penalty=%.1f) return=%.1fs (penalty=%.1f+%.1f ride=%.0fy) nearest_player=%s nearest_fate=%s",
        fate.name, directTime, distanceFlat(playerPosition, fate.location),
        shardTime, approachDist, shardRideDist, AETHERNET_TRANSITION_PENALTY,
        returnTime, RETURN_PENALTY, returnTeleportPenalty, returnRideDist,
        nearestToPlayer and nearestToPlayer.name or "nil",
        nearestToFate and nearestToFate.name or "nil")

    if directTime <= shardTime and directTime <= returnTime then
        logf("FATE route: chose direct (fastest).")
        return { kind = "direct", reason = "faster_direct" }
    end
    if returnTime < shardTime then
        logf("FATE route: chose return+teleport via %s (%.1fs vs shard %.1fs vs direct %.1fs).", nearestToFate.name, returnTime, shardTime, directTime)
        return { kind = "return", reason = "faster_return", preferred = nearestToFate }
    end
    logf("FATE route: chose aethernet via %s (%.1fs vs return %.1fs vs direct %.1fs).", nearestToFate.name, shardTime, returnTime, directTime)
    return { kind = "aethernet", reason = "faster_shard", preferred = nearestToFate }
end

local function isCeAvailable()
    local events = safeCall(function() return InstancedContent.OccultCrescent.Events end)
    if events == nil then return false end
    local count = tonumber(safeCall(function() return events.Count end)) or 0
    for i = 0, math.max(0, count - 1) do
        local event = safeCall(function() return events[i] end)
        if event ~= nil then
            local name = tostring(event.Name or "")
            local ceId = ceNameToId[name]
            local ceMetadata = ceId and metadata.ces[ceId] or nil
            if ceMetadata ~= nil and ceMetadata.stagingPoint ~= nil then
                local isActive = event.IsActive == true
                local stateText = tostring(event.State or "")
                local stateCode = tonumber(string.match(stateText, "(%d+)")) or 0
                if isActive and stateCode > 0 and stateCode < 3 then
                    return true
                end
            end
        end
    end
    return false
end

local function fateMoveToPosition(targetPosition, stopDistance, timeoutSec, fateId)
    if targetPosition == nil then return CeMoveResult.Timeout end
    if distanceFlat(getPlayerPosition(), targetPosition) <= (stopDistance or ARRIVAL_DISTANCE) then
        return CeMoveResult.Arrived
    end
    if not pathfindTo(targetPosition) then return CeMoveResult.Timeout end

    lastCeCheckAt = os.clock()
    local timeout = timeoutSec or CE_ATTEMPT_TIMEOUT
    local deadline = os.clock() + timeout
    while os.clock() < deadline do
        if not isFateActive(fateId) then
            stopPathing()
            logf("FATE %d no longer in active list; aborting move.", fateId)
            return CeMoveResult.BattleAbort
        end
        local snapshot = getFateSnapshot(fateId)
        if snapshot == nil then
            stopPathing()
            logf("FATE %d vanished; aborting move.", fateId)
            return CeMoveResult.BattleAbort
        end
        if (os.clock() - lastFateMoveLogAt) >= IDLE_LOG_INTERVAL then
            logf("fateMoveToPosition still running for fateId=%d, remaining=%.1fs.", fateId, deadline - os.clock())
            lastFateMoveLogAt = os.clock()
        end
        if PRIORITIZE_CE and ENABLE_CE_FARMING and (os.clock() - lastCeCheckAt) >= CE_CHECK_INTERVAL then
            lastCeCheckAt = os.clock()
            if isCeAvailable() then
                stopPathing()
                logf("CE available while traveling to FATE %d; aborting.", fateId)
                return CeMoveResult.CeAvailable
            end
        end
        if isDead() then
            stopPathing()
            handleDeathState()
            if not pathfindTo(targetPosition) then return CeMoveResult.Timeout end
        end
        if distanceFlat(getPlayerPosition(), targetPosition) <= (stopDistance or ARRIVAL_DISTANCE) then
            stopPathing()
            return CeMoveResult.Arrived
        end
        sleep(POLL_INTERVAL)
    end
    stopPathing()
    return CeMoveResult.Timeout
end

local function travelToFate(fate)
    local route = chooseFateRoute(fate)
    logf("Traveling to FATE '%s' via %s (%s).", fate.name, route.kind, route.reason)

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

    if getFateSnapshot(fate.id) == nil then
        logf("FATE %s vanished before travel.", fate.name)
        return false, "FATE ended before travel"
    end

    if not ensureMounted() then return false, "failed to mount" end

    local stopDist = math.min(fate.radius, 15)
    local speed = metadata.mountedTravelSpeed or 14.13
    local estimatedTime = distanceFlat(getPlayerPosition(), fate.location) / speed
    local timeout = math.max(CE_ATTEMPT_TIMEOUT, estimatedTime * 1.5 + 10)
    local result = fateMoveToPosition(fate.location, stopDist, timeout, fate.id)
    if result == CeMoveResult.CeAvailable then
        return false, "ce_available"
    end
    if result == CeMoveResult.BattleAbort then
        logf("FATE %s ended while traveling.", fate.name)
        return false, "FATE ended during travel"
    end
    if result ~= CeMoveResult.Arrived then
        return false, "failed to reach FATE position"
    end
    return true, nil
end

local function applyBossModForFate()
    if applyBossModPreset(AUTOROTATION_PRESET_NAME) then
        log("Autorotation enabled for FATE.")
        return true
    end
    log("Autorotation preset activation failed for FATE; continuing without it.")
    return false
end

local function monitorFate(fate)
    local autorotationActive = false
    lastCeCheckAt = os.clock()
    logf("Monitoring FATE '%s' (id=%d).", fate.name, fate.id)

    while true do
        if not isFateActive(fate.id) then
            logf("FATE %s no longer in active list; ending monitor.", fate.name)
            break
        end

        local snapshot = getFateSnapshot(fate.id)
        if snapshot == nil then
            logf("FATE %s vanished; ending monitor.", fate.name)
            break
        end

        if isInCombat() or snapshot.inFate then
            if not autorotationActive then
                autorotationActive = applyBossModForFate()
            end
        elseif autorotationActive then
            logf("Combat ended for FATE %s; clearing autorotation.", fate.name)
            clearBossModPreset()
            autorotationActive = false
        end

        if (os.clock() - lastFateMonitorLogAt) >= IDLE_LOG_INTERVAL then
            logf("FATE monitor: id=%d active=%s inFate=%s inCombat=%s progress=%.1f", fate.id, tostring(isFateActive(fate.id)), tostring(snapshot.inFate), tostring(isInCombat()), snapshot.progress or 0)
            lastFateMonitorLogAt = os.clock()
        end
        if PRIORITIZE_CE and ENABLE_CE_FARMING and (os.clock() - lastCeCheckAt) >= CE_CHECK_INTERVAL then
            lastCeCheckAt = os.clock()
            if isCeAvailable() then
                logf("CE available while monitoring FATE %s; ending monitor.", fate.name)
                return false, "ce_available"
            end
        end

        if isDead() then
            logf("Player died during FATE %s.", fate.name)
            handleDeathState()
            autorotationActive = false
        end

        sleep(POLL_INTERVAL)
    end

    logf("Final combat clear for FATE %s. Clearing autorotation.", fate.name)
    clearBossModPreset()
    return true, nil
end

local function returnAfterFate(fate)
    waitForCombatToSettle()

    if not USE_RETURN_AFTER then
        logf("FATE %s complete, return disabled; staying in place.", fate.name)
        return true
    end

    local ok, err = useReturn()
    if not ok then
        logf("FATE %s complete, return failed: %s; staying in place.", fate.name, tostring(err))
        return true
    end

    local waitPoint = getBaseCampWaitPoint()
    if waitPoint ~= nil then
        moveToPosition(waitPoint, WAIT_POINT_FALLBACK_DISTANCE)
    end
    return true
end

--#endregion

local function main()
    math.randomseed(os.time())
    log("Starting Occult Crescent FATE & CE Farmer.")
    if not isVnavAvailable() then
        stopScriptWithError("vnavmesh IPC is unavailable")
    end
    if not isLifestreamAvailable() then
        stopScriptWithError("Lifestream IPC is unavailable")
    end
    ceNameToId = buildCeNameResolver()

    local ok, err = validateAutorotationPreset()
    if not ok then
        stopScriptWithError(err)
    end
    log("BossMod preset validation succeeded.")

    while not isInSouthHorn() do
        logf("Waiting for South Horn territoryTypeId=%d.", SOUTH_HORN_TERRITORY_ID)
        sleep(1.0)
    end

    logf("Entered South Horn at position %s.", formatVector3(getPlayerPosition()))

    applyBuffRotation()

    local baseOk, baseErr = ensureAtBaseCampWaitBand()
    if not baseOk then
        stopScriptWithError(baseErr)
    end

    while true do
        if isDead() and not handleDeathState() then
            stopScriptWithError("Failed to revive after death timeout")
        end

        -- CE farming
        if ENABLE_CE_FARMING then
            local snapshots = scanEvents()
            local target = selectTargetCe(snapshots)
            if target ~= nil then
                local travelOk, travelErr = travelToCe(target)
                if not travelOk then
                    logf("Travel to CE %s failed: %s. Resuming scan.", target.name, travelErr or "unknown error")
                else
                    monitorCe(target)

                    if stopAfterCurrentCe then
                        local returnOk, returnErr = returnToBaseAndWait()
                        if not returnOk then
                            stopScriptWithError(returnErr or "failed to return to base after fatal CE error")
                        end
                        stopScriptWithError("Stopping after CE because autorotation failed during Battle")
                    end

                    local fateAttempted = false
                    local cePreempted = false
                    if ENABLE_FATE_FARMING then
                        local fateTarget = selectTargetFate(scanFates())
                        if fateTarget then
                            fateAttempted = true
                            local fateOk, fateErr = travelToFate(fateTarget)
                            if fateOk then
                                local monitorOk, monitorErr = monitorFate(fateTarget)
                                if monitorErr == "ce_available" then
                                    cePreempted = true
                                end
                            elseif fateErr == "ce_available" then
                                cePreempted = true
                            else
                                logf("Post-CE FATE travel failed: %s.", tostring(fateErr))
                            end
                            if not cePreempted then
                                returnAfterFate(fateTarget)
                            end
                        end
                    end

                    if cePreempted then
                        log("CE available after CE; abandoning FATE.")
                        sleep(POLL_INTERVAL)
                        goto continue_loop
                    end

                    if not fateAttempted then
                        local returnOk, returnErr = returnToBaseAndWait()
                        if not returnOk then
                            stopScriptWithError(returnErr or "failed to return to base")
                        end
                    end
                    applyBuffRotation()
                end
                sleep(POLL_INTERVAL)
                goto continue_loop
            end
        end

        -- FATE farming (no CE found or CE disabled)
        if ENABLE_FATE_FARMING then
            local fateTarget = selectTargetFate(scanFates())
            if fateTarget then
                local ok, err = travelToFate(fateTarget)
                local cePreempted = false
                if ok then
                    local monitorOk, monitorErr = monitorFate(fateTarget)
                    if monitorErr == "ce_available" then
                        cePreempted = true
                    end
                elseif err == "ce_available" then
                    cePreempted = true
                else
                    logf("Travel to FATE failed: %s.", tostring(err))
                end

                if cePreempted then
                    logf("CE available; abandoning FATE %s.", fateTarget.name)
                    sleep(POLL_INTERVAL)
                    goto continue_loop
                end

                returnAfterFate(fateTarget)
                applyBuffRotation()
                sleep(POLL_INTERVAL)
                goto continue_loop
            end
        end

        -- Idle
        if (os.clock() - lastScanSummaryAt) >= IDLE_LOG_INTERVAL then
            logf("Idle (mode=%s CE=%s FATE=%s).", FARMING_MODE, tostring(ENABLE_CE_FARMING), tostring(ENABLE_FATE_FARMING))
            lastScanSummaryAt = os.clock()
        end
        if (os.clock() - lastIdleLogAt) >= IDLE_LOG_INTERVAL then
            log("Idle.")
            lastIdleLogAt = os.clock()
        end
        sleep(POLL_INTERVAL)
        ::continue_loop::
    end
end

main()
