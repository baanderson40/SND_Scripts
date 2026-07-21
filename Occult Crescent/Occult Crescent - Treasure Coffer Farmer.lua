--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.0.0
description: >-
  Visit mapped Occult Crescent treasure coffer positions, filter by configured
  aggro level, and loot visible Treasure Coffer entities.
plugin_dependencies:
- vnavmesh
configs:
    Maximum Aggro Level:
        default: 19
        description: >-
          Normal travel threshold.
          With Ninja mode disabled, skip mapped coffers above this value.
          With Ninja mode enabled, spots above this value use threshold-based Hide travel.
        min: 0
        max: 28
    Use Ninja For Dangerous Area:
        description: Equip Ninja for the full pass and use threshold-based Hide travel for spots above Maximum Aggro Level.
        is_choice: true
        choices:
          - Disabled
          - Enabled
        default: Disabled
    Hide Threshold Distance:
        default: 120
        description: >-
          Distance from a dangerous mapped coffer position to dismount, apply Hide, and walk.
          Also used before mounting when leaving a dangerous coffer position.
        min: 10
        max: 300
    Ninja Gearset Number:
        default: 0
        description: Gearset number for Ninja when Ninja mode is enabled. Set to 0 to disable.
        min: 0
        max: 100
    Arrival Distance:
        default: 20
        description: Distance from a mapped point that counts as arrived.
        min: 3
        max: 40
    Skip High-Level Caverns During Ashkin Time:
        description: >-
          Skip Crystallized Caverns coffers with aggroLevel 20 or higher from
          22:30 through 03:59 Eorzea Time, when Ashkin spawns are active.
        is_choice: true
        choices:
          - Disabled
          - Enabled
        default: Enabled
[[End Metadata]]
--]=====]

import("System.Numerics")

local PREFIX = "[OC Coffer Farmer]"

local GENERAL_ACTION_RETURN = 8
local SOUTH_HORN_TERRITORY_ID = 1252
local GENERAL_ACTION_JUMP = 2
local GENERAL_ACTION_DISMOUNT = 23
local GENERAL_ACTION_MOUNT = 24
local HIDE_ACTION_ID = 2245
local HIDDEN_STATUS_ID = 614
local MOUNT_TIMEOUT = 8.0
local MOVE_START_TIMEOUT = 3.0
local MOVE_HARD_TIMEOUT = 180.0
local MOVE_PROGRESS_TIMEOUT = 5.0
local MOVE_PROGRESS_MIN_MOVE = 2.0
local POLL_INTERVAL = 0.25
local INTERACT_WAIT_TIMEOUT = 8.0
local APPROACH_SCAN_TRIGGER_DISTANCE = 40.0
local APPROACH_SCAN_POLL_INTERVAL = 0.2
local INTERACT_RETRY_DELAY = 1.25
local MAX_INTERACT_ATTEMPTS = 2
local JUMP_ASSIST_TRIGGER_DISTANCE = 10.0
local JUMP_ASSIST_COUNT = 1
local JUMP_ASSIST_DELAY = 0.35
local DEATH_RETURN_TIMEOUT = 30.0
local DEATH_PATH_DIAGNOSTIC_TIMEOUT = 5.0
local BASE_CAMP_POSITION = Vector3(830.7468, 72.98389, -695.97925)
local BASE_START_DISTANCE = 50.0
local SCAN_RADIUS = 60.0
local INTERACT_DISTANCE = 3.25
local MOUNT_ENABLED = true
local DEFAULT_ROUTE_ONLY_AGGRO_LEVEL = 28
local COMBAT_DIAGNOSTIC_RADIUS = 50.0
local COMBAT_DIAGNOSTIC_LIMIT = 12

local MAX_AGGRO_LEVEL = math.max(0, math.min(28, tonumber(Config.Get("Maximum Aggro Level")) or 19))
local USE_NINJA_FOR_DANGEROUS_AREA = tostring(Config.Get("Use Ninja For Dangerous Area") or "Disabled") == "Enabled"
local HIDE_THRESHOLD_DISTANCE = math.max(10, math.min(300, tonumber(Config.Get("Hide Threshold Distance")) or 120))
local NINJA_GEARSET_NUMBER = math.max(0, math.min(100, tonumber(Config.Get("Ninja Gearset Number")) or 0))
local ARRIVAL_DISTANCE = math.max(3, math.min(40, tonumber(Config.Get("Arrival Distance")) or 20))
local SKIP_HIGH_CAVERNS_DURING_ASHKIN =
    tostring(Config.Get("Skip High-Level Caverns During Ashkin Time") or "Enabled") == "Enabled"

local CharacterCondition = {
    dead = 2,
    mounted = 4,
    inCombat = 26,
    casting = 27,
    betweenAreas = 45,
}

local ninjaGearsetEquipped = false
local deathReturnTriggered = false
local dangerousCombatAbortTriggered = false
local ROUTE_CONTEXT = {
    previousEntry = nil,
    currentEntry = nil,
}

local STEALTH_TRACE = {
    context = nil,
    hidden = nil,
    mounted = nil,
    combat = nil,
}

local STATIC_ROUTE_ORDER = {
    "Southdown Heath_1",
    "Southdown Heath_2",
    "Southdown Heath_3",
    "Southdown Heath_5",
    "Southdown Heath_4",

    "Lost Citadel_1",
    "Lost Citadel_2",
    "Lost Citadel_3",
    "Lost Citadel_5",
    "Lost Citadel_6",
    "Lost Citadel_7",

    "Shadowed City_9",
    "Shadowed City_10",

    "Lost Citadel_4",
    "Heathcliff_1",
    "Lost Citadel_8",

    "Shadowed City_1",

    "Eldergrowth_1",

    "Shadowed City_4",
    "Shadowed City_5",
    "Shadowed City_2",
    "Shadowed City_3",
    "Shadowed City_6",
    "Shadowed City_7",
    "Shadowed City_8",

    "Eldergrowth_2",

    "Stonemarsh_1",
    "Stonemarsh_2",

    "Heathcliff_2",
    "Heathcliff_3",

    "Stonemarsh_4",
    "Stonemarsh_3",

    "Abandoned Ascent_2",
    "Abandoned Ascent_3",
    "Abandoned Ascent_6",
    {
        area = "Abandoned Ascent",
        label = "Abandoned Ascent_7_UnhidePoint",
        general = Vector3(-637.906, 180.037, 764.909),
        aggroLevel = 28,
        stopDistance = 3.0,
        routeOnly = true,
        forceHidden = true,
        disableExitHideThreshold = true,
        mountOnArrival = true,
        specialBranch = "ascent7",
        recheckAscentSafetyOnArrival = true,
        note = "drop_hide_before_ascent_7",
    },
    {
        area = "Abandoned Ascent",
        label = "Abandoned Ascent_7_RampCorner",
        general = Vector3(-701.109, 203.000, 781.534),
        aggroLevel = 28,
        stopDistance = 3.0,
        routeOnly = true,
        forceUnhidden = true,
        specialBranch = "ascent7",
        note = "spell_aggro_unhidden",
    },
    "Abandoned Ascent_7",
    {
        area = "Abandoned Ascent",
        label = "Abandoned Ascent_5_UnhidePoint",
        general = Vector3(-687.237, 171.000, 665.097),
        aggroLevel = 28,
        stopDistance = 3.0,
        routeOnly = true,
        forceHidden = true,
        disableExitHideThreshold = true,
        mountOnArrival = true,
        specialBranch = "ascent5_only",
        note = "drop_hide_before_ascent_5",
    },
    "Abandoned Ascent_5",
    {
        area = "Abandoned Ascent",
        label = "Abandoned Ascent_5_RehidePoint",
        general = Vector3(-687.237, 171.000, 665.097),
        aggroLevel = 28,
        stopDistance = 3.0,
        routeOnly = true,
        forceUnhidden = true,
        hideOnArrival = true,
        note = "rehide_after_ascent_5",
    },
    "Abandoned Ascent_4",
    "Abandoned Ascent_1",

    "Stonemarsh_5",

    "Crystallized Caverns_3",
    "Crystallized Caverns_9",
    "Crystallized Caverns_8",
    "Crystallized Caverns_5",
    "Crystallized Caverns_7",
    "Crystallized Caverns_6",
    "Crystallized Caverns_4",

    "Heathcliff_10",

    "Crystallized Caverns_2",
    "Crystallized Caverns_1",

    "Heathcliff_9",
    "Heathcliff_8",
    "Heathcliff_4",
    "Heathcliff_5",
    "Heathcliff_6",
    "Heathcliff_7",

    "Vanishing Slope_4",
    "Vanishing Slope_3",

    "Vanishing Slope_5",

    "The Wanderer's Haven_4",
    "The Wanderer's Haven_5",
    "The Wanderer's Haven_6",
    "The Wanderer's Haven_3",
    "The Wanderer's Haven_2",
    "The Wanderer's Haven_1",

    "Vanishing Slope_6",
    "Vanishing Slope_2",
    "Vanishing Slope_1",
}

