--[=====[
[[SND Metadata]]
author: baanderson40
version: 0.0.4a
description: Fisher script for Phaenna for relic
plugin_dependencies:
- vnavmesh
- AutoHook
- ICE

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
    echo("awaiting ready: " .. tostring(name))
    local deadline = tonumber(timeoutSec) or TIME.TIMEOUT
    local t = 0.0
    while t < deadline do
        local addon = _get_addon(name)
        if addon and addon.Ready then return true end
        sleep(TIME.POLL); t = t + TIME.POLL
    end
    log("[Cosmic Fisher] AwaitAddonReady timeout for: " .. tostring(name))
    return false
end

function IsAddonVisible(name)
    local addon = _get_addon(name)
    return addon and addon.Exists or false
end

-- =========================================================
-- Character / Condition Helpers
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
        log("[Cosmic Fisher] WaitConditionStable: Svc.Condition unavailable"); return false
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

function WaitZoneChange()
    sleep(1)
    while Svc.Condition[CharacterCondition.casting]
        or Svc.Condition[CharacterCondition.betweenAreas]
        or Svc.Condition[CharacterCondition.betweenAreasForDuty]
        or Svc.Condition[CharacterCondition.occupiedInQuestEvent] do
            sleep(0.05)
        end
    sleep(0.5)
    return true
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

function SetAH(preset)
    IPC.AutoHook.CreateAndSelectAnonymousPreset(preset); sleep(TIME.POLL)
    IPC.AutoHook.SetPluginState(true);                   sleep(TIME.POLL)
end

function UnSetAH()
    IPC.AutoHook.DeleteAllAnonymousPresets(); sleep(TIME.POLL)
end

function StartAH()
    yield('/ahstart'); sleep(TIME.POLL)
end

function StellarReturn()
    Log("[Cosmic Fisher] Stellar Return")
    yield('/gaction "Duty Action"')
    sleep(3)
    repeat sleep(TIME.POLL) until WaitConditionStable(CharacterCondition.normalConditions, 2)
    sleep(TIME.POLL)
end

function Mount()    yield('/gaction "mount roulette"'); sleep(TIME.POLL) end
function Dismount() yield("/ac dismount");              sleep(TIME.POLL) end

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
    local t, timeout = 0, TIME.TIMEOUT
    while not IPC.vnavmesh.IsRunning() and t < timeout do
        sleep(TIME.POLL); t = t + TIME.POLL
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
-- Worker Functions
-- =========================================================
function RetrieveRelicResearch()
    repeat
        if not IsAddonVisible("WKSToolCustomize") and IsAddonVisible("WKSHud") then
            SafeCallback("WKSHud", 15)
            sleep(0.25) -- one-shot UI settle
        end
        sleep(TIME.POLL)
    until IsAddonVisible("WKSToolCustomize")

    local ToolAddon = Addons.GetAddon("WKSToolCustomize")

    -- Divisor rules for rows
    local rowDivisors = {
        [4]     = 55,
        [41001] = 55,
        [41002] = 55,
        [41003] = 70,
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

        local current  = toNumberSafe(currentNode.Text)  or 0
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

    sleep(TIME.POLL)
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
        repeat sleep(TIME.POLL) until MissionPicked
        sleep(1)

        if not IsAddonVisible("WKSMissionInfomation") then
            repeat
                SafeCallback("WKSHud", 11)
                sleep(2)
            until IsAddonVisible("WKSMissionInfomation")
        end

        StartAH()
        sleep(5)

        repeat sleep(TIME.POLL)
        until WaitConditionStable(CharacterCondition.fishing, false, 2, 10.0, TIME.POLL)

        if i >= numberof then StopICE() end
        ReportMission()
        MissionPicked = false
    end
    UnSetAH()
end

-- =========================================================
-- Script Settings 
-- =========================================================
CharacterCondition = {
    normalConditions = 1,  -- moving or standing still
    mounted          = 4,  -- moving
    fishing          = 43,
}

missionA = {
    name     = "Cultivated Specimen Survey",
    position = Vector3(217.964, 133.719, -740.187),
    id       = 986,
    ahPreset = "AH4_H4sIAAAAAAAACu1XS2/bOBD+KwHPIqAH9fLNcZNsgDQJ6nR7CPYwEkc2EVl0KSpbb+D/vqAetuTYcRt40T3kJpEz33wz+jgcvZBxpeUESl1OshkZvZCLApIcx3lORlpVaBGzeSMK3G7ybuuak5EbxRa5V0IqoVdk5Fjkurz4keYVR75dNvbrBuuzlOncgNUPrnmqcYLIIlfLh7nCci5zTkaObQ+Q34auMeJw4GEfJTOZV4uOAXNsdoRC5yXzHFPdc3T6Zu7xsFJxAXkHEDhsAMBas0tRzi9WWPYC+TsMfX/AMOiKDE84nYtMn4OoeZqFsluYakifSjLy27IF0WvcPmrcot6DFlik2OMT7PoFw4q5nasS/+AEdPPpu6i73u5Ovb3W+2EOuYCn8hKepTIAg4UuHc8arn/BVD6jIiPHFGmfdoPIfPJewK5+52J2BYs60XExy1GVXRDzcTkZeaHNXrEfQEXrtUUufmgFg5O1IWA+xIOc/g3L60JXQgtZXIEouvJQxyI3lcLPWJYwQzIixCK3NSdyKwskLcJqiWRk6rQH70aW+t149wpL3M+QUHJgv4lY72/5TJeYagX5pFIKC32iLHdQT5brXravMt4bvba6lCpFbvDrIxIGsWe1IppquTRnWhSzqcZl3S23CbVCG6vT5NGHq4l9LcT3Cg0uSZPA87iTUi9xGGVxmNEoyQLqOX7iQeQwdJCsLXIjSn2XmRglGT2+1NFMAhuCcXyY4TjPzxrXXZq3Ui0g/0PKJwPUdZVvCPW7WS9Rb45LBnmJ3fltN02C3UFqlxp45oSmW3WYU61k0Tt9x91tr+d+gzMsOKjVCXjVwJ9kleS7mTYWbhBvDLa0D5rso9a3elBieShS6LvexuRQrIHRG9FaO6PtcaZRTaCazfWNWJiLx2k2dkVfzxSVam4289Br4Xv6tBf68eur+Y1b1swDXUvqZPYFv1dCIZ9q0JW5/MzA8Zu1d1fkq29zLMapFs94zbHQIjVzwS9K80ODv67BryVOqlLLRSOIRia9kfe/lWevGTse9yBwOUU3BMpsZtPIjSOKmRPZGUuAhxFZ/9V143Z+ftwsNA358YVczwqp8K7YSL8j2W/ZzNTqcNP+JOUC+dmfcgUzVIPO7bxV4Y12Te1MrMZgvJBV0TPbUz3mx7uDlDccaiMTuFIZpDjNjbbbTPzYPzI/+muL/G/+N7Y3/bvvd+NsViamqnVB+zd+e8+bx2Z5a7b3AGwlGIfgI0NO0c8SylzOaJImQG0XnQw8J0YbyNp6eaUkdjiBc6m1XNAcVsd11Olhv7zcn5bXh55+m55so4X+iBmlQcjSmEYQcMqQ2zQCyKjnQmrbvosZJLWkfrprvZHcVIM6myhItJnWT9203q2q/d3uQ2T3J2laqZMkCAGj4KYuZbYX0TjJXBpwHiaul7peAPW92eC2FCdVrsUzaORn5h9OLLA4m1bqGVfDXyQWRQkPApuCzSPKMh9oYkNKmZOAz2MfEuRk/S+bc5nAQBMAAA=="
}

missionB = {
    name     = "Elemental-esque Aquaculture Specimens",
    position = Vector3(381.041, 27.040, -76.952),
    id       = 988,
    ahPreset = "AH4_H4sIAAAAAAAACs1WTW/bOBD9KwHPUkHJFC3p5rpuNoCTDWoHeyj2QEkjmwgtOiTVbTbwf19QEmNbtlt1kXb3JpEzb958cl7QpDZyyrTR03KF0hc0q1gmYCIESo2qwUMfZGWmrMpB3EqZr1FaMqHBQ1ZpzivYKxVO5aZAaRgnl3XvFZeKm2eUBh660bOvuagLKPbHFmfX2ug0X1DzEdqvBp/GHrreLtcK9FqKAqUBxkfI34ZuMJLxII74uySn63pzIRAkwKTHNLJMB9h14FIIyI3znAQ4GKIefp+1VAVn4gLxAGMakEGmSAf4kev17Bn0AdWo73s0yHfqss8eYbHmpXnPeBMBe6DdwcKw/FGjNOrySeNTe0OsJZ21e2Y4VDkc8Kd9PDosd6GDVPxvmDLT1rBj2UcNB1bEqENdrpng7FF/ZF+kssBHBy4sI+/4/BPk8gsolAY2Ceealsa2WAcQcfl5z1fXbNMEbFKtBCjtjNvyK1A6GmNy4u0gE/Fu56HZV6NYN5psxpdy8Rfb3lSm5obL6prxysXVDzw0rxXcgtZsBShFyEN3DTl0JytAXovwvAWU2kCewZtLbf413r0CDecZIh9duG8tNvd7Post5EYxMa2Vgsq8kZc91Dfz9SzbE4/PWm+k2sJZGLm184NXq4WBbfM07Ll3xTVRb0P5EK7h8FDxpxosLiqKPAtDHPt0jMc+ScLIz4oSfJpkOCBACxYQtPPQnGvze2ltaJR+bsvTOvBKMEkuM5wIcdWq9mneSbVh4jcpHy2Qm0h/AGv+26a1txqM9cS1b3fU4pBgbEeaU14YJavVj6jj0YH6HFZQFUw9/zDCg4YPsu7k9wuFPXEO2Zsl34DqjaNbXr1e2WHwDnvIvrLnZO15Tx6/i3uUQmpD0hrfB+Q/MX8U0F/MYKn49jj6e4FxFI5eRY5jdEHoxJMTOdvWk9KAmrJ6tTZzvrHveBC1N8cNj0PS7ZW1apcI+3HwmrUPSpT0F6pvbmh22XPT1rXVJ3iquYJiYZip7QJht8l+rw1rqcGdc07wtBcG1Ouwmvp/5v1c2n9Ozh/2E50EUIaUMj/HNPFJGRM/znDox9G4CBjBJEso2v3pRnq3kXx+PWinuv1v35Buhs8EbKAyTPign2q4mjzVLK+FAXVlHzu+gcqO9wMiGGdJFuYjPx8z7JMyI35csMiPaZLQLMcjCiHa/QOhkWZllQ0AAA=="
}

PhaennaResearchNpc = {
    name     = GetENpcResidentName(1052629),
    position = Vector3(321.218, 53.193, -401.236)
}

-- =========================================================
-- Main Script 
-- =========================================================
while true do
    if not GetCharacterCondition(CharacterCondition.mounted) then
        Mount()
    end

    local missions = RetrieveRelicResearch()

    local missionAtotal = need(missions, 4) + need(missions, 41001) + need(missions, 41002)
    local missionBtotal = need(missions, 41003) + need(missions, 41004) + need(missions, 41002)

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
        sleep(TIME.POLL)

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

        repeat sleep(TIME.POLL) until AwaitAddonReady("SelectString")
        if IsAddonReady("SelectString") then
            SafeCallback("SelectString", 0)
        end

        repeat sleep(TIME.POLL) until AwaitAddonReady("SelectIconString")
        if IsAddonReady("SelectIconString") then
            StringId = Player.Job.Id - 8
            SafeCallback("SelectIconString", StringId)
        end

        repeat sleep(TIME.POLL) until AwaitAddonReady("SelectYesno")
        if IsAddonReady("SelectYesno") then
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
