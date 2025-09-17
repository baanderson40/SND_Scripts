--[=====[
[[SND Metadata]]
author: baanderson40
version: 0.0.2
description: Miner script for Phaenna for relic
plugin_dependencies:
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

-- =========================================================
-- Echo / Log Helpers
-- =========================================================
local function _echo(s)
    yield("/echo " .. tostring(s))
end

local function _log(s)
    local msg = tostring(s)
    Dalamud.Log(msg)
    if echoLog then _echo(msg) end
end

Echo, echo = _echo, _echo
Log,  log  = _log,  _log

-- =========================================================
-- Sleep Helpers
-- =========================================================
local function _sleep(seconds)
    seconds = tonumber(seconds) or 0
    if seconds < 0 then seconds = 0 end
    yield("/wait " .. seconds)
end

Sleep, sleep = _sleep, _sleep

-- =========================================================
-- Addon Helpers
-- =========================================================
local function _get_addon(name)
    local ok, addon = pcall(Addons.GetAddon, name)
    if ok and addon ~= nil then
        return addon
    else
        return nil
    end
end

function IsAddonReady(name)
    local addon = _get_addon(name)
    return addon and addon.Ready or false
end

function AwaitAddonReady(name, timeoutSec)
    echo("awaiting ready: " .. tostring(name))
    local deadline = (timeoutSec or 10.0)
    local t = 0.0
    while t < deadline do
        local addon = _get_addon(name)
        if addon and addon.Ready then return true end
        sleep(0.05); t = t + 0.05
    end
    log("[Cosmic Miner] AwaitAddonReady timeout for: " .. tostring(name))
    return false
end

function IsAddonVisible(name)
    local addon = _get_addon(name)
    return addon and addon.Exists or false
end

function AwaitAddonVisible(name, timeoutSec)
    echo("awaiting visible: " .. tostring(name))
    local deadline = (timeoutSec or 10.0)
    local t = 0.0
    while t < deadline do
        local addon = _get_addon(name)
        if addon and addon.Exists then return true end
        sleep(0.05); t = t + 0.05
    end
    log(" AwaitAddonVisible timeout for: " .. tostring(name))
    return false
end

local function WaitAddonStable(addonName, stableSec, timeoutSec, pollSec)
    stableSec  = tonumber(stableSec)  or 2.0
    timeoutSec = tonumber(timeoutSec) or 10.0
    pollSec    = tonumber(pollSec)    or 0.05

    local t, visibleStart = 0.0, nil
    while t < timeoutSec do
        local addon = _get_addon(addonName)
        local visible = (addon and addon.Exists) or false

        if visible then
            if not visibleStart then visibleStart = t end
            if (t - visibleStart) >= stableSec then
                return true
            end
        else
            visibleStart = nil  -- reset the debounce if it closes
        end

        sleep(pollSec); t = t + pollSec
    end
    return false
end

-- =========================================================
-- Node Helpers (path = table of node indices, e.g., {3,5,2})
-- =========================================================
local _unpack = table.unpack or unpack

local function _get_node(addonName, path)
    if type(path) ~= "table" then return nil end
    local addon = _get_addon(addonName)
    if not (addon and addon.Ready) then return nil end
    local ok, node = pcall(function() return addon:GetNode(_unpack(path)) end)
    if ok then return node end
    return nil
end

-- path: table of node indices (e.g., {3,5,2})
-- expected: string OR nil (if nil, only visibility is required)
-- mode: "equals" | "contains" | "pattern"  (default "equals")
-- caseInsensitive: boolean (default true)
function AwaitAddonNodeVisible(addonName, timeoutSec, path, expected, mode, caseInsensitive)
    echo("awaiting node visible: " .. tostring(addonName))
    local deadline = tonumber(timeoutSec) or 10.0
    local t = 0.0
    mode = mode or "equals"
    if caseInsensitive == nil then caseInsensitive = true end

    local function matches(text)
        if expected == nil then return true end
        local lhs, rhs = tostring(text or ""), tostring(expected or "")
        if caseInsensitive then
            lhs = lhs:lower(); rhs = rhs:lower()
        end
        if mode == "equals" then
            return lhs == rhs
        elseif mode == "contains" then
            return lhs:find(rhs, 1, true) ~= nil -- plain find
        elseif mode == "pattern" then
            return lhs:find(rhs) ~= nil          -- pattern match
        else
            -- fallback to equals if an unknown mode is passed
            return lhs == rhs
        end
    end

    while t < deadline do
        local node = _get_node(addonName, path)
        if node and node.IsVisible then
            local text = tostring(node.Text or "")
            if matches(text) then
                return true
            end
        end
        sleep(0.05); t = t + 0.05
    end

    local lastText = ""
    local node = _get_node(addonName, path)
    if node then lastText = tostring(node.Text or "") end
    Log(string.format("AwaitAddonNodeVisible timeout for: %s (last Text='%s')",
        tostring(addonName), lastText))
    return false
end


function IsNodeVisible(addonName, path)
    local node = _get_node(addonName, path)
    return node and node.IsVisible or false
end

function GetNodeText(addonName, path)
    local node = _get_node(addonName, path)
    return node and tostring(node.Text or "") or ""
end

function GetNodeType(addonName, path)
    local node = _get_node(addonName, path)
    return node and tostring(node.NodeType or "") or ""
end

function GetMyNode(addonName, index)
    local addon = _get_addon(addonName)
    if not (addon and addon.Ready) then return nil end
    local nodes = addon.Nodes
    return nodes and nodes[index] or nil
end

function GetNodeText2(addonName, path)
    if not AwaitAddonReady(addonName, 5) then return "" end
    return GetNodeText(addonName, path)
end

-- =========================================================
-- Character / Target / Position Helpers
-- =========================================================
function GetCharacterName()
    return (Entity and Entity.Player and Entity.Player.Name) or ""
end

function GetCharacterCondition(i, bool)
    if bool == nil then bool = true end
    return Svc and Svc.Condition and (Svc.Condition[i] == bool) or false
end

-- Wait until Svc.Condition[idx] == want for `stableSec` seconds straight.
-- Returns true on success, false on timeout.
function WaitConditionStable(idx, want, stableSec, timeoutSec, pollSec)
    want       = (want ~= false)                 -- default true
    stableSec  = tonumber(stableSec)  or 2.0     -- how long it must hold
    timeoutSec = tonumber(timeoutSec) or 15.0    -- total wait budget
    pollSec    = tonumber(pollSec)    or 0.05

    if not (Svc and Svc.Condition) then
        log(" WaitConditionStable: Svc.Condition unavailable"); return false
    end

    local t, startHold = 0.0, nil
    while t < timeoutSec do
        local ok = GetCharacterCondition(idx, want) -- your helper
        if ok then
            if not startHold then startHold = t end
            if (t - startHold) >= stableSec then
                return true
            end
        else
            startHold = nil -- broke the streak; reset debounce
        end
        sleep(pollSec); t = t + pollSec
    end

    Log(string.format("WaitConditionStable timeout (idx=%s want=%s stable=%.2fs)",
        tostring(idx), tostring(want), stableSec))
    return false
end

function IsInZone(id)
    return Svc and Svc.ClientState and (Svc.ClientState.TerritoryType == id) or false
end

function GetTargetName()
    return (Entity and Entity.Target and Entity.Target.Name) or ""
end

function GetDistanceToTarget()
    if not (Entity and Entity.Player and Entity.Target) then return math.huge end
    return Vector3.Distance(Entity.Player.Position, Entity.Target.Position)
end

function DistanceBetweenPositions(pos1, pos2)
    if not (pos1 and pos2) then return math.huge end
    return Vector3.Distance(pos1, pos2)
end

function GetTargetName()
    return (Entity and Entity.Target and Entity.Target.Name) or ""
end

function InteractByName(name, timeout)
    timeout = timeout or 5
    local e = Entity.GetEntityByName(name)
    if not e then return false end

    local start = os.clock()
    while (os.clock() - start) < timeout do
        e:SetAsTarget()
        sleep(.05)
        if Entity.Target or Entity.Target.Name ~= name then
            e:Interact()
            return true
        end
        sleep(0.05)
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

    echo("calling: " .. call)
    if IsAddonReady(addon) and IsAddonVisible(addon) then
        yield(call)
    else
        log(" SafeCallback: addon not ready/visible: " .. addon)
    end
end

-- =========================================================
-- Plugins
-- =========================================================
function HasPlugin(name)
    for plugin in luanet.each(Svc.PluginInterface.InstalledPlugins) do
        if plugin.InternalName == name and plugin.IsLoaded then return true end
    end
    return false
end

function GetPlugins()
    local plugins = {}
    for plugin in luanet.each(Svc.PluginInterface.InstalledPlugins) do
        table.insert(plugins, { name = plugin.InternalName, loaded = plugin.IsLoaded })
    end
    table.sort(plugins, function(a,b) return a.name:lower() < b.name:lower() end)

    log(" Installed plugins:")
    for _, p in ipairs(plugins) do
        Log(string.format("  %s | Enabled: %s", p.name, tostring(p.loaded)))
    end
end

function OnChatMessage()
    local message = TriggerData.message
    if message and message:find(MissionName, 1, true) and message:find("underway") then
        MissionPicked = true
        return
    end
    MissionPicked = false
end

function StartICE(missionId)
    yield('/ice only '..missionId)
    sleep(.05)
    yield('/ice start')
    sleep(.05)
end

function StopICE()
    yield('/ice stop')
    sleep(.05)
end

function EnablePandora()
    IPC.PandorasBox.SetFeatureEnabled("Auto-interact with Gathering Nodes", true)
    sleep(.05)
end

function DisablePandora()
    IPC.PandorasBox.SetFeatureEnabled("Auto-interact with Gathering Nodes", false)
    sleep(.05)
end

function StellarReturn()
    Log(" Stellar Return")
    yield('/gaction "Duty Action"')
    sleep(4)
    repeat
        sleep(0.1)
    until not GetCharacterCondition(CharacterCondition.casting)
        and not GetCharacterCondition(CharacterCondition.betweenAreas) and not Player.IsBusy
    sleep(.05)
end


function Mount()
    yield('/gaction "mount roulette"')
    sleep(.05)
end

function Dismount()
    yield("/ac dismount")
    sleep(.05)
end

function CurrentGP()
    return toNumberSafe(Svc.ClientState.LocalPlayer.CurrentGp)
end

function KingYieldII()

    yield('/action "King\'s Yield II"')
    sleep(.75)
end

function MountaineersGiftII()
    yield('/action "Mountaineer\'s Gift II"')
    sleep(.75)
end

function MountaineersGiftI()
    yield('/action "Mountaineer\'s Gift I"')
    sleep(.75)
end

function PegmatiteCount()
    return toNumberSafe(Inventory.GetItemCount(47362)) or 0
end

function PegmatiteCollect()
    SafeCallback("Gathering", 2)
    sleep(1)
end

function MilkyQuartzCount()
    return toNumberSafe(Inventory.GetItemCount(47363)) or 0
end

function MilkyQuartzCollect()
    SafeCallback("Gathering", 4)
    sleep(1)
end

function HighsilicaWaterCount()
    return toNumberSafe(Inventory.GetItemCount(47364)) or 0
end

function HighsilicaWaterCollect()
    SafeCallback("Gathering", 6)
    sleep(1)
end

function PhaennaFeldsparCount()
    return toNumberSafe(Inventory.GetItemCount(47365)) or 0
end

function PhaennaFeldsparCollect()
    SafeCallback("Gathering", 3)
    sleep(1)
end

function ObsidianVitrisandCount()
    return toNumberSafe(Inventory.GetItemCount(47366)) or 0
end

function ObsidianVitrisandCollect()
    SafeCallback("Gathering", 4)
    sleep(1)
end

function PhaennaAlumanCount()
    return toNumberSafe(Inventory.GetItemCount(47367)) or 0
end

function PhaennaAlumanCollect()
    SafeCallback("Gathering", 7)
    sleep(1)
end
-- =========================================================
-- VNAV Helpers
-- =========================================================
function PathandMoveVnav(dest, fly)
    fly = (fly == true) -- default false
    local t, timeout = 0, 10.0
    while not IPC.vnavmesh.IsReady() and t < timeout do
        sleep(0.05); t = t + 0.05
    end
    if not IPC.vnavmesh.IsReady() then
        log("[Cosmic Miner]  VNAV not ready (timeout)")
        return false
    end
    local ok = IPC.vnavmesh.PathfindAndMoveTo(dest, fly)
    if not ok then log("[Cosmic Miner] VNAV pathfind failed") end
    return ok and true or false
end

function StopCloseVnav(dest, stopDistance)
    stopDistance = tonumber(stopDistance) or 3.0
    if not dest then return end
    local t, timeout = 0, 10.0
    while not IPC.vnavmesh.IsRunning() and t < timeout do
        sleep(0.05); t = t + 0.05
    end
    if not IPC.vnavmesh.IsRunning() then
        log("[Cosmic Miner]  VNAV not running (timeout)")
        return false
    end
    while IPC.vnavmesh.IsRunning() do
        local me = Entity and Entity.Player
        if me and me.Position then
            if Vector3.Distance(me.Position, dest) < stopDistance then
                IPC.vnavmesh.Stop()
                break
            end
        end
        sleep(0.05)
    end
end

function MoveNearVnav(dest, stopDistance, fly)
    stopDistance = tonumber(stopDistance) or 3.0
    if PathandMoveVnav(dest, fly) then
        return StopCloseVnav(dest, stopDistance)
    end
    return false
end

function MissionBravoGather()
    sleep(0.05)
    if CurrentGP() >= 650 then
        KingYieldII(); MountaineersGiftII(); MountaineersGiftI()
    elseif CurrentGP() >= 150 then
        MountaineersGiftII(); MountaineersGiftI()
    end

    repeat
    if HighsilicaWaterCount() < 20 then
        HighsilicaWaterCollect()
    elseif MilkyQuartzCount() < 15 then
        MilkyQuartzCollect()
    elseif PegmatiteCount() < 15 then
        PegmatiteCollect()
    else
        HighsilicaWaterCollect()
    end
    until not IsAddonVisible("Gathering")
end

function MissionBravoComplete()
    local h = HighsilicaWaterCount() or 0
    local m = MilkyQuartzCount() or 0
    local p = PegmatiteCount() or 0
    if h < 20 then return false
    elseif m < 15 then return false
    elseif p < 15 then return false
    elseif (h + m + p) >= 60 then return true end
end


function MissionAlphaGather()
    sleep(0.05)
    if CurrentGP() >= 650 then
        KingYieldII(); MountaineersGiftII(); MountaineersGiftI()
    elseif CurrentGP() >= 150 then
        MountaineersGiftII(); MountaineersGiftI()
    end
    repeat
    if PhaennaAlumanCount() < 15 then
        PhaennaAlumanCollect()
    elseif ObsidianVitrisandCount() < 15 then
        ObsidianVitrisandCollect()
    elseif PhaennaFeldsparCount() < 15 then
        PhaennaFeldsparCollect()
    else
        PhaennaFeldsparCollect()
    end
    until not IsAddonVisible("Gathering")
end

function MissionAlphaComplete()
    local a = PhaennaAlumanCount() or 0
    local v = ObsidianVitrisandCount() or 0
    local f = PhaennaFeldsparCount() or 0
    if a < 15 then return false
    elseif v < 15 then return false
    elseif f < 15 then return false
    elseif (a + v + f) >= 50 then return true end
end

function ReportMission()
    SafeCallback("WKSMissionInfomation", 11)
    sleep(.05)
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
-- Worker Funcitons
-- =========================================================

-- Returns a table of remaining needed per row.
-- Keys = row IDs, Values = how many still needed (0 if complete).
function RetrieveRelicResearch()
    repeat
    if not IsAddonVisible("WKSToolCustomize") and IsAddonVisible("WKSHud") then
        SafeCallback("WKSHud", 15)
        sleep(0.25)
    end
    until IsAddonVisible("WKSToolCustomize")
    local ToolAddon = Addons.GetAddon("WKSToolCustomize")

    -- Divisor rules for rows
    local rowDivisors = {
        [4]     = 30,
        [41001] = 30,
        [41002] = 1,   -- no division, just raw deficit
        [41003] = 40,
        [41004] = 25,
    }

    local rows = { 4, 41001, 41002, 41003, 41004 }
    local remainingByRow = {}

    for _, row in ipairs(rows) do
        local currentNode  = ToolAddon:GetNode(1, 55, 68, row, 4, 5)
        local requiredNode = ToolAddon:GetNode(1, 55, 68, row, 4, 7)

        if not currentNode or not requiredNode then
            break
        end

        local current  = toNumberSafe(currentNode.Text) or 0
        local required = toNumberSafe(requiredNode.Text) or 0

        local deficit = 0
        if required > current then
            deficit = required - current
        end

        local divisor = rowDivisors[row] or 1
        if divisor > 1 then
            remainingByRow[row] = math.ceil(deficit / divisor)
        else
            remainingByRow[row] = deficit
        end
    end
    sleep(.05)
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
        repeat
            sleep(.05)
        until MissionPicked
        sleep(1)
        if not IsAddonVisible("WKSMissionInfomation") then
            repeat
                SafeCallback("WKSHud", 11)
                sleep(2)
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
        sleep(.05)
        if i >= 3 then StopICE() end
        log("[Cosmic Miner] Report Mission")
        ReportMission()

        log("[Cosmic Miner] - (Pandora) Disable Auto-Interact with Gathering Nodes")
        DisablePandora()
        MoveNearVnav(nodes[1])
    end
end

-- =========================================================
-- Script Settings 
-- =========================================================

 CharacterCondition = {
    normalConditions                   = 1, -- moving or standing still
    mounted                            = 4, -- moving
    crafting                           = 5,
    gathering                          = 6,
    casting                            = 27,
    occupiedInQuestEvent               = 32,
    occupied33                         = 33,
    occupiedMateriaExtractionAndRepair = 39,
    executingCraftingAction            = 40,
    preparingToCraft                   = 41,
    executingGatheringAction           = 42,
    fishing                            = 43,
    betweenAreas                       = 45,
    jumping48                          = 48, -- moving
    occupiedSummoningBell              = 50,
    mounting57                         = 57, -- moving
    unknown85                          = 85, -- Part of gathering
 }

missionA = {
    name = "Soda-lime Float Survey",
    position = Vector3(-263.495, -8.297, -41.192),
    id = 906,
    node = {Vector3(-269.733, -6.921, -40.614),
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
    name = "Glass Refinement Materials",
    position = Vector3(-293.606, 18.787, 132.563),
    id = 908,
    node = {Vector3(-290.602, 20.749, 143.793),
            Vector3(-299.463, 21.232, 141.520),
            Vector3(-375.364, 16.603, 76.825),
            Vector3(-374.672, 16.602, 67.367),
            Vector3(-290.435, 16.255, 56.018),
            Vector3(-283.031, 16.306, 57.604),
        }
    }

PhaennaGateHub = Vector3(340.721, 52.864, -418.183)
PhaennaResearchNpc = {name = GetENpcResidentName(1052629), position = Vector3(321.218, 53.193, -401.236)}

-- =========================================================
-- Main Script 
-- ========================================================= 

while true do
    local missions = RetrieveRelicResearch()

    local missionAtotal = need(missions, 4) + need(missions, 41001)
    local missionBtotal = need(missions, 41003) + need(missions, 41004)

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
        sleep(.05)
        repeat
            sleep(.05)
        until InteractByName(PhaennaResearchNpc.name)
        repeat
            sleep(.05)
        until AwaitAddonReady("SelectString")
        if IsAddonReady("SelectString") then
            SafeCallback("SelectString", 0)
        end
        repeat
            sleep(.05)
        until AwaitAddonReady("SelectIconString")
        if IsAddonReady("SelectIconString") then
            StringId = Player.Job.Id - 8
            SafeCallback("SelectIconString", StringId)
        end
        repeat
            sleep(.05)
        until AwaitAddonReady("SelectYesno")
        if IsAddonReady("SelectYesno") then
            SafeCallback("SelectYesno", 0)
        end
        repeat
            sleep(.05)
        until not IsAddonVisible("SelectYesno")
        if EnabledAutoText then
            yield("/at disable")
            EnabledAutoText = false
        end
    else
        sleep(0.5)
    end
end