local COFFER_SPOTS = {
    { area = "Southdown Heath", label = "Southdown Heath_1", general = Vector3(617.090, 66.300, -703.883), aggroLevel = 1 },
    { area = "Southdown Heath", label = "Southdown Heath_2", general = Vector3(490.410, 62.455, -590.570), aggroLevel = 1 },
    { area = "Southdown Heath", label = "Southdown Heath_3", general = Vector3(386.923, 96.788, -451.377), aggroLevel = 1 },
    { area = "Southdown Heath", label = "Southdown Heath_4", general = Vector3(666.529, 79.118, -480.369), aggroLevel = 2 },
    { area = "Southdown Heath", label = "Southdown Heath_5", general = Vector3(343.672, 95.536, -284.062), aggroLevel = 3 },

    { area = "Vanishing Slope", label = "Vanishing Slope_1", general = Vector3(381.735, 22.171, -743.648), aggroLevel = 3 },
    { area = "Vanishing Slope", label = "Vanishing Slope_2", general = Vector3(142.107, 16.403, -574.060), aggroLevel = 6 },
    { area = "Vanishing Slope", label = "Vanishing Slope_3", general = Vector3(-140.459, 22.354, -414.267), aggroLevel = 6 },
    { area = "Vanishing Slope", label = "Vanishing Slope_4", general = Vector3(-343.160, 52.323, -382.132), aggroLevel = 11 },
    { area = "Vanishing Slope", label = "Vanishing Slope_5", general = Vector3(-491.020, 2.975, -529.595), aggroLevel = 8 },
    { area = "Vanishing Slope", label = "Vanishing Slope_6", general = Vector3(-118.975, 4.990, -708.461), aggroLevel = 7 },

    { area = "The Wanderer's Haven", label = "The Wanderer's Haven_1", general = Vector3(-451.682, 2.975, -775.570), aggroLevel = 8 },
    { area = "The Wanderer's Haven", label = "The Wanderer's Haven_2", general = Vector3(-585.290, 4.990, -864.836), aggroLevel = 22 },
    { area = "The Wanderer's Haven", label = "The Wanderer's Haven_3", general = Vector3(-729.427, 4.990, -724.819), aggroLevel = 22 },
    { area = "The Wanderer's Haven", label = "The Wanderer's Haven_4", general = Vector3(-661.708, 2.975, -579.492), aggroLevel = 22 },
    { area = "The Wanderer's Haven", label = "The Wanderer's Haven_5", general = Vector3(-884.123, 3.799, -682.032), aggroLevel = 23, note = "requires_jump" },
    { area = "The Wanderer's Haven", label = "The Wanderer's Haven_6", general = Vector3(-825.162, 2.975, -832.273), aggroLevel = 23, note = "silver_variant" },

    { area = "Lost Citadel", label = "Lost Citadel_1", general = Vector3(870.664, 95.689, -388.357), aggroLevel = 4 },
    { area = "Lost Citadel", label = "Lost Citadel_2", general = Vector3(779.019, 96.086, -256.245), aggroLevel = 4 },
    { area = "Lost Citadel", label = "Lost Citadel_3", general = Vector3(475.730, 95.994, -87.083), aggroLevel = 4 },
    { area = "Lost Citadel", label = "Lost Citadel_4", general = Vector3(609.613, 107.988, 117.266), aggroLevel = 5 },
    { area = "Lost Citadel", label = "Lost Citadel_5", general = Vector3(726.284, 108.141, -67.918), aggroLevel = 5 },
    { area = "Lost Citadel", label = "Lost Citadel_6", general = Vector3(770.748, 107.988, -143.572), aggroLevel = 5 },
    { area = "Lost Citadel", label = "Lost Citadel_7", general = Vector3(788.876, 120.378, 109.392), aggroLevel = 20 },
    { area = "Lost Citadel", label = "Lost Citadel_8", general = Vector3(517.754, 67.887, 236.133), aggroLevel = 21 },

    { area = "Heathcliff", label = "Heathcliff_1", general = Vector3(277.790, 103.776, 241.901), aggroLevel = 10 },
    { area = "Heathcliff", label = "Heathcliff_2", general = Vector3(8.987, 103.197, 426.963), aggroLevel = 10 },
    { area = "Heathcliff", label = "Heathcliff_3", general = Vector3(-283.986, 115.984, 377.035), aggroLevel = 11 },
    { area = "Heathcliff", label = "Heathcliff_4", general = Vector3(-256.886, 120.989, 125.078), aggroLevel = 11 },
    { area = "Heathcliff", label = "Heathcliff_5", general = Vector3(-25.681, 102.220, 150.164), aggroLevel = 10 },
    { area = "Heathcliff", label = "Heathcliff_6", general = Vector3(245.594, 109.117, -18.174), aggroLevel = 9 },
    { area = "Heathcliff", label = "Heathcliff_7", general = Vector3(55.283, 111.314, -289.082), aggroLevel = 9 },
    { area = "Heathcliff", label = "Heathcliff_8", general = Vector3(-158.648, 98.619, -132.738), aggroLevel = 11 },
    { area = "Heathcliff", label = "Heathcliff_9", general = Vector3(-487.114, 98.527, -205.463), aggroLevel = 11 },
    { area = "Heathcliff", label = "Heathcliff_10", general = Vector3(-682.795, 135.607, -195.270), aggroLevel = 13, rainSensitive = true },

    { area = "Crystallized Caverns", label = "Crystallized Caverns_1", general = Vector3(-444.114, 90.684, 26.230), aggroLevel = 12 },
    { area = "Crystallized Caverns", label = "Crystallized Caverns_2", general = Vector3(-394.888, 106.737, 175.433), aggroLevel = 12 },
    { area = "Crystallized Caverns", label = "Crystallized Caverns_3", general = Vector3(-713.802, 62.058, 192.615), aggroLevel = 13 },
    { area = "Crystallized Caverns", label = "Crystallized Caverns_4", general = Vector3(-756.832, 76.554, 97.368), aggroLevel = 13 },
    { area = "Crystallized Caverns", label = "Crystallized Caverns_5", general = Vector3(-767.453, 115.618, -235.004), aggroLevel = 24, hideThreshold = 400 },
    { area = "Crystallized Caverns", label = "Crystallized Caverns_6", general = Vector3(-680.537, 104.845, -354.788), aggroLevel = 25, hideThreshold = 425 },
    { area = "Crystallized Caverns", label = "Crystallized Caverns_7", general = Vector3(-798.245, 105.577, -310.567), aggroLevel = 25, hideThreshold = 400 },
    { area = "Crystallized Caverns", label = "Crystallized Caverns_8", general = Vector3(-856.962, 68.833, -93.156), aggroLevel = 24, hideThreshold = 400 },
    { area = "Crystallized Caverns", label = "Crystallized Caverns_9", general = Vector3(-729.915, 116.533, -79.057), aggroLevel = 24, hideThreshold = 400 },

    { area = "Shadowed City", label = "Shadowed City_1", general = Vector3(642.969, 69.993, 407.797), aggroLevel = 16 },
    { area = "Shadowed City", label = "Shadowed City_2", general = Vector3(697.322, 69.993, 597.925), aggroLevel = 17 },
    { area = "Shadowed City", label = "Shadowed City_3", general = Vector3(596.460, 70.298, 622.766), aggroLevel = 17 },
    { area = "Shadowed City", label = "Shadowed City_4", general = Vector3(471.183, 70.298, 530.022), aggroLevel = 16 },
    { area = "Shadowed City", label = "Shadowed City_5", general = Vector3(835.080, 69.993, 699.092), aggroLevel = 17 },
    { area = "Shadowed City", label = "Shadowed City_6", general = Vector3(433.707, 70.298, 683.528), aggroLevel = 17 },
    { area = "Shadowed City", label = "Shadowed City_7", general = Vector3(294.880, 56.077, 640.223), aggroLevel = 15 },
    { area = "Shadowed City", label = "Shadowed City_8", general = Vector3(140.978, 55.985, 770.992), aggroLevel = 15 },
    { area = "Shadowed City", label = "Shadowed City_9", general = Vector3(826.688, 121.996, 434.989), aggroLevel = 21 },
    { area = "Shadowed City", label = "Shadowed City_10", general = Vector3(869.291, 109.972, 581.201), aggroLevel = 21 },

    { area = "Eldergrowth", label = "Eldergrowth_1", general = Vector3(256.153, 73.167, 492.363), aggroLevel = 14 },
    { area = "Eldergrowth", label = "Eldergrowth_2", general = Vector3(35.721, 65.110, 648.951), aggroLevel = 14 },

    { area = "Stonemarsh", label = "Stonemarsh_1", general = Vector3(-225.025, 74.998, 804.990), aggroLevel = 20 },
    { area = "Stonemarsh", label = "Stonemarsh_2", general = Vector3(-197.192, 74.906, 618.341), aggroLevel = 18 },
    { area = "Stonemarsh", label = "Stonemarsh_3", general = Vector3(-372.671, 74.998, 527.428), aggroLevel = 19 },
    { area = "Stonemarsh", label = "Stonemarsh_4", general = Vector3(-401.663, 85.038, 332.540), aggroLevel = 19 },
    { area = "Stonemarsh", label = "Stonemarsh_5", general = Vector3(-648.005, 74.998, 403.952), aggroLevel = 19 },

    { area = "Abandoned Ascent", label = "Abandoned Ascent_1", general = Vector3(-729.549, 106.981, 561.150), aggroLevel = 26, hideThreshold = 175 },
    { area = "Abandoned Ascent", label = "Abandoned Ascent_2", general = Vector3(-550.134, 106.981, 627.741), aggroLevel = 26, hideThreshold = 400 },
    { area = "Abandoned Ascent", label = "Abandoned Ascent_3", general = Vector3(-600.275, 138.994, 802.640), aggroLevel = 27 },
    { area = "Abandoned Ascent", label = "Abandoned Ascent_4", general = Vector3(-784.756, 138.994, 699.763), aggroLevel = 27 },
    { area = "Abandoned Ascent", label = "Abandoned Ascent_5", general = Vector3(-676.417, 170.977, 640.375), aggroLevel = 28, forceUnhidden = true, note = "spell_aggro_unhidden" },
    { area = "Abandoned Ascent", label = "Abandoned Ascent_6", general = Vector3(-716.152, 170.977, 794.430), aggroLevel = 28 },
    { area = "Abandoned Ascent", label = "Abandoned Ascent_7", general = Vector3(-645.686, 202.991, 710.170), aggroLevel = 28, forceUnhidden = true, specialBranch = "ascent7", note = "spell_aggro_unhidden" },
}

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

local function logf(fmt, ...)
    Dalamud.Log(string.format("%s %s", PREFIX, string.format(fmt, ...)))
end

-- Forward declarations for helpers referenced before their implementations.
local getSpotDescriptor
local getObjectName
local stopPathing
local collectVisibleCoffers
local returnToBase
local getEntryAggroLevel

SPECIAL_SPAWN_RULES = SPECIAL_SPAWN_RULES or {}
SPECIAL_SPAWN_RULES.cavernsDecision = nil
SPECIAL_SPAWN_RULES.ascentDecision = nil
SPECIAL_SPAWN_RULES.ascentLocked = false
SPECIAL_SPAWN_RULES.rainWeatherIds = {
    [7] = true,
    [62] = true,
    [64] = true,
}

function SPECIAL_SPAWN_RULES.reset()
    SPECIAL_SPAWN_RULES.cavernsDecision = nil
    SPECIAL_SPAWN_RULES.ascentDecision = nil
    SPECIAL_SPAWN_RULES.ascentLocked = false
end

function SPECIAL_SPAWN_RULES.readEorzeaTime()
    local raw = tonumber(safeCall(function()
        return Instances.Framework.EorzeaTime
    end))

    if raw == nil then
        return nil, "Instances.Framework.EorzeaTime unavailable"
    end

    local secondsToday = raw % 86400
    local hour = math.floor(secondsToday / 3600)
    local minute = math.floor((secondsToday % 3600) / 60)
    local second = math.floor(secondsToday % 60)

    return {
        raw = raw,
        secondsToday = secondsToday,
        hour = hour,
        minute = minute,
        second = second,
    }, nil
end

function SPECIAL_SPAWN_RULES.readWeatherId()
    local weather = safeCall(function()
        return Instances.EnvManager.ActiveWeather
    end)

    if weather == nil then
        return nil, "Instances.EnvManager.ActiveWeather unavailable"
    end

    local weatherId = tonumber(safeCall(function() return tonumber(weather) end))
        or tonumber(safeCall(function() return weather.RowId end))
        or tonumber(safeCall(function() return weather.Id end))
        or tonumber(safeCall(function() return weather.Row end))

    if weatherId == nil then
        return nil, "ActiveWeather did not expose a numeric weather ID"
    end

    return weatherId, nil
end

function SPECIAL_SPAWN_RULES.isAshkinTime(et)
    if et == nil then
        return true
    end
    return et.secondsToday >= (22 * 3600 + 30 * 60)
        or et.secondsToday < (4 * 3600)
end

function SPECIAL_SPAWN_RULES.isRainWeather(weatherId)
    if weatherId == nil then
        return true
    end
    return SPECIAL_SPAWN_RULES.rainWeatherIds[weatherId] == true
end

function SPECIAL_SPAWN_RULES.readConditions()
    local et, timeError = SPECIAL_SPAWN_RULES.readEorzeaTime()
    local weatherId, weatherError = SPECIAL_SPAWN_RULES.readWeatherId()

    return {
        et = et,
        weatherId = weatherId,
        ashkin = SPECIAL_SPAWN_RULES.isAshkinTime(et),
        rain = SPECIAL_SPAWN_RULES.isRainWeather(weatherId),
        timeError = timeError,
        weatherError = weatherError,
    }
end

function SPECIAL_SPAWN_RULES.formatTime(et)
    if et == nil then
        return "unavailable"
    end
    return string.format("%02d:%02d:%02d", et.hour, et.minute, et.second)
end

function SPECIAL_SPAWN_RULES.copyEntry(entry)
    local copy = {}
    for key, value in pairs(entry or {}) do
        copy[key] = value
    end
    return copy
end

function SPECIAL_SPAWN_RULES.isHighLevelCavernsEntry(entry)
    return entry ~= nil
        and entry.area == "Crystallized Caverns"
        and getEntryAggroLevel(entry) >= 20
end

function SPECIAL_SPAWN_RULES.shouldSkipHighCaverns(entry)
    if not SKIP_HIGH_CAVERNS_DURING_ASHKIN
        or not SPECIAL_SPAWN_RULES.isHighLevelCavernsEntry(entry) then

        return false
    end

    if SPECIAL_SPAWN_RULES.cavernsDecision == nil then
        local et, timeError = SPECIAL_SPAWN_RULES.readEorzeaTime()
        local ashkin = SPECIAL_SPAWN_RULES.isAshkinTime(et)

        SPECIAL_SPAWN_RULES.cavernsDecision = ashkin and "skip" or "run"

        if et == nil then
            logf(
                "Unable to read Eorzea time at the high-level Caverns gate (%s); fail-safe skipping Caverns entries with aggroLevel >= 20.",
                tostring(timeError or "unknown error")
            )
        elseif ashkin then
            logf(
                "Eorzea time at the high-level Caverns gate is %s ET (raw=%s); Ashkin window 22:30-04:00 is active, skipping Caverns entries with aggroLevel >= 20.",
                SPECIAL_SPAWN_RULES.formatTime(et),
                tostring(et.raw)
            )
        else
            logf(
                "Eorzea time at the high-level Caverns gate is %s ET (raw=%s); Ashkin window is inactive, running the high-level Caverns block.",
                SPECIAL_SPAWN_RULES.formatTime(et),
                tostring(et.raw)
            )
        end
    end

    return SPECIAL_SPAWN_RULES.cavernsDecision == "skip"
