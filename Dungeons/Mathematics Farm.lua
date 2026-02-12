--[=====[
[[SND Metadata]]
author: baanderson40
version: 0.1.1
description: |
  Run Mathematics tome dungeons repeatedly and auto-purchase Phantom relic arcanite items.
  Open AutoDuty and pick your trust party to run dungeons with then close it.
plugin_dependencies:
- AutoDuty
- Lifestream
- vnavmesh
configs:
  Mathematics Tome Limit:
    description: The number of Mathematics tomes to gather before spending them.
    default: 1500
    min: 500
    max: 2000
  Max Purchase Cycles:
    description: How many times the script should spend tomes before stopping. Set to 0 for unlimited.
    default: 1
  Dungeon:
    description: The dungeon AutoDuty should run..
    default: "Mistwake"
    is_choice: true
    choices: ["Mistwake", "The Meso Terminal", "The Underkeep", "Yuweyawata Field Station", "Alexandria"]
  Arcanite type:
    description: The type of arcanite to purchase with tomes.
    default: "Waning Arcanite"
    is_choice: true
    choices: ["Waning Arcanite", "Waxing Arcanite", "Arcanite"]
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
import("System.Numerics")
echoLog = false
PREFIX  = "[Mathematics Farmer]"
closeRetainer = true

-- ==============================================================
-- Echo / Log Helpers (ALL code should call Log(...) / Echo(...))
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
    local s = seconds
    if s == nil then s = 0 end
    s = tonumber(s) or 0
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

function IsAddonReady(name)
    local addon = _get_addon(name)
    return addon and addon.Ready or false
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

function AwaitAddonReady(name, timeoutSec)
    Log("awaiting ready: %s", tostring(name))
    local ok = WaitUntil(function()
        local addon = _get_addon(name)
        return addon and addon.Ready
    end, timeoutSec or TIME.TIMEOUT, TIME.POLL, 0.0)
    if not ok then Log("AwaitAddonReady timeout: %s", tostring(name)) end
    return ok
end

function AwaitAddonVisible(name, timeoutSec)
    Log("awaiting visible: %s", tostring(name))
    local ok = WaitUntil(function()
        local addon = _get_addon(name)
        return addon and addon.Exists
    end, timeoutSec or TIME.TIMEOUT, TIME.POLL, 0.0)
    if not ok then Log("AwaitAddonVisible timeout: %s", tostring(name)) end
    return ok
end

function WaitAddonStable(addonName, stableSec, timeoutSec, pollSec)
    return WaitUntil(function()
        local addon = _get_addon(addonName)
        return addon and addon.Exists
    end, timeoutSec or TIME.TIMEOUT, pollSec or TIME.POLL, stableSec or 2.0)
end

-- =========================================================
-- Character / Zone / Conditions
-- =========================================================
CharacterCondition = {
    casting               = 27,
    occupiedInQuestEvent  = 32,
    betweenAreas          = 45,
    occupiedSummoningBell = 50,
    betweenAreasForDuty   = 51,
    boundByDuty34         = 34,
    boundByDuty56         = 56,
}

function GetCharacterCondition(i, bool)
    if bool == nil then bool = true end
    return Svc and Svc.Condition and (Svc.Condition[i] == bool) or false
end

function GetZoneId()
    local cs = Svc and Svc.ClientState
    return cs and cs.TerritoryType or nil
end

function WaitZoneChange()
    sleep(1.0)
    while GetCharacterCondition(CharacterCondition.casting, true)
       or GetCharacterCondition(CharacterCondition.betweenAreas, true)
       or GetCharacterCondition(CharacterCondition.betweenAreasForDuty, true)
       or GetCharacterCondition(CharacterCondition.occupiedInQuestEvent, true)
       or Player.IsBusy do
        sleep(TIME.POLL)
    end
    sleep(1.0)
    return true
end

local function InDuty()
    return GetCharacterCondition(CharacterCondition.boundByDuty34, true)
        or GetCharacterCondition(CharacterCondition.boundByDuty56, true)
end

local function AtSummoningBell()
    return GetCharacterCondition(CharacterCondition.occupiedSummoningBell, true)
end

-- =========================================================
-- Interaction Helper
-- =========================================================
function InteractByName(name, timeout)
    if type(name) ~= "string" or name == "" then
        Log("InteractByName: invalid name '%s'", tostring(name)); return false
    end
    timeout = toNumberSafe(timeout, 5, 0.1)

    local e = Entity and Entity.GetEntityByName and Entity.GetEntityByName(name)
    if not e then
        Log("InteractByName: entity not found '%s'", name); return false
    end

    local start = os.clock()
    while (os.clock() - start) < timeout do
        e:SetAsTarget()
        sleep(TIME.POLL)
        local tgt = Entity and Entity.Target
        if tgt and tgt.Name == name then
            e:Interact()
            return true
        end
        sleep(TIME.POLL)
    end
    Log("InteractByName: timeout '%s'", name)
    return false
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
        Log("SafeCallback: invalid addon name"); return false
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

    Log("calling: %s", call)
    if IsAddonReady(addon) and IsAddonVisible(addon) then
        yield(call)
        return true
    end
    Log("SafeCallback: addon not ready/visible: %s", addon)
    return false
end

-- =========================================================
-- VNAV Helpers
-- =========================================================
function PathandMoveVnav(dest, fly)
    fly = (fly == true)
    local t, timeout = 0, TIME.TIMEOUT
    while not IPC.vnavmesh.IsReady() and t < timeout do
        sleep(TIME.POLL); t = t + TIME.POLL
    end
    if not IPC.vnavmesh.IsReady() then
        Log("VNAV not ready (timeout)")
        return false
    end

    local ok = IPC.vnavmesh.PathfindAndMoveTo(dest, fly)
    if not ok then Log("VNAV pathfind failed") end
    return ok and true or false
end

function StopCloseVnav(dest, stopDistance)
    stopDistance = tonumber(stopDistance) or 3.0
    if not dest then return false end

    local t, timeout = 0, TIME.TIMEOUT
    while not IPC.vnavmesh.IsRunning() and t < timeout do
        sleep(TIME.POLL); t = t + TIME.POLL
    end
    if not IPC.vnavmesh.IsRunning() then
        Log("VNAV not running (timeout)")
        return false
    end

    while IPC.vnavmesh.IsRunning() do
        local me = Entity and Entity.Player
        if me and me.Position then
            if Vector3.Distance(me.Position, dest) < stopDistance then
                StopVNAV()
                return true
            end
        end
        sleep(TIME.POLL)
    end
    return false
end

function MoveNearVnav(dest, stopDistance, fly)
    stopDistance = tonumber(stopDistance) or 3.0
    if PathandMoveVnav(dest, fly) then
        return StopCloseVnav(dest, stopDistance)
    end
    return false
end

function StopVNAV()
    if IPC.vnavmesh.BuildProgress() or IPC.vnavmesh.IsRunning() then IPC.vnavmesh.Stop() end
end

-- =========================================================
-- Plugin Helpers
-- =========================================================

local function EnableAutoRetainer()
    Log("enabling AutoRetainer")
    yield("/ays e")
    sleep(TIME.STABLE)
    return true
end

local function CloseRetainerList()
    Log("CloseRetainerList: begin")

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

    if IsAddonVisible("RetainerList") then
        Log("CloseRetainerList: RetainerList still open after attempts")
        return false
    end

    Log("CloseRetainerList: done (RetainerList closed)")
    return true
end

-- =========================================================
-- Trigger Events
-- =========================================================
function OnStop()
    StopVNAV()
end

-- =========================================================
-- Excel Sheet Lookups (guarded, return {ok,value|err})
-- =========================================================
local function ok(v)  return true, v end
local function err(m) return false, tostring(m or "unknown error") end

function GetENpcResidentName(dataId)
    local id = toNumberSafe(dataId, nil)
    if not id then return err("ENpcResident: invalid id '"..tostring(dataId).."'") end

    local sheet = Excel.GetSheet("ENpcResident")
    if not sheet then return err("ENpcResident sheet not available") end

    local row = sheet:GetRow(id)
    if not row then return err("ENpcResident: no row for id "..tostring(id)) end

    local name = row.Singular or row.Name
    if not name or name == "" then return err("ENpcResident: name missing for id "..tostring(id)) end

    return ok({ name = tostring(name), source = "ENpcResident", id = id })
end

-- =========================================================
-- Variable State + Tables
-- =========================================================
local ArcaniteTypes  = {
    {name = "Arcanite",         id = 1},
    {name = "Waxing Arcanite",  id = 0},
    {name = "Waning Arcanite",  id = 2}
}

local DungList = {
    {name = "Mistwake",                 id = 1314, amount = 80},
    {name = "The Meso Terminal",        id = 1292, amount = 80},
    {name = "The Underkeep",            id = 1266, amount = 80},
    {name = "Yuweyawata Field Station", id = 1242, amount = 60},
    {name = "Alexandria",               id = 1199, amount = 50},
}

local ArcaniteMap = {}
for i = 1, #ArcaniteTypes do
    local t = ArcaniteTypes[i]
    ArcaniteMap[t.name] = t.id
end

local DungMap = {}
for i = 1, #DungList do
    local t = DungList[i]
    DungMap[t.name] = { id = t.id, amount = t.amount }
end

-- Config reads
local mathematicsLimit    = toNumberSafe(Config.Get("Mathematics Tome Limit"), 1500, 0)
local maxPurchases        = toNumberSafe(Config.Get("Max Purchase Cycles"), 0, 0)
local arcanitePick        = tostring(Config.Get("Arcanite type") or "Waning Arcanite")
local dungeonPick         = tostring(Config.Get("Dungeon") or "Mistwake")
local pauseAutoRetainer   = (Config.Get("Pause for AutoRetainer") ~= false)
local multiMode           = (Config.Get("Enable AutoRetainer MultiMode") ~= false)

local ItemToBuy           = (ArcaniteMap[arcanitePick] or 0)
local DungeonToDo         = (DungMap[dungeonPick] and DungMap[dungeonPick].id or 0)
local MathematicsFromDung = (DungMap[dungeonPick] and DungMap[dungeonPick].amount or 0)
local purchaseCounter     = 0

-- IDs / locations
local INN_TERRITORY_ID     = 177
local PHANTOM_VILLAGE_ID   = 1278
local MATHEMATICS_ITEM_ID  = 48

-- Tome Exchange NPC (localized name from ENpcResident)
local TOME_EXCHANGE_NPC_ID = 1053904
local TomeExchange = {
    id       = TOME_EXCHANGE_NPC_ID,
    name     = nil,
    position = Vector3(40.818, 0.000, 20.828),
}

do
    local okNpc, npc = GetENpcResidentName(TomeExchange.id)
    if okNpc then
        TomeExchange.name = npc.name
        Log("TomeExchange NPC: %s (id=%d)", npc.name, npc.id)
    else
        Log("TomeExchange NPC lookup failed: %s", npc)
    end
end

-- =========================================================
-- AutoDuty + Lifestream helpers
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

local function MathematicsOnHand()
    return tonumber(Inventory.GetItemCount(MATHEMATICS_ITEM_ID)) or 0
end

local function RunsToGo()
    local perRun = tonumber(MathematicsFromDung) or 0
    if perRun <= 0 then return 0 end
    local remaining = mathematicsLimit - MathematicsOnHand()
    if remaining <= 0 then return 0 end
    return math.ceil(remaining / perRun)
end

local function StartAutoDuty()
    if not (IPC and IPC.AutoDuty and IPC.AutoDuty.Run) then
        Log("StartAutoDuty: AutoDuty IPC missing")
        gotoState(STATE.FAIL)
        return false
    end
    IPC.AutoDuty.Run(DungeonToDo, RunsToGo(), false)
    sleep(TIME.POLL)
    return true
end

local function TravelToZone(command, targetZoneId)
    IPC.Lifestream.ExecuteCommand(command)
    while IPC.Lifestream.IsBusy() do
        if WaitZoneChange() and (GetZoneId() or 0) == targetZoneId then
            IPC.Lifestream.Abort()
        end
        sleep(TIME.POLL)
    end
end

local function ReturnToInn()
    TravelToZone("Inn", INN_TERRITORY_ID)
end

local function MoveToPhantomVillage()
    TravelToZone("Phantom Village", PHANTOM_VILLAGE_ID)
end

-- =========================================================
-- AutoRetainer readiness (retainer fix)
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
    SPEND_TOMES  = "SPEND_TOMES",
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
EchoOnce("Starting Mathematics Farmer script.")

while sm.s ~= STATE.DONE and sm.s ~= STATE.FAIL do
    -- ======================
    -- READY
    -- ======================
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

        if MathematicsOnHand() >= mathematicsLimit then
            gotoState(STATE.SPEND_TOMES)

        elseif RunsToGo() > 0 then
            gotoState(STATE.RUN_AUTODUTY)

        else
            gotoState(STATE.DONE)
        end

    -- ======================
    -- RUN_AUTODUTY
    -- ======================
    elseif sm.s == STATE.RUN_AUTODUTY then
        Log("Starting AutoDuty: dungeon=%s runs=%d", dungeonPick, RunsToGo())
        StartAutoDuty()
        Sleep(TIME.STABLE)
        gotoState(STATE.READY)

    -- ======================
    -- SPEND_TOMES
    -- ======================
    elseif sm.s == STATE.SPEND_TOMES then
        Log("Moving to Phantom Village to spend tomes")
        MoveToPhantomVillage()

        if not TomeExchange.name or TomeExchange.name == "" then
            Log("SPEND_TOMES: TomeExchange.name missing (Excel lookup failed)")
            gotoState(STATE.FAIL)
            goto continue
        end

        local ent = (Entity and Entity.GetEntityByName) and Entity.GetEntityByName(TomeExchange.name) or nil
        if not (ent and ent.Position and ent.Name and ent.Name ~= "") then
            Log("SPEND_TOMES: TomeExchange entity not found/invalid (sheetName='%s')", tostring(TomeExchange.name))
            gotoState(STATE.FAIL)
            goto continue
        end

        Log("SPEND_TOMES: Moving to tome exchange NPC (%s)", ent.Name)
        if not MoveNearVnav(ent.Position, 3.0, false) then
            goto continue
        end

        Log("SPEND_TOMES: Interacting with tome exchange NPC (%s)", ent.Name)
        if not InteractByName(ent.Name, 5.0) then
            Log("SPEND_TOMES: could not interact with NPC (%s)", ent.Name)
            gotoState(STATE.FAIL)
            goto continue
        end

        if not AwaitAddonReady("ShopExchangeCurrency", 5.0) then
            Log("SPEND_TOMES: ShopExchangeCurrency did not open")
            gotoState(STATE.FAIL)
            goto continue
        end

        while MathematicsOnHand() >= 500 do
            SafeCallback("ShopExchangeCurrency", true, 0, ItemToBuy, 1)

            if not AwaitAddonReady("SelectYesno", 5.0) then
                Log("SPEND_TOMES: SelectYesno missing")
                gotoState(STATE.FAIL)
                break
            end
            SafeCallback("SelectYesno", true, 0)

            if not AwaitAddonReady("ShopExchangeCurrency", 5.0) then
                Log("SPEND_TOMES: ShopExchangeCurrency not ready after confirm")
                gotoState(STATE.FAIL)
                break
            end

            sleep(TIME.STABLE)
        end

        if sm.s ~= STATE.FAIL then
            Log("Closing shop window")
            for i = 1, 10 do
                if not IsAddonVisible("ShopExchangeCurrency") then break end
                SafeCallback("ShopExchangeCurrency", true, -1)
                Sleep(TIME.STABLE)
            end

            Sleep(TIME.STABLE)

            purchaseCounter = purchaseCounter + 1
            Log("Purchase complete: %s/%d", purchaseCounter, maxPurchases)

            if maxPurchases == 0 or purchaseCounter < maxPurchases then
                gotoState(STATE.READY)
            else
                gotoState(STATE.DONE)
            end
        end

    -- ======================
    -- WAIT_BELL
    -- ======================
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
            Sleep(TIME.POLL)
            goto continue
        end

        Log("Checking RetainerList stable")
        if closeRetainer and WaitAddonStable("RetainerList", TIME.STABLE, 3, TIME.POLL) then
            CloseRetainerList()
        elseif not closeRetainer then
            WaitUntil(function() return not AtSummoningBell() end, 999999, TIME.POLL, 1)
        end

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
