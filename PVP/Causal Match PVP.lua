--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.1.7
description: PvP script - Inspired by Dhog | Improved by SudoStitch
plugin_dependencies:
- vnavmesh
- RotationSolver
configs:
  garoTitles:
    default: false
    description: Set Garo Titles
  Hello on entry:
    default: true
    description: Send /quickchat Hello during the portrait phase.
  Good Match on results:
    default: true
    description: Send /quickchat "Good Match" when the results addon appears.
  Match Limit:
    default: 0
    min: 0
    max: 999
    description: Stop after this many completed matches. Set to 0 for unlimited.
  Gearset Slot:
    description: Optional gearset slot number to equip before queueing (0 disables).
    default: 0
    min: 0
    max: 100
  Lifestream Command:
    default: ""
    description: Optional Lifestream command to run before initial queueing.
  Follow-up script:
    default: ""
    description: Optional SND script to run after the script stops from Match Limit.
[[End Metadata]]
--]=====]
-- =========================================================
-- PvP Utilities (Log/Sleep/WaitUntil/Addons/Conditions)
-- =========================================================
import("System.Numerics")

local UI = {
    PREFIX = "[PVP]",
    ECHO_ON_START = true,
    ECHO_TO_CHAT = false,
}

local function _echoLine(s) yield("/echo " .. tostring(s)) end
local function _logLine(s)
    local msg = tostring(s)
    Dalamud.Log(msg)
    if UI.ECHO_TO_CHAT then _echoLine(msg) end
end
local function _fmt(msg, ...) return string.format("%s %s", UI.PREFIX, string.format(msg, ...)) end

function Log(msg, ...) _logLine(_fmt(msg, ...)) end

TIME = {
    POLL    = 0.10,
    TIMEOUT = 10.0,
    STABLE  = 0.0
}

function Sleep(seconds)
    local s = tonumber(seconds) or 0
    if s < 0 then s = 0 end
    s = math.floor(s * 10 + 0.5) / 10
    yield("/wait " .. s)
end

function toNumberSafe(s, default, min, max)
    if s == nil then return default end
    local str = tostring(s):gsub("[^%d%-%.]", "")
    local n = tonumber(str)
    if n == nil then return default end
    if min ~= nil and n < min then n = min end
    if max ~= nil and n > max then n = max end
    return n
end

local function trimString(value)
    if type(value) ~= "string" then return "" end
    local trimmed = value:match("^%s*(.-)%s*$")
    return trimmed or value
end

local function _getAddon(name)
    local ok, addon = pcall(Addons.GetAddon, name)
    if ok and addon ~= nil then return addon end
    return nil
end

function IsAddonReady(name)
    local a = _getAddon(name)
    return a and a.Ready or false
end

function IsAddonVisible(name)
    local a = _getAddon(name)
    return a and a.Exists or false
end

-- WaitUntil(predicateFn, timeoutSec, pollSec, stableSec) -> true/false
function WaitUntil(predicateFn, timeoutSec, pollSec, stableSec)
    timeoutSec = toNumberSafe(timeoutSec, TIME.TIMEOUT, 0.1)
    pollSec    = toNumberSafe(pollSec,    TIME.POLL,   0.01)
    stableSec  = toNumberSafe(stableSec,  TIME.STABLE, 0.0)

    local start = os.clock()
    local holdStart = nil

    while (os.clock() - start) < timeoutSec do
        local ok, res = pcall(predicateFn)
        if ok and res then
            if not holdStart then holdStart = os.clock() end
            if (os.clock() - holdStart) >= stableSec then return true end
        else
            holdStart = nil
        end
        Sleep(pollSec)
    end
    return false
end

function AwaitAddonReady(name, timeoutSec)
    local t = toNumberSafe(timeoutSec, TIME.TIMEOUT, 0.1)
    Log("AwaitAddonReady: %s", tostring(name))
    local ok = WaitUntil(function()
        local a = _getAddon(name)
        return a and a.Ready
    end, t, TIME.POLL, 0.0)
    if not ok then
        Log("AwaitAddonReady timeout: %s", tostring(name))
    end
    return ok
end

