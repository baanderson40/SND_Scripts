--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.5.18
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
        max: 30
    Do Non-Pot FATEs While Waiting:
        description: Participate in other FATEs while waiting between predicted pot spawns, then stop at Spawn Lead Minutes and head to the pot FATE.
        is_choice: true
        choices:
          - Disabled
          - Enabled
        default: Disabled
    Manage Instance Time:
        description: Leave South Horn when the remaining instance time cannot safely fit another complete pot cycle.
        is_choice: true
        choices:
          - Disabled
          - Enabled
        default: Enabled
    FATE Completion Budget Minutes:
        default: 5
        description: Reserved time after a pot FATE spawns to complete the FATE.
        min: 1
        max: 15
    Treasure Hunt Budget Minutes:
        default: 5
        description: Reserved time after the pot FATE completes to reveal, locate, and open the coffer.
        min: 1
        max: 20
    Instance Exit Buffer Minutes:
        default: 2
        description: Extra time reserved to stop automation and leave the instance after the final completed cycle.
        min: 1
        max: 10
    Spawn Arrival Radius:
        default: 18
        description: Radius used to pick a random wait point around the pot FATE location before spawn.
        min: 10
        max: 35
    Maximum Aggro Level:
        default: 19
        description: Normal travel threshold. Candidates above this value are skipped unless Ninja mode is enabled.
        min: 0
        max: 28
    Use Ninja For Dangerous Area:
        description: >-
          Equip Ninja for dangerous coffer candidates.
          When disabled, candidates above Maximum Aggro Level are skipped.
          When enabled, candidates above Maximum Aggro Level use threshold-based Hide travel.
        is_choice: true
        choices:
          - Disabled
          - Enabled
        default: Disabled
    Hide Threshold Distance:
        default: 120
        description: Distance from a dangerous candidate to dismount, apply Hide, and walk the rest of the approach.
        min: 10
        max: 300
    Ninja Gearset Number:
        default: 0
        description: >-
          Gearset number for Ninja when Ninja mode is enabled.
          Required if Use Ninja For Dangerous Area is enabled and above-threshold candidates are allowed.
        min: 0
        max: 100
    FATE Gearset Number:
        default: 0
        description: >-
          Gearset number to re-equip after returning to base if Ninja gearset was used during treasure routing.
          Set to 0 to leave the current gearset unchanged.
        min: 0
        max: 100
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
local AUTOROTATION_PRESET_NAME = tostring(Config.Get("Autorotation Preset Name") or "Occult")

local POLL_INTERVAL = 0.25
local SPAWN_LEAD_MINUTES = math.max(1, math.min(30, tonumber(Config.Get("Spawn Lead Minutes")) or 5))
local SPAWN_ARRIVAL_RADIUS = math.max(10, math.min(35, tonumber(Config.Get("Spawn Arrival Radius")) or 18))
local STARTING_FATE_CONFIG = tostring(Config.Get("Starting FATE") or "Auto")
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
local TREASURE_ELIXIR_RETRY_DELAY = 1.0
local POT_CYCLE_SECONDS = 30 * 60
local ENABLE_KEEP_ALIVE = false
local KEEP_ALIVE_INTERVAL = 8 * 60
local KEEP_ALIVE_MIN_RADIUS = 15.0
local KEEP_ALIVE_MAX_RADIUS = 20.0
local TREASURE_STALL_MIN_MOVE = 5.0
local TREASURE_MAX_CONSECUTIVE_STALLS = 2
local TREASURE_MOVE_START_TIMEOUT = 5.0
local TREASURE_PROGRESS_CHECK_INTERVAL = 5.0
local TREASURE_PROGRESS_MIN_MOVE = 2.0
local TREASURE_CANDIDATE_STOP_DISTANCE = 10.0
local TREASURE_LOCAL_MAX_STEPS = 12
local TREASURE_LOCAL_MOVE_SKIP_DISTANCE = 3.0
local TREASURE_REVEAL_ACQUIRE_TIMEOUT = 15.0
local TREASURE_REVEAL_SCAN_INTERVAL = 0.25
local TREASURE_REVEAL_SCAN_RADIUS = 12.0
local TREASURE_SEARCH_RADII = { 2.0, 4.0, 6.0, 10.0, 20.0 }
local TREASURE_NAVMESH_HALF_EXTENT_XZ = 6.0
local TREASURE_NAVMESH_HALF_EXTENT_Y = 8.0

local TREASURE_CANDIDATE_TRAVEL = {
    nearEnoughRadius = 35.0,
    maxAttempts = 3,
    hardTimeout = 180.0,
    progressTimeout = 5.0,
    progressMinMove = 2.0,
}

local NINJA_MODE = {
    enabled = tostring(Config.Get("Use Ninja For Dangerous Area") or "Disabled") == "Enabled",
    maxAggroLevel = math.max(0, math.min(28, tonumber(Config.Get("Maximum Aggro Level")) or 19)),
    fateGearsetNumber = math.max(0, math.min(100, tonumber(Config.Get("FATE Gearset Number")) or 0)),
    hideActionId = 2245,
    hiddenStatusId = 614,
    hideThresholdDistance = math.max(10, math.min(300, tonumber(Config.Get("Hide Threshold Distance")) or 120)),
    gearsetNumber = math.max(0, math.min(100, tonumber(Config.Get("Ninja Gearset Number")) or 0)),
    gearsetEquipped = false,
    usedThisCycle = false,
    activeCandidateLabel = nil,
    activeCandidateDangerous = false,
    hideFailed = false,
    hideRetryUsed = false,
    abortReason = nil,
    gearsetEquipMaxAttempts = 2,
    gearsetEquipVerifyTimeout = 5.0,
    gearsetEquipRetryDelay = 1.0,
    gearsetReadyTimeout = 5.0,
    postElixirGearsetDelay = 2.0,
    hideFallbackRecastSeconds = 20.0,
    hideCooldownPollInterval = 0.25,
    hideReadyMaximumWaitSeconds = 25.0,
    hideStatusAcquireTimeout = 3.0,
    lastHideActivatedAt = nil,
}

NON_POT_FATE_MODE = {
    enabled = tostring(Config.Get("Do Non-Pot FATEs While Waiting") or "Disabled") == "Enabled",
    interspawnMinimumStartWindowSeconds = 5 * 60,
    stateEnded = 6,
    stateFailed = 7,
    lastScanLogAt = 0,
    lastWaitResultLogAt = 0,
    holdingForDeparture = false,
    aethernetPreference = {
        [1967] = "CrystallizedCaverns",
    },
}

INSTANCE_TIME_MODE = {
    enabled = tostring(Config.Get("Manage Instance Time") or "Enabled") == "Enabled",
    fateBudgetSeconds = math.max(1, math.min(15, tonumber(Config.Get("FATE Completion Budget Minutes")) or 5)) * 60,
    treasureBudgetSeconds = math.max(1, math.min(20, tonumber(Config.Get("Treasure Hunt Budget Minutes")) or 5)) * 60,
    exitBufferSeconds = math.max(1, math.min(10, tonumber(Config.Get("Instance Exit Buffer Minutes")) or 2)) * 60,
    spawnGraceSeconds = 60,
    decisionLogInterval = 5 * 60,
    lastDecisionLogAt = 0,
    leavePending = false,
    exitRequested = false,
}

RETURN_MODE = {
    maxAttempts = 2,
    postCofferCooldownSeconds = 2.0,
    retryDelaySeconds = 2.0,
    readinessTimeoutSeconds = 5.0,
    castStartTimeoutSeconds = 3.0,
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
            interactDistanceMax = 4.25,
        },
        Stonemarsh = {
            name = "Stonemarsh",
            placeNameId = 4942,
            position = Vector3(-384.11542, 99.19885, 281.42212),
            destination = Vector3(-384.38, 97.44333, 276.6886),
            interactDistanceMin = 3.15,
            interactDistanceMax = 4.25,
        },
        CrystallizedCaverns = {
            name = "CrystallizedCaverns",
            placeNameId = 4929,
            position = Vector3(-358.14453, 101.97595, -120.95831),
            destination = Vector3(-353.8978, 99.99078, -120.3132),
            interactDistanceMin = 3.15,
            interactDistanceMax = 4.25,
        },
        TheWanderersHaven = {
            name = "TheWanderersHaven",
            placeNameId = 4928,
            position = Vector3(-173.02203, 8.194031, -611.1391),
            destination = Vector3(-169.27321, 6.5, -609.5403),
            interactDistanceMin = 3.15,
            interactDistanceMax = 4.25,
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
            { label = "N1", position = Vector3(330.866, 6.717, -654.534), aggroLevel = 6 },
        },
        northeast = {
            { label = "NE1", position = Vector3(587.704, 78.896, -545.817), aggroLevel = 2 },
            { label = "NE2", position = Vector3(571.584, 51.451, -813.164), aggroLevel = 1 },
        },
        east = {
            { label = "E1", position = Vector3(803.661, 96.000, -354.181), aggroLevel = 4 },
            { label = "E2", position = Vector3(684.422, 96.101, -165.481), aggroLevel = 4 },
            { label = "E3", position = Vector3(878.113, 108.290, -91.106), aggroLevel = 5 },
            { label = "E4", position = Vector3(885.93, 120.00, -23.25), aggroLevel = 20 },
        },
        southeast = {
            -- SE1/SE2 records were previously reversed. SE2 is the eastern,
            -- dangerous plateau location confirmed by Capture 33.
            { label = "SE1", position = Vector3(606.464, 108.074, 184.852), aggroLevel = 4 },
            { label = "SE2", position = Vector3(662.439, 120.000, 161.134), aggroLevel = 21 },
            { label = "SE3", position = Vector3(569.10, 64.40, 275.10), aggroLevel = 14 },
            { label = "SE4", position = Vector3(705.272, 68.144, 358.671), aggroLevel = 14 },
        },
        south = {
            { label = "S1", position = Vector3(331.47, 96.00, 185.22), aggroLevel = 4 },
            { label = "S2", position = Vector3(250.53, 102.50, 310.78), aggroLevel = 10 },
            { label = "S3", position = Vector3(46.03, 102.40, 373.00), aggroLevel = 10 },
            { label = "S4", position = Vector3(242.52, 58.84, 535.85), aggroLevel = 15 },
        },
        southwest = {
            { label = "SW1", position = Vector3(-54.695, 99.406, 405.026), aggroLevel = 10 },
            { label = "SW2", position = Vector3(-165.237, 95.338, 437.451), aggroLevel = 10 },
            { label = "SW3", position = Vector3(-330.78, 121.00, 195.48), aggroLevel = 11 },
            { label = "SW4", position = Vector3(-313.291, 108.110, 70.762), aggroLevel = 12 },
        },
        west = {
            { label = "W1", position = Vector3(-459.173, 93.574, 5.054), aggroLevel = 12 },
            { label = "W2", position = Vector3(-312.278, 103.199, -35.253), aggroLevel = 11 },
            { label = "W3", position = Vector3(-473.32, 101.95, -70.80), aggroLevel = 11 },
            { label = "W4", position = Vector3(-660.534, 98.000, -216.767), aggroLevel = 11 },
            { label = "W5", position = Vector3(-382.440, 109.302, -378.348), aggroLevel = 11 },
        },
        northwest = {
            { label = "NW1", position = Vector3(19.740, 26.046, -420.977), aggroLevel = 6 },
            { label = "NW2", position = Vector3(-222.16, 5.46, -504.77), aggroLevel = 6 },
            { label = "NW3", position = Vector3(-386.5904, -0.13994062, -461.0976), aggroLevel = 6 },
            { label = "NW4", position = Vector3(-534.6993, 2.999998, -651.6244), aggroLevel = 8 },
            { label = "NW5", position = Vector3(-326.17, 3.00, -855.72), aggroLevel = 8 },
            { label = "NW6", position = Vector3(-188.174, 3.000, -717.201), aggroLevel = 7 },
        },
    },
    ["Pleading Pots"] = {
        north = {
            { label = "N1", position = Vector3(-195.442, 110.153, -287.891), aggroLevel = 11 },
            { label = "N2", position = Vector3(-387.09, 98.74, -237.71), aggroLevel = 11 },
            { label = "N3", position = Vector3(-554.615, 99.018, -309.123), aggroLevel = 11 },
            { label = "N4", position = Vector3(-676.620, 128.574, 1.532), aggroLevel = 13 },
            -- Capture 32 was produced before position-based capture attribution.
            -- Its coffer coordinate is nearest N5 and must not overwrite confirmed N4.
            { label = "N5", position = Vector3(-645.303, 135.692, -73.548), aggroLevel = 13 },
            { label = "N6", position = Vector3(-730.544, 107.694, -371.478), aggroLevel = 25, hideThreshold = 450, travelTimeout = 300, note = "hostile mob aggro" },
        },
        northeast = {
            { label = "NE1", position = Vector3(74.734, 110.494, -394.129), aggroLevel = 9 },
            { label = "NE2", position = Vector3(113.73, 111.53, -219.07), aggroLevel = 9 },
            { label = "NE3", position = Vector3(-55.11, 101.03, -192.67), aggroLevel = 9 },
            { label = "NE4", position = Vector3(393.019, 104.000, -124.165), aggroLevel = 9 },
            { label = "NE5", position = Vector3(301.874, 103.784, 70.599), aggroLevel = 9 },
            { label = "NE6", position = Vector3(104.58, 105.46, 148.65), aggroLevel = 10 },
        },
        east = {
            { label = "E1", position = Vector3(8.90, 65.44, 664.74), aggroLevel = 15 },
            { label = "E2", position = Vector3(67.453, 69.478, 745.866), aggroLevel = 15 },
            { label = "E3", position = Vector3(200.124, 56.000, 624.229), aggroLevel = 15 },
            { label = "E4", position = Vector3(393.268, 57.546, 844.692), aggroLevel = 17 },
            { label = "E5", position = Vector3(440.836, 70.300, 876.410), aggroLevel = 17 },
            { label = "E6", position = Vector3(825.9521, 70.0, 772.4054), aggroLevel = 17 },
            { label = "E7", position = Vector3(781.251, 70.000, 560.070), aggroLevel = 17 },
            { label = "E8", position = Vector3(423.350, 70.300, 578.901), aggroLevel = 17 },
        },
        southeast = {
            { label = "SE1", position = Vector3(-57.69, 69.79, 823.02), aggroLevel = 14 },
        },
        south = {
            { label = "S1", position = Vector3(-598.99, 139.00, 856.82), aggroLevel = 27, hideThreshold = 350, note = "aggro" },
        },
        southwest = {
            { label = "SW1", position = Vector3(-746.132, 172.000, 828.881), aggroLevel = 27, hideThreshold = 400, note = "aggro" },
            { label = "SW2", position = Vector3(-741.50, 171.50, 689.72), aggroLevel = 28, hideThreshold = 310, note = "aggro" },
            { label = "SW3", position = Vector3(-707.70, 203.00, 702.15), aggroLevel = 28, hideThreshold = 290, note = "aggro" },
            { label = "SW4", position = Vector3(-848.56, 107.00, 751.23), aggroLevel = 26, hideThreshold = 435, note = "aggro" },
        },
        west = {
            { label = "W1", position = Vector3(-837.49, 107.00, 599.90), aggroLevel = 26, hideThreshold = 370, note = "aggro" },
        },
        northwest = {
            { label = "NW1", position = Vector3(-811.84, 114.07, -225.39), aggroLevel = 25, hideThreshold = 300, note = "aggro" },
            { label = "NW2", position = Vector3(-803.60, 84.13, 4.45), aggroLevel = 24, hideThreshold = 75, note = "aggro" },
            { label = "NW3", position = Vector3(-829.598, 62.668, 66.829), aggroLevel = 13 },
        },
    },
}

local COFFER_EOBJ_IDS = {
    2014741,
    2014742,
    2014743,
}

local COFFER_DATA_ID_LOOKUP = {
    [2014741] = true, -- Gold coffer EObj row
    [2014742] = true, -- Silver coffer EObj row
    [2014743] = true, -- Bronze coffer EObj row
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
    -- FFXIV world coordinates use -Z for north and +Z for south.
    north = { x = 0, z = -1 },
    south = { x = 0, z = 1 },
    east = { x = 1, z = 0 },
    west = { x = -1, z = 0 },
    northeast = { x = 0.70710678, z = -0.70710678 },
    northwest = { x = -0.70710678, z = -0.70710678 },
    southeast = { x = 0.70710678, z = 0.70710678 },
    southwest = { x = -0.70710678, z = 0.70710678 },
}

local SENTENCE_PATTERN = "^you sense something (.+) to the (.+)$"
local SENTENCE_DIRECTION_ONLY_PATTERN = "^you sense something to the (.+)$"