end

function SPECIAL_SPAWN_RULES.chooseAscentBranch()
    if SPECIAL_SPAWN_RULES.ascentDecision ~= nil then
        return SPECIAL_SPAWN_RULES.ascentDecision
    end

    local conditions = SPECIAL_SPAWN_RULES.readConditions()
    local safe = USE_NINJA_FOR_DANGEROUS_AREA
        and not conditions.ashkin
        and not conditions.rain
        and conditions.et ~= nil
        and conditions.weatherId ~= nil

    SPECIAL_SPAWN_RULES.ascentDecision = safe and "ascent7" or "ascent5_only"

    logf(
        "Ascent 7 conditions: ET=%s weatherId=%s ashkin=%s rain=%s ninja=%s timeError=%s weatherError=%s. Using %s branch.",
        SPECIAL_SPAWN_RULES.formatTime(conditions.et),
        tostring(conditions.weatherId or "unavailable"),
        tostring(conditions.ashkin),
        tostring(conditions.rain),
        tostring(USE_NINJA_FOR_DANGEROUS_AREA),
        tostring(conditions.timeError or "none"),
        tostring(conditions.weatherError or "none"),
        SPECIAL_SPAWN_RULES.ascentDecision == "ascent7" and "Ascent 7" or "Ascent 5-only"
    )

    return SPECIAL_SPAWN_RULES.ascentDecision
end

function SPECIAL_SPAWN_RULES.recheckAscent7BeforeUnhide(entry)
    if entry == nil or entry.recheckAscentSafetyOnArrival ~= true then
        return true
    end

    if SPECIAL_SPAWN_RULES.ascentDecision ~= "ascent7" then
        return false
    end

    local conditions = SPECIAL_SPAWN_RULES.readConditions()
    local stillSafe = USE_NINJA_FOR_DANGEROUS_AREA
        and not conditions.ashkin
        and not conditions.rain
        and conditions.et ~= nil
        and conditions.weatherId ~= nil

    if stillSafe then
        SPECIAL_SPAWN_RULES.ascentLocked = true
        logf(
            "Ascent 7 safety recheck passed at %s: ET=%s weatherId=%s; locking Ascent 7 branch before removing Hide.",
            getSpotDescriptor(entry),
            SPECIAL_SPAWN_RULES.formatTime(conditions.et),
            tostring(conditions.weatherId)
        )
        return true
    end

    SPECIAL_SPAWN_RULES.ascentDecision = "ascent5_only"
    SPECIAL_SPAWN_RULES.ascentLocked = false
    logf(
        "Ascent 7 safety changed at %s: ET=%s weatherId=%s ashkin=%s rain=%s timeError=%s weatherError=%s; retaining Hide and switching to the Ascent 5-only branch.",
        getSpotDescriptor(entry),
        SPECIAL_SPAWN_RULES.formatTime(conditions.et),
        tostring(conditions.weatherId or "unavailable"),
        tostring(conditions.ashkin),
        tostring(conditions.rain),
        tostring(conditions.timeError or "none"),
        tostring(conditions.weatherError or "none")
    )
    return false
end

function SPECIAL_SPAWN_RULES.evaluate(entry)
    if entry == nil then
        return entry, false
    end

    if SPECIAL_SPAWN_RULES.shouldSkipHighCaverns(entry) then
        logf(
            "Skipping %s because the Ashkin spawn window is active.",
            getSpotDescriptor(entry)
        )
        return entry, true
    end

    if entry.rainSensitive == true then
        local weatherId, weatherError = SPECIAL_SPAWN_RULES.readWeatherId()
        local rain = SPECIAL_SPAWN_RULES.isRainWeather(weatherId)

        if rain and not USE_NINJA_FOR_DANGEROUS_AREA then
            logf(
                "Weather ID %s is treated as rain for %s, but Ninja mode is disabled; skipping. weatherError=%s.",
                tostring(weatherId or "unavailable"),
                getSpotDescriptor(entry),
                tostring(weatherError or "none")
            )
            return entry, true
        end

        if rain then
            local effectiveEntry = SPECIAL_SPAWN_RULES.copyEntry(entry)
            effectiveEntry.forceHidden = true
            effectiveEntry.note = "rain_sensitive_hidden"
            logf(
                "Weather ID %s is treated as rain; %s is rain-sensitive and will use Hide.",
                tostring(weatherId or "unavailable"),
                getSpotDescriptor(entry)
            )
            return effectiveEntry, false
        end
    end

    if entry.specialBranch ~= nil then
        local selectedBranch = SPECIAL_SPAWN_RULES.chooseAscentBranch()
        if entry.specialBranch ~= selectedBranch then
            logf(
                "Skipping %s because branch %s is inactive; selected branch=%s.",
                getSpotDescriptor(entry),
                tostring(entry.specialBranch),
                tostring(selectedBranch)
            )
            return entry, true
        end
    end

    return entry, false
end

local function waitUntil(predicate, timeoutSeconds, pollSeconds)
    local deadline = os.clock() + (tonumber(timeoutSeconds) or 0)
    local interval = tonumber(pollSeconds) or POLL_INTERVAL
    while os.clock() < deadline do
        if predicate() then
            return true
        end
        sleep(interval)
    end
    return predicate()
end

local function getCondition(flag)
    return Svc and Svc.Condition and flag ~= nil and Svc.Condition[flag] == true
end

local function isDead()
    return getCondition(CharacterCondition.dead)
end

local function isInCombat()
    return getCondition(CharacterCondition.inCombat)
end

local function hasStatusId(statusId)
    if Svc == nil or Svc.Objects == nil or Svc.Objects.LocalPlayer == nil then
        return false
    end
    local statusList = Svc.Objects.LocalPlayer.StatusList
    if statusList == nil then
        return false
    end
    for i = 0, statusList.Length - 1 do
        local status = statusList[i]
        if status ~= nil and tonumber(status.StatusId) == tonumber(statusId) then
            return true
        end
    end
    return false
end

local function isHidden()
    return hasStatusId(HIDDEN_STATUS_ID)
end

local function isMounted()
    return getCondition(CharacterCondition.mounted) or safeCall(function() return Player.Entity.IsMounted end) == true
end

local function getPlayerPosition()
    return safeCall(function() return Player.Entity.Position end)
end

local function getTerritoryType()
    return tonumber(safeCall(function() return Svc.ClientState.TerritoryType end))
end

local function isAddonReady(name)
    if name == nil or not Addons then
        return false
    end
    return safeCall(function()
        local addon = Addons.GetAddon(name)
        return addon ~= nil and addon.Ready
    end) == true
end

local function formatVector3(pos)
    if pos == nil then
        return "nil"
    end
    return string.format("(%.3f, %.3f, %.3f)", pos.X, pos.Y, pos.Z)
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

local function idText(value)
    if value == nil then
        return "nil"
    end
    return tostring(value)
end

local function getObjectTargetId(object)
    return safeCall(function() return object.TargetObjectId end)
        or safeCall(function() return object.TargetObject.GameObjectId end)
        or safeCall(function() return object.TargetObject.EntityId end)
end