function WaitConditionStable(idx, want, stableSec, timeoutSec, pollSec)
    if want == nil then want = true end
    timeoutSec = toNumberSafe(timeoutSec, TIME.TIMEOUT, 0.1)
    pollSec    = toNumberSafe(pollSec, TIME.POLL, 0.01)
    stableSec  = toNumberSafe(stableSec, 0.0, 0.0)

    local ok = WaitUntil(function()
        return GetCondition(idx, want)
    end, timeoutSec, pollSec, stableSec)

    if not ok then
        Log("WaitConditionStable timeout: idx=%s want=%s stable=%.1f", tostring(idx), tostring(want), stableSec)
    end
    return ok
end

local function _quoteArg(s)
    s = tostring(s)
    s = s:gsub("\\", "\\\\"):gsub('"', '\\"')
    return '"' .. s .. '"'
end

function SafeCallback(...)
    local args = {...}
    local idx  = 1
    local addon = args[idx]; idx = idx + 1
    if type(addon) ~= "string" or addon == "" then
        Log("SafeCallback: invalid addon name")
        return false
    end

    local update = args[idx]; idx = idx + 1
    local updateStr = "true"
    if type(update) == "boolean" then
        updateStr = update and "true" or "false"
    elseif type(update) == "string" then
        local s = update:lower()
        if s == "false" or s == "f" or s == "0" or s == "off" then updateStr = "false" end
    else
        idx = idx - 1
    end

    local call = "/callback " .. addon .. " " .. updateStr
    for i = idx, #args do
        local v = args[i]
        local t = type(v)
        if t == "number" then
            call = call .. " " .. tostring(v)
        elseif t == "boolean" then
            call = call .. " " .. (v and "true" or "false")
        elseif t == "string" then
            call = call .. " " .. _quoteArg(v)
        else
            Log("SafeCallback: ignoring unsupported arg #%d (type=%s)", i, t)
        end
    end

    Log("SafeCallback: %s", call)
    if IsAddonReady(addon) and IsAddonVisible(addon) then
        yield(call)
        return true
    else
        Log("SafeCallback: addon not ready/visible: %s", addon)
        return false
    end
end

CharacterCondition = CharacterCondition or {
    normalConditions = 1,
    dead             = 2,
    casting          = 27,
    boundByDuty34    = 34,
    betweenAreas     = 45,
    betweenAreasForDuty = 51,
    pvpDisplayActive = 62,
    inDutyQueue      = 91,
    editingPortrait  = 100,
}

function GetCondition(idx, want)
    if want == nil then want = true end
    return (Svc and Svc.Condition and (Svc.Condition[idx] == want)) or false
end

-- =========================================================
-- Config
-- =========================================================
local RUN_LOOP = true

local SET_GARO_TITLES = Config.Get("garoTitles")
local SEND_HELLO_ON_ENTRY = Config.Get("Hello on entry") ~= false
local SEND_GOOD_MATCH_ON_RESULTS = Config.Get("Good Match on results") ~= false
local MATCH_LIMIT = toNumberSafe(Config.Get("Match Limit"), 0, 0, 999)
local GEARSET_SLOT = toNumberSafe(Config.Get("Gearset Slot"), 0, 0, 100)
local LIFESTREAM_COMMAND = trimString(Config.Get("Lifestream Command"))
if LIFESTREAM_COMMAND ~= "" and string.lower(LIFESTREAM_COMMAND) == "none" then
    LIFESTREAM_COMMAND = ""
end
local FOLLOW_UP_SCRIPT = trimString(Config.Get("Follow-up script"))
if FOLLOW_UP_SCRIPT ~= "" and string.lower(FOLLOW_UP_SCRIPT) == "none" then
    FOLLOW_UP_SCRIPT = ""
end
local TITLE_1 = "barago"
local TITLE_2 = "garo"

local CRYSTAL_NAME = "Tactical Crystal"

