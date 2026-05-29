--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.0.7
description: |
  Follow the current hunt flag, wait for any cross-zone teleport to finish, and redirect to the hunt mob once it loads.
plugin_dependencies:
- vnavmesh
configs:
  Flag Stop Distance:
    description: Distance from the flag that counts as arrival when no hunt is found.
    default: 10
    min: 1
    max: 20
  Hunt Wait Distance:
    description: Distance from the hunt hitbox to stop, dismount, and wait before handing off.
    default: 25
    min: 10
    max: 40
  BossMod Autorotation Preset:
    description: Autorotation preset to apply after the hunt is targeted. Leave empty to disable.
    default: ""
  Teleport Penalty:
    description: Estimated seconds spent teleporting, loading, and remounting.
    default: 13
    min: 0
    max: 60
  Minimum Teleport Savings:
    description: Minimum seconds saved before teleporting to a closer aetheryte.
    default: 0
    min: 0
    max: 30
  Zone Timeout:
    description: Maximum seconds to wait for teleport, zoning, or instance-switch completion.
    default: 30
    min: 10
    max: 300
  Mount Timeout:
    description: Maximum seconds to keep retrying mount or dismount actions.
    default: 10
    min: 2
    max: 60
[[End Metadata]]
--]=====]

import("System.Numerics")

local PREFIX = "[Hunt Flag]"
-- Measured mounted flight speed used for same-zone aetheryte travel estimates.
local FLIGHT_SPEED = 20
local TELEPORT_START_TIMEOUT = 2.0
local HUNT_TARGET_DISTANCE = 45
local INSTANCE_WATCH_TIMEOUT = 2.0
local INSTANCE_WATCH_POLL = 0.05
local FLAG_ACQUIRE_TIMEOUT = 5.0
local MOUNT_RETRY_COOLDOWN = 1.0
local HUNT_SCAN_START_DISTANCE = 60
local SAFE_HUNT_MIN_BUFFER = 3
local SAFE_HUNT_VERTICAL_TOLERANCE = 12
local SAFE_HUNT_MAX_PROJECTION_DRIFT = 8
local SAFE_HUNT_STALL_TIMEOUT = 3.0
local SAFE_HUNT_PROJECTION_RESCUE_NUDGE = 3
local SAFE_HUNT_STALL_GRACE_AFTER_START = 2.0
local SAFE_HUNT_STALL_GRACE_AFTER_TARGET = 1.5
local SAFE_HUNT_STALL_GRACE_AFTER_REPATH = 2.0
local SAFE_HUNT_TARGET_ACQUIRE_TIMEOUT = 8.0
local STARTUP_REPEAT_CALL_DISTANCE = 45
local FLAG_MOVEMENT_START_TIMEOUT = 2.0
local FLAG_NO_PROGRESS_TIMEOUT = 10.0
local ENGAGED_HANDOFF_POINT_REACHED_DISTANCE = 5.0
local STARTUP_HUNT_MISS_THRESHOLD = 3
local STARTUP_HUNT_HEARTBEAT_INTERVAL = 5.0
local autorotationPrefix = nil

local STATE_TRAVEL_TO_FLAG = "travel_to_flag"
local STATE_SAFE_HUNT_APPROACH = "safe_hunt_approach"
local STATE_WAIT_HUNT_HANDOFF = "wait_hunt_handoff"
local STATE_ENGAGED_HUNT_HANDOFF = "engaged_hunt_handoff"

local STATE_LABELS = {
    [STATE_TRAVEL_TO_FLAG] = "travel_to_flag",
    [STATE_SAFE_HUNT_APPROACH] = "safe_hunt_approach",
    [STATE_WAIT_HUNT_HANDOFF] = "wait_hunt_handoff",
    [STATE_ENGAGED_HUNT_HANDOFF] = "engaged_hunt_handoff",
}

local INSTANCE_ACTIVITY_NONE = "none"
local INSTANCE_ACTIVITY_TRANSITION = "transition_active"
local INSTANCE_ACTIVITY_SELECT_STRING = "select_string"
local INSTANCE_ACTIVITY_CHANGED = "instance_changed"

local RESULT_CONTINUE = "continue"
local RESULT_SUCCESS = "success"
local RESULT_ERROR = "error"

-- Hunt distance roles:
-- scan start: begin looking for hunts only after getting near the flag area
-- target acquire: attempt to set target when close enough for reliable target lock
-- wait: stop, dismount, and hold near the hunt until it is safe to hand off

CharacterCondition = {
    mounted = 4,
    inCombat = 26,
    casting = 27,
    betweenAreas = 45,
    betweenAreasForDuty = 51,
    mounting57 = 57,
    mounting64 = 64,
}

local function getConfigValue(name, fallback)
    local ok, value = pcall(function()
        return Config and Config.Get and Config.Get(name)
    end)

    if ok and value ~= nil then
        return value
    end

    return fallback
end

local POLL_INTERVAL = 0.25
local BOSSMOD_AUTOROTATION_PRESET = tostring(getConfigValue("BossMod Autorotation Preset", "") or "")
local TELEPORT_PENALTY = tonumber(getConfigValue("Teleport Penalty", 13)) or 13
local MINIMUM_TELEPORT_SAVINGS = tonumber(getConfigValue("Minimum Teleport Savings", 0)) or 0
local FLAG_STOP_DISTANCE = tonumber(getConfigValue("Flag Stop Distance", 10)) or 10
local HUNT_WAIT_DISTANCE = tonumber(getConfigValue("Hunt Wait Distance", 25)) or 25
local ZONE_TIMEOUT = tonumber(getConfigValue("Zone Timeout", 30)) or 30
local MOUNT_TIMEOUT = tonumber(getConfigValue("Mount Timeout", 10)) or 10

TELEPORT_PENALTY = math.max(0, math.min(60, TELEPORT_PENALTY))
MINIMUM_TELEPORT_SAVINGS = math.max(0, math.min(30, MINIMUM_TELEPORT_SAVINGS))
FLAG_STOP_DISTANCE = math.max(1, math.min(20, FLAG_STOP_DISTANCE))
HUNT_WAIT_DISTANCE = math.max(10, math.min(40, HUNT_WAIT_DISTANCE))
ZONE_TIMEOUT = math.max(10, math.min(300, ZONE_TIMEOUT))
MOUNT_TIMEOUT = math.max(2, math.min(60, MOUNT_TIMEOUT))

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

local function SetRuntimeState(runtime, state, detailFmt, ...)
    if runtime.state == state then
        return
    end

    runtime.state = state

    local stateLabel = tostring(STATE_LABELS[state] or state or "unknown")
    if detailFmt ~= nil then
        logf("State -> %s: " .. tostring(detailFmt), stateLabel, ...)
        return
    end

    logf("State -> %s.", stateLabel)
end

local function verboseLog(message)
    local text = string.format("%s %s", PREFIX, tostring(message))
    pcall(function()
        Dalamud.LogVerbose(text)
    end)
end

local function verboseLogf(fmt, ...)
    local ok, formatted = pcall(string.format, fmt, ...)
    if ok then
        verboseLog(formatted)
    end
end

local function trimString(value)
    local s = tostring(value or "")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

BOSSMOD_AUTOROTATION_PRESET = trimString(BOSSMOD_AUTOROTATION_PRESET)

local function _get_addon(name)
    if not (Addons and Addons.GetAddon) then
        return nil
    end

    local ok, addon = pcall(Addons.GetAddon, name)
    if ok and addon ~= nil then
        return addon
    end

    return nil
end

local function _addon_ready(addon)
    if not addon then
        return false
    end

    if addon.Ready == true or addon.IsReady == true or addon.Loaded == true then
        return true
    end

    if type(addon.Ready) == "function" then
        local ok, value = pcall(addon.Ready, addon)
        if ok and value then
            return true
        end
    end

    if type(addon.IsReady) == "function" then
        local ok, value = pcall(addon.IsReady, addon)
        if ok and value then
            return true
        end
    end

    return false
end

local function IsAddonReady(name)
    return _addon_ready(_get_addon(name))
end

local function IsSpecificPluginLoaded(name)
    if not (Svc and Svc.PluginInterface and Svc.PluginInterface.InstalledPlugins) then
        return false
    end

    for plugin in luanet.each(Svc.PluginInterface.InstalledPlugins) do
        if plugin.InternalName == name then
            return plugin.IsLoaded == true
        end
    end

    return false
end

local function GetAutorotationCommandPrefix()
    if IsSpecificPluginLoaded("BossModReborn") then
        return "/bmr"
    end

    if IsSpecificPluginLoaded("BossMod") then
        return "/vbm"
    end

    return nil
end

local function ClearAutorotationPreset(prefix)
    if not prefix then
        return false
    end

    logf("Clearing autorotation preset via %s.", prefix)
    yield(prefix .. " ar clear")
    return true
end

local function ApplyAutorotationPreset(prefix, preset)
    preset = trimString(preset)
    if not prefix or preset == "" then
        return false
    end

    logf("Applying autorotation preset '%s' via %s.", preset, prefix)
    yield(string.format("%s ar set %s", prefix, preset))
    return true
end

local function WaitUntil(predicate, timeoutSec, pollSec, stableSec)
    timeoutSec = tonumber(timeoutSec) or 10
    pollSec = tonumber(pollSec) or 0.1
    stableSec = tonumber(stableSec) or 0

    if stableSec < 0 then
        stableSec = 0
    end

    local deadline = os.clock() + timeoutSec
    local stableStart = nil

    while os.clock() < deadline do
        local ok, result = pcall(predicate)
        if ok and result then
            if stableSec <= 0 then
                return true
            end

            if stableStart == nil then
                stableStart = os.clock()
            elseif (os.clock() - stableStart) >= stableSec then
                return true
            end
        else
            stableStart = nil
        end

        sleep(pollSec)
    end

    return false
end

local function getCurrentTerritoryId()
    local ok, territoryId = pcall(function()
        return Svc and Svc.ClientState and Svc.ClientState.TerritoryType
    end)

    territoryId = ok and tonumber(territoryId) or nil
    if not territoryId or territoryId <= 0 then
        return nil
    end

    return territoryId
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

local function getZoneInstance()
    local ok, instanceId = pcall(function()
        return InstancedContent and InstancedContent.PublicInstance and InstancedContent.PublicInstance.InstanceId
    end)

    instanceId = ok and tonumber(instanceId) or 0
    if not instanceId or instanceId < 0 then
        return 0
    end

    return instanceId
end

local function isPlayerAvailable()
    return Player ~= nil and Player.Available == true
end

local function getCondition(flag)
    if flag == nil or not (Svc and Svc.Condition) then
        return false
    end

    return Svc.Condition[flag] == true
end

local function isMounting()
    return getCondition(CharacterCondition.mounting57) or getCondition(CharacterCondition.mounting64)
end

local function isMounted()
    return getCondition(CharacterCondition.mounted)
end

local function IsLifestreamBusy()
    if IPC and IPC.Lifestream and IPC.Lifestream.IsBusy then
        local ok, busy = pcall(IPC.Lifestream.IsBusy)
        return ok and busy == true
    end

    return false
end

local function describeZoneTransitionState()
    local states = {}

    if getCondition(CharacterCondition.casting) then
        table.insert(states, "casting")
    end
    if getCondition(CharacterCondition.betweenAreas) then
        table.insert(states, "betweenAreas")
    end
    if getCondition(CharacterCondition.betweenAreasForDuty) then
        table.insert(states, "betweenAreasForDuty")
    end
    if IsLifestreamBusy() then
        table.insert(states, "lifestreamBusy")
    end

    if #states == 0 then
        return "idle"
    end

    return table.concat(states, ",")
