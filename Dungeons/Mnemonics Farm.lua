--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.0.0
description: |
  Run selected dungeons repeatedly to farm Mnemonics up to cap.
  Open AutoDuty and pick your trust party to run dungeons with then close it.
plugin_dependencies:
- AutoDuty
configs:
  Mnemonics Cap:
    description: Hard cap for Mnemonics to farm (max 450).
    default: 450
    min: 0
    max: 450
  Dungeon:
    description: The dungeon AutoDuty should run.
    default: "Mistwake"
    is_choice: true
    choices: ["Mistwake", "The Meso Terminal", "The Underkeep", "Yuweyawata Field Station", "Alexandria"]
  Pause for AutoRetainer:
    description: |
      Pause the script while AutoRetainer handles retainer interactions.
      This script does not interact with retainers; AutoRetainer MultiMode or RetainerSense must be enabled for processing.
    default: true
  Enable AutoRetainer MultiMode:
    description: Enable AutoRetainer MultiMode when the script completes.
    default: true
[[End Metadata]]
--]=====]

-- =========================================================
-- Config
-- =========================================================
echoLog = false
PREFIX  = "[Mnemonics Farmer]"
closeRetainer = true

-- ==============================================================
-- Echo / Log Helpers
-- ==============================================================
local function _echo(s)
    yield("/echo " .. tostring(s))
end

local function _log(s)
    local msg = tostring(s)
    Dalamud.Log(msg)
    if echoLog then _echo(msg) end
end

local function _fmt(msg, ...)
    return string.format("%s %s", PREFIX, string.format(msg, ...))
end

function Logf(msg, ...)   _log(_fmt(msg, ...))  end
function Echof(msg, ...)  _echo(_fmt(msg, ...)) end

Log,  log  = Logf,  Logf
Echo, echo = Echof, Echof

function EchoOnce(msg, ...)
    if echoLog then
        Log(msg, ...)
    else
        Echo(msg, ...)
        Log(msg, ...)
    end
end

-- =========================================================
-- Timing constants + Sleep
-- =========================================================
TIME = {
    POLL    = 0.10,
    TIMEOUT = 10.0,
    STABLE  = 0.30
}

local function _sleep(seconds)
    local s = tonumber(seconds) or 0
    if s < 0 then s = 0 end
    s = math.floor(s * 10 + 0.5) / 10
    yield("/wait " .. s)
end

Sleep, sleep = _sleep, _sleep

-- =========================================================
-- Number helper (parsing + optional clamping)
-- =========================================================
function toNumberSafe(s, default, min, max)
    if s == nil then return default end
    local str = tostring(s):gsub("[^%d%-%.]", "")
    local n = tonumber(str)
    if n == nil then return default end
    if min ~= nil and n < min then n = min end
    if max ~= nil and n > max then n = max end
    return n
end

-- =========================================================
-- Addon Helpers
-- =========================================================
local function _get_addon(name)
    local ok, addon = pcall(Addons.GetAddon, name)
    if ok and addon ~= nil then return addon end
    return nil
end

function IsAddonVisible(name)
    local addon = _get_addon(name)
    return addon and addon.Exists or false
end

-- =========================================================
-- WaitUntil Helper
-- =========================================================
function WaitUntil(predicateFn, timeoutSec, pollSec, stableSec)
    timeoutSec = toNumberSafe(timeoutSec, TIME.TIMEOUT, 0.1)
    pollSec    = toNumberSafe(pollSec,    TIME.POLL,   0.01)
    stableSec  = toNumberSafe(stableSec,  TIME.STABLE, 0.0)

    local start     = os.clock()
    local holdStart = nil

    while (os.clock() - start) < timeoutSec do
        local ok, res = pcall(predicateFn)
        if ok and res then
            if not holdStart then holdStart = os.clock() end
            if (os.clock() - holdStart) >= stableSec then return true end
        else
            holdStart = nil
        end
        sleep(pollSec)
    end
    return false
end