-- vnav safety anchor points (two endpoints per map)
local SAFE_ANCHORS = {
    [1032] = { 70.08521270752,  4.0, -9.7963066101074,  -72.121978759766,  3.9999887943268,   9.7666854858398 }, -- Palaistra
    [1058] = { 70.08521270752,  4.0, -9.7963066101074,  -72.121978759766,  3.9999887943268,   9.7666854858398 }, -- Palaistra (alt)
    [1033] = { 60.159770965576, -1.5, -20.096973419189, -59.741413116455, -1.5,              -20.130617141724 }, -- Volcanic Heart
    [1059] = { 60.159770965576, -1.5, -20.096973419189, -59.741413116455, -1.5,              -20.130617141724 }, -- Volcanic Heart (alt)
    [1034] = { -90.087173461914,  6.2741222381592, 78.478736877441, 89.641860961914, 6.2917737960815, -72.475570678711 }, -- Cloud Nine
    [1060] = { -90.087173461914,  6.2741222381592, 78.478736877441, 89.641860961914, 6.2917737960815, -72.475570678711 }, -- Cloud Nine (alt)
    [1116] = { 59.628620147705,  -4.887580871582e-06, 30.043525695801, -59.981777191162, 1.1920928955078e-07, -30.034025192261 }, -- Clockwork Castletown
    [1117] = { 59.628620147705,  -4.887580871582e-06, 30.043525695801, -59.981777191162, 1.1920928955078e-07, -30.034025192261 }, -- Clockwork Castletown (alt)
    [1138] = { -103.6203994751,   2.000935792923, -50.288391113281, 102.09278869629, 2.0002493858337, 50.151763916016 }, -- Red Sands
    [1139] = { -103.6203994751,   2.000935792923, -50.288391113281, 102.09278869629, 2.0002493858337, 50.151763916016 }, -- Red Sands (alt)
    [1293] = { 187.177, -2.000, 99.600,  11.792, -2.000, 100.139 }, -- Bayside Battleground
    [1294] = { 187.177, -2.000, 99.600,  11.792, -2.000, 100.139 }, -- Bayside Battleground (alt)
    [1357] = { 24.983, 1.001, 117.666, 174.256, 1.001, 82.660 }, -- Archeia Harmonias
    [1358] = { 24.983, 1.001, 117.666, 174.256, 1.001, 82.660 }, -- Archeia Harmonias (alt)
}

-- JobId -> Limit Break action name
local LIMIT_BREAK_BY_JOB = {
    { job = 19, name = "Phalanx" },
    { job = 21, name = "Primal Scream" },
    { job = 32, name = "Eventide" },
    { job = 37, name = "Relentless Rush" },
    { job = 37, name = "Terminal Trigger" },
    { job = 24, name = "Afflatus Purgation" },
    { job = 33, name = "Celestial River" },
    { job = 40, name = "Mesotes" },
    { job = 23, name = "Final Fantasia" },
    { job = 31, name = "Marksman's Spite" },
    { job = 38, name = "Contradance" },
    { job = 20, name = "Meteodrive" },
    { job = 22, name = "Sky High" },
    { job = 22, name = "Sky Shatter" },
    { job = 30, name = "Seiton Tenchu" },
    { job = 34, name = "Zantetsuken" },
    { job = 39, name = "Tenebrae Lemurum" },
    { job = 25, name = "Soul Resonance" },
    { job = 27, name = "Summon Bahamut" },
    { job = 27, name = "Summon Phoenix" },
    { job = 41, name = "World-swallower" },
    { job = 42, name = "Advent of Chocobastion" },
    { job = 35, name = "Southern Cross" },
    { job = 28, name = "Seraphism" },
}

-- =========================================================
-- Minimal gameplay helpers
-- =========================================================
local function randInt(min, max) return math.random(min, max) end

local function ClearEnemySignTarget()
    yield("/enemysign clear <me>")
end

local function playerAvailable()
    return Player ~= nil and Player.Available == true
end

local function playerPos()
    if playerAvailable() and Entity and Entity.Player and Entity.Player.Position then
        local p = Entity.Player.Position
        return p.X or 0, p.Y or 0, p.Z or 0
    end
    return 0, 0, 0
end

local function myName()
    if Entity and Entity.Player and Entity.Player.Name then
        return Entity.Player.Name
    end
    return "Unknown"
end

local function localPlayer()
    if Svc and Svc.Objects and Svc.Objects.LocalPlayer then
        return Svc.Objects.LocalPlayer
    end
    return nil
end

local function classJobId()
    local lp = localPlayer()
    if lp and lp.ClassJob then return lp.ClassJob.RowId end
    return 0
end

local function objectPos(name)
    if not name or name == "" or not (Entity and Entity.GetEntityByName) then return nil end
    local ok, e = pcall(Entity.GetEntityByName, name)
    if not ok or not (e and e.Position) then return nil end
    return e.Position.X or 0, e.Position.Y or 0, e.Position.Z or 0
