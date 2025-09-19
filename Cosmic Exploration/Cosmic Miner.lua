--[=====[
[[SND Metadata]]
author: baanderson40
version: 0.0.4
description: Miner script for Phaenna for relic
plugin_dependencies:
- vnavmesh
- ICE
- PandorasBox

[[End Metadata]]
--]=====]

-- =========================================================
-- Config
-- =========================================================
import("System.Numerics")
echoLog = false
MissionName = ""
MissionPicked = false
EnabledAutoText = false

-- =========================================================
-- Timing constants + Sleep (rounded to /wait granularity)
-- =========================================================
TIME = {
    POLL    = 0.10,  -- canonical polling step (matches /wait)
    TIMEOUT = 10.0,  -- default time budget
}

local function _sleep(seconds)
    local s = seconds
    if s == nil then s = 0 end
    s = tonumber(s) or 0
    if s < 0 then s = 0 end
    -- round to 0.1s to avoid drift vs /wait resolution
    s = math.floor(s * 10 + 0.5) / 10
    yield("/wait " .. s)
end
Sleep, sleep = _sleep, _sleep

-- =========================================================
-- Echo / Log Helpers
-- =========================================================
local function _echo(s) yield("/echo " .. tostring(s)) end
local function _log(s)
    local msg = tostring(s)
    Dalamud.Log(msg)
    if echoLog then _echo(msg) end
end
Echo, echo = _echo, _echo
Log,  log  = _log,  _log

local function InfoWindow()
    yield("/fellowship")
    sleep(TIME.POLL)
    SafeCallback("CircleList", 3)
    --yield("/callback CircleList true 3")
    sleep(TIME.POLL)
    Addons.GetAddon("MultipleHelpWindow"):GetNode(1, 3, 2, 3, 4).Text = "Cosmic Miner\r\rWith ICE supporting DoL missions now you must enable\rmanual mode for the missions below:\r\rSoda-lime Float Survey\rGlass Refinement Materials.\r\r The script will begin after closing this window!"
    Addons.GetAddon("MultipleHelpWindow"):GetNode(1, 2, 2, 2).Text = "Cosmic Miner - Help"
    Addons.GetAddon("MultipleHelpWindow"):GetNode(1, 5, 2, 3).Text = "Cosmic Miner"
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

function AwaitAddonReady(name, timeoutSec)
    log("[Cosmic Miner] awaiting ready: " .. tostring(name))
    local deadline = (timeoutSec or TIME.TIMEOUT)
    local t = 0.0
    while t < deadline do
        local addon = _get_addon(name)
        if addon and addon.Ready then return true end
        sleep(TIME.POLL); t = t + TIME.POLL
    end
    log("[Cosmic Miner] AwaitAddonReady timeout for: " .. tostring(name))
    return false
end

function IsAddonVisible(name)
    local addon = _get_addon(name)
    return addon and addon.Exists or false
end

function AwaitAddonVisible(name, timeoutSec)
    log("[Cosmic Miner] awaiting visible: " .. tostring(name))
    local deadline = (timeoutSec or TIME.TIMEOUT)
    local t = 0.0
    while t < deadline do
        local addon = _get_addon(name)
        if addon and addon.Exists then return true end
        sleep(TIME.POLL); t = t + TIME.POLL
    end
    log(" AwaitAddonVisible timeout for: " .. tostring(name))
    return false
end

-- =========================================================
-- Character / Interaction Helpers
-- =========================================================
function GetCharacterCondition(i, bool)
    if bool == nil then bool = true end
    return Svc and Svc.Condition and (Svc.Condition[i] == bool) or false
end