end

local function isZoneTransitionActive()
    return getCondition(CharacterCondition.casting)
        or getCondition(CharacterCondition.betweenAreas)
        or getCondition(CharacterCondition.betweenAreasForDuty)
        or IsLifestreamBusy()
end

local function isZoneTransitionComplete()
    return (not IsAddonReady("FadeMiddle"))
        and (not IsLifestreamBusy())
        and (not getCondition(CharacterCondition.casting))
        and (not getCondition(CharacterCondition.betweenAreas))
        and (not getCondition(CharacterCondition.betweenAreasForDuty))
        and isPlayerAvailable()
end

local function WaitForZoneCompletion(targetTerritoryId, timeoutSec, requireActivity)
    timeoutSec = tonumber(timeoutSec) or ZONE_TIMEOUT
    requireActivity = requireActivity == true

    if not requireActivity and targetTerritoryId ~= nil then
        local current = getCurrentTerritoryId()
        if current == targetTerritoryId and isZoneTransitionComplete() and (not isZoneTransitionActive()) then
            return true
        end
    elseif not requireActivity and isZoneTransitionComplete() and (not isZoneTransitionActive()) then
        return true
    end

    local startDeadline = os.clock() + timeoutSec
    local sawActivity = false

    while os.clock() < startDeadline do
        local current = getCurrentTerritoryId()

        if isZoneTransitionActive() then
            if not sawActivity then
                logf("Zone activity detected: %s", describeZoneTransitionState())
            end
            sawActivity = true
        end

        if ((not requireActivity) or sawActivity) and isZoneTransitionComplete() then
            if targetTerritoryId == nil or current == targetTerritoryId then
                logf("Zone completion confirmed in territory %s.", tostring(current))
                return true
            end
        end

        sleep(POLL_INTERVAL)
    end

    return false
end

local function WaitForTeleportStart(startTerritoryId, expectedTerritoryId, timeoutSec, sourceLabel)
    timeoutSec = tonumber(timeoutSec) or TELEPORT_START_TIMEOUT
    sourceLabel = tostring(sourceLabel or "teleport")
    local deadline = os.clock() + timeoutSec

    logf(
        "Waiting up to %.2fs for %s to start (from %s to %s).",
        timeoutSec,
        sourceLabel,
        tostring(startTerritoryId),
        tostring(expectedTerritoryId)
    )

    while os.clock() < deadline do
        local currentTerritoryId = getCurrentTerritoryId()
        local transitionState = describeZoneTransitionState()

        if transitionState ~= "idle" then
            logf("%s start detected via state: %s", sourceLabel, transitionState)
            return true
        end

        if expectedTerritoryId ~= nil and currentTerritoryId == expectedTerritoryId and currentTerritoryId ~= startTerritoryId then
            logf("%s start detected via territory arrival: %s", sourceLabel, tostring(currentTerritoryId))
            return true
        end

        if startTerritoryId ~= nil and currentTerritoryId ~= nil and currentTerritoryId ~= 0 and currentTerritoryId ~= startTerritoryId then
            logf("%s start detected via territory change: %s -> %s", sourceLabel, tostring(startTerritoryId), tostring(currentTerritoryId))
            return true
        end

        sleep(POLL_INTERVAL)
    end

    logf("%s did not start within %.2fs.", sourceLabel, timeoutSec)
    return false
end

local function WaitForTeleportCompletion(targetTerritoryId, timeoutSec, sourceLabel)
    timeoutSec = tonumber(timeoutSec) or ZONE_TIMEOUT
    sourceLabel = tostring(sourceLabel or "teleport")
    local deadline = os.clock() + timeoutSec
    local sawCastEnd = false
    local sawBetweenAreas = false
    local stableStart = nil

    logf("Waiting up to %.2fs for %s to complete.", timeoutSec, sourceLabel)

    while os.clock() < deadline do
        local currentTerritoryId = getCurrentTerritoryId()
        local casting = getCondition(CharacterCondition.casting)
        local betweenAreas = getCondition(CharacterCondition.betweenAreas)
        local betweenAreasForDuty = getCondition(CharacterCondition.betweenAreasForDuty)
        local lifestreamBusy = IsLifestreamBusy()
        local fadeReady = IsAddonReady("FadeMiddle")

        if not casting and not sawCastEnd then
            sawCastEnd = true
            logf("%s cast phase finished.", sourceLabel)
        end

        if betweenAreas or betweenAreasForDuty then
            if not sawBetweenAreas then
                sawBetweenAreas = true
                logf(
                    "%s entered zone transition state (betweenAreas=%s, betweenAreasForDuty=%s).",
                    sourceLabel,
                    tostring(betweenAreas),
                    tostring(betweenAreasForDuty)
                )
            end
            stableStart = nil
        end

        local fullySettled = sawCastEnd
            and (not casting)
            and (not betweenAreas)
            and (not betweenAreasForDuty)
            and (not lifestreamBusy)
            and (not fadeReady)
            and isPlayerAvailable()
            and (targetTerritoryId == nil or currentTerritoryId == targetTerritoryId)

        if fullySettled then
            if stableStart == nil then
                stableStart = os.clock()
                logf("%s appears settled; starting stability confirmation.", sourceLabel)
            elseif (os.clock() - stableStart) >= 1.0 then
                logf(
                    "%s completion confirmed in territory %s after castEnd=%s, sawBetweenAreas=%s.",
                    sourceLabel,
                    tostring(currentTerritoryId),
                    tostring(sawCastEnd),
                    tostring(sawBetweenAreas)
                )
                return true
            end
        else
            stableStart = nil
        end

        sleep(POLL_INTERVAL)
    end

    logf(
        "%s completion timed out after castEnd=%s, sawBetweenAreas=%s, finalState=%s.",
        sourceLabel,
        tostring(sawCastEnd),
        tostring(sawBetweenAreas),
        describeZoneTransitionState()
    )
    return false
end

local function WatchForInstancedZoneActivity(startInstanceId, timeoutSec)
    verboseLogf("Public instance before watch: %d", startInstanceId)
    verboseLogf("Watching %.2fs for transition, SelectString, or instance change.", timeoutSec)

    local deadline = os.clock() + timeoutSec
    while os.clock() < deadline do
        local latestInstanceId = getZoneInstance()

        if isZoneTransitionActive() then
            logf("Instanced-zone activity detected via state: %s", describeZoneTransitionState())
            return INSTANCE_ACTIVITY_TRANSITION, latestInstanceId
        end

        if IsAddonReady("SelectString") then
            log("SelectString detected after zoning; assuming instance switch.")
            return INSTANCE_ACTIVITY_SELECT_STRING, latestInstanceId
        end

        if latestInstanceId > 0 and latestInstanceId ~= startInstanceId then
            logf("Public instance changed during watch: %d -> %d", startInstanceId, latestInstanceId)
            return INSTANCE_ACTIVITY_CHANGED, latestInstanceId
        end

        sleep(INSTANCE_WATCH_POLL)
    end

    return INSTANCE_ACTIVITY_NONE, getZoneInstance()
end

local function HandleInstancedZoneActivity(activity, currentInstanceId)
    if activity == INSTANCE_ACTIVITY_TRANSITION then
        log("Instanced-zone transition active; waiting for completion.")
        if not WaitForTeleportCompletion(getCurrentTerritoryId(), ZONE_TIMEOUT, "instance-zone transition") then
            return false, "timed out waiting for instanced-zone transition to complete"
        end
        return true
    end

    if activity == INSTANCE_ACTIVITY_SELECT_STRING then
        if WaitForTeleportStart(getCurrentTerritoryId(), nil, TELEPORT_START_TIMEOUT, "instance switch") then
            if not WaitForTeleportCompletion(getCurrentTerritoryId(), ZONE_TIMEOUT, "instance switch") then
                return false, "timed out waiting for instance switch to complete"
            end
        else
            local endInstanceId = getZoneInstance()
            if endInstanceId > 0 and endInstanceId ~= currentInstanceId then
                logf("Instance switch completed without caught transition start: %d -> %d", currentInstanceId, endInstanceId)
            else
                return false, "instance switch prompt detected but no follow-up transition started"
            end
        end
        return true
    end

    if activity == INSTANCE_ACTIVITY_CHANGED then
        log("Instance changed without SelectString; confirming settled state.")
        if not WaitUntil(function()
            local latestInstanceId = getZoneInstance()
            return latestInstanceId > 0
                and latestInstanceId ~= currentInstanceId
                and isZoneTransitionComplete()
                and (not isZoneTransitionActive())
        end, 3.0, INSTANCE_WATCH_POLL, 0.5) then
            return false, "instance changed but zone did not settle in time"
        end
        return true
    end

    return true
end

local function WaitForInstancedZoneSettle(timeoutSec)
    timeoutSec = tonumber(timeoutSec) or INSTANCE_WATCH_TIMEOUT
    local initialInstanceId = getZoneInstance()

    if initialInstanceId <= 0 then
        return true
    end

    -- HTA can chain multiple steps here: teleport to the aetheryte, open SelectString,
    -- then perform the actual instance switch. Re-watch after each settle cycle.
    local currentInstanceId = initialInstanceId
    local sawAnyActivity = false

    for cycle = 1, 3 do
        local activity, activityInstanceId = WatchForInstancedZoneActivity(currentInstanceId, timeoutSec)

        if activity == INSTANCE_ACTIVITY_NONE then
            if not sawAnyActivity then
                verboseLogf("No instance-switch signal detected; continuing in instance %d.", currentInstanceId)
            else
                logf("Instanced-zone activity settled; continuing in instance %d.", currentInstanceId)
            end
            return true
        end

        sawAnyActivity = true

        local ok, reason = HandleInstancedZoneActivity(activity, currentInstanceId)
        if not ok then
            return false, reason
        end

        local settledInstanceId = getZoneInstance()
        logf("Public instance after settle cycle %d: %d -> %d", cycle, currentInstanceId, settledInstanceId)
        currentInstanceId = settledInstanceId > 0 and settledInstanceId or activityInstanceId or currentInstanceId
    end

    logf("Public instance after settle: %d -> %d", initialInstanceId, getZoneInstance())
    return true
end

local function DistanceBetweenFlat(a, b)
    if not (a and b) then
        return math.huge
    end

    local dx = a.X - b.X
    local dz = a.Z - b.Z
    return math.sqrt((dx * dx) + (dz * dz))
end

local function GetAetherytesInTerritory(territoryId)
    local results = {}
    if territoryId == nil or not (Svc and Svc.AetheryteList) then
        return results
    end

    for _, aetheryte in ipairs(Svc.AetheryteList) do
        if tonumber(aetheryte.TerritoryId) == tonumber(territoryId) then
            table.insert(results, aetheryte)
        end
    end

    return results
end

local function GetAetheryteName(aetheryte)
    if aetheryte == nil then
        return nil
    end

    local data = aetheryte.AetheryteData
    local value = data and data.Value
    local placeName = value and value.PlaceName
    local placeValue = placeName and placeName.Value
    local name = placeValue and placeValue.Name

    if name and name.GetText then
        local ok, text = pcall(function()
            return name:GetText()
        end)
        if ok and text and text ~= "" then
            return tostring(text)
        end
    end

    return tostring(name or "")
end

local function BuildTerritoryAetheryteList(territoryId)
    local results = {}
    if territoryId == nil or not (Instances and Instances.Telepo and Instances.Telepo.GetAetherytePosition) then
        return results
    end

    local aetherytes = GetAetherytesInTerritory(territoryId)
    for _, aetheryte in ipairs(aetherytes) do
        local aetheryteId = tonumber(aetheryte.AetheryteId)
        local name = GetAetheryteName(aetheryte)
        if aetheryteId ~= nil and name ~= nil and name ~= "" then
            local ok, position = pcall(function()
                return Instances.Telepo:GetAetherytePosition(aetheryteId)
            end)
            if ok and position ~= nil then
                table.insert(results, {
                    aetheryteId = aetheryteId,
                    aetheryteName = name,
                    position = position,
                })
            end
        end
    end

    return results