end

local function distBetween(x1,y1,z1,x2,y2,z2)
    x1 = tonumber(x1) or 0; y1 = tonumber(y1) or 0; z1 = tonumber(z1) or 0
    x2 = tonumber(x2) or 0; y2 = tonumber(y2) or 0; z2 = tonumber(z2) or 0
    local d = math.sqrt((x2-x1)^2 + (y2-y1)^2 + (z2-z1)^2)
    return tonumber(d) or 0
end

local function distToXYZ(x2, y2, z2)
    local x1,y1,z1 = playerPos()
    return distBetween(x1,y1,z1,x2,y2,z2)
end

local function distToName(name)
    local x2,y2,z2 = objectPos(name)
    if x2 == nil then return nil end
    return distToXYZ(x2,y2,z2)
end

local function hasStatus(statusId)
    local lp = localPlayer()
    if not lp or not lp.StatusList then return false end

    for i = 0, lp.StatusList.Length - 1 do
        local s = lp.StatusList[i]
        if s and s.StatusId == statusId then
            return true
        end
    end
    return false
end

local function contentTimeLeft()
    return (InstancedContent and InstancedContent.ContentTimeLeft) or 0
end

-- =========================================================
-- Death tracking (RSR disables rotation on death)
-- =========================================================
local wasDead = false
local deadSince = 0
local rotationNeedsReset = false

local function nowSec() return os.time() end
local function isDead()   return GetCondition(CharacterCondition.dead, true) end
local function isNormal() return GetCondition(CharacterCondition.normalConditions, true) end

local function checkDeathAndReapplyRotation()
    if isDead() then
        if not wasDead then
            wasDead = true
            deadSince = nowSec()
            rotationNeedsReset = true
            Log("death detected -> rotation will be re-applied after respawn")
        end
        return
    end

    if wasDead then
        wasDead = false
        local deadDuration = nowSec() - (deadSince or nowSec())
        if rotationNeedsReset and deadDuration >= 10 and isNormal() then
            yield("/rotation auto nearest")
            rotationNeedsReset = false
            Log("respawn detected -> rotation re-applied")
        end
    end

    if rotationNeedsReset and isNormal() then
        yield("/rotation auto nearest")
        rotationNeedsReset = false
        Log("rotation re-applied (failsafe)")
    end
end

-- =========================================================
-- Enemy extraction (nil means the party-list entry is not currently available)
-- =========================================================
local function getEnemyName(slotIndex)
    if not IsAddonReady("PvPMKSPartyList3") then
        return nil
    end

    local ok, addon = pcall(Addons.GetAddon, "PvPMKSPartyList3")
    if not ok or not addon then return nil end
    local nodeOk, node = pcall(function()
        return addon:GetNode(1, 5, slotIndex, 6, 18, 21)
    end)
    if not nodeOk or not node then return nil end

    local textOk, txt = pcall(function() return node.Text end)
    if textOk and txt ~= nil then
        local name = trimString(tostring(txt))
        if name ~= "" then return name end
    end
    return nil
end

local function refreshEnemyNames()
    return { getEnemyName(6), getEnemyName(7), getEnemyName(8), getEnemyName(9), getEnemyName(10) }
end

-- =========================================================
-- Runtime state + reset
-- =========================================================
inMatchLive = false
ranSafetyMoveThisDuty = false
enemyNames = { myName(), myName(), myName(), myName(), myName() }
lbTick = 0
hasEnabledRotationThisLife = false

announcedEntered = false
announcedPortrait = false
sawIntroBand = false

dutyBaselineTime = nil
baselineCaptured = false
timerMovedFromBaseline = false

portraitHelloThreshold = nil
portraitHelloSent = false
goodMatchSent = false
local resultsHandled = false
local resultsVisibleSince = nil
local lastResultsLeaveAttempt = 0
local resultsVnavStopped = false
completedMatches = 0
stopAfterCurrentMatch = false
limitStopTriggered = false
followUpIssued = false
local equipGearsetSlot = -1
local gearsetEquipped = false

local crystalSampleAt = 0
local crystalLastPosition = nil
local crystalVelocity = { x = 0, y = 0, z = 0 }
local crystalOffset = nil
local lastCrystalCommandTarget = nil