local lastIdleLogAt = 0
local lastPotScanLogAt = 0
local latestTreasureEventRevision = 0
local latestTreasureEvent = nil
local lastTreasureSummary = nil
local potCycleRuntime = {
    activeFateName = nil,
    lastSpawnFateName = nil,
    lastSpawnAt = nil,
    lastInterspawnPredictionBucket = nil,
    interspawnPredictionOverdueLogged = false,
    waitingAtPredictedSpawn = false,
    bootstrapWaitActive = false,
}
local lastKeepAliveAt = 0
local TREASURE_RUNTIME = {
    trackingActive = false,
    resolvedCofferNames = nil,
    resolvedCofferNameLookup = nil,
    currentContext = nil,
    lastLoggedCaptureKey = nil,
    elixirUseCount = 0,
    lastElixirUseAt = nil,
    lastCofferOpenedAt = nil,
    cofferRevealed = false,
    revealedCofferBypassLogged = false,
    movementDetourTimeout = 15.0,
    movementStationaryThreshold = 0.75,
    initialProbeCenterStopDistance = 5.0,
    initialProbeCenterMoveTimeout = 30.0,
    initialProbeCenterMoveAttempts = 2,
    initialProbeCenterRetryDelay = 1.0,
    initialProbeCenterMaxSnapDistance = 12.0,
    initialProbeCenterMaxVerticalSnap = 30.0,
    navmeshMinimumValidY = -400.0,
    navmeshMaximumValidY = 500.0,
    navmeshSentinelY = -500.0,
    navmeshSentinelTolerance = 0.5,
    navmeshMaxVerticalSnap = 180.0,
    navmeshCoordinateAbsLimit = 100000.0,
    lastNavmeshRejectionSummary = nil,
    candidateHandoffRadius = 25.0,
    candidateHandoffAdvantage = 10.0,
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

LOGGING = LOGGING or {}

LOGGING.verbose = function(message)
    local line = string.format("%s %s", PREFIX, tostring(message))
    pcall(function()
        Dalamud.LogVerbose(line)
    end)
end

LOGGING.verbosef = function(fmt, ...)
    LOGGING.verbose(string.format(fmt, ...))
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
        local name = getEObjNameByRowId(dataId)
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

TREASURE_RUNTIME.newMovementWatch = function(startPosition, targetPosition)
    local now = os.clock()
    return {
        lastProgressPosition = startPosition,
        lastProgressDistance = distanceFlat(startPosition, targetPosition),
        lastProgressAt = now,
        lastMovementPosition = startPosition,
        lastMovementAt = now,
        detourStartedAt = nil,
    }
end

TREASURE_RUNTIME.checkMovementWatch = function(state, currentPosition, targetPosition, progressMin, stallSeconds, detourSeconds, stationaryThreshold)
    local now = os.clock()
    local currentDistance = distanceFlat(currentPosition, targetPosition)
    local progress = state.lastProgressDistance - currentDistance
    local movementSinceSample = distanceFlat(state.lastMovementPosition, currentPosition)

    if movementSinceSample >= (stationaryThreshold or TREASURE_RUNTIME.movementStationaryThreshold) then
        state.lastMovementPosition = currentPosition
        state.lastMovementAt = now
    end

    if progress >= (progressMin or 1.0) then
        local previousDistance = state.lastProgressDistance
        state.lastProgressPosition = currentPosition
        state.lastProgressDistance = currentDistance
        state.lastProgressAt = now
        state.detourStartedAt = nil
        return "progress", {
            currentDistance = currentDistance,
            previousDistance = previousDistance,
            playerTravel = movementSinceSample,
            elapsed = 0,
        }
    end

    local noProgressFor = now - state.lastProgressAt
    if noProgressFor < (stallSeconds or 5.0) then
        return "waiting", {
            currentDistance = currentDistance,
            previousDistance = state.lastProgressDistance,
            playerTravel = distanceFlat(state.lastProgressPosition, currentPosition),
            elapsed = noProgressFor,
        }
    end

    local stationaryFor = now - state.lastMovementAt
    local detail = {
        currentDistance = currentDistance,
        previousDistance = state.lastProgressDistance,
        playerTravel = distanceFlat(state.lastProgressPosition, currentPosition),
        elapsed = noProgressFor,
        stationaryFor = stationaryFor,
    }

    if stationaryFor >= (stallSeconds or 5.0) then
        return "stalled", detail
    end

    state.detourStartedAt = state.detourStartedAt or state.lastProgressAt
    detail.detourFor = now - state.detourStartedAt
    if detail.detourFor >= (detourSeconds or TREASURE_RUNTIME.movementDetourTimeout) then
        return "detour_timeout", detail
    end

    return "detouring", detail
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

function isVnavPathfindInProgress()
    local pathing = safeCall(function()
        return IPC.vnavmesh.PathfindInProgress()
    end)
    return pathing == true
end

function isVnavActive()
    return isVnavPathfindInProgress() or isVnavRunning()
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
local ensureDismounted

NINJA_MODE.hasStatusId = function(statusId)
    local statusList = safeCall(function()
        return Player.Status
    end)
    local count = tonumber(safeCall(function()
        return statusList.Count
    end)) or 0
    for i = 0, math.max(0, count - 1) do
        local status = safeCall(function()
            return statusList[i]
        end)
        if status ~= nil and tonumber(status.StatusId) == tonumber(statusId) then
            return true
        end
    end
    return false
end

NINJA_MODE.isHidden = function()
    return NINJA_MODE.hasStatusId(NINJA_MODE.hiddenStatusId)
end

NINJA_MODE.isDangerousCandidate = function(candidate)
    return candidate ~= nil and (tonumber(candidate.aggroLevel) or 0) > NINJA_MODE.maxAggroLevel
end

NINJA_MODE.getHideReferencePosition = function(candidate)
    if candidate == nil then
        return nil
    end
    return candidate.position
end

NINJA_MODE.getHideThreshold = function(candidate)
    return math.max(10, tonumber(candidate and candidate.hideThreshold) or NINJA_MODE.hideThresholdDistance)
end

NINJA_MODE.isWithinHideThreshold = function(candidate, position)
    local reference = NINJA_MODE.getHideReferencePosition(candidate)
    return reference ~= nil and NINJA_MODE.isDangerousCandidate(candidate) and distanceFlat(position, reference) <= NINJA_MODE.getHideThreshold(candidate)
end

NINJA_MODE.getHideThresholdContext = function(previousCandidate, currentCandidate, position)
    if NINJA_MODE.isWithinHideThreshold(currentCandidate, position) then
        return currentCandidate
    end
    if NINJA_MODE.isWithinHideThreshold(previousCandidate, position) then
        return previousCandidate
    end
    return currentCandidate or previousCandidate
end

NINJA_MODE.getThresholdApproachPoint = function(candidate, fromPosition, extraDistance)
    local reference = NINJA_MODE.getHideReferencePosition(candidate)
    if candidate == nil or reference == nil or fromPosition == nil then
        return nil
    end
    local nx, nz = normalizeFlat(reference, fromPosition)
    if nx == nil then
        return nil
    end
    local radius = NINJA_MODE.getHideThreshold(candidate) + math.max(0, tonumber(extraDistance) or 0)
    return Vector3(
        reference.X + (nx * radius),
        reference.Y,
        reference.Z + (nz * radius)
    )
end

NINJA_MODE.equipGearsetNumber = function(gearsetNumber, contextLabel)
    if gearsetNumber == nil or gearsetNumber <= 0 then
        return false, string.format("configured %s gearset number is invalid", tostring(contextLabel or "gearset"))
    end
    if not (Player and Player.GetGearset) then
        return false, "Player.GetGearset unavailable"
    end

    local slot = gearsetNumber - 1
    local slotDisplay = slot + 1
    local label = tostring(contextLabel or "gearset")
    local maxAttempts = math.max(2, tonumber(NINJA_MODE.gearsetEquipMaxAttempts) or 2)
    local lastError = nil

    for attempt = 1, maxAttempts do
        local lastElixirUseAt = tonumber(TREASURE_RUNTIME.lastElixirUseAt)
        if lastElixirUseAt ~= nil then
            local postElixirRemaining = (tonumber(NINJA_MODE.postElixirGearsetDelay) or 2.0) - (os.clock() - lastElixirUseAt)
            if postElixirRemaining > 0 then
                logf(
                    "%s gearset equip attempt %d/%d waiting %.1fs for the post-elixir action lock window.",
                    label,
                    attempt,
                    maxAttempts,
                    postElixirRemaining
                )
                sleep(postElixirRemaining)
            end
        end

        if isMounted() or isMounting() then
            if not ensureDismounted(5.0) then
                lastError = string.format("failed to dismount before %s gearset attempt %d/%d", label, attempt, maxAttempts)
            end
        end

        if lastError == nil or not (isMounted() or isMounting()) then
            local ready = waitUntil(function()
                return isPlayerAvailable()
                    and not isInCombat()
                    and not getCondition(CharacterCondition.casting)
                    and not isMounted()
                    and not isMounting()
            end, tonumber(NINJA_MODE.gearsetReadyTimeout) or 5.0, 0.25)

            if not ready then
                lastError = string.format(
                    "%s gearset attempt %d/%d timed out waiting for a changeable state; current job=%s combat=%s casting=%s mounted=%s",
                    label,
                    attempt,
                    maxAttempts,
                    tostring(NINJA_MODE.getBestEffortJobLabel()),
                    tostring(isInCombat()),
                    tostring(getCondition(CharacterCondition.casting)),
                    tostring(isMounted() or isMounting())
                )
            else
                local gearset = Player.GetGearset(slot)
                if not gearset or gearset.IsValid ~= true then
                    lastError = string.format("%s gearset number %d invalid or unavailable on attempt %d/%d", label, slotDisplay, attempt, maxAttempts)
                else
                    local targetJobId = tonumber(safeCall(function() return gearset.ClassJob end))
                    if targetJobId == nil or targetJobId <= 0 then
                        lastError = string.format("%s gearset number %d has no readable ClassJob id on attempt %d/%d", label, slotDisplay, attempt, maxAttempts)
                    elseif tonumber(safeCall(function() return Player.Job.Id end)) == targetJobId then
                        logf("%s gearset number %d is already active before attempt %d/%d (%s).", label, slotDisplay, attempt, maxAttempts, tostring(NINJA_MODE.getBestEffortJobLabel()))
                        return true, nil
                    else
                        logf("%s gearset equip attempt %d/%d for gearset number %d.", label, attempt, maxAttempts, slotDisplay)
                        local ok, err = pcall(function()
                            gearset:Equip()
                        end)
                        if not ok then
                            lastError = string.format("%s gearset attempt %d/%d raised an error: %s", label, attempt, maxAttempts, tostring(err))
                        else
                            local changed = waitUntil(function()
                                return tonumber(safeCall(function() return Player.Job.Id end)) == targetJobId
                            end, tonumber(NINJA_MODE.gearsetEquipVerifyTimeout) or 5.0, 0.25)
                            if changed then
                                logf("%s gearset equip complete on attempt %d/%d: %s.", label, attempt, maxAttempts, tostring(NINJA_MODE.getBestEffortJobLabel()))
                                return true, nil
                            end
                            lastError = string.format(
                                "%s gearset attempt %d/%d did not activate ClassJob %d; current job=%s",
                                label,
                                attempt,
                                maxAttempts,
                                targetJobId,
                                tostring(NINJA_MODE.getBestEffortJobLabel())
                            )
                        end
                    end
                end
            end
        end

        log(tostring(lastError))
        if attempt < maxAttempts then
            local retryDelay = tonumber(NINJA_MODE.gearsetEquipRetryDelay) or 1.0
            logf("Waiting %.1f second(s) before retrying %s gearset.", retryDelay, label)
            sleep(retryDelay)
            lastError = nil
        end
    end

    return false, tostring(lastError or string.format("%s gearset equip failed", label))
end

NINJA_MODE.ensureGearset = function()
    if not NINJA_MODE.enabled then
        return true, nil
    end
    if NINJA_MODE.gearsetEquipped then
        local activeGearset = Player and Player.GetGearset and Player.GetGearset(NINJA_MODE.gearsetNumber - 1) or nil
        local expectedJobId = activeGearset and activeGearset.IsValid == true and tonumber(safeCall(function() return activeGearset.ClassJob end)) or nil
        local currentJobId = tonumber(safeCall(function() return Player.Job.Id end))
        if expectedJobId ~= nil and currentJobId == expectedJobId then
            NINJA_MODE.usedThisCycle = true
            return true, nil
        end
        logf("Stored Ninja gearset state was stale (current job=%s); revalidating gearset number %d.", tostring(NINJA_MODE.getBestEffortJobLabel()), NINJA_MODE.gearsetNumber)
        NINJA_MODE.gearsetEquipped = false
    end
    logf("Ninja dangerous-area mode enabled; equipping gearset number %d.", NINJA_MODE.gearsetNumber)
    local ok, err = NINJA_MODE.equipGearsetNumber(NINJA_MODE.gearsetNumber, "Ninja")
    if not ok then
        NINJA_MODE.gearsetEquipped = false
        return false, string.format("Failed to equip Ninja gearset after %d attempts: %s", tonumber(NINJA_MODE.gearsetEquipMaxAttempts) or 2, tostring(err))
    end
    NINJA_MODE.gearsetEquipped = true
    NINJA_MODE.usedThisCycle = true
    return true, nil
end

NINJA_MODE.restoreFateGearsetIfNeeded = function()
    if not NINJA_MODE.usedThisCycle then
        return true
    end
    if NINJA_MODE.fateGearsetNumber <= 0 then
        log("No FATE gearset configured; leaving current gearset unchanged after Ninja treasure routing.")
        return true
    end

    logf("Re-equipping FATE gearset number %d after Ninja treasure routing.", NINJA_MODE.fateGearsetNumber)
    local ok, err = NINJA_MODE.equipGearsetNumber(NINJA_MODE.fateGearsetNumber, "FATE")
    if not ok then
        logf("Failed to re-equip FATE gearset: %s.", tostring(err))
        return false
    end

    NINJA_MODE.usedThisCycle = false
    NINJA_MODE.gearsetEquipped = false
    return true
end

NINJA_MODE.getBestEffortJobLabel = function()
    local abbreviation = safeCall(function() return Player.Job.Abbreviation end)
    local jobId = tonumber(safeCall(function() return Player.Job.Id end))
    if abbreviation ~= nil or jobId ~= nil then
        return string.format("%s(%s)", tostring(abbreviation or "?"), tostring(jobId or "?"))
    end
    return "unknown"
end

NINJA_MODE.getHideCooldownRemaining = function()
    local recastTime = nil
    local elapsed = nil
    if Actions and Actions.GetActionInfo then
        local actionInfo = safeCall(function()
            return Actions.GetActionInfo(NINJA_MODE.hideActionId)
        end)
        if actionInfo ~= nil then
            recastTime = tonumber(safeCall(function() return actionInfo.RealRecastTime end))
            elapsed = tonumber(safeCall(function() return actionInfo.RealRecastTimeElapsed end))
        end
    end

    local function validNumber(value)
        return value ~= nil and value == value and math.abs(value) ~= math.huge and value >= 0 and value < 3600
    end

    if validNumber(recastTime) and validNumber(elapsed) then
        if elapsed <= 0 then
            return 0, recastTime, elapsed, "ipc_ready"
        end
        return math.max(0, recastTime - elapsed), recastTime, elapsed, "ipc_cooldown"
    end

    if NINJA_MODE.lastHideActivatedAt ~= nil then
        local fallbackRecast = tonumber(NINJA_MODE.hideFallbackRecastSeconds) or 20.0
        local fallbackElapsed = math.max(0, os.clock() - NINJA_MODE.lastHideActivatedAt)
        if fallbackElapsed < fallbackRecast then
            return fallbackRecast - fallbackElapsed, fallbackRecast, fallbackElapsed, "timestamp_fallback"
        end
    end

    return 0, tonumber(NINJA_MODE.hideFallbackRecastSeconds) or 20.0, 0, "unavailable_assume_ready"
end

NINJA_MODE.waitForHideReady = function(candidate)
    if NINJA_MODE.isHidden() then
        return true, "already_hidden"
    end

    local label = tostring(candidate and candidate.label or "?")
    local deadline = os.clock() + (tonumber(NINJA_MODE.hideReadyMaximumWaitSeconds) or 25.0)
    local loggedCooldown = false

    while os.clock() < deadline do
        if TREASURE_RUNTIME.cofferRevealed then
            return false, "coffer_revealed"
        end
        if NINJA_MODE.isHidden() then
            return true, "hidden_while_waiting"
        end

        local remaining, recastTime, elapsed, source = NINJA_MODE.getHideCooldownRemaining()
        if elapsed <= 0 then
            return true, "ready"
        end

        if not loggedCooldown then
            logf("Hide is on cooldown for candidate %s; waiting %.1fs before reapplying.", label, remaining)
            loggedCooldown = true
        else
            LOGGING.verbosef(
                "Hide cooldown for candidate %s: remaining=%.2fs recast=%.2fs elapsed=%.2fs source=%s.",
                label,
                remaining,
                recastTime,
                elapsed,
                tostring(source)
            )
        end
        sleep(tonumber(NINJA_MODE.hideCooldownPollInterval) or 0.25)
    end

    return false, "hide_ready_timeout"
end

NINJA_MODE.tryHideOnce = function(candidate)
    if NINJA_MODE.isHidden() then
        return true, "already_hidden"
    end

    local ready, readyReason = NINJA_MODE.waitForHideReady(candidate)
    if not ready then
        if readyReason ~= "coffer_revealed" then
            logf("Hide did not become ready for candidate %s within %.1fs.", tostring(candidate and candidate.label or "?"), tonumber(NINJA_MODE.hideReadyMaximumWaitSeconds) or 25.0)
        end
        return false, readyReason
    end

    if TREASURE_RUNTIME.cofferRevealed then
        return false, "coffer_revealed"
    end
    if not ensureDismounted(5.0) then
        logf("Hide attempt aborted: failed to dismount (mounted=%s).", tostring(isMounted()))
        return false, "dismount_failed"
    end
    if not (Actions and Actions.ExecuteAction) then
        logf("Hide attempt aborted: Actions.ExecuteAction unavailable.")
        return false, "actions_unavailable"
    end

    logf("Attempting Hide action %d (job=%s, mounted=%s).", NINJA_MODE.hideActionId, tostring(NINJA_MODE.getBestEffortJobLabel()), tostring(isMounted()))
    local actionOk, actionErr = pcall(function()
        Actions.ExecuteAction(NINJA_MODE.hideActionId)
    end)
    if not actionOk then
        logf("Hide action execution raised an error: %s.", tostring(actionErr))
        return false, "execute_error"
    end

    local hidden = waitUntil(function()
        return NINJA_MODE.isHidden() or TREASURE_RUNTIME.cofferRevealed
    end, tonumber(NINJA_MODE.hideStatusAcquireTimeout) or 3.0, 0.1)

    if TREASURE_RUNTIME.cofferRevealed and not NINJA_MODE.isHidden() then
        return false, "coffer_revealed"
    end
    if hidden and NINJA_MODE.isHidden() then
        NINJA_MODE.lastHideActivatedAt = os.clock()
        logf("Hide applied for dangerous candidate %s.", tostring(candidate and candidate.label or "?"))
        return true, "hidden"
    end

    local remaining, recastTime, elapsed, source = NINJA_MODE.getHideCooldownRemaining()
    LOGGING.verbosef(
        "Hide status %d not acquired after action call for candidate %s; remaining=%.2fs recast=%.2fs elapsed=%.2fs source=%s job=%s mounted=%s.",
        NINJA_MODE.hiddenStatusId,
        tostring(candidate and candidate.label or "?"),
        remaining,
        recastTime,
        elapsed,
        tostring(source),
        tostring(NINJA_MODE.getBestEffortJobLabel()),
        tostring(isMounted())
    )
    return false, "status_not_acquired"
end

NINJA_MODE.beginCandidate = function(candidate)
    NINJA_MODE.activeCandidateLabel = tostring(candidate and candidate.label or "?")
    NINJA_MODE.activeCandidateDangerous = NINJA_MODE.isDangerousCandidate(candidate)
    NINJA_MODE.hideFailed = false
    NINJA_MODE.hideRetryUsed = false
    NINJA_MODE.abortReason = nil
    TREASURE_RUNTIME.revealedCofferBypassLogged = false
    logf("Starting candidate %s: dangerous=%s; candidate-specific Ninja/Hide state reset.", NINJA_MODE.activeCandidateLabel, tostring(NINJA_MODE.activeCandidateDangerous))
end

NINJA_MODE.endCandidate = function()
    NINJA_MODE.activeCandidateLabel = nil
    NINJA_MODE.activeCandidateDangerous = false
    NINJA_MODE.hideFailed = false
    NINJA_MODE.hideRetryUsed = false
    NINJA_MODE.abortReason = nil
end

NINJA_MODE.ensureHiddenOrAbort = function(candidate)
    if TREASURE_RUNTIME.cofferRevealed then
        NINJA_MODE.hideFailed = false
        NINJA_MODE.abortReason = nil
        return true
    end
    if NINJA_MODE.isHidden() then
        NINJA_MODE.hideFailed = false
        NINJA_MODE.abortReason = nil
        return true
    end

    local gearsetOk, gearsetErr = NINJA_MODE.ensureGearset()
    if not gearsetOk then
        NINJA_MODE.hideFailed = false
        NINJA_MODE.abortReason = "gearset_failed"
        logf("Failed to validate Ninja gearset before Hide for candidate %s: %s", tostring(candidate and candidate.label or "?"), tostring(gearsetErr))
        return false
    end

    logf("Hide status %d missing for candidate %s; preparing hidden travel.", NINJA_MODE.hiddenStatusId, tostring(candidate and candidate.label or "?"))
    local hidden, firstReason = NINJA_MODE.tryHideOnce(candidate)
    if hidden then
        NINJA_MODE.hideFailed = false
        NINJA_MODE.abortReason = nil
        return true
    end
    if firstReason == "coffer_revealed" then
        NINJA_MODE.hideFailed = false
        NINJA_MODE.abortReason = nil
        return true
    end
    if firstReason ~= "status_not_acquired" then
        NINJA_MODE.hideFailed = true
        NINJA_MODE.abortReason = "hide_failed"
        logf("Hide could not be applied for candidate %s (%s); abandoning this candidate to avoid unhidden aggro risk.", tostring(candidate and candidate.label or "?"), tostring(firstReason or "unknown"))
        return false
    end

    NINJA_MODE.hideRetryUsed = true
    logf("Hide was ready but did not apply for candidate %s; waiting for its next ready state before one final attempt.", tostring(candidate and candidate.label or "?"))
    local retryHidden, retryReason = NINJA_MODE.tryHideOnce(candidate)
    if retryHidden then
        NINJA_MODE.hideFailed = false
        NINJA_MODE.abortReason = nil
        return true
    end
    if retryReason == "coffer_revealed" then
        NINJA_MODE.hideFailed = false
        NINJA_MODE.abortReason = nil
        return true
    end

    NINJA_MODE.hideFailed = true
    NINJA_MODE.abortReason = "hide_failed"
    logf("Hide failed after two ready-state attempts for candidate %s; abandoning this candidate to avoid unhidden aggro risk.", tostring(candidate and candidate.label or "?"))
    return false
end

local function moveToCandidatePositionWithRetryInternal(targetPosition, stopDistance, contextLabel, allowMount, hardTimeout)
    local desiredStopDistance = stopDistance or TREASURE_CANDIDATE_STOP_DISTANCE

    for attempt = 1, TREASURE_CANDIDATE_TRAVEL.maxAttempts do
        local startPosition = getPlayerPosition()
        if distanceFlat(startPosition, targetPosition) <= desiredStopDistance then
            return true, getPlayerPosition(), attempt, "already_near"
        end

        if allowMount ~= false then
            ensureMounted()
        end
        if not pathfindTo(targetPosition) then
            logf("%s candidate travel attempt %d/%d failed to start vnav movement.", tostring(contextLabel), attempt, TREASURE_CANDIDATE_TRAVEL.maxAttempts)
        else
            local started = waitUntil(function()
                return isVnavActive()
            end, TREASURE_MOVE_START_TIMEOUT, 0)

            if not started then
                logf("%s candidate travel attempt %d/%d never entered pathfind or running state.", tostring(contextLabel), attempt, TREASURE_CANDIDATE_TRAVEL.maxAttempts)
            else
                local candidateTimeout = tonumber(hardTimeout) or TREASURE_CANDIDATE_TRAVEL.hardTimeout
                local deadline = os.clock() + candidateTimeout
                local movementWatch = TREASURE_RUNTIME.newMovementWatch(startPosition, targetPosition)

                while os.clock() < deadline do
                    local currentPosition = getPlayerPosition()
                    local currentDistance = distanceFlat(currentPosition, targetPosition)
                    if currentDistance <= desiredStopDistance then
                        stopPathing()
                        return true, currentPosition, attempt, "arrived"
                    end

                    local movementStatus, movementDetail = TREASURE_RUNTIME.checkMovementWatch(
                        movementWatch,
                        currentPosition,
                        targetPosition,
                        TREASURE_CANDIDATE_TRAVEL.progressMinMove,
                        TREASURE_CANDIDATE_TRAVEL.progressTimeout,
                        TREASURE_RUNTIME.movementDetourTimeout,
                        TREASURE_RUNTIME.movementStationaryThreshold
                    )
                    if movementStatus == "stalled" then
                        stopPathing()
                        logf(
                            "%s candidate travel attempt %d/%d stalled: player remained effectively stationary for %.1fs while remaining distance changed from %.1fy to %.1fy.",
                            tostring(contextLabel),
                            attempt,
                            TREASURE_CANDIDATE_TRAVEL.maxAttempts,
                            tonumber(movementDetail.stationaryFor) or 0,
                            tonumber(movementDetail.previousDistance) or currentDistance,
                            currentDistance
                        )
                        break
                    elseif movementStatus == "detour_timeout" then
                        stopPathing()
                        logf(
                            "%s candidate travel attempt %d/%d remained on a moving detour for %.1fs without meaningful target-distance improvement; player moved %.1fy and remaining distance changed from %.1fy to %.1fy.",
                            tostring(contextLabel),
                            attempt,
                            TREASURE_CANDIDATE_TRAVEL.maxAttempts,
                            tonumber(movementDetail.detourFor) or 0,
                            tonumber(movementDetail.playerTravel) or 0,
                            tonumber(movementDetail.previousDistance) or currentDistance,
                            currentDistance
                        )
                        break
                    end

                    if not isVnavActive() then
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
                    logf("%s candidate travel attempt %d/%d hit hard timeout after %.0fs.", tostring(contextLabel), attempt, TREASURE_CANDIDATE_TRAVEL.maxAttempts, candidateTimeout)
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

NINJA_MODE.moveToDangerousCandidate = function(previousCandidate, candidate, targetPosition, stopDistance, contextLabel)
    local gearsetOk, gearsetErr = NINJA_MODE.ensureGearset()
    if not gearsetOk then
        NINJA_MODE.gearsetEquipped = false
        NINJA_MODE.abortReason = "gearset_failed"
        logf("Failed to equip Ninja gearset after retry; skipping dangerous candidate %s: %s", tostring(candidate and candidate.label or "?"), tostring(gearsetErr))
        return false, getPlayerPosition(), 1, "gearset_failed"
    end
    local hardTimeout = tonumber(candidate and candidate.travelTimeout) or TREASURE_CANDIDATE_TRAVEL.hardTimeout

    local currentPosition = getPlayerPosition()
    if NINJA_MODE.isWithinHideThreshold(previousCandidate, currentPosition) then
        if isInCombat() then
            logf("In combat near previous dangerous candidate %s; skipping Hide and continuing mounted.", tostring(previousCandidate and previousCandidate.label or "?"))
        else
            if not NINJA_MODE.ensureHiddenOrAbort(NINJA_MODE.getHideThresholdContext(previousCandidate, candidate, currentPosition)) then
                return false, getPlayerPosition(), 1, tostring(NINJA_MODE.abortReason or "hide_failed")
            end
            local clearPoint = NINJA_MODE.getThresholdApproachPoint(previousCandidate, targetPosition, 6.0)
            if clearPoint ~= nil then
                local cleared = moveToCandidatePositionWithRetryInternal(clearPoint, 3.5, contextLabel .. " previous threshold", false, hardTimeout)
                if not cleared then
                    return false, getPlayerPosition(), TREASURE_CANDIDATE_TRAVEL.maxAttempts, "failed_previous_threshold"
                end
            end
        end
    end

    currentPosition = getPlayerPosition()
    if not NINJA_MODE.isWithinHideThreshold(candidate, currentPosition) then
        local thresholdPoint = NINJA_MODE.getThresholdApproachPoint(candidate, currentPosition, 0)
        if thresholdPoint ~= nil then
            local moved, endPosition, attempt, reason = moveToCandidatePositionWithRetryInternal(thresholdPoint, 3.5, contextLabel .. " threshold", true, hardTimeout)
            if not moved then
                return moved, endPosition, attempt, reason
            end
        end
    end

    if isInCombat() then
        logf("In combat at dangerous candidate %s; skipping Hide and continuing without hidden travel.", tostring(candidate and candidate.label or "?"))
        return moveToCandidatePositionWithRetryInternal(targetPosition, stopDistance, contextLabel, true, hardTimeout)
    end

    if not NINJA_MODE.ensureHiddenOrAbort(candidate) then
        return false, getPlayerPosition(), 1, tostring(NINJA_MODE.abortReason or "hide_failed")
    end
    return moveToCandidatePositionWithRetryInternal(targetPosition, stopDistance, contextLabel, false, hardTimeout)
end

NINJA_MODE.moveToTreasureCandidate = function(previousCandidate, candidate, targetPosition, stopDistance, contextLabel)
    if NINJA_MODE.isDangerousCandidate(candidate) then
        return NINJA_MODE.moveToDangerousCandidate(previousCandidate, candidate, targetPosition, stopDistance, contextLabel)
    end

    if previousCandidate ~= nil and NINJA_MODE.isDangerousCandidate(previousCandidate) then
        logf("Candidate %s is not dangerous; previous candidate %s Hide state will not be inherited.", tostring(candidate and candidate.label or "?"), tostring(previousCandidate.label or "?"))
    end
    NINJA_MODE.hideFailed = false
    NINJA_MODE.hideRetryUsed = false
    NINJA_MODE.abortReason = nil
    return moveToCandidatePositionWithRetryInternal(targetPosition, stopDistance, contextLabel, true, tonumber(candidate and candidate.travelTimeout))
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

ensureDismounted = function(timeoutSec)
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

local function isNearBaseCamp(radius)
    local baseCamp = metadata and metadata.aethernets and metadata.aethernets.BaseCamp or nil
    local playerPosition = getPlayerPosition()
    if baseCamp == nil or playerPosition == nil then
        return false
    end
    return distanceFlat(playerPosition, baseCamp.position) <= (tonumber(radius) or 120.0)
end

local function waitForReturnReady(timeoutSec)
    local deadline = os.clock() + (tonumber(timeoutSec) or RETURN_MODE.readinessTimeoutSeconds)
    while os.clock() < deadline do
        if isNearBaseCamp(120.0) then
            return true, nil
        end
        if isPlayerAvailable()
            and not isDead()
            and not isInCombat()
            and not isMounting()
            and not getCondition(CharacterCondition.casting)
            and not getCondition(CharacterCondition.betweenAreas)
            and not getCondition(CharacterCondition.occupiedInQuestEvent)
            and not isLifestreamBusy()
        then
            return true, nil
        end
        sleep(POLL_INTERVAL)
    end
    return false, string.format(
        "player not ready for Return (available=%s dead=%s combat=%s mounted=%s mounting=%s casting=%s betweenAreas=%s occupied=%s lifestreamBusy=%s)",
        tostring(isPlayerAvailable()),
        tostring(isDead()),
        tostring(isInCombat()),
        tostring(isMounted()),
        tostring(isMounting()),
        tostring(getCondition(CharacterCondition.casting)),
        tostring(getCondition(CharacterCondition.betweenAreas)),
        tostring(getCondition(CharacterCondition.occupiedInQuestEvent)),
        tostring(isLifestreamBusy())
    )
end

local function useReturnOnce()
    if isNearBaseCamp(120.0) then
        return true, nil
    end
    if isDead() or isInCombat() or isMounting() then
        return false, "cannot use Return right now"
    end
    if not executeGeneralAction(GENERAL_ACTION_RETURN) then
        return false, "failed to trigger Return"
    end
    local deadline = os.clock() + RETURN_MODE.castStartTimeoutSeconds
    local castingStarted = false
    while os.clock() < deadline do
        if isAddonReady("SelectYesno") then
            yield("/callback SelectYesno true 0")
            castingStarted = waitUntil(function()
                return getCondition(CharacterCondition.casting) or getCondition(CharacterCondition.betweenAreas)
            end, RETURN_MODE.castStartTimeoutSeconds, 0)
            break
        end
        if getCondition(CharacterCondition.casting) or getCondition(CharacterCondition.betweenAreas) then
            castingStarted = true
            break
        end
        sleep(POLL_INTERVAL)
    end
    if not castingStarted then
        if isNearBaseCamp(120.0) then
            return true, nil
        end
        return false, "return did not start casting"
    end
    if not waitForTransitionCompletion(CharacterCondition.casting, TRANSITION_TIMEOUT, "Return") then
        if isNearBaseCamp(120.0) then
            return true, nil
        end
        return false, "return transition did not complete"
    end
    return true, nil
end

local function useReturnWithRetry()
    if isNearBaseCamp(120.0) then
        return true, nil
    end

    stopPathing()
    local openedAt = tonumber(TREASURE_RUNTIME.lastCofferOpenedAt)
    if openedAt ~= nil then
        local remainingCooldown = RETURN_MODE.postCofferCooldownSeconds - (os.clock() - openedAt)
        if remainingCooldown > 0 then
            logf("Waiting %.1f second(s) after coffer interaction before using Return.", remainingCooldown)
            sleep(remainingCooldown)
        end
    end

    local lastError = "unknown Return failure"
    for attempt = 1, RETURN_MODE.maxAttempts do
        if isNearBaseCamp(120.0) then
            return true, nil
        end

        local ready, readyErr = waitForReturnReady(RETURN_MODE.readinessTimeoutSeconds)
        if not ready then
            lastError = readyErr or "player was not ready"
            logf("Return attempt %d/%d could not start: %s.", attempt, RETURN_MODE.maxAttempts, tostring(lastError))
        else
            logf("Return attempt %d/%d%s.", attempt, RETURN_MODE.maxAttempts, isMounted() and " while mounted" or "")
            local ok, err = useReturnOnce()
            if ok then
                logf("Return completed successfully on attempt %d/%d.", attempt, RETURN_MODE.maxAttempts)
                return true, nil
            end
            lastError = err or "unknown Return failure"
            logf("Return attempt %d/%d failed: %s.", attempt, RETURN_MODE.maxAttempts, tostring(lastError))
        end

        if attempt < RETURN_MODE.maxAttempts then
            if isNearBaseCamp(120.0) then
                return true, nil
            end
            logf("Waiting %.1f second(s) before retrying Return.", RETURN_MODE.retryDelaySeconds)
            sleep(RETURN_MODE.retryDelaySeconds)
        end
    end

    return false, string.format("Return failed after %d attempts: %s", RETURN_MODE.maxAttempts, tostring(lastError))
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
        LOGGING.verbose("Autorotation enabled for FATE.")
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
        local ok, err = useReturnWithRetry()
        if not ok then
            logf("%s Attempting BaseCamp aethernet fallback.", tostring(err))
            local fallbackOk, fallbackErr = useOccultAethernet(baseCamp)
            if not fallbackOk then
                return false, string.format("%s; BaseCamp aethernet fallback also failed: %s", tostring(err), tostring(fallbackErr))
            end
        end
    end

    local waitPoint = getBaseCampWaitPoint()
    if waitPoint == nil then
        return false, "base camp wait point unavailable"
    end
    if not moveToPosition(waitPoint, WAIT_POINT_FALLBACK_DISTANCE) then
        return false, "failed to move to base camp wait point"
    end
    if not ensureDismounted(5.0) then
        return false, "failed to dismount at base camp wait point"
    end
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
        position = candidate.position,
        aggroLevel = candidate.aggroLevel,
        hideThreshold = candidate.hideThreshold,
        travelTimeout = candidate.travelTimeout,
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
        if NINJA_MODE.isDangerousCandidate(candidate) and not NINJA_MODE.enabled then
            skippedDangerous = skippedDangerous + 1
        else
            table.insert(eligible, cloneCandidate(candidate))
        end
    end

    if #eligible == 0 then
        return nil, skippedDangerous, "all candidates were filtered above max aggro"
    end

    local ordered = {}
    local remaining = eligible
    local currentPoint = fateInfo.location
    while #remaining > 0 do
        local bestIndex = 1
        local bestDistance = math.huge
        for index, candidate in ipairs(remaining) do
            local destination = candidate.position
            local dist = distanceFlat(currentPoint, destination)
            if dist < bestDistance then
                bestDistance = dist
                bestIndex = index
            end
        end
        local chosen = table.remove(remaining, bestIndex)
        table.insert(ordered, chosen)
        currentPoint = chosen.position
    end

    return ordered, skippedDangerous, nil
end

TREASURE_RUNTIME.findCandidateHandoff = function(currentCandidate, referencePosition)
    local context = TREASURE_RUNTIME.currentContext
    if currentCandidate == nil or referencePosition == nil or context == nil then
        return nil, nil, nil
    end

    local groupsForFate = COFFER_GROUPS[context.fateName]
    local group = groupsForFate and groupsForFate[context.group or ""] or nil
    if group == nil then
        return nil, nil, nil
    end

    local handled = context.handledCandidateLabels or {}
    local currentDistance = distanceFlat(referencePosition, currentCandidate.position)
    local bestCandidate = nil
    local bestDistance = math.huge

    for _, configuredCandidate in ipairs(group) do
        local label = tostring(configuredCandidate.label or "?")
        if label ~= tostring(currentCandidate.label or "?") and not handled[label] then
            local candidateDistance = distanceFlat(referencePosition, configuredCandidate.position)
            local advantage = currentDistance - candidateDistance
            if candidateDistance <= TREASURE_RUNTIME.candidateHandoffRadius
                and advantage >= TREASURE_RUNTIME.candidateHandoffAdvantage
                and candidateDistance < bestDistance
            then
                bestCandidate = cloneCandidate(configuredCandidate)
                bestDistance = candidateDistance
            end
        end
    end

    if bestCandidate == nil then
        return nil, currentDistance, nil
    end
    return bestCandidate, currentDistance, bestDistance
end

TREASURE_RUNTIME.activateCandidateHandoff = function(previousCandidate, nextCandidate, referencePosition, reason)
    if previousCandidate == nil or nextCandidate == nil then
        return false, previousCandidate, "invalid_handoff"
    end

    local nextDangerous = NINJA_MODE.isDangerousCandidate(nextCandidate)
    if nextDangerous and not NINJA_MODE.enabled then
        logf(
            "Treasure refinement approached dangerous candidate %s while refining %s, but Ninja mode is disabled; stopping before entering the dangerous handoff area.",
            tostring(nextCandidate.label or "?"),
            tostring(previousCandidate.label or "?")
        )
        return false, previousCandidate, "dangerous_handoff_unavailable"
    end

    stopPathing()
    local previousDistance = distanceFlat(referencePosition, previousCandidate.position)
    local nextDistance = distanceFlat(referencePosition, nextCandidate.position)
    local context = TREASURE_RUNTIME.currentContext
    if context ~= nil then
        context.handledCandidateLabels = context.handledCandidateLabels or {}
        context.handledCandidateLabels[tostring(previousCandidate.label or "?")] = true
        context.handledCandidateLabels[tostring(nextCandidate.label or "?")] = true
        context.candidateLabel = nextCandidate.label
        context.dangerous = nextDangerous
        context.currentCandidate = nextCandidate
        context.note = nextCandidate.note
    end

    NINJA_MODE.beginCandidate(nextCandidate)
    logf(
        "Treasure refinement handed off from %s to %s: reference position is %.1fy from %s and %.1fy from %s%s.",
        tostring(previousCandidate.label or "?"),
        tostring(nextCandidate.label or "?"),
        nextDistance,
        tostring(nextCandidate.label or "?"),
        previousDistance,
        tostring(previousCandidate.label or "?"),
        reason and (" (" .. tostring(reason) .. ")") or ""
    )

    if nextDangerous and not TREASURE_RUNTIME.cofferRevealed then
        logf("Handoff candidate %s is dangerous; applying Hide before continuing.", tostring(nextCandidate.label or "?"))
        if not NINJA_MODE.ensureHiddenOrAbort(nextCandidate) then
            return false, nextCandidate, tostring(NINJA_MODE.abortReason or "hide_failed")
        end
    end

    return true, nextCandidate, nil
end

TREASURE_RUNTIME.checkCandidateHandoff = function(currentCandidate, referencePosition, reason)
    local nextCandidate, currentDistance, nextDistance = TREASURE_RUNTIME.findCandidateHandoff(currentCandidate, referencePosition)
    if nextCandidate == nil then
        return true, currentCandidate, nil
    end

    LOGGING.verbosef(
        "Candidate handoff qualified: current=%s currentDist=%.1f next=%s nextDist=%.1f advantage=%.1f reason=%s.",
        tostring(currentCandidate and currentCandidate.label or "?"),
        tonumber(currentDistance) or -1,
        tostring(nextCandidate.label or "?"),
        tonumber(nextDistance) or -1,
        (tonumber(currentDistance) or 0) - (tonumber(nextDistance) or 0),
        tostring(reason or "unspecified")
    )
    return TREASURE_RUNTIME.activateCandidateHandoff(currentCandidate, nextCandidate, referencePosition, reason)
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

TREASURE_RUNTIME.isPlausibleNavmeshPoint = function(point)
    if point == nil then
        return false, "nil_point"
    end

    local x = tonumber(point.X)
    local y = tonumber(point.Y)
    local z = tonumber(point.Z)
    if x == nil or y == nil or z == nil then
        return false, "non_numeric"
    end
    if x ~= x or y ~= y or z ~= z then
        return false, "nan"
    end
    if math.abs(x) == math.huge or math.abs(y) == math.huge or math.abs(z) == math.huge then
        return false, "infinite"
    end
    if math.abs(x) > TREASURE_RUNTIME.navmeshCoordinateAbsLimit
        or math.abs(y) > TREASURE_RUNTIME.navmeshCoordinateAbsLimit
        or math.abs(z) > TREASURE_RUNTIME.navmeshCoordinateAbsLimit then
        return false, "absurd_coordinate"
    end
    if math.abs(y - TREASURE_RUNTIME.navmeshSentinelY) < TREASURE_RUNTIME.navmeshSentinelTolerance then
        return false, "sentinel_elevation"
    end
    if y < TREASURE_RUNTIME.navmeshMinimumValidY or y > TREASURE_RUNTIME.navmeshMaximumValidY then
        return false, "elevation_out_of_range"
    end

    return true, nil, x, y, z
end

TREASURE_RUNTIME.validateNavmeshResolution = function(referencePoint, meshPoint, maxVerticalDelta)
    local plausible, reason, _, meshY = TREASURE_RUNTIME.isPlausibleNavmeshPoint(meshPoint)
    if not plausible then
        return false, reason, nil
    end

    local referenceY = referencePoint and tonumber(referencePoint.Y) or nil
    if referenceY == nil or referenceY ~= referenceY or math.abs(referenceY) == math.huge then
        return false, "invalid_reference", nil
    end

    local verticalDelta = math.abs(meshY - referenceY)
    local allowedDelta = tonumber(maxVerticalDelta) or TREASURE_RUNTIME.navmeshMaxVerticalSnap
    if verticalDelta > allowedDelta then
        return false, "vertical_snap", verticalDelta
    end

    return true, nil, verticalDelta
end

local function resolvePotFateLocation(fateName, runtimeLocation)
    if isValidWorldPosition(runtimeLocation) then
        return runtimeLocation, false
    end
    local fallback = POT_FATES[fateName]
    return fallback and fallback.location or runtimeLocation, true
end

TREASURE_RUNTIME.resolveInitialProbeCenterFallback = function(fateCenter)
    if not isValidWorldPosition(fateCenter) then
        return nil
    end

    local playerPosition = getPlayerPosition()
    if playerPosition == nil then
        return nil
    end

    local bestPoint = nil
    local bestDrift = math.huge
    local searchRadii = { 2, 4, 6, 10, 12 }

    local function consider(point)
        local validMeshPoint, rejectionReason, verticalDelta = TREASURE_RUNTIME.validateNavmeshResolution(
            fateCenter,
            point,
            TREASURE_RUNTIME.initialProbeCenterMaxVerticalSnap
        )
        if not validMeshPoint then
            if point ~= nil then
                LOGGING.verbosef(
                    "Initial probe center fallback rejected navmesh point %s: reason=%s verticalSnap=%s.",
                    formatVector3(point),
                    tostring(rejectionReason),
                    verticalDelta and string.format("%.1fy", verticalDelta) or "n/a"
                )
            end
            return
        end

        local drift = distanceFlat(point, fateCenter)
        if drift > TREASURE_RUNTIME.initialProbeCenterMaxSnapDistance or drift >= bestDrift then
            return
        end

        local _, hasRoute = pathfindRoute(playerPosition, point)
        if not hasRoute then
            return
        end

        bestPoint = point
        bestDrift = drift
    end

    for _, radius in ipairs(searchRadii) do
        consider(getPointOnFloor(fateCenter, radius))
        consider(getNearestNavmeshPoint(
            fateCenter,
            radius,
            math.max(TREASURE_NAVMESH_HALF_EXTENT_Y, radius)
        ))
    end

    return bestPoint
end

TREASURE_RUNTIME.moveToInitialProbeOrigin = function(fateName, fateCenter)
    if not isValidWorldPosition(fateCenter) then
        logf("No valid center position was available for %s; using the initial Magical Elixir from the current position.", tostring(fateName))
        return false
    end

    local function moveLocal(targetPosition, stopDistance, timeoutSeconds)
        if distanceFlat(getPlayerPosition(), targetPosition) <= stopDistance then
            return true
        end
        if not pathfindTo(targetPosition) then
            return false
        end

        local started = waitUntil(function()
            return distanceFlat(getPlayerPosition(), targetPosition) <= stopDistance or isVnavActive()
        end, 2.0, 0.1)
        if not started then
            stopPathing()
            return false
        end

        local deadline = os.clock() + math.max(1.0, timeoutSeconds)
        while os.clock() < deadline do
            if distanceFlat(getPlayerPosition(), targetPosition) <= stopDistance then
                stopPathing()
                return true
            end
            if not isVnavActive() then
                stopPathing()
                return false
            end
            sleep(0.2)
        end

        stopPathing()
        return false
    end

    stopPathing()
    local playerPosition = getPlayerPosition()
    local currentDistance = distanceFlat(playerPosition, fateCenter)
    if currentDistance <= TREASURE_RUNTIME.initialProbeCenterStopDistance then
        logf("Already within %.1fy of %s center; beginning treasure search.", currentDistance, tostring(fateName))
        return true
    end

    local ready = waitUntil(function()
        return not isInCombat()
            and not getCondition(CharacterCondition.casting)
            and not getCondition(CharacterCondition.betweenAreas)
    end, 10.0, 0.25)
    if not ready then
        logf("Post-FATE combat or action lock did not fully clear before moving to %s center; attempting the local move anyway.", tostring(fateName))
    end

    logf(
        "Moving to %s center at %s before the initial Magical Elixir use.",
        tostring(fateName),
        formatVector3(fateCenter)
    )

    for attempt = 1, TREASURE_RUNTIME.initialProbeCenterMoveAttempts do
        stopPathing()
        local attemptDeadline = os.clock() + TREASURE_RUNTIME.initialProbeCenterMoveTimeout
        local moved = moveLocal(
            fateCenter,
            TREASURE_RUNTIME.initialProbeCenterStopDistance,
            math.max(1.0, attemptDeadline - os.clock())
        )

        if not moved then
            local fallbackPoint = TREASURE_RUNTIME.resolveInitialProbeCenterFallback(fateCenter)
            local remaining = attemptDeadline - os.clock()
            if fallbackPoint ~= nil and remaining > 1.0 then
                logf(
                    "Direct path to %s center failed on attempt %d/%d; trying nearby navmesh point %s (%.1fy from center).",
                    tostring(fateName),
                    attempt,
                    TREASURE_RUNTIME.initialProbeCenterMoveAttempts,
                    formatVector3(fallbackPoint),
                    distanceFlat(fallbackPoint, fateCenter)
                )
                moved = moveLocal(fallbackPoint, 1.5, remaining)
            end
        end

        stopPathing()
        waitUntil(function()
            return not isVnavActive()
        end, 2.0, 0.1)

        local finalPosition = getPlayerPosition()
        local finalDistance = distanceFlat(finalPosition, fateCenter)
        if moved and finalDistance <= TREASURE_RUNTIME.initialProbeCenterMaxSnapDistance then
            logf("Arrived within %.1fy of %s center; beginning treasure search.", finalDistance, tostring(fateName))
            return true
        end

        if attempt < TREASURE_RUNTIME.initialProbeCenterMoveAttempts then
            logf(
                "Initial move to %s center failed on attempt %d/%d; retrying after %.1f second(s).",
                tostring(fateName),
                attempt,
                TREASURE_RUNTIME.initialProbeCenterMoveAttempts,
                TREASURE_RUNTIME.initialProbeCenterRetryDelay
            )
            sleep(TREASURE_RUNTIME.initialProbeCenterRetryDelay)
        end
    end

    stopPathing()
    logf(
        "Could not reach the %s center after %d attempts; using the initial Magical Elixir from the current position. The first direction may be less reliable.",
        tostring(fateName),
        TREASURE_RUNTIME.initialProbeCenterMoveAttempts
    )
    return false
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

    if #result == 0 then
        potCycleRuntime.activeFateName = nil
    elseif potCycleRuntime.activeFateName == nil or potCycleRuntime.activeFateName ~= result[1].name then
        local observed = result[1]
        potCycleRuntime.activeFateName = observed.name
        potCycleRuntime.lastSpawnFateName = observed.name
        potCycleRuntime.lastSpawnAt = os.clock()
        potCycleRuntime.lastInterspawnPredictionBucket = nil
        potCycleRuntime.interspawnPredictionOverdueLogged = false
        logf("Recorded pot FATE spawn anchor for '%s' at first active-list observation; next pot spawn is predicted 30.0 minutes from this timestamp.", observed.name)
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


function INSTANCE_TIME_MODE.getContentTimeLeft()
    local value = safeCall(function()
        return InstancedContent.ContentTimeLeft
    end)
    return tonumber(value) or 0
end

function INSTANCE_TIME_MODE.getSecondsUntilNextPotSpawn(now)
    now = tonumber(now) or os.clock()
    if potCycleRuntime.lastSpawnAt == nil then
        return POT_CYCLE_SECONDS, "unknown_cycle_worst_case"
    end

    local elapsed = math.max(0, now - potCycleRuntime.lastSpawnAt)
    if elapsed < POT_CYCLE_SECONDS then
        return POT_CYCLE_SECONDS - elapsed, "predicted_from_last_spawn"
    end

    local phase = elapsed % POT_CYCLE_SECONDS
    if phase <= INSTANCE_TIME_MODE.spawnGraceSeconds then
        return 0, "predicted_spawn_grace"
    end
    return POT_CYCLE_SECONDS - phase, "rolled_spawn_schedule"
end

function INSTANCE_TIME_MODE.evaluate(context)
    if not INSTANCE_TIME_MODE.enabled or INSTANCE_TIME_MODE.exitRequested or INSTANCE_TIME_MODE.leavePending then
        return false, nil
    end

    local timeLeft = INSTANCE_TIME_MODE.getContentTimeLeft()
    if timeLeft <= 0 then
        return false, nil
    end

    local activePot = getBestActivePotFate(nil)
    local waitSeconds = 0
    local timingSource = "active_pot_fate"
    if activePot == nil then
        waitSeconds, timingSource = INSTANCE_TIME_MODE.getSecondsUntilNextPotSpawn(os.clock())
    end

    local requiredSeconds = waitSeconds
        + INSTANCE_TIME_MODE.fateBudgetSeconds
        + INSTANCE_TIME_MODE.treasureBudgetSeconds
        + INSTANCE_TIME_MODE.exitBufferSeconds
    local shouldLeave = timeLeft < requiredSeconds
    local now = os.clock()
    if shouldLeave or (now - INSTANCE_TIME_MODE.lastDecisionLogAt) >= INSTANCE_TIME_MODE.decisionLogInterval then
        logf(
            "Instance time check [%s]: remaining=%.1f min, nextPotIn=%.1f min (%s), required=%.1f min [FATE %.1f + treasure %.1f + exit %.1f], decision=%s.",
            tostring(context or "unspecified"),
            timeLeft / 60.0,
            waitSeconds / 60.0,
            tostring(timingSource),
            requiredSeconds / 60.0,
            INSTANCE_TIME_MODE.fateBudgetSeconds / 60.0,
            INSTANCE_TIME_MODE.treasureBudgetSeconds / 60.0,
            INSTANCE_TIME_MODE.exitBufferSeconds / 60.0,
            shouldLeave and "leave" or "stay"
        )
        INSTANCE_TIME_MODE.lastDecisionLogAt = now
    end

    return shouldLeave, {
        timeLeft = timeLeft,
        waitSeconds = waitSeconds,
        requiredSeconds = requiredSeconds,
        timingSource = timingSource,
        activePot = activePot,
    }
end

function INSTANCE_TIME_MODE.leaveIfNeeded(context)
    if INSTANCE_TIME_MODE.leavePending then
        return false
    end

    local shouldLeave, detail = INSTANCE_TIME_MODE.evaluate(context)
    if not shouldLeave then
        return false
    end

    local canLeave = safeCall(function()
        return InstancedContent.CanLeaveCurrentContent()
    end)
    if canLeave == false then
        logf("Instance time is below the safe-cycle requirement, but the content cannot be left yet [%s]. Will retry.", tostring(context or "unspecified"))
        return false
    end

    stopPathing()
    pcall(clearBossModPreset)
    logf(
        "Leaving South Horn: %.1f minute(s) remain, but %.1f minute(s) are required to wait for the next spawn, complete the FATE, find the coffer, and preserve the exit buffer.",
        detail.timeLeft / 60.0,
        detail.requiredSeconds / 60.0
    )

    INSTANCE_TIME_MODE.leavePending = true
    local called = pcall(function()
        InstancedContent.LeaveCurrentContent()
    end)
    if not called then
        INSTANCE_TIME_MODE.leavePending = false
        INSTANCE_TIME_MODE.exitRequested = false
        log("InstancedContent.LeaveCurrentContent() raised an error; leave will be retried.")
        return false
    end

    local deadline = os.clock() + 15.0
    while os.clock() < deadline and isInSouthHorn() do
        sleep(0.25)
    end

    INSTANCE_TIME_MODE.leavePending = false
    if isInSouthHorn() then
        INSTANCE_TIME_MODE.exitRequested = false
        log("Leave request was issued, but no territory transition was observed. The script remains active and will retry leaving.")
        return false
    end

    INSTANCE_TIME_MODE.exitRequested = true
    log("South Horn leave transition completed.")
    return true
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

local function travelToPoint(targetPosition, preferredAethernetName, stopDistance, verboseTravel)
    local route = chooseRouteToPoint(targetPosition, preferredAethernetName)
    if verboseTravel then
        LOGGING.verbosef("Traveling to %s via %s (%s).", formatVector3(targetPosition), route.kind, route.reason)
    else
        logf("Traveling to %s via %s (%s).", formatVector3(targetPosition), route.kind, route.reason)
    end
    if route.kind == "return" then
        local ok, err = useReturnWithRetry()
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

TREASURE_RUNTIME.formatSpawnCountdown = function(seconds)
    seconds = math.max(0, math.floor((tonumber(seconds) or 0) + 0.5))
    local minutes = math.floor(seconds / 60)
    local remainingSeconds = seconds % 60
    return string.format("%dm %02ds", minutes, remainingSeconds)
end

TREASURE_RUNTIME.getSpawnCountdownDelay = function(secondsUntilSpawn)
    secondsUntilSpawn = math.max(0, tonumber(secondsUntilSpawn) or 0)
    if secondsUntilSpawn > 60 then
        return math.max(0.5, math.min(60, secondsUntilSpawn - 60))
    end
    if secondsUntilSpawn > 10 then
        return math.max(0.5, math.min(10, secondsUntilSpawn - 10))
    end
    return math.max(0.5, math.min(5, secondsUntilSpawn))
end

local function waitAtSpawnForFate(targetName, options)
    options = options or {}
    local mode = tostring(options.mode or "bootstrap")
    local predictedSpawnAt = tonumber(options.predictedSpawnAt)
    local timeoutSec = math.max(0, tonumber(options.timeoutSeconds) or (INITIAL_SPAWN_WAIT_MINUTES * 60))
    local graceSeconds = math.max(0, tonumber(options.graceSeconds) or (5 * 60))

    ensureDismounted(5.0)

    local now = os.clock()
    local deadline
    local nextCountdownLogAt
    local predictionReachedLogged = false
    local lastOverdueLogAt = 0

    if mode == "predicted" and predictedSpawnAt ~= nil then
        INSTANCE_TIME_MODE.lastDecisionLogAt = os.clock() - INSTANCE_TIME_MODE.decisionLogInterval
        deadline = predictedSpawnAt + graceSeconds
        local secondsUntilSpawn = predictedSpawnAt - now
        if secondsUntilSpawn > 0 then
            logf("Waiting at %s spawn. Predicted spawn in %s.", targetName, TREASURE_RUNTIME.formatSpawnCountdown(secondsUntilSpawn))
            nextCountdownLogAt = now + TREASURE_RUNTIME.getSpawnCountdownDelay(secondsUntilSpawn)
        else
            predictionReachedLogged = true
            logf("%s predicted spawn time reached; waiting for active-list detection.", targetName)
            nextCountdownLogAt = now + 60
            lastOverdueLogAt = now
        end
    else
        mode = "bootstrap"
        deadline = now + timeoutSec
        nextCountdownLogAt = now + WAIT_COUNTDOWN_INTERVAL
        logf("Waiting at %s spawn for up to %.1f minutes.", targetName, timeoutSec / 60.0)
    end

    while os.clock() < deadline do
        if INSTANCE_TIME_MODE.leaveIfNeeded("waiting at " .. tostring(targetName) .. " spawn") then
            return nil
        end

        local active = getBestActivePotFate(mode == "predicted" and nil or targetName)
        if active ~= nil then
            if mode == "predicted" and active.name ~= targetName then
                logf("Detected active pot FATE '%s' while waiting for predicted '%s'; following the active FATE instead.", active.name, targetName)
            elseif mode == "predicted" then
                logf("Detected predicted pot FATE '%s'.", active.name)
            else
                logf("Detected active pot FATE '%s' while waiting at spawn.", active.name)
            end
            return active
        end

        if isDead() and not handleDeathState() then
            return nil
        end

        now = os.clock()
        if mode == "predicted" and predictedSpawnAt ~= nil then
            local secondsUntilSpawn = predictedSpawnAt - now
            if secondsUntilSpawn <= 0 and not predictionReachedLogged then
                predictionReachedLogged = true
                lastOverdueLogAt = now
                nextCountdownLogAt = now + 60
                logf("%s predicted spawn time reached; waiting for active-list detection.", targetName)
            elseif secondsUntilSpawn > 0 and now >= nextCountdownLogAt then
                logf("%s predicted to spawn in %s.", targetName, TREASURE_RUNTIME.formatSpawnCountdown(secondsUntilSpawn))
                nextCountdownLogAt = now + TREASURE_RUNTIME.getSpawnCountdownDelay(secondsUntilSpawn)
            elseif predictionReachedLogged and (now - lastOverdueLogAt) >= 60 then
                local overdueSeconds = math.max(0, now - predictedSpawnAt)
                logf("%s is %s past its predicted spawn time; still waiting for active-list detection.", targetName, TREASURE_RUNTIME.formatSpawnCountdown(overdueSeconds))
                lastOverdueLogAt = now
            end
        elseif now >= nextCountdownLogAt then
            local remainingMinutes = math.max(0, math.ceil((deadline - now) / 60.0))
            logf("Waiting at %s spawn. %d minute(s) remaining.", targetName, remainingMinutes)
            nextCountdownLogAt = now + WAIT_COUNTDOWN_INTERVAL
        end

        sleep(WAIT_POLL)
    end

    if mode == "predicted" and predictedSpawnAt ~= nil then
        logf("%s was not detected within %.1f minute(s) after its predicted spawn. Returning to cycle recovery.", targetName, graceSeconds / 60.0)
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
    local joinedFate = false
    LOGGING.verbosef("Monitoring pot FATE '%s' (id=%d).", fate.name, fate.id)
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
        if snapshot.inFate and not joinedFate then
            joinedFate = true
            logf("Joined pot FATE '%s' at %.1f%% progress.", fate.name, snapshot.progress or 0)
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
            LOGGING.verbosef("Still monitoring '%s'. inFate=%s inCombat=%s progress=%.1f buff=%s.", fate.name, tostring(snapshot.inFate), tostring(isInCombat()), snapshot.progress or 0, tostring(hasTreasureBuff()))
            lastIdleLogAt = os.clock()
        end
        sleep(POLL_INTERVAL)
    end
    if autorotationActive then
        logf("Final combat clear for pot FATE %s. Clearing autorotation.", fate.name)
        clearBossModPreset()
    end
    return true, nil
end

NON_POT_FATE_MODE.scanActiveFates = function()
    local result = {}
    local activeFates = safeCall(function()
        return Fates.GetActiveFates()
    end)
    if activeFates == nil then
        if (os.clock() - NON_POT_FATE_MODE.lastScanLogAt) >= IDLE_LOG_INTERVAL then
            LOGGING.verbose("scanNonPotFates: Fates.GetActiveFates() returned nil; cannot select an active FATE yet.")
            NON_POT_FATE_MODE.lastScanLogAt = os.clock()
        end
        return result
    end

    local count = tonumber(safeCall(function() return activeFates.Count end)) or 0
    local shouldLog = (os.clock() - NON_POT_FATE_MODE.lastScanLogAt) >= IDLE_LOG_INTERVAL
    local skippedEndedOrFailed = 0

    if shouldLog then
        LOGGING.verbosef("scanNonPotFates: %d active entries from Fates.GetActiveFates().", count)
    end

    for i = 0, math.max(0, count - 1) do
        local fate = safeCall(function() return activeFates[i] end)
        if fate ~= nil then
            local name = tostring(safeCall(function() return fate.Name end) or "")
            local id = tonumber(safeCall(function() return fate.Id end)) or 0
            local state = tonumber(safeCall(function() return fate.State end)) or 0
            local progress = tonumber(safeCall(function() return fate.Progress end)) or 0
            local radius = tonumber(safeCall(function() return fate.Radius end)) or 0
            local distance = tonumber(safeCall(function() return fate.DistanceToPlayer end)) or 0
            local location = safeCall(function() return fate.Location end)
            local endedOrFailed = state == NON_POT_FATE_MODE.stateEnded or state == NON_POT_FATE_MODE.stateFailed

            if shouldLog then
                LOGGING.verbosef("scanNonPotFates: [%d] '%s' id=%d state=%d progress=%.1f radius=%.1f dist=%.1f endedOrFailed=%s loc=%s.",
                    i, name ~= "" and name or "?", id, state, progress, radius, distance,
                    tostring(endedOrFailed), formatVector3(location))
            end

            if endedOrFailed then
                skippedEndedOrFailed = skippedEndedOrFailed + 1
            else
                table.insert(result, {
                    id = id,
                    name = name,
                    location = location,
                    radius = radius,
                    progress = progress,
                    distance = distance,
                    state = state,
                })
            end
        end
    end

    if shouldLog then
        LOGGING.verbosef("scanNonPotFates: %d usable active FATE(s) from %d active FATE(s); skippedEndedOrFailed=%d.",
            #result, count, skippedEndedOrFailed)
        if #result > 0 then
            local preview = {}
            for _, fate in ipairs(result) do
                table.insert(preview, fate)
            end
            table.sort(preview, function(a, b)
                if a.progress ~= b.progress then
                    return a.progress < b.progress
                end
                return a.distance < b.distance
            end)
            local previewCount = math.min(3, #preview)
            for index = 1, previewCount do
                local fate = preview[index]
                LOGGING.verbosef("scanNonPotFates candidate %d: '%s' id=%d state=%d progress=%.1f dist=%.1f radius=%.1f loc=%s.",
                    index, fate.name, fate.id, fate.state or 0, fate.progress or 0, fate.distance or -1, fate.radius or 0, formatVector3(fate.location))
            end
        end
        NON_POT_FATE_MODE.lastScanLogAt = os.clock()
    end

    return result
end

NON_POT_FATE_MODE.selectFate = function(fates)
    if fates == nil or #fates == 0 then
        return nil
    end
    table.sort(fates, function(a, b)
        if a.progress ~= b.progress then
            return a.progress < b.progress
        end
        return a.distance < b.distance
    end)
    local best = fates[1]
    LOGGING.verbosef("Selected non-pot FATE '%s' (id=%d) progress=%.1f distance=%.1f radius=%.1f.", best.name, best.id, best.progress or 0, best.distance or -1, best.radius or 0)
    return best
end

NON_POT_FATE_MODE.monitorUntilDoneOrDeadline = function(fate, departAt)
    local autorotationActive = false
    local joinedFate = false
    LOGGING.verbosef("Monitoring non-pot FATE '%s' (id=%d) until completion or pot departure window.", fate.name, fate.id)
    while true do
        if INSTANCE_TIME_MODE.leaveIfNeeded("monitoring non-pot FATE " .. tostring(fate.name)) then
            if autorotationActive then
                clearBossModPreset()
            end
            return false, "instance_exit"
        end
        if getBestActivePotFate(nil) ~= nil then
            if autorotationActive then
                clearBossModPreset()
            end
            return false, "pot_active"
        end
        if os.clock() >= departAt then
            if autorotationActive then
                clearBossModPreset()
            end
            return false, "deadline"
        end
        if not isFateActive(fate.id) then
            break
        end

        local snapshot = getFateSnapshot(fate.id)
        if snapshot == nil then
            break
        end

        if snapshot.inFate and not joinedFate then
            joinedFate = true
            logf("Joined non-pot FATE '%s' at %.1f%% progress.", fate.name, snapshot.progress or 0)
        end
        if isInCombat() or snapshot.inFate then
            if not autorotationActive then
                autorotationActive = applyBossModForFate()
            end
        elseif autorotationActive then
            clearBossModPreset()
            autorotationActive = false
        end

        if isDead() and not handleDeathState() then
            if autorotationActive then
                clearBossModPreset()
            end
            return false, "failed_death_recovery"
        end

        if (os.clock() - lastIdleLogAt) >= IDLE_LOG_INTERVAL then
            LOGGING.verbosef("Non-pot FATE '%s' still active. inFate=%s inCombat=%s progress=%.1f timeUntilPotMove=%.1fs.", snapshot.name, tostring(snapshot.inFate), tostring(isInCombat()), snapshot.progress or 0, math.max(0, departAt - os.clock()))
            potCycleRuntime.logInterspawnPredictionIfDue("monitoring_non_pot_fate", departAt)
            lastIdleLogAt = os.clock()
        end
        sleep(POLL_INTERVAL)
    end

    if autorotationActive then
        clearBossModPreset()
    end
    return true, nil
end

NON_POT_FATE_MODE.attemptOneBeforeDeadline = function(departAt)
    if not NON_POT_FATE_MODE.enabled then
        NON_POT_FATE_MODE.holdingForDeparture = false
        return "disabled"
    end
    if INSTANCE_TIME_MODE.leaveIfNeeded("before selecting a non-pot FATE") then
        return "instance_exit"
    end

    local remaining = departAt - os.clock()
    if remaining <= NON_POT_FATE_MODE.interspawnMinimumStartWindowSeconds then
        if not NON_POT_FATE_MODE.holdingForDeparture then
            if isNearBaseCamp(120.0) then
                logf("Non-pot FATE window closed; holding at base until departure in %.1f minute(s).", math.max(0, remaining) / 60.0)
            else
                logf("Non-pot FATE window closed; waiting at the current location until departure in %.1f minute(s) because BaseCamp recovery has not completed.", math.max(0, remaining) / 60.0)
            end
            NON_POT_FATE_MODE.holdingForDeparture = true
        end
        return "insufficient_time"
    end

    if NON_POT_FATE_MODE.holdingForDeparture then
        NON_POT_FATE_MODE.holdingForDeparture = false
    end
    if getBestActivePotFate(nil) ~= nil then
        return "pot_active"
    end

    local target = NON_POT_FATE_MODE.selectFate(NON_POT_FATE_MODE.scanActiveFates())
    if target == nil then
        if (os.clock() - NON_POT_FATE_MODE.lastWaitResultLogAt) >= IDLE_LOG_INTERVAL then
            LOGGING.verbose("Non-pot mode active, but no usable active FATE was found; continuing base scan.")
            NON_POT_FATE_MODE.lastWaitResultLogAt = os.clock()
        end
        return "none"
    end

    NON_POT_FATE_MODE.holdingForDeparture = false
    local nearestAethernet = getNearestConfiguredAethernet(target.location)
    local preferredAethernetName = nearestAethernet and nearestAethernet.name or nil
    local overrideAethernetName = NON_POT_FATE_MODE.aethernetPreference[tonumber(target.id) or -1]
    if overrideAethernetName ~= nil and getAethernetByName(overrideAethernetName) ~= nil then
        LOGGING.verbosef("Interspawn FATE '%s' id=%d: overriding nearest aethernet (%s) with preferred (%s).", target.name, target.id, preferredAethernetName or "nil", overrideAethernetName)
        preferredAethernetName = overrideAethernetName
    end
    LOGGING.verbosef("Interspawn active FATE selected: '%s' id=%d progress=%.1f distance=%.1f preferredAethernet=%s.", target.name, target.id, target.progress or 0, target.distance or -1, preferredAethernetName or "nil")
    logf("Starting non-pot FATE '%s'.", target.name)

    local travelOk, travelErr = travelToPoint(target.location, preferredAethernetName, math.min(math.max(10, target.radius), 15), true)
    if not travelOk then
        logf("Interspawn active FATE travel failed for '%s': %s.", target.name, tostring(travelErr))
        potCycleRuntime.logInterspawnPredictionIfDue("non_pot_travel_failed", departAt)
        return "travel_failed"
    end

    local monitorOk, monitorErr = NON_POT_FATE_MODE.monitorUntilDoneOrDeadline(target, departAt)
    if not monitorOk then
        if monitorErr == "pot_active" or monitorErr == "deadline" or monitorErr == "instance_exit" then
            return monitorErr
        end
        logf("Interspawn active FATE monitor ended for '%s': %s.", target.name, tostring(monitorErr))
        return "monitor_failed"
    end

    logf("Non-pot FATE '%s' completed.", target.name)
    potCycleRuntime.logInterspawnPredictionIfDue("after_non_pot_fate", departAt)
    if getBestActivePotFate(nil) ~= nil or os.clock() >= departAt then
        return "pot_active"
    end
    if INSTANCE_TIME_MODE.leaveIfNeeded("after completed non-pot FATE") then
        return "instance_exit"
    end

    local returnOk, returnErr = returnToBaseAndWait()
    if not returnOk then
        logf("Return to base failed after interspawn active FATE '%s': %s.", target.name, tostring(returnErr))
        potCycleRuntime.logInterspawnPredictionIfDue("non_pot_return_failed", departAt)
        return "return_failed"
    end
    potCycleRuntime.logInterspawnPredictionIfDue("returned_to_base", departAt)
    return "completed"
end

local function getPredictedNextFateName()
    if potCycleRuntime.lastSpawnFateName == nil then
        return nil
    end
    return getOppositePotName(potCycleRuntime.lastSpawnFateName)
end

potCycleRuntime.resetInterspawnPredictionLog = function()
    potCycleRuntime.lastInterspawnPredictionBucket = nil
    potCycleRuntime.interspawnPredictionOverdueLogged = false
end

potCycleRuntime.logInterspawnPredictionIfDue = function(context, departAt)
    if potCycleRuntime.lastSpawnAt == nil
        or potCycleRuntime.lastSpawnFateName == nil
        or potCycleRuntime.activeFateName ~= nil
        or potCycleRuntime.waitingAtPredictedSpawn
        or potCycleRuntime.bootstrapWaitActive
        or INSTANCE_TIME_MODE.leavePending
        or INSTANCE_TIME_MODE.exitRequested
        or TREASURE_RUNTIME.trackingActive
    then
        return false
    end

    local predictedName = getPredictedNextFateName()
    local now = os.clock()
    local predictedSpawnAt = potCycleRuntime.lastSpawnAt + POT_CYCLE_SECONDS
    local secondsUntilSpawn = predictedSpawnAt - now
    if secondsUntilSpawn <= 0 then
        if not potCycleRuntime.interspawnPredictionOverdueLogged then
            if predictedName ~= nil then
                logf("Predicted %s spawn time has passed; switching to prediction recovery.", predictedName)
            else
                log("Predicted pot FATE spawn time has passed; switching to prediction recovery.")
            end
            potCycleRuntime.interspawnPredictionOverdueLogged = true
        end
        potCycleRuntime.lastInterspawnPredictionBucket = nil
        return false
    end

    local resolvedDepartAt = tonumber(departAt)
        or (predictedSpawnAt - (SPAWN_LEAD_MINUTES * 60))
    local secondsUntilDeparture = resolvedDepartAt - now
    if secondsUntilDeparture <= NON_POT_FATE_MODE.interspawnMinimumStartWindowSeconds then
        return false
    end

    local bucketMinutes
    if secondsUntilSpawn > 20 * 60 then
        bucketMinutes = math.ceil(secondsUntilSpawn / (5 * 60)) * 5
    elseif secondsUntilSpawn > 10 * 60 then
        bucketMinutes = 11 + (math.ceil((secondsUntilSpawn - (11 * 60)) / (3 * 60)) * 3)
    else
        bucketMinutes = math.ceil(secondsUntilSpawn / (2 * 60)) * 2
    end

    local bucketKey = string.format("%s:%d", tostring(predictedName or "pot"), bucketMinutes)
    if bucketKey == potCycleRuntime.lastInterspawnPredictionBucket then
        return false
    end

    potCycleRuntime.lastInterspawnPredictionBucket = bucketKey
    potCycleRuntime.interspawnPredictionOverdueLogged = false
    if predictedName ~= nil then
        logf("Next predicted %s spawn in %s.", predictedName, TREASURE_RUNTIME.formatSpawnCountdown(secondsUntilSpawn))
    else
        logf("Next predicted pot FATE spawn in %s.", TREASURE_RUNTIME.formatSpawnCountdown(secondsUntilSpawn))
    end
    return true
end

local function waitForPredictedWindow()
    NON_POT_FATE_MODE.holdingForDeparture = false
    potCycleRuntime.resetInterspawnPredictionLog()
    local nextName = getPredictedNextFateName()
    if nextName == nil or potCycleRuntime.lastSpawnAt == nil then
        return true
    end
    local departAt = potCycleRuntime.lastSpawnAt + POT_CYCLE_SECONDS - (SPAWN_LEAD_MINUTES * 60)
    INSTANCE_TIME_MODE.lastDecisionLogAt = os.clock() - INSTANCE_TIME_MODE.decisionLogInterval
    if NON_POT_FATE_MODE.enabled then
        logf("Non-pot mode enabled for interspawn window. Will run side FATEs until %.1f minute(s) before predicted %s.", SPAWN_LEAD_MINUTES, nextName)
    end
    while os.clock() < departAt do
        if INSTANCE_TIME_MODE.leaveIfNeeded("waiting for predicted pot window") then
            NON_POT_FATE_MODE.holdingForDeparture = false
            return false
        end
        local restartedWaitLoop = false
        local active = getBestActivePotFate(nil)
        if active ~= nil then
            NON_POT_FATE_MODE.holdingForDeparture = false
            return true
        end
        if isDead() and not handleDeathState() then
            NON_POT_FATE_MODE.holdingForDeparture = false
            return false
        end
        potCycleRuntime.logInterspawnPredictionIfDue("predicted_window", departAt)
        if NON_POT_FATE_MODE.enabled then
            local sideFateResult = NON_POT_FATE_MODE.attemptOneBeforeDeadline(departAt)
            if sideFateResult == "pot_active" then
                NON_POT_FATE_MODE.holdingForDeparture = false
                return true
            elseif sideFateResult == "instance_exit" then
                NON_POT_FATE_MODE.holdingForDeparture = false
                return false
            elseif sideFateResult == "deadline" then
                break
            elseif sideFateResult == "completed" then
                restartedWaitLoop = true
            end
        end
        if restartedWaitLoop then
            sleep(0.1)
        else
        if ENABLE_KEEP_ALIVE and (lastKeepAliveAt <= 0 or (os.clock() - lastKeepAliveAt) >= KEEP_ALIVE_INTERVAL) then
            performKeepAliveMove()
        end
        local remaining = departAt - os.clock()
        if remaining <= NON_POT_FATE_MODE.interspawnMinimumStartWindowSeconds
            and (os.clock() - lastIdleLogAt) >= WAIT_COUNTDOWN_INTERVAL
        then
            if isNearBaseCamp(120.0) then
                logf("Waiting at base until it is time to leave %.1f minute(s) early for predicted %s.", remaining / 60.0, nextName)
            else
                logf("Waiting for the predicted departure window from the current location; %.1f minute(s) remain before leaving for %s.", remaining / 60.0, nextName)
            end
            lastIdleLogAt = os.clock()
        end
        sleep(1.0)
        end
    end
    NON_POT_FATE_MODE.holdingForDeparture = false
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

TREASURE_RUNTIME.isValidCofferTargetMetadata = function(targetMetadata, expectedPosition)
    if targetMetadata == nil or targetMetadata.position == nil or expectedPosition == nil then
        return false, "missing_target_position"
    end
    local targetDistance = distanceFlat(targetMetadata.position, expectedPosition)
    if targetDistance > 8.0 then
        return false, string.format("target_position_mismatch:%.1f", targetDistance)
    end

    if COFFER_DATA_ID_LOOKUP[tonumber(targetMetadata.dataId)] == true then
        return true, nil
    end

    local _, localizedNameLookup = getResolvedCofferNames()
    local nameMatches = localizedNameLookup[string.lower(tostring(targetMetadata.name or ""))] == true
    local kindText = string.lower(tostring(targetMetadata.objectKind or ""))
    if nameMatches and kindText:find("eventobj", 1, true) ~= nil then
        return true, nil
    end

    return false, "target_not_confirmed_as_coffer"
end

local function resolveCaptureContext(runtimeContext, cofferPosition)
    local captureContext = {
        fateName = runtimeContext and runtimeContext.fateName or "?",
        group = runtimeContext and runtimeContext.group or "?",
        candidateLabel = runtimeContext and runtimeContext.candidateLabel or "?",
        dangerous = runtimeContext and runtimeContext.dangerous == true,
        note = runtimeContext and runtimeContext.note or nil,
        traversalCandidateLabel = runtimeContext and runtimeContext.candidateLabel or "?",
        attributionNote = nil,
    }

    if runtimeContext == nil or cofferPosition == nil then
        return captureContext
    end

    local groupCandidates = COFFER_GROUPS[captureContext.fateName]
    groupCandidates = groupCandidates and groupCandidates[captureContext.group] or nil
    if groupCandidates == nil or #groupCandidates == 0 then
        captureContext.candidateLabel = "UNMAPPED"
        captureContext.attributionNote = string.format(
            "Capture could not be attributed because no candidate group exists for %s -> %s; traversal candidate was %s.",
            tostring(captureContext.fateName),
            tostring(captureContext.group),
            tostring(captureContext.traversalCandidateLabel)
        )
        return captureContext
    end

    local nearestCandidate = nil
    local nearestDistance = math.huge
    local traversalDistance = nil
    for _, candidate in ipairs(groupCandidates) do
        local candidateDistance = distance3d(cofferPosition, candidate.position)
        if tostring(candidate.label) == tostring(captureContext.traversalCandidateLabel) then
            traversalDistance = candidateDistance
        end
        if candidateDistance < nearestDistance then
            nearestDistance = candidateDistance
            nearestCandidate = candidate
        end
    end

    -- A runtime capture is attributed from the actual coffer position, not from
    -- the candidate that started refinement. Dead reckoning may cross into a
    -- different mapped candidate. Thirty yalms allows for rough seed positions
    -- without assigning an unrelated candidate when the location is truly new.
    if nearestCandidate ~= nil and nearestDistance <= 30.0 then
        captureContext.candidateLabel = nearestCandidate.label
        captureContext.dangerous = NINJA_MODE.isDangerousCandidate(nearestCandidate)
        captureContext.note = nearestCandidate.note

        if tostring(nearestCandidate.label) ~= tostring(captureContext.traversalCandidateLabel) then
            captureContext.attributionNote = string.format(
                "Capture attribution corrected from traversal candidate %s to nearest mapped candidate %s (nearest %.1fy%s).",
                tostring(captureContext.traversalCandidateLabel),
                tostring(nearestCandidate.label),
                nearestDistance,
                traversalDistance and string.format(", traversal candidate %.1fy", traversalDistance) or ""
            )
        end
        return captureContext
    end

    captureContext.candidateLabel = "UNMAPPED"
    captureContext.attributionNote = string.format(
        "No mapped candidate was within 30.0y of the actual coffer position; nearest was %s at %.1fy. Traversal candidate was %s%s.",
        tostring(nearestCandidate and nearestCandidate.label or "?"),
        nearestDistance,
        tostring(captureContext.traversalCandidateLabel),
        traversalDistance and string.format(" at %.1fy", traversalDistance) or ""
    )
    return captureContext
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

    local captureContext = resolveCaptureContext(TREASURE_RUNTIME.currentContext, match.position)
    local captureKey = buildCofferCaptureKey(captureContext, match)
    if TREASURE_RUNTIME.lastLoggedCaptureKey == captureKey then
        return true
    end

    if captureContext.attributionNote ~= nil then
        log(captureContext.attributionNote)
    end

    local playerPosition = getPlayerPosition()
    local captureIndex = getNextCaptureIndex(filePath)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local lines = {
        "",
        string.format("## Capture %d", captureIndex),
        "",
        string.format("- Timestamp: `%s`", timestamp),
        "- Source: `Occult Crescent - Pots Treasure Farmer.lua runtime capture`",
        string.format("- TerritoryType: `%s`", tostring(getTerritoryType() or "?")),
        string.format("- FATE: `%s`", tostring(captureContext.fateName or "?")),
        string.format("- Group: `%s`", tostring(captureContext.group or "?")),
        string.format("- Candidate: `%s`", tostring(captureContext.candidateLabel or "?")),
        string.format("- Coffer type: `%s`", tostring(match.name or "?")),
        string.format("- Detection source: `%s`", tostring(match.source or "unknown")),
        string.format("- Dangerous candidate: `%s`", tostring(captureContext.dangerous == true)),
        string.format("- Player position: `%s`", formatPositionFields(playerPosition)),
        string.format("- Coffer position: `%s`", formatPositionFields(match.position)),
        string.format("- Distance from player: `%.3f`", tonumber(match.distance) or distance3d(playerPosition, match.position)),
        string.format("- DataId: `%s`", tostring(match.dataId or "?")),
        string.format("- GameObjectId: `%s`", tostring(match.gameObjectId or "?")),
        string.format("- ObjectKind: `%s`", tostring(match.objectKind or "?")),
    }
    if captureContext.note ~= nil then
        table.insert(lines, string.format("- Candidate note: `%s`", tostring(captureContext.note)))
    end
    if captureContext.attributionNote ~= nil then
        table.insert(lines, string.format("- Note: `%s`", tostring(captureContext.attributionNote)))
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
    logf("Appended coffer capture to %s for %s %s %s (traversal candidate %s).", tostring(filePath), tostring(captureContext.fateName or "?"), tostring(captureContext.group or "?"), tostring(captureContext.candidateLabel or "?"), tostring(captureContext.traversalCandidateLabel or "?"))
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

                if COFFER_DATA_ID_LOOKUP[dataId] == true or nameLookup[lowerName] == true then
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
    -- Stable EObj DataIds are authoritative and work in every client language.
    -- Localized names are only a fallback for wrappers that are not yet visible
    -- through the indexed object scan.
    local byDataId = findNearbyCofferByObjectScan(radius, false, nil)
    if byDataId ~= nil then
        return byDataId
    end
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

COFFER_INTERACTION = COFFER_INTERACTION or {}
COFFER_INTERACTION.maxDurationSeconds = tonumber(COFFER_INTERACTION.maxDurationSeconds) or 45.0
COFFER_INTERACTION.maxInteractionAttempts = tonumber(COFFER_INTERACTION.maxInteractionAttempts) or 10

-- Inventory-count confirmation for coffer interaction.
-- These helpers are intentionally global because the main chunk is already close
-- to NLua's 200-local limit. Only the four normal player inventory bags are
-- included; armory, key-item, currency, and special containers are excluded.
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
                return snapshot, false, string.format("slot_unavailable:%s:%d", tostring(containerName), slot)
            end

            snapshot.slotsRead = snapshot.slotsRead + 1
            local itemId = tonumber(safeCall(function() return item.ItemId end))
            local isEmpty = safeCall(function() return item.IsEmpty end)
            if isEmpty == nil then
                isEmpty = itemId == nil or itemId == 0
            end

            if not isEmpty then
                local baseItemId = tonumber(safeCall(function() return item.BaseItemId end)) or itemId
                local quantity = tonumber(safeCall(function() return item.Count end))
                local isHighQuality = safeCall(function() return item.IsHighQuality end) == true
                if itemId == nil or itemId == 0 or baseItemId == nil or quantity == nil or quantity < 0 then
                    return snapshot, false, string.format("slot_data_invalid:%s:%d", tostring(containerName), slot)
                end

                local key = tostring(baseItemId) .. ":" .. (isHighQuality and "hq" or "normal")
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
            return (a.isHighQuality and 1 or 0) < (b.isHighQuality and 1 or 0)
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

local function interactWithEntity(entityOrMatch)
    if entityOrMatch == nil then
        return false
    end

    local match = entityOrMatch.entity and entityOrMatch or createCofferMatch(entityOrMatch, "direct_wrapper", nil)
    local currentCandidate = TREASURE_RUNTIME.currentContext and TREASURE_RUNTIME.currentContext.currentCandidate or nil
    local captureWritten = false
    local captureDeferredLogged = false
    local acquisitionPass = 0
    local interactionAttempt = 0
    local interactionIssued = false
    local consecutiveMissingScans = 0
    local interactionStartedAt = os.clock()
    local interactionDeadline = interactionStartedAt + COFFER_INTERACTION.maxDurationSeconds
    local targetMetadataRejectedLogged = false
    local identity = {
        gameObjectId = match.gameObjectId or safeCall(function() return match.entity.GameObjectId end),
        dataId = tonumber(match.dataId or safeCall(function() return match.entity.DataId end)),
        position = match.position or safeCall(function() return match.entity.Position end),
        name = tostring(match.name or safeCall(function() return match.entity.Name end) or ""),
    }

    local function getFreeInventorySlots()
        if not (Inventory and Inventory.GetFreeInventorySlots) then
            return nil
        end
        return tonumber(safeCall(function()
            return Inventory.GetFreeInventorySlots()
        end))
    end

    local function updateIdentity(currentMatch)
        if currentMatch == nil then
            return
        end
        if identity.gameObjectId == nil then
            identity.gameObjectId = currentMatch.gameObjectId or safeCall(function() return currentMatch.entity.GameObjectId end)
        end
        if identity.dataId == nil then
            identity.dataId = tonumber(currentMatch.dataId or safeCall(function() return currentMatch.entity.DataId end))
        end
        if identity.position == nil then
            identity.position = currentMatch.position or safeCall(function() return currentMatch.entity.Position end)
        end
        if identity.name == "" or identity.name == "?" then
            identity.name = tostring(currentMatch.name or safeCall(function() return currentMatch.entity.Name end) or "")
        end
    end

    local function refreshSameCoffer(currentMatch, radius)
        updateIdentity(currentMatch)
        local searchRadius = tonumber(radius) or 28
        local playerPosition = getPlayerPosition()
        local _, localizedNameLookup = getResolvedCofferNames()
        local exactMatch = nil
        local dataIdMatch = nil
        local nearbyVariantMatch = nil
        local bestDataDistance = math.huge
        local bestVariantDistance = math.huge
        local objectCount = tonumber(safeCall(function() return Svc.Objects.Length end)) or 0

        for index = 0, math.max(0, objectCount - 1) do
            local object = safeCall(function() return Svc.Objects[index] end)
            if object ~= nil then
                local position = safeCall(function() return object.Position end)
                local playerDistance = distance3d(playerPosition, position)
                if position ~= nil and playerDistance <= searchRadius then
                    local dataId = tonumber(safeCall(function() return object.DataId end))
                    local gameObjectId = safeCall(function() return object.GameObjectId end)
                    local name = getObjectName(object)
                    local isCofferVariant = COFFER_DATA_ID_LOOKUP[dataId] == true or localizedNameLookup[string.lower(name or "")] == true
                    if isCofferVariant then
                        local entity = safeCall(function() return Entity[index] end)
                        if entity ~= nil then
                            local candidateMatch = createCofferMatch(entity, "identity_scan", {
                                name = name,
                                position = position,
                                distance = playerDistance,
                                dataId = dataId,
                                gameObjectId = gameObjectId,
                                objectKind = safeCall(function() return object.ObjectKind end),
                                objectIndex = index,
                            })

                            if identity.gameObjectId ~= nil and gameObjectId == identity.gameObjectId then
                                exactMatch = candidateMatch
                                break
                            end

                            local identityDistance = identity.position and distanceFlat(identity.position, position) or playerDistance
                            if identity.dataId ~= nil and dataId == identity.dataId and identityDistance <= 12.0 and identityDistance < bestDataDistance then
                                dataIdMatch = candidateMatch
                                bestDataDistance = identityDistance
                            elseif identityDistance <= 8.0 and identityDistance < bestVariantDistance then
                                nearbyVariantMatch = candidateMatch
                                bestVariantDistance = identityDistance
                            end
                        end
                    end
                end
            end
        end

        if exactMatch ~= nil then
            return exactMatch
        end
        if dataIdMatch ~= nil then
            return dataIdMatch
        end
        if nearbyVariantMatch ~= nil then
            return nearbyVariantMatch
        end

        local namedMatch = findNearbyCofferByName(searchRadius, true)
        if namedMatch ~= nil then
            local identityDistance = identity.position and distanceFlat(identity.position, namedMatch.position) or 0
            if identity.position == nil or identityDistance <= 8.0 then
                return namedMatch
            end
        end
        return nil
    end

    updateIdentity(match)
    logCofferMatch("Found coffer entity", match)

    while os.clock() < interactionDeadline and interactionAttempt < COFFER_INTERACTION.maxInteractionAttempts do
        local refreshed = refreshSameCoffer(match, 28)
        if refreshed == nil and acquisitionPass == 0 then
            refreshed = match
        end

        if refreshed == nil then
            consecutiveMissingScans = consecutiveMissingScans + 1
            if consecutiveMissingScans >= 3 then
                if interactionIssued then
                    logf(
                        "Coffer GameObjectId %s is absent for %d consecutive scan(s) after a successful direct interaction call; coffer open confirmed.",
                        tostring(identity.gameObjectId or "?"),
                        consecutiveMissingScans
                    )
                    TREASURE_RUNTIME.lastCofferOpenedAt = os.clock()
                    return true
                end
                logf(
                    "Coffer acquisition lost the entity for %d consecutive scan(s) before any direct interaction; continuing reacquisition without confirming open.",
                    consecutiveMissingScans
                )
                consecutiveMissingScans = 0
            end
            sleep(0.4)
        else
            match = refreshed
            updateIdentity(match)
            consecutiveMissingScans = 0
            acquisitionPass = acquisitionPass + 1

            local entity = match.entity
            local name = tostring(match.name or safeCall(function() return entity.Name end) or "?")
            local position = match.position or safeCall(function() return entity.Position end)
            local isTargetable = safeCall(function() return entity.IsTargetable end)

            if position == nil then
                logf("Coffer acquisition pass %d could not resolve the entity position; rescanning.", acquisitionPass)
                sleep(0.4)
            elseif isTargetable == false then
                LOGGING.verbosef("Coffer acquisition pass %d found %s but it is not targetable yet; rescanning.", acquisitionPass, name)
                sleep(0.4)
            else
                local moved = false
                if NINJA_MODE.isDangerousCandidate(currentCandidate) and TREASURE_RUNTIME.cofferRevealed then
                    NINJA_MODE.hideFailed = false
                    NINJA_MODE.abortReason = nil
                    if not TREASURE_RUNTIME.revealedCofferBypassLogged then
                        logf("Revealed coffer found for dangerous candidate %s; bypassing Hide cooldown and opening it immediately.", tostring(currentCandidate and currentCandidate.label or "?"))
                        TREASURE_RUNTIME.revealedCofferBypassLogged = true
                    end
                    moved = moveToPosition(position, 3.0, 15.0)
                elseif NINJA_MODE.isDangerousCandidate(currentCandidate) and not isInCombat() then
                    if not NINJA_MODE.ensureHiddenOrAbort(currentCandidate) then
                        if NINJA_MODE.abortReason == "gearset_failed" then
                            logf("Ninja gearset recovery failed while approaching dangerous coffer for candidate %s; aborting this candidate.", tostring(currentCandidate and currentCandidate.label or "?"))
                        else
                            logf("Hide failed while approaching dangerous coffer for candidate %s; aborting interaction to avoid unhidden aggro risk.", tostring(currentCandidate and currentCandidate.label or "?"))
                        end
                        return false
                    end
                    moved = moveToCandidatePositionWithRetryInternal(position, 3.0, "Visible coffer", false)
                else
                    moved = moveToPosition(position, 3.0, 15.0)
                end

                if not moved then
                    logf("Coffer acquisition pass %d failed to reach within 3.0y of %s; rescanning and repathing.", acquisitionPass, formatVector3(position))
                    stopPathing()
                    sleep(0.4)
                elseif not targetEntity(entity) then
                    logf("Coffer acquisition pass %d failed to target %s; rescanning.", acquisitionPass, name)
                    sleep(0.4)
                else
                    sleep(0.15)
                    local targetMetadata = getCurrentTargetMetadata()
                    local targetMetadataValid, targetMetadataReason = TREASURE_RUNTIME.isValidCofferTargetMetadata(targetMetadata, position)
                    if targetMetadataValid then
                        match.dataId = match.dataId or targetMetadata.dataId
                        match.gameObjectId = match.gameObjectId or targetMetadata.gameObjectId
                        match.objectKind = match.objectKind or targetMetadata.objectKind
                        match.position = match.position or targetMetadata.position
                        if (match.name == nil or match.name == "?" or match.name == "") and targetMetadata.name ~= nil and targetMetadata.name ~= "" then
                            match.name = targetMetadata.name
                        end
                        if match.distance == nil and match.position ~= nil then
                            match.distance = distance3d(getPlayerPosition(), match.position)
                        end
                        updateIdentity(match)
                    elseif not targetMetadataRejectedLogged then
                        logf(
                            "Coffer acquisition pass %d ignored current-target metadata because it was not validated as the discovered coffer (%s).",
                            acquisitionPass,
                            tostring(targetMetadataReason or "unknown")
                        )
                        targetMetadataRejectedLogged = true
                    end

                    if not captureWritten then
                        if identity.dataId ~= nil and identity.gameObjectId ~= nil then
                            captureWritten = appendRuntimeCofferCapture(match, nil) == true
                        elseif not captureDeferredLogged then
                            logf(
                                "Coffer capture deferred on acquisition pass %d because stable DataId/GameObjectId metadata is not available yet.",
                                acquisitionPass
                            )
                            captureDeferredLogged = true
                        end
                    end

                    interactionAttempt = interactionAttempt + 1
                    name = tostring(match.name or name)
                    position = match.position or position
                    local freeSlotsBefore = getFreeInventorySlots()
                    local inventoryBefore, inventoryBeforeValid, inventoryBeforeError = COFFER_INVENTORY.snapshot()
                    local inventoryFallbackLogged = false
                    if not inventoryBeforeValid then
                        logf(
                            "Inventory snapshot incomplete before coffer interaction attempt %d (%s); using exact-coffer disappearance confirmation.",
                            interactionAttempt,
                            tostring(inventoryBeforeError or "unknown_error")
                        )
                        inventoryFallbackLogged = true
                    end
                    logf(
                        "Coffer interaction attempt %d: direct entity interaction with %s at %s after repathing to 3.0y; freeSlotsBefore=%s trackedInventorySlots=%s GameObjectId=%s DataId=%s.",
                        interactionAttempt,
                        name,
                        formatVector3(position),
                        tostring(freeSlotsBefore or "?"),
                        tostring(inventoryBeforeValid and inventoryBefore.nonEmptySlots or "?"),
                        tostring(identity.gameObjectId or "?"),
                        tostring(identity.dataId or "?")
                    )

                    local interactOk, interactErr = pcall(function()
                        entity:Interact()
                    end)
                    if not interactOk then
                        logf("Coffer interaction attempt %d direct entity interaction failed: %s. Rescanning and retrying.", interactionAttempt, tostring(interactErr))
                        sleep(0.4)
                    else
                        interactionIssued = true
                        local missingAfterInteract = 0
                        for _ = 1, 8 do
                            sleep(0.4)

                            if inventoryBeforeValid then
                                local inventoryNow, inventoryNowValid, inventoryNowError = COFFER_INVENTORY.snapshot()
                                if inventoryNowValid then
                                    local inventoryDeltas = COFFER_INVENTORY.findPositiveDeltas(inventoryBefore, inventoryNow)
                                    if #inventoryDeltas > 0 then
                                        logf(
                                            "Coffer interaction attempt %d added inventory items: %s; coffer open confirmed.",
                                            interactionAttempt,
                                            COFFER_INVENTORY.formatDeltas(inventoryDeltas)
                                        )
                                        TREASURE_RUNTIME.lastCofferOpenedAt = os.clock()
                                        return true
                                    end
                                elseif not inventoryFallbackLogged then
                                    logf(
                                        "Inventory snapshot incomplete after coffer interaction attempt %d (%s); using exact-coffer disappearance confirmation.",
                                        interactionAttempt,
                                        tostring(inventoryNowError or "unknown_error")
                                    )
                                    inventoryFallbackLogged = true
                                end
                            end

                            local sameCoffer = refreshSameCoffer(match, 28)
                            if sameCoffer == nil then
                                missingAfterInteract = missingAfterInteract + 1
                                if missingAfterInteract >= 3 then
                                    logf(
                                        "Coffer GameObjectId %s disappeared for %d consecutive scan(s) after interaction attempt %d; coffer open confirmed.",
                                        tostring(identity.gameObjectId or "?"),
                                        missingAfterInteract,
                                        interactionAttempt
                                    )
                                    TREASURE_RUNTIME.lastCofferOpenedAt = os.clock()
                                    return true
                                end
                            else
                                match = sameCoffer
                                updateIdentity(match)
                                missingAfterInteract = 0
                            end
                        end

                        local freeSlotsAfter = getFreeInventorySlots()
                        if freeSlotsBefore ~= nil and freeSlotsAfter ~= nil then
                            logf(
                                "Coffer interaction attempt %d inventory telemetry: free slots %d -> %d; no positive normal-bag item-count delta detected.",
                                interactionAttempt,
                                freeSlotsBefore,
                                freeSlotsAfter
                            )
                        end
                        logf("Coffer remains present after interaction attempt %d; repathing to 3.0y and retrying direct interaction.", interactionAttempt)
                    end
                end
            end
         end
    end

    stopPathing()
    logf(
        "Coffer interaction ended without confirmation after %.1fs and %d direct interaction attempt(s).",
        os.clock() - interactionStartedAt,
        interactionAttempt
    )
    return false
end
local function acquireRevealedCoffer(contextLabel)
    local revealRadius = TREASURE_REVEAL_SCAN_RADIUS
    TREASURE_RUNTIME.cofferRevealed = true
    NINJA_MODE.hideFailed = false
    NINJA_MODE.abortReason = nil
    logf("%s reveal detected at player position %s.", tostring(contextLabel), formatVector3(getPlayerPosition()))

    local deadline = os.clock() + TREASURE_REVEAL_ACQUIRE_TIMEOUT
    local fallbackLogged = false
    while os.clock() < deadline do
        local namedMatch = findNearbyCofferByName(revealRadius, true)
        if namedMatch ~= nil then
            logCofferMatch(string.format("%s named coffer scan hit", tostring(contextLabel)), namedMatch)
            if interactWithEntity(namedMatch) then
                return true, nil
            end
            LOGGING.verbosef("%s named coffer interaction did not confirm open; continuing reveal acquisition.", tostring(contextLabel))
        end

        local objectMatch = findNearbyCofferByObjectScan(revealRadius, not fallbackLogged, contextLabel)
        if not fallbackLogged then
            fallbackLogged = true
            logf("%s reveal fallback scan engaged; named coffer lookup failed or did not confirm open.", tostring(contextLabel))
        end
        if objectMatch ~= nil then
            logCofferMatch(string.format("%s fallback object-scan hit", tostring(contextLabel)), objectMatch)
            if interactWithEntity(objectMatch) then
                return true, nil
            end
            LOGGING.verbosef("%s fallback coffer interaction did not confirm open; continuing reveal acquisition.", tostring(contextLabel))
        end

        sleep(TREASURE_REVEAL_SCAN_INTERVAL)
    end

    logf("Revealed coffer for %s could not be opened after %.1fs of acquisition attempts.", tostring(contextLabel), TREASURE_REVEAL_ACQUIRE_TIMEOUT)
    return false, "revealed_coffer_unopened"
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
    TREASURE_RUNTIME.lastElixirUseAt = os.clock()
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
    -- Local treasure hints are direct cardinal offsets from the player's current position.
    -- In FFXIV world coordinates, north is -Z, south is +Z, east is +X, and west is -X.
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
    local directionVector = DIRECTION_VECTORS[direction]
    if position == nil or directionVector == nil then
        return nil
    end

    TREASURE_RUNTIME.lastNavmeshRejectionSummary = nil
    local rejectionCounts = {}
    local stepMultipliers = { 1.0, 0.75, 0.5, 0.25 }

    local function recordRejection(reason)
        local key = tostring(reason or "unknown")
        rejectionCounts[key] = (rejectionCounts[key] or 0) + 1
    end

    local function validateMeshTarget(rawTarget, meshTarget, method, radius, step, multiplier)
        if meshTarget == nil then
            return nil
        end

        local validMeshPoint, rejectionReason, verticalDelta = TREASURE_RUNTIME.validateNavmeshResolution(
            rawTarget,
            meshTarget,
            TREASURE_RUNTIME.navmeshMaxVerticalSnap
        )
        if not validMeshPoint then
            recordRejection(rejectionReason)
            LOGGING.verbosef(
                "Treasure target %s resolved via %s(r=%.0f) to %s, but navmesh validation rejected it: reason=%s verticalSnap=%s.",
                formatVector3(rawTarget),
                tostring(method),
                radius,
                formatVector3(meshTarget),
                tostring(rejectionReason),
                verticalDelta and string.format("%.1fy", verticalDelta) or "n/a"
            )
            return nil
        end

        local snapDistance = distanceFlat(rawTarget, meshTarget)
        local moveX = meshTarget.X - position.X
        local moveZ = meshTarget.Z - position.Z
        local targetDistance = math.sqrt((moveX * moveX) + (moveZ * moveZ))
        local forwardDistance = (moveX * directionVector.x) + (moveZ * directionVector.z)
        local lateralDistance = math.abs((moveX * directionVector.z) - (moveZ * directionVector.x))

        local maxSnapDistance = math.max(3.5, step * 0.75)
        local minimumForwardDistance = math.max(1.0, step * 0.20)
        local maxLateralDistance = math.max(3.0, step * 0.75)

        if snapDistance > maxSnapDistance then
            recordRejection("horizontal_snap")
            LOGGING.verbosef("Treasure target %s resolved via %s(r=%.0f) to %s, but snap drift %.1fy exceeds %.1fy; rejecting mesh point.", formatVector3(rawTarget), tostring(method), radius, formatVector3(meshTarget), snapDistance, maxSnapDistance)
            return nil
        end

        if forwardDistance < minimumForwardDistance then
            recordRejection("insufficient_forward")
            LOGGING.verbosef("Treasure target %s resolved via %s(r=%.0f) to %s, but it only advances %.1fy in the intended %s direction; rejecting mesh point.", formatVector3(rawTarget), tostring(method), radius, formatVector3(meshTarget), forwardDistance, tostring(direction))
            return nil
        end

        if lateralDistance > maxLateralDistance then
            recordRejection("lateral_drift")
            LOGGING.verbosef("Treasure target %s resolved via %s(r=%.0f) to %s, but lateral drift %.1fy exceeds %.1fy for %s; rejecting mesh point.", formatVector3(rawTarget), tostring(method), radius, formatVector3(meshTarget), lateralDistance, maxLateralDistance, tostring(direction))
            return nil
        end

        local _, hasRoute = pathfindRoute(position, meshTarget)
        if not hasRoute then
            recordRejection("no_route")
            LOGGING.verbosef("Treasure target %s resolved via %s(r=%.0f) to %s but pathfind returned no route.", formatVector3(rawTarget), tostring(method), radius, formatVector3(meshTarget))
            return nil
        end

        return {
            rawTarget = rawTarget,
            snappedTarget = meshTarget,
            snapMethod = method,
            snapRadius = radius,
            snapDistance = snapDistance,
            verticalSnapDistance = verticalDelta,
            forwardDistance = forwardDistance,
            lateralDistance = lateralDistance,
            targetDistance = targetDistance,
            step = step,
            multiplier = multiplier,
            score = snapDistance + (lateralDistance * 0.5) + (math.abs(targetDistance - step) * 0.25),
        }
    end

    for _, multiplier in ipairs(stepMultipliers) do
        local step = baseStep * multiplier
        local rawTarget = buildTreasureTarget(position, direction, step)
        if rawTarget ~= nil then
            for _, radius in ipairs(TREASURE_SEARCH_RADII) do
                local bestPlan = nil

                local floorPoint = getPointOnFloor(rawTarget, radius)
                local floorPlan = validateMeshTarget(rawTarget, floorPoint, "PointOnFloor", radius, step, multiplier)
                if floorPlan ~= nil then
                    bestPlan = floorPlan
                end

                local nearestPoint = getNearestNavmeshPoint(rawTarget, radius, math.max(TREASURE_NAVMESH_HALF_EXTENT_Y, radius * 0.4))
                local nearestPlan = validateMeshTarget(rawTarget, nearestPoint, "NearestPoint", radius, step, multiplier)
                if nearestPlan ~= nil and (bestPlan == nil or nearestPlan.score < bestPlan.score) then
                    bestPlan = nearestPlan
                end

                if bestPlan ~= nil then
                    return bestPlan
                end

                if floorPoint == nil and nearestPoint == nil then
                    LOGGING.verbosef("Treasure target %s had no navmesh point from PointOnFloor or NearestPoint at radius %.0f.", formatVector3(rawTarget), radius)
                end
            end
        end
    end

    local rejectionParts = {}
    for reason, count in pairs(rejectionCounts) do
        table.insert(rejectionParts, string.format("%s=%d", reason, count))
    end
    table.sort(rejectionParts)
    if #rejectionParts > 0 then
        TREASURE_RUNTIME.lastNavmeshRejectionSummary = table.concat(rejectionParts, ", ")
    end

    return nil
end

local function performTreasureMove(event, contextLabel, stepIndex, consecutiveStalls, activeCandidate)
    local playerPosition = getPlayerPosition()
    local moveStep = getStepSize(event.distanceBucket)
    local movePlan = resolveTreasureMove(playerPosition, event.direction, moveStep)
    if movePlan == nil then
        local rejectionSummary = TREASURE_RUNTIME.lastNavmeshRejectionSummary
        if rejectionSummary ~= nil then
            logf(
                "%s move %d: no valid navmesh route for %s %s. Rejections: %s. Holding position and retrying elixir.",
                contextLabel,
                stepIndex,
                tostring(event.distanceBucket),
                tostring(event.direction),
                rejectionSummary
            )
        else
            logf("%s move %d: no valid navmesh route for %s %s. Holding position and retrying elixir.", contextLabel, stepIndex, tostring(event.distanceBucket), tostring(event.direction))
        end
        return false, consecutiveStalls or 0, "retry", activeCandidate
    end

    local target = movePlan.snappedTarget
    if target == nil then
        logf("%s move %d: hint parse incomplete. direction=%s distance=%s raw=%q", contextLabel, stepIndex, tostring(event.direction), tostring(event.distanceBucket), tostring(event.raw))
        return false, consecutiveStalls or 0, "retry", activeCandidate
    end

    local handoffOk, handoffCandidate, handoffReason = TREASURE_RUNTIME.checkCandidateHandoff(activeCandidate, target, "resolved target")
    if not handoffOk then
        return false, consecutiveStalls or 0, handoffReason or "candidate_handoff_failed", handoffCandidate or activeCandidate
    end
    if handoffCandidate ~= nil then
        activeCandidate = handoffCandidate
        contextLabel = string.format("Candidate %s", tostring(activeCandidate.label or "?"))
    end

    if TREASURE_RUNTIME.cofferRevealed then
        local acquired, acquireReason = acquireRevealedCoffer(contextLabel)
        if acquired then
            return true, 0, "found", activeCandidate
        end
        return false, consecutiveStalls or 0, acquireReason or "revealed_coffer_unopened", activeCandidate
    end

    if NINJA_MODE.isDangerousCandidate(activeCandidate) then
        if not NINJA_MODE.ensureHiddenOrAbort(activeCandidate) then
            return false, consecutiveStalls or 0, tostring(NINJA_MODE.abortReason or "hide_failed"), activeCandidate
        end
        if TREASURE_RUNTIME.cofferRevealed then
            local acquired, acquireReason = acquireRevealedCoffer(contextLabel)
            if acquired then
                return true, 0, "found", activeCandidate
            end
            return false, consecutiveStalls or 0, acquireReason or "revealed_coffer_unopened", activeCandidate
        end
    end

    local targetDistance = distanceFlat(playerPosition, target)
    logf("%s move %d: %s %s -> raw=%s resolved=%s via %s(r=%.0f) step=%.1f actualTarget=%.1fy.", contextLabel, stepIndex, tostring(event.distanceBucket), tostring(event.direction), formatVector3(movePlan.rawTarget), formatVector3(target), tostring(movePlan.snapMethod), tonumber(movePlan.snapRadius) or 0, movePlan.step, targetDistance)
    if targetDistance <= TREASURE_LOCAL_MOVE_SKIP_DISTANCE then
        logf("%s move %d resolved to an underfoot target (%.1fy away). Holding position and retrying elixir.", contextLabel, stepIndex, targetDistance)
        return false, 0, "retry", activeCandidate
    end

    if NINJA_MODE.isDangerousCandidate(activeCandidate) then
        ensureDismounted()
    else
        ensureMounted()
    end
    local moveStarted = pathfindTo(target)
    local moveReached = false
    local pathUnsuitable = false
    local pathUnsuitableFrom = targetDistance
    local pathUnsuitableTo = targetDistance
    local pathUnsuitableTravel = 0
    local pathUnsuitableReason = nil
    if moveStarted then
        moveStarted = waitUntil(function()
            return isVnavActive()
        end, TREASURE_MOVE_START_TIMEOUT, 0)
    end

    if moveStarted then
        local arrivalDistance = math.max(2.5, STEP_IMMEDIATE / 2)
        local deadline = os.clock() + getTreasureMoveTimeout(movePlan.step)
        local movementWatch = TREASURE_RUNTIME.newMovementWatch(playerPosition, target)

        while os.clock() < deadline do
            local currentPosition = getPlayerPosition()
            local currentRemaining = distanceFlat(currentPosition, target)
            if currentRemaining <= arrivalDistance then
                moveReached = true
                break
            end

            local movementStatus, movementDetail = TREASURE_RUNTIME.checkMovementWatch(
                movementWatch,
                currentPosition,
                target,
                TREASURE_PROGRESS_MIN_MOVE,
                TREASURE_PROGRESS_CHECK_INTERVAL,
                TREASURE_RUNTIME.movementDetourTimeout,
                TREASURE_RUNTIME.movementStationaryThreshold
            )
            if movementStatus == "stalled" or movementStatus == "detour_timeout" then
                pathUnsuitable = true
                pathUnsuitableReason = movementStatus
                pathUnsuitableFrom = tonumber(movementDetail.previousDistance) or currentRemaining
                pathUnsuitableTo = currentRemaining
                pathUnsuitableTravel = tonumber(movementDetail.playerTravel) or 0
                break
            end

            if not isVnavActive() then
                break
            end
            sleep(0.5)
        end
    else
        logf("%s move %d failed to start vnav movement.", contextLabel, stepIndex)
    end

    stopPathing()
    local movedTo = getPlayerPosition()
    local movedDistance = distanceFlat(playerPosition, movedTo)
    local remainingDistance = distanceFlat(movedTo, target)
    local overallImprovement = targetDistance - remainingDistance

    local postHandoffOk, postHandoffCandidate, postHandoffReason = TREASURE_RUNTIME.checkCandidateHandoff(activeCandidate, movedTo, "actual post-move position")
    if not postHandoffOk then
        return false, consecutiveStalls or 0, postHandoffReason or "candidate_handoff_failed", postHandoffCandidate or activeCandidate
    end
    if postHandoffCandidate ~= nil then
        activeCandidate = postHandoffCandidate
        contextLabel = string.format("Candidate %s", tostring(activeCandidate.label or "?"))
    end

    if TREASURE_RUNTIME.cofferRevealed then
        local acquired, acquireReason = acquireRevealedCoffer(contextLabel)
        if acquired then
            return true, 0, "found", activeCandidate
        end
        return false, consecutiveStalls or 0, acquireReason or "revealed_coffer_unopened", activeCandidate
    end

    if pathUnsuitable then
        if pathUnsuitableReason == "detour_timeout" then
            logf(
                "%s move %d remained on a moving detour for %.1fs without meaningful target-distance improvement: player moved %.1fy while remaining distance changed from %.1fy to %.1fy. Retrying elixir from current position.",
                contextLabel,
                stepIndex,
                TREASURE_RUNTIME.movementDetourTimeout,
                pathUnsuitableTravel,
                pathUnsuitableFrom,
                pathUnsuitableTo
            )
        else
            logf(
                "%s move %d path stalled while the player was effectively stationary: remaining distance changed from %.1fy to %.1fy while player moved %.1fy. Retrying elixir from current position.",
                contextLabel,
                stepIndex,
                pathUnsuitableFrom,
                pathUnsuitableTo,
                pathUnsuitableTravel
            )
        end
        sleep(TREASURE_MOVE_SETTLE)
        return false, 0, "retry", activeCandidate
    end

    if not moveReached and overallImprovement < TREASURE_STALL_MIN_MOVE then
        if movedDistance >= TREASURE_RUNTIME.movementStationaryThreshold then
            logf(
                "%s movement ended after a detour: remaining distance improved only %.1fy (%.1fy to %.1fy), but the player traveled %.1fy. Retrying elixir without counting a stationary stall.",
                contextLabel,
                overallImprovement,
                targetDistance,
                remainingDistance,
                movedDistance
            )
            return false, 0, "retry", activeCandidate
        end

        local newStalls = (consecutiveStalls or 0) + 1
        logf(
            "%s movement stalled: remaining distance improved only %.1fy (%.1fy to %.1fy), player traveled %.1fy, stall %d/%d.",
            contextLabel,
            overallImprovement,
            targetDistance,
            remainingDistance,
            movedDistance,
            newStalls,
            TREASURE_MAX_CONSECUTIVE_STALLS
        )
        if newStalls >= TREASURE_MAX_CONSECUTIVE_STALLS then
            return false, newStalls, "stalled", activeCandidate
        end
        return false, newStalls, "retry", activeCandidate
    end

    logf(
        "%s move %d ended: traveled %.1fy toward %s, remaining %.1fy (step target %.1fy, reached=%s).",
        contextLabel,
        stepIndex,
        movedDistance,
        tostring(event.direction),
        remainingDistance,
        movePlan.step,
        tostring(moveReached)
    )
    sleep(TREASURE_MOVE_SETTLE)
    local afterMoveCoffer = findNearbyCoffer(COFFER_SCAN_RADIUS, true)
    if afterMoveCoffer ~= nil then
        if interactWithEntity(afterMoveCoffer) then
            log("Treasure coffer opened after movement.")
            return true, 0, "found", activeCandidate
        end
        log("Coffer interaction after movement did not confirm open.")
    end

    return false, 0, "moved", activeCandidate
end

local function probeTreasureAtCurrentPosition(contextLabel)
    if TREASURE_RUNTIME.cofferRevealed then
        local acquired, acquireReason = acquireRevealedCoffer(contextLabel)
        if acquired then
            log("Treasure coffer found from preserved reveal state.")
            return true, nil, "found"
        end
        return false, nil, acquireReason or "revealed_coffer_unopened"
    end

    local coffer = findNearbyCoffer(COFFER_SCAN_RADIUS, true)
    if coffer ~= nil then
        if interactWithEntity(coffer) then
            log("Primary treasure coffer opened. Bonus handling disabled; ending treasure phase.")
            return true, nil, "found"
        end
        log("Primary treasure coffer interaction did not confirm open.")
    else
        logf("%s coffer scan found nothing within %.0fy.", tostring(contextLabel), COFFER_SCAN_RADIUS)
    end

    if TREASURE_RUNTIME.cofferRevealed then
        local acquired, acquireReason = acquireRevealedCoffer(contextLabel)
        if acquired then
            log("Treasure coffer found before another Magical Elixir use.")
            return true, nil, "found"
        end
        return false, nil, acquireReason or "revealed_coffer_unopened"
    end

    local revisionBefore = latestTreasureEventRevision
    if not useMagicalElixir() then
        sleep(TREASURE_ELIXIR_RETRY_DELAY)
    else
        TREASURE_RUNTIME.elixirUseCount = (tonumber(TREASURE_RUNTIME.elixirUseCount) or 0) + 1
        logf("%s used %s (elixir use %d).", contextLabel, MAGICAL_ELIXIR_NAME, TREASURE_RUNTIME.elixirUseCount)
    end

    local _, event = waitForTreasureEvent(revisionBefore, TREASURE_HINT_TIMEOUT)
    if event == nil then
        local revealedAfterDelay = findNearbyCoffer(COFFER_SCAN_RADIUS, true)
        if revealedAfterDelay ~= nil then
            if interactWithEntity(revealedAfterDelay) then
                log("Coffer opened after delayed reveal.")
                return true, nil, "found"
            end
            log("Delayed-reveal coffer interaction did not confirm open.")
        end
        logf("%s no new treasure hint arrived.", contextLabel)
        return false, nil, "no_event"
    end

    if event.kind == "coffer_reveal" or event.kind == "coffer_message" then
        TREASURE_RUNTIME.cofferRevealed = true
        NINJA_MODE.hideFailed = false
        NINJA_MODE.abortReason = nil
        local acquired, acquireReason = acquireRevealedCoffer(contextLabel)
        if acquired then
            log("Treasure coffer found after reveal message.")
            return true, event, "found"
        end
        return false, event, acquireReason or "revealed_coffer_unopened"
    elseif event.kind == "bonus_offer" then
        log("Bonus chest offer detected, but bonus handling is disabled for this version.")
        return true, event, "bonus"
    elseif event.kind == "elixir_prompt" then
        logf("%s treasure prompt detected; elixir will be retried if needed.", contextLabel)
    end

    return false, event, "event"
end

local function refineTreasureNearCandidate(candidate, initialEvent)
    local activeCandidate = candidate
    local contextLabel = string.format("Candidate %s", tostring(activeCandidate.label or "?"))
    local consecutiveStalls = 0
    local currentEvent = initialEvent
    local mappedPointRetryUsedByLabel = {}

    for stepIndex = 1, TREASURE_LOCAL_MAX_STEPS do
        contextLabel = string.format("Candidate %s", tostring(activeCandidate.label or "?"))
        if TREASURE_RUNTIME.cofferRevealed then
            local acquired, acquireReason = acquireRevealedCoffer(contextLabel)
            if acquired then
                return true, nil, activeCandidate
            end
            return false, acquireReason or "revealed_coffer_unopened", activeCandidate
        end
        if NINJA_MODE.abortReason == "gearset_failed" then
            return false, "gearset_failed", activeCandidate
        end
        if NINJA_MODE.hideFailed then
            return false, "hide_failed", activeCandidate
        end
        if not hasTreasureBuff() and not TREASURE_RUNTIME.cofferRevealed then
            return false, "treasure buff expired before coffer reveal", activeCandidate
        end

        local coffer = findNearbyCoffer(COFFER_SCAN_RADIUS, true)
        if coffer ~= nil then
            if interactWithEntity(coffer) then
                log("Primary treasure coffer opened. Bonus handling disabled; ending treasure phase.")
                return true, nil, activeCandidate
            end
            log("Primary treasure coffer interaction did not confirm open.")
        end

        if currentEvent == nil then
            local probeFound, probeEvent, probeReason = probeTreasureAtCurrentPosition(contextLabel)
            if probeFound then
                return true, nil, activeCandidate
            end
            if probeReason == "revealed_coffer_unopened" or probeReason == "hide_failed" or probeReason == "gearset_failed" then
                return false, probeReason, activeCandidate
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
                return false, "candidate_mismatch", activeCandidate
            end

            local activeLabel = tostring(activeCandidate.label or "?")
            local positionDistance = distanceFlat(getPlayerPosition(), activeCandidate.position)
            if positionDistance > 4.5 and not mappedPointRetryUsedByLabel[activeLabel] then
                mappedPointRetryUsedByLabel[activeLabel] = true
                logf("%s local hint confirmed; making one mapped-point retry at %s (%.1fy away). Further local hints will follow dead-reckoning instead of returning to the mapped point.", contextLabel, formatVector3(activeCandidate.position), positionDistance)
                local positionMoved, positionEndPosition, _, positionReason = NINJA_MODE.moveToTreasureCandidate(activeCandidate, activeCandidate, activeCandidate.position, 4.5, contextLabel .. " mapped")
                local positionRemaining = distanceFlat(positionEndPosition, activeCandidate.position)
                if not positionMoved then
                    if positionReason == "hide_failed" or positionReason == "gearset_failed" then
                        return false, positionReason, activeCandidate
                    end
                    logf("%s failed to reach mapped point %s (remaining %.1fy). Continuing with local dead-reckoning from current position.", contextLabel, formatVector3(activeCandidate.position), positionRemaining)
                end

                local handoffOk, handoffCandidate, handoffReason = TREASURE_RUNTIME.checkCandidateHandoff(activeCandidate, getPlayerPosition(), "mapped-point movement result")
                if not handoffOk then
                    return false, handoffReason or "candidate_handoff_failed", handoffCandidate or activeCandidate
                end
                if handoffCandidate ~= nil then
                    activeCandidate = handoffCandidate
                    contextLabel = string.format("Candidate %s", tostring(activeCandidate.label or "?"))
                end

                if TREASURE_RUNTIME.cofferRevealed then
                    local acquired, acquireReason = acquireRevealedCoffer(contextLabel)
                    if acquired then
                        return true, nil, activeCandidate
                    end
                    return false, acquireReason or "revealed_coffer_unopened", activeCandidate
                end

                local foundAfterPositionMove = findNearbyCoffer(COFFER_SCAN_RADIUS, true)
                if foundAfterPositionMove ~= nil then
                    if interactWithEntity(foundAfterPositionMove) then
                        log("Treasure coffer opened after mapped-point movement.")
                        return true, nil, activeCandidate
                    end
                    log("Mapped-point coffer interaction did not confirm open.")
                end
            else
                local moveFound, newStalls, moveReason, finalCandidate = performTreasureMove(currentEvent, contextLabel, stepIndex, consecutiveStalls, activeCandidate)
                activeCandidate = finalCandidate or activeCandidate
                contextLabel = string.format("Candidate %s", tostring(activeCandidate.label or "?"))
                consecutiveStalls = newStalls or 0
                if moveFound then
                    return true, nil, activeCandidate
                end
                if moveReason == "stalled" then
                    return false, "candidate_stalled", activeCandidate
                end
                if moveReason == "hide_failed" or moveReason == "gearset_failed" or moveReason == "dangerous_handoff_unavailable" or moveReason == "revealed_coffer_unopened" then
                    return false, moveReason, activeCandidate
                end
            end
        elseif currentEvent.kind == "bonus_offer" then
            return true, nil, activeCandidate
        end

        currentEvent = nil

        ::continue_refine::
    end

    return false, "candidate_refinement_exceeded", activeCandidate
end

local function runTreasureHunt(fateName, fateCenter)
    if not hasTreasureBuff() then
        return false, "treasure buff missing"
    end

    local function finishTreasureHunt(ok, err)
        NINJA_MODE.endCandidate()
        TREASURE_RUNTIME.trackingActive = false
        TREASURE_RUNTIME.cofferRevealed = false
        TREASURE_RUNTIME.revealedCofferBypassLogged = false
        TREASURE_RUNTIME.currentContext = nil
        return ok, err
    end

    TREASURE_RUNTIME.trackingActive = true
    TREASURE_RUNTIME.lastLoggedCaptureKey = nil
    TREASURE_RUNTIME.elixirUseCount = 0
    TREASURE_RUNTIME.lastElixirUseAt = nil
    TREASURE_RUNTIME.lastCofferOpenedAt = nil
    TREASURE_RUNTIME.cofferRevealed = false
    TREASURE_RUNTIME.revealedCofferBypassLogged = false
    TREASURE_RUNTIME.currentContext = {
        fateName = fateName,
        group = nil,
        candidateLabel = nil,
        dangerous = false,
        currentCandidate = nil,
        note = nil,
        handledCandidateLabels = {},
    }
    resetTreasureEvents()
    TREASURE_RUNTIME.currentContext.group = nil
    TREASURE_RUNTIME.currentContext.candidateLabel = nil
    TREASURE_RUNTIME.currentContext.currentCandidate = nil
    TREASURE_RUNTIME.currentContext.note = nil
    TREASURE_RUNTIME.moveToInitialProbeOrigin(fateName, fateCenter)
    stopPathing()
    waitUntil(function()
        return not isVnavActive()
    end, 2.0, 0.1)
    sleep(0.3)
    resetTreasureEvents()
    logf("Starting treasure hunt for %s with buff remaining %.1fs.", tostring(fateName), getStatusRemaining(CACHE_ME_IF_YOU_CAN_STATUS_ID))

    local initialFound, initialEvent, initialReason = probeTreasureAtCurrentPosition("Initial treasure hint")
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

    local previousCandidate = nil
    for index, candidate in ipairs(orderedCandidates) do
        local candidateLabel = tostring(candidate.label or "?")
        local handledCandidates = TREASURE_RUNTIME.currentContext.handledCandidateLabels or {}
        TREASURE_RUNTIME.currentContext.handledCandidateLabels = handledCandidates

        if handledCandidates[candidateLabel] then
            LOGGING.verbosef("Skipping outer candidate %s because it was already handled during treasure refinement.", candidateLabel)
        else
            if not hasTreasureBuff() and not TREASURE_RUNTIME.cofferRevealed then
                return finishTreasureHunt(false, "treasure buff expired before coffer reveal")
            end

            handledCandidates[candidateLabel] = true
            NINJA_MODE.beginCandidate(candidate)
            local destination = candidate.position
            local suffix = NINJA_MODE.isDangerousCandidate(candidate) and string.format(" [aggro=%s%s]", tostring(candidate.aggroLevel or "?"), candidate.note and (", " .. tostring(candidate.note)) or "") or ""
            TREASURE_RUNTIME.currentContext.candidateLabel = candidate.label
            TREASURE_RUNTIME.currentContext.dangerous = NINJA_MODE.isDangerousCandidate(candidate)
            TREASURE_RUNTIME.currentContext.currentCandidate = candidate
            TREASURE_RUNTIME.currentContext.note = candidate.note
            logf("Checking coffer candidate %d/%d: group=%s label=%s.", index, #orderedCandidates, tostring(initialEvent.direction), candidateLabel)
            logf("Candidate %d/%d %s: moving to %s%s.", index, #orderedCandidates, candidateLabel, formatVector3(destination), suffix)
            local candidateContextLabel = string.format("Candidate %s", candidateLabel)
            local moved, endPosition, _, moveReason = NINJA_MODE.moveToTreasureCandidate(previousCandidate, candidate, destination, TREASURE_CANDIDATE_STOP_DISTANCE, candidateContextLabel)
            if not moved then
                local remainingDistance = distanceFlat(endPosition, destination)
                logf("Candidate %s: failed to reach target %s after %d attempt(s); final remaining distance %.1fy (reason=%s).", candidateLabel, formatVector3(destination), TREASURE_CANDIDATE_TRAVEL.maxAttempts, remainingDistance, tostring(moveReason or "unknown"))
                if moveReason == "gearset_failed" and NINJA_MODE.isDangerousCandidate(candidate) then
                    logf("Candidate %s: Ninja gearset failed after retry; clearing its state and checking the next candidate.", candidateLabel)
                    previousCandidate = nil
                    goto continue_candidate_body
                elseif moveReason == "hide_failed" and NINJA_MODE.isDangerousCandidate(candidate) then
                    logf("Candidate %s: Hide failed for this dangerous candidate; clearing its state before the next candidate.", candidateLabel)
                    previousCandidate = nil
                    goto continue_candidate_body
                elseif moveReason == "hide_failed" then
                    logf("Candidate %s returned an unexpected Hide failure despite dangerous=false; clearing stale state and continuing normally.", candidateLabel)
                    NINJA_MODE.hideFailed = false
                    NINJA_MODE.abortReason = nil
                end
                if remainingDistance > TREASURE_CANDIDATE_TRAVEL.nearEnoughRadius then
                    previousCandidate = candidate
                    goto continue_candidate_body
                end
                logf("Candidate %s: ended within %.1fy of target; probing candidate anyway.", candidateLabel, remainingDistance)
            end

            local foundAfterMove = findNearbyCoffer(COFFER_SCAN_RADIUS, true)
            if foundAfterMove ~= nil then
                if interactWithEntity(foundAfterMove) then
                    log("Treasure coffer opened after candidate travel.")
                    return finishTreasureHunt(true, nil)
                end
                log("Candidate-travel coffer interaction did not confirm open.")
            end

            local probeFound, probeEvent, probeReason = probeTreasureAtCurrentPosition(candidateContextLabel)
            if probeFound then
                return finishTreasureHunt(true, nil)
            end
            if probeReason == "gearset_failed" then
                logf("Candidate %s interaction was blocked because the Ninja gearset failed after retry; checking the next candidate.", candidateLabel)
                previousCandidate = nil
                goto continue_candidate_body
            end
            if probeReason == "hide_failed" then
                logf("Candidate %s interaction was blocked by candidate-local Hide failure; clearing state before the next candidate.", candidateLabel)
                previousCandidate = nil
                goto continue_candidate_body
            end
            if probeReason == "revealed_coffer_unopened" then
                return finishTreasureHunt(false, "revealed_coffer_unopened")
            end
            if probeReason == "no_event" or probeEvent == nil then
                logf("Candidate %s produced no usable hint. Trying next candidate.", candidateLabel)
                if NINJA_MODE.hideFailed then
                    previousCandidate = nil
                else
                    previousCandidate = candidate
                end
                goto continue_candidate_body
            end
            if probeEvent.kind ~= "hint" then
                logf("Candidate %s produced non-hint event %s. Trying next candidate.", candidateLabel, tostring(probeEvent.kind))
                previousCandidate = candidate
                goto continue_candidate_body
            end
            if not isLocalTreasureDistance(probeEvent.distanceBucket) then
                logf("Candidate %s is not local yet (%s %s). Trying next candidate.", candidateLabel, tostring(probeEvent.distanceBucket), tostring(probeEvent.direction))
                previousCandidate = candidate
                goto continue_candidate_body
            end

            local refined, refineErr, finalCandidate = refineTreasureNearCandidate(candidate, probeEvent)
            if refined then
                return finishTreasureHunt(true, nil)
            end
            if refineErr == "revealed_coffer_unopened" then
                return finishTreasureHunt(false, "revealed_coffer_unopened")
            end

            local finalLabel = tostring(finalCandidate and finalCandidate.label or candidateLabel)
            logf("Candidate %s refinement ended without success: %s. Trying next candidate.", finalLabel, tostring(refineErr))

            if refineErr == "hide_failed" or refineErr == "gearset_failed" or refineErr == "dangerous_handoff_unavailable" then
                previousCandidate = nil
            else
                previousCandidate = finalCandidate or candidate
            end

            ::continue_candidate_body::
        end
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
        local treasureOk, treasureErr = runTreasureHunt(activeFate.name, targetLocation)
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

    potCycleRuntime.resetInterspawnPredictionLog()
    INSTANCE_TIME_MODE.lastDecisionLogAt = os.clock() - INSTANCE_TIME_MODE.decisionLogInterval
    if INSTANCE_TIME_MODE.leaveIfNeeded("after completed pot cycle") then
        return true, nil
    end

    local returnOk, returnErr = returnToBaseAndWait()
    local restoreOk = NINJA_MODE.restoreFateGearsetIfNeeded()
    if not returnOk then
        logf("Return to base failed after pot cycle: %s.", tostring(returnErr))
    end
    if not restoreOk then
        log("FATE gearset restoration failed after the pot cycle.")
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

    potCycleRuntime.bootstrapWaitActive = true
    active = waitAtSpawnForFate(guessedName, {
        mode = "bootstrap",
        timeoutSeconds = INITIAL_SPAWN_WAIT_MINUTES * 60,
    })
    potCycleRuntime.bootstrapWaitActive = false
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

    local predictedSpawnAt = potCycleRuntime.lastSpawnAt + POT_CYCLE_SECONDS
    potCycleRuntime.waitingAtPredictedSpawn = true
    local predictedActive = waitAtSpawnForFate(nextName, {
        mode = "predicted",
        predictedSpawnAt = predictedSpawnAt,
        graceSeconds = 5 * 60,
    })
    potCycleRuntime.waitingAtPredictedSpawn = false
    if predictedActive ~= nil then
        return predictedActive
    end

    logf("Predicted wait for '%s' expired. Clearing the stale spawn anchor and returning to bootstrap recovery.", nextName)
    potCycleRuntime.activeFateName = nil
    potCycleRuntime.lastSpawnFateName = nil
    potCycleRuntime.lastSpawnAt = nil
    potCycleRuntime.waitingAtPredictedSpawn = false
    potCycleRuntime.bootstrapWaitActive = false
    potCycleRuntime.resetInterspawnPredictionLog()
    local returnOk, returnErr = returnToBaseAndWait()
    if not returnOk then
        logf("Cycle recovery return-to-base failed after predicted wait timeout: %s.", tostring(returnErr))
    end
    return nil
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
    if parsed.kind == "coffer_reveal" or parsed.kind == "coffer_message" then
        TREASURE_RUNTIME.cofferRevealed = true
        TREASURE_RUNTIME.revealedCofferBypassLogged = false
        NINJA_MODE.hideFailed = false
        NINJA_MODE.abortReason = nil
    end
    latestTreasureEvent = parsed
    latestTreasureEventRevision = latestTreasureEventRevision + 1
end

local function main()
    math.randomseed(os.time())
    log("Starting Occult Crescent Pots Treasure Farmer.")
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
            LOGGING.verbose("Autorotation disabled; no preset configured.")
        end
    end

    do
        local names = getResolvedCofferNames()
        if #names > 0 then
            logf("Resolved localized coffer names from EObjName rows 2014741/2014742/2014743: %s.", table.concat(names, ", "))
        else
            log("Localized coffer names could not be resolved; stable EObj DataIds 2014741/2014742/2014743 remain active for detection.")
        end
        if getCaptureFilePath() ~= nil then
            logf("Runtime coffer captures will append to %s.", tostring(getCaptureFilePath()))
        else
            log("Runtime coffer capture file is disabled.")
        end
    end

    waitForSouthHorn()
    logf("Entered South Horn at position %s.", formatVector3(getPlayerPosition()))
    if INSTANCE_TIME_MODE.enabled then
        logf(
            "Instance time management enabled: reserve %.1f minutes for FATE completion, %.1f minutes for treasure, and %.1f minutes for exit. Unknown spawn timing reserves the full 30-minute spawn interval.",
            INSTANCE_TIME_MODE.fateBudgetSeconds / 60.0,
            INSTANCE_TIME_MODE.treasureBudgetSeconds / 60.0,
            INSTANCE_TIME_MODE.exitBufferSeconds / 60.0
        )
    end
    INSTANCE_TIME_MODE.lastDecisionLogAt = os.clock() - INSTANCE_TIME_MODE.decisionLogInterval
    if INSTANCE_TIME_MODE.leaveIfNeeded("initial South Horn entry") then
        return
    end

    if shouldSkipInitialBaseReturn() then
        log("Skipping initial return-to-base because player is already staged near the configured starting FATE.")
    else
        local baseOk, baseErr = returnToBaseAndWait()
        if not baseOk then
            logf("Initial return-to-base step failed: %s.", tostring(baseErr))
        end
    end

    while true do
        if INSTANCE_TIME_MODE.exitRequested then
            return
        end
        if INSTANCE_TIME_MODE.leaveIfNeeded("main cycle decision") then
            return
        end
        if isDead() and not handleDeathState() then
            stopScriptWithError("Failed to recover from death")
        end

        local active = getBestActivePotFate(nil)
        if active == nil then
            if potCycleRuntime.lastSpawnFateName ~= nil then
                active = runPredictedCycle()
            else
                active = runBootstrapCycle()
            end
        end

        if INSTANCE_TIME_MODE.exitRequested then
            return
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