end

local function ChooseClosestAetheryte(position, territoryId)
    local aetherytes = BuildTerritoryAetheryteList(territoryId)
    local closestAetheryte = nil
    local closestDistance = math.huge

    for _, aetheryte in ipairs(aetherytes) do
        local comparisonDistance = DistanceBetweenFlat(aetheryte.position, position)
        if comparisonDistance < closestDistance then
            closestDistance = comparisonDistance
            closestAetheryte = aetheryte
        end
    end

    return closestAetheryte, closestDistance
end

local function EvaluateAetheryteShortcut(flag)
    if flag == nil or flag.position == nil or flag.territoryId == nil then
        return nil
    end

    local playerPosition = getPlayerPosition()
    if playerPosition == nil then
        return nil
    end

    local playerDistance = DistanceBetweenFlat(playerPosition, flag.position)
    local closestAetheryte, aetheryteDistance = ChooseClosestAetheryte(flag.position, flag.territoryId)
    if closestAetheryte == nil or aetheryteDistance == nil then
        return {
            shouldTeleport = false,
            reason = "no_aetheryte",
        }
    end

    -- Compare estimated direct flight time against teleport/load/remount time.
    local playerTravelTime = playerDistance / FLIGHT_SPEED
    local aetheryteTravelTime = (aetheryteDistance / FLIGHT_SPEED) + TELEPORT_PENALTY
    local timeSavings = playerTravelTime - aetheryteTravelTime

    return {
        shouldTeleport = timeSavings >= MINIMUM_TELEPORT_SAVINGS,
        reason = timeSavings >= MINIMUM_TELEPORT_SAVINGS and "teleport" or "insufficient_savings",
        aetheryte = closestAetheryte,
        playerDistance = playerDistance,
        aetheryteDistance = aetheryteDistance,
        playerTravelTime = playerTravelTime,
        aetheryteTravelTime = aetheryteTravelTime,
        timeSavings = timeSavings,
    }
end

local function TeleportToAetheryte(aetheryte)
    if not aetheryte or not aetheryte.aetheryteId then
        return false
    end

    local startTerritoryId = getCurrentTerritoryId()

    if IPC and IPC.Lifestream and IPC.Lifestream.Teleport then
        logf("Attempting Lifestream teleport to '%s' (id=%s).", tostring(aetheryte.aetheryteName), tostring(aetheryte.aetheryteId))
        local ok = pcall(function()
            IPC.Lifestream.Teleport(aetheryte.aetheryteId, 0)
        end)
        if ok then
            if WaitForTeleportStart(startTerritoryId, nil, TELEPORT_START_TIMEOUT, "Lifestream teleport") then
                return true
            end
            log("Lifestream teleport did not show activity before fallback.")
        else
            log("Lifestream teleport call failed; falling back to Actions.Teleport.")
        end
    else
        log("Lifestream teleport unavailable; using Actions.Teleport fallback.")
    end

    if Actions and Actions.Teleport then
        logf("Attempting Actions.Teleport to '%s' (id=%s).", tostring(aetheryte.aetheryteName), tostring(aetheryte.aetheryteId))
        local ok = pcall(function()
            Actions.Teleport(aetheryte.aetheryteId)
        end)
        if ok then
            return WaitForTeleportStart(startTerritoryId, nil, TELEPORT_START_TIMEOUT, "Actions.Teleport")
        end
        log("Actions.Teleport call failed.")
    end

    return false
end

local function MaybeTeleportCloserToFlag(flag)
    local choice = EvaluateAetheryteShortcut(flag)
    if choice == nil then
        return true
    end

    if choice.reason == "no_aetheryte" then
        logf("No eligible aetheryte shortcut found for territory %s.", tostring(flag.territoryId))
        return true
    end

    logf(
        "Direct %.2fs, best aetheryte '%s' %.2fs, savings %.2fs.",
        choice.playerTravelTime,
        tostring(choice.aetheryte.aetheryteName),
        choice.aetheryteTravelTime,
        choice.timeSavings
    )

    if not choice.shouldTeleport then
        logf("Skipping aetheryte teleport because it saves less than %.2fs.", MINIMUM_TELEPORT_SAVINGS)
        return true
    end

    logf("Teleporting to closer aetheryte '%s'.", tostring(choice.aetheryte.aetheryteName))
    if not TeleportToAetheryte(choice.aetheryte) then
        return false, string.format("failed to start teleport to aetheryte '%s'", tostring(choice.aetheryte.aetheryteName))
    end

    if not WaitForTeleportCompletion(flag.territoryId, ZONE_TIMEOUT, "aetheryte teleport") then
        return false, string.format("timed out waiting for teleport to aetheryte '%s'", tostring(choice.aetheryte.aetheryteName))
    end

    return true
end

local function WaitForMountStable(stabilitySeconds, timeoutSeconds)
    stabilitySeconds = tonumber(stabilitySeconds) or 1.0
    timeoutSeconds = tonumber(timeoutSeconds) or MOUNT_TIMEOUT
    local stableStart = nil
    local deadline = os.clock() + timeoutSeconds

    while os.clock() < deadline do
        if isMounted() and (not isMounting()) then
            if stableStart == nil then
                stableStart = os.clock()
            elseif (os.clock() - stableStart) >= stabilitySeconds then
                return true
            end
        else
            stableStart = nil
        end

        sleep(POLL_INTERVAL)
    end

    return false
end

local function executeGeneralAction(id)
    if not (Actions and Actions.ExecuteGeneralAction) then
        return false
    end

    local ok = pcall(function()
        Actions.ExecuteGeneralAction(id)
    end)

    return ok
end

local function EnsureMounted(timeoutSec)
    timeoutSec = tonumber(timeoutSec) or MOUNT_TIMEOUT
    local deadline = os.clock() + timeoutSec
    local lastMountAttemptAt = -math.huge

    logf("Ensuring mounted state for up to %.2fs.", timeoutSec)

    while os.clock() < deadline do
        if isMounted() and (not isMounting()) then
            log("Mount state detected; verifying stability.")
            return WaitForMountStable(1.0, math.max(POLL_INTERVAL, deadline - os.clock()))
        end

        if not isMounted() and not isMounting() then
            if (os.clock() - lastMountAttemptAt) >= MOUNT_RETRY_COOLDOWN then
                log("Mount not active; using general action 24.")
                executeGeneralAction(24)
                lastMountAttemptAt = os.clock()
            end
        else
            verboseLog("Mount transition active; waiting for completion.")
        end

        sleep(POLL_INTERVAL)
    end

    log("Mount attempt timed out.")
    return false
end

local function EnsureDismounted(timeoutSec)
    timeoutSec = tonumber(timeoutSec) or MOUNT_TIMEOUT
    local deadline = os.clock() + timeoutSec

    logf("Ensuring dismounted state for up to %.2fs.", timeoutSec)

    while os.clock() < deadline do
        if not isMounted() and not isMounting() then
            log("Dismount confirmed.")
            return true
        end

        verboseLog("Still mounted or mounting; using general action 23.")
        executeGeneralAction(23)
        sleep(POLL_INTERVAL)
    end

    log("Dismount attempt timed out.")
    return false
end

local function DistanceTo3D(position)
    if not (position and Entity and Entity.Player and Entity.Player.Position) then
        return math.huge
    end

    return Vector3.Distance(Entity.Player.Position, position)
end

local function DistanceToFlat(position)
    local playerPosition = getPlayerPosition()
    if not (position and playerPosition) then
        return math.huge
    end

    local dx = playerPosition.X - position.X
    local dz = playerPosition.Z - position.Z
    return math.sqrt((dx * dx) + (dz * dz))
end

local function GetPlayerHitboxRadius()
    local ok, radius = pcall(function()
        return Svc and Svc.ClientState and Svc.ClientState.LocalPlayer and Svc.ClientState.LocalPlayer.HitboxRadius
    end)

    radius = ok and tonumber(radius) or nil
    return radius or 0
end

local function GetCurrentTargetHitboxRadius()
    local ok, radius = pcall(function()
        return Svc and Svc.Targets and Svc.Targets.Target and Svc.Targets.Target.HitboxRadius
    end)

    radius = ok and tonumber(radius) or nil
    return radius
end

local GetEntityHitboxRadius

local function GetDistanceToHuntWaitThreshold(currentEntity, huntTargeted)
    local centerDistance = DistanceTo3D(currentEntity.Position)
    local playerRadius = GetPlayerHitboxRadius()
    local entityRadius = GetEntityHitboxRadius(currentEntity)
    local flatEdgeDistance = math.max(0, DistanceToFlat(currentEntity.Position) - entityRadius - playerRadius)

    if not huntTargeted then
        return flatEdgeDistance
    end

    local targetRadius = GetCurrentTargetHitboxRadius()
    if not targetRadius then
        targetRadius = entityRadius
    end

    return math.max(0, centerDistance - targetRadius - playerRadius)
end

local function IsVnavMovementActive()
    if not (IPC and IPC.vnavmesh) then
        return false
    end

    if IPC.vnavmesh.PathfindInProgress then
        local okPath, pathing = pcall(IPC.vnavmesh.PathfindInProgress)
        if okPath and pathing == true then
            return true
        end
    end

    if IPC.vnavmesh.IsRunning then
        local okRun, running = pcall(IPC.vnavmesh.IsRunning)
        if okRun and running == true then
            return true
        end
    end

    return false
end

local function IsPlayerMoving()
    local okMoving, movingValue = pcall(function()
        return Player and Player.IsMoving
    end)
    return okMoving and movingValue == true
end

local function isBattleNpcType(typeText)
    return string.find(tostring(typeText or ""), "BattleNpc", 1, true) == 1
end

local function StopVnav()
    if not (IPC and IPC.vnavmesh) then
        return
    end

    local shouldStop = false

    if IPC.vnavmesh.PathfindInProgress then
        local ok, active = pcall(IPC.vnavmesh.PathfindInProgress)
        if ok and active then
            shouldStop = true
        end
    end

    if not shouldStop and IPC.vnavmesh.IsRunning then
        local ok, running = pcall(IPC.vnavmesh.IsRunning)
        if ok and running then
            shouldStop = true
        end
    end

    if not shouldStop and IPC.vnavmesh.BuildProgress then
        local ok, progress = pcall(IPC.vnavmesh.BuildProgress)
        if ok and tonumber(progress) and tonumber(progress) > 0 then
            shouldStop = true
        end
    end

    if shouldStop and IPC.vnavmesh.Stop then
        pcall(IPC.vnavmesh.Stop)
    end
end

local function ResetMovementBeforeStart()
    StopVnav()
    sleep(POLL_INTERVAL)
end

local function normalizeDestination(position)
    if position == nil then
        return nil
    end

    local floorPoint = nil
    local ok = pcall(function()
        if IPC and IPC.vnavmesh and IPC.vnavmesh.PointOnFloor then
            floorPoint = IPC.vnavmesh.PointOnFloor(position, true, 10)
        end
    end)
    if ok and floorPoint ~= nil then
        return floorPoint
    end

    return position
end

local function TryProjectPointToFloor(position)
    if position == nil then
        return nil
    end

    if IPC and IPC.vnavmesh and IPC.vnavmesh.PointOnFloor then
        local ok, floorPoint = pcall(function()
            return IPC.vnavmesh.PointOnFloor(position, true, 10)
        end)
        if ok and floorPoint ~= nil then
            return floorPoint
        end
    end

    return nil