local function resetCrystalPrediction()
    crystalSampleAt = 0
    crystalLastPosition = nil
    crystalVelocity = { x = 0, y = 0, z = 0 }
    crystalOffset = nil
    lastCrystalCommandTarget = nil
end

local function updateCrystalPrediction()
    local now = os.clock()
    if now - crystalSampleAt < 0.2 then return nil end

    local x, y, z = objectPos(CRYSTAL_NAME)
    if x == nil then
        resetCrystalPrediction()
        return nil
    end

    if not crystalOffset then
        crystalOffset = { x = randInt(0, 2), z = randInt(0, 2) }
    end

    if crystalLastPosition then
        local dt = now - crystalSampleAt
        local dx = x - crystalLastPosition.x
        local dy = y - crystalLastPosition.y
        local dz = z - crystalLastPosition.z
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

        if dt <= 0 or dt > 1.0 or distance > 12 then
            crystalVelocity = { x = 0, y = 0, z = 0 }
        elseif distance < 0.05 then
            crystalVelocity = { x = 0, y = 0, z = 0 }
        else
            local vx, vy, vz = dx / dt, dy / dt, dz / dt
            local reverse = crystalVelocity.x * vx + crystalVelocity.y * vy + crystalVelocity.z * vz < 0
            if reverse then
                crystalVelocity = { x = vx, y = vy, z = vz }
            else
                local smoothing = 0.5
                crystalVelocity.x = crystalVelocity.x * (1 - smoothing) + vx * smoothing
                crystalVelocity.y = crystalVelocity.y * (1 - smoothing) + vy * smoothing
                crystalVelocity.z = crystalVelocity.z * (1 - smoothing) + vz * smoothing
            end
        end
    end

    crystalSampleAt = now
    crystalLastPosition = { x = x, y = y, z = z }

    local leadX = crystalVelocity.x * 0.8 + crystalOffset.x
    local leadY = crystalVelocity.y * 0.8
    local leadZ = crystalVelocity.z * 0.8 + crystalOffset.z
    local leadDistance = math.sqrt(leadX * leadX + leadY * leadY + leadZ * leadZ)
    if leadDistance > 10 then
        local scale = 10 / leadDistance
        leadX, leadY, leadZ = leadX * scale, leadY * scale, leadZ * scale
    end

    return x + leadX, y + leadY, z + leadZ
end

if GEARSET_SLOT >= 1 then
    equipGearsetSlot = math.floor(GEARSET_SLOT) - 1
end

local function equipConfiguredGearset()
    if gearsetEquipped then return true end

    local slot = tonumber(equipGearsetSlot)
    if slot == nil or slot < 0 then
        gearsetEquipped = true
        return true
    end

    local slotDisplay = slot + 1
    if not Player or not Player.GetGearset then
        Log("gearset equip requested but Player.GetGearset unavailable")
        return false
    end

    local gearset = Player.GetGearset(slot)
    if not gearset or gearset.IsValid ~= true then
        Log("configured gearset slot %d invalid or unavailable", slotDisplay)
        return false
    end

    local gearsetName = gearset.Name
    if gearsetName and gearsetName.GetText then
        local ok, resolved = pcall(function()
            return gearsetName:GetText()
        end)
        if ok and type(resolved) == "string" and resolved ~= "" then
            gearsetName = resolved
        end
    end
    gearsetName = tostring(gearsetName or ("Gearset " .. slotDisplay))

    Log("equipping gearset slot %d (%s)", slotDisplay, gearsetName)
    local ok, err = pcall(function()
        return gearset:Equip()
    end)
    if not ok then
        Log("failed to equip gearset slot %d: %s", slotDisplay, tostring(err))
        return false
    end

    yield("/wait 1")
    gearsetEquipped = true
    return true
end

local function isLifestreamBusy()
    if IPC and IPC.Lifestream and IPC.Lifestream.IsBusy then
        local ok, busy = pcall(IPC.Lifestream.IsBusy)
        return ok and busy == true
    end
    return false
end

