--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.0.4.1
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
            interactDistanceMax = 4.25,
        },
        Stonemarsh = {
            name = "Stonemarsh",
            placeNameId = 4942,
            baseId = 2014744,
            position = Vector3(-384.11542, 99.19885, 281.42212),
            destination = Vector3(-384.38, 97.44333, 276.6886),
            interactDistanceMin = 3.15,
            interactDistanceMax = 4.25,
        },
        CrystallizedCaverns = {
            name = "CrystallizedCaverns",
            placeNameId = 4929,
            baseId = 2014666,
            position = Vector3(-358.14453, 101.97595, -120.95831),
            destination = Vector3(-353.8978, 99.99078, -120.3132),
            interactDistanceMin = 3.15,
            interactDistanceMax = 4.25,
        },
        TheWanderersHaven = {
            name = "TheWanderersHaven",
            placeNameId = 4928,
            baseId = 2014665,
            position = Vector3(-173.02203, 8.194031, -611.1391),
            destination = Vector3(-169.27321, 6.5, -609.5403),
            interactDistanceMin = 3.15,
            interactDistanceMax = 4.25,
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
local USE_RETURN = Config.Get("Use Return") == true
local PRIORITIZE_CE = Config.Get("Prioritize CE") ~= false
local BASE_DIRECT_THRESHOLD = 120
local CE_WAIT_RING_MIN = 7
local CE_RADIUS_SAFETY_MARGIN = 2.0
local CE_WAIT_POINT_STOP_DISTANCE = 0.75
local AUTOROTATION_PRESET_NAME = tostring(Config.Get("Autorotation Preset Name") or "")

local RETURN_PENALTY = 7.0
local AETHERNET_TRANSITION_PENALTY = 3.0
local SOUTH_HORN_TERRITORY_ID = 1252
local GENERAL_ACTION_RETURN = 8
local GENERAL_ACTION_MOUNT = 24
local ARRIVAL_DISTANCE = 2.5
local TRANSITION_STABLE_SECONDS = 0.75
local TRANSITION_TIMEOUT = 10.0
local AETHERNET_TIMEOUT = 6.0
local MOUNT_TIMEOUT = 8.0
local MOVE_TIMEOUT_PADDING = 15.0
local WAIT_POINT_RETRIES = 6
local AETHERNET_APPROACH_RETRIES = 5
local AETHERNET_APPROACH_STOP_DISTANCE = 0.5
local AETHERNET_INNER_EDGE_BIAS = 0.1
local DESTINATION_CONFIRM_DISTANCE = 30.0
local POST_CE_COMBAT_SETTLE_SECONDS = 2.0
local RAISE_TIMEOUT = 300.0
local CE_ATTEMPT_TIMEOUT = 30.0
local IDLE_LOG_INTERVAL = 10.0
local BUFF_SETTLE_SECONDS = 1.0
local BUFF_TIMEOUT = 3.0
local BUFF_FRESH_DURATION = 600.0
local BUFF_VERIFY_RETRIES = 3
local DISMOUNT_TIMEOUT = 4.0
local DISMOUNT_RETRIES = 2
local CE_CHECK_INTERVAL = 2.5

local REQUIRED_BUFF_STATUS_IDS = { 4233, 4239, 4244, 4799 }

local BUFF_ACTIONS = {
    { jobId = 0,  name = "Freelancer", actionId = 46606, minLevel = 15, buffName = "Inquiring Mind",      appliesAll = true,  checkStatusIds = REQUIRED_BUFF_STATUS_IDS },
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

-- BossMod ownership state. The script only clears a runtime preset while it
-- still owns the exact preset it activated.
local initialBossModPreset = nil
local bossModOwned = false
local bossModOwnershipPreset = nil

-- Buff rotation restoration state remains available to OnStop so the original
-- support job can be recovered after an interruption.
local pendingSupportJobRestore = nil

local ActivityResult = {
    Completed = "completed",
    CeAvailable = "ce_available",
    EndedDuringTravel = "ended_during_travel",
    TravelFailed = "travel_failed",
    DeathRecoveryFailed = "death_recovery_failed",
    AutorotationFailed = "autorotation_failed",
    CombatDidNotSettle = "combat_did_not_settle",
}
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
local recoverToBaseAndWait
local waitUntil

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

local function getVnavMovementState()
    local running = false
    local pathfinding = false

    if IPC and IPC.vnavmesh then
        if IPC.vnavmesh.IsRunning then
            running = safeCall(function()
                return IPC.vnavmesh.IsRunning()
            end) == true
        end
        if IPC.vnavmesh.PathfindInProgress then
            pathfinding = safeCall(function()
                return IPC.vnavmesh.PathfindInProgress()
            end) == true
        end
    end

    return running, pathfinding
end

local function issueVnavStop()
    if IPC and IPC.vnavmesh and IPC.vnavmesh.Stop then
        local ok = pcall(IPC.vnavmesh.Stop)
        if ok then
            return true
        end
        log("IPC.vnavmesh.Stop() failed; falling back to /vnav stop.")
    end

    yield("/vnav stop")
    return true
end

local function stopPathing(timeoutSec)
    log("Stopping vnav pathing through IPC.")
    local deadline = os.clock() + (timeoutSec or 3.0)

    repeat
        issueVnavStop()
        sleep(0.10)

        local running, pathfinding = getVnavMovementState()
        if not running and not pathfinding then
            -- Require a brief stable stop so Return is not attempted during
            -- the same frame that vnav releases movement.
            sleep(0.20)
            running, pathfinding = getVnavMovementState()
            if not running and not pathfinding then
                log("vnav pathing stopped.")
                return true
            end
        end
    until os.clock() >= deadline

    local running, pathfinding = getVnavMovementState()
    logf(
        "Timed out waiting for vnav to stop (running=%s pathfinding=%s).",
        tostring(running),
        tostring(pathfinding)
    )
    return false
end

waitUntil = function(predicate, timeoutSec, stableSec)
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
    if not isBossModAvailable() then
        return ""
    end
    local active = safeCall(function()
        return IPC.BossMod.GetActive()
    end)
    return active and tostring(active) or ""
end

local function clearBossModPresetRaw()
    if not isBossModAvailable() then
        log("BossMod IPC unavailable while clearing preset.")
        return false
    end

    log("Clearing BossMod preset through raw IPC operation.")
    local ok, err = pcall(IPC.BossMod.ClearActive)
    if not ok then
        logf("BossMod ClearActive failed: %s", tostring(err))
        return false
    end

    local cleared = waitUntil(function()
        return getBossModActive() == ""
    end, 2.5, 0.25)
    logf("BossMod raw clear result=%s active=%q.", tostring(cleared), getBossModActive())
    return cleared
end

local function setBossModPresetRaw(preset)
    if not isBossModAvailable() then
        log("BossMod IPC unavailable while applying preset.")
        return false
    end

    preset = tostring(preset or "")
    if preset == "" then
        log("Refusing to apply a blank BossMod preset.")
        return false
    end

    logf("Applying BossMod preset %q through raw IPC operation.", preset)
    local ok, err = pcall(function()
        IPC.BossMod.SetActive(preset)
    end)
    if not ok then
        logf("BossMod SetActive(%q) failed: %s", preset, tostring(err))
        return false
    end

    local applied = waitUntil(function()
        return getBossModActive() == preset
    end, 2.5, 0.25)
    logf("BossMod raw apply result=%s active=%q.", tostring(applied), getBossModActive())
    return applied
end

local function restoreBossModPresetRaw(preset, context)
    preset = tostring(preset or "")
    context = tostring(context or "BossMod restoration")

    if preset == "" then
        if getBossModActive() == "" then
            logf("%s: BossMod is already clear.", context)
            return true
        end
        local cleared = clearBossModPresetRaw()
        if not cleared then
            logf("%s: failed to restore blank BossMod state.", context)
        end
        return cleared
    end

    if getBossModActive() == preset then
        logf("%s: preset %q is already active.", context, preset)
        return true
    end

    local restored = setBossModPresetRaw(preset)
    if not restored then
        logf("%s: failed to restore preset %q.", context, preset)
    end
    return restored
end

local function acquireBossModPreset(preset)
    preset = tostring(preset or "")
    if preset == "" then
        log("Cannot acquire a blank BossMod preset.")
        bossModOwned = false
        bossModOwnershipPreset = nil
        return false
    end

    local activeBefore = getBossModActive()

    if bossModOwned and bossModOwnershipPreset == preset and activeBefore == preset then
        logf("BossMod preset %q is already owned by this script.", preset)
        return true
    end

    if bossModOwned and activeBefore ~= bossModOwnershipPreset then
        logf(
            "BossMod ownership lost: expected=%q active=%q. Refusing to overwrite external preset.",
            tostring(bossModOwnershipPreset),
            tostring(activeBefore)
        )
        bossModOwned = false
        bossModOwnershipPreset = nil
        return false
    end

    if not bossModOwned and activeBefore == preset then
        logf("BossMod preset %q is already active externally; using it without claiming ownership.", preset)
        bossModOwnershipPreset = nil
        return true
    end

    if not bossModOwned and activeBefore ~= nil and activeBefore ~= "" and activeBefore ~= preset then
        logf(
            "BossMod preset %q is already active. Refusing to replace it with %q.",
            tostring(activeBefore),
            tostring(preset)
        )
        bossModOwnershipPreset = nil
        return false
    end

    bossModOwned = false
    bossModOwnershipPreset = nil

    if not setBossModPresetRaw(preset) then
        return false
    end

    bossModOwned = true
    bossModOwnershipPreset = preset
    logf("BossMod ownership acquired for preset %q.", preset)
    return true
end

local function releaseOwnedBossModPreset()
    if not bossModOwned or bossModOwnershipPreset == nil then
        return true
    end

    local expected = bossModOwnershipPreset
    local active = getBossModActive()
    if active ~= expected then
        logf(
            "BossMod ownership lost externally: expected=%q active=%q. Leaving active preset unchanged.",
            tostring(expected),
            tostring(active)
        )
        bossModOwned = false
        bossModOwnershipPreset = nil
        return true
    end

    if not clearBossModPresetRaw() then
        logf("Failed to release script-owned BossMod preset %q.", expected)
        return false
    end

    bossModOwned = false
    bossModOwnershipPreset = nil
    logf("Released script-owned BossMod preset %q.", expected)
    return true
end

local function restoreInitialBossModPreset()
    if initialBossModPreset == nil then
        log("Initial BossMod state was not captured; skipping restoration.")
        return true
    end
    return restoreBossModPresetRaw(initialBossModPreset, "Initial BossMod restoration")
end

local function validateAutorotationPreset()
    local preset = tostring(AUTOROTATION_PRESET_NAME or "")
    if preset == "" then
        return false, "Autorotation Preset Name config is blank"
    end
    if not isBossModAvailable() then
        return false, "BossMod IPC is unavailable"
    end

    local previousPreset = getBossModActive()
    initialBossModPreset = previousPreset
    bossModOwned = false
    bossModOwnershipPreset = nil
    logf("Captured initial BossMod preset %q before validation.", previousPreset)

    local activated = setBossModPresetRaw(preset)
    local restored = restoreBossModPresetRaw(previousPreset, "BossMod validation cleanup")

    bossModOwned = false
    bossModOwnershipPreset = nil

    if not restored then
        return false, string.format(
            "Failed to restore BossMod preset '%s' after validating '%s'",
            previousPreset,
            preset
        )
    end
    if not activated then
        return false, string.format("Failed to activate BossMod preset '%s'", preset)
    end

    logf("Autorotation preset %q validated and prior preset %q restored successfully.", preset, previousPreset)
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
    local targetDistance = minDistance + AETHERNET_INNER_EDGE_BIAS
    local nx, nz = normalizeFlat(aethernet.position, playerPosition)
    if nx == nil then
        logf("Could not derive directional approach for %s; falling back to random band point.", tostring(aethernet.name))
        return randomPointInRing(aethernet.position, targetDistance, math.min(targetDistance + 0.15, tonumber(aethernet.interactDistanceMax or metadata.aethernetInteractDistance) or 4.5))
    end
    local point = Vector3(
        aethernet.position.X + nx * targetDistance,
        aethernet.position.Y,
        aethernet.position.Z + nz * targetDistance
    )
    logf("Directional approach point for %s is %s.", tostring(aethernet.name), formatVector3(point))
    return point
end

local function getRandomAethernetBandPoint(aethernet)
    local minDistance = tonumber(aethernet.interactDistanceMin or metadata.aethernetInteractDistanceMin) or 3.15
    local maxDistance = tonumber(aethernet.interactDistanceMax or metadata.aethernetInteractDistance) or 4.5
    local innerMin = math.min(minDistance + AETHERNET_INNER_EDGE_BIAS, maxDistance)
    local innerMax = math.min(innerMin + 0.25, maxDistance)
    return randomPointInRing(aethernet.position, innerMin, innerMax)
end

local function getBaseCampWaitPoint()
    local baseCamp = getAethernetByName("BaseCamp")
    if baseCamp == nil then
        return nil
    end

    local minDistance = tonumber(baseCamp.interactDistanceMin or metadata.aethernetInteractDistanceMin) or 3.15
    local maxDistance = tonumber(baseCamp.interactDistanceMax or metadata.aethernetInteractDistance) or 4.5
    local innerMin = math.min(minDistance + AETHERNET_INNER_EDGE_BIAS, maxDistance)
    local innerMax = math.min(innerMin + 0.25, maxDistance)
    local point = randomPointInRing(baseCamp.position, innerMin, innerMax)
    logf("Generated Base Camp wait point %s inside %.2f..%.2f interaction band.", formatVector3(point), innerMin, innerMax)
    return point
end

local function ensureAtBaseCampWaitBand()
    local baseCamp = getAethernetByName("BaseCamp")
    if baseCamp == nil then
        return false, "BaseCamp metadata missing"
    end

    local inBand, distance, minDistance, maxDistance = isWithinAethernetBand(getPlayerPosition(), baseCamp)
    if inBand then
        logf("Already inside Base Camp interaction band at %.2f yalms.", distance)
        return true, nil
    end

    logf(
        "Player is outside Base Camp interaction band: distance=%.2f required=%.2f..%.2f. Starting recovery.",
        distance,
        minDistance,
        maxDistance
    )
    return recoverToBaseAndWait()
end

local function waitForReturnCompletion(startPosition, timeoutSec)
    local baseCamp = getAethernetByName("BaseCamp")
    if baseCamp == nil or baseCamp.destination == nil then
        log("Return completion cannot be verified because Base Camp destination metadata is missing.")
        return false
    end

    local startedAway = distanceFlat(startPosition, baseCamp.destination) > DESTINATION_CONFIRM_DISTANCE
    local deadline = os.clock() + (timeoutSec or TRANSITION_TIMEOUT)
    local sawTransition = false
    local stableStart = nil

    while os.clock() < deadline do
        local casting = getCondition(CharacterCondition.casting)
        local betweenAreas = getCondition(CharacterCondition.betweenAreas)
        local busy = isLifestreamBusy()
        if casting or betweenAreas or busy then
            sawTransition = true
            stableStart = nil
        end

        local distance = distanceFlat(getPlayerPosition(), baseCamp.destination)
        local complete = not casting
            and not betweenAreas
            and not busy
            and isPlayerAvailable()
            and distance <= DESTINATION_CONFIRM_DISTANCE
            and (sawTransition or startedAway)

        if complete then
            stableStart = stableStart or os.clock()
            if (os.clock() - stableStart) >= TRANSITION_STABLE_SECONDS then
                logf("Return completed near Base Camp destination at %.2f yalms.", distance)
                return true
            end
        else
            stableStart = nil
        end

        sleep(POLL_INTERVAL)
    end

    logf(
        "Return transition timed out. sawTransition=%s finalDistance=%.2f conditions=%s playerPos=%s",
        tostring(sawTransition),
        distanceFlat(getPlayerPosition(), baseCamp.destination),
        describeConditionState(),
        formatVector3(getPlayerPosition())
    )
    return false
end

local function waitForAethernetCompletion(aethernet, startPosition, timeoutSec)
    if aethernet == nil or aethernet.destination == nil then
        return false
    end

    local startedAway = distanceFlat(startPosition, aethernet.destination) > DESTINATION_CONFIRM_DISTANCE
    local deadline = os.clock() + (timeoutSec or AETHERNET_TIMEOUT)
    local sawTransition = false
    local stableStart = nil

    while os.clock() < deadline do
        local casting = getCondition(CharacterCondition.casting)
        local occupied = getCondition(CharacterCondition.occupiedInQuestEvent)
        local betweenAreas = getCondition(CharacterCondition.betweenAreas)
        local busy = isLifestreamBusy()
        if casting or occupied or betweenAreas or busy then
            sawTransition = true
            stableStart = nil
        end

        local distance = distanceFlat(getPlayerPosition(), aethernet.destination)
        local complete = not casting
            and not betweenAreas
            and not busy
            and isPlayerAvailable()
            and distance <= DESTINATION_CONFIRM_DISTANCE
            and (sawTransition or startedAway)

        if complete then
            stableStart = stableStart or os.clock()
            if (os.clock() - stableStart) >= TRANSITION_STABLE_SECONDS then
                logf("Aethernet transition to %s completed at %.2f yalms from destination.", tostring(aethernet.name), distance)
                return true
            end
        else
            stableStart = nil
        end

        sleep(POLL_INTERVAL)
    end

    logf(
        "Aethernet transition to %s timed out. sawTransition=%s finalDistance=%.2f conditions=%s playerPos=%s",
        tostring(aethernet.name),
        tostring(sawTransition),
        distanceFlat(getPlayerPosition(), aethernet.destination),
        describeConditionState(),
        formatVector3(getPlayerPosition())
    )
    return false
end

local function waitForCombatToSettle(timeoutSec)
    logf("Waiting for combat to remain clear for %.2fs.", POST_CE_COMBAT_SETTLE_SECONDS)
    local settled = waitUntil(function()
        return not isInCombat()
    end, timeoutSec or 15.0, POST_CE_COMBAT_SETTLE_SECONDS)
    logf("Combat settle result=%s inCombat=%s.", tostring(settled), tostring(isInCombat()))
    return settled
end

local function prepareForTravel(targetValidator, label)
    label = tostring(label or "target")

    if not stopPathing(3.0) then
        return ActivityResult.TravelFailed, "vnav did not stop before travel"
    end

    if isDead() and not handleDeathState() then
        return ActivityResult.DeathRecoveryFailed, "death recovery failed before travel"
    end

    if not waitForCombatToSettle() then
        return ActivityResult.CombatDidNotSettle, "combat did not settle before travel"
    end

    if targetValidator ~= nil then
        local result, detail = targetValidator()
        if result ~= ActivityResult.Completed then
            logf("Travel preparation for %s stopped: result=%s detail=%s.", label, tostring(result), tostring(detail))
            return result, detail
        end
    end

    logf("Travel preparation for %s completed.", label)
    return ActivityResult.Completed, nil
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

local function validateCeForTravel(ceId)
    local snapshot = waitForSnapshotById(ceId)
    if snapshot == nil or snapshot.metadata == nil or snapshot.metadata.stagingPoint == nil then
        return ActivityResult.EndedDuringTravel, "CE is no longer available"
    end

    if not snapshot.isActive or snapshot.stateCode <= 0 then
        return ActivityResult.EndedDuringTravel, "CE is inactive"
    end

    if snapshot.stateCode >= 3 then
        local radius = tonumber(snapshot.metadata.engageRadius) or 20
        local distance = distanceFlat(getPlayerPosition(), snapshot.metadata.stagingPoint)
        if distance <= radius then
            logf("CE %s entered Battle, but player is already inside its radius at %.2f yalms.", snapshot.name, distance)
            return ActivityResult.Completed, nil
        end
        return ActivityResult.EndedDuringTravel, "CE entered Battle before arrival"
    end

    return ActivityResult.Completed, nil
end

local function shouldAbortForBattleState(snapshot)
    local shouldAbort = snapshot ~= nil and snapshot.stateCode >= 3 and distanceFlat(getPlayerPosition(), snapshot.metadata.stagingPoint) > (tonumber(snapshot.metadata.engageRadius) or 20)
    if shouldAbort then
        logf("Aborting CE %s because it reached Battle before arrival. playerDistance=%.2f radius=%.2f", snapshot.name, distanceFlat(getPlayerPosition(), snapshot.metadata.stagingPoint), tonumber(snapshot.metadata.engageRadius) or 20)
    end
    return shouldAbort
end

local CeMoveResult = {
    Arrived = 1,
    Timeout = 2,
    BattleAbort = 3,
    CeAvailable = 4,
    DeathRecoveryFailed = 5,
}

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
            if not handleDeathState() then
                log("Death recovery failed during CE travel.")
                return CeMoveResult.DeathRecoveryFailed
            end
            local afterDeath = waitForSnapshotById(ceId)
            if afterDeath == nil then
                log("CE vanished during death recovery.")
                return CeMoveResult.BattleAbort
            end
            if shouldAbortForBattleState(afterDeath) then
                log("CE aborted after revive: entered Battle.")
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
    if aethernet == nil then
        return false
    end

    local playerPosition = getPlayerPosition()
    local inBand, currentDistance = isWithinAethernetBand(playerPosition, aethernet)
    if inBand then
        logf("Already inside %s interaction band at %.2f yalms.", tostring(aethernet.name), currentDistance)
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

    for index, approachPoint in ipairs(attempts) do
        logf("Trying %s band approach %d/%d at %s.", tostring(aethernet.name), index, #attempts, formatVector3(approachPoint))
        if approachPoint ~= nil and moveToPosition(approachPoint, AETHERNET_APPROACH_STOP_DISTANCE) then
            local nowInBand, finalDistance, minDistance, maxDistance = isWithinAethernetBand(getPlayerPosition(), aethernet)
            if nowInBand then
                logf("Entered %s interaction band at %.2f yalms.", tostring(aethernet.name), finalDistance)
                return true
            end
            logf(
                "%s approach finished outside interaction band: distance=%.2f required=%.2f..%.2f.",
                tostring(aethernet.name),
                finalDistance,
                minDistance,
                maxDistance
            )
        end
    end

    logf("Failed to enter %s interaction band.", tostring(aethernet.name))
    return false
end

local function useOccultAethernet(preferredAethernet)
    if not isLifestreamAvailable() then
        return false, "Lifestream aethernet IPC is unavailable"
    end
    if preferredAethernet == nil then
        return false, "preferred aethernet is missing"
    end

    local startPosition = getPlayerPosition()
    if distanceFlat(startPosition, preferredAethernet.destination) <= DESTINATION_CONFIRM_DISTANCE then
        logf("Already near %s destination; skipping aethernet teleport.", tostring(preferredAethernet.name))
        return true, nil
    end

    local currentAethernet = nil
    for _, aethernet in pairs(metadata.aethernets or {}) do
        local inBand = isWithinAethernetBand(startPosition, aethernet)
        if inBand then
            currentAethernet = aethernet
            break
        end
    end

    if currentAethernet == nil then
        currentAethernet = getNearestConfiguredAethernet(startPosition)
        currentAethernet = currentAethernet or preferredAethernet
        if currentAethernet == nil or not moveIntoAethernetBand(currentAethernet) then
            return false, "failed to reach aethernet interaction band"
        end
    end

    if not stopPathing(3.0) then
        return false, "vnav did not stop before aethernet teleport"
    end

    startPosition = getPlayerPosition()
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

    if not waitForAethernetCompletion(preferredAethernet, startPosition, AETHERNET_TIMEOUT) then
        return false, "aethernet transition did not complete at the requested destination"
    end

    return true, nil
end

local function useReturn()
    if not USE_RETURN then
        return false, "Return is disabled by configuration"
    end
    if isDead() then
        log("Player is dead; cannot use Return.")
        return false, "player is dead"
    end
    if isInCombat() then
        log("Player is in combat; cannot use Return.")
        return false, "player in combat"
    end

    if not stopPathing(3.0) then
        return false, "vnav did not stop before Return"
    end

    local startPosition = getPlayerPosition()
    if not executeGeneralAction(GENERAL_ACTION_RETURN) then
        return false, "failed to trigger Return"
    end
    log("Return action triggered.")

    local promptDeadline = os.clock() + 3.0
    while os.clock() < promptDeadline do
        if isAddonReady("SelectYesno") then
            log("SelectYesno detected during Return; confirming.")
            yield("/callback SelectYesno true 0")
            break
        end
        if getCondition(CharacterCondition.casting) or getCondition(CharacterCondition.betweenAreas) then
            break
        end
        sleep(POLL_INTERVAL)
    end

    if not waitForReturnCompletion(startPosition, TRANSITION_TIMEOUT) then
        return false, "return transition did not complete at Base Camp"
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

    for _, ae in pairs(metadata.aethernets) do
        if isWithinAethernetBand(playerPosition, ae) and ae.name == preferredAethernet.name then
            logf("Player already at preferred aethernet %s; routing direct.", ae.name)
            return { kind = "direct", reason = "already_at_preferred_aethernet", preferred = preferredAethernet }
        end
    end

    local speed = tonumber(metadata.mountedTravelSpeed) or 14.13
    local directTime = distanceFlat(playerPosition, ceMetadata.stagingPoint) / speed
    local nearestAethernet = getNearestConfiguredAethernet(playerPosition)
    local nearestApproachDistance = aethernetApproachDistance(playerPosition, nearestAethernet)
    local shardTime = (nearestApproachDistance / speed)
        + AETHERNET_TRANSITION_PENALTY
        + (distanceFlat(preferredAethernet.destination, ceMetadata.stagingPoint) / speed)

    local returnTime = math.huge
    if USE_RETURN then
        returnTime = RETURN_PENALTY
            + ((preferredAethernet.name == "BaseCamp") and 0 or AETHERNET_TRANSITION_PENALTY)
            + (distanceFlat(preferredAethernet.destination, ceMetadata.stagingPoint) / speed)
    end

    local baseCamp = getAethernetByName("BaseCamp")
    local inBaseBand = baseCamp and isWithinAethernetBand(playerPosition, baseCamp)
    local nearBase = baseCamp and distanceFlat(playerPosition, baseCamp.position) <= BASE_DIRECT_THRESHOLD
    if preferredAethernet.name == "BaseCamp" and (inBaseBand or nearBase) then
        logf("Route metrics for %s: direct=%.2f shard=%.2f return=%s; using direct because player is close to base.", snapshot.name, directTime, shardTime, USE_RETURN and string.format("%.2f", returnTime) or "disabled")
        return { kind = "direct", reason = "already_close_to_base", preferred = preferredAethernet }
    end

    if not USE_RETURN then
        if directTime + MINIMUM_ROUTE_SAVINGS <= shardTime then
            logf("Route metrics for %s: direct=%.2f shard=%.2f return=disabled; choosing direct.", snapshot.name, directTime, shardTime)
            return { kind = "direct", reason = "faster_direct_return_disabled", preferred = preferredAethernet }
        end
        logf("Route metrics for %s: direct=%.2f shard=%.2f return=disabled; choosing aethernet.", snapshot.name, directTime, shardTime)
        return { kind = "aethernet", reason = "aethernet_route_return_disabled", preferred = preferredAethernet }
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
    local engageRadius = tonumber(ceMetadata.engageRadius) or 20
    local safeOuterRadius = math.max(0.5, engageRadius - CE_RADIUS_SAFETY_MARGIN)
    local minRadius = math.min(CE_WAIT_RING_MIN, safeOuterRadius)
    local point = randomPointInRing(ceMetadata.stagingPoint, minRadius, safeOuterRadius)
    logf(
        "Generated CE wait point %s around staging point %s using safe ring %.2f..%.2f inside engageRadius %.2f.",
        formatVector3(point),
        formatVector3(ceMetadata.stagingPoint),
        minRadius,
        safeOuterRadius,
        engageRadius
    )
    return point
end

local function ensureInsideCeRadius(snapshot)
    local engageRadius = tonumber(snapshot.metadata.engageRadius) or 20
    local distance = distanceFlat(getPlayerPosition(), snapshot.metadata.stagingPoint)
    if distance <= engageRadius then
        if (os.clock() - lastCeRadiusLogAt) >= IDLE_LOG_INTERVAL then
            logf("Player remains inside CE radius for %s at %.2f yalms.", snapshot.name, distance)
            lastCeRadiusLogAt = os.clock()
        end
        return true
    end

    logf("Player drifted outside CE radius for %s: %.2f > %.2f. Repositioning.", snapshot.name, distance, engageRadius)
    lastCeRadiusLogAt = os.clock()

    for attempt = 1, WAIT_POINT_RETRIES do
        local fallbackPoint = getCeWaitPoint(snapshot.metadata)
        if fallbackPoint ~= nil and moveToPosition(fallbackPoint, CE_WAIT_POINT_STOP_DISTANCE) then
            local finalDistance = distanceFlat(getPlayerPosition(), snapshot.metadata.stagingPoint)
            if finalDistance <= engageRadius then
                logf("Re-entered CE radius for %s at %.2f yalms on attempt %d.", snapshot.name, finalDistance, attempt)
                return true
            end
        end
    end

    local innerStopDistance = math.max(0.5, engageRadius - CE_RADIUS_SAFETY_MARGIN)
    if not moveToPosition(snapshot.metadata.stagingPoint, innerStopDistance) then
        return false
    end

    local finalDistance = distanceFlat(getPlayerPosition(), snapshot.metadata.stagingPoint)
    local inside = finalDistance <= engageRadius
    logf("CE radius fallback for %s finished at %.2f yalms; inside=%s.", snapshot.name, finalDistance, tostring(inside))
    return inside
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
    if distToBuff > 50 and USE_RETURN then
        logf("Buff zone is %.1f yalms away; attempting Return first.", distToBuff)
        local returnOk, returnErr = useReturn()
        if not returnOk then
            logf("Buff-zone Return failed: %s. Continuing with direct movement.", tostring(returnErr))
        end
    elseif distToBuff > 50 then
        logf("Buff zone is %.1f yalms away; Return is disabled, using direct movement.", distToBuff)
    end

    playerPosition = getPlayerPosition()
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

local function getOccultCrescentState()
    return safeCall(function()
        return InstancedContent.OccultCrescent.OccultCrescentState
    end)
end

local function restorePendingSupportJob(context)
    context = tostring(context or "support-job restoration")
    local targetJob = pendingSupportJobRestore
    if targetJob == nil then
        return true
    end

    local ocState = getOccultCrescentState()
    if ocState == nil then
        logf("%s: OccultCrescentState unavailable; pending original job %s remains unrestored.", context, tostring(targetJob))
        return false
    end

    if ocState.CurrentSupportJob == targetJob then
        logf("%s: original support job %d is already active.", context, targetJob)
        pendingSupportJobRestore = nil
        return true
    end

    logf("%s: restoring original support job %d.", context, targetJob)
    local ok, err = pcall(function()
        ocState:ChangeSupportJob(targetJob)
    end)
    if not ok then
        logf("%s: ChangeSupportJob(%d) failed: %s", context, targetJob, tostring(err))
        return false
    end

    local restored = waitUntil(function()
        return ocState.CurrentSupportJob == targetJob
    end, BUFF_TIMEOUT, BUFF_SETTLE_SECONDS)

    if not restored then
        logf(
            "%s: original job restoration timed out; currentJob=%s expectedJob=%d.",
            context,
            tostring(ocState.CurrentSupportJob),
            targetJob
        )
        return false
    end

    logf("%s: restored original support job %d.", context, targetJob)
    pendingSupportJobRestore = nil
    return true
end

local function auditRequiredBuffs()
    local missing = {}

    for _, statusId in ipairs(REQUIRED_BUFF_STATUS_IDS) do
        if getStatusRemaining(statusId) < BUFF_FRESH_DURATION then
            table.insert(missing, statusId)
        end
    end

    return #missing == 0, missing
end

local function ensureDismounted()
    if not isMounted() and not isMounting() then
        return true
    end

    for attempt = 1, DISMOUNT_RETRIES do
        logf("Buff rotation: dismount attempt %d/%d.", attempt, DISMOUNT_RETRIES)
        if not executeGeneralAction(23) then
            log("Buff rotation: dismount action could not be executed.")
        end

        local dismounted = waitUntil(function()
            return not isMounted() and not isMounting()
        end, DISMOUNT_TIMEOUT, 0.25)

        if dismounted then
            log("Buff rotation: dismounted state confirmed.")
            return true
        end
    end

    log("Buff rotation: failed to confirm dismounted state.")
    return false
end

local function applyBuffRotation()
    if not ENABLE_BUFF_ROTATION then
        return true, "buff rotation disabled", false
    end
    if isDead() or isInCombat() then
        log("Buff rotation skipped: player dead or in combat.")
        return false, "player dead or in combat", false
    end

    local ocState = getOccultCrescentState()
    if ocState == nil then
        log("Buff rotation skipped: OccultCrescentState unavailable.")
        return false, "OccultCrescentState unavailable", false
    end

    local levels = ocState.SupportJobLevels
    if levels == nil or levels.Length < 16 then
        logf("Buff rotation skipped: SupportJobLevels unavailable or incomplete (%s).", tostring(levels and levels.Length or "nil"))
        return false, "SupportJobLevels unavailable or incomplete", false
    end

    local originalJob = ocState.CurrentSupportJob
    if originalJob == nil then
        log("Buff rotation skipped: could not read current job.")
        return false, "current support job unavailable", false
    end

    logf("Starting buff rotation for originalJob=%d.", originalJob)

    local buffsFresh, missingBeforeRotation = auditRequiredBuffs()
    if buffsFresh then
        log("Buff rotation: all buffs fresh, skipping.")
        return true, "all buffs fresh", false
    end

    logf(
        "Buff rotation: required statuses need refresh: %s.",
        table.concat(missingBeforeRotation, ", ")
    )

    if not moveIntoBuffZone() then
        log("Buff rotation: failed to reach buff zone; aborting before job changes.")
        return false, "buff zone unreachable", false
    end

    if not ensureDismounted() then
        log("Buff rotation: dismount failed; aborting before job changes.")
        return false, "dismount failed", false
    end

    pendingSupportJobRestore = originalJob

    local rotationSucceeded = true
    local failureReason = nil
    local abortRotation = false

    sleep(BUFF_SETTLE_SECONDS)

    for _, entry in ipairs(BUFF_ACTIONS) do
        if abortRotation then break end

        local processEntry = true
        local jobLevel = levels[entry.jobId]
        if jobLevel == nil or jobLevel < entry.minLevel then
            logf("Buff rotation: skipping %s (jobId=%d level=%d < %d).", entry.name, entry.jobId, jobLevel or 0, entry.minLevel)
            processEntry = false
        end

        if processEntry and entry.appliesAll then
            local allFresh = true
            for _, sid in ipairs(entry.checkStatusIds) do
                if getStatusRemaining(sid) < BUFF_FRESH_DURATION then
                    allFresh = false
                    break
                end
            end
            if allFresh then
                log("Buff rotation: all Freelancer-covered statuses are fresh, skipping remaining buffs.")
                break
            end
        elseif processEntry and entry.statusId then
            local remaining = getStatusRemaining(entry.statusId)
            if remaining >= BUFF_FRESH_DURATION then
                logf("Buff rotation: %s still has %.0fs remaining, skipping.", entry.name, remaining)
                processEntry = false
            end
        end

        if processEntry then
            if not isWithinBuffZone(getPlayerPosition()) then
                logf("Buff rotation: outside buff zone before %s; repositioning.", entry.buffName)
                if not moveIntoBuffZone() then
                    rotationSucceeded = false
                    failureReason = "left buff zone and could not re-enter"
                    abortRotation = true
                    break
                end
            end

            if ocState.CurrentSupportJob ~= entry.jobId then
                logf("Buff rotation: switching to %s (jobId=%d).", entry.name, entry.jobId)
                local ok, err = pcall(function()
                    ocState:ChangeSupportJob(entry.jobId)
                end)
                if not ok then
                    logf("Buff rotation: ChangeSupportJob(%d) failed: %s", entry.jobId, tostring(err))
                    rotationSucceeded = false
                    failureReason = string.format("job switch to %s failed", entry.name)
                    abortRotation = true
                    break
                end

                local changed = waitUntil(function()
                    return ocState.CurrentSupportJob == entry.jobId
                end, BUFF_TIMEOUT, BUFF_SETTLE_SECONDS)
                if not changed then
                    logf(
                        "Buff rotation: failed to switch to %s (jobId=%d); currentJob=%s.",
                        entry.name,
                        entry.jobId,
                        tostring(ocState.CurrentSupportJob)
                    )
                    rotationSucceeded = false
                    failureReason = string.format("job switch to %s timed out", entry.name)
                    abortRotation = true
                    break
                end
            else
                logf("Buff rotation: already on %s (jobId=%d), skipping switch.", entry.name, entry.jobId)
            end

            local applied = false
            for attempt = 1, BUFF_VERIFY_RETRIES do
                if not isWithinBuffZone(getPlayerPosition()) then
                    logf("Buff rotation: outside buff zone before casting %s; repositioning.", entry.buffName)
                    if not moveIntoBuffZone() then
                        rotationSucceeded = false
                        failureReason = "buff-zone repositioning failed"
                        abortRotation = true
                        break
                    end
                end

                sleep(BUFF_SETTLE_SECONDS)
                logf("Buff rotation: casting %s (actionId=%d) attempt %d/%d.", entry.buffName, entry.actionId, attempt, BUFF_VERIFY_RETRIES)
                local ok, err = pcall(function()
                    Actions.ExecuteAction(entry.actionId)
                end)
                if not ok then
                    logf("Buff rotation: ExecuteAction(%d) failed: %s", entry.actionId, tostring(err))
                else
                    sleep(BUFF_SETTLE_SECONDS)

                    if entry.appliesAll then
                        applied = true
                        for _, sid in ipairs(entry.checkStatusIds) do
                            local remain = getStatusRemaining(sid)
                            if remain >= BUFF_FRESH_DURATION then
                                logf("Buff rotation: %s status %d refreshed (%.0fs remaining).", entry.buffName, sid, remain)
                            else
                                logf(
                                    "Buff rotation: %s status %d not refreshed (%.0fs remaining; need %.0fs).",
                                    entry.buffName,
                                    sid,
                                    remain,
                                    BUFF_FRESH_DURATION
                                )
                                applied = false
                            end
                        end
                    elseif entry.statusId then
                        local remain = getStatusRemaining(entry.statusId)
                        logf("Buff rotation: %s status %d remain=%.0fs.", entry.buffName, entry.statusId, remain)
                        applied = remain >= BUFF_FRESH_DURATION
                    else
                        applied = true
                    end
                end

                if applied or abortRotation then
                    break
                end

                if attempt < BUFF_VERIFY_RETRIES then
                    logf("Buff rotation: %s not verified, repositioning before retry.", entry.buffName)
                    if not moveIntoBuffZone() then
                        log("Buff rotation: repositioning failed; aborting rotation.")
                        rotationSucceeded = false
                        failureReason = "buff-zone repositioning failed"
                        abortRotation = true
                        break
                    end
                end
            end

            if abortRotation then break end

            if not applied then
                logf("Buff rotation: %s failed to apply after %d attempts.", entry.buffName, BUFF_VERIFY_RETRIES)
                if entry.appliesAll then
                    log("Buff rotation: Freelancer Inquiring Mind failed; continuing with individual buffs.")
                else
                    rotationSucceeded = false
                    failureReason = failureReason or string.format("%s verification failed", entry.buffName)
                end
            end

            if entry.appliesAll then
                if applied then
                    log("Buff rotation: Freelancer Inquiring Mind covers all buffs, done.")
                    break
                end
            end

            sleep(BUFF_SETTLE_SECONDS)
        end
    end

    if not abortRotation then
        local buffsComplete, missingStatuses = auditRequiredBuffs()
        if buffsComplete then
            rotationSucceeded = true
            failureReason = nil
            log("Buff rotation audit: all required buffs are fresh.")
        else
            rotationSucceeded = false
            failureReason = string.format(
                "required buffs missing after rotation: %s",
                table.concat(missingStatuses, ", ")
            )
            logf("Buff rotation audit failed: %s.", failureReason)
        end
    end

    local restored = restorePendingSupportJob("Buff rotation cleanup")
    if not restored then
        log("Buff rotation incomplete: failed to restore the original support job.")
        return false, "original support job restoration failed", true
    end

    if not rotationSucceeded then
        logf("Buff rotation ended with failure: %s.", tostring(failureReason))
        return false, failureReason or "one or more buffs failed", false
    end

    log("Buff rotation complete; original support job restored.")
    return true, "completed", false
end

recoverToBaseAndWait = function()
    log("Starting Base Camp recovery flow.")

    if not stopPathing(3.0) then
        return false, "vnav did not stop before Base Camp recovery"
    end

    if isDead() and not handleDeathState() then
        return false, "death recovery failed before Base Camp recovery"
    end

    if not waitForCombatToSettle() then
        return false, "combat did not clear before Base Camp recovery"
    end

    local baseCamp = getAethernetByName("BaseCamp")
    if baseCamp == nil then
        return false, "BaseCamp metadata missing"
    end

    local inBand = isWithinAethernetBand(getPlayerPosition(), baseCamp)
    if inBand then
        log("Already inside Base Camp interaction band.")
        return true, nil
    end

    local distanceToBase = distanceFlat(getPlayerPosition(), baseCamp.position)
    if distanceToBase <= BASE_DIRECT_THRESHOLD then
        logf("Base Camp is %.2f yalms away; moving directly into its interaction band.", distanceToBase)
    elseif USE_RETURN then
        local ok, err = useReturn()
        if not ok then
            logf("Return failed during Base Camp recovery: %s. Falling back to direct movement.", tostring(err))
        end
    else
        log("Return is disabled; recovering to Base Camp by direct movement.")
    end

    distanceToBase = distanceFlat(getPlayerPosition(), baseCamp.position)
    if distanceToBase > BASE_DIRECT_THRESHOLD and not isMounted() then
        if not ensureMounted() then
            log("Could not mount for Base Camp recovery; continuing unmounted.")
        end
    end

    if not moveIntoAethernetBand(baseCamp) then
        return false, "failed to move into verified Base Camp interaction band"
    end

    local verified = isWithinAethernetBand(getPlayerPosition(), baseCamp)
    if not verified then
        return false, "Base Camp recovery ended outside interaction band"
    end

    return true, nil
end

local function stopScriptWithError(message)
    logf("Fatal: %s", tostring(message))
    error(message)
end

local function runBuffRotation(context)
    local success, detail, restorationCritical = applyBuffRotation()
    if success then
        return true
    end

    logf("Buff rotation failed during %s: %s.", tostring(context or "unknown context"), tostring(detail))
    if restorationCritical then
        stopScriptWithError(detail or "original support job restoration failed")
    end
    return false
end

local function cleanupBossModOnStop()
    if not isBossModAvailable() then
        log("OnStop: BossMod IPC unavailable; cannot restore BossMod state.")
        return false
    end

    local active = getBossModActive()
    if bossModOwned and active == bossModOwnershipPreset then
        if not releaseOwnedBossModPreset() then
            return false
        end
        return restoreInitialBossModPreset()
    end

    if bossModOwned then
        logf(
            "OnStop: BossMod ownership lost externally: expected=%q active=%q. Leaving external preset unchanged.",
            tostring(bossModOwnershipPreset),
            tostring(active)
        )
        bossModOwned = false
        bossModOwnershipPreset = nil
        return true
    end

    if active == "" then
        return restoreInitialBossModPreset()
    end

    logf("OnStop: leaving externally active BossMod preset unchanged: %q.", active)
    return true
end

function OnStop()
    pcall(function()
        log("OnStop cleanup starting.")
    end)

    pcall(function()
        stopPathing(1.0)
    end)

    local bossOk, bossResult = pcall(cleanupBossModOnStop)
    if not bossOk or bossResult == false then
        pcall(function()
            local detail = bossOk and "cleanup returned false" or tostring(bossResult)
            logf("OnStop: BossMod cleanup failed: %s", detail)
        end)
    end

    local jobOk, jobResult = pcall(function()
        return restorePendingSupportJob("OnStop support-job cleanup")
    end)
    if not jobOk or jobResult == false then
        pcall(function()
            logf("OnStop: support-job restoration failed: %s", tostring(jobOk and "restoration returned false" or jobResult))
        end)
    end

    pcall(function()
        log("OnStop cleanup finished.")
    end)
end

local function handleAutorotationEnable(snapshot)
    if acquireBossModPreset(AUTOROTATION_PRESET_NAME) then
        logf("Autorotation enabled for CE %s (%s).", snapshot.name, tostring(snapshot.id))
        return true, nil
    end

    if snapshot.stateCode < 3 then
        log("Autorotation activation failed before Battle.")
        return false, ActivityResult.AutorotationFailed
    end

    if not stopAfterCurrentCe then
        stopAfterCurrentCe = true
        log("Autorotation activation failed during Battle; will stop after current CE.")
    end
    return false, nil
end

local function travelToCe(snapshot)
    local route = chooseRoute(snapshot)
    local preferredAethernet = route.preferred
    local selectedRoute = route.kind
    local completedTransport = "direct"
    logf("Selected CE '%s' (%s) via route %s (%s).", snapshot.name, tostring(snapshot.id), selectedRoute, route.reason)

    local function validateTarget()
        return validateCeForTravel(snapshot.id)
    end

    local function revalidate(stage)
        local result, detail = validateTarget()
        if result ~= ActivityResult.Completed then
            logf("CE %s invalid after %s: result=%s detail=%s.", snapshot.name, stage, tostring(result), tostring(detail))
        end
        return result, detail
    end

    local function recoverAfterBattle(detail)
        stopPathing(3.0)
        local recoveryOk, recoveryErr = recoverToBaseAndWait()
        if not recoveryOk then
            return ActivityResult.EndedDuringTravel, string.format("%s; Base Camp recovery failed: %s", detail, tostring(recoveryErr))
        end
        return ActivityResult.EndedDuringTravel, detail
    end

    local prepResult, prepDetail = prepareForTravel(validateTarget, "CE " .. snapshot.name)
    if prepResult ~= ActivityResult.Completed then
        return prepResult, prepDetail
    end

    if selectedRoute == "return" then
        logf("CE route attempt 1 for %s: Return.", snapshot.name)
        local returnOk, returnErr = useReturn()
        if returnOk then
            completedTransport = "return"
            local validResult, validDetail = revalidate("Return")
            if validResult ~= ActivityResult.Completed then
                return validResult, validDetail
            end
        else
            logf("CE Return route failed for %s: %s. Falling back to aethernet/direct.", snapshot.name, tostring(returnErr))
        end

        if preferredAethernet ~= nil and (not returnOk or preferredAethernet.name ~= "BaseCamp") then
            local validResult, validDetail = revalidate("before aethernet fallback")
            if validResult ~= ActivityResult.Completed then
                return validResult, validDetail
            end
            logf("CE route fallback for %s: aethernet via %s.", snapshot.name, tostring(preferredAethernet.name))
            local aethOk, aethErr = useOccultAethernet(preferredAethernet)
            if aethOk then
                completedTransport = "aethernet"
                validResult, validDetail = revalidate("aethernet fallback")
                if validResult ~= ActivityResult.Completed then
                    return validResult, validDetail
                end
            else
                logf("CE aethernet fallback failed for %s: %s. Falling back to direct travel.", snapshot.name, tostring(aethErr))
            end
        end
    elseif selectedRoute == "aethernet" then
        local validResult, validDetail = revalidate("before aethernet")
        if validResult ~= ActivityResult.Completed then
            return validResult, validDetail
        end
        logf("CE route attempt for %s: aethernet via %s.", snapshot.name, tostring(preferredAethernet and preferredAethernet.name))
        local aethOk, aethErr = useOccultAethernet(preferredAethernet)
        if aethOk then
            completedTransport = "aethernet"
            validResult, validDetail = revalidate("aethernet")
            if validResult ~= ActivityResult.Completed then
                return validResult, validDetail
            end
        else
            logf("CE aethernet route failed for %s: %s. Falling back to direct travel.", snapshot.name, tostring(aethErr))
        end
    end

    local validResult, validDetail = revalidate("before mounting")
    if validResult ~= ActivityResult.Completed then
        return validResult, validDetail
    end

    if not ensureMounted() then
        return ActivityResult.TravelFailed, "failed to mount"
    end

    validResult, validDetail = revalidate("after mounting")
    if validResult ~= ActivityResult.Completed then
        return validResult, validDetail
    end

    local moved = false
    local engageRadius = tonumber(snapshot.metadata.engageRadius) or 20

    for attempt = 1, WAIT_POINT_RETRIES do
        local current = waitForSnapshotById(snapshot.id)
        if shouldAbortForBattleState(current) then
            return recoverAfterBattle("CE entered Battle before arrival")
        end

        local waitPoint = getCeWaitPoint(snapshot.metadata)
        logf("CE wait-point attempt %d/%d: target %s.", attempt, WAIT_POINT_RETRIES, formatVector3(waitPoint))
        local result = ceMoveToPosition(waitPoint, CE_WAIT_POINT_STOP_DISTANCE, nil, snapshot.id)
        if result == CeMoveResult.Arrived then
            local finalDistance = distanceFlat(getPlayerPosition(), snapshot.metadata.stagingPoint)
            if finalDistance <= engageRadius then
                moved = true
                break
            end
            logf("CE wait-point attempt ended outside engage radius: %.2f > %.2f.", finalDistance, engageRadius)
        elseif result == CeMoveResult.DeathRecoveryFailed then
            return ActivityResult.DeathRecoveryFailed, "failed to recover from death during CE travel"
        elseif result == CeMoveResult.BattleAbort then
            return recoverAfterBattle("CE entered Battle before arrival")
        end
    end

    if not moved then
        local current = waitForSnapshotById(snapshot.id)
        if shouldAbortForBattleState(current) then
            return recoverAfterBattle("CE entered Battle before arrival")
        end

        local innerStopDistance = math.max(0.5, engageRadius - CE_RADIUS_SAFETY_MARGIN)
        logf("All CE wait-point attempts exhausted; moving toward inner staging radius %.2f.", innerStopDistance)
        local result = ceMoveToPosition(snapshot.metadata.stagingPoint, innerStopDistance, nil, snapshot.id)
        if result == CeMoveResult.Arrived then
            moved = distanceFlat(getPlayerPosition(), snapshot.metadata.stagingPoint) <= engageRadius
        elseif result == CeMoveResult.DeathRecoveryFailed then
            return ActivityResult.DeathRecoveryFailed, "failed to recover from death during CE travel"
        elseif result == CeMoveResult.BattleAbort then
            return recoverAfterBattle("CE entered Battle before arrival")
        end
    end

    if not moved then
        return ActivityResult.TravelFailed, "failed to reach CE wait area"
    end

    logf(
        "CE travel result: name=%q selectedRoute=%s completedTransport=%s result=%s.",
        snapshot.name,
        selectedRoute,
        completedTransport,
        ActivityResult.Completed
    )
    return ActivityResult.Completed, nil
end

local function monitorCe(snapshot)
    local autorotationActive = false
    local autorotationAttempted = false
    local endedByDisappearance = false
    local outcome = ActivityResult.Completed
    local detail = nil
    logf("Monitoring CE %s (%s).", snapshot.name, tostring(snapshot.id))

    while true do
        local current = waitForSnapshotById(snapshot.id)
        if current == nil then
            logf("CE %s disappeared from scan results.", snapshot.name)
            endedByDisappearance = true
            break
        end

        if current.stateCode == 0 and not current.isActive then
            logf("CE %s is now inactive; ending monitor loop.", current.name)
            break
        end

        local rotationNeeded = current.stateCode >= 3 or isInCombat()
        if rotationNeeded then
            if current.stateCode >= 3 and (os.clock() - lastCeBattleLogAt) >= IDLE_LOG_INTERVAL then
                logf(
                    "CE %s is in Battle state. autorotationActive=%s attempted=%s inCombat=%s",
                    current.name,
                    tostring(autorotationActive),
                    tostring(autorotationAttempted),
                    tostring(isInCombat())
                )
                lastCeBattleLogAt = os.clock()
            end

            if not autorotationActive and not autorotationAttempted then
                autorotationAttempted = true
                local enableResult = nil
                autorotationActive, enableResult = handleAutorotationEnable(current)
                if enableResult ~= nil then
                    outcome = enableResult
                    detail = "BossMod preset activation failed before CE Battle"
                    break
                end
            end
        else
            if autorotationActive then
                logf("Combat ended before Battle for CE %s; clearing autorotation and rechecking radius.", current.name)
                releaseOwnedBossModPreset()
                autorotationActive = false
            end
            autorotationAttempted = false
            ensureInsideCeRadius(current)
        end

        if isDead() then
            logf("Player died during CE %s.", current.name)
            if not handleDeathState() then
                outcome = ActivityResult.DeathRecoveryFailed
                detail = "failed to recover from death during CE"
                break
            end

            if bossModOwned then
                releaseOwnedBossModPreset()
            end
            autorotationActive = false
            autorotationAttempted = false

            local afterDeath = waitForSnapshotById(snapshot.id)
            if afterDeath and afterDeath.isActive then
                local rotationNeededAfterDeath = afterDeath.stateCode >= 3 or isInCombat()
                if rotationNeededAfterDeath then
                    autorotationAttempted = true
                    local enableResult = nil
                    autorotationActive, enableResult = handleAutorotationEnable(afterDeath)
                    if enableResult ~= nil then
                        outcome = enableResult
                        detail = "BossMod preset activation failed after CE death recovery"
                        break
                    end
                end
            else
                break
            end
        end

        sleep(POLL_INTERVAL)
    end

    if outcome == ActivityResult.Completed then
        if not waitForCombatToSettle() then
            outcome = ActivityResult.CombatDidNotSettle
            detail = "combat did not settle after CE"
        elseif endedByDisappearance then
            logf("CE %s ended by disappearance; post-combat cleanup complete.", snapshot.name)
        end
    end

    if autorotationActive or bossModOwned then
        logf("Final CE cleanup for %s. Clearing autorotation.", snapshot.name)
        releaseOwnedBossModPreset()
    end

    return outcome, detail
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
    local returnTime = math.huge
    if USE_RETURN then
        returnTime = RETURN_PENALTY + returnTeleportPenalty + (returnRideDist / speed)
    end

    logf(
        "FATE route for '%s': direct=%.1fs shard=%.1fs return=%s nearest_player=%s nearest_fate=%s",
        fate.name,
        directTime,
        shardTime,
        USE_RETURN and string.format("%.1fs", returnTime) or "disabled",
        nearestToPlayer and nearestToPlayer.name or "nil",
        nearestToFate and nearestToFate.name or "nil"
    )

    if not USE_RETURN then
        if directTime <= shardTime then
            return { kind = "direct", reason = "faster_direct_return_disabled", preferred = nearestToFate }
        end
        return { kind = "aethernet", reason = "faster_shard_return_disabled", preferred = nearestToFate }
    end

    if directTime <= shardTime and directTime <= returnTime then
        return { kind = "direct", reason = "faster_direct", preferred = nearestToFate }
    end
    if returnTime < shardTime then
        return { kind = "return", reason = "faster_return", preferred = nearestToFate }
    end
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

local function validateFateForTravel(fateId)
    if PRIORITIZE_CE and ENABLE_CE_FARMING and isCeAvailable() then
        return ActivityResult.CeAvailable, "CE became available during FATE travel"
    end

    if not isFateActive(fateId) or getFateSnapshot(fateId) == nil then
        return ActivityResult.EndedDuringTravel, "FATE is no longer available"
    end

    return ActivityResult.Completed, nil
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
            if not handleDeathState() then
                logf("Death recovery failed while traveling to FATE %d.", fateId)
                return CeMoveResult.DeathRecoveryFailed
            end
            if not isFateActive(fateId) or getFateSnapshot(fateId) == nil then
                logf("FATE %d ended during death recovery.", fateId)
                return CeMoveResult.BattleAbort
            end
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
    local selectedRoute = route.kind
    local completedTransport = "direct"
    logf("Traveling to FATE '%s' via selected route %s (%s).", fate.name, selectedRoute, route.reason)

    local function validateTarget()
        return validateFateForTravel(fate.id)
    end

    local function revalidate(stage)
        local result, detail = validateTarget()
        if result ~= ActivityResult.Completed then
            logf("FATE %s invalid after %s: result=%s detail=%s.", fate.name, stage, tostring(result), tostring(detail))
        end
        return result, detail
    end

    local prepResult, prepDetail = prepareForTravel(validateTarget, "FATE " .. fate.name)
    if prepResult ~= ActivityResult.Completed then
        return prepResult, prepDetail
    end

    if selectedRoute == "return" then
        logf("FATE route attempt 1 for %s: Return.", fate.name)
        local returnOk, returnErr = useReturn()
        if returnOk then
            completedTransport = "return"
            local validResult, validDetail = revalidate("Return")
            if validResult ~= ActivityResult.Completed then
                return validResult, validDetail
            end
        else
            logf("FATE Return route failed for %s: %s. Falling back to aethernet/direct.", fate.name, tostring(returnErr))
        end

        if route.preferred ~= nil and (not returnOk or route.preferred.name ~= "BaseCamp") then
            local validResult, validDetail = revalidate("before aethernet fallback")
            if validResult ~= ActivityResult.Completed then
                return validResult, validDetail
            end
            logf("FATE route fallback for %s: aethernet via %s.", fate.name, tostring(route.preferred.name))
            local aethOk, aethErr = useOccultAethernet(route.preferred)
            if aethOk then
                completedTransport = "aethernet"
                validResult, validDetail = revalidate("aethernet fallback")
                if validResult ~= ActivityResult.Completed then
                    return validResult, validDetail
                end
            else
                logf("FATE aethernet fallback failed for %s: %s. Falling back to direct travel.", fate.name, tostring(aethErr))
            end
        end
    elseif selectedRoute == "aethernet" then
        local validResult, validDetail = revalidate("before aethernet")
        if validResult ~= ActivityResult.Completed then
            return validResult, validDetail
        end
        logf("FATE route attempt for %s: aethernet via %s.", fate.name, tostring(route.preferred and route.preferred.name))
        local aethOk, aethErr = useOccultAethernet(route.preferred)
        if aethOk then
            completedTransport = "aethernet"
            validResult, validDetail = revalidate("aethernet")
            if validResult ~= ActivityResult.Completed then
                return validResult, validDetail
            end
        else
            logf("FATE aethernet route failed for %s: %s. Falling back to direct travel.", fate.name, tostring(aethErr))
        end
    end

    local validResult, validDetail = revalidate("before mounting")
    if validResult ~= ActivityResult.Completed then
        return validResult, validDetail
    end

    if not ensureMounted() then
        return ActivityResult.TravelFailed, "failed to mount"
    end

    validResult, validDetail = revalidate("after mounting")
    if validResult ~= ActivityResult.Completed then
        return validResult, validDetail
    end

    local stopDist = math.min(fate.radius, 15)
    local speed = metadata.mountedTravelSpeed or 14.13
    local estimatedTime = distanceFlat(getPlayerPosition(), fate.location) / speed
    local timeout = math.max(CE_ATTEMPT_TIMEOUT, estimatedTime * 1.5 + 10)
    local result = fateMoveToPosition(fate.location, stopDist, timeout, fate.id)
    if result == CeMoveResult.CeAvailable then
        return ActivityResult.CeAvailable, "CE became available during FATE travel"
    end
    if result == CeMoveResult.DeathRecoveryFailed then
        return ActivityResult.DeathRecoveryFailed, "failed to recover from death during FATE travel"
    end
    if result == CeMoveResult.BattleAbort then
        logf("FATE %s ended while traveling.", fate.name)
        return ActivityResult.EndedDuringTravel, "FATE ended during travel"
    end
    if result ~= CeMoveResult.Arrived then
        return ActivityResult.TravelFailed, "failed to reach FATE position"
    end

    logf(
        "FATE travel result: name=%q selectedRoute=%s completedTransport=%s result=%s.",
        fate.name,
        selectedRoute,
        completedTransport,
        ActivityResult.Completed
    )
    return ActivityResult.Completed, nil
end

local function applyBossModForFate()
    if acquireBossModPreset(AUTOROTATION_PRESET_NAME) then
        log("Autorotation enabled for FATE.")
        return true
    end
    log("Autorotation preset activation failed for FATE; continuing without it.")
    return false
end

local function monitorFate(fate)
    local autorotationActive = false
    local autorotationAttempted = false
    local outcome = ActivityResult.Completed
    local detail = nil
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

        local rotationNeeded = isInCombat() or snapshot.inFate
        if rotationNeeded then
            if not autorotationActive and not autorotationAttempted then
                autorotationAttempted = true
                autorotationActive = applyBossModForFate()
            end
        else
            if autorotationActive then
                logf("Combat ended for FATE %s; clearing autorotation.", fate.name)
                releaseOwnedBossModPreset()
                autorotationActive = false
            end
            autorotationAttempted = false
        end

        if (os.clock() - lastFateMonitorLogAt) >= IDLE_LOG_INTERVAL then
            logf(
                "FATE monitor: id=%d active=%s inFate=%s inCombat=%s autorotationActive=%s attempted=%s progress=%.1f",
                fate.id,
                tostring(isFateActive(fate.id)),
                tostring(snapshot.inFate),
                tostring(isInCombat()),
                tostring(autorotationActive),
                tostring(autorotationAttempted),
                snapshot.progress or 0
            )
            lastFateMonitorLogAt = os.clock()
        end
        if PRIORITIZE_CE and ENABLE_CE_FARMING and (os.clock() - lastCeCheckAt) >= CE_CHECK_INTERVAL then
            lastCeCheckAt = os.clock()
            if isCeAvailable() then
                logf("CE available while monitoring FATE %s; ending monitor.", fate.name)
                outcome = ActivityResult.CeAvailable
                detail = "CE became available during FATE monitoring"
                break
            end
        end

        if isDead() then
            logf("Player died during FATE %s.", fate.name)
            if not handleDeathState() then
                outcome = ActivityResult.DeathRecoveryFailed
                detail = "failed to recover from death during FATE"
                break
            end
            if bossModOwned then
                releaseOwnedBossModPreset()
            end
            autorotationActive = false
            autorotationAttempted = false
        end

        sleep(POLL_INTERVAL)
    end

    if outcome == ActivityResult.Completed then
        if not waitForCombatToSettle() then
            outcome = ActivityResult.CombatDidNotSettle
            detail = "combat did not settle after FATE"
        end
    end

    if autorotationActive or bossModOwned then
        logf("Final FATE cleanup for %s. Clearing autorotation.", fate.name)
        releaseOwnedBossModPreset()
    end

    return outcome, detail
end

local function returnAfterFate(fate)
    if not USE_RETURN then
        if not waitForCombatToSettle() then
            logf("FATE %s complete, but combat did not settle; staying in place.", fate.name)
            return false
        end
        logf("FATE %s complete, Return disabled; staying in place.", fate.name)
        return true
    end

    local ok, err = recoverToBaseAndWait()
    if not ok then
        logf("FATE %s complete, Base Camp recovery failed: %s.", fate.name, tostring(err))
        return false
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

    runBuffRotation("startup")

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
                local travelResult, travelDetail = travelToCe(target)
                if travelResult == ActivityResult.DeathRecoveryFailed then
                    stopScriptWithError(travelDetail or "failed to recover from death during CE travel")
                elseif travelResult ~= ActivityResult.Completed then
                    logf(
                        "Travel to CE %s ended with result=%s detail=%s. Resuming scan.",
                        target.name,
                        tostring(travelResult),
                        tostring(travelDetail)
                    )
                else
                    local monitorResult, monitorDetail = monitorCe(target)
                    if monitorResult == ActivityResult.DeathRecoveryFailed then
                        stopScriptWithError(monitorDetail or "failed to recover from death during CE")
                    elseif monitorResult == ActivityResult.CombatDidNotSettle then
                        stopScriptWithError(monitorDetail or "combat did not settle after CE")
                    elseif monitorResult == ActivityResult.AutorotationFailed then
                        local returnOk, returnErr = recoverToBaseAndWait()
                        if not returnOk then
                            stopScriptWithError(returnErr or "failed to return to base after CE autorotation failure")
                        end
                        stopScriptWithError(monitorDetail or "BossMod preset activation failed before CE Battle")
                    end

                    if stopAfterCurrentCe then
                        local returnOk, returnErr = recoverToBaseAndWait()
                        if not returnOk then
                            stopScriptWithError(returnErr or "failed to return to base after fatal CE error")
                        end
                        stopScriptWithError("Stopping after CE because autorotation failed during Battle")
                    end

                    local fateHandled = false
                    local cePreempted = false
                    if ENABLE_FATE_FARMING then
                        local fateTarget = selectTargetFate(scanFates())
                        if fateTarget then
                            local fateTravelResult, fateTravelDetail = travelToFate(fateTarget)
                            if fateTravelResult == ActivityResult.Completed then
                                local fateMonitorResult, fateMonitorDetail = monitorFate(fateTarget)
                                if fateMonitorResult == ActivityResult.CeAvailable then
                                    cePreempted = true
                                elseif fateMonitorResult == ActivityResult.Completed then
                                    returnAfterFate(fateTarget)
                                    fateHandled = true
                                elseif fateMonitorResult == ActivityResult.DeathRecoveryFailed then
                                    stopScriptWithError(fateMonitorDetail or "failed to recover from death during post-CE FATE")
                                elseif fateMonitorResult == ActivityResult.CombatDidNotSettle then
                                    stopScriptWithError(fateMonitorDetail or "combat did not settle after post-CE FATE")
                                else
                                    logf(
                                        "Post-CE FATE monitor ended with result=%s detail=%s.",
                                        tostring(fateMonitorResult),
                                        tostring(fateMonitorDetail)
                                    )
                                end
                            elseif fateTravelResult == ActivityResult.CeAvailable then
                                cePreempted = true
                            elseif fateTravelResult == ActivityResult.EndedDuringTravel then
                                logf("Post-CE FATE ended during travel: %s.", tostring(fateTravelDetail))
                                returnAfterFate(fateTarget)
                                fateHandled = true
                            elseif fateTravelResult == ActivityResult.DeathRecoveryFailed then
                                stopScriptWithError(fateTravelDetail or "failed to recover from death during post-CE FATE travel")
                            else
                                logf(
                                    "Post-CE FATE travel ended with result=%s detail=%s.",
                                    tostring(fateTravelResult),
                                    tostring(fateTravelDetail)
                                )
                            end
                        end
                    end

                    if cePreempted then
                        log("CE available after CE; abandoning FATE.")
                        sleep(POLL_INTERVAL)
                        goto continue_loop
                    end

                    if not fateHandled then
                        local returnOk, returnErr = recoverToBaseAndWait()
                        if not returnOk then
                            stopScriptWithError(returnErr or "failed to return to base")
                        end
                    end
                    runBuffRotation("post-CE recovery")
                end
                sleep(POLL_INTERVAL)
                goto continue_loop
            end
        end

        -- FATE farming (no CE found or CE disabled)
        if ENABLE_FATE_FARMING then
            local fateTarget = selectTargetFate(scanFates())
            if fateTarget then
                local travelResult, travelDetail = travelToFate(fateTarget)
                if travelResult == ActivityResult.CeAvailable then
                    logf("CE available; abandoning FATE %s.", fateTarget.name)
                    sleep(POLL_INTERVAL)
                    goto continue_loop
                elseif travelResult == ActivityResult.DeathRecoveryFailed then
                    stopScriptWithError(travelDetail or "failed to recover from death during FATE travel")
                elseif travelResult == ActivityResult.EndedDuringTravel then
                    logf("FATE %s ended during travel: %s.", fateTarget.name, tostring(travelDetail))
                    returnAfterFate(fateTarget)
                    runBuffRotation("FATE ended during travel")
                    sleep(POLL_INTERVAL)
                    goto continue_loop
                elseif travelResult ~= ActivityResult.Completed then
                    logf(
                        "Travel to FATE ended with result=%s detail=%s.",
                        tostring(travelResult),
                        tostring(travelDetail)
                    )
                    sleep(POLL_INTERVAL)
                    goto continue_loop
                end

                local monitorResult, monitorDetail = monitorFate(fateTarget)
                if monitorResult == ActivityResult.CeAvailable then
                    logf("CE available; abandoning FATE %s.", fateTarget.name)
                    sleep(POLL_INTERVAL)
                    goto continue_loop
                elseif monitorResult == ActivityResult.DeathRecoveryFailed then
                    stopScriptWithError(monitorDetail or "failed to recover from death during FATE")
                elseif monitorResult == ActivityResult.CombatDidNotSettle then
                    stopScriptWithError(monitorDetail or "combat did not settle after FATE")
                elseif monitorResult ~= ActivityResult.Completed then
                    logf(
                        "FATE monitor ended with result=%s detail=%s.",
                        tostring(monitorResult),
                        tostring(monitorDetail)
                    )
                    sleep(POLL_INTERVAL)
                    goto continue_loop
                end

                returnAfterFate(fateTarget)
                runBuffRotation("post-FATE recovery")
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