function WaitAddonStable(addonName, stableSec, timeoutSec, pollSec)
    return WaitUntil(function()
        local addon = _get_addon(addonName)
        return addon and addon.Exists
    end, timeoutSec or TIME.TIMEOUT, pollSec or TIME.POLL, stableSec or 2.0)
end

-- =========================================================
-- Character / Conditions
-- =========================================================
CharacterCondition = {
    occupiedSummoningBell = 50,
    boundByDuty34         = 34,
    boundByDuty56         = 56,
}

function GetCharacterCondition(i, bool)
    if bool == nil then bool = true end
    return Svc and Svc.Condition and (Svc.Condition[i] == bool) or false
end

local function InDuty()
    return GetCharacterCondition(CharacterCondition.boundByDuty34, true)
        or GetCharacterCondition(CharacterCondition.boundByDuty56, true)
end

local function AtSummoningBell()
    return GetCharacterCondition(CharacterCondition.occupiedSummoningBell, true)
end

-- =========================================================
-- Safe Callback
-- =========================================================
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
        end
    end

    if IsAddonVisible(addon) then
        yield(call)
        return true
    end
    return false
end

-- =========================================================
-- Plugin Helpers
-- =========================================================
local function CloseRetainerList()
    if IsAddonVisible("RetainerSellList") then
        SafeCallback("RetainerSellList", true, -1)
        sleep(TIME.STABLE)
    end

    if IsAddonVisible("SelectString") then
        SafeCallback("SelectString", true, -1)
        sleep(TIME.STABLE)
    end

    local tries = 0
    while IsAddonVisible("RetainerList") and tries < 80 do
        SafeCallback("RetainerList", true, -1)
        sleep(TIME.STABLE)
        tries = tries + 1
    end

    return not IsAddonVisible("RetainerList")
end

-- =========================================================
-- Trigger Events
-- =========================================================
function OnStop()
end

-- =========================================================
-- Variable State + Tables
-- =========================================================
local DungList = {
    {name = "Mistwake",                 id = 1314, amount = 50},
    {name = "The Meso Terminal",        id = 1292, amount = 50},
    {name = "The Underkeep",            id = 1266, amount = 30},
    {name = "Yuweyawata Field Station", id = 1242, amount = 20},
    {name = "Alexandria",               id = 1199, amount = 20},
}

local DungMap = {}
for i = 1, #DungList do
    local t = DungList[i]
    DungMap[t.name] = { id = t.id, amount = t.amount }
end

-- Config reads
local mnemonicsCap      = toNumberSafe(Config.Get("Mnemonics Cap"), 450, 0, 450)
local dungeonPick       = tostring(Config.Get("Dungeon") or "Mistwake")
local pauseAutoRetainer = (Config.Get("Pause for AutoRetainer") ~= false)
local multiMode         = (Config.Get("Enable AutoRetainer MultiMode") ~= false)

local DungeonToDo       = (DungMap[dungeonPick] and DungMap[dungeonPick].id or 0)
local MnemonicsFromDung = (DungMap[dungeonPick] and DungMap[dungeonPick].amount or 0)

-- IDs
local MNEMONICS_ITEM_ID = 49

-- =========================================================
-- AutoDuty helpers
-- =========================================================
local function IsAutoDutyRunning()
    return IPC and IPC.AutoDuty and (not IPC.AutoDuty.IsStopped())
end

local function StopAutoDuty()
    if IPC and IPC.AutoDuty and IPC.AutoDuty.Stop then
        IPC.AutoDuty.Stop()
        sleep(TIME.POLL)
    end
    return true
end

local function MnemonicsOnHand()
    return tonumber(Inventory.GetItemCount(MNEMONICS_ITEM_ID)) or 0
end

local function RunsToGo()
    local perRun = tonumber(MnemonicsFromDung) or 0
    if perRun <= 0 then return 0 end
    local remaining = mnemonicsCap - MnemonicsOnHand()
    if remaining <= 0 then return 0 end
    return math.ceil(remaining / perRun)
end

local function StartAutoDuty()
    if not (IPC and IPC.AutoDuty and IPC.AutoDuty.Run) then
        Log("StartAutoDuty: AutoDuty IPC missing")
        return false
    end
    IPC.AutoDuty.Run(DungeonToDo, RunsToGo(), false)
    sleep(TIME.POLL)
    return true