end

function GetEntityHitboxRadius(entity)
    local radius = entity and tonumber(entity.HitboxRadius) or nil
    return radius or 0
end

local function GetSafeHuntApproachBounds(huntEntity)
    local targetRadius = GetEntityHitboxRadius(huntEntity)
    local playerRadius = GetPlayerHitboxRadius()
    local minimumRadius = math.max(8, targetRadius + playerRadius + SAFE_HUNT_MIN_BUFFER)
    local maximumRadius = math.max(minimumRadius, HUNT_WAIT_DISTANCE - 2)
    local preferredRadius = maximumRadius
    return minimumRadius, maximumRadius, preferredRadius
end

local function GetFlatAngle(fromPosition, toPosition)
    local dx = (toPosition.X or 0) - (fromPosition.X or 0)
    local dz = (toPosition.Z or 0) - (fromPosition.Z or 0)

    if dx == 0 then
        if dz >= 0 then
            return math.pi / 2
        end
        return -math.pi / 2
    end

    local angle = math.atan(dz / dx)
    if dx < 0 then
        angle = angle + math.pi
    end

    return angle
end

local function EvaluateSafeHuntApproachPoint(candidate, huntPosition, minimumRadius, maximumRadius)
    if candidate == nil or huntPosition == nil then
        return false, "projection_failed", nil, nil
    end

    local flatDistance = DistanceBetweenFlat(candidate, huntPosition)
    if flatDistance < minimumRadius or flatDistance > maximumRadius then
        return false, "out_of_radius", flatDistance, nil
    end

    local verticalDelta = math.abs((candidate.Y or 0) - (huntPosition.Y or 0))
    if verticalDelta > SAFE_HUNT_VERTICAL_TOLERANCE then
        return false, "vertical_delta", flatDistance, verticalDelta
    end

    return true, nil, flatDistance, verticalDelta
end

local function EvaluateProjectedHuntApproachPoint(requestedPoint, projectedPoint, huntPosition, minimumRadius, maximumRadius)
    local valid, rejectReason, flatDistance, verticalDelta = EvaluateSafeHuntApproachPoint(projectedPoint, huntPosition, minimumRadius, maximumRadius)
    if not valid then
        return valid, rejectReason, flatDistance, verticalDelta, nil
    end

    local projectionDrift = DistanceBetweenFlat(projectedPoint, requestedPoint)
    if projectionDrift > SAFE_HUNT_MAX_PROJECTION_DRIFT then
        return false, "projection_drift", flatDistance, verticalDelta, projectionDrift
    end

    return true, nil, flatDistance, verticalDelta, projectionDrift
end

local function BuildHuntApproachCandidateLabel(baseLabel, angleOffsetDegrees)
    if angleOffsetDegrees == 0 then
        return baseLabel
    end

    local direction = angleOffsetDegrees > 0 and "left" or "right"
    return string.format("%s-%s-%d", baseLabel, direction, math.abs(angleOffsetDegrees))
end

local function BuildHuntApproachCandidatePoint(huntPosition, baseAngle, radius, angleOffsetDegrees)
    local angle = baseAngle + math.rad(angleOffsetDegrees)
    return Vector3(
        huntPosition.X + (math.cos(angle) * radius),
        huntPosition.Y,
        huntPosition.Z + (math.sin(angle) * radius)
    )
end

local TryProjectPointToFloorWithRescue

local function BuildOrderedHuntApproachCandidates(minimumRadius, maximumRadius, preferredRadius)
    return {
        { label = "player-facing", radius = preferredRadius, angleOffsetDegrees = 0 },
        { label = "player-facing", radius = preferredRadius, angleOffsetDegrees = 30 },
        { label = "player-facing", radius = preferredRadius, angleOffsetDegrees = -30 },
        { label = "player-facing-tight", radius = minimumRadius, angleOffsetDegrees = 0 },
    }
end

local function GetProjectionRescueOffsets()
    local nudge = SAFE_HUNT_PROJECTION_RESCUE_NUDGE
    return {
        { label = "center", x = 0, z = 0 },
        { label = "east", x = nudge, z = 0 },
        { label = "west", x = -nudge, z = 0 },
        { label = "south", x = 0, z = nudge },
        { label = "north", x = 0, z = -nudge },
        { label = "south-east", x = nudge, z = nudge },
        { label = "south-west", x = -nudge, z = nudge },
        { label = "north-east", x = nudge, z = -nudge },
        { label = "north-west", x = -nudge, z = -nudge },
    }
end

local function LogRejectedHuntApproachCandidate(candidateIndex, huntName, rejectReason, flatDistance, minimumRadius, maximumRadius, verticalDelta, projectionDrift)
    if rejectReason == "projection_failed" then
        verboseLogf("Candidate %d for '%s' rejected: projection_failed.", candidateIndex, tostring(huntName))
        return
    end

    if rejectReason == "projection_drift" then
        verboseLogf(
            "Candidate %d for '%s' rejected: projection_drift=%.2f > %.2f.",
            candidateIndex,
            tostring(huntName),
            tonumber(projectionDrift) or -1,
            SAFE_HUNT_MAX_PROJECTION_DRIFT
        )
        return
    end

    if rejectReason == "out_of_radius" then
        verboseLogf(
            "Candidate %d for '%s' rejected: out_of_radius (flat=%.2f, allowed %.2f-%.2f).",
            candidateIndex,
            tostring(huntName),
            tonumber(flatDistance) or -1,
            minimumRadius,
            maximumRadius
        )
        return
    end

    if rejectReason == "vertical_delta" then
        verboseLogf(
            "Candidate %d for '%s' rejected: vertical_delta=%.2f > %.2f.",
            candidateIndex,
            tostring(huntName),
            tonumber(verticalDelta) or -1,
            SAFE_HUNT_VERTICAL_TOLERANCE
        )
    end
end

local function SummarizeHuntApproachRejections(rejectedCounts)
    return string.format(
        "projection_failed=%d, projection_drift=%d, out_of_radius=%d, vertical_delta=%d",
        rejectedCounts.projection_failed or 0,
        rejectedCounts.projection_drift or 0,
        rejectedCounts.out_of_radius or 0,
        rejectedCounts.vertical_delta or 0
    )
end

TryProjectPointToFloorWithRescue = function(candidateIndex, huntName, requestedPoint)
    local offsets = GetProjectionRescueOffsets()

    for rescueIndex, offset in ipairs(offsets) do
        local probePoint = requestedPoint
        if offset.x ~= 0 or offset.z ~= 0 then
            probePoint = Vector3(
                requestedPoint.X + offset.x,
                requestedPoint.Y,
                requestedPoint.Z + offset.z
            )
        end

        local projectedPoint = TryProjectPointToFloor(probePoint)
        if projectedPoint ~= nil then
            verboseLogf(
                "Candidate %d for '%s' projected via %s rescue probe %d at (%.2f, %.2f, %.2f).",
                candidateIndex,
                tostring(huntName),
                tostring(offset.label),
                rescueIndex,
                probePoint.X,
                probePoint.Y,
                probePoint.Z
            )
            return projectedPoint, offset.label
        end
    end

    return nil, nil
end

local function BuildSafeHuntApproachPoint(huntEntity, selectionReason)
    local huntPosition = huntEntity and huntEntity.Position or nil
    local playerPosition = getPlayerPosition()
    local huntName = tostring(huntEntity and huntEntity.Name or "Unknown Hunt")
    local selectionLabel = tostring(selectionReason or "initial")
    if huntPosition == nil or playerPosition == nil then
        return nil, "hunt or player position unavailable"
    end

    local minimumRadius, maximumRadius, preferredRadius = GetSafeHuntApproachBounds(huntEntity)
    local baseAngle = GetFlatAngle(huntPosition, playerPosition)
    local candidates = BuildOrderedHuntApproachCandidates(minimumRadius, maximumRadius, preferredRadius)
    local rejectedCounts = {
        projection_failed = 0,
        projection_drift = 0,
        out_of_radius = 0,
        vertical_delta = 0,
    }

    logf("Selecting hunt approach point for '%s' (%s).", tostring(huntName), selectionLabel)
    verboseLogf(
        "Approach bounds for '%s': min=%.2f max=%.2f preferred=%.2f.",
        tostring(huntName),
        minimumRadius,
        maximumRadius,
        preferredRadius
    )
    verboseLogf(
        "Approach inputs for '%s': player=(%.2f, %.2f, %.2f) hunt=(%.2f, %.2f, %.2f) baseAngle=%.2f.",
        tostring(huntName),
        playerPosition.X,
        playerPosition.Y,
        playerPosition.Z,
        huntPosition.X,
        huntPosition.Y,
        huntPosition.Z,
        math.deg(baseAngle)
    )

    for candidateIndex, candidate in ipairs(candidates) do
        local requestedPoint = BuildHuntApproachCandidatePoint(huntPosition, baseAngle, candidate.radius, candidate.angleOffsetDegrees)
        verboseLogf(
            "Candidate %d for '%s': label=%s radius=%.2f angleOffset=%d requested=(%.2f, %.2f, %.2f).",
            candidateIndex,
            tostring(huntName),
            BuildHuntApproachCandidateLabel(candidate.label, candidate.angleOffsetDegrees),
            candidate.radius,
            candidate.angleOffsetDegrees,
            requestedPoint.X,
            requestedPoint.Y,
            requestedPoint.Z
        )

        local projectedPoint, rescueLabel = TryProjectPointToFloorWithRescue(candidateIndex, huntName, requestedPoint)
        local valid, rejectReason, flatDistance, verticalDelta, projectionDrift = EvaluateProjectedHuntApproachPoint(requestedPoint, projectedPoint, huntPosition, minimumRadius, maximumRadius)
        if valid then
            logf(
                "Selected %s hunt approach for '%s': radius=%.2f angleOffset=%d at %.2f, %.2f, %.2f%s (drift=%.2f).",
                BuildHuntApproachCandidateLabel(candidate.label, candidate.angleOffsetDegrees),
                tostring(huntName),
                candidate.radius,
                candidate.angleOffsetDegrees,
                projectedPoint.X,
                projectedPoint.Y,
                projectedPoint.Z,
                rescueLabel ~= nil and string.format(" via %s projection rescue", tostring(rescueLabel)) or "",
                tonumber(projectionDrift) or 0
            )
            return projectedPoint, nil, {
                label = BuildHuntApproachCandidateLabel(candidate.label, candidate.angleOffsetDegrees),
                radius = candidate.radius,
                angleOffsetDegrees = candidate.angleOffsetDegrees,
                projectionDrift = projectionDrift,
                projectionMode = rescueLabel ~= nil and string.format("projected-%s", tostring(rescueLabel)) or "projected",
                selectionReason = selectionLabel,
            }
        end

        if rejectReason ~= nil then
            rejectedCounts[rejectReason] = (rejectedCounts[rejectReason] or 0) + 1
        end
        LogRejectedHuntApproachCandidate(candidateIndex, huntName, rejectReason, flatDistance, minimumRadius, maximumRadius, verticalDelta, projectionDrift)
    end

    logf(
        "Projected safe offset selection failed for '%s' within %.2f-%.2f yalms (%s).",
        tostring(huntName),
        minimumRadius,
        maximumRadius,
        SummarizeHuntApproachRejections(rejectedCounts)
    )

    for candidateIndex, candidate in ipairs(candidates) do
        local requestedPoint = BuildHuntApproachCandidatePoint(huntPosition, baseAngle, candidate.radius, candidate.angleOffsetDegrees)
        local valid, rejectReason, flatDistance, verticalDelta = EvaluateSafeHuntApproachPoint(requestedPoint, huntPosition, minimumRadius, maximumRadius)
        if valid then
            logf(
                "Using raw %s hunt approach for '%s' at %.2f, %.2f, %.2f after projection failures.",
                BuildHuntApproachCandidateLabel(candidate.label, candidate.angleOffsetDegrees),
                tostring(huntName),
                requestedPoint.X,
                requestedPoint.Y,
                requestedPoint.Z
            )
            return requestedPoint, "projection failed; using raw safe offset fallback", {
                label = BuildHuntApproachCandidateLabel(candidate.label, candidate.angleOffsetDegrees),
                radius = candidate.radius,
                angleOffsetDegrees = candidate.angleOffsetDegrees,
                projectionMode = "unprojected",
                selectionReason = selectionLabel,
            }
        end

        verboseLogf(
            "Unprojected candidate %d for '%s' rejected: %s%s%s.",
            candidateIndex,
            tostring(huntName),
            tostring(rejectReason or "unknown"),
            flatDistance ~= nil and string.format(" flat=%.2f", flatDistance) or "",
            verticalDelta ~= nil and string.format(" vertical=%.2f", verticalDelta) or ""
        )
    end

    logf("Safe offset selection failed for '%s'; falling back to raw hunt position.", tostring(huntName))
    return huntPosition, "safe offset selection failed; using raw hunt position", {
        label = "raw-hunt-position",
        projectionMode = "raw",
        selectionReason = selectionLabel,
    }