function WaitConditionStable(idx, want, stableSec, timeoutSec, pollSec)
    want       = (want ~= false)
    stableSec  = tonumber(stableSec)  or 2.0
    timeoutSec = tonumber(timeoutSec) or 15.0
    pollSec    = tonumber(pollSec)    or TIME.POLL

    if not (Svc and Svc.Condition) then
        log("[Cosmic Miner] WaitConditionStable: Svc.Condition unavailable"); return false
    end

    local t, startHold = 0.0, nil
    while t < timeoutSec do
        local ok = GetCharacterCondition(idx, want)
        if ok then
            if not startHold then startHold = t end
            if (t - startHold) >= stableSec then return true end
        else
            startHold = nil
        end
        sleep(pollSec); t = t + pollSec
    end

    Log(string.format("WaitConditionStable timeout (idx=%s want=%s stable=%.2fs)",
        tostring(idx), tostring(want), stableSec))
    return false
end

function InteractByName(name, timeout)
    timeout = timeout or 5
    local e = Entity.GetEntityByName(name)
    if not e then return false end

    local start = os.clock()
    while (os.clock() - start) < timeout do
        e:SetAsTarget()
        sleep(TIME.POLL)
        if Entity.Target and Entity.Target.Name == name then
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
    local args = {...}
    local idx = 1

    local addon = args[idx]; idx = idx + 1
    if type(addon) ~= "string" then
        log(" SafeCallback: first arg must be addon name (string)")
        return
    end

    local update = args[idx]; idx = idx + 1
    local updateStr = "true"

    if type(update) == "boolean" then
        updateStr = update and "true" or "false"
    elseif type(update) == "string" then
        local s = update:lower()
        if s == "false" or s == "f" or s == "0" or s == "off" then
            updateStr = "false"
        else
            updateStr = "true"
        end
    else
        idx = idx - 1
    end

    local call = "/callback " .. addon .. " " .. updateStr
    for i = idx, #args do
        local v = args[i]
        if type(v) == "number" then call = call .. " " .. tostring(v) end
    end

    log("[Cosmic Miner] calling: " .. call)
    if IsAddonReady(addon) and IsAddonVisible(addon) then
        yield(call)
    else
        log(" SafeCallback: addon not ready/visible: " .. addon)
    end
end

-- =========================================================
-- Chat + Actions
-- =========================================================
function OnChatMessage()
    local message = TriggerData.message
    if message and message:find(MissionName, 1, true) and message:find("underway") then
        MissionPicked = true
        return
    end
end

function StartICE(missionId)
    yield('/ice only '..missionId); sleep(TIME.POLL)
    yield('/ice start');            sleep(TIME.POLL)
end

function StopICE()
    yield('/ice stop'); sleep(TIME.POLL)
end

function EnablePandora()
    IPC.PandorasBox.SetFeatureEnabled("Auto-interact with Gathering Nodes", true)
    sleep(TIME.POLL)
end

function DisablePandora()
    IPC.PandorasBox.SetFeatureEnabled("Auto-interact with Gathering Nodes", false)
    sleep(TIME.POLL)
end

function StellarReturn()
    Log("[Cosmic Miner] Stellar Return")
    yield('/gaction "Duty Action"')
    sleep(3)
    repeat sleep(TIME.POLL) until WaitConditionStable(CharacterCondition.normalConditions, 2)
    sleep(TIME.POLL)
end

function Mount()    yield('/gaction "mount roulette"'); sleep(TIME.POLL) end
function Dismount() yield("/ac dismount");               sleep(TIME.POLL) end

-- =========================================================
-- Stats / Abilities
-- =========================================================
function CurrentGP()
    return toNumberSafe(Svc.ClientState.LocalPlayer.CurrentGp)
end

function KingYieldII()            yield('/action "King\'s Yield II"');        sleep(0.75) end
function MountaineersGiftII()     yield('/action "Mountaineer\'s Gift II"');  sleep(0.75) end
function MountaineersGiftI()      yield('/action "Mountaineer\'s Gift I"');   sleep(0.75) end