end

-- =========================================================
-- AutoRetainer readiness
-- =========================================================
local function IsRetainerWorkPending()
    if not (IPC and IPC.AutoRetainer and IPC.AutoRetainer.AreAnyRetainersAvailableForCurrentChara) then
        return false
    end
    return IPC.AutoRetainer.AreAnyRetainersAvailableForCurrentChara() == true
end

local function WaitRetainersFinished()
    Log("waiting for AutoRetainer to finish")
    WaitUntil(function()
        return not IsRetainerWorkPending()
    end, 999999, TIME.POLL, 1)
    Log("AutoRetainer finished")
    return true
end

-- =========================================================
-- STATE MACHINE
-- =========================================================
STATE = {
    READY        = "READY",
    RUN_AUTODUTY = "RUN_AUTODUTY",
    WAIT_BELL    = "WAIT_BELL",
    DONE         = "DONE",
    FAIL         = "FAIL",
}

local sm = { s = STATE.READY, t0 = os.clock() }

local function gotoState(s)
    sm.s = s
    sm.t0 = os.clock()
    Log("STATE -> %s", s)
end

-- =========================================================
-- Main Loop
-- =========================================================
EchoOnce("Starting Mnemonics Farmer script.")

while sm.s ~= STATE.DONE and sm.s ~= STATE.FAIL do
    if sm.s == STATE.READY then
        if (AtSummoningBell() or IsRetainerWorkPending()) and pauseAutoRetainer then
            Log("READY: bell/retainer active; entering WAIT_BELL")
            gotoState(STATE.WAIT_BELL)
            goto continue
        end

        if IsAutoDutyRunning() then
            Sleep(TIME.POLL)
            goto continue
        end

        if MnemonicsOnHand() >= mnemonicsCap then
            Log("READY: cap reached (%d/%d)", MnemonicsOnHand(), mnemonicsCap)
            gotoState(STATE.DONE)
        elseif RunsToGo() > 0 then
            gotoState(STATE.RUN_AUTODUTY)
        else
            gotoState(STATE.DONE)
        end

    elseif sm.s == STATE.RUN_AUTODUTY then
        Log("Starting AutoDuty: dungeon=%s runs=%d", dungeonPick, RunsToGo())
        if StartAutoDuty() then
            Sleep(TIME.STABLE)
            gotoState(STATE.READY)
        else
            gotoState(STATE.FAIL)
        end

    elseif sm.s == STATE.WAIT_BELL then
        if InDuty() then
            Log("WAIT_BELL: in duty (34/56); waiting for duty flags to clear")
            while InDuty() do
                Sleep(TIME.POLL)
            end
            Sleep(TIME.STABLE)
        end

        if IsAutoDutyRunning() then
            Log("WAIT_BELL: AutoDuty running; stopping it")
            StopAutoDuty()
            Sleep(TIME.STABLE)
        end

        if IsRetainerWorkPending() then
            WaitRetainersFinished()
            Sleep(TIME.POLL)
            goto continue
        end

        if closeRetainer and WaitAddonStable("RetainerList", TIME.STABLE, 10, TIME.POLL) then
            CloseRetainerList()
        elseif not closeRetainer then
            WaitUntil(function() return not AtSummoningBell() end, 999999, TIME.POLL, 1)
        end

        WaitUntil(function() return not AtSummoningBell() end, 999999, TIME.POLL, 1)

        Log("WAIT_BELL: cleared (no bell, no retainer work); returning to READY")
        Sleep(TIME.STABLE)
        gotoState(STATE.READY)
    end

    ::continue::
    Sleep(TIME.POLL)
end

if multiMode then
    if IPC and IPC.AutoRetainer and IPC.AutoRetainer.SetMultiModeEnabled then
        IPC.AutoRetainer.SetMultiModeEnabled(true)
        Log("AutoRetainer MultiMode enabled")
    end
end

EchoOnce("STATE MACHINE EXIT: %s", sm.s)