end

local function BeginMoveTo(position)
    if not (IPC and IPC.vnavmesh and IPC.vnavmesh.IsReady and IPC.vnavmesh.PathfindAndMoveTo) then
        return false
    end

    ResetMovementBeforeStart()

    local ready = WaitUntil(function()
        return IPC.vnavmesh.IsReady()
    end, 15, POLL_INTERVAL, 0)

    if not ready then
        log("vnavmesh did not become ready in time.")
        return false
    end

    local playerPosition = getPlayerPosition()
    if playerPosition and math.abs((playerPosition.Y or 0) - (position.Y or 0)) >= 30 then
        logf(
            "Starting vnav movement toward %.2f, %.2f, %.2f with large Y delta from player %.2f.",
            position.X,
            position.Y,
            position.Z,
            playerPosition.Y
        )
    else
        logf("Starting vnav movement toward %.2f, %.2f, %.2f.", position.X, position.Y, position.Z)
    end

    local ok, started = pcall(function()
        return IPC.vnavmesh.PathfindAndMoveTo(position, true)
    end)

    return ok and started == true
end

local function WaitForVnavStart(timeoutSec)
    return WaitUntil(function()
        local running = false
        local pathing = false

        if IPC and IPC.vnavmesh and IPC.vnavmesh.IsRunning then
            local okRun, value = pcall(IPC.vnavmesh.IsRunning)
            running = okRun and value == true
        end

        if IPC and IPC.vnavmesh and IPC.vnavmesh.PathfindInProgress then
            local okPath, value = pcall(IPC.vnavmesh.PathfindInProgress)
            pathing = okPath and value == true
        end

        return running or pathing
    end, timeoutSec or 5, POLL_INTERVAL, 0)
end

local function DidMovementActuallyStart()
    local pathing = false
    local running = false
    local moving = false

    if IPC and IPC.vnavmesh and IPC.vnavmesh.PathfindInProgress then
        local okPath, value = pcall(IPC.vnavmesh.PathfindInProgress)
        pathing = okPath and value == true
    end

    if IPC and IPC.vnavmesh and IPC.vnavmesh.IsRunning then
        local okRun, value = pcall(IPC.vnavmesh.IsRunning)
        running = okRun and value == true
    end

    moving = IsPlayerMoving()

    return pathing or running or moving
end

local function WaitForConfirmedMovementStart(timeoutSec)
    return WaitUntil(function()
        return DidMovementActuallyStart()
    end, timeoutSec or FLAG_MOVEMENT_START_TIMEOUT, POLL_INTERVAL, 0)
end

local function BeginVnavCommand(command, startLogMessage, timeoutFailureMessage)
    ResetMovementBeforeStart()

    if startLogMessage ~= nil then
        log(startLogMessage)
    end

    yield(command)

    local started = WaitForVnavStart(5)
    if not started and timeoutFailureMessage ~= nil then
        log(timeoutFailureMessage)
    end

    return started
end

local function BeginFlyToFlag()
    if not (Instances and Instances.Map and Instances.Map.IsFlagMarkerSet) then
        log("Map flag is unavailable for /vnav flyflag.")
        return false
    end

    if not Instances.Map.IsFlagMarkerSet then
        log("No active map flag for /vnav flyflag.")
        return false
    end

    return BeginVnavCommand(
        "/vnav flyflag",
        "Starting vnav flyflag movement toward the current map flag.",
        "/vnav flyflag did not start in time."
    )
end

local function StartConfirmedFlagPathfind(flagDestination)
    if not BeginMoveTo(flagDestination) then
        return false, "failed to start direct pathfind to the flag"
    end

    if WaitForConfirmedMovementStart(FLAG_MOVEMENT_START_TIMEOUT) then
        return true, nil
    end

    StopVnav()
    return false, string.format("direct pathfind did not show movement within %.2fs", FLAG_MOVEMENT_START_TIMEOUT)
end

local function StartConfirmedFlagTravel(flagDestination)
    if BeginFlyToFlag() and WaitForConfirmedMovementStart(FLAG_MOVEMENT_START_TIMEOUT) then
        return true, nil
    end

    StopVnav()
    logf("No flyflag movement detected within %.2fs; falling back to direct pathfind.", FLAG_MOVEMENT_START_TIMEOUT)

    local started, reason = StartConfirmedFlagPathfind(flagDestination)
    if started then
        return true, nil
    end

    logf("%s; retrying once.", tostring(reason))
    started, reason = StartConfirmedFlagPathfind(flagDestination)
    if started then
        return true, nil
    end

    return false, string.format("second direct pathfind attempt did not show movement within %.2fs", FLAG_MOVEMENT_START_TIMEOUT)
end

local function BeginFlyToPosition(position)
    if position == nil then
        log("No destination available for /vnav flyto.")
        return false
    end

    return BeginVnavCommand(
        string.format("/vnav flyto %.3f %.3f %.3f", position.X, position.Y, position.Z),
        string.format("Starting vnav flyto movement toward %.2f, %.2f, %.2f.", position.X, position.Y, position.Z),
        "/vnav flyto did not start in time."
    )
end

local function StartConfirmedApproachPathfind(position)
    if not BeginMoveTo(position) then
        return false
    end

    if WaitForConfirmedMovementStart(FLAG_MOVEMENT_START_TIMEOUT) then
        return true
    end

    StopVnav()
    return false
end

local function StartApproachMovement(position)
    if position == nil then
        return false
    end

    if BeginFlyToPosition(position) and WaitForConfirmedMovementStart(FLAG_MOVEMENT_START_TIMEOUT) then
        return true
    end

    StopVnav()

    log("/vnav flyto did not start; falling back to grounded pathfind for hunt approach.")
    return StartConfirmedApproachPathfind(position)
end

local function IsLiveHuntEntity(entity)
    return entity ~= nil
        and entity.Position ~= nil
        and isBattleNpcType(entity.Type)
        and tonumber(entity.CurrentHp) ~= nil
        and tonumber(entity.CurrentHp) > 0
        and tonumber(entity.HuntRank) ~= nil
        and tonumber(entity.HuntRank) > 0
end

local function GetCurrentTargetEntity()
    if Entity and Entity.Target then
        return Entity.Target
    end

    return nil
end

local function WaitForStartupTargetHuntToDie(targetHunt)
    local huntName = tostring(targetHunt and targetHunt.Name or "Unknown Hunt")

    logf("Player already targeting hunt '%s'; waiting for it to die before moving to distant flag.", tostring(huntName))

    local misses = 0
    local waitStart = os.clock()
    local nextHeartbeatAt = waitStart + STARTUP_HUNT_HEARTBEAT_INTERVAL

    while true do
        local currentEntity = nil
        local currentOk = pcall(function()
            currentEntity = Entity.GetEntityByName and Entity.GetEntityByName(huntName) or nil
        end)

        if currentOk and IsLiveHuntEntity(currentEntity) then
            misses = 0

            local now = os.clock()
            if now >= nextHeartbeatAt then
                logf(
                    "Startup hunt '%s' still alive after %.1fs; waiting.",
                    tostring(huntName),
                    now - waitStart
                )
                nextHeartbeatAt = now + STARTUP_HUNT_HEARTBEAT_INTERVAL
            end

            sleep(POLL_INTERVAL)
        else
            misses = misses + 1
            if misses >= STARTUP_HUNT_MISS_THRESHOLD then
                logf(
                    "Startup hunt '%s' is gone or dead after %.1fs; resuming next-flag travel.",
                    tostring(huntName),
                    os.clock() - waitStart
                )
                return
            end

            sleep(POLL_INTERVAL)
        end
    end
end

local function RefreshCurrentFlagAfterStartupWait(originalFlag)
    log("Startup hunt handling complete; rechecking current flag.")

    local refreshedFlag, flagErr = WaitForCurrentFlag(FLAG_ACQUIRE_TIMEOUT)
    if not refreshedFlag then
        logf("Flag recheck failed after startup hunt handling; keeping original flag (%s).", tostring(flagErr))
        return originalFlag
    end

    if refreshedFlag.territoryId ~= originalFlag.territoryId or DistanceBetweenFlat(refreshedFlag.position, originalFlag.position) > 1 then
        logf(
            "Flag changed during startup hunt handling; updating target to territory %d at %.2f, %.2f, %.2f.",
            refreshedFlag.territoryId,
            refreshedFlag.position.X,
            refreshedFlag.position.Y,
            refreshedFlag.position.Z
        )
        return refreshedFlag
    end

    log("Flag unchanged after startup hunt handling; continuing to current target flag.")
    return refreshedFlag
end

local function HandleStartupTargetHunt(flag)
    local currentTarget = GetCurrentTargetEntity()
    if not IsLiveHuntEntity(currentTarget) then
        return true, flag
    end

    local currentFlagDistance = DistanceToFlat(flag.position)
    local huntName = tostring(currentTarget.Name or "Unknown Hunt")

    if currentFlagDistance <= STARTUP_REPEAT_CALL_DISTANCE then
        logf(
            "Current target is live hunt '%s' and flag is within %.2f yalms; treating this as a repeat call.",
            tostring(huntName),
            STARTUP_REPEAT_CALL_DISTANCE
        )
        return false, "repeat call on current hunt"
    end

    logf(
        "Current target is live hunt '%s' and flag is %.2f yalms away; waiting for current hunt to die before moving on.",
        tostring(huntName),
        currentFlagDistance
    )
    WaitForStartupTargetHuntToDie(currentTarget)
    return true, RefreshCurrentFlagAfterStartupWait(flag)
end

local function FindNearestLiveHuntEntity(flagPosition)
    if not (Svc and Svc.Objects and Entity) then
        return nil
    end

    local nearestEntity = nil
    local nearestDistance = math.huge

    for i = 0, Svc.Objects.Length - 1 do
        local ok, entity = pcall(function()
            return Entity[i]
        end)
        if ok and IsLiveHuntEntity(entity) then
            local distance = DistanceBetweenFlat(entity.Position, flagPosition)
            if distance < nearestDistance then
                nearestDistance = distance
                nearestEntity = entity
            end
        end
    end

    return nearestEntity
end