function PegmatiteCount()         return toNumberSafe(Inventory.GetItemCount(47362)) or 0 end
function PegmatiteCollect()       SafeCallback("Gathering", 2); sleep(1) end
function MilkyQuartzCount()       return toNumberSafe(Inventory.GetItemCount(47363)) or 0 end
function MilkyQuartzCollect()     SafeCallback("Gathering", 4); sleep(1) end
function HighsilicaWaterCount()   return toNumberSafe(Inventory.GetItemCount(47364)) or 0 end
function HighsilicaWaterCollect() SafeCallback("Gathering", 6); sleep(1) end
function PhaennaFeldsparCount()   return toNumberSafe(Inventory.GetItemCount(47365)) or 0 end
function PhaennaFeldsparCollect() SafeCallback("Gathering", 3); sleep(1) end
function ObsidianVitrisandCount() return toNumberSafe(Inventory.GetItemCount(47366)) or 0 end
function ObsidianVitrisandCollect() SafeCallback("Gathering", 4); sleep(1) end
function PhaennaAlumanCount()     return toNumberSafe(Inventory.GetItemCount(47367)) or 0 end
function PhaennaAlumanCollect()   SafeCallback("Gathering", 7); sleep(1) end

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
        log("[Cosmic Botanist]  VNAV not ready (timeout)")
        return false
    end
    local ok = IPC.vnavmesh.PathfindAndMoveTo(dest, fly)
    if not ok then log("[Cosmic Botanist] VNAV pathfind failed") end
    if ok then
        local me = Entity and Entity.Player
        if me and me.Position and Vector3.Distance(me.Position, dest) > 25 then
            Mount()
        end
    end
    return ok and true or false
end

function StopCloseVnav(dest, stopDistance)
    stopDistance = tonumber(stopDistance) or 3.0
    if not dest then return end
    local t, timeout = 0, TIME.TIMEOUT
    while not IPC.vnavmesh.IsRunning() and t < timeout do
        sleep(TIME.POLL); t = t + TIME.POLL
    end
    if not IPC.vnavmesh.IsRunning() then
        log("[Cosmic Botanist]  VNAV not running (timeout)")
        return false
    end
    while IPC.vnavmesh.IsRunning() do
        local me = Entity and Entity.Player
        if me and me.Position then
            if Vector3.Distance(me.Position, dest) < 10 and GetCharacterCondition(CharacterCondition.mounted) then
                Dismount()
            end
            if Vector3.Distance(me.Position, dest) < stopDistance then
                IPC.vnavmesh.Stop()
                break
            end
        end
        sleep(TIME.POLL)
    end
end

function MoveNearVnav(dest, stopDistance, fly)
    stopDistance = tonumber(stopDistance) or 3.0
    if PathandMoveVnav(dest, fly) then
        return StopCloseVnav(dest, stopDistance)
    end
    return false
end

-- =========================================================
-- Mission Logic
-- =========================================================
function MissionBravoGather()
    sleep(TIME.POLL)
    if CurrentGP() >= 650 then
        KingYieldII(); MountaineersGiftII(); MountaineersGiftI()
    elseif CurrentGP() >= 150 then
        MountaineersGiftII(); MountaineersGiftI()
    end

    repeat
        if     HighsilicaWaterCount() < 20 then HighsilicaWaterCollect()
        elseif MilkyQuartzCount()     < 15 then MilkyQuartzCollect()
        elseif PegmatiteCount()       < 15 then PegmatiteCollect()
        else                               HighsilicaWaterCollect()
        end
    until not IsAddonVisible("Gathering")
end

function MissionBravoComplete()
    local h = HighsilicaWaterCount() or 0
    local m = MilkyQuartzCount()     or 0
    local p = PegmatiteCount()       or 0
    if h < 20 then return false
    elseif m < 15 then return false
    elseif p < 15 then return false
    elseif (h + m + p) >= 60 then return true end
end

function MissionAlphaGather()
    sleep(TIME.POLL)
    if CurrentGP() >= 650 then
        KingYieldII(); MountaineersGiftII(); MountaineersGiftI()
    elseif CurrentGP() >= 150 then
        MountaineersGiftII(); MountaineersGiftI()
    end
    repeat
        if     PhaennaAlumanCount()     < 15 then PhaennaAlumanCollect()
        elseif ObsidianVitrisandCount() < 15 then ObsidianVitrisandCollect()
        elseif PhaennaFeldsparCount()   < 15 then PhaennaFeldsparCollect()
        else                                   PhaennaFeldsparCollect()
        end
    until not IsAddonVisible("Gathering")
