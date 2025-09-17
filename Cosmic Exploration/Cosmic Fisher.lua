--[=====[
[[SND Metadata]]
author: baanderson40
version: 0.0.2
description: |
  Fisher script for Phaenna for relic

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
    log("[Cosmic Fisher] AwaitAddonReady timeout for: " .. tostring(name))
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
    log("[Cosmic Fisher] AwaitAddonVisible timeout for: " .. tostring(name))
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
        log("[Cosmic Fisher] WaitConditionStable: Svc.Condition unavailable"); return false
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

-- =========================================================
-- Safe Callback
-- =========================================================
function SafeCallback(...)
    local args = {...}
    local idx = 1

    local addon = args[idx]; idx = idx + 1
    if type(addon) ~= "string" then
        log("[Cosmic Fisher] SafeCallback: first arg must be addon name (string)")
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
        log("[Cosmic Fisher] SafeCallback: addon not ready/visible: " .. addon)
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

    log("[Cosmic Fisher] Installed plugins:")
    for _, p in ipairs(plugins) do
        Log(string.format("  %s | Enabled: %s", p.name, tostring(p.loaded)))
    end
end

function OnChatMessage()
    local message = TriggerData.message
    if message and message:find(MissionName) and message:find("underway") then
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

function SetAH(preset)
    IPC.AutoHook.CreateAndSelectAnonymousPreset(preset)
    sleep(.05)
    IPC.AutoHook.SetPluginState(true)
    sleep(.05)
end

function UnSetAH()
    IPC.AutoHook.DeleteAllAnonymousPresets()
    sleep(.05)
end

function StartAH()
    yield('/ahstart')
    sleep(.05)
end

function StellarReturn()
    Log("[Cosmic Fisher] Stellar Return")
    yield('/gaction "Duty Action"')
    sleep(3)
    repeat
        sleep(.05)
    until GetCharacterCondition(CharacterCondition.normalConditions)
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
        log("[Cosmic Fisher] VNAV not ready (timeout)")
        return false
    end
    local ok = IPC.vnavmesh.PathfindAndMoveTo(dest, fly)
    if not ok then log("[Cosmic Fisher] VNAV pathfind failed") end
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
        log("[Cosmic Fisher] VNAV not running (timeout)")
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
local function toNumberSafe(s)
    if s == nil then return nil end
    local str = tostring(s):gsub("[^%d%-%.]", "")
    return tonumber(str)
end

local function need(tbl, key)
    if not tbl then return 0 end
    return tonumber(tbl[key] or 0) or 0
end


-- =========================================================
-- Worker Funcitons
-- =========================================================

-- Returns a table of remaining needed per row.
-- Keys = row IDs, Values = how many still needed (0 if complete).
function RetrieveRelicResearch()
    if not IsAddonVisible("WKSToolCustomize") and IsAddonVisible("WKSHud") then
        SafeCallback("WKSHud", 15)
        sleep(0.25)
    end
    repeat
        sleep(.05)
    until AwaitAddonVisible("WKSToolCustomize")
    local ToolAddon = Addons.GetAddon("WKSToolCustomize")

    -- Divisor rules for rows
    local rowDivisors = {
        [4]     = 55,
        [41001] = 55,
        [41002] = 1,   -- no division, just raw deficit
        [41003] = 50,
        [41004] = 50,
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

function DoMission(name, position, preset, missionId, numberof)
    numberof = tonumber(numberof) or 1
    if not position then log("[Cosmic Fisher] DoMission: missing position"); return end
    MissionName = name

    log("[Cosmic Fisher] Moving to ".. tostring(position))
    MoveNearVnav(position, 2)

    log("[Cosmic Fisher] Dismounting")
    Dismount()

    log("[Cosmic Fisher] Starting ICE")
    StartICE(missionId)

    log("[Cosmic Fisher] Setting AutoHook preset")
    SetAH(preset)

    for i = 1, numberof do
        log("[Cosmic Fisher] Starting wait for mission")
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
        StartAH()
        sleep(5)
        -- Ensure we are NOT gathering/fishing for 1.0s before reporting
        -- (use CharacterCondition.gathering unless you have a specific 'fishing' flag)
        repeat
            sleep(.05)
        until WaitConditionStable(CharacterCondition.fishing, false, 2, 10.0, 0.05)
        if i >= 3 then StopICE() end
        ReportMission()
    end
    UnSetAH()
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
    name = "Cultivated Specimen Survey",
    position = Vector3(217.964, 133.719, -740.187),
    id = 986,
    ahPreset = "AH4_H4sIAAAAAAAACu1XS2/bOBD+KwHPIqAH9fLNcZNsgDQJ6nR7CPYwEkc2EVl0KSpbb+D/vqAetuTYcRt40T3kJpEz33wz+jgcvZBxpeUESl1OshkZvZCLApIcx3lORlpVaBGzeSMK3G7ybuuak5EbxRa5V0IqoVdk5Fjkurz4keYVR75dNvbrBuuzlOncgNUPrnmqcYLIIlfLh7nCci5zTkaObQ+Q34auMeJw4GEfJTOZV4uOAXNsdoRC5yXzHFPdc3T6Zu7xsFJxAXkHEDhsAMBas0tRzi9WWPYC+TsMfX/AMOiKDE84nYtMn4OoeZqFsluYakifSjLy27IF0WvcPmrcot6DFlik2OMT7PoFw4q5nasS/+AEdPPpu6i73u5Ovb3W+2EOuYCn8hKepTIAg4UuHc8arn/BVD6jIiPHFGmfdoPIfPJewK5+52J2BYs60XExy1GVXRDzcTkZeaHNXrEfQEXrtUUufmgFg5O1IWA+xIOc/g3L60JXQgtZXIEouvJQxyI3lcLPWJYwQzIixCK3NSdyKwskLcJqiWRk6rQH70aW+t149wpL3M+QUHJgv4lY72/5TJeYagX5pFIKC32iLHdQT5brXravMt4bvba6lCpFbvDrIxIGsWe1IppquTRnWhSzqcZl3S23CbVCG6vT5NGHq4l9LcT3Cg0uSZPA87iTUi9xGGVxmNEoyQLqOX7iQeQwdJCsLXIjSn2XmRglGT2+1NFMAhuCcXyY4TjPzxrXXZq3Ui0g/0PKJwPUdZVvCPW7WS9Rb45LBnmJ3fltN02C3UFqlxp45oSmW3WYU61k0Tt9x91tr+d+gzMsOKjVCXjVwJ9kleS7mTYWbhBvDLa0D5rso9a3elBieShS6LvexuRQrIHRG9FaO6PtcaZRTaCazfWNWJiLx2k2dkVfzxSVam4289Br4Xv6tBf68eur+Y1b1swDXUvqZPYFv1dCIZ9q0JW5/MzA8Zu1d1fkq29zLMapFs94zbHQIjVzwS9K80ODv67BryVOqlLLRSOIRia9kfe/lWevGTse9yBwOUU3BMpsZtPIjSOKmRPZGUuAhxFZ/9V143Z+ftwsNA358YVczwqp8K7YSL8j2W/ZzNTqcNP+JOUC+dmfcgUzVIPO7bxV4Y12Te1MrMZgvJBV0TPbUz3mx7uDlDccaiMTuFIZpDjNjbbbTPzYPzI/+muL/G/+N7Y3/bvvd+NsViamqnVB+zd+e8+bx2Z5a7b3AGwlGIfgI0NO0c8SylzOaJImQG0XnQw8J0YbyNp6eaUkdjiBc6m1XNAcVsd11Olhv7zcn5bXh55+m55so4X+iBmlQcjSmEYQcMqQ2zQCyKjnQmrbvosZJLWkfrprvZHcVIM6myhItJnWT9203q2q/d3uQ2T3J2laqZMkCAGj4KYuZbYX0TjJXBpwHiaul7peAPW92eC2FCdVrsUzaORn5h9OLLA4m1bqGVfDXyQWRQkPApuCzSPKMh9oYkNKmZOAz2MfEuRk/S+bc5nAQBMAAA=="
}
missionB = {
    name = "Elemental-esque Aquaculture Specimens",
    position = Vector3(381.041, 27.040, -76.952),
    id = 988,
    ahPreset = "AH4_H4sIAAAAAAAACs1WTW/bOBD9KwHPUkHJFC3p5rpuNoCTDWoHeyj2QEkjmwgtOiTVbTbwf19QEmNbtlt1kXb3JpEzb958cl7QpDZyyrTR03KF0hc0q1gmYCIESo2qwUMfZGWmrMpB3EqZr1FaMqHBQ1ZpzivYKxVO5aZAaRgnl3XvFZeKm2eUBh660bOvuagLKPbHFmfX2ug0X1DzEdqvBp/GHrreLtcK9FqKAqUBxkfI34ZuMJLxII74uySn63pzIRAkwKTHNLJMB9h14FIIyI3znAQ4GKIefp+1VAVn4gLxAGMakEGmSAf4kev17Bn0AdWo73s0yHfqss8eYbHmpXnPeBMBe6DdwcKw/FGjNOrySeNTe0OsJZ21e2Y4VDkc8Kd9PDosd6GDVPxvmDLT1rBj2UcNB1bEqENdrpng7FF/ZF+kssBHBy4sI+/4/BPk8gsolAY2Ceealsa2WAcQcfl5z1fXbNMEbFKtBCjtjNvyK1A6GmNy4u0gE/Fu56HZV6NYN5psxpdy8Rfb3lSm5obL6prxysXVDzw0rxXcgtZsBShFyEN3DTl0JytAXovwvAWU2kCewZtLbf413r0CDecZIh9duG8tNvd7Post5EYxMa2Vgsq8kZc91Dfz9SzbE4/PWm+k2sJZGLm184NXq4WBbfM07Ll3xTVRb0P5EK7h8FDxpxosLiqKPAtDHPt0jMc+ScLIz4oSfJpkOCBACxYQtPPQnGvze2ltaJR+bsvTOvBKMEkuM5wIcdWq9mneSbVh4jcpHy2Qm0h/AGv+26a1txqM9cS1b3fU4pBgbEeaU14YJavVj6jj0YH6HFZQFUw9/zDCg4YPsu7k9wuFPXEO2Zsl34DqjaNbXr1e2WHwDnvIvrLnZO15Tx6/i3uUQmpD0hrfB+Q/MX8U0F/MYKn49jj6e4FxFI5eRY5jdEHoxJMTOdvWk9KAmrJ6tTZzvrHveBC1N8cNj0PS7ZW1apcI+3HwmrUPSpT0F6pvbmh22XPT1rXVJ3iquYJiYZip7QJht8l+rw1rqcGdc07wtBcG1Ouwmvp/5v1c2n9Ozh/2E50EUIaUMj/HNPFJGRM/znDox9G4CBjBJEso2v3pRnq3kXx+PWinuv1v35Buhs8EbKAyTPign2q4mjzVLK+FAXVlHzu+gcqO9wMiGGdJFuYjPx8z7JMyI35csMiPaZLQLMcjCiHa/QOhkWZllQ0AAA=="
    }

PhaennaGateHub = Vector3(340.721, 52.864, -418.183)
PhaennaResearchNpc = {name = GetENpcResidentName(1052629), position = Vector3(321.218, 53.193, -401.236)}

-- =========================================================
-- Main Script 
-- ========================================================= 

while true do
    if not GetCharacterCondition(CharacterCondition.mounted) then Mount() end
    local missions = RetrieveRelicResearch()

    local missionAtotal = need(missions, 4) + need(missions, 41001)
    local missionBtotal = need(missions, 41003) + need(missions, 41004)

    if missionAtotal > missionBtotal and missionAtotal > 0 then
        local numberof = math.min(missionAtotal, 3)
        DoMission(missionA.name, missionA.position, missionA.ahPreset, missionA.id, numberof)
        StellarReturn()
    elseif missionBtotal > 0 then
        local numberof = math.min(missionBtotal, 3)
        DoMission(missionB.name, missionB.position, missionB.ahPreset, missionB.id, numberof)
        StellarReturn()
    elseif missionAtotal == 0 and missionBtotal == 0 then
        if not IPC.TextAdvance.IsEnabled() then
            yield("/at enable")
            EnabledAutoText = true
        end
        log("[Cosmic Fisher] Research level met!")
        MoveNearVnav(PhaennaResearchNpc.position)
        log("[Cosmic Fisher] Moving to Research bunny")
        sleep(.05)
        local e = Entity.GetEntityByName(PhaennaResearchNpc.name)
        if e then
            log("[Cosmic Fisher] Targetting: " .. PhaennaResearchNpc.name)
            e:SetAsTarget()
        end
        if Entity.Target and Entity.Target.Name == PhaennaResearchNpc.name then
            log("[Cosmic Fisher] Interacting: " .. PhaennaResearchNpc.name)
            e:Interact()
            sleep(1)
        end
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
