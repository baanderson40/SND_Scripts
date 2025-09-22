--[=====[
[[SND Metadata]]
author: baanderson40
version: 0.0.2
description: |
  Script to run Helio tome dungeons repeatly and auto purchase Phantom relic arcanite items.
plugin_dependencies:
- AutoDuty
- Lifestream
configs:
  Helio Tome Limit:
    description: |
      Maximum number of Helio tome before spending.
    default: 1500
    min: 500
    max: 2000
  Dungeon:
    description: |
      Select dungeon to run.
    default: "The Meso Terminal"
    is_choice: true
    choices: ["The Meso Terminal", "The Underkeep", "Yuweyawata Field Station", "Alexandria"]
  Arcanite type:
    description: Select arcanite to purchase.
    default: "Waxing Arcanite"
    is_choice: true
    choices: ["Waxing Arcanite", "Arcanite"]

[[End Metadata]]
--]=====]

-- =========================================================
-- Script Settings
-- =========================================================
import("System.Numerics")
echoLog = false

CharacterCondition = {
    casting              = 27,
    betweenAreas         = 45,
    betweenAreasForDuty  = 51,
    occupiedInQuestEvent = 32,
}

ArcaniteTypes  = {
    {name = "Arcanite",         id = 1},
    {name = "Waxing Arcanite",  id = 0}
}

DungList = {
    {name = "The Meso Terminal",        id = 1292, amount = 80},
    {name = "The Underkeep",            id = 1266, amount = 80},
    {name = "Yuweyawata Field Station", id = 1242, amount = 60},
    {name = "Alexandria",               id = 1199, amount = 50},
}

ArcaniteMap = {}
for i = 1, #ArcaniteTypes do
    local t = ArcaniteTypes[i]
    ArcaniteMap[t.name] = t.id
end

DungMap = {}
for i = 1, #DungList do
    local t = DungList[i]
    DungMap[t.name] = { id = t.id, amount = t.amount }
end

HelioWanted     = Config.Get("Helio Tome Limit")
Arcanite        = Config.Get("Arcanite type")
DungPicked      = Config.Get("Dungeon")

ItemToBuy       = (ArcaniteMap[Arcanite] or 0)
DungToDo        = (DungMap[DungPicked] and DungMap[DungPicked].id or 0)
HelioFromDung   = (DungMap[DungPicked] and DungMap[DungPicked].amount or 0)
InnId           = 177
PhantomCityId   = 1278
TomeExchange    = { name = "Ermina", position = Vector3(40.818, 0.000, 20.828) }

-- =========================================================
-- Echo / Log
-- =========================================================
function _echo(s)
    local msg = tostring(s)
    yield("/echo " .. msg)
end

function _log(s)
    local msg = tostring(s)
    Dalamud.Log(msg)
    if echoLog then _echo(msg) end
end

Echo, echo  = _echo, _echo
Log,  log   = _log,  _log