end

function MissionAlphaComplete()
    local a = PhaennaAlumanCount()     or 0
    local v = ObsidianVitrisandCount() or 0
    local f = PhaennaFeldsparCount()   or 0
    if a < 15 then return false
    elseif v < 15 then return false
    elseif f < 15 then return false
    elseif (a + v + f) >= 50 then return true end
end

function ReportMission()
    SafeCallback("WKSMissionInfomation", 11)
    sleep(TIME.POLL)
end

function GetENpcResidentName(dataId)
    local sheet = Excel.GetSheet("ENpcResident")
    if not sheet then return nil, "ENpcResident sheet not available" end
    local row = sheet:GetRow(dataId)
    if not row then return nil, "no row for id "..tostring(dataId) end
    local name = row.Singular or row.Name
    return name, "ENpcResident"
end

-- =========================================================
-- String / Number Helpers
-- =========================================================
function toNumberSafe(s)
    if s == nil then return nil end
    local str = tostring(s):gsub("[^%d%-%.]", "")
    return tonumber(str)
end

function need(tbl, key)
    if not tbl then return 0 end
    return tonumber(tbl[key] or 0) or 0
end

-- =========================================================
-- Worker Functions
-- =========================================================
function RetrieveRelicResearch()
    repeat
        if not IsAddonVisible("WKSToolCustomize") and IsAddonVisible("WKSHud") then
            SafeCallback("WKSHud", 15)
            sleep(0.25) -- allow UI to open/settle
        end
        sleep(TIME.POLL)
    until IsAddonVisible("WKSToolCustomize")

    local ToolAddon = Addons.GetAddon("WKSToolCustomize")

    -- Divisor rules for rows
    local rowDivisors = {
        [4]     = 30,
        [41001] = 30,
        [41002] = 40,
        [41003] = 40,
        [41004] = 25,
    }

    local rows = { 4, 41001, 41002, 41003, 41004 }
    local remainingByRow = {}

    for _, row in ipairs(rows) do
        local currentNode  = ToolAddon:GetNode(1, 55, 68, row, 4, 5)
        local requiredNode = ToolAddon:GetNode(1, 55, 68, row, 4, 7)

        if not currentNode or not requiredNode then break end

        local current  = toNumberSafe(currentNode.Text)  or 0
        local required = toNumberSafe(requiredNode.Text) or 0

        local deficit = (required > current) and (required - current) or 0
        local divisor = rowDivisors[row] or 1
        remainingByRow[row] = (divisor > 1) and math.ceil(deficit / divisor) or deficit
    end

    sleep(TIME.POLL)
    if IsAddonVisible("WKSToolCustomize") then SafeCallback("WKSToolCustomize",-1) end
    return remainingByRow
end

