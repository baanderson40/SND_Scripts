--[=====[
[[SND Metadata]]
author: baanderson40
version: 0.0.4
description: Botanist script for Phaenna for relic
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
    Addons.GetAddon("MultipleHelpWindow"):GetNode(1, 3, 2, 3, 4).Text = "Cosmic Botanist\r\rWith ICE supporting DoL missions now you must enable\rmanual mode for the missions below:\r\rPrecise Iridized Rise Survey\rGlass Refinement Materials.\r\r The script will begin after closing this window!"
    Addons.GetAddon("MultipleHelpWindow"):GetNode(1, 2, 2, 2).Text = "Cosmic Botanist - Help"
    Addons.GetAddon("MultipleHelpWindow"):GetNode(1, 5, 2, 3).Text = "Cosmic Botanist"
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
    log("[Cosmic Botanist] awaiting ready: " .. tostring(name))
    local deadline = (timeoutSec or TIME.TIMEOUT)
    local t = 0.0
    while t < deadline do
        local addon = _get_addon(name)
        if addon and addon.Ready then return true end
        sleep(TIME.POLL); t = t + TIME.POLL
    end
    log("[Cosmic Botanist] AwaitAddonReady timeout for: " .. tostring(name))
    return false
end

function IsAddonVisible(name)
    local addon = _get_addon(name)
    return addon and addon.Exists or false
end

function AwaitAddonVisible(name, timeoutSec)
    log("[Cosmic Botanist]awaiting visible: " .. tostring(name))
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
-- Character / Position Helpers
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
        log("[Cosmic Botanist] WaitConditionStable: Svc.Condition unavailable"); return false
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
        if type(v) == "number" then
            call = call .. " " .. tostring(v)
        end
    end

    log("[Cosmic Botanist] calling: " .. call)
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
    Log("[Cosmic Botanist] Stellar Return")
    yield('/gaction "Duty Action"')
    sleep(3)
    repeat sleep(TIME.POLL) until WaitConditionStable(CharacterCondition.normalConditions, 2)
    sleep(TIME.POLL)
end

function Mount()    yield('/gaction "mount roulette"'); sleep(TIME.POLL) end
function Dismount() yield("/ac dismount");               sleep(TIME.POLL) end

function CurrentGP()
    return toNumberSafe(Svc.ClientState.LocalPlayer.CurrentGp)
end

function BlessedHarvestII()  yield('/action "Blessed Harvest II"');  sleep(0.75) end
function PioneersGiftII()    yield('/action "Pioneer\'s Gift II"');  sleep(0.75) end
function PioneersGiftI()     yield('/action "Pioneer\'s Gift I"');   sleep(0.75) end

function FacetedBluegrassCount()       return toNumberSafe(Inventory.GetItemCount(47393)) or 0 end
function FacetedBluegrassCollect()     SafeCallback("Gathering", 2); sleep(1) end
function BluegrassFritCount()          return toNumberSafe(Inventory.GetItemCount(47394)) or 0 end
function BluegrassFritCollect()        SafeCallback("Gathering", 4); sleep(1) end
function FacetedBluegrassRootCount()   return toNumberSafe(Inventory.GetItemCount(47395)) or 0 end
function FacetedBluegrassRootCollect() SafeCallback("Gathering", 6); sleep(1) end
function FacetedGrassRootCount()       return toNumberSafe(Inventory.GetItemCount(47398)) or 0 end
function FacetedGrassRootCollect()     SafeCallback("Gathering", 7); sleep(1) end
function FacetedGrassStemsCount()      return toNumberSafe(Inventory.GetItemCount(47397)) or 0 end
function FacetedGrassStemsCollect()    SafeCallback("Gathering", 4); sleep(1) end
function FacetedGrassCount()           return toNumberSafe(Inventory.GetItemCount(47396)) or 0 end
function FacetedGrassCollect()         SafeCallback("Gathering", 3); sleep(1) end

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
        BlessedHarvestII(); PioneersGiftII(); PioneersGiftI()
    elseif CurrentGP() >= 150 then
        PioneersGiftII(); PioneersGiftI()
    end

    repeat
        if     FacetedBluegrassRootCount() < 20 then FacetedBluegrassRootCollect()
        elseif BluegrassFritCount()        < 15 then BluegrassFritCollect()
        elseif FacetedBluegrassCount()     < 15 then FacetedBluegrassCollect()
        else                                     FacetedBluegrassRootCollect()
        end
    until not IsAddonVisible("Gathering")
end

function MissionBravoComplete()
    local h = FacetedBluegrassRootCount() or 0
    local m = BluegrassFritCount()        or 0
    local p = FacetedBluegrassCount()     or 0
    if h < 20 then return false
    elseif m < 15 then return false
    elseif p < 15 then return false
    elseif (h + m + p) >= 60 then return true end
end

function MissionAlphaGather()
    sleep(TIME.POLL)
    if CurrentGP() >= 650 then
        BlessedHarvestII(); PioneersGiftII(); PioneersGiftI()
    elseif CurrentGP() >= 150 then
        PioneersGiftII(); PioneersGiftI()
    end
    repeat
        if     FacetedGrassCount()      < 15 then FacetedGrassCollect()
        elseif FacetedGrassStemsCount() < 15 then FacetedGrassStemsCollect()
        elseif FacetedGrassRootCount()  < 15 then FacetedGrassRootCollect()
        else                                   FacetedGrassRootCollect()
        end
    until not IsAddonVisible("Gathering")
end

function MissionAlphaComplete()
    local a = FacetedGrassCount()      or 0
    local v = FacetedGrassStemsCount() or 0
    local f = FacetedGrassRootCount()  or 0
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
    if not position then log("[Cosmic Botanist]  DoMission: missing position"); return end
    MissionName = name

    log("[Cosmic Botanist] Moving to ".. tostring(position))
    MoveNearVnav(position, 2)

    log("[Cosmic Botanist] Dismounting")
    Dismount()

    log("[Cosmic Botanist] Starting ICE")
    StartICE(missionId)

    for i = 1, numberof do
        log("[Cosmic Botanist] - (Pandora) Enabling Auto-Interact with Gathering Nodes")
        EnablePandora()

        log("[Cosmic Botanist] Starting wait for mission")
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

            log("[Cosmic Botanist] Waiting for gathering")
            AwaitAddonVisible("Gathering")

            if missionId == 948 then
                log("[Cosmic Botanist] Doing Mission A")
                MissionAlphaGather()
            elseif missionId == 950 then
                log("[Cosmic Botanist] Doing Mission B")
                MissionBravoGather()
            end

            idx = (idx % #nodes) + 1
        until MissionAlphaComplete() or MissionBravoComplete()

        log("[Cosmic Botanist] Mission Complete")
        sleep(TIME.POLL)
        if i >= numberof then StopICE() end

        log("[Cosmic Botanist] Report Mission")
        ReportMission()
        MissionPicked = false

        log("[Cosmic Botanist] - (Pandora) Disable Auto-Interact with Gathering Nodes")
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
    name     = "Precise Iridized Rise Survey",
    position = Vector3(-264.160, 20.315, 163.899),
    id       = 948,
    node     = {
        Vector3(-255.782, 20.880, 160.893),
        Vector3(-251.373, 21.086, 161.462),
        Vector3(-224.286, 20.862, 179.909),
        Vector3(-218.142, 20.717, 184.682),
        Vector3(-215.209, 20.717, 197.586),
        Vector3(-208.331, 20.780, 200.303),
        Vector3(-243.339, 20.850, 211.779),
        Vector3(-245.061, 21.010, 215.409),
    }
}

missionB = {
    name     = "Glass Refinement Materials",
    position = Vector3(-83.884, 1.980, 171.817),
    id       = 950,
    node     = {
        Vector3(-71.634, 2.706, 176.741),
        Vector3(-73.996, 2.704, 167.992),
        Vector3(-122.463, 2.847, 120.669),
        Vector3(-129.567, 2.558, 116.940),
        Vector3(-14.556, -9.342, 79.263),
        Vector3(-16.470, -9.328, 72.524),
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

        log("[Cosmic Botanist] Research level met!")
        MoveNearVnav(PhaennaResearchNpc.position)
        log("[Cosmic Botanist] Moving to Research bunny")
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
