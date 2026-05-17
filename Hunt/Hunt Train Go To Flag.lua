--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.0.1
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
  Hunt Stop Distance:
    description: Distance from the hunt that triggers the dismount sequence.
    default: 4
    min: 1
    max: 20
  BossMod Autorotation Preset:
    description: Autorotation preset to apply after the hunt is targeted. Leave empty to disable.
    default: ""
  Flight Speed:
    description: Estimated mounted flight speed in yalms per second for same-zone travel decisions.
    default: 20
    min: 1
    max: 200
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
local TELEPORT_START_TIMEOUT = 2.0
local HUNT_TARGET_DISTANCE = 45
local INSTANCE_WATCH_TIMEOUT = 2.0
local INSTANCE_WATCH_POLL = 0.05
local FLAG_ACQUIRE_TIMEOUT = 5.0
local MOUNT_RETRY_COOLDOWN = 1.0
local HUNT_SCAN_START_DISTANCE = 100
local autorotationPrefix = nil

CharacterCondition = {
    mounted = 4,
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
local FLIGHT_SPEED = tonumber(getConfigValue("Flight Speed", 20)) or 20
local TELEPORT_PENALTY = tonumber(getConfigValue("Teleport Penalty", 13)) or 13
local MINIMUM_TELEPORT_SAVINGS = tonumber(getConfigValue("Minimum Teleport Savings", 0)) or 0
local FLAG_STOP_DISTANCE = tonumber(getConfigValue("Flag Stop Distance", 10)) or 10
local HUNT_STOP_DISTANCE = tonumber(getConfigValue("Hunt Stop Distance", 4)) or 4
local ZONE_TIMEOUT = tonumber(getConfigValue("Zone Timeout", 30)) or 30
local MOUNT_TIMEOUT = tonumber(getConfigValue("Mount Timeout", 10)) or 10

FLIGHT_SPEED = math.max(1, math.min(200, FLIGHT_SPEED))
TELEPORT_PENALTY = math.max(0, math.min(60, TELEPORT_PENALTY))
MINIMUM_TELEPORT_SAVINGS = math.max(0, math.min(30, MINIMUM_TELEPORT_SAVINGS))
FLAG_STOP_DISTANCE = math.max(1, math.min(20, FLAG_STOP_DISTANCE))
HUNT_STOP_DISTANCE = math.max(1, math.min(20, HUNT_STOP_DISTANCE))
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

local function _addon_exists(addon)
    if not addon then
        return false
    end

    if addon.Exists == true or addon.Visible == true or addon.IsVisible == true or addon.IsOpen == true or addon.IsShown == true then
        return true
    end

    if type(addon.Exists) == "function" then
        local ok, value = pcall(addon.Exists, addon)
        if ok and value then
            return true
        end
    end

    if type(addon.IsVisible) == "function" then
        local ok, value = pcall(addon.IsVisible, addon)
        if ok and value then
            return true
        end
    end

    return _addon_ready(addon)
end

local function IsAddonReady(name)
    return _addon_ready(_get_addon(name))
end

local function IsAddonVisible(name)
    return _addon_exists(_get_addon(name))
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

local function WaitForInstancedZoneSettle(timeoutSec)
    timeoutSec = tonumber(timeoutSec) or INSTANCE_WATCH_TIMEOUT
    local startInstanceId = getZoneInstance()

    if startInstanceId <= 0 then
        return true
    end

    logf("Public instance before watch: %d", startInstanceId)
    logf("Watching %.2fs for SelectString or instance change.", timeoutSec)

    local deadline = os.clock() + timeoutSec
    local sawSelectString = false
    local sawInstanceChange = false
    local latestInstanceId = startInstanceId

    while os.clock() < deadline do
        latestInstanceId = getZoneInstance()

        if IsAddonReady("SelectString") then
            sawSelectString = true
            log("SelectString detected after zoning; assuming instance switch.")
            break
        end

        if latestInstanceId > 0 and latestInstanceId ~= startInstanceId then
            sawInstanceChange = true
            logf("Public instance changed during watch: %d -> %d", startInstanceId, latestInstanceId)
            break
        end

        sleep(INSTANCE_WATCH_POLL)
    end

    if not sawSelectString and not sawInstanceChange then
        logf("No instance-switch signal detected; continuing in instance %d.", startInstanceId)
        return true
    end

    if isZoneTransitionActive() then
        log("Instance-switch transition already active; waiting for completion.")
        if not WaitForTeleportCompletion(getCurrentTerritoryId(), ZONE_TIMEOUT, "instance switch") then
            return false, "timed out waiting for active instance switch to complete"
        end
    elseif sawSelectString then
        if WaitForTeleportStart(getCurrentTerritoryId(), nil, TELEPORT_START_TIMEOUT, "instance switch") then
            if not WaitForTeleportCompletion(getCurrentTerritoryId(), ZONE_TIMEOUT, "instance switch") then
                return false, "timed out waiting for instance switch to complete"
            end
        else
            local endInstanceId = getZoneInstance()
            if endInstanceId > 0 and endInstanceId ~= startInstanceId then
                logf("Instance switch completed without caught transition start: %d -> %d", startInstanceId, endInstanceId)
            else
                return false, "instance switch prompt detected but no follow-up transition started"
            end
        end
    else
        log("Instance changed without SelectString; confirming settled state.")
        if not WaitUntil(function()
            local currentInstanceId = getZoneInstance()
            return currentInstanceId > 0
                and currentInstanceId ~= startInstanceId
                and isZoneTransitionComplete()
                and (not isZoneTransitionActive())
        end, 3.0, INSTANCE_WATCH_POLL, 0.5) then
            return false, "instance changed but zone did not settle in time"
        end
    end

    logf("Public instance after settle: %d -> %d", startInstanceId, getZoneInstance())
    return true
end

local function distanceBetweenFlat(a, b)
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

local function GetClosestAetheryteToPoint(position, territoryId)
    local aetherytes = BuildTerritoryAetheryteList(territoryId)
    local closestAetheryte = nil
    local closestDistance = math.huge

    for _, aetheryte in ipairs(aetherytes) do
        local comparisonDistance = distanceBetweenFlat(aetheryte.position, position)
        if comparisonDistance < closestDistance then
            closestDistance = comparisonDistance
            closestAetheryte = aetheryte
        end
    end

    return closestAetheryte, closestDistance
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
    if flag == nil or flag.position == nil or flag.territoryId == nil then
        return true
    end

    local playerPosition = getPlayerPosition()
    if playerPosition == nil then
        return true
    end

    local playerDistance = distanceBetweenFlat(playerPosition, flag.position)
    local closestAetheryte, aetheryteDistance = GetClosestAetheryteToPoint(flag.position, flag.territoryId)
    if closestAetheryte == nil or aetheryteDistance == nil then
        logf("No eligible aetheryte shortcut found for territory %s.", tostring(flag.territoryId))
        return true
    end

    local playerTravelTime = playerDistance / FLIGHT_SPEED
    local aetheryteTravelTime = (aetheryteDistance / FLIGHT_SPEED) + TELEPORT_PENALTY
    local timeSavings = playerTravelTime - aetheryteTravelTime

    logf(
        "Direct %.2fs, best aetheryte '%s' %.2fs, savings %.2fs.",
        playerTravelTime,
        tostring(closestAetheryte.aetheryteName),
        aetheryteTravelTime,
        timeSavings
    )

    if timeSavings < MINIMUM_TELEPORT_SAVINGS then
        logf("Skipping aetheryte teleport because it saves less than %.2fs.", MINIMUM_TELEPORT_SAVINGS)
        return true
    end

    logf("Teleporting to closer aetheryte '%s'.", tostring(closestAetheryte.aetheryteName))
    if not TeleportToAetheryte(closestAetheryte) then
        return false, string.format("failed to start teleport to aetheryte '%s'", tostring(closestAetheryte.aetheryteName))
    end

    if not WaitForTeleportCompletion(flag.territoryId, ZONE_TIMEOUT, "aetheryte teleport") then
        return false, string.format("timed out waiting for teleport to aetheryte '%s'", tostring(closestAetheryte.aetheryteName))
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
            log("Mount transition active; waiting for completion.")
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

        log("Still mounted or mounting; using general action 23.")
        executeGeneralAction(23)
        sleep(POLL_INTERVAL)
    end

    log("Dismount attempt timed out.")
    return false
end

local function distanceTo(position)
    if not (position and Entity and Entity.Player and Entity.Player.Position) then
        return math.huge
    end

    return Vector3.Distance(Entity.Player.Position, position)
end

local function distanceToFlat(position)
    local playerPosition = getPlayerPosition()
    if not (position and playerPosition) then
        return math.huge
    end

    local dx = playerPosition.X - position.X
    local dz = playerPosition.Z - position.Z
    return math.sqrt((dx * dx) + (dz * dz))
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

local function normalizeDestination(position)
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

    return position
end

local function beginMoveTo(position)
    if not (IPC and IPC.vnavmesh and IPC.vnavmesh.IsReady and IPC.vnavmesh.PathfindAndMoveTo) then
        return false
    end

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

local function beginFlyToFlag()
    if not (Instances and Instances.Map and Instances.Map.IsFlagMarkerSet) then
        log("Map flag is unavailable for /vnav flyflag.")
        return false
    end

    if not Instances.Map.IsFlagMarkerSet then
        log("No active map flag for /vnav flyflag.")
        return false
    end

    log("Starting vnav flyflag movement toward the current map flag.")
    yield("/vnav flyflag")

    local started = WaitUntil(function()
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
    end, 5, POLL_INTERVAL, 0)

    if not started then
        log("/vnav flyflag did not start in time.")
    end

    return started
end

local function beginFlyToPosition(position)
    if position == nil then
        log("No destination available for /vnav flyto.")
        return false
    end

    logf("Starting vnav flyto movement toward %.2f, %.2f, %.2f.", position.X, position.Y, position.Z)
    yield(string.format("/vnav flyto %.3f %.3f %.3f", position.X, position.Y, position.Z))

    local started = WaitUntil(function()
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
    end, 5, POLL_INTERVAL, 0)

    if not started then
        log("/vnav flyto did not start in time.")
    end

    return started
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
            local distance = distanceBetweenFlat(entity.Position, flagPosition)
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

    local distance = distanceTo(entity.Position)
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

local function MoveToFlagWithRedirect(flagPosition)
    local flagDestination = normalizeDestination(flagPosition)
    if flagDestination == nil then
        return false, "flag destination unavailable"
    end

    if not beginFlyToFlag() then
        log("Falling back to direct pathfind for flag movement.")
        if not beginMoveTo(flagDestination) then
            return false, "failed to start movement to the flag"
        end
    end

    log("Moving toward flag and scanning for hunt entities.")

    local bestFlagDistance = math.huge
    local lastFlagProgressTime = os.clock()
    local huntScanActivated = false
    local huntCommitted = false

    local chasedHuntName = nil
    local detectedHuntName = nil
    local chaseMode = "flag"

    while true do
        local currentFlagDistance = distanceToFlat(flagDestination)
        if currentFlagDistance + 0.5 < bestFlagDistance then
            bestFlagDistance = currentFlagDistance
            lastFlagProgressTime = os.clock()
        end

        if not huntScanActivated and currentFlagDistance <= HUNT_SCAN_START_DISTANCE then
            huntScanActivated = true
            logf("Entered hunt scan range within %.2f yalms of the flag.", HUNT_SCAN_START_DISTANCE)
        end

        if chasedHuntName ~= nil then
            local currentEntity = nil
            local currentOk = pcall(function()
                currentEntity = Entity.GetEntityByName and Entity.GetEntityByName(chasedHuntName) or nil
            end)

            if not currentOk or not IsLiveHuntEntity(currentEntity) then
                logf("Hunt '%s' is no longer alive; resuming movement to the flag.", tostring(chasedHuntName))
                StopVnav()
                sleep(POLL_INTERVAL)
                if not beginFlyToFlag() then
                    log("Falling back to direct pathfind for resumed flag movement.")
                    if not beginMoveTo(flagDestination) then
                        return false, string.format("failed to resume movement to flag after losing hunt '%s'", tostring(chasedHuntName))
                    end
                end
                chasedHuntName = nil
                detectedHuntName = nil
                chaseMode = "flag"
            else
                local currentPosition = currentEntity.Position
                if chaseMode == "hunt_position" then
                    if TargetHuntEntityIfClose(chasedHuntName, HUNT_TARGET_DISTANCE) then
                        chaseMode = "hunt_target"
                        logf("Hunt '%s' targeted; continuing flyto to hunt position.", tostring(chasedHuntName))
                    end
                end

                if distanceTo(currentPosition) <= HUNT_STOP_DISTANCE then
                    TargetHuntEntityIfClose(chasedHuntName, HUNT_TARGET_DISTANCE)
                    logf("Reached hunt '%s' within %.2f yalms.", tostring(chasedHuntName), HUNT_STOP_DISTANCE)
                    ApplyAutorotationPreset(autorotationPrefix, BOSSMOD_AUTOROTATION_PRESET)
                    StopVnav()
                    if not EnsureDismounted(MOUNT_TIMEOUT) then
                        return false, string.format("failed to dismount at hunt '%s'", tostring(chasedHuntName))
                    end
                    return true, string.format("reached hunt '%s'", tostring(chasedHuntName))
                end
            end
        else
            local huntEntity = nil
            if huntScanActivated then
                huntEntity = FindNearestLiveHuntEntity(flagDestination)
            end
            if huntEntity then
                local huntName = tostring(huntEntity.Name or "Unknown Hunt")
                if detectedHuntName ~= huntName then
                    logf("Found hunt entity '%s' at %.2f, %.2f, %.2f.", tostring(huntName), huntEntity.Position.X, huntEntity.Position.Y, huntEntity.Position.Z)
                    detectedHuntName = huntName
                end

                if TargetHuntEntityIfClose(huntName, HUNT_TARGET_DISTANCE) then
                    StopVnav()
                    sleep(POLL_INTERVAL)
                    if not beginFlyToPosition(huntEntity.Position) then
                        return false, string.format("failed to start flyto for targeted hunt '%s'", tostring(huntName))
                    end
                    huntCommitted = true
                    chasedHuntName = huntName
                    chaseMode = "hunt_target"
                    logf("Hunt '%s' targeted; switching to flyto hunt position.", tostring(huntName))
                else
                    StopVnav()
                    sleep(POLL_INTERVAL)
                    if not beginFlyToPosition(huntEntity.Position) then
                        return false, string.format("failed to start flyto for hunt '%s'", tostring(huntName))
                    end
                    huntCommitted = true
                    chasedHuntName = huntName
                    chaseMode = "hunt_position"
                    logf("Hunt '%s' detected; switching to flyto until targetable.", tostring(huntName))
                end
            else
                detectedHuntName = nil
            end
        end

        if chaseMode == "flag" and not huntCommitted and currentFlagDistance <= FLAG_STOP_DISTANCE then
            logf("Reached flag within %.2f flat yalms before hunt loaded.", FLAG_STOP_DISTANCE)
            StopVnav()
            return true, "reached flag before any hunt loaded"
        end

        local stalledNearFlag = (os.clock() - lastFlagProgressTime) >= 2.5 and currentFlagDistance <= (FLAG_STOP_DISTANCE + 5)
        if chaseMode == "flag" and not huntCommitted and stalledNearFlag then
            logf(
                "Stopping near flag after stalled progress at %.2f yalms (best %.2f).",
                currentFlagDistance,
                bestFlagDistance
            )
            StopVnav()
            return true, "stopped near unreachable flag position"
        end

        sleep(POLL_INTERVAL)
    end
end

log("Starting hunt go-to-flag script.")
logf("BossMod autorotation preset config: '%s'", BOSSMOD_AUTOROTATION_PRESET)

autorotationPrefix = GetAutorotationCommandPrefix()
if autorotationPrefix ~= nil then
    ClearAutorotationPreset(autorotationPrefix)
elseif BOSSMOD_AUTOROTATION_PRESET ~= "" then
    log("BossMod autorotation unavailable; no supported plugin enabled.")
end

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