local function TargetHuntEntityIfClose(huntName, maxDistance)
    if not huntName or not (Entity and Entity.GetEntityByName) then
        return false
    end

    local currentTargetName = nil
    pcall(function()
        if Svc and Svc.Targets and Svc.Targets.Target and Svc.Targets.Target.Name then
            currentTargetName = Svc.Targets.Target.Name:GetText()
        end
    end)

    if currentTargetName == huntName then
        return true
    end

    local ok, entity = pcall(function()
        return Entity.GetEntityByName(huntName)
    end)
    if not ok or not entity or not entity.Position then
        return false
    end

    local distance = DistanceToFlat(entity.Position)
    if distance > (tonumber(maxDistance) or HUNT_TARGET_DISTANCE) then
        return false
    end

    if entity.IsTargetable ~= true then
        return false
    end

    logf("Attempting to target hunt '%s' at %.2f yalms.", tostring(huntName), distance)

    if entity.SetAsTarget then
        local targeted = pcall(function()
            entity:SetAsTarget()
        end)
        if targeted then
            sleep(0.1)

            currentTargetName = nil
            local okTargetName = pcall(function()
                if Svc and Svc.Targets and Svc.Targets.Target and Svc.Targets.Target.Name then
                    currentTargetName = Svc.Targets.Target.Name:GetText()
                end
            end)

            if okTargetName and currentTargetName == huntName then
                logf("Targeted hunt '%s' at %.2f yalms.", tostring(huntName), distance)
                return true
            end

            logf(
                "Target attempt did not stick for hunt '%s' (current target: %s).",
                tostring(huntName),
                tostring(currentTargetName)
            )
            return false
        end

        logf("SetAsTarget call failed for hunt '%s'.", tostring(huntName))
    end

    logf("Unable to target hunt '%s' while in range.", tostring(huntName))
    return false
end

local function getCurrentFlag()
    if not (Instances and Instances.Map and Instances.Map.IsFlagMarkerSet and Instances.Map.Flag) then
        return nil, "map flag API unavailable"
    end

    if not Instances.Map.IsFlagMarkerSet then
        return nil, "no map flag is currently set"
    end

    local flag = Instances.Map.Flag
    local territoryId = tonumber(flag.TerritoryId)
    local position = flag.Vector3 or Vector3(flag.XFloat, 0, flag.YFloat)

    if territoryId == nil or position == nil then
        return nil, "flag details unavailable"
    end

    return {
        territoryId = territoryId,
        position = position,
    }
end

local function WaitForCurrentFlag(timeoutSec)
    timeoutSec = tonumber(timeoutSec) or FLAG_ACQUIRE_TIMEOUT
    local deadline = os.clock() + timeoutSec
    local announcedWait = false

    while os.clock() < deadline do
        local flag = nil
        local ok = pcall(function()
            flag = getCurrentFlag()
        end)

        if ok and flag ~= nil then
            logf("Flag detected after %.2fs.", timeoutSec - math.max(0, deadline - os.clock()))
            return flag
        end

        if not announcedWait then
            logf("Waiting up to %.2fs for HTA-provided map flag.", timeoutSec)
            announcedWait = true
        end

        sleep(POLL_INTERVAL)
    end

    return nil, string.format("no readable map flag detected within %.2fs", timeoutSec)
end

local function WaitForStartupSettle(timeoutSec)
    timeoutSec = tonumber(timeoutSec) or 5

    if not isZoneTransitionActive() and isZoneTransitionComplete() then
        return true
    end

    log("Startup transition active; waiting to settle.")
    local ok = WaitForZoneCompletion(getCurrentTerritoryId(), timeoutSec, false)
    if ok then
        log("Startup settle complete.")
    end
    return ok
end

local function CreateHuntRuntime(flagDestination)
    return {
        flagDestination = flagDestination,
        bestDistance = math.huge,
        lastProgressAt = os.clock(),
        huntScanActivated = false,
        -- Once true, flag-complete fallback should never win again this run.
        huntCommitted = false,
        -- True only after an actual target lock on the chosen hunt.
        huntTargeted = false,
        chasedHuntName = nil,
        huntAutorotationApplied = false,
        huntEngagedStartTime = os.clock(),
        huntApproachPoint = nil,
        huntApproachRepathCount = 0,
        huntApproachStartTime = os.clock(),
        huntApproachGraceUntil = os.clock(),
        huntRetryExhaustedLogged = false,
        detectedHuntName = nil,
        waitingForHuntDamage = false,
        dismountedForHandoff = false,
        state = nil,
    }
end

local function StartFlagTravel(runtime)
    local started, reason = StartConfirmedFlagTravel(runtime.flagDestination)
    if not started then
        return false, reason
    end

    return true
end

local function UpdateFlagProgress(runtime)
    local currentFlagDistance = DistanceToFlat(runtime.flagDestination)
    if currentFlagDistance + 0.5 < runtime.bestDistance then
        runtime.bestDistance = currentFlagDistance
        runtime.lastProgressAt = os.clock()
    end

    if not runtime.huntScanActivated and currentFlagDistance <= HUNT_SCAN_START_DISTANCE then
        runtime.huntScanActivated = true
        logf("Entered hunt scan range within %.2f yalms of the flag.", HUNT_SCAN_START_DISTANCE)
    end

    return currentFlagDistance
end

local function ResumeFlagTravel(runtime)
    local started, reason = StartConfirmedFlagTravel(runtime.flagDestination)
    if not started then
        return false, string.format("failed to resume movement to flag after losing hunt '%s': %s", tostring(runtime.chasedHuntName), tostring(reason))
    end

    local lostHuntName = runtime.chasedHuntName

    -- Keep huntCommitted sticky so flag-only completion cannot win later in this run.
    runtime.chasedHuntName = nil
    runtime.detectedHuntName = nil
    runtime.huntTargeted = false
    runtime.huntAutorotationApplied = false
    runtime.huntEngagedStartTime = os.clock()
    runtime.huntApproachPoint = nil
    runtime.huntApproachRepathCount = 0
    runtime.huntApproachStartTime = os.clock()
    runtime.huntApproachGraceUntil = os.clock()
    runtime.huntRetryExhaustedLogged = false
    runtime.bestDistance = math.huge
    runtime.lastProgressAt = os.clock()
    runtime.waitingForHuntDamage = false
    runtime.dismountedForHandoff = false
    SetRuntimeState(runtime, STATE_TRAVEL_TO_FLAG, "resuming flag travel after losing hunt '%s'.", tostring(lostHuntName))
    return true
end

local function LogDetectedHunt(runtime, huntEntity)
    local huntName = tostring(huntEntity.Name or "Unknown Hunt")
    if runtime.detectedHuntName ~= huntName then
        logf("Found hunt entity '%s' at %.2f, %.2f, %.2f.", tostring(huntName), huntEntity.Position.X, huntEntity.Position.Y, huntEntity.Position.Z)
        runtime.detectedHuntName = huntName
    end
    return huntName
end

local function TryTargetDetectedHunt(huntName)
    return TargetHuntEntityIfClose(huntName, HUNT_TARGET_DISTANCE)
end

local function StartHuntApproach(runtime, huntEntity, targetedNow)
    local huntName = tostring(huntEntity.Name or "Unknown Hunt")
    local approachPoint, approachReason, approachMeta = BuildSafeHuntApproachPoint(huntEntity, "initial")
    local movePoint = approachPoint or huntEntity.Position

    if approachPoint ~= nil then
        logf(
            "Using %s hunt approach point for '%s' at %.2f, %.2f, %.2f.",
            tostring(approachMeta and approachMeta.label or "validated"),
            tostring(huntName),
            movePoint.X,
            movePoint.Y,
            movePoint.Z
        )
    else
        logf("No validated hunt approach point found for '%s'; using raw hunt position.", tostring(huntName))
    end

    if approachReason ~= nil then
        logf("Hunt approach note for '%s': %s", tostring(huntName), tostring(approachReason))
    end

    if not StartApproachMovement(movePoint) then
        if targetedNow then
            return false, string.format("failed to start approach movement for targeted hunt '%s'", tostring(huntName))
        end
        return false, string.format("failed to start approach movement for hunt '%s'", tostring(huntName))
    end

    runtime.huntCommitted = true
    runtime.chasedHuntName = huntName
    runtime.huntAutorotationApplied = false
    runtime.huntEngagedStartTime = os.clock()
    runtime.huntApproachPoint = approachPoint
    runtime.huntApproachRepathCount = 0
    runtime.huntApproachStartTime = os.clock()
    runtime.huntApproachGraceUntil = os.clock() + SAFE_HUNT_STALL_GRACE_AFTER_START
    runtime.huntRetryExhaustedLogged = false
    runtime.bestDistance = math.huge
    runtime.lastProgressAt = os.clock()
    if targetedNow then
        runtime.huntTargeted = true
        SetRuntimeState(runtime, STATE_SAFE_HUNT_APPROACH, "targeted hunt '%s'; closing to handoff range.", tostring(huntName))
    else
        SetRuntimeState(runtime, STATE_SAFE_HUNT_APPROACH, "detected hunt '%s'; closing to handoff range.", tostring(huntName))
    end

    return true
end

local function TryReacquireChasedHunt(runtime)
    local currentEntity = nil
    local currentOk = pcall(function()
        currentEntity = Entity.GetEntityByName and Entity.GetEntityByName(runtime.chasedHuntName) or nil
    end)

    if not currentOk or not IsLiveHuntEntity(currentEntity) then
        return nil
    end

    return currentEntity
end

local function HandleLostChasedHunt(runtime)
    logf("Hunt '%s' is no longer alive; resuming movement to the flag.", tostring(runtime.chasedHuntName))
    local ok, reason = ResumeFlagTravel(runtime)
    if not ok then
        return RESULT_ERROR, reason
    end
    return RESULT_CONTINUE
end

local function UpdateHuntTargetState(runtime)
    if runtime.huntTargeted then
        return
    end

    if TryTargetDetectedHunt(runtime.chasedHuntName) then
        runtime.huntTargeted = true
        runtime.huntApproachGraceUntil = os.clock() + SAFE_HUNT_STALL_GRACE_AFTER_TARGET
        runtime.huntRetryExhaustedLogged = false
        logf("Hunt '%s' targeted; continuing hunt approach.", tostring(runtime.chasedHuntName))
    end
end

local function HasHuntTakenDamage(currentEntity)
    local currentHp = tonumber(currentEntity and currentEntity.CurrentHp) or nil
    local maxHp = tonumber(currentEntity and currentEntity.MaxHp) or nil
    return currentHp ~= nil and maxHp ~= nil and maxHp > 0 and currentHp < maxHp
end

local function GetEngagedHuntHitboxDistance(currentEntity)
    if currentEntity == nil or currentEntity.Position == nil then
        return math.huge
    end

    local centerDistance = DistanceTo3D(currentEntity.Position)
    local targetRadius = GetEntityHitboxRadius(currentEntity)
    return math.max(0, centerDistance - targetRadius)
end

local function HasReachedEngagedHandoffPoint(runtime)
    if runtime == nil or runtime.huntApproachPoint == nil then
        return false, math.huge
    end

    local flatDistance = DistanceToFlat(runtime.huntApproachPoint)
    return flatDistance <= ENGAGED_HANDOFF_POINT_REACHED_DISTANCE, flatDistance
end

