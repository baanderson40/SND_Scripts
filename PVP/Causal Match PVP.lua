--[=====[
[[SND Metadata]]
author: baanderson40
version: 0.0.5
description: PvP script - Inspired by Dhog
plugin_dependencies:
- vnavmesh
- RotationSolver

[[End Metadata]]
--]=====]
--[[
Logging policy (standardized):
- Everything logs to Dalamud with [PVP] prefix.
- Only echo once on script start.

Queueing:
- If not in duty and not in duty queue, open Duty Finder and callback.

Gate detection (ContentTimeLeft method, hardened + fixed for requeue):
- Do NOT treat tLeft < 5 as gate open (tLeft can be 0 while zoning / before PvP area)
- Only capture baseline AFTER we are actually in the PvP area (pvpDisplayActive) OR in a known PvP territory
- Detect intro/portrait band: 1 < t < 32  (sawIntroBand = true)
- Gate open / match live when:
    t > 100 AND (sawIntroBand OR timerMovedFromBaseline)

Portrait quickchat:
- During portraits, pick a random threshold between 5..29 seconds remaining.
- Fire /quickchat Hello once when tLeft drops to/below that threshold (and still > 5).

Match end:
- When MKSRecord addon becomes visible at end of match, call InstancedContent.LeaveCurrentContent() to exit duty.

Other:
- /rotation auto nearest is re-applied after death/respawn because RSR disables it.

--]]

-- =========================================================
-- PvP Utilities (Log/Sleep/WaitUntil/Addons/Conditions)
-- =========================================================
import("System.Numerics")