function DoMission(name, position, missionId, nodes, numberof)
    numberof = tonumber(numberof) or 1
    if not position then log("[Cosmic Miner]  DoMission: missing position"); return end
    MissionName = name

    log("[Cosmic Miner] Moving to ".. tostring(position))
    MoveNearVnav(position, 2)

    log("[Cosmic Miner] Dismounting")
    Dismount()

    log("[Cosmic Miner] Starting ICE")
    StartICE(missionId)

    for i = 1, numberof do
        log("[Cosmic Miner] - (Pandora) Enabling Auto-Interact with Gathering Nodes")
        EnablePandora()

        log("[Cosmic Miner] Starting wait for mission")
        repeat sleep(TIME.POLL) until MissionPicked
        sleep(1) -- grace for mission window

        if not IsAddonVisible("WKSMissionInfomation") then
            repeat
                SafeCallback("WKSHud", 11)
                sleep(2) -- allow UI to open
            until IsAddonVisible("WKSMissionInfomation")
        end

        local idx = 1
        repeat
            MoveNearVnav(nodes[idx])

            log("[Cosmic Miner] Waiting for gathering")
            AwaitAddonVisible("Gathering")

            if missionId == 906 then
                log("[Cosmic Miner] Doing Mission A")
                MissionAlphaGather()
            elseif missionId == 908 then
                log("[Cosmic Miner] Doing Mission B")
                MissionBravoGather()
            end

            idx = (idx % #nodes) + 1
        until MissionAlphaComplete() or MissionBravoComplete()

        log("[Cosmic Miner] Mission Complete")
        sleep(TIME.POLL)
        if i >= numberof then StopICE() end

        log("[Cosmic Miner] Report Mission")
        ReportMission()
        MissionPicked = false

        log("[Cosmic Miner] - (Pandora) Disable Auto-Interact with Gathering Nodes")
        DisablePandora()
        MoveNearVnav(nodes[1])
    end
end

-- =========================================================
-- Script Settings 
-- =========================================================
CharacterCondition = {
    normalConditions = 1, -- moving or standing still
    mounted          = 4, -- moving
}

missionA = {
    name     = "Soda-lime Float Survey",
    position = Vector3(-263.495, -8.297, -41.192),
    id       = 906,
    node     = {
        Vector3(-269.733, -6.921, -40.614),
        Vector3(-267.175, -4.791, -26.315),
        Vector3(-261.229, -2.604, -21.767),
        Vector3(-252.064, -1.320, -19.709),
        Vector3(-245.833, -3.649, -27.760),
        Vector3(-236.160, -0.943, -18.201),
        Vector3(-244.571, 3.650, -5.230),
        Vector3(-219.182, -2.932, -16.260),
    }
}

missionB = {
    name     = "Glass Refinement Materials",
    position = Vector3(-293.606, 18.787, 132.563),
    id       = 908,
    node     = {
        Vector3(-290.602, 20.749, 143.793),
        Vector3(-299.463, 21.232, 141.520),
        Vector3(-375.364, 16.603, 76.825),
        Vector3(-374.672, 16.602, 67.367),
        Vector3(-290.435, 16.255, 56.018),
        Vector3(-283.031, 16.306, 57.604),
    }
}

PhaennaResearchNpc = { name = GetENpcResidentName(1052629), position = Vector3(321.218, 53.193, -401.236) }

-- =========================================================
-- Main Script 
-- =========================================================
InfoWindow()
while IsAddonVisible("MultipleHelpWindow") do
    sleep(TIME.POLL)
end

while true do
    local missions = RetrieveRelicResearch()

    local missionAtotal = need(missions, 4) + need(missions, 41001) + need(missions, 41002)
    local missionBtotal = need(missions, 41003) + need(missions, 41004) + need(missions, 41002)

    if missionAtotal > missionBtotal and missionAtotal > 0 then
        local numberof = math.min(missionAtotal, 3)
        DoMission(missionA.name, missionA.position, missionA.id, missionA.node, numberof)

    elseif missionBtotal > 0 then
        local numberof = math.min(missionBtotal, 3)
        DoMission(missionB.name, missionB.position, missionB.id, missionB.node, numberof)

    elseif missionAtotal == 0 and missionBtotal == 0 then
        StellarReturn()
        sleep(0.25)

        if not IPC.TextAdvance.IsEnabled() then
            yield("/at enable")
            EnabledAutoText = true
        end

        log("[Cosmic Miner] Research level met!")
        MoveNearVnav(PhaennaResearchNpc.position)
        log("[Cosmic Miner] Moving to Research bunny")
        sleep(TIME.POLL)

        repeat sleep(TIME.POLL) until InteractByName(PhaennaResearchNpc.name)

        if AwaitAddonReady("SelectString") then
            SafeCallback("SelectString", 0)
        end

        if AwaitAddonReady("SelectIconString") then
            StringId = Player.Job.Id - 8
            SafeCallback("SelectIconString", StringId)
        end

        if AwaitAddonReady("SelectYesno") then
            SafeCallback("SelectYesno", 0)
        end
        repeat sleep(TIME.POLL) until not IsAddonVisible("SelectYesno")

        if EnabledAutoText then
            yield("/at disable")
            EnabledAutoText = false
        end
    else
        sleep(TIME.POLL)
    end
end
