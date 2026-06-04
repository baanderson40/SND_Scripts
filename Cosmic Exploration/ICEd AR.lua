--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.0.1
description: Somewhat intergrate AutoRetainer into ICE
plugin_dependencies:
- vnavmesh
- AutoRetainer
configs:
  Mount:
    description: Input the name of the mount to use. Leave empty to use mount roulette
    default: ""
  Close Retainer List:
    description: Close the retainer list after AutoRetainer finishes.
    default: true
[[End Metadata]]
--]=====]

-- =========================================================
-- Config
-- =========================================================
import("System.Numerics")

local SETTINGS = {
    echoLog = false,
    closeRetainerList = (Config.Get("Close Retainer List") ~= false),
}

local PREFIX = "[ICEd AR]"

local BELL_EOBJ_DEFAULT = 2000441
local BELL_EOBJ_BY_TERRITORY = {
    [1237] = 2014985,
}

local LIMITS = {
    maxBellDistanceBeforeStellar = 100.0,
    moveStopDistance = 3.0,
    interactTimeout = 5.0,
    retainerListTimeout = 5.0,
    waitForever = 999999,
    retainerCloseAttempts = 80,
    stellarReturnDelay = 4.0,
    mountDistance = 50.0,
    dismountDistance = 20.0,
    autoRetainerIdleSettle = 1.0,
    autoRetainerIdleTimeout = 120.0,
}

-- =========================================================
-- Echo / Log Helpers (ALL code should call Log(...) / Echo(...))
-- =========================================================
local function _echo(s)
    yield("/echo " .. tostring(s))
end

local function _log(s)
    local msg = tostring(s)
    Dalamud.Log(msg)
    if SETTINGS.echoLog then _echo(msg) end
end

local function _fmt(msg, ...)
    return string.format("%s %s", PREFIX, string.format(msg, ...))
end

local function Log(msg, ...)
    _log(_fmt(msg, ...))
end

local function Echo(msg, ...)
    _echo(_fmt(msg, ...))
end

local function EchoOnce(msg, ...)
    if SETTINGS.echoLog then
        Log(msg, ...)
    else
        Echo(msg, ...)
        Log(msg, ...)
    end
end