local function runStartupLifestreamCommand()
    if LIFESTREAM_COMMAND == "" then return true end
    if not (IPC and IPC.Lifestream and IPC.Lifestream.ExecuteCommand) then
        Log("lifestream command configured but IPC unavailable")
        return false
    end

    Log("issuing lifestream command -> %s", LIFESTREAM_COMMAND)
    local executeOk, executeErr = pcall(function()
        IPC.Lifestream.ExecuteCommand(LIFESTREAM_COMMAND)
    end)
    if not executeOk then
        Log("lifestream command failed: %s", tostring(executeErr))
        return false
    end

    local started = WaitUntil(function()
        return GetCondition(CharacterCondition.casting, true)
            or GetCondition(CharacterCondition.betweenAreas, true)
            or GetCondition(CharacterCondition.betweenAreasForDuty, true)
            or isLifestreamBusy()
            or IsAddonVisible("FadeMiddle")
    end, 2.0, TIME.POLL, 0.0)

    if not started then
        Log("no lifestream activity detected after command; startup aborted")
        return false
    end

    Log("lifestream activity detected; waiting for zoning completion")
    local completed = WaitUntil(function()
        return (not IsAddonReady("FadeMiddle"))
            and (not isLifestreamBusy())
            and GetCondition(CharacterCondition.betweenAreas, false)
            and GetCondition(CharacterCondition.betweenAreasForDuty, false)
            and Player ~= nil
            and Player.Available == true
    end, 300.0, TIME.POLL, 1.0)

    if not completed then
        Log("lifestream zoning completion timed out")
        return false
    end

    Log("lifestream zoning complete")
    return true
end

local function runFollowUpScript()
    if followUpIssued or FOLLOW_UP_SCRIPT == "" then return false end
    WaitConditionStable(CharacterCondition.betweenAreas, false, 1.0, 30.0, TIME.POLL)
    WaitConditionStable(CharacterCondition.betweenAreasForDuty, false, 1.0, 30.0, TIME.POLL)
    WaitUntil(function()
        return Player ~= nil and Player.Available == true
    end, 10.0, TIME.POLL, 1.0)
    local sanitized = FOLLOW_UP_SCRIPT:gsub('"', '\\"')
    Log("running follow-up script -> %s", FOLLOW_UP_SCRIPT)
    yield(string.format('/snd run "%s"', sanitized))
    followUpIssued = true
    return true
end

local function inPvPArea()
    local terr = Svc and Svc.ClientState and Svc.ClientState.TerritoryType
    if terr and SAFE_ANCHORS[terr] ~= nil then return true end
    return GetCondition(CharacterCondition.pvpDisplayActive, true)
end

local function resetAllState(reason)
    inMatchLive = false
    ranSafetyMoveThisDuty = false
    lbTick = 0

    wasDead = false
    deadSince = 0
    rotationNeedsReset = false
    hasEnabledRotationThisLife = false

    announcedEntered = false
    announcedPortrait = false
    sawIntroBand = false
    dutyBaselineTime = nil
    baselineCaptured = false
    timerMovedFromBaseline = false

    portraitHelloThreshold = nil
    portraitHelloSent = false
    goodMatchSent = false
    resultsHandled = false
    resultsVisibleSince = nil
    lastResultsLeaveAttempt = 0
    resultsVnavStopped = false
    resetCrystalPrediction()

    if reason then Log("reset: %s", tostring(reason)) end
end

-- =========================================================
-- One-time start banner
-- =========================================================
if UI.ECHO_ON_START then
    _echoLine(_fmt("script starting"))
end
Log("script starting")
Log("match limit -> %d", MATCH_LIMIT)

-- =========================================================
-- Optional title flips
-- =========================================================
if SET_GARO_TITLES then
    Log("setting titles: %s -> %s", tostring(TITLE_1), tostring(TITLE_2))
    yield("/title set " .. TITLE_1); Sleep(3)
    yield("/title set " .. TITLE_2); Sleep(3)
end

local startupReady = equipConfiguredGearset()
if startupReady then
    startupReady = runStartupLifestreamCommand()
end

if startupReady then
    -- =========================================================
    -- Initial DF clicks
    -- =========================================================
    Instances.DutyFinder:QueueRoulette(40)
else
    Log("startup preparation failed -> not queueing")
    RUN_LOOP = false
end