local function StartEngagedHuntHandoff(runtime, currentEntity, reasonLabel)
    if runtime.huntAutorotationApplied then
        return RESULT_SUCCESS, string.format("engaged hunt '%s' handed off", tostring(runtime.chasedHuntName))
    end

    local movePoint = currentEntity and currentEntity.Position or nil
    if movePoint == nil then
        return RESULT_ERROR, string.format("failed to read engaged hunt position for '%s'", tostring(runtime.chasedHuntName))
    end

    if not StartApproachMovement(movePoint) then
        return RESULT_ERROR, string.format("failed to start engaged handoff movement for hunt '%s'", tostring(runtime.chasedHuntName))
    end

    runtime.huntEngagedStartTime = os.clock()
    runtime.huntApproachPoint = movePoint
    runtime.huntApproachRepathCount = 0
    runtime.waitingForHuntDamage = false
    runtime.huntApproachStartTime = os.clock()
    runtime.huntApproachGraceUntil = os.clock() + SAFE_HUNT_STALL_GRACE_AFTER_REPATH
    runtime.huntRetryExhaustedLogged = false
    runtime.bestDistance = math.huge
    runtime.lastProgressAt = os.clock()
    SetRuntimeState(runtime, STATE_ENGAGED_HUNT_HANDOFF, "hunt '%s' damaged; pathing directly to %.2f, %.2f, %.2f.", tostring(runtime.chasedHuntName), movePoint.X, movePoint.Y, movePoint.Z)

    if reasonLabel ~= nil then
        logf("Engaged handoff trigger for '%s': %s", tostring(runtime.chasedHuntName), tostring(reasonLabel))
    end

    return RESULT_CONTINUE
end

local function EnsureDismountedForEngagedHandoff(runtime)
    if runtime.dismountedForHandoff then
        return true, nil
    end

    StopVnav()

    if not EnsureDismounted(MOUNT_TIMEOUT) then
        return false, string.format("failed to dismount at engaged hunt '%s'", tostring(runtime.chasedHuntName))
    end

    runtime.dismountedForHandoff = true
    return true, nil
end

local function TryCompleteEngagedHuntHandoff(runtime, currentEntity)
    if runtime.huntAutorotationApplied then
        return RESULT_SUCCESS, string.format("engaged hunt '%s' handed off", tostring(runtime.chasedHuntName))
    end

    if TryTargetDetectedHunt(runtime.chasedHuntName) then
        runtime.huntTargeted = true
    end

    local reachedPoint, pointDistance = HasReachedEngagedHandoffPoint(runtime)
    if reachedPoint then
        logf(
            "Reached engaged chase point for '%s' within %.2f flat yalms; dismounting for handoff.",
            tostring(runtime.chasedHuntName),
            pointDistance
        )

        local dismounted, dismountReason = EnsureDismountedForEngagedHandoff(runtime)
        if not dismounted then
            return RESULT_ERROR, dismountReason
        end

        ApplyAutorotationPreset(autorotationPrefix, BOSSMOD_AUTOROTATION_PRESET)
        runtime.huntAutorotationApplied = true
        return RESULT_SUCCESS, string.format("engaged hunt '%s' handed off", tostring(runtime.chasedHuntName))
    end

    local hitboxDistance = GetEngagedHuntHitboxDistance(currentEntity)
    if hitboxDistance > 1.0 then
        return RESULT_CONTINUE
    end

    logf(
        "Reached engaged hunt '%s' within %.2f yalms of its hitbox; dismounting for handoff.",
        tostring(runtime.chasedHuntName),
        hitboxDistance
    )

    local dismounted, dismountReason = EnsureDismountedForEngagedHandoff(runtime)
    if not dismounted then
        return RESULT_ERROR, dismountReason
    end

    ApplyAutorotationPreset(autorotationPrefix, BOSSMOD_AUTOROTATION_PRESET)
    runtime.huntAutorotationApplied = true
    return RESULT_SUCCESS, string.format("engaged hunt '%s' handed off", tostring(runtime.chasedHuntName))
end

local function TryImmediateDamagedHandoff(runtime, currentEntity)
    if runtime.huntAutorotationApplied then
        return RESULT_SUCCESS, string.format("reached hunt '%s'", tostring(runtime.chasedHuntName))
    end

    if not runtime.dismountedForHandoff then
        return RESULT_CONTINUE
    end

    if not HasHuntTakenDamage(currentEntity) then
        return RESULT_CONTINUE
    end

    local waitDistance = GetDistanceToHuntWaitThreshold(currentEntity, runtime.huntTargeted)
    if waitDistance > HUNT_WAIT_DISTANCE then
        return RESULT_CONTINUE
    end

    logf("Hunt '%s' has taken damage while already in handoff range; dismounting for immediate handoff.", tostring(runtime.chasedHuntName))

    local dismounted, dismountReason = EnsureDismountedForEngagedHandoff(runtime)
    if not dismounted then
        return RESULT_ERROR, dismountReason
    end

    ApplyAutorotationPreset(autorotationPrefix, BOSSMOD_AUTOROTATION_PRESET)
    runtime.huntAutorotationApplied = true
    runtime.waitingForHuntDamage = false
    return RESULT_SUCCESS, string.format("reached hunt '%s'", tostring(runtime.chasedHuntName))
end

local function UpdateHuntProgress(runtime, currentEntity)
    local waitDistance = GetDistanceToHuntWaitThreshold(currentEntity, runtime.huntTargeted)
    if waitDistance + 0.5 < runtime.bestDistance then
        runtime.bestDistance = waitDistance
        runtime.lastProgressAt = os.clock()
        runtime.huntRetryExhaustedLogged = false
    end
    return waitDistance
end

local function UpdateEngagedHuntProgress(runtime, currentEntity)
    local hitboxDistance = GetEngagedHuntHitboxDistance(currentEntity)
    if hitboxDistance + 0.5 < runtime.bestDistance then
        runtime.bestDistance = hitboxDistance
        runtime.lastProgressAt = os.clock()
        runtime.huntRetryExhaustedLogged = false
    end
    return hitboxDistance
end

local function TryRestartEngagedHuntHandoff(runtime, currentEntity)
    if os.clock() < (runtime.huntApproachGraceUntil or 0) then
        return RESULT_CONTINUE
    end

    if IsVnavMovementActive() and IsPlayerMoving() then
        return RESULT_CONTINUE
    end

    local stalledFor = os.clock() - runtime.lastProgressAt
    if stalledFor < SAFE_HUNT_STALL_TIMEOUT then
        return RESULT_CONTINUE
    end

    if runtime.huntApproachRepathCount >= 1 then
        if not runtime.huntRetryExhaustedLogged then
            local hitboxDistance = GetEngagedHuntHitboxDistance(currentEntity)
            logf(
                "Hunt '%s' engaged handoff is still stalled; retry budget exhausted, continuing current path (hitboxDistance=%.2f, best=%.2f).",
                tostring(runtime.chasedHuntName),
                hitboxDistance,
                runtime.bestDistance
            )
            runtime.huntRetryExhaustedLogged = true
        end
        return RESULT_CONTINUE
    end

    local movePoint = currentEntity and currentEntity.Position or nil
    if movePoint == nil then
        return RESULT_ERROR, string.format("failed to rebuild engaged hunt position for '%s'", tostring(runtime.chasedHuntName))
    end

    if runtime.huntApproachPoint ~= nil and DistanceBetweenFlat(runtime.huntApproachPoint, movePoint) < 2 then
        logf("Engaged handoff retry found no meaningfully different hunt position for '%s'; keeping current path.", tostring(runtime.chasedHuntName))
        runtime.huntApproachRepathCount = runtime.huntApproachRepathCount + 1
        runtime.huntApproachGraceUntil = os.clock() + SAFE_HUNT_STALL_GRACE_AFTER_REPATH
        runtime.huntRetryExhaustedLogged = false
        return RESULT_CONTINUE
    end

    if not StartApproachMovement(movePoint) then
        return RESULT_ERROR, string.format("failed to restart engaged handoff movement for hunt '%s'", tostring(runtime.chasedHuntName))
    end

    runtime.huntApproachPoint = movePoint
    runtime.huntApproachRepathCount = runtime.huntApproachRepathCount + 1
    runtime.huntApproachStartTime = os.clock()
    runtime.huntApproachGraceUntil = os.clock() + SAFE_HUNT_STALL_GRACE_AFTER_REPATH
    runtime.huntRetryExhaustedLogged = false
    runtime.bestDistance = math.huge
    runtime.lastProgressAt = os.clock()

    logf(
        "Hunt '%s' engaged handoff stalled; retrying direct chase at %.2f, %.2f, %.2f.",
        tostring(runtime.chasedHuntName),
        movePoint.X,
        movePoint.Y,
        movePoint.Z
    )

    return RESULT_CONTINUE
end

local function TryRestartHuntApproach(runtime, currentEntity)
    if os.clock() < (runtime.huntApproachGraceUntil or 0) then
        return RESULT_CONTINUE
    end

    if not runtime.huntTargeted then
        local acquireElapsed = os.clock() - (runtime.huntApproachStartTime or 0)
        if acquireElapsed < SAFE_HUNT_TARGET_ACQUIRE_TIMEOUT then
            return RESULT_CONTINUE
        end

        if IsVnavMovementActive() then
            return RESULT_CONTINUE
        end
    end

    local stalledFor = os.clock() - runtime.lastProgressAt
    if stalledFor < SAFE_HUNT_STALL_TIMEOUT then
        return RESULT_CONTINUE
    end

    if runtime.huntApproachRepathCount >= 1 then
        if not runtime.huntRetryExhaustedLogged then
            local waitDistance = GetDistanceToHuntWaitThreshold(currentEntity, runtime.huntTargeted)
            logf(
                "Hunt '%s' approach is still stalled; retry budget exhausted, continuing current path (waitDistance=%.2f, best=%.2f).",
                tostring(runtime.chasedHuntName),
                waitDistance,
                runtime.bestDistance
            )
            runtime.huntRetryExhaustedLogged = true
        end
        return RESULT_CONTINUE
    end

    logf("Hunt '%s' approach stalled for %.2fs; recomputing offset-first approach.", tostring(runtime.chasedHuntName), stalledFor)

    local approachPoint, approachReason, approachMeta = BuildSafeHuntApproachPoint(currentEntity, "retry")
    local movePoint = approachPoint or currentEntity.Position

    if runtime.huntApproachPoint ~= nil and approachPoint ~= nil then
        local shiftDistance = DistanceBetweenFlat(runtime.huntApproachPoint, approachPoint)
        if shiftDistance < 2 then
            logf("Retry found no meaningfully different validated approach for '%s'; keeping current path.", tostring(runtime.chasedHuntName))
            runtime.huntApproachRepathCount = runtime.huntApproachRepathCount + 1
            runtime.huntApproachGraceUntil = os.clock() + SAFE_HUNT_STALL_GRACE_AFTER_REPATH
            runtime.huntRetryExhaustedLogged = false
            return RESULT_CONTINUE
        end
        verboseLogf("Retry produced new approach for '%s' shifted by %.2f yalms.", tostring(runtime.chasedHuntName), shiftDistance)
    end

    if not StartApproachMovement(movePoint) then
        return RESULT_ERROR, string.format("failed to restart approach movement for hunt '%s'", tostring(runtime.chasedHuntName))
    end

    runtime.huntApproachPoint = approachPoint
    runtime.huntApproachRepathCount = runtime.huntApproachRepathCount + 1
    runtime.huntApproachStartTime = os.clock()
    runtime.huntApproachGraceUntil = os.clock() + SAFE_HUNT_STALL_GRACE_AFTER_REPATH
    runtime.huntRetryExhaustedLogged = false
    runtime.bestDistance = math.huge
    runtime.lastProgressAt = os.clock()

    if approachPoint ~= nil then
        logf(
            "Hunt '%s' approach stalled; retrying with %s point at %.2f, %.2f, %.2f.",
            tostring(runtime.chasedHuntName),
            tostring(approachMeta and approachMeta.label or "validated"),
            movePoint.X,
            movePoint.Y,
            movePoint.Z
        )
    else
        logf("Hunt '%s' approach stalled; retrying with raw hunt position.", tostring(runtime.chasedHuntName))
    end

    if approachReason ~= nil then
        logf("Hunt approach retry note for '%s': %s", tostring(runtime.chasedHuntName), tostring(approachReason))
    end

    return RESULT_CONTINUE