-- =========================================================
-- Timing constants + Sleep
-- =========================================================
local TIME = {
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

local sleep = _sleep

-- =========================================================
-- Number helper (parsing + optional clamping)
-- =========================================================
local function toNumberSafe(s, default, min, max)
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

local function IsAddonReady(name)
    local addon = _get_addon(name)
    return addon and addon.Ready or false
end

local function IsAddonVisible(name)
    local addon = _get_addon(name)
    return addon and addon.Exists or false
end

-- =========================================================
-- WaitUntil Helper
-- =========================================================
-- Usage Recap:
-- WaitUntil(predicateFn, timeoutSec, pollSec, stableSec)
--
--   predicateFn : function() -> true/false  (checked each poll)
--   timeoutSec  : max seconds before giving up (default 10)
--   pollSec     : seconds between checks (default 0.10)
--   stableSec   : must remain true for this many seconds
--                 continuously before success (default 0)
--
-- Returns: true if condition satisfied, false on timeout
--
-- Examples:
--   Wait until addon "Talk" is ready (10s max):
--     WaitUntil(function()
--         local addon = _get_addon("Talk")
--         return addon and addon.Ready
--     end, 10.0)
--
--   Wait until crafting condition holds for 2s (15s max):
--     WaitUntil(function()
--         return GetCharacterCondition(CharacterCondition.crafting, true)
--     end, 15.0, 0.10, 2.0)
--
--   Quick one-off wait (target = "NPC Bob"):
--     WaitUntil(function()
--         return Entity.Target and Entity.Target.Name == "NPC Bob"
--     end, 5.0, 0.10)
--
local function WaitUntil(predicateFn, timeoutSec, pollSec, stableSec)
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

local function AwaitAddonReady(name, timeoutSec)
    Log("awaiting ready: %s", tostring(name))
    local ok = WaitUntil(function()
        local addon = _get_addon(name)
        return addon and addon.Ready
    end, timeoutSec or TIME.TIMEOUT, TIME.POLL, 0.0)
    if not ok then Log("AwaitAddonReady timeout: %s", tostring(name)) end
    return ok
end

local function AwaitAddonVisible(name, timeoutSec)
    Log("awaiting visible: %s", tostring(name))
    local ok = WaitUntil(function()
        local addon = _get_addon(name)
        return addon and addon.Exists
    end, timeoutSec or TIME.TIMEOUT, TIME.POLL, 0.0)
    if not ok then Log("AwaitAddonVisible timeout: %s", tostring(name)) end
    return ok
end

local function WaitAddonStable(addonName, stableSec, timeoutSec, pollSec)
    return WaitUntil(function()
        local addon = _get_addon(addonName)
        return addon and addon.Exists
    end, timeoutSec or TIME.TIMEOUT, pollSec or TIME.POLL, stableSec or 2.0)
end

local function WaitConditionStable(idx, want, stableSec, timeoutSec, pollSec)
    want       = (want ~= false)
    stableSec  = toNumberSafe(stableSec,  2.0,   0.0)
    timeoutSec = toNumberSafe(timeoutSec, 15.0,  0.1)
    pollSec    = toNumberSafe(pollSec,    TIME.POLL, 0.01)

    if not (Svc and Svc.Condition) then
        Log("WaitConditionStable: Svc.Condition unavailable")
        return false
    end

    local ok = WaitUntil(function()
        return GetCharacterCondition(idx, want)
    end, timeoutSec, pollSec, stableSec)

    if not ok then
        Log("WaitConditionStable: timeout (idx=%s want=%s stable=%.2fs)",
            tostring(idx), tostring(want), stableSec)
    end
    return ok
end

-- =========================================================
-- Character Conditions + Helpers
-- =========================================================
local CharacterCondition = {
    normalConditions                   = 1,
    dead                               = 2,
    emoting                            = 3,
    mounted                            = 4,
    crafting                           = 5,
    gathering                          = 6,
    meldingMateria                     = 7,
    operatingSiegeMachine              = 8,
    carryingObject                     = 9,
    mounted2                           = 10,
    inThatPosition                     = 11,
    chocoboRacing                      = 12,
    playingMiniGame                    = 13,
    playingLordOfVerminion             = 14,
    participatingInCustomMatch         = 15,
    performing                         = 16,
    occupied                           = 25,
    inCombat                           = 26,
    casting                            = 27,
    sufferingStatusAffliction          = 28,
    sufferingStatusAffliction2         = 29,
    occupied30                         = 30,
    occupiedInEvent                    = 31,
    occupiedInQuestEvent               = 32,
    occupied33                         = 33,
    boundByDuty34                      = 34,
    occupiedInCutSceneEvent            = 35,
    inDuelingArea                      = 36,
    tradeOpen                          = 37,
    occupied38                         = 38,
    occupiedMateriaExtractionAndRepair = 39,
    executingCraftingAction            = 40,
    preparingToCraft                   = 41,
    executingGatheringAction           = 42,
    fishing                            = 43,
    betweenAreas                       = 45,
    stealthed                          = 46,
    jumping48                          = 48,
    autorunActive                      = 49,
    usingChocoboTaxi                   = 49,
    occupiedSummoningBell              = 50,
    betweenAreasForDuty                = 51,
    systemError                        = 52,
    loggingOut                         = 53,
    conditionLocation                  = 54,
    waitingForDuty                     = 55,
    boundByDuty56                      = 56,
    mounting57                         = 57,
    watchingCutscene                   = 58,
    waitingForDutyFinder               = 59,
    creatingCharacter                  = 60,
    jumping61                          = 61,
    pvpDisplayActive                   = 62,
    sufferingStatusAffliction63        = 63,
    mounting64                         = 64,
    carryingItem                       = 65,
    usingPartyFinder                   = 66,
    usingHousingFunctions              = 67,
    transformed                        = 68,
    onFreeTrial                        = 69,
    beingMoved                         = 70,
    mounting71                         = 71,
    sufferingStatusAffliction72        = 72,
    sufferingStatusAffliction73        = 73,
    registeringForRaceOrMatch          = 74,
    waitingForRaceOrMatch              = 75,
    waitingForTripleTriadMatch         = 76,
    flying                             = 77,
    watchingCutscene78                 = 78,
    inDeepDungeon                      = 79,
    swimming                           = 80,
    diving                             = 81,
    registeringForTripleTriadMatch     = 82,
    waitingForTripleTriadMatch83       = 83,
    participatingInCrossWorldPartyOrAlliance = 84,
    unknown85                          = 85,
    dutyRecorderPlayback               = 86,
    casting87                          = 87,
    inThisState88                      = 88,
    inThisState89                      = 89,
    rolePlaying                        = 90,
    boundToDuty97                      = 91,
    inDutyQueue                        = 91,
    readyingVisitOtherWorld            = 92,
    waitingToVisitOtherWorld           = 93,
    usingFashionAccessory              = 94,
    boundByDuty95                      = 95,
    unknown96                          = 96,
    disguised                          = 97,
    recruitingWorldOnly                = 98,
    unknown99                          = 99,
    editingPortrait                    = 100,
    unknown101                         = 101,
    pilotingMech                       = 102,
}

local function GetCharacterCondition(i, bool)
    if bool == nil then bool = true end
    return Svc and Svc.Condition and (Svc.Condition[i] == bool) or false
end

local function GetCharacterPosition()
    local player = Svc and Svc.Objects and Svc.Objects.LocalPlayer
    return player and player.Position or nil
end

local function GetZoneId()
    local cs = Svc and Svc.ClientState
    return cs and cs.TerritoryType or nil
end

local function IsCrafterJob()
    return Player and Player.Job and Player.Job.IsCrafter or false
end

-- =========================================================
-- Safe Callback
-- =========================================================
local function _quoteArg(s)
    s = tostring(s)
    s = s:gsub("\\", "\\\\"):gsub('"', '\\"')
    return '"' .. s .. '"'
end

local function SafeCallback(...)
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

    Log("calling: %s", call)
    if IsAddonReady(addon) and IsAddonVisible(addon) then
        yield(call)
        return true
    end

    Log("SafeCallback: addon not ready/visible: %s", addon)
    return false
end

-- =========================================================
-- Mount helpers
-- =========================================================
local function Mount()
    local useMount = Config.Get("Mount")
    if not Svc.Condition[CharacterCondition.mounted] then
        if useMount ~= nil and useMount ~= "" then
            yield('/mount "'..useMount..'"')
        else
            Actions.ExecuteGeneralAction(9) -- Mount Roulette
        end
    end
end

local function Dismount()
    if Svc.Condition[CharacterCondition.mounted] then
        Actions.ExecuteGeneralAction(23) -- Dismount
    end
end

-- =========================================================
-- Distance helpers
-- =========================================================
local function DistanceBetweenPositions(pos1, pos2)
    if not (pos1 and pos2) then return math.huge end
    return Vector3.Distance(pos1, pos2)
end

-- =========================================================
-- Interaction Helper
-- =========================================================
local function InteractByName(name, timeout)
    if type(name) ~= "string" or name == "" then
        Log("InteractByName: invalid name '%s'", tostring(name))
        return false
    end
    timeout = toNumberSafe(timeout, 5, 0.1)

    local e = Entity and Entity.GetEntityByName and Entity.GetEntityByName(name)
    if not e then
        Log("InteractByName: entity not found '%s'", name)
        return false
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
-- VNAV Helpers
-- =========================================================
local function PathandMoveVnav(dest, fly)
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
    if not ok then
        Log("VNAV pathfind failed")
        return false
    end

    local me = Entity and Entity.Player
    if me and me.Position and Vector3.Distance(me.Position, dest) > LIMITS.mountDistance then
        Mount()
    end
    return true
end

local function StopCloseVnav(dest, stopDistance)
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
            if Vector3.Distance(me.Position, dest) < LIMITS.dismountDistance
                and GetCharacterCondition(CharacterCondition.mounted) then
                Dismount()
            end

            if Vector3.Distance(me.Position, dest) < stopDistance then
                IPC.vnavmesh.Stop()
                return true
            end
        end
        sleep(TIME.POLL)
    end

    return false
end

local function MoveNearVnav(dest, stopDistance, fly)
    stopDistance = tonumber(stopDistance) or 3.0
    if PathandMoveVnav(dest, fly) then
        return StopCloseVnav(dest, stopDistance)
    end
    return false
end

local function StopVNAV()
    if IPC.vnavmesh.BuildProgress() or IPC.vnavmesh.IsRunning() then
        IPC.vnavmesh.Stop()
    end
end

-- =========================================================
-- Excel Sheet Lookups (guarded, return ok,value|err)
-- =========================================================
local function ok(v)  return true, v end
local function err(m) return false, tostring(m or "unknown error") end

local function GetEObjName(dataId)
    local id = toNumberSafe(dataId, nil)
    if not id then
        return err("EObjName: invalid id '" .. tostring(dataId) .. "'")
    end

    local sheet = Excel.GetSheet("EObjName")
    if not sheet then
        return err("EObjName sheet not available")
    end

    local row = sheet:GetRow(id)
    if not row then
        return err("EObjName: no row for id " .. tostring(id))
    end

    local name = row.Singular
    if not name or name == "" then
        return err("EObjName: Singular missing for id " .. tostring(id))
    end

    return ok({
        id     = id,
        name   = tostring(name),
        plural = row.Plural and tostring(row.Plural) or nil,
        source = "EObjName",
    })
end

-- =========================================================
-- Script-specific helpers
-- =========================================================
local function StellarReturn()
    Actions.ExecuteAction(42149) -- Stellar Return
    sleep(LIMITS.stellarReturnDelay)
    return WaitConditionStable(CharacterCondition.betweenAreas, false, 2, 10)
end

local function WaitWksMissionInfoClosed()
    Log("waiting for WKSMissionInfomation to close")
    while IsAddonVisible("WKSMissionInfomation") do
        sleep(TIME.POLL)
    end
    Log("WKSMissionInfomation closed")
    return true
end

local function SafeAutoRetainerCall(fieldName)
    if not (IPC and IPC.AutoRetainer) then
        return false, nil
    end

    local okField, fn = pcall(function()
        return IPC.AutoRetainer[fieldName]
    end)
    if not okField or not fn then
        return false, nil
    end

    local okCall, value = pcall(function()
        return fn()
    end)
    if not okCall then
        return false, nil
    end

    return true, value
end

local function AutoRetainerAnyAvailable()
    local ok, value = SafeAutoRetainerCall("AreAnyRetainersAvailableForCurrentChara")
    return ok and value == true or false
end

local function AutoRetainerBusySignal()
    local ok, value = SafeAutoRetainerCall("IsBusy")
    return ok and value == true or false
end

local function IsAutoRetainerIdle()
    return (not AutoRetainerBusySignal()) and (not AutoRetainerAnyAvailable())
end

local function GetBellEobjIdForTerritory(territoryId)
    return BELL_EOBJ_BY_TERRITORY[territoryId] or BELL_EOBJ_DEFAULT
end

local function ResolveBellNameByEobjId(eobjId)
    local okRes, dataOrErr = GetEObjName(eobjId)
    if not okRes then
        Log("GetEObjName failed (%s): %s", tostring(eobjId), tostring(dataOrErr))
        return nil
    end

    local sheetName = tostring(dataOrErr.name or "")
    if sheetName == "" then
        Log("empty bell name for eobjId=%s", tostring(eobjId))
        return nil
    end

    return sheetName
end

local function ResolveBellEntityByName(name)
    local ent = Entity and Entity.GetEntityByName and Entity.GetEntityByName(name) or nil
    if not (ent and ent.Position and ent.Name) then
        Log("bell not found locally by name '%s'", tostring(name))
        return nil
    end

    Log("resolved bell '%s' at x=%.2f y=%.2f z=%.2f",
        tostring(ent.Name), ent.Position.X, ent.Position.Y, ent.Position.Z)
    return ent
end

local function ResolveSummoningBellEntity()
    local terr = GetZoneId()
    local eobjId = GetBellEobjIdForTerritory(terr)

    Log("resolving summoning bell for territory=%s eobjId=%s", tostring(terr), tostring(eobjId))

    local sheetName = ResolveBellNameByEobjId(eobjId)
    if not sheetName then return nil end

    return ResolveBellEntityByName(sheetName)
end

local function ResolveBellOrReturnOnce(maxDist)
    maxDist = tonumber(maxDist) or LIMITS.maxBellDistanceBeforeStellar

    local function distTo(ent)
        local me = GetCharacterPosition()
        if not (me and ent and ent.Position) then return math.huge end
        return DistanceBetweenPositions(me, ent.Position)
    end

    local bell = ResolveSummoningBellEntity()
    if bell then
        local d = distTo(bell)
        Log("distance to bell (current): %.2f", d)
        if d <= maxDist then
            return bell, false
        end
        Log("bell too far (%.2f > %.2f) -> Stellar Return", d, maxDist)
    else
        Log("bell not resolved -> Stellar Return")
    end

    if not StellarReturn() then
        Log("Stellar Return failed")
        return nil, true
    end
    sleep(TIME.STABLE)

    bell = ResolveSummoningBellEntity()
    if not bell then
        Log("bell still not resolved after Stellar Return")
        return nil, true
    end

    local d2 = distTo(bell)
    Log("distance to bell after return (current): %.2f", d2)
    return bell, false
end

local function StopIce()
    Log("stopping ICE")
    yield("/ice stop")
    sleep(TIME.STABLE)
    return true
end

local function StartIce()
    Log("starting ICE")
    yield("/ice start")
    return true
end

local function CaptureOriginPosition()
    local origin = GetCharacterPosition()
    if not origin then
        Log("failed to get player position")
        return nil
    end
    return origin
end

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
    while IsAddonVisible("RetainerList") and tries < LIMITS.retainerCloseAttempts do
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

local function MoveToBellAndOpenRetainerList()
    local bell = ResolveBellOrReturnOnce(LIMITS.maxBellDistanceBeforeStellar)
    if not bell then
        Log("failed to resolve summoning bell")
        return nil
    end

    if not MoveNearVnav(bell.Position, LIMITS.moveStopDistance, false) then
        Log("failed to move near bell")
        return nil
    end

    if not InteractByName(bell.Name, LIMITS.interactTimeout) then
        Log("failed to interact with bell '%s'", tostring(bell.Name))
        return nil
    end

    if not AwaitAddonVisible("RetainerList", LIMITS.retainerListTimeout) then
        Log("failed to open bell '%s'", tostring(bell.Name))
        return nil
    end

    return bell
end

local function WaitForAutoRetainerCompletion()
    Log("waiting for AutoRetainer to finish")
    local finished = WaitUntil(function()
        return IsAutoRetainerIdle()
    end, LIMITS.autoRetainerIdleTimeout, TIME.POLL, LIMITS.autoRetainerIdleSettle)

    if finished then
        Log("AutoRetainer idle confirmed")
    else
        Log("AutoRetainer idle confirmation timed out")
    end

    return finished
end

local function FinishRetainerSession()
    Log("Checking RetainerList stable")
    if SETTINGS.closeRetainerList and WaitAddonStable("RetainerList", TIME.STABLE, 3, TIME.POLL) then
        return CloseRetainerList()
    end

    return WaitUntil(function()
        return not GetCharacterCondition(CharacterCondition.occupiedSummoningBell)
    end, LIMITS.waitForever, TIME.POLL, 1)
end

local function ReturnToOriginIfCrafter(origin)
    if not IsCrafterJob() then
        Log("non-crafter job; skipping return move")
        return true
    end

    Log("crafter job detected; returning to origin")
    return MoveNearVnav(origin, LIMITS.moveStopDistance, false)
end

-- =========================================================
-- Trigger Events
-- =========================================================
function OnStop()
    StopVNAV()
end

-- =========================================================
-- Main (single pass)
-- =========================================================
local function Main()
    if not (IPC and IPC.AutoRetainer and IPC.AutoRetainer.AreAnyRetainersAvailableForCurrentChara) then
        Log("AutoRetainer IPC missing")
        return
    end

    if not IPC.AutoRetainer.AreAnyRetainersAvailableForCurrentChara() then
        Log("no retainers ready; exiting")
        return
    end

    WaitWksMissionInfoClosed()

    StopIce()

    local origin = CaptureOriginPosition()
    if not origin then return end

    local bell = MoveToBellAndOpenRetainerList()
    if not bell then return end

    EnableAutoRetainer()

    if not WaitForAutoRetainerCompletion() then return end
    FinishRetainerSession()
    ReturnToOriginIfCrafter(origin)
    StartIce()
end

Main()
