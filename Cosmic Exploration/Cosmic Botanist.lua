--[=====[
[[SND Metadata]]
author: baanderson40
version: 0.0.2
description: Botanist script for Phaenna for relic
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
    log("[Cosmic Botanist] AwaitAddonReady timeout for: " .. tostring(name))
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
    sleep(.1)
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

function BlessedHarvestII()
    yield('/action "Blessed Harvest II"')
    sleep(.75)
end

function PioneersGiftII()
    yield('/action "Pioneer\'s Gift II"')
    sleep(.75)
end

function PioneersGiftI()
    yield('/action "Pioneer\'s Gift I"')
    sleep(.75)
end

function FacetedBluegrassCount()
    return toNumberSafe(Inventory.GetItemCount(47393)) or 0
end

function FacetedBluegrassCollect()
    SafeCallback("Gathering", 2)
    sleep(1)
end

function BluegrassFritCount()
    return toNumberSafe(Inventory.GetItemCount(47394)) or 0
end

function BluegrassFritCollect()
    SafeCallback("Gathering", 4)
    sleep(1)
end

function FacetedBluegrassRootCount()
    return toNumberSafe(Inventory.GetItemCount(47395)) or 0
end

function FacetedBluegrassRootCollect()
    SafeCallback("Gathering", 6)
    sleep(1)
end

function FacetedGrassRootCount()
    return toNumberSafe(Inventory.GetItemCount(47398)) or 0
end

function FacetedGrassRootCollect()
    SafeCallback("Gathering", 7)
    sleep(1)
end

function FacetedGrassStemsCount()
    return toNumberSafe(Inventory.GetItemCount(47397)) or 0
end

function FacetedGrassStemsCollect()
    SafeCallback("Gathering", 4)
    sleep(1)
end

function FacetedGrassCount()
    return toNumberSafe(Inventory.GetItemCount(47396)) or 0
end

function FacetedGrassCollect()
    SafeCallback("Gathering", 3)
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
        log("[Cosmic Botanist]  VNAV not ready (timeout)")
        return false
    end
    local ok = IPC.vnavmesh.PathfindAndMoveTo(dest, fly)
    if not ok then log("[Cosmic Botanist] VNAV pathfind failed") end
    if ok then
        local me = Entity and Entity.Player
        if me and me.Position then
            if Vector3.Distance(me.Position, dest) > 25 then
                Mount()
            end
        end
    end
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
        log("[Cosmic Botanist]  VNAV not running (timeout)")
        return false
    end
    while IPC.vnavmesh.IsRunning() do
        local me = Entity and Entity.Player
        if me and me.Position then
            if Vector3.Distance(me.Position, dest) < 10 then
                if GetCharacterCondition(CharacterCondition.mounted) then
                    Dismount()
                end
            end
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
        BlessedHarvestII(); PioneersGiftII(); PioneersGiftI()
    elseif CurrentGP() >= 150 then
        PioneersGiftII(); PioneersGiftI()
    end

    repeat
    if FacetedBluegrassRootCount() < 20 then
        FacetedBluegrassRootCollect()
    elseif BluegrassFritCount() < 15 then
        BluegrassFritCollect()
    elseif FacetedBluegrassCount() < 15 then
        FacetedBluegrassCollect()
    else
        FacetedBluegrassRootCollect()
    end
    until not IsAddonVisible("Gathering")
end

function MissionBravoComplete()
    local h = FacetedBluegrassRootCount() or 0
    local m = BluegrassFritCount() or 0
    local p = FacetedBluegrassCount() or 0
    if h < 20 then return false
    elseif m < 15 then return false
    elseif p < 15 then return false
    elseif (h + m + p) >= 60 then return true end
end

function MissionAlphaGather()
    sleep(0.05)
    if CurrentGP() >= 650 then
        BlessedHarvestII(); PioneersGiftII(); PioneersGiftI()
    elseif CurrentGP() >= 150 then
        PioneersGiftII(); PioneersGiftI()
    end
    repeat
    if FacetedGrassCount() < 15 then
        FacetedGrassCollect()
    elseif FacetedGrassStemsCount() < 15 then
        FacetedGrassStemsCollect()
    elseif FacetedGrassRootCount() < 15 then
        FacetedGrassRootCollect()
    else
        FacetedGrassRootCollect()
    end
    until not IsAddonVisible("Gathering")
end

function MissionAlphaComplete()
    local a = FacetedGrassCount() or 0
    local v = FacetedGrassStemsCount() or 0
    local f = FacetedGrassRootCount() or 0
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
        sleep(.05)
        if i >= 3 then StopICE() end
        log("[Cosmic Botanist] Report Mission")
        ReportMission()

        log("[Cosmic Botanist] - (Pandora) Disable Auto-Interact with Gathering Nodes")
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
    name = "Precise Iridized Rise Survey",
    position = Vector3(-264.160, 20.315, 163.899),
    id = 948,
    node = {Vector3(-255.782, 20.880, 160.893),
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
    name = "Glass Refinement Materials",
    position = Vector3(-83.884, 1.980, 171.817),
    id = 950,
    node = {Vector3(-71.634, 2.706, 176.741),
            Vector3(-73.996, 2.704, 167.992),
            Vector3(-122.463, 2.847, 120.669),
            Vector3(-129.567, 2.558, 116.940),
            Vector3(-14.556, -9.342, 79.263),
            Vector3(-16.470, -9.328, 72.524),
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
        log("[Cosmic Botanist] Research level met!")
        MoveNearVnav(PhaennaResearchNpc.position)
        log("[Cosmic Botanist] Moving to Research bunny")
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