local function logCombatDiagnostics(context, currentPosition)
    local player = safeCall(function() return Svc.Objects.LocalPlayer end)
    local playerGameObjectId = safeCall(function() return player.GameObjectId end)
    local playerEntityId = safeCall(function() return player.EntityId end)
    local playerAddress = safeCall(function() return player.Address end)

    logf(
        "Combat diagnostics context=%s pos=%s hidden=%s mounted=%s combat=%s playerGameObjectId=%s playerEntityId=%s playerAddress=%s.",
        tostring(context or "?"),
        formatVector3(currentPosition or getPlayerPosition()),
        tostring(isHidden()),
        tostring(isMounted()),
        tostring(isInCombat()),
        idText(playerGameObjectId),
        idText(playerEntityId),
        idText(playerAddress)
    )

    local target = safeCall(function() return Svc.Targets.Target end)
    if target ~= nil then
        logf(
            "Combat diagnostics currentTarget name=%s kind=%s dataId=%s gameObjectId=%s entityId=%s targetObjectId=%s pos=%s.",
            tostring(getObjectName(target) or "?"),
            tostring(safeCall(function() return target.ObjectKind end) or "?"),
            idText(safeCall(function() return target.DataId end)),
            idText(safeCall(function() return target.GameObjectId end)),
            idText(safeCall(function() return target.EntityId end)),
            idText(getObjectTargetId(target)),
            formatVector3(safeCall(function() return target.Position end))
        )
    else
        logf("Combat diagnostics currentTarget=nil.")
    end

    local origin = currentPosition or getPlayerPosition()
    local nearby = {}
    local objectCount = tonumber(safeCall(function() return Svc.Objects.Length end)) or 0
    for i = 0, math.max(0, objectCount - 1) do
        local object = safeCall(function() return Svc.Objects[i] end)
        if object ~= nil then
            local kind = tostring(safeCall(function() return object.ObjectKind end) or "?")
            if string.find(string.lower(kind), "battlenpc", 1, true) ~= nil then
                local position = safeCall(function() return object.Position end)
                local distance = distance3d(origin, position)
                if position ~= nil and distance <= COMBAT_DIAGNOSTIC_RADIUS then
                    local targetObjectId = getObjectTargetId(object)
                    local targetText = idText(targetObjectId)
                    local targetsPlayer =
                        (playerGameObjectId ~= nil and targetText == idText(playerGameObjectId))
                        or (playerEntityId ~= nil and targetText == idText(playerEntityId))
                        or (playerAddress ~= nil and targetText == idText(playerAddress))

                    table.insert(nearby, {
                        object = object,
                        distance = distance,
                        position = position,
                        kind = kind,
                        targetObjectId = targetObjectId,
                        targetsPlayer = targetsPlayer,
                    })
                end
            end
        end
    end

    table.sort(nearby, function(a, b)
        if a.targetsPlayer ~= b.targetsPlayer then
            return a.targetsPlayer
        end
        return a.distance < b.distance
    end)

    if #nearby == 0 then
        logf("Combat diagnostics found no BattleNpc objects within %.1fy.", COMBAT_DIAGNOSTIC_RADIUS)
        return
    end

    for i = 1, math.min(#nearby, COMBAT_DIAGNOSTIC_LIMIT) do
        local candidate = nearby[i]
        local object = candidate.object
        logf(
            "Combat actor %d/%d name=%s kind=%s dist=%.1f targetsPlayer=%s targetObjectId=%s dataId=%s gameObjectId=%s entityId=%s hp=%s/%s pos=%s.",
            i,
            #nearby,
            tostring(getObjectName(object) or "?"),
            tostring(candidate.kind),
            candidate.distance,
            tostring(candidate.targetsPlayer),
            idText(candidate.targetObjectId),
            idText(safeCall(function() return object.DataId end)),
            idText(safeCall(function() return object.GameObjectId end)),
            idText(safeCall(function() return object.EntityId end)),
            idText(safeCall(function() return object.CurrentHp end)),
            idText(safeCall(function() return object.MaxHp end)),
            formatVector3(candidate.position)
        )
    end
end

local function resetStealthTrace(context)
    STEALTH_TRACE.context = tostring(context or "?")
    STEALTH_TRACE.hidden = nil
    STEALTH_TRACE.mounted = nil
    STEALTH_TRACE.combat = nil
end

local function traceStealthState(context, currentPosition, targetPosition)
    local hidden = isHidden()
    local mounted = isMounted()
    local combat = isInCombat()
    local contextText = tostring(context or STEALTH_TRACE.context or "?")

    if STEALTH_TRACE.context ~= contextText
        or STEALTH_TRACE.hidden ~= hidden
        or STEALTH_TRACE.mounted ~= mounted
        or STEALTH_TRACE.combat ~= combat then

        local remaining = targetPosition ~= nil and distanceFlat(currentPosition, targetPosition) or -1
        logf(
            "Stealth state context=%s hidden=%s mounted=%s combat=%s pos=%s remaining=%.1fy.",
            contextText,
            tostring(hidden),
            tostring(mounted),
            tostring(combat),
            formatVector3(currentPosition),
            remaining
        )

        local combatStarted = combat and STEALTH_TRACE.combat == false
        STEALTH_TRACE.context = contextText
        STEALTH_TRACE.hidden = hidden
        STEALTH_TRACE.mounted = mounted
        STEALTH_TRACE.combat = combat

        if combatStarted then
            logCombatDiagnostics(contextText, currentPosition)
        end
    end
end

local function isNearBaseCamp(distance)
    return distanceFlat(getPlayerPosition(), BASE_CAMP_POSITION) <= (tonumber(distance) or BASE_START_DISTANCE)
end

local function getFreeInventorySlots()
    if not (Inventory and Inventory.GetFreeInventorySlots) then
        return nil
    end
    return tonumber(safeCall(function()
        return Inventory.GetFreeInventorySlots()
    end))
end


-- Global namespace avoids adding more chunk-level locals in NLua.
-- Only the four normal player inventory bags are scanned.
COFFER_INVENTORY = COFFER_INVENTORY or {}
COFFER_INVENTORY.containerNames = COFFER_INVENTORY.containerNames or {
    "Inventory1",
    "Inventory2",
    "Inventory3",
    "Inventory4",
}

function COFFER_INVENTORY.snapshot()
    local snapshot = {
        totals = {},
        nonEmptySlots = 0,
        slotsRead = 0,
        containersRead = 0,
    }

    if Inventory == nil then
        return snapshot, false, "inventory_module_unavailable"
    end

    for _, containerName in ipairs(COFFER_INVENTORY.containerNames) do
        local container = nil
        if Inventory.GetInventoryContainer ~= nil then
            container = safeCall(function()
                return Inventory.GetInventoryContainer(containerName)
            end)
        end
        if container == nil then
            container = safeCall(function()
                return Inventory[containerName]
            end)
        end
        if container == nil then
            return snapshot, false, "container_unavailable:" .. tostring(containerName)
        end

        local slotCount = tonumber(safeCall(function()
            return container.Count
        end))
        if slotCount == nil or slotCount < 0 then
            return snapshot, false, "container_count_unavailable:" .. tostring(containerName)
        end

        snapshot.containersRead = snapshot.containersRead + 1
        for slot = 0, slotCount - 1 do
            local item = nil
            if Inventory.GetInventoryItemBySlot ~= nil then
                item = safeCall(function()
                    return Inventory.GetInventoryItemBySlot(containerName, slot)
                end)
            end
            if item == nil then
                item = safeCall(function()
                    return container[slot]
                end)
            end
            if item == nil then
                return snapshot, false, string.format(
                    "slot_unavailable:%s:%d",
                    tostring(containerName),
                    slot
                )
            end

            snapshot.slotsRead = snapshot.slotsRead + 1
            local itemId = tonumber(safeCall(function() return item.ItemId end))
            local isEmpty = safeCall(function() return item.IsEmpty end)
            if isEmpty == nil then
                isEmpty = itemId == nil or itemId == 0
            end

            if not isEmpty then
                local baseItemId =
                    tonumber(safeCall(function() return item.BaseItemId end))
                    or itemId
                local quantity =
                    tonumber(safeCall(function() return item.Count end))
                local isHighQuality =
                    safeCall(function() return item.IsHighQuality end) == true

                if itemId == nil
                    or itemId == 0
                    or baseItemId == nil
                    or quantity == nil
                    or quantity < 0 then

                    return snapshot, false, string.format(
                        "slot_data_invalid:%s:%d",
                        tostring(containerName),
                        slot
                    )
                end

                local key =
                    tostring(baseItemId)
                    .. ":"
                    .. (isHighQuality and "hq" or "normal")

                local aggregate = snapshot.totals[key]
                if aggregate == nil then
                    aggregate = {
                        itemId = itemId,
                        baseItemId = baseItemId,
                        isHighQuality = isHighQuality,
                        count = 0,
                    }
                    snapshot.totals[key] = aggregate
                end

                aggregate.count = aggregate.count + quantity
                snapshot.nonEmptySlots = snapshot.nonEmptySlots + 1
            end
        end
    end

    return snapshot, true, nil
end

function COFFER_INVENTORY.findPositiveDeltas(beforeSnapshot, afterSnapshot)
    local deltas = {}
    local beforeTotals = beforeSnapshot and beforeSnapshot.totals or {}
    local afterTotals = afterSnapshot and afterSnapshot.totals or {}

    for key, afterEntry in pairs(afterTotals) do
        local beforeEntry = beforeTotals[key]
        local beforeCount = beforeEntry and tonumber(beforeEntry.count) or 0
        local afterCount = tonumber(afterEntry.count) or 0

        if afterCount > beforeCount then
            deltas[#deltas + 1] = {
                itemId = afterEntry.itemId,
                baseItemId = afterEntry.baseItemId,
                isHighQuality = afterEntry.isHighQuality == true,
                beforeCount = beforeCount,
                afterCount = afterCount,
                added = afterCount - beforeCount,
            }
        end
    end

    table.sort(deltas, function(a, b)
        if a.baseItemId == b.baseItemId then
            return (a.isHighQuality and 1 or 0)
                < (b.isHighQuality and 1 or 0)
        end
        return (a.baseItemId or 0) < (b.baseItemId or 0)
    end)

    return deltas
end

function COFFER_INVENTORY.formatDeltas(deltas)
    local parts = {}
    for _, delta in ipairs(deltas or {}) do
        parts[#parts + 1] = string.format(
            "ItemId=%s BaseItemId=%s HQ=%s count %d -> %d (+%d)",
            tostring(delta.itemId or "?"),
            tostring(delta.baseItemId or "?"),
            tostring(delta.isHighQuality == true),
            tonumber(delta.beforeCount) or 0,
            tonumber(delta.afterCount) or 0,
            tonumber(delta.added) or 0
        )
    end
    return table.concat(parts, "; ")
end

local function getSpotKey(entry)
    if entry == nil then
        return "?"
    end
    return string.format("%s|%s", tostring(entry.area or "?"), tostring(entry.label or "?"))
end

getSpotDescriptor = function(entry)
    local key = getSpotKey(entry)
    if entry ~= nil and entry.note ~= nil and tostring(entry.note) ~= "" then
        return string.format("%s [%s]", key, tostring(entry.note))
    end
    return key
end

getEntryAggroLevel = function(entry)
    local configured = tonumber(entry and entry.aggroLevel)
    if configured ~= nil then
        return configured
    end
    if entry ~= nil and entry.routeOnly then
        return DEFAULT_ROUTE_ONLY_AGGRO_LEVEL
    end
    return 0
end

local function isDangerousSpot(entry)
    if not USE_NINJA_FOR_DANGEROUS_AREA or entry == nil then
        return false
    end
    if entry.forceUnhidden == true then
        return false
    end
    if entry.forceHidden == true then
        return true
    end
    return getEntryAggroLevel(entry) > MAX_AGGRO_LEVEL
end

local function getHideThreshold(entry)
    return math.max(10, tonumber(entry and entry.hideThreshold) or HIDE_THRESHOLD_DISTANCE)
end

local function getArrivalDistance(entry)
    return math.max(0.5, tonumber(entry and entry.stopDistance) or ARRIVAL_DISTANCE)
end

local function isWithinHideThreshold(entry, position)
    if entry ~= nil and entry.disableExitHideThreshold == true then
        return false
    end
    return isDangerousSpot(entry)
        and distanceFlat(position, entry.general) <= getHideThreshold(entry)
end

local function ensureMounted()
    if not MOUNT_ENABLED then
        logf("Mount request skipped because mounting is disabled.")
        return true
    end
    if isMounted() then
        logf("Mount request skipped because player is already mounted.")
        return true
    end

    logf(
        "Mount request starting pos=%s hidden=%s combat=%s timeout=%.1fs.",
        formatVector3(getPlayerPosition()),
        tostring(isHidden()),
        tostring(isInCombat()),
        MOUNT_TIMEOUT
    )

    if not (Actions and Actions.ExecuteGeneralAction) then
        logf("Mount request failed because ExecuteGeneralAction is unavailable.")
        return false
    end

    local deadline = os.clock() + MOUNT_TIMEOUT
    local attempts = 0
    while os.clock() < deadline do
        attempts = attempts + 1
        pcall(function() Actions.ExecuteGeneralAction(GENERAL_ACTION_MOUNT) end)
        sleep(1.0)
        if isMounted() then
            logf(
                "Mount request succeeded after %d attempt(s) pos=%s hidden=%s combat=%s.",
                attempts,
                formatVector3(getPlayerPosition()),
                tostring(isHidden()),
                tostring(isInCombat())
            )
            return true
        end
    end

    logf(
        "Mount request failed after %d attempt(s) pos=%s hidden=%s combat=%s.",
        attempts,
        formatVector3(getPlayerPosition()),
        tostring(isHidden()),
        tostring(isInCombat())
    )
    return false
end

local function ensureDismounted(timeoutSeconds)
    if not isMounted() then
        return true
    end

    logf(
        "Dismount request starting pos=%s hidden=%s combat=%s.",
        formatVector3(getPlayerPosition()),
        tostring(isHidden()),
        tostring(isInCombat())
    )

    if not (Actions and Actions.ExecuteGeneralAction) then
        logf("Dismount request failed because ExecuteGeneralAction is unavailable.")
        return false
    end

    local deadline = os.clock() + (timeoutSeconds or MOUNT_TIMEOUT)
    local attempts = 0
    while os.clock() < deadline do
        attempts = attempts + 1
        pcall(function() Actions.ExecuteGeneralAction(GENERAL_ACTION_DISMOUNT) end)
        sleep(0.5)
        if not isMounted() then
            logf(
                "Dismount request succeeded after %d attempt(s) pos=%s hidden=%s combat=%s.",
                attempts,
                formatVector3(getPlayerPosition()),
                tostring(isHidden()),
                tostring(isInCombat())
            )
            return true
        end
    end

    local dismounted = not isMounted()
    logf(
        "Dismount request finished success=%s after %d attempt(s) pos=%s hidden=%s combat=%s.",
        tostring(dismounted),
        attempts,
        formatVector3(getPlayerPosition()),
        tostring(isHidden()),
        tostring(isInCombat())
    )
    return dismounted
end

local function equipGearsetNumber(gearsetNumber)
    if gearsetNumber == nil or gearsetNumber <= 0 then
        return false, "configured Ninja gearset number is invalid"
    end
    if not (Player and Player.GetGearset) then
        return false, "Player.GetGearset unavailable"
    end
    local slot = gearsetNumber - 1
    local slotDisplay = slot + 1
    local gearset = Player.GetGearset(slot)
    if not gearset or gearset.IsValid ~= true then
        return false, string.format("gearset number %d invalid or unavailable", slotDisplay)
    end
    local gearsetName = gearset.Name
    if gearsetName and gearsetName.GetText then
        local okName, resolved = pcall(function()
            return gearsetName:GetText()
        end)
        if okName and type(resolved) == "string" and resolved ~= "" then
            gearsetName = resolved
        end
    end
    gearsetName = tostring(gearsetName or ("Gearset " .. tostring(slotDisplay)))
    logf("Equipping Ninja gearset number %d (%s).", slotDisplay, gearsetName)
    local ok, err = pcall(function()
        gearset:Equip()
    end)
    if not ok then
        return false, tostring(err)
    end
    sleep(1.0)
    return true, nil
end

local function ensureNinjaGearset()
    if not USE_NINJA_FOR_DANGEROUS_AREA then
        return true
    end
    if ninjaGearsetEquipped then
        return true
    end
    logf("Ninja dangerous-area mode enabled; equipping gearset number %d.", NINJA_GEARSET_NUMBER)
    local ok, err = equipGearsetNumber(NINJA_GEARSET_NUMBER)
    if not ok then
        error(string.format("Failed to equip Ninja gearset: %s", tostring(err)))
    end
    ninjaGearsetEquipped = true
    return true
end

local function tryHideOnce()
    if isHidden() then
        return true
    end
    if not ensureDismounted(5.0) then
        return false
    end
    if not (Actions and Actions.ExecuteAction) then
        logf("Hide action unavailable.")
        return false
    end

    logf(
        "Hide action requested actionId=%d pos=%s mounted=%s combat=%s.",
        HIDE_ACTION_ID,
        formatVector3(getPlayerPosition()),
        tostring(isMounted()),
        tostring(isInCombat())
    )

    pcall(function() Actions.ExecuteAction(HIDE_ACTION_ID) end)
    local applied = waitUntil(function()
        return isHidden()
    end, 1.5, 0.1)

    logf(
        "Hide action result applied=%s pos=%s mounted=%s combat=%s.",
        tostring(applied),
        formatVector3(getPlayerPosition()),
        tostring(isMounted()),
        tostring(isInCombat())
    )
    return applied
end

local function ensureHiddenOrAbort(entry)
    if isMounted() then
        logf("Mounted while preparing hidden travel for %s; dismounting before Hide validation.", getSpotDescriptor(entry))
        if not ensureDismounted(5.0) then
            if isInCombat() then
                stopPathing()
                dangerousCombatAbortTriggered = true
                logCombatDiagnostics("dismount-failed:" .. getSpotDescriptor(entry), getPlayerPosition())
                logf(
                    "Could not dismount for hidden travel to %s because combat started; aborting pass without attempting Return.",
                    getSpotDescriptor(entry)
                )
                return false
            end
            logf("Could not dismount for hidden travel to %s; returning to base and stopping script.", getSpotDescriptor(entry))
            returnToBase()
            error(string.format("Could not dismount for hidden travel to %s", getSpotDescriptor(entry)))
        end
    end

    if isInCombat() then
        stopPathing()
        dangerousCombatAbortTriggered = true
        logCombatDiagnostics("hide-blocked:" .. getSpotDescriptor(entry), getPlayerPosition())
        logf(
            "Combat started before Hide could be validated for %s; aborting pass without attempting Hide or Return.",
            getSpotDescriptor(entry)
        )
        return false
    end

    if isHidden() then
        logf("Hide status %d already active for %s.", HIDDEN_STATUS_ID, getSpotDescriptor(entry))
        return true
    end

    logf("Hide status %d missing for %s; preparing Hide travel.", HIDDEN_STATUS_ID, getSpotDescriptor(entry))
    if tryHideOnce() then
        logf("Hide status %d applied for %s.", HIDDEN_STATUS_ID, getSpotDescriptor(entry))
        return true
    end

    if isInCombat() then
        stopPathing()
        dangerousCombatAbortTriggered = true
        logCombatDiagnostics("hide-first-attempt:" .. getSpotDescriptor(entry), getPlayerPosition())
        logf(
            "Combat started during the first Hide attempt for %s; aborting pass without retrying Hide or attempting Return.",
            getSpotDescriptor(entry)
        )
        return false
    end

    logf("Hide failed for %s; retrying once.", getSpotDescriptor(entry))
    if tryHideOnce() then
        logf("Hide status %d applied for %s on retry.", HIDDEN_STATUS_ID, getSpotDescriptor(entry))
        return true
    end

    if isInCombat() then
        stopPathing()
        dangerousCombatAbortTriggered = true
        logCombatDiagnostics("hide-second-attempt:" .. getSpotDescriptor(entry), getPlayerPosition())
        logf(
            "Combat started during the second Hide attempt for %s; aborting pass without attempting Return.",
            getSpotDescriptor(entry)
        )
        return false
    end

    logf("Hide failed twice for %s; returning to base and stopping script.", getSpotDescriptor(entry))
    returnToBase()
    error(string.format("Hide failed twice for %s", getSpotDescriptor(entry)))
end

local function prepareForTravel(previousEntry, currentEntry)
    if USE_NINJA_FOR_DANGEROUS_AREA then
        ensureNinjaGearset()
    end
    return true
end

returnToBase = function()
    if not (Actions and Actions.ExecuteGeneralAction) then
        return false
    end
    logf("Returning to base.")
    pcall(function() Actions.ExecuteGeneralAction(GENERAL_ACTION_RETURN) end)
    local deadline = os.clock() + 3.0
    local returnStarted = false
    while os.clock() < deadline do
        if isAddonReady("SelectYesno") then
            logf("Confirming Return SelectYesno.")
            yield("/callback SelectYesno true 0")
            returnStarted = waitUntil(function()
                return getCondition(CharacterCondition.casting) or getCondition(CharacterCondition.betweenAreas)
            end, 3.0, 0.1)
            break
        end
        if getCondition(CharacterCondition.casting) or getCondition(CharacterCondition.betweenAreas) then
            returnStarted = true
            break
        end
        sleep(POLL_INTERVAL)
    end
    if not returnStarted then
        logf("Return did not start promptly.")
        return false
    end
    return true
end

local function pathfindTo(position)
    if not (IPC and IPC.vnavmesh and IPC.vnavmesh.PathfindAndMoveTo) then
        return false
    end
    return pcall(function()
        IPC.vnavmesh.PathfindAndMoveTo(position, false)
    end)
end

local function resolvePath(task, timeoutSeconds)
    if task == nil then
        return nil, "nil_task"
    end

    local deadline = os.clock() + (tonumber(timeoutSeconds) or DEATH_PATH_DIAGNOSTIC_TIMEOUT)
    while os.clock() < deadline do
        local completed = safeCall(function() return task.IsCompleted end)
        if completed == true then
            local result = safeCall(function() return task.Result end)
            if result ~= nil then
                return result, nil
            end
            return nil, "nil_result"
        end
        sleep(0.1)
    end

    return nil, "timeout"
end

local function pathDistance(path)
    local count = tonumber(path and path.Count) or tonumber(path and #path) or 0
    local total = 0
    local previous = nil
    for i = 0, count - 1 do
        local point = path[i]
        if point ~= nil then
            if previous ~= nil then
                total = total + distance3d(previous, point)
            end
            previous = point
        end
    end
    return count, total
end

local function logPathDiagnostic(label, fromPosition, toPosition)
    if fromPosition == nil or toPosition == nil then
        logf("Death path %s unavailable from=%s to=%s.", tostring(label), formatVector3(fromPosition), formatVector3(toPosition))
        return
    end

    local flatDistance = distanceFlat(fromPosition, toPosition)
    if not (IPC and IPC.vnavmesh and IPC.vnavmesh.Pathfind) then
        logf("Death path %s flat=%.3f mesh unavailable from=%s to=%s.", tostring(label), flatDistance, formatVector3(fromPosition), formatVector3(toPosition))
        return
    end

    local task = safeCall(function()
        return IPC.vnavmesh.Pathfind(fromPosition, toPosition, false)
    end)
    if task == nil then
        logf("Death path %s flat=%.3f returned nil task from=%s to=%s.", tostring(label), flatDistance, formatVector3(fromPosition), formatVector3(toPosition))
        return
    end

    local path, err = resolvePath(task, DEATH_PATH_DIAGNOSTIC_TIMEOUT)
    if path == nil then
        logf("Death path %s flat=%.3f mesh unavailable reason=%s from=%s to=%s.", tostring(label), flatDistance, tostring(err or "unknown"), formatVector3(fromPosition), formatVector3(toPosition))
        return
    end

    local count, meshDistance = pathDistance(path)
    logf("Death path %s count=%d flat=%.3f mesh=%.3f from=%s to=%s.", tostring(label), count, flatDistance, meshDistance, formatVector3(fromPosition), formatVector3(toPosition))
end

local function logDeathPathDiagnostics()
    local previousEntry = ROUTE_CONTEXT.previousEntry
    local currentEntry = ROUTE_CONTEXT.currentEntry
    local deathPosition = getPlayerPosition()

    logf(
        "Death diagnostics previous=%s current=%s death=%s.",
        getSpotDescriptor(previousEntry),
        getSpotDescriptor(currentEntry),
        formatVector3(deathPosition)
    )

    if previousEntry ~= nil then
        logf("Death diagnostics previous position=%s.", formatVector3(previousEntry.general))
    end
    if currentEntry ~= nil then
        logf("Death diagnostics current position=%s.", formatVector3(currentEntry.general))
    end

    if previousEntry ~= nil then
        logPathDiagnostic("previous_to_death", previousEntry.general, deathPosition)
    end
    if currentEntry ~= nil then
        logPathDiagnostic("death_to_current", deathPosition, currentEntry.general)
    end
    if previousEntry ~= nil and currentEntry ~= nil then
        logPathDiagnostic("previous_to_current", previousEntry.general, currentEntry.general)
    end
end

stopPathing = function()
    if IPC and IPC.vnavmesh and IPC.vnavmesh.Stop then
        pcall(function() IPC.vnavmesh.Stop() end)
    end
end

local function handleDeathReturn()
    stopPathing()
    logf("Player died; accepting return prompt.")
    logDeathPathDiagnostics()

    local promptSeen = waitUntil(function()
        return isAddonReady("SelectYesno")
            or getCondition(CharacterCondition.betweenAreas)
            or (not isDead() and distanceFlat(getPlayerPosition(), BASE_CAMP_POSITION) <= BASE_START_DISTANCE)
    end, 10.0, 0.1)

    if not promptSeen then
        error("Player died during route; death return prompt did not appear.")
    end

    if isAddonReady("SelectYesno") then
        logf("Confirming death return SelectYesno.")
        yield("/callback SelectYesno true 0")
    end

    local returned = waitUntil(function()
        return getTerritoryType() == SOUTH_HORN_TERRITORY_ID
            and not isDead()
            and distanceFlat(getPlayerPosition(), BASE_CAMP_POSITION) <= BASE_START_DISTANCE
    end, DEATH_RETURN_TIMEOUT, 0.5)

    if not returned then
        error("Player died during route; failed to return to base after accepting prompt.")
    end

    deathReturnTriggered = true
    logf("Player died during route; returned to base.")
    return false
end

local function isVnavRunning()
    return safeCall(function() return IPC.vnavmesh.IsRunning() end) == true
end

local function isVnavPathfindInProgress()
    return safeCall(function() return IPC.vnavmesh.PathfindInProgress() end) == true
end

local function isVnavActive()
    return isVnavPathfindInProgress() or isVnavRunning()
end

local function moveToPosition(targetPosition, stopDistance, allowMount, onStep)
    if deathReturnTriggered then
        stopPathing()
        return false, getPlayerPosition()
    end

    local startPosition = getPlayerPosition()
    if distanceFlat(startPosition, targetPosition) <= stopDistance then
        return true, getPlayerPosition()
    end
    if allowMount ~= false then
        ensureMounted()
    end
    if not pathfindTo(targetPosition) then
        return false, getPlayerPosition()
    end

    local started = false
    local startDeadline = os.clock() + MOVE_START_TIMEOUT
    while os.clock() < startDeadline do
        if isVnavActive() then
            started = true
            break
        end
        sleep(POLL_INTERVAL)
    end
    if not started then
        stopPathing()
        return false, getPlayerPosition()
    end

    local hardDeadline = os.clock() + MOVE_HARD_TIMEOUT
    local lastProgressPosition = startPosition
    local lastProgressAt = os.clock()
    while os.clock() < hardDeadline do
        if isDead() then
            return handleDeathReturn(), getPlayerPosition()
        end
        local currentPosition = getPlayerPosition()
        if onStep ~= nil then
            pcall(onStep, currentPosition, targetPosition)
        end
        if distanceFlat(currentPosition, targetPosition) <= stopDistance then
            stopPathing()
            return true, currentPosition
        end
        if distanceFlat(lastProgressPosition, currentPosition) >= MOVE_PROGRESS_MIN_MOVE then
            lastProgressPosition = currentPosition
            lastProgressAt = os.clock()
        elseif (os.clock() - lastProgressAt) >= MOVE_PROGRESS_TIMEOUT then
            stopPathing()
            return false, currentPosition
        end
        if not isVnavActive() then
            stopPathing()
            currentPosition = getPlayerPosition()
            return distanceFlat(currentPosition, targetPosition) <= stopDistance, currentPosition
        end
        sleep(POLL_INTERVAL)
    end
    stopPathing()
    return false, getPlayerPosition()
end

local function moveToPositionWithRetry(targetPosition, stopDistance, label, allowMount)
    local onStep = type(allowMount) == "table" and allowMount.onStep or nil
    local actualAllowMount = type(allowMount) == "table" and allowMount.allowMount or allowMount
    local moved, endPosition = moveToPosition(targetPosition, stopDistance, actualAllowMount, onStep)
    if moved then
        return true, endPosition
    end
    if deathReturnTriggered then
        stopPathing()
        return false, endPosition
    end
    local remaining = distanceFlat(endPosition, targetPosition)
    logf("Move failed for %s at %s; remaining %.1fy. Retrying once.", tostring(label or "point"), formatVector3(targetPosition), remaining)
    sleep(0.5)
    if deathReturnTriggered then
        stopPathing()
        return false, getPlayerPosition()
    end
    return moveToPosition(targetPosition, stopDistance, actualAllowMount, onStep)
end

local function moveToPositionHiddenWithRetry(targetPosition, stopDistance, label, hiddenEntry, onStep)
    for attempt = 1, 2 do
        if deathReturnTriggered then
            stopPathing()
            return false, getPlayerPosition()
        end
        local traceContext = string.format(
            "hidden-position:%s:%s:attempt-%d",
            getSpotDescriptor(hiddenEntry),
            tostring(label or "point"),
            attempt
        )
        resetStealthTrace(traceContext)
        traceStealthState(traceContext, getPlayerPosition(), targetPosition)

        if isInCombat() then
            stopPathing()
            dangerousCombatAbortTriggered = true
            logCombatDiagnostics(traceContext, getPlayerPosition())
            logf(
                "Combat detected near dangerous spot %s while moving to %s; aborting hidden movement. Mounted fallback is disabled inside the hide threshold.",
                getSpotDescriptor(hiddenEntry),
                tostring(label or "point")
            )
            return false, getPlayerPosition()
        end

        if not ensureHiddenOrAbort(hiddenEntry) then
            return false, getPlayerPosition()
        end
        traceStealthState(traceContext, getPlayerPosition(), targetPosition)

        local interruptedReason = nil
        local moved, endPosition = moveToPosition(targetPosition, stopDistance, false, function(currentPosition, finalTarget)
            traceStealthState(traceContext, currentPosition, finalTarget)

            if isMounted() then
                interruptedReason = "mounted"
                stopPathing()
                return
            end
            if not isHidden() then
                if isInCombat() then
                    interruptedReason = "combat"
                    stopPathing()
                    return
                end
                interruptedReason = "hide_missing"
                stopPathing()
                return
            end
            if onStep ~= nil then
                pcall(onStep, currentPosition, finalTarget)
            end
        end)

        if moved then
            return true, endPosition
        end

        if deathReturnTriggered then
            stopPathing()
            return false, endPosition
        end

        if interruptedReason == "combat" then
            stopPathing()
            dangerousCombatAbortTriggered = true
            logf(
                "Combat interrupted hidden movement near %s while moving to %s; aborting route instead of continuing mounted.",
                getSpotDescriptor(hiddenEntry),
                tostring(label or "point")
            )
            return false, endPosition
        end

        if interruptedReason == nil or attempt >= 2 then
            return false, endPosition
        end

        logf(
            "Hidden movement interrupted for %s while moving to %s (%s); enforcing dismount, reapplying Hide, and retrying.",
            getSpotDescriptor(hiddenEntry),
            tostring(label or "point"),
            interruptedReason
        )
        sleep(0.25)
    end
    return false, getPlayerPosition()
end

local function moveToSpotWithApproachScan(entry, allowMount, stopDistance, stopPredicate, hiddenEntry)
    if deathReturnTriggered then
        stopPathing()
        return false, getPlayerPosition(), nil
    end

    local targetPosition = entry.general
    local targetStopDistance = tonumber(stopDistance) or ARRIVAL_DISTANCE
    local allowApproachScan = not (entry and entry.routeOnly)
    local startPosition = getPlayerPosition()
    local traceContext = nil

    if hiddenEntry ~= nil then
        traceContext = string.format(
            "hidden-route:%s->%s",
            getSpotDescriptor(hiddenEntry),
            getSpotDescriptor(entry)
        )
        resetStealthTrace(traceContext)
        traceStealthState(traceContext, startPosition, targetPosition)
    end
    if distanceFlat(startPosition, targetPosition) <= targetStopDistance then
        return true, getPlayerPosition(), nil
    end
    if hiddenEntry ~= nil then
        if not ensureHiddenOrAbort(hiddenEntry) then
            return false, getPlayerPosition(), nil, "combat"
        end
    end
    if allowMount ~= false then
        ensureMounted()
    end
    if not pathfindTo(targetPosition) then
        return false, getPlayerPosition(), nil
    end

    local started = false
    local startDeadline = os.clock() + MOVE_START_TIMEOUT
    while os.clock() < startDeadline do
        if isVnavActive() then
            started = true
            break
        end
        sleep(POLL_INTERVAL)
    end
    if not started then
        stopPathing()
        return false, getPlayerPosition(), nil
    end

    local hardDeadline = os.clock() + MOVE_HARD_TIMEOUT
    local lastProgressPosition = startPosition
    local lastProgressAt = os.clock()
    local lastApproachScanAt = 0
    while os.clock() < hardDeadline do
        if isDead() then
            return handleDeathReturn(), getPlayerPosition(), nil
        end
        local currentPosition = getPlayerPosition()
        local remainingDistance = distanceFlat(currentPosition, targetPosition)

        if hiddenEntry ~= nil then
            traceStealthState(traceContext, currentPosition, targetPosition)

            if isMounted() then
                stopPathing()
                return false, currentPosition, nil, "mounted"
            end
            if not isHidden() then
                if isInCombat() then
                    stopPathing()
                    return false, currentPosition, nil, "combat"
                end
                stopPathing()
                return false, currentPosition, nil, "hide_missing"
            end
        end

        if allowApproachScan and remainingDistance <= APPROACH_SCAN_TRIGGER_DISTANCE and (os.clock() - lastApproachScanAt) >= APPROACH_SCAN_POLL_INTERVAL then
            lastApproachScanAt = os.clock()
            local visible = collectVisibleCoffers(SCAN_RADIUS)
            if #visible > 0 then
                stopPathing()
                logf("Approach scan found visible Treasure Coffer near %s with %.1fy remaining to mapped point.", getSpotDescriptor(entry), remainingDistance)
                return true, currentPosition, visible[1]
            end
        end

        if stopPredicate ~= nil and stopPredicate(currentPosition, targetPosition) then
            stopPathing()
            return true, currentPosition, nil
        end

        if remainingDistance <= targetStopDistance then
            stopPathing()
            return true, currentPosition, nil
        end

        if distanceFlat(lastProgressPosition, currentPosition) >= MOVE_PROGRESS_MIN_MOVE then
            lastProgressPosition = currentPosition
            lastProgressAt = os.clock()
        elseif (os.clock() - lastProgressAt) >= MOVE_PROGRESS_TIMEOUT then
            stopPathing()
            return false, currentPosition, nil
        end
        if not isVnavActive() then
            stopPathing()
            currentPosition = getPlayerPosition()
            return distanceFlat(currentPosition, targetPosition) <= targetStopDistance, currentPosition, nil
        end
        sleep(POLL_INTERVAL)
    end
    stopPathing()
    return false, getPlayerPosition(), nil
end

local function moveToSpotWithApproachScanHidden(entry, stopDistance, hiddenEntry, stopPredicate)
    for attempt = 1, 2 do
        if deathReturnTriggered then
            stopPathing()
            return false, getPlayerPosition(), nil
        end
        if isInCombat() then
            stopPathing()
            dangerousCombatAbortTriggered = true
            logf(
                "Combat detected near dangerous spot %s while traveling to %s; aborting route. Mounted fallback is disabled inside the hide threshold.",
                getSpotDescriptor(hiddenEntry),
                getSpotDescriptor(entry)
            )
            return false, getPlayerPosition(), nil
        end

        local moved, endPosition, earlyMatch, interruptedReason =
            moveToSpotWithApproachScan(entry, false, stopDistance, stopPredicate, hiddenEntry)

        if deathReturnTriggered then
            stopPathing()
            return false, endPosition, nil
        end

        if moved or earlyMatch ~= nil then
            return moved, endPosition, earlyMatch
        end

        if interruptedReason == "combat" then
            stopPathing()
            dangerousCombatAbortTriggered = true
            logf(
                "Combat interrupted hidden travel near %s while traveling to %s; aborting route instead of continuing mounted.",
                getSpotDescriptor(hiddenEntry),
                getSpotDescriptor(entry)
            )
            return false, endPosition, nil
        end

        if interruptedReason == nil or attempt >= 2 then
            return moved, endPosition, earlyMatch
        end

        logf(
            "Hidden movement interrupted for %s while traveling to %s (%s); enforcing dismount, reapplying Hide, and retrying.",
            getSpotDescriptor(hiddenEntry),
            getSpotDescriptor(entry),
            interruptedReason
        )
        sleep(0.25)
    end
    return false, getPlayerPosition(), nil
end

local function getHideThresholdContext(previousEntry, currentEntry, position)
    if isWithinHideThreshold(currentEntry, position) then
        return currentEntry
    end
    if isWithinHideThreshold(previousEntry, position) then
        return previousEntry
    end
    return currentEntry or previousEntry
end

local function moveToSpotRespectingHideThreshold(previousEntry, entry)
    if deathReturnTriggered then
        stopPathing()
        return false, getPlayerPosition(), nil
    end

    prepareForTravel(previousEntry, entry)
    local arrivalDistance = getArrivalDistance(entry)
    local position = getPlayerPosition()

    -- Stay hidden only while leaving a previously dangerous location.
    if isWithinHideThreshold(previousEntry, position) then
        if isInCombat() then
            stopPathing()
            dangerousCombatAbortTriggered = true
            logCombatDiagnostics(
                "combat-leaving-dangerous:" .. getSpotDescriptor(previousEntry),
                position
            )
            logf(
                "Combat detected while still inside the hide threshold of previous dangerous spot %s; aborting pass.",
                getSpotDescriptor(previousEntry)
            )
            return false, position, nil
        end

        logf(
            "Inside hide threshold %.1fy of previous dangerous spot %s; staying hidden until clear.",
            getHideThreshold(previousEntry),
            getSpotDescriptor(previousEntry)
        )

        local moved, endPosition, earlyMatch =
            moveToSpotWithApproachScanHidden(
                entry,
                arrivalDistance,
                previousEntry,
                function(currentPosition)
                    return not isWithinHideThreshold(previousEntry, currentPosition)
                end
            )

        if earlyMatch ~= nil
            or not moved
            or distanceFlat(endPosition, entry.general) <= arrivalDistance then
            return moved, endPosition, earlyMatch
        end
    end

    position = getPlayerPosition()

    if entry.forceUnhidden == true then
        logf(
            "Destination %s uses explicit unhidden travel despite aggroLevel=%d; continuing normal mounted pathing.",
            getSpotDescriptor(entry),
            getEntryAggroLevel(entry)
        )
    end

    -- A destination above maxAggro must be hidden before any movement begins,
    -- unless it is explicitly marked forceUnhidden.
    if isDangerousSpot(entry) then
        if isInCombat() then
            stopPathing()
            dangerousCombatAbortTriggered = true
            logCombatDiagnostics(
                "combat-before-dangerous:" .. getSpotDescriptor(entry),
                position
            )
            logf(
                "Combat is active before dangerous destination %s (aggroLevel=%d > max=%d); Hide cannot be applied, aborting pass.",
                getSpotDescriptor(entry),
                getEntryAggroLevel(entry),
                MAX_AGGRO_LEVEL
            )
            return false, position, nil
        end

        logf(
            "Destination %s is above max aggro level (%d > %d); applying Hide before movement.",
            getSpotDescriptor(entry),
            getEntryAggroLevel(entry),
            MAX_AGGRO_LEVEL
        )

        if not ensureHiddenOrAbort(entry) then
            return false, getPlayerPosition(), nil
        end

        return moveToSpotWithApproachScanHidden(
            entry,
            arrivalDistance,
            entry
        )
    end

    -- Destinations at or below maxAggro use normal movement. Combat does not
    -- interrupt or alter the route. If already mounted, remain mounted.
    local allowMountAttempt = not isInCombat() or isMounted()

    if isInCombat() then
        logf(
            "Combat active while traveling to allowed destination %s (aggroLevel=%d <= max=%d); continuing normal pathing mounted=%s.",
            getSpotDescriptor(entry),
            getEntryAggroLevel(entry),
            MAX_AGGRO_LEVEL,
            tostring(isMounted())
        )
    end

    return moveToSpotWithApproachScan(
        entry,
        allowMountAttempt,
        arrivalDistance
    )
end

getObjectName = function(object)
    return safeCall(function() return object.Name.TextValue end)
        or safeCall(function() return object.Name:GetText() end)
        or tostring(safeCall(function() return object.Name end) or "")
end

collectVisibleCoffers = function(radius)
    local playerPosition = getPlayerPosition()
    if playerPosition == nil or not (Svc and Svc.Objects) then
        return {}
    end

    local results = {}
    local objectCount = tonumber(safeCall(function() return Svc.Objects.Length end)) or 0
    for i = 0, math.max(0, objectCount - 1) do
        local object = safeCall(function() return Svc.Objects[i] end)
        if object ~= nil then
            local position = safeCall(function() return object.Position end)
            local distance = distance3d(playerPosition, position)
            if position ~= nil and distance <= radius then
                local kindText = tostring(safeCall(function() return object.ObjectKind end) or "?")
                local name = tostring(getObjectName(object) or "")
                if string.find(kindText, "Treasure", 1, true) == 1 and name == "Treasure Coffer" then
                    local entity = safeCall(function() return Entity[i] end)
                    if entity ~= nil and safeCall(function() return entity.IsTargetable end) == true then
                        table.insert(results, {
                            entity = entity,
                            index = i,
                            name = name,
                            dataId = tonumber(safeCall(function() return object.DataId end)),
                            gameObjectId = safeCall(function() return object.GameObjectId end),
                            position = position,
                            distance = distance,
                        })
                    end
                end
            end
        end
    end

    table.sort(results, function(a, b)
        return (a.distance or math.huge) < (b.distance or math.huge)
    end)
    return results
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

local function refreshVisibleCoffer(match, radius)
    if match == nil then
        return nil
    end
    local visible = collectVisibleCoffers(radius or 15)
    for _, entry in ipairs(visible) do
        if match.gameObjectId ~= nil and entry.gameObjectId == match.gameObjectId then
            return entry
        end
    end
    return nil
end

local function createJumpAssistCallback(match, entry)
    if entry == nil or entry.note ~= "requires_jump" or match == nil or match.position == nil then
        return nil
    end

    local fired = false
    return function(currentPosition, targetPosition)
        if fired or currentPosition == nil or targetPosition == nil then
            return
        end
        local remaining = distanceFlat(currentPosition, targetPosition)
        if remaining > JUMP_ASSIST_TRIGGER_DISTANCE then
            return
        end
        fired = true
        logf("Applying moving jump assist for %s near %s at %.1fy trigger.", getSpotDescriptor(entry), formatVector3(match.position), JUMP_ASSIST_TRIGGER_DISTANCE)
        for _ = 1, JUMP_ASSIST_COUNT do
            pcall(function() Actions.ExecuteGeneralAction(GENERAL_ACTION_JUMP) end)
            sleep(JUMP_ASSIST_DELAY)
        end
    end
end

local function interactWithCoffer(match, entry, previousEntry)
    local currentMatch = match

    for attempt = 1, MAX_INTERACT_ATTEMPTS do
        if deathReturnTriggered then
            stopPathing()
            return false
        end

        if attempt > 1 then
            local reacquired = nil
            local missingBeforeRetry = 0

            for _ = 1, 3 do
                reacquired = refreshVisibleCoffer(currentMatch, 15)
                if reacquired ~= nil then
                    currentMatch = reacquired
                    break
                end
                missingBeforeRetry = missingBeforeRetry + 1
                sleep(0.4)
            end

            if reacquired == nil and missingBeforeRetry >= 3 then
                logf(
                    "Coffer gameObjectId=%s remained absent for %d consecutive scans before retry; coffer open confirmed.",
                    tostring(currentMatch and currentMatch.gameObjectId or "?"),
                    missingBeforeRetry
                )
                return true
            end

            logf(
                "Retrying coffer interaction attempt %d/%d for gameObjectId=%s.",
                attempt,
                MAX_INTERACT_ATTEMPTS,
                tostring(currentMatch.gameObjectId or "?")
            )
            sleep(INTERACT_RETRY_DELAY)
        end

        logf(
            "Looting coffer dataId=%s gameObjectId=%s dist=%.1f pos=%s (attempt %d/%d).",
            tostring(currentMatch.dataId or "?"),
            tostring(currentMatch.gameObjectId or "?"),
            tonumber(currentMatch.distance) or -1,
            formatVector3(currentMatch.position),
            attempt,
            MAX_INTERACT_ATTEMPTS
        )

        local jumpCallback = createJumpAssistCallback(currentMatch, entry)
        local currentPosition = getPlayerPosition()
        local mustStayHidden = isDangerousSpot(entry)
            or isWithinHideThreshold(previousEntry, currentPosition)
            or isWithinHideThreshold(entry, currentPosition)

        if mustStayHidden and isInCombat() then
            stopPathing()
            dangerousCombatAbortTriggered = true
            logf(
                "Combat detected before approaching a coffer inside the hide threshold for %s; aborting route instead of continuing mounted.",
                getSpotDescriptor(
                    getHideThresholdContext(
                        previousEntry,
                        entry,
                        currentPosition
                    )
                )
            )
            return false
        end

        if mustStayHidden then
            if not ensureHiddenOrAbort(
                getHideThresholdContext(previousEntry, entry, currentPosition)
            ) then
                return false
            end
        end

        local moved = nil
        if mustStayHidden then
            moved = moveToPositionHiddenWithRetry(
                currentMatch.position,
                INTERACT_DISTANCE,
                "visible coffer",
                getHideThresholdContext(
                    previousEntry,
                    entry,
                    currentPosition
                ),
                jumpCallback
            )
        else
            moved = moveToPositionWithRetry(
                currentMatch.position,
                INTERACT_DISTANCE,
                "visible coffer",
                {
                    allowMount = true,
                    onStep = jumpCallback,
                }
            )
        end

        if deathReturnTriggered then
            stopPathing()
            return false
        end

        if not moved then
            logf(
                "Could not reach coffer at %s.",
                formatVector3(currentMatch.position)
            )
            return false
        end

        if not targetEntity(currentMatch.entity) then
            logf(
                "Failed to target coffer gameObjectId=%s.",
                tostring(currentMatch.gameObjectId or "?")
            )
            return false
        end

        local freeSlotsBefore = getFreeInventorySlots()
        local inventoryBefore,
            inventoryBeforeValid,
            inventoryBeforeError = COFFER_INVENTORY.snapshot()
        local inventoryFallbackLogged = false

        if not inventoryBeforeValid then
            logf(
                "Inventory snapshot incomplete before coffer interaction attempt %d (%s); using exact-coffer disappearance confirmation.",
                attempt,
                tostring(inventoryBeforeError or "unknown_error")
            )
            inventoryFallbackLogged = true
        end

        logf(
            "Coffer interaction attempt %d inventory baseline: freeSlots=%s nonEmptySlots=%s slotsRead=%s containersRead=%s.",
            attempt,
            tostring(freeSlotsBefore or "?"),
            tostring(
                inventoryBeforeValid
                    and inventoryBefore.nonEmptySlots
                    or "?"
            ),
            tostring(
                inventoryBeforeValid
                    and inventoryBefore.slotsRead
                    or "?"
            ),
            tostring(
                inventoryBeforeValid
                    and inventoryBefore.containersRead
                    or "?"
            )
        )

        sleep(0.1)
        yield("/interact")

        local missingAfterInteract = 0
        local confirmationStartedAt = os.clock()

        -- Inventory polling phase: catches both new slots and increases to
        -- existing stacks. Exact-coffer disappearance is checked in parallel.
        for _ = 1, 8 do
            sleep(0.4)

            if deathReturnTriggered then
                stopPathing()
                return false
            end

            if inventoryBeforeValid then
                local inventoryNow,
                    inventoryNowValid,
                    inventoryNowError = COFFER_INVENTORY.snapshot()

                if inventoryNowValid then
                    local inventoryDeltas =
                        COFFER_INVENTORY.findPositiveDeltas(
                            inventoryBefore,
                            inventoryNow
                        )

                    if #inventoryDeltas > 0 then
                        logf(
                            "Coffer interaction attempt %d added inventory items: %s; coffer open confirmed.",
                            attempt,
                            COFFER_INVENTORY.formatDeltas(
                                inventoryDeltas
                            )
                        )
                        return true
                    end
                elseif not inventoryFallbackLogged then
                    logf(
                        "Inventory snapshot incomplete after coffer interaction attempt %d (%s); using exact-coffer disappearance confirmation.",
                        attempt,
                        tostring(inventoryNowError or "unknown_error")
                    )
                    inventoryFallbackLogged = true
                end
            end

            local sameCoffer = refreshVisibleCoffer(currentMatch, 15)
            if sameCoffer == nil then
                missingAfterInteract = missingAfterInteract + 1

                if missingAfterInteract >= 3 then
                    logf(
                        "Coffer gameObjectId=%s disappeared for %d consecutive scans after interaction attempt %d; coffer open confirmed.",
                        tostring(currentMatch.gameObjectId or "?"),
                        missingAfterInteract,
                        attempt
                    )
                    return true
                end
            else
                currentMatch = sameCoffer
                missingAfterInteract = 0
            end
        end

        -- Use the remainder of the configured interaction timeout for
        -- disappearance-only confirmation. Inventory has already received
        -- eight complete normal-bag scans.
        local elapsed = os.clock() - confirmationStartedAt
        local confirmationDeadline =
            os.clock() + math.max(0, INTERACT_WAIT_TIMEOUT - elapsed)

        while os.clock() < confirmationDeadline do
            sleep(0.4)

            if deathReturnTriggered then
                stopPathing()
                return false
            end

            local sameCoffer = refreshVisibleCoffer(currentMatch, 15)
            if sameCoffer == nil then
                missingAfterInteract = missingAfterInteract + 1

                if missingAfterInteract >= 3 then
                    logf(
                        "Coffer gameObjectId=%s disappeared for %d consecutive scans after interaction attempt %d; coffer open confirmed.",
                        tostring(currentMatch.gameObjectId or "?"),
                        missingAfterInteract,
                        attempt
                    )
                    return true
                end
            else
                currentMatch = sameCoffer
                missingAfterInteract = 0
            end
        end

        local freeSlotsAfter = getFreeInventorySlots()
        if freeSlotsBefore ~= nil and freeSlotsAfter ~= nil then
            logf(
                "Coffer interaction attempt %d inventory telemetry: free slots %d -> %d; no positive normal-bag item-count delta detected.",
                attempt,
                freeSlotsBefore,
                freeSlotsAfter
            )
        else
            logf(
                "Coffer interaction attempt %d inventory telemetry unavailable; no positive normal-bag item-count delta detected.",
                attempt
            )
        end

        logf(
            "Coffer gameObjectId=%s remains present and no positive inventory delta was detected after interaction attempt %d.",
            tostring(currentMatch.gameObjectId or "?"),
            attempt
        )
    end

    return false
end

local function getEligibleSpots(maxAggroLevel)
    local eligible = {}
    for _, entry in ipairs(COFFER_SPOTS) do
        local aggroLevel = getEntryAggroLevel(entry)

        if entry.routeExcluded == true then
            logf(
                "Excluding %s from route: %s.",
                getSpotDescriptor(entry),
                tostring(entry.note or "route excluded")
            )
        elseif USE_NINJA_FOR_DANGEROUS_AREA then
            table.insert(eligible, entry)
        elseif aggroLevel <= maxAggroLevel then
            table.insert(eligible, entry)
        else
            logf(
                "Skipping %s aggroLevel=%s above max=%d.",
                getSpotDescriptor(entry),
                tostring(aggroLevel),
                maxAggroLevel
            )
        end
    end
    return eligible
end

local function buildStaticRoute(eligible, maxAggroLevel)
    local byLabel = {}
    for _, entry in ipairs(eligible) do
        byLabel[entry.label] = entry
    end

    local ordered = {}
    for _, routeEntry in ipairs(STATIC_ROUTE_ORDER) do
        if type(routeEntry) == "table" then
            local aggroLevel = getEntryAggroLevel(routeEntry)
            if USE_NINJA_FOR_DANGEROUS_AREA or aggroLevel <= maxAggroLevel then
                table.insert(ordered, routeEntry)
            else
                logf(
                    "Skipping route waypoint %s aggroLevel=%d above max=%d.",
                    getSpotDescriptor(routeEntry),
                    aggroLevel,
                    maxAggroLevel
                )
            end
        else
            local entry = byLabel[routeEntry]
            if entry ~= nil then
                table.insert(ordered, entry)
                byLabel[routeEntry] = nil
            end
        end
    end

    for _, entry in pairs(byLabel) do
        table.insert(ordered, entry)
    end
    return ordered
end

local function logRoute(route, maxAggroLevel)
    local cofferCount = 0
    for _, entry in ipairs(route) do
        if not entry.routeOnly then
            cofferCount = cofferCount + 1
        end
    end

    logf("Configured max aggro level=%d route points=%d mapped coffers=%d.", maxAggroLevel, #route, cofferCount)
    local preview = {}
    local limit = math.min(#route, 12)
    for i = 1, limit do
        preview[#preview + 1] = string.format("%s(%d)", getSpotDescriptor(route[i]), getEntryAggroLevel(route[i]))
    end
    if #preview > 0 then
        logf("Route preview: %s%s.", table.concat(preview, " -> "), #route > limit and " -> ..." or "")
    end
end

local function scanAndLootAtSpot(previousEntry, entry)
    local arrivalDistance = getArrivalDistance(entry)
    logf(
        "Traveling to %s at %s (aggroLevel=%d, arrivalDistance=%.1f).",
        getSpotDescriptor(entry),
        formatVector3(entry.general),
        getEntryAggroLevel(entry),
        arrivalDistance
    )

    local moved, endPosition, earlyMatch = moveToSpotRespectingHideThreshold(previousEntry, entry)

    if deathReturnTriggered then
        stopPathing()
        logf(
            "Death return completed while traveling to %s; ending route at base without retrying.",
            getSpotDescriptor(entry)
        )
        return false
    end

    local remaining = distanceFlat(endPosition, entry.general)

    if entry.routeOnly and moved and earlyMatch == nil and remaining > arrivalDistance then
        logf(
            "Movement reported success for route waypoint %s, but remaining %.1fy exceeds required %.1fy.",
            getSpotDescriptor(entry),
            remaining,
            arrivalDistance
        )
        moved = false
    end

    if not moved and earlyMatch == nil then
        logf(
            "Move to %s did not complete; remaining %.1fy exceeds required %.1fy. Retrying once.",
            getSpotDescriptor(entry),
            remaining,
            arrivalDistance
        )
        sleep(0.5)

        if deathReturnTriggered then
            stopPathing()
            return false
        end

        moved, endPosition, earlyMatch = moveToSpotRespectingHideThreshold(previousEntry, entry)

        if deathReturnTriggered then
            stopPathing()
            logf(
                "Death return completed during retry toward %s; ending route at base.",
                getSpotDescriptor(entry)
            )
            return false
        end

        remaining = distanceFlat(endPosition, entry.general)

        if entry.routeOnly and moved and earlyMatch == nil and remaining > arrivalDistance then
            logf(
                "Retry reported success for route waypoint %s, but remaining %.1fy exceeds required %.1fy.",
                getSpotDescriptor(entry),
                remaining,
                arrivalDistance
            )
            moved = false
        end
    end

    logf(
        "Arrived=%s current=%s remaining=%.1fy required=%.1fy.",
        tostring(moved),
        formatVector3(endPosition),
        remaining,
        arrivalDistance
    )

    if not moved and earlyMatch == nil then
        logf(
            "Skipping %s after failed movement attempt; remaining %.1fy exceeds required %.1fy.",
            getSpotDescriptor(entry),
            remaining,
            arrivalDistance
        )
        return true, true
    end

    if entry.routeOnly then
        logf(
            "Reached route waypoint %s within %.1fy.",
            getSpotDescriptor(entry),
            arrivalDistance
        )

        if entry.mountOnArrival == true then
            if not SPECIAL_SPAWN_RULES.recheckAscent7BeforeUnhide(entry) then
                return true, true
            end

            logf(
                "Waypoint %s requires unhidden mounted travel next; mounting now to remove Hide.",
                getSpotDescriptor(entry)
            )
            if not ensureMounted() then
                error(string.format(
                    "Failed to mount at required unhide waypoint %s",
                    getSpotDescriptor(entry)
                ))
            end
            logf(
                "Unhide waypoint complete for %s hidden=%s mounted=%s combat=%s.",
                getSpotDescriptor(entry),
                tostring(isHidden()),
                tostring(isMounted()),
                tostring(isInCombat())
            )
        end

        if entry.hideOnArrival == true then
            logf(
                "Waypoint %s is the safe re-hide point; applying Hide before continuing.",
                getSpotDescriptor(entry)
            )

            if isInCombat() then
                stopPathing()
                dangerousCombatAbortTriggered = true
                logCombatDiagnostics(
                    "combat-at-rehide-point:" .. getSpotDescriptor(entry),
                    getPlayerPosition()
                )
                logf(
                    "Combat is still active at safe re-hide point %s; aborting instead of entering the sight-aggro section unhidden.",
                    getSpotDescriptor(entry)
                )
                return
            end

            if not ensureHiddenOrAbort(entry) then
                return
            end

            logf(
                "Re-hide waypoint complete for %s hidden=%s mounted=%s combat=%s.",
                getSpotDescriptor(entry),
                tostring(isHidden()),
                tostring(isMounted()),
                tostring(isInCombat())
            )
        end

        return true, false
    end

    local visible = nil
    if earlyMatch ~= nil then
        visible = { earlyMatch }
    else
        visible = collectVisibleCoffers(SCAN_RADIUS)
    end
    if #visible == 0 then
        logf("No visible Treasure Coffer found near %s within %.1fy.", getSpotDescriptor(entry), SCAN_RADIUS)
        return true, false
    end

    local match = visible[1]
    if match == nil then
        return true, false
    end
    return interactWithCoffer(match, entry, previousEntry), false
end

local function validateRuntime()
    if getTerritoryType() ~= SOUTH_HORN_TERRITORY_ID then
        error(string.format("Not in South Horn (territory=%s).", tostring(getTerritoryType() or "?")))
    end
    if not (IPC and IPC.vnavmesh and IPC.vnavmesh.PathfindAndMoveTo) then
        error("vnavmesh IPC is unavailable.")
    end
end

local function ensureBaseStart()
    if isNearBaseCamp(BASE_START_DISTANCE) then
        logf("Player is within %.1fy of base camp; starting route from Southdown Heath.", BASE_START_DISTANCE)
        return true
    end

    logf("Player is %.1fy from base camp; using Return before starting static route.", distanceFlat(getPlayerPosition(), BASE_CAMP_POSITION))
    if not returnToBase() then
        error("Failed to start Return while outside base camp start radius.")
    end

    local returned = waitUntil(function()
        return getTerritoryType() == SOUTH_HORN_TERRITORY_ID and isNearBaseCamp(BASE_START_DISTANCE)
    end, 30.0, 0.5)
    if not returned then
        error(string.format("Did not reach base camp within %.1fy after Return.", BASE_START_DISTANCE))
    end

    logf("Reached base camp start radius %.1fy; starting route from Southdown Heath.", BASE_START_DISTANCE)
    return true
end

local function runPass()
    SPECIAL_SPAWN_RULES.reset()

    local eligible = getEligibleSpots(MAX_AGGRO_LEVEL)
    if #eligible == 0 then
        logf("No mapped coffers are eligible at max aggro level=%d.", MAX_AGGRO_LEVEL)
        return false
    end
    local route = buildStaticRoute(eligible, MAX_AGGRO_LEVEL)
    logRoute(route, MAX_AGGRO_LEVEL)

    local previousEntry = nil
    for _, routeEntry in ipairs(route) do
        local entry, policySkipped = SPECIAL_SPAWN_RULES.evaluate(routeEntry)

        if not policySkipped then
            ROUTE_CONTEXT.previousEntry = previousEntry
            ROUTE_CONTEXT.currentEntry = entry

            if getTerritoryType() ~= SOUTH_HORN_TERRITORY_ID then
                error("Left South Horn during route.")
            end
            if isDead() then
                handleDeathReturn()
                return false
            end
            if isInCombat() then
                if isDangerousSpot(entry) then
                    stopPathing()
                    dangerousCombatAbortTriggered = true
                    logCombatDiagnostics(
                        "route-combat-before-dangerous:" .. getSpotDescriptor(entry),
                        getPlayerPosition()
                    )
                    logf(
                        "Player is in combat before dangerous destination %s (aggroLevel=%d > max=%d); aborting because Hide must be active before movement.",
                        getSpotDescriptor(entry),
                        getEntryAggroLevel(entry),
                        MAX_AGGRO_LEVEL
                    )
                    return false
                end

                logf(
                    "Player is in combat before allowed destination %s (aggroLevel=%d <= max=%d); continuing normal route pathing.",
                    getSpotDescriptor(entry),
                    getEntryAggroLevel(entry),
                    MAX_AGGRO_LEVEL
                )
            end

            local spotCompleted, spotSkipped =
                scanAndLootAtSpot(previousEntry, entry)

            if deathReturnTriggered
                or dangerousCombatAbortTriggered
                or spotCompleted == false then

                return false
            end

            if not spotSkipped then
                previousEntry = entry
            end
        end
    end
    ROUTE_CONTEXT.previousEntry = previousEntry
    ROUTE_CONTEXT.currentEntry = nil
    return true
end

local function main()
    logf(
        "Starting farmer maxAggro=%d hideThreshold=%.1f scanRadius=%.1f arrivalDistance=%.1f interactDistance=%.1f skipHighCavernsDuringAshkin=%s AshkinWindow=22:30-04:00 rainWeatherIds=7,62,64.",
        MAX_AGGRO_LEVEL,
        HIDE_THRESHOLD_DISTANCE,
        SCAN_RADIUS,
        ARRIVAL_DISTANCE,
        INTERACT_DISTANCE,
        tostring(SKIP_HIGH_CAVERNS_DURING_ASHKIN)
    )
    validateRuntime()
    if USE_NINJA_FOR_DANGEROUS_AREA then
        ensureNinjaGearset()
    end
    ensureBaseStart()
    local passCompleted = runPass()
    if deathReturnTriggered then
        stopPathing()
        logf(
            "Treasure coffer farmer stopped at base after death return; no route retry was attempted."
        )
        return false
    end
    if dangerousCombatAbortTriggered then
        logf("Treasure coffer farmer stopped after combat inside a hide-threshold area; no mounted continuation or Return was attempted.")
        return false
    end
    if not passCompleted then
        logf("Treasure coffer farmer pass stopped before completion.")
        return false
    end
    returnToBase()
    logf("Treasure coffer farmer pass complete.")
end

main()