local UI = {
    PREFIX = "[PVP]",
    ECHO_ON_START = true, -- only echo once at script start
    ECHO_TO_CHAT = false,  -- NOTE: this echoes ALL logs; if you truly want only 1 echo, set false
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

-- REQUIRED: AwaitAddonReady
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

-- REQUIRED: SafeCallback
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

    -- Optional "update" argument (boolean/string). If not provided, default true.
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
    boundByDuty34    = 34,
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

local SET_GARO_TITLES = true
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

local function classJobId()
    local lp = Svc and Svc.ClientState and Svc.ClientState.LocalPlayer
    if lp and lp.ClassJob then return lp.ClassJob.RowId end
    return 0
end

local function objectPos(name)
    if not (Entity and Entity.GetEntityByName) then return 0, 0, 0 end
    local e = Entity.GetEntityByName(name)
    if not (e and e.Position) then return 0, 0, 0 end
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
    return distToXYZ(x2,y2,z2)
end

local function statusRemaining(statusId)
    local lp = Svc and Svc.ClientState and Svc.ClientState.LocalPlayer
    if not lp then return 0 end
    local list = lp.StatusList
    if not list then return 0 end
    for i = 0, list.Length - 1 do
        local s = list[i]
        if s and s.StatusId == statusId then
            return s.RemainingTime or 0
        end
    end
    return 0
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
-- Enemy extraction (always returns strings)
-- =========================================================
local function getEnemyName(slotIndex)
    if not IsAddonReady("PvPMKSPartyList3") then
        return myName()
    end

    local addon = Addons.GetAddon("PvPMKSPartyList3")
    local node = addon:GetNode(1, 5, slotIndex, 6, 18, 21)

    if type(node) == "table" and node.Text ~= nil and tostring(node.Text) ~= "" then
        return tostring(node.Text)
    end

    if type(node) == "userdata" then
        local ok, txt = pcall(function() return node.Text end)
        if ok and txt ~= nil and tostring(txt) ~= "" then
            return tostring(txt)
        end
    end

    return myName()
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

-- gate detection state
announcedEntered = false
announcedPortrait = false
sawIntroBand = false

dutyBaselineTime = nil
baselineCaptured = false
timerMovedFromBaseline = false

-- NEW: portrait quickchat threshold state
portraitHelloThreshold = nil   -- number in [5..29]
portraitHelloSent = false

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

    -- reset portrait hello
    portraitHelloThreshold = nil
    portraitHelloSent = false

    if reason then Log("reset: %s", tostring(reason)) end
end

-- =========================================================
-- One-time start banner
-- =========================================================
if UI.ECHO_ON_START then
    _echoLine(_fmt("script starting"))
end
Log("script starting")

-- =========================================================
-- Optional title flips
-- =========================================================
if SET_GARO_TITLES then
    Log("setting titles: %s -> %s", tostring(TITLE_1), tostring(TITLE_2))
    yield("/title set " .. TITLE_1); Sleep(3)
    yield("/title set " .. TITLE_2); Sleep(3)
end

-- =========================================================
-- Initial DF clicks (as you had)
-- =========================================================
yield("/dutyfinder")
AwaitAddonReady("ContentsFinder")
SafeCallback("ContentsFinder", 12, 1)
Sleep(1)
SafeCallback("ContentsFinder", 1, 8)
Sleep(.7)
SafeCallback("ContentsFinder", 3, 1)
Sleep(.5)
SafeCallback("ContentsFinder", -1)

-- =========================================================
-- Main loop
-- =========================================================
while RUN_LOOP do
    local inDuty = GetCondition(CharacterCondition.boundByDuty34, true)

    -- =====================================================
    -- Match-end detector: if MKSRecord is visible, leave duty
    -- =====================================================
    if inDuty then
        local endScreenStable = WaitUntil(function()
            return IsAddonVisible("MKSRecord")
        end, 0.5, 0.10, 0.25)

        if endScreenStable then
            Log("match ended (MKSRecord visible) -> leaving duty")
            yield("/vnav stop")

            if InstancedContent and InstancedContent.LeaveCurrentContent then
                pcall(function() InstancedContent.LeaveCurrentContent() end)
            else
                Log("ERROR: InstancedContent.LeaveCurrentContent unavailable")
            end

            Sleep(2.0)
            resetAllState("left duty (post-match)")
            goto continue_loop
        end
    end

    -- =====================================================
    -- Out of duty: reset + queue
    -- =====================================================
    if not inDuty then
        if inMatchLive or announcedEntered or ranSafetyMoveThisDuty or baselineCaptured then
            resetAllState("out of duty")
        end

        Sleep(5.0)

        if GetCondition(CharacterCondition.inDutyQueue, true) == false then
            Log("not queued -> opening duty finder")
            yield("/dutyfinder")

            if AwaitAddonReady("ContentsFinder", 10.0) then
                SafeCallback("ContentsFinder", 12, 0)
            else
                Log("ERROR: ContentsFinder not ready after /dutyfinder")
            end
        else
            if AwaitAddonReady("ContentsFinderConfirm", 30) then
                SafeCallback("ContentsFinderConfirm", 8)
            end
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

        -- NEW: pick hello threshold for this duty (5..29 inclusive) and reset sent flag
        portraitHelloThreshold = randInt(5, 29)
        portraitHelloSent = false

        Log("duty entry baseline ContentTimeLeft -> %s", tostring(dutyBaselineTime))
        Log("portrait hello threshold set -> %ds", tostring(portraitHelloThreshold))
    end

    -- =====================================================
    -- Waiting phase: portraits + gate (ContentTimeLeft method)
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

            -- NEW: during portraits, send Hello once when timer drops to/below threshold, but still above 5
            if (not portraitHelloSent)
                and portraitHelloThreshold ~= nil
                and tLeft <= portraitHelloThreshold
                and tLeft > 5
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
        local crystalNear = distToName(CRYSTAL_NAME) < 10
        if crystalNear then
            for i = 1, 5 do
                if distToName(enemyNames[i]) < 10 then
                    shouldHold = true
                    break
                end
            end
        end

        if not shouldHold then
            local cx, cy, cz = objectPos(CRYSTAL_NAME)
            local rX = randInt(0, 2)
            local rZ = randInt(0, 2)
            yield(string.format("/vnavmesh moveto %f %f %f", cx + rX, cy, cz + rZ))
        end

        local spawnSide = -1
        while (statusRemaining(895) > 0.1) and inDuty and spawnSide == -1 and inMatchLive do
            checkDeathAndReapplyRotation()
            yield("/pvpac sprint")
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

            Sleep(0.10)
            inDuty = GetCondition(CharacterCondition.boundByDuty34, true)
        end

        lbTick = lbTick + 1
        if lbTick > 5 and inDuty then
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

    Sleep(0.50)
    ::continue_loop::
end