end

local function TryCompleteHuntHandoff(runtime, currentEntity, waitDistance)
    waitDistance = tonumber(waitDistance) or GetDistanceToHuntWaitThreshold(currentEntity, runtime.huntTargeted)
    if waitDistance <= HUNT_WAIT_DISTANCE then
        SetRuntimeState(runtime, STATE_WAIT_HUNT_HANDOFF, "hunt '%s' reached within %.2f yalms; dismounting and waiting for handoff.", tostring(runtime.chasedHuntName), HUNT_WAIT_DISTANCE)

        if TryTargetDetectedHunt(runtime.chasedHuntName) then
            runtime.huntTargeted = true
            waitDistance = GetDistanceToHuntWaitThreshold(currentEntity, runtime.huntTargeted)
        end

        if not runtime.dismountedForHandoff then
            StopVnav()

            if not EnsureDismounted(MOUNT_TIMEOUT) then
                return RESULT_ERROR, string.format("failed to dismount at hunt '%s'", tostring(runtime.chasedHuntName))
            end

            runtime.dismountedForHandoff = true
        end

        if not runtime.huntTargeted then
            if not runtime.waitingForHuntDamage then
                runtime.waitingForHuntDamage = true
                logf("Within %.2f yalms of hunt '%s' and dismounted; waiting for target or damage before handoff.", HUNT_WAIT_DISTANCE, tostring(runtime.chasedHuntName))
            end
            return RESULT_CONTINUE
        end

        if tonumber(currentEntity.CurrentHp) ~= nil
            and tonumber(currentEntity.MaxHp) ~= nil
            and tonumber(currentEntity.MaxHp) > 0
            and tonumber(currentEntity.CurrentHp) >= tonumber(currentEntity.MaxHp) then
            if not runtime.waitingForHuntDamage then
                runtime.waitingForHuntDamage = true
                logf("Within %.2f yalms of hunt '%s' hitbox and dismounted; waiting for another player to damage it before handoff.", HUNT_WAIT_DISTANCE, tostring(runtime.chasedHuntName))
            end
            return RESULT_CONTINUE
        end

        if runtime.waitingForHuntDamage then
            logf("Hunt '%s' has taken damage; handing off to autorotation.", tostring(runtime.chasedHuntName))
            runtime.waitingForHuntDamage = false
        end

        logf("Reached hunt '%s' within %.2f yalms of the hitbox for handoff.", tostring(runtime.chasedHuntName), HUNT_WAIT_DISTANCE)
        ApplyAutorotationPreset(autorotationPrefix, BOSSMOD_AUTOROTATION_PRESET)
        return RESULT_SUCCESS, string.format("reached hunt '%s'", tostring(runtime.chasedHuntName))
    end

    return RESULT_CONTINUE
end

local function UpdateActiveHuntChase(runtime)
    local currentEntity = TryReacquireChasedHunt(runtime)
    if currentEntity == nil then
        return HandleLostChasedHunt(runtime)
    end

    if runtime.state ~= STATE_WAIT_HUNT_HANDOFF then
        UpdateHuntTargetState(runtime)
    end

    if runtime.dismountedForHandoff then
        local immediateStatus, immediateReason = TryImmediateDamagedHandoff(runtime, currentEntity)
        if immediateStatus ~= RESULT_CONTINUE then
            return immediateStatus, immediateReason
        end

        local waitDistance = GetDistanceToHuntWaitThreshold(currentEntity, runtime.huntTargeted)
        return TryCompleteHuntHandoff(runtime, currentEntity, waitDistance)
    end

    if runtime.state ~= STATE_ENGAGED_HUNT_HANDOFF and HasHuntTakenDamage(currentEntity) then
        local immediateStatus, immediateReason = TryImmediateDamagedHandoff(runtime, currentEntity)
        if immediateStatus ~= RESULT_CONTINUE then
            return immediateStatus, immediateReason
        end

        return StartEngagedHuntHandoff(runtime, currentEntity, "hunt damaged during approach")
    end

    if runtime.state == STATE_ENGAGED_HUNT_HANDOFF then
        local engagedResult, engagedReason = TryCompleteEngagedHuntHandoff(runtime, currentEntity)
        if engagedResult ~= RESULT_CONTINUE then
            return engagedResult, engagedReason
        end

        UpdateEngagedHuntProgress(runtime, currentEntity)

        local restartStatus, restartResult = TryRestartEngagedHuntHandoff(runtime, currentEntity)
        if restartStatus ~= RESULT_CONTINUE then
            return restartStatus, restartResult
        end

        return RESULT_CONTINUE
    end

    local waitDistance = UpdateHuntProgress(runtime, currentEntity)
    if waitDistance > HUNT_WAIT_DISTANCE then
        local restartStatus, restartResult = TryRestartHuntApproach(runtime, currentEntity)
        if restartStatus ~= RESULT_CONTINUE then
            return restartStatus, restartResult
        end
    end

    return TryCompleteHuntHandoff(runtime, currentEntity, waitDistance)
end

local function TryAcquireHuntFromFlagMode(runtime)
    if not runtime.huntScanActivated then
        return RESULT_CONTINUE
    end

    local huntEntity = FindNearestLiveHuntEntity(runtime.flagDestination)
    if not huntEntity then
        runtime.detectedHuntName = nil
        return RESULT_CONTINUE
    end

    local huntName = LogDetectedHunt(runtime, huntEntity)
    local targetedNow = TryTargetDetectedHunt(huntName)
    local ok, reason = StartHuntApproach(runtime, huntEntity, targetedNow)
    if not ok then
        return RESULT_ERROR, reason
    end

    return RESULT_CONTINUE
end

local function TryCompleteAtFlag(runtime, currentFlagDistance)
    -- Once hunt pursuit begins, never end the script as a pure flag-only run.
    if runtime.state == STATE_TRAVEL_TO_FLAG
        and not runtime.huntCommitted
        and not runtime.huntTargeted
        and currentFlagDistance <= FLAG_STOP_DISTANCE then
        logf("Reached flag within %.2f flat yalms before hunt loaded.", FLAG_STOP_DISTANCE)
        StopVnav()
        return RESULT_SUCCESS, "reached flag before any hunt loaded"
    end

    local stalledFarFromFlag = runtime.state == STATE_TRAVEL_TO_FLAG
        and not runtime.huntCommitted
        and not runtime.huntTargeted
        and (os.clock() - runtime.lastProgressAt) >= FLAG_NO_PROGRESS_TIMEOUT
        and currentFlagDistance > (FLAG_STOP_DISTANCE + 5)
    if stalledFarFromFlag then
        logf(
            "Stopping after %.2fs without flag progress at %.2f yalms (best %.2f).",
            FLAG_NO_PROGRESS_TIMEOUT,
            currentFlagDistance,
            runtime.bestDistance
        )
        StopVnav()
        return RESULT_ERROR, "timed out waiting for flag movement progress"
    end

    local stalledNearFlag = (os.clock() - runtime.lastProgressAt) >= 2.5
        and currentFlagDistance <= (FLAG_STOP_DISTANCE + 5)
    if runtime.state == STATE_TRAVEL_TO_FLAG
        and not runtime.huntCommitted
        and not runtime.huntTargeted
        and stalledNearFlag then
        logf(
            "Stopping near flag after stalled progress at %.2f yalms (best %.2f).",
            currentFlagDistance,
            runtime.bestDistance
        )
        StopVnav()
        return RESULT_SUCCESS, "stopped near unreachable flag position"
    end

    return RESULT_CONTINUE
end

local function MoveToFlagWithRedirect(flagPosition)
    local flagDestination = normalizeDestination(flagPosition)
    if flagDestination == nil then
        return false, "flag destination unavailable"
    end

    local runtime = CreateHuntRuntime(flagDestination)

    local started, startReason = StartFlagTravel(runtime)
    if not started then
        return false, startReason
    end

    SetRuntimeState(runtime, STATE_TRAVEL_TO_FLAG, "moving toward flag and scanning for hunts.")

    while true do
        if runtime.state == STATE_TRAVEL_TO_FLAG then
            local currentFlagDistance = UpdateFlagProgress(runtime)

            local status, result = TryAcquireHuntFromFlagMode(runtime)
            if status == RESULT_ERROR then
                return false, result
            end

            local flagStatus, flagResult = TryCompleteAtFlag(runtime, currentFlagDistance)
            if flagStatus == RESULT_SUCCESS then
                return true, flagResult
            elseif flagStatus == RESULT_ERROR then
                return false, flagResult
            end
        else
            local status, result = UpdateActiveHuntChase(runtime)
            if status == RESULT_SUCCESS then
                return true, result
            elseif status == RESULT_ERROR then
                return false, result
            end
        end

        sleep(POLL_INTERVAL)
    end
end

log("Starting hunt go-to-flag script.")
logf("BossMod autorotation preset config: '%s'", BOSSMOD_AUTOROTATION_PRESET)

autorotationPrefix = GetAutorotationCommandPrefix()

local flag, flagErr = WaitForCurrentFlag(FLAG_ACQUIRE_TIMEOUT)
if not flag then
    logf("Cannot continue: %s", tostring(flagErr))
    return
end

logf("Using flag in territory %d at %.2f, %.2f, %.2f", flag.territoryId, flag.position.X, flag.position.Y, flag.position.Z)

if not WaitForStartupSettle(5) then
    log("Cannot continue: startup transition did not settle in time.")
    return
end

local currentTerritoryId = getCurrentTerritoryId()
if currentTerritoryId ~= flag.territoryId then
    logf("Waiting to arrive in territory %d.", flag.territoryId)
    if not WaitForZoneCompletion(flag.territoryId, ZONE_TIMEOUT) then
        logf("Timed out waiting for zone completion into territory %d.", flag.territoryId)
        return
    end
else
    WaitForZoneCompletion(flag.territoryId, 1)
end

local settledInstance, instanceErr = WaitForInstancedZoneSettle(INSTANCE_WATCH_TIMEOUT)
if not settledInstance then
    logf("Cannot continue: %s", tostring(instanceErr))
    return
end

local shouldContinue, startupFlagResult = HandleStartupTargetHunt(flag)
if not shouldContinue then
    logf("Finished: %s", tostring(startupFlagResult))
    return
end

flag = startupFlagResult or flag

local currentFlagDistance = DistanceToFlat(flag.position)
if currentFlagDistance <= FLAG_STOP_DISTANCE then
    logf("Already within %.2f yalms of the flag after startup hunt handling; skipping rerun.", FLAG_STOP_DISTANCE)
    return
end

if autorotationPrefix ~= nil then
    ClearAutorotationPreset(autorotationPrefix)
elseif BOSSMOD_AUTOROTATION_PRESET ~= "" then
    log("BossMod autorotation unavailable; no supported plugin enabled.")
end

local teleportedCloser, teleportErr = MaybeTeleportCloserToFlag(flag)
if not teleportedCloser then
    logf("Cannot continue: %s", tostring(teleportErr))
    return
end

if not EnsureMounted(MOUNT_TIMEOUT) then
    log("Failed to mount before moving to the hunt flag.")
    return
end

local ok, result = MoveToFlagWithRedirect(flag.position)
if not ok then
    logf("Stopped: %s", tostring(result))
    return
end

logf("Finished: %s", tostring(result))