-- =========================================================
-- Main loop
-- =========================================================
while RUN_LOOP do
    local inDuty = GetCondition(CharacterCondition.boundByDuty34, true)

    -- =====================================================
    -- Match-end detector
    -- =====================================================
    if inDuty then
        local resultsVisible = IsAddonVisible("MKSRecord")
        if resultsVisible then
            resultsVisibleSince = resultsVisibleSince or os.clock()
        else
            resultsVisibleSince = nil
        end
        local endScreenStable = resultsVisibleSince ~= nil
            and (os.clock() - resultsVisibleSince) >= 0.25

        if endScreenStable then
            if not resultsHandled then
                resultsHandled = true
                completedMatches = completedMatches + 1
                if MATCH_LIMIT > 0 then
                    Log("completed match %d/%d", completedMatches, MATCH_LIMIT)
                    if completedMatches >= MATCH_LIMIT then
                        stopAfterCurrentMatch = true
                        limitStopTriggered = true
                    end
                else
                    Log("completed match %d", completedMatches)
                end

                if SEND_GOOD_MATCH_ON_RESULTS and not goodMatchSent then
                    yield('/quickchat "Good Match"')
                    goodMatchSent = true
                    Log("quickchat Good Match requested on results screen")
                end
            end

            if not resultsVnavStopped then
                yield("/vnav stop")
                resultsVnavStopped = true
            end

            if os.clock() - lastResultsLeaveAttempt >= 2.0 then
                Log("match ended (MKSRecord visible) -> leaving duty")
                if InstancedContent and InstancedContent.LeaveCurrentContent then
                    pcall(function() InstancedContent.LeaveCurrentContent() end)
                else
                    Log("ERROR: InstancedContent.LeaveCurrentContent unavailable")
                end
                lastResultsLeaveAttempt = os.clock()
            end

            Sleep(0.2)
            goto continue_loop
        end
    end

    -- =====================================================
    -- Out of duty: reset + queue
    -- =====================================================
    if not inDuty then
        if inMatchLive or announcedEntered or ranSafetyMoveThisDuty or baselineCaptured or resultsHandled then
            resetAllState("out of duty")
        end

        if stopAfterCurrentMatch then
            Log("match limit reached -> stopping script")
            RUN_LOOP = false
            goto continue_loop
        end

        Sleep(5.0)

        if GetCondition(CharacterCondition.inDutyQueue, true) == false then
            Log("not queued -> opening duty finder")
            Instances.DutyFinder:QueueRoulette(40)
        end

        Sleep(0.5)
        goto continue_loop
    end

    -- =====================================================
    -- On duty: wait until actually in PvP area before baseline
    -- =====================================================
    if inDuty and not baselineCaptured then
        yield("/vnav stop")
        Log("in duty -> waiting for PvP area before baseline capture")

        WaitUntil(function()
            return inPvPArea()
        end, 90.0, TIME.POLL, 0.5)

        dutyBaselineTime = contentTimeLeft()
        baselineCaptured = true
        timerMovedFromBaseline = false
        sawIntroBand = false
        announcedEntered = false
        announcedPortrait = false
        inMatchLive = false
        ranSafetyMoveThisDuty = false
        hasEnabledRotationThisLife = false

        portraitHelloThreshold = randInt(1, 29)
        portraitHelloSent = false

        Log("duty entry baseline ContentTimeLeft -> %s", tostring(dutyBaselineTime))
        Log("portrait hello threshold set -> %ds", tostring(portraitHelloThreshold))
    end

    -- =====================================================
    -- Waiting phase: portraits + gate
    -- =====================================================
    while inDuty and not inMatchLive do
        checkDeathAndReapplyRotation()

        if not announcedEntered then
            Log("entered PvP match; waiting for portraits + gate (ContentTimeLeft)")
            yield("/vnav stop")
            announcedEntered = true
        end

        local tLeft = contentTimeLeft()

        if dutyBaselineTime ~= nil and tLeft > 0 then
            if math.abs(tLeft - dutyBaselineTime) >= 10 then
                timerMovedFromBaseline = true
            end
        end

        if tLeft < 32 and tLeft > 1 then
            sawIntroBand = true
            if not announcedPortrait then
                Log("Intro/portraits phase detected (timer ~31s)")
                announcedPortrait = true
            end

            if SEND_HELLO_ON_ENTRY
                and (not portraitHelloSent)
                and portraitHelloThreshold ~= nil
                and tLeft <= portraitHelloThreshold
                and tLeft > 1
            then
                yield("/quickchat Hello")
                portraitHelloSent = true
                Log("quickchat Hello sent at tLeft=%.1f (threshold=%ds)", tonumber(tLeft) or 0, tonumber(portraitHelloThreshold) or 0)
            end

            yield("/vnav stop")
            Sleep(1.0)
        else
            local gateOpen = (tLeft > 100 and (sawIntroBand or timerMovedFromBaseline))
            if gateOpen then
                Log("Gate open detected by ContentTimeLeft -> %s", tostring(tLeft))
                inMatchLive = true
                enemyNames = refreshEnemyNames()

                yield("/rotation Settings TargetingTypes add Nearest")
                Sleep(TIME.POLL)
                yield("/rotation auto nearest")
                hasEnabledRotationThisLife = true
                rotationNeedsReset = false
                Log("rotation enabled (match start)")
                break
            end
            Sleep(0.10)
        end

        inDuty = GetCondition(CharacterCondition.boundByDuty34, true)
    end

    -- =====================================================
    -- Live match behavior
    -- =====================================================
    if inMatchLive then
        checkDeathAndReapplyRotation()
        if not isDead() then
            ClearEnemySignTarget()
        end

        if isNormal() and not isDead() and not hasEnabledRotationThisLife then
            yield("/rotation auto nearest")
            hasEnabledRotationThisLife = true
            Log("rotation enabled (live failsafe)")
        end
        if isDead() then
            hasEnabledRotationThisLife = false
        end

        local territoryId = Svc.ClientState.TerritoryType

        local shouldHold = false
        local crystalDistance = distToName(CRYSTAL_NAME)
        local crystalNear = crystalDistance ~= nil and crystalDistance < 10
        if crystalNear then
            local unresolvedEnemy = false
            for i = 1, 5 do
                if not enemyNames[i] then
                    unresolvedEnemy = true
                else
                    local enemyDistance = distToName(enemyNames[i])
                    if enemyDistance and enemyDistance < 10 then
                        shouldHold = true
                        break
                    end
                end
            end
            if unresolvedEnemy then
                enemyNames = refreshEnemyNames()
            end
        end

        if not shouldHold then
            local tx, ty, tz = updateCrystalPrediction()
            if tx ~= nil then
                local target = { x = tx, y = ty, z = tz }
                local movedEnough = not lastCrystalCommandTarget
                    or distBetween(target.x, target.y, target.z,
                        lastCrystalCommandTarget.x, lastCrystalCommandTarget.y, lastCrystalCommandTarget.z) >= 0.75
                if movedEnough then
                    yield(string.format("/vnavmesh moveto %f %f %f", tx, ty, tz))
                    lastCrystalCommandTarget = target
                end
            end
        else
            -- Continue sampling while holding so velocity prediction stays current.
            updateCrystalPrediction()
        end

        local spawnSide = -1
        while hasStatus(895) and inDuty and spawnSide == -1 and inMatchLive do
            checkDeathAndReapplyRotation()
            if not hasStatus(1342) then yield("/pvpac sprint") end
            yield("/vnav stop")

            local anchors = SAFE_ANCHORS[territoryId]
            if anchors then
                local dA = distToXYZ(anchors[1], anchors[2], anchors[3])
                local dB = distToXYZ(anchors[4], anchors[5], anchors[6])

                if dA < 40 then spawnSide = 0 end
                if dB < 40 then spawnSide = 3 end

                if spawnSide > -1 then
                    ranSafetyMoveThisDuty = true
                    yield(string.format("/vnavmesh moveto %f %f %f",
                        anchors[1 + spawnSide],
                        anchors[2 + spawnSide],
                        anchors[3 + spawnSide]
                    ))
                end
            end

            Sleep(0.30)
            inDuty = GetCondition(CharacterCondition.boundByDuty34, true)
        end

        lbTick = lbTick + 1
        if lbTick > 14 and inDuty and not isDead() then
            lbTick = 0
            local jobId = classJobId()
            for i = 1, #LIMIT_BREAK_BY_JOB do
                if jobId == LIMIT_BREAK_BY_JOB[i].job then
                    yield("/pvpac \"" .. LIMIT_BREAK_BY_JOB[i].name .. "\"")
                    Sleep(0.10)
                end
            end
        end
    end

    Sleep(0.20)
    ::continue_loop::
end

if limitStopTriggered then
    runFollowUpScript()
end