-- =========================================================
-- Timing constants + Sleep
-- =========================================================
TIME = {
    POLL    = 0.10,  -- canonical polling step
    TIMEOUT = 10.0,  -- default time budget
    STABLE  = 0.0    -- default stability window
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
-- Addon Helpers
-- =========================================================
function _get_addon(name)
    local ok, addon = pcall(Addons.GetAddon, name)
    if ok and addon ~= nil then return addon end
    return nil
end

function IsAddonReady(name)
    local addon = _get_addon(name)
    return addon and addon.Ready or false
end

function AwaitAddonReady(name, timeoutSec)
    echo("awaiting ready: " .. tostring(name))
    local deadline, t = (timeoutSec or 10.0), 0.0
    while t < deadline do
        local addon = _get_addon(name)
        if addon and addon.Ready then return true end
        sleep(TIME.POLL); t = t + TIME.POLL
    end
    Log("AwaitAddonReady timeout for: " .. tostring(name))
    return false
end

function IsAddonVisible(name)
    local addon = _get_addon(name)
    return addon and addon.Exists or false
end

function AwaitAddonVisible(name, timeoutSec)
    echo("awaiting visible: " .. tostring(name))
    local deadline, t = (timeoutSec or 10.0), 0.0
    while t < deadline do
        local addon = _get_addon(name)
        if addon and addon.Exists then return true end
        sleep(TIME.POLL); t = t + TIME.POLL
    end
    Log("AwaitAddonVisible timeout for: " .. tostring(name))
    return false
end

-- =========================================================
-- Character / Target / Position Helpers
-- =========================================================
function GetZoneId()
    local svc = Svc
    if not svc then return nil end
    local cs = svc.ClientState
    return cs and cs.TerritoryType or nil
end

function WaitZoneChange()
    sleep(1) -- Second into the change
    local cond, cc = Svc.Condition, CharacterCondition
    while cond[cc.casting]
       or cond[cc.betweenAreas]
       or cond[cc.betweenAreasForDuty]
       or cond[cc.occupiedInQuestEvent] do
        sleep(TIME.POLL)
    end
    sleep(1) -- Second out of the change
    return true
end

function InteractByName(name, timeout)
    timeout = timeout or 5
    local e = Entity.GetEntityByName(name)
    if not e then return false end
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
    return false
end

-- =========================================================
-- Safe Callback
-- =========================================================
function SafeCallback(...)
    local args, idx = {...}, 1
    local addon = args[idx]; idx = idx + 1
    if type(addon) ~= "string" then
        Log("SafeCallback: first arg must be addon name (string)")
        return
    end
    local update, updateStr = args[idx], "true"
    if type(update) == "boolean" then
        updateStr = tostring(update); idx = idx + 1
    elseif type(update) == "string" then
        local s = update:lower()
        if s == "false" or s == "f" or s == "0" or s == "off" then updateStr = "false" end
        idx = idx + 1
    end
    local call = "/callback " .. addon .. " " .. updateStr
    for i = idx, #args do
        local v = args[i]
        if type(v) == "number" then call = call .. " " .. tostring(v) end
    end
    echo("calling: " .. call)
    if IsAddonReady(addon) and IsAddonVisible(addon) then
        yield(call)
    else
        Log("SafeCallback: addon not ready/visible: " .. addon)
    end
end

-- =========================================================
-- Plugin helpers
-- =========================================================
function IsAutoDutyRunning()
    return not IPC.AutoDuty.IsStopped()
end

function EnablePreLoopActions()
    yield("/autoduty cfg EnablePreLoopActions true")
    sleep(TIME.POLL)
end

function EnableBetweenLoopActions()
    yield("/autoduty cfg EnableBetweenLoopActions true")
    sleep(TIME.POLL)
end

function StartAD()
    IPC.AutoDuty.Run(DungToDo, RunsToGo(), true)
    sleep(TIME.POLL)
end

-- =========================================================
-- VNAV Helpers
-- =========================================================
function PathandMoveVnav(dest, fly)
    fly = (fly == true)
    local vnav, t, timeout = IPC.vnavmesh, 0, 10.0
    while not vnav.IsReady() and t < timeout do sleep(TIME.POLL); t = t + TIME.POLL end
    if not vnav.IsReady() then Log("VNAV not ready (timeout)"); return false end
    local ok = vnav.PathfindAndMoveTo(dest, fly)
    if not ok then Log("VNAV pathfind failed") end
    return ok
end

function StopCloseVnav(dest, stopDistance)
    stopDistance = tonumber(stopDistance) or 3.0
    if not dest then return false end
    local vnav, t, timeout = IPC.vnavmesh, 0, 10.0
    while not vnav.IsRunning() and t < timeout do sleep(TIME.POLL); t = t + TIME.POLL end
    if not vnav.IsRunning() then Log("VNAV not running (timeout)"); return false end
    while vnav.IsRunning() do
        local me = Entity and Entity.Player
        if me and me.Position and Vector3.Distance(me.Position, dest) < stopDistance then
            vnav.Stop(); return true
        end
        sleep(TIME.POLL)
    end
    return true
end

function MoveNearVnav(dest, stopDistance, fly)
    stopDistance = tonumber(stopDistance) or 3.0
    if PathandMoveVnav(dest, fly) then return StopCloseVnav(dest, stopDistance) end
    return false
end

-- =========================================================
-- Worker functions
-- =========================================================
function HelioOnHand()
    return Inventory.GetItemCount(47) or 0
end

function RunsToGo()
    local perRun = tonumber(HelioFromDung) or 0
    if perRun <= 0 then return 0 end
    local remaining = HelioWanted - HelioOnHand()
    if remaining <= 0 then return 0 end
    return math.ceil(remaining / perRun)
end

function TravelToZone(command, targetZoneId)
    IPC.Lifestream.ExecuteCommand(command)
    while IPC.Lifestream.IsBusy() do
        if WaitZoneChange() and (GetZoneId() or 0) == targetZoneId then
            IPC.Lifestream.Abort()
        end
        sleep(TIME.POLL)
    end
end

function ReturnToInn()
    TravelToZone("Inn", InnId)
end

function MoveToPhantomCity()
    TravelToZone("Occult", PhantomCityId)
end

-- =========================================================
-- Branch functions / State machine
-- =========================================================
function Ready()
    if not IsAutoDutyRunning() then
        if HelioOnHand() >= HelioWanted then
            log("[Helio Farmer] CharacterState changed to spend helio from ready")
            State = CharacterState.spendhelio
        elseif RunsToGo() > 0 and GetZoneId() ~= InnId then
            log("[Helio Farmer] CharacterState changed to return to base from ready")
            State = CharacterState.returntobase
        elseif RunsToGo() > 0 and GetZoneId() == InnId then
            log("[Helio Farmer] CharacterState changed to run auto duty from ready")
            State = CharacterState.runautoduty
        end
    end
end

function RunAutoDuty()
    log("[Helio Farmer] Starting auto duty")
    StartAD()
    EnablePreLoopActions()
    EnableBetweenLoopActions()
    while IsAutoDutyRunning() do sleep(10) end
    log("[Helio Farmer] CharacterState changed to ready from RunAutoDuty")
    State = CharacterState.ready
end

function SpendHelio()
    log("[Helio Farmer] Moving to Phantom Village")
    MoveToPhantomCity()

    log("[Helio Farmer] Moving to tome exchange npc")
    MoveNearVnav(TomeExchange.position)

    log("[Helio Farmer] Interacting with npc")
    if not TomeExchange or not TomeExchange.name or TomeExchange.name == "" then
        log("[Helio Farmer] TomeExchange NPC name missing; aborting spend and returning to ready")
        State = CharacterState.ready
        return
    end
    if not InteractByName(TomeExchange.name) then
        log("[Helio Farmer] Could not interact with TomeExchange NPC; aborting spend and returning to ready")
        State = CharacterState.ready
        return
    end

    log("[Helio Farmer] Waiting on shop window")
    AwaitAddonReady("ShopExchangeCurrency")

    repeat
        log("[Helio Farmer] Purchasing item tome item")
        SafeCallback("ShopExchangeCurrency", 0, ItemToBuy, 1)
        AwaitAddonReady("SelectYesno")
        SafeCallback("SelectYesno", 0)
        AwaitAddonReady("ShopExchangeCurrency")
        sleep(0.75)
    until HelioOnHand() < 500

    log("[Helio Farmer] Closing shop window")
    repeat
        SafeCallback("ShopExchangeCurrency", -1)
    until not AwaitAddonVisible("ShopExchangeCurrency", 0.1)

    log("[Helio Farmer] CharacterState changed to ready from SpendHelio")
    State = CharacterState.ready
end

function ReturnToBase()
    log("[Helio Farmer] Return to Inn")
    ReturnToInn()
    log("[Helio Farmer] CharacterState changed to ready from ReturnToBase")
    State = CharacterState.ready
end

CharacterState = {
    ready        = Ready,
    runautoduty  = RunAutoDuty,
    spendhelio   = SpendHelio,
    returntobase = ReturnToBase,
}

-- =========================================================
-- Main loop
-- =========================================================
State = CharacterState.ready
while true do
    State()
    sleep(TIME.POLL)
end
