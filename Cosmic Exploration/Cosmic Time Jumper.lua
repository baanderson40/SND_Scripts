--[=====[
[[SND Metadata]]
author: baanderson40
version: 0.1.0
description: Visits configured Cosmic Exploration planets by Eorzea Time and runs ICE during each time slot.
plugin_dependencies:
- vnavmesh
- ICE
configs:
  Early Departure Minutes:
    description: Real-world minutes before the next Eorzea time slot to depart.
    default: 5
    min: 0
    max: 30
  Normal Condition Minutes:
    description: Continuous normal-condition time before stopping ICE.
    default: 1
    min: 1
    max: 10
  00:00-02:00 Planet:
    description: Planet for the 00:00-02:00 Eorzea Time slot.
    default: "None"
    is_choice: true
    choices: ["None", "Sinus Ardorum", "Phaenna", "Oizys", "Auxesia"]
  02:00-04:00 Planet:
    description: Planet for the 02:00-04:00 Eorzea Time slot.
    default: "None"
    is_choice: true
    choices: ["None", "Sinus Ardorum", "Phaenna", "Oizys", "Auxesia"]
  04:00-06:00 Planet:
    description: Planet for the 04:00-06:00 Eorzea Time slot.
    default: "None"
    is_choice: true
    choices: ["None", "Sinus Ardorum", "Phaenna", "Oizys", "Auxesia"]
  06:00-08:00 Planet:
    description: Planet for the 06:00-08:00 Eorzea Time slot.
    default: "None"
    is_choice: true
    choices: ["None", "Sinus Ardorum", "Phaenna", "Oizys", "Auxesia"]
  08:00-10:00 Planet:
    description: Planet for the 08:00-10:00 Eorzea Time slot.
    default: "None"
    is_choice: true
    choices: ["None", "Sinus Ardorum", "Phaenna", "Oizys", "Auxesia"]
  10:00-12:00 Planet:
    description: Planet for the 10:00-12:00 Eorzea Time slot.
    default: "None"
    is_choice: true
    choices: ["None", "Sinus Ardorum", "Phaenna", "Oizys", "Auxesia"]
  12:00-14:00 Planet:
    description: Planet for the 12:00-14:00 Eorzea Time slot.
    default: "None"
    is_choice: true
    choices: ["None", "Sinus Ardorum", "Phaenna", "Oizys", "Auxesia"]
  14:00-16:00 Planet:
    description: Planet for the 14:00-16:00 Eorzea Time slot.
    default: "None"
    is_choice: true
    choices: ["None", "Sinus Ardorum", "Phaenna", "Oizys", "Auxesia"]
  16:00-18:00 Planet:
    description: Planet for the 16:00-18:00 Eorzea Time slot.
    default: "None"
    is_choice: true
    choices: ["None", "Sinus Ardorum", "Phaenna", "Oizys", "Auxesia"]
  18:00-20:00 Planet:
    description: Planet for the 18:00-20:00 Eorzea Time slot.
    default: "None"
    is_choice: true
    choices: ["None", "Sinus Ardorum", "Phaenna", "Oizys", "Auxesia"]
  20:00-22:00 Planet:
    description: Planet for the 20:00-22:00 Eorzea Time slot.
    default: "None"
    is_choice: true
    choices: ["None", "Sinus Ardorum", "Phaenna", "Oizys", "Auxesia"]
  22:00-24:00 Planet:
    description: Planet for the 22:00-24:00 Eorzea Time slot.
    default: "None"
    is_choice: true
    choices: ["None", "Sinus Ardorum", "Phaenna", "Oizys", "Auxesia"]
[[End Metadata]]
--]=====]

import("System.Numerics")

local PREFIX = "[Cosmic Time Jumper]"
local POLL_SECONDS = 0.10
local ADDON_POLL_SECONDS = 0.25
local MAX_ATTEMPTS = 3
local NPC_INTERACT_ATTEMPTS = 3
local NPC_NAME = "Cruisingway"
local NPC_STOP_DISTANCE = 3.0
local NORMAL_CONDITION = 1
local ET_DAY_SECONDS = 86400
local REAL_SECONDS_PER_ET_SECOND = 70 / ET_DAY_SECONDS

local TERRITORIES = {
    ["Sinus Ardorum"] = {
        name = "Sinus Ardorum", territoryId = 1237, planetIndex = 0,
        npcPosition = Vector3(-42.01, 11.87, -95.75),
    },
    ["Phaenna"] = {
        name = "Phaenna", territoryId = 1291, planetIndex = 1,
        npcPosition = Vector3(277.33, 52.03, -377.46),
    },
    ["Oizys"] = {
        name = "Oizys", territoryId = 1310, planetIndex = 2,
        npcPosition = Vector3(-204.43, 0.50, 66.48),
    },
    ["Auxesia"] = {
        name = "Auxesia", territoryId = 1319, planetIndex = 3,
        npcPosition = Vector3(366.11, 204.14, 395.62),
    },
}

local SLOT_CONFIGS = {
    "00:00-02:00 Planet", "02:00-04:00 Planet", "04:00-06:00 Planet",
    "06:00-08:00 Planet", "08:00-10:00 Planet", "10:00-12:00 Planet",
    "12:00-14:00 Planet", "14:00-16:00 Planet", "16:00-18:00 Planet",
    "18:00-20:00 Planet", "20:00-22:00 Planet", "22:00-24:00 Planet",
}

local SLOT_LABELS = {
    "00:00-02:00", "02:00-04:00", "04:00-06:00", "06:00-08:00",
    "08:00-10:00", "10:00-12:00", "12:00-14:00", "14:00-16:00",
    "16:00-18:00", "18:00-20:00", "20:00-22:00", "22:00-24:00",
}

local stopped = false

local function log(message)
    Dalamud.Log(PREFIX .. " " .. tostring(message))
end

local function report(message)
    log(message)
    yield("/echo " .. PREFIX .. " " .. tostring(message))
end

local function sleep(seconds)
    seconds = math.max(0, tonumber(seconds) or 0)
    yield("/wait " .. tostring(math.floor(seconds * 10 + 0.5) / 10))
end

local function getAddon(name)
    local ok, addon = pcall(Addons.GetAddon, name)
    return ok and addon or nil
end

local function waitUntil(predicate, timeoutSeconds, pollSeconds)
    local deadline = os.clock() + (tonumber(timeoutSeconds) or 10)
    pollSeconds = tonumber(pollSeconds) or POLL_SECONDS
    while not stopped and os.clock() < deadline do
        local ok, result = pcall(predicate)
        if ok and result then return true end
        sleep(pollSeconds)
    end
    return false
end

local function currentTerritory()
    local ok, value = pcall(function() return Svc.ClientState.TerritoryType end)
    return ok and tonumber(value) or nil
end

local function readEorzeaSeconds()
    local ok, value = pcall(function() return tonumber(Instances.Framework.EorzeaTime) end)
    if not ok or not value then return nil end
    return value % ET_DAY_SECONDS
end

local function formatEorzeaTime(seconds)
    seconds = tonumber(seconds) or 0
    local hour = math.floor(seconds / 3600) % 24
    local minute = math.floor((seconds % 3600) / 60)
    local second = math.floor(seconds % 60)
    return string.format("%02d:%02d:%02d", hour, minute, second)
end

local function territoryName(territoryId)
    for _, territory in pairs(TERRITORIES) do
        if territory.territoryId == territoryId then return territory.name end
    end
    return "unknown"
end

local function currentSlot(seconds)
    return math.floor(seconds / 7200) + 1
end

local function slotStart(slot)
    return (slot - 1) * 7200
end

local function slotTarget(slot)
    local value = Config.Get(SLOT_CONFIGS[slot])
    return value and tostring(value) or "None"
end

local function secondsUntilEt(targetSeconds, nowSeconds)
    local delta = (targetSeconds - nowSeconds) % ET_DAY_SECONDS
    return delta * REAL_SECONDS_PER_ET_SECOND
end

local function waitForEt(targetSeconds, reason)
    local lastHeartbeat = os.clock()
    local nowAtStart = readEorzeaSeconds()
    log(string.format("Waiting for %s at ET %s; current ET=%s; real wait=%.1fs",
        tostring(reason or "target time"),
        formatEorzeaTime(targetSeconds),
        formatEorzeaTime(nowAtStart),
        nowAtStart and secondsUntilEt(targetSeconds, nowAtStart) or -1))

    while not stopped do
        local now = readEorzeaSeconds()
        if not now then
            sleep(1)
        else
            local remaining = secondsUntilEt(targetSeconds, now)
            if remaining < 0.2 or remaining > (ET_DAY_SECONDS * REAL_SECONDS_PER_ET_SECOND / 2) then
                log(string.format("Reached %s at ET %s", tostring(reason or "target time"), formatEorzeaTime(now)))
                return true
            end
            if os.clock() - lastHeartbeat >= 30 then
                log(string.format("Still waiting for %s; ET=%s; %.1fs real remaining",
                    tostring(reason or "target time"), formatEorzeaTime(now), remaining))
                lastHeartbeat = os.clock()
            end
            sleep(math.min(5, math.max(0.25, remaining / 2)))
        end
    end
    return false
end

local function waitForSlotStart(slot)
    local now = readEorzeaSeconds()
    if not now then return false end
    local start = slotStart(slot)
    if math.abs(now - start) < 1 or (now >= start and now < start + 7200) then
        return true
    end
    return waitForEt(start, "slot " .. tostring(slot) .. " (" .. SLOT_LABELS[slot] .. ") start")
end

local function stopVnav()
    if not (IPC and IPC.vnavmesh) then return end
    pcall(function()
        if IPC.vnavmesh.IsRunning() or IPC.vnavmesh.PathfindInProgress() then
            IPC.vnavmesh.Stop()
        end
    end)
end

local function flatDistance(positionA, positionB)
    if not (positionA and positionB) then return math.huge end
    local dx = positionA.X - positionB.X
    local dz = positionA.Z - positionB.Z
    return math.sqrt((dx * dx) + (dz * dz))
end

local function stellarReturnIfFar(territory)
    local player = Entity and Entity.Player
    if not (player and player.Position) then
        log("Player position unavailable before Stellar Return check")
        return false
    end

    local distance = flatDistance(player.Position, territory.npcPosition)
    if distance <= 75 then return true end

    report(string.format("%.1f yalms from %s NPC; using Stellar Return", distance, territory.name))
    stopVnav()

    local ok = pcall(function()
        Actions.ExecuteAction(42149)
    end)
    if not ok then
        log("Stellar Return action failed")
        return false
    end

    local sawTransition = waitUntil(function()
        return Svc and Svc.Condition
            and (Svc.Condition[45] == true or Svc.Condition[27] == true)
    end, 10)
    if not sawTransition then
        log("Stellar Return transition did not begin")
        return false
    end

    local settled = waitUntil(function()
        return Svc and Svc.Condition
            and Svc.Condition[45] ~= true
            and Svc.Condition[27] ~= true
    end, 60)
    if not settled then
        log("Stellar Return transition did not settle")
        return false
    end

    sleep(1)
    return true
end

local function moveTo(position)
    if not (IPC and IPC.vnavmesh and IPC.vnavmesh.PathfindAndMoveTo) then
        log("vnavmesh is unavailable")
        return false
    end
    local ok, started = pcall(function()
        return IPC.vnavmesh.PathfindAndMoveTo(position, false)
    end)
    if not ok or started == false then return false end

    local arrived = waitUntil(function()
        local player = Entity and Entity.Player
        return player and player.Position
            and Vector3.Distance(player.Position, position) <= NPC_STOP_DISTANCE
    end, 90)
    stopVnav()
    return arrived
end

local function targetAndInteract(territory)
    for attempt = 1, NPC_INTERACT_ATTEMPTS do
        yield('/target "' .. NPC_NAME .. '"')
        local targeted = waitUntil(function()
            local target = Entity and Entity.Target
            local player = Entity and Entity.Player
            return target and player and target.Name == NPC_NAME
                and target.Position and player.Position
                and Vector3.Distance(player.Position, target.Position) <= 8
        end, 5, ADDON_POLL_SECONDS)

        if targeted then
            local target = Entity and Entity.Target
            local ok = pcall(function() target:Interact() end)
            if ok and waitUntil(function()
                local addon = getAddon("SelectString")
                return addon and addon.Exists == true
            end, 5, ADDON_POLL_SECONDS) then
                return true
            end
        end

        if attempt < NPC_INTERACT_ATTEMPTS then sleep(0.5) end
    end
    log("NPC interaction did not open SelectString in " .. territory.name)
    return false
end

local function callbackWhenVisible(addonName, callback)
    if not waitUntil(function()
        local addon = getAddon(addonName)
        return addon and addon.Exists == true
    end, 15, ADDON_POLL_SECONDS) then
        log(addonName .. " did not appear")
        return false
    end
    local ok = pcall(callback)
    return ok
end

local function waitAddonClosed(addonName)
    return waitUntil(function()
        local addon = getAddon(addonName)
        return not addon or addon.Exists ~= true
    end, 15, ADDON_POLL_SECONDS)
end

local function changeTerritory(fromTerritory, destination)
    report("Changing from " .. fromTerritory.name .. " to " .. destination.name)
    if not stellarReturnIfFar(fromTerritory) then return false end
    if not moveTo(fromTerritory.npcPosition) then return false end
    if not targetAndInteract(fromTerritory) then return false end

    if not callbackWhenVisible("SelectString", function()
        yield("/callback SelectString true 0")
    end) then return false end
    if not waitAddonClosed("SelectString") then return false end

    if not callbackWhenVisible("WKSPlanetSelect", function()
        yield("/callback WKSPlanetSelect true 11 " .. tostring(destination.planetIndex) .. " 1")
    end) then return false end

    if not callbackWhenVisible("SelectYesno", function()
        yield("/callback SelectYesno true 0")
    end) then return false end
    if not waitAddonClosed("SelectYesno") then return false end

    local arrived = waitUntil(function()
        return currentTerritory() == destination.territoryId
            and not (Svc.Condition and Svc.Condition[45] == true)
    end, 60)
    if arrived then report("Arrived in " .. destination.name) end
    return arrived
end

local function changeTerritoryWithRetries(fromTerritory, destination)
    for attempt = 1, MAX_ATTEMPTS do
        report("Territory change attempt " .. tostring(attempt) .. "/" .. tostring(MAX_ATTEMPTS)
            .. ": " .. fromTerritory.name .. " -> " .. destination.name)
        if changeTerritory(fromTerritory, destination) then return true end
        if attempt < MAX_ATTEMPTS then sleep(2) end
    end
    report("Territory change failed after " .. tostring(MAX_ATTEMPTS) .. " attempts; stopping this cycle")
    return false
end

local function stopIce()
    yield("/ice stop")
    sleep(1)
end

local function startIce()
    yield("/ice start")
    sleep(1)
end

local function monitorNormalCondition()
    local required = (tonumber(Config.Get("Normal Condition Minutes")) or 1) * 60
    local normalSince = nil
    local lastHeartbeat = os.clock()
    report("ICE normal-condition monitor started; required=" .. tostring(required) .. "s")
    while not stopped do
        local normal = Svc and Svc.Condition and Svc.Condition[NORMAL_CONDITION] == true
        local moving = Player and Player.IsMoving == true
        if normal and not moving then
            normalSince = normalSince or os.clock()
            if os.clock() - normalSince >= required then return true end
        else
            if normalSince ~= nil then
                log("Normal-condition timer reset: normal=" .. tostring(normal) .. " moving=" .. tostring(moving))
            end
            normalSince = nil
        end
        if os.clock() - lastHeartbeat >= 30 then
            local elapsed = normalSince and (os.clock() - normalSince) or 0
            log(string.format("ICE monitor heartbeat: normal=%s moving=%s timer=%.1fs/%.1fs",
                tostring(normal), tostring(moving), elapsed, required))
            lastHeartbeat = os.clock()
        end
        sleep(POLL_SECONDS)
    end
    return false
end

function OnStop()
    stopped = true
    stopVnav()
    stopIce()
end

local function main()
    stopIce()
    local now = readEorzeaSeconds()
    if not now then
        report("Unable to read Eorzea time; stopping")
        return
    end

    local slot = currentSlot(now)
    local firstCycle = true
    report(string.format("Starting: ET=%s slot %d (%s) target=%s current=%s (%s)",
        formatEorzeaTime(now), slot, SLOT_LABELS[slot], slotTarget(slot),
        tostring(currentTerritory()), territoryName(currentTerritory())))

    while not stopped do
        local loopNow = readEorzeaSeconds()
        local targetName = slotTarget(slot)
        local target = TERRITORIES[targetName]
        report(string.format("Slot %d (%s): ET=%s target=%s current=%s (%s)",
            slot, SLOT_LABELS[slot], formatEorzeaTime(loopNow), targetName,
            tostring(currentTerritory()), territoryName(currentTerritory())))

        if target then
            if currentTerritory() ~= target.territoryId then
                local current = nil
                for _, territory in pairs(TERRITORIES) do
                    if territory.territoryId == currentTerritory() then current = territory break end
                end
                if not current then
                    report("Current territory is not a known Cosmic territory; stopping")
                    return
                end
                if not changeTerritoryWithRetries(current, target) then
                    sleep(5)
                end
            end

            if currentTerritory() == target.territoryId then
                if firstCycle then
                    startIce()
                else
                    waitForSlotStart(slot)
                    startIce()
                end
                monitorNormalCondition()
                stopIce()
            end
        else
            stopIce()
            report("Slot " .. tostring(slot) .. " is None; staying in place")
        end

        firstCycle = false
        local nextSlot = (slot % 12) + 1
        local earlyMinutes = tonumber(Config.Get("Early Departure Minutes")) or 5
        local departure = slotStart(nextSlot) - (earlyMinutes * 60 / REAL_SECONDS_PER_ET_SECOND)
        local currentSeconds = readEorzeaSeconds()
        local nextStart = slotStart(nextSlot)
        local departureReached = false
        if currentSeconds then
            local untilDeparture = secondsUntilEt(departure % ET_DAY_SECONDS, currentSeconds)
            local untilNextStart = secondsUntilEt(nextStart, currentSeconds)
            departureReached = untilDeparture > untilNextStart
            log(string.format("Next slot %d (%s): target=%s; departure ET=%s; next start ET=%s; departureReached=%s",
                nextSlot, SLOT_LABELS[nextSlot], slotTarget(nextSlot),
                formatEorzeaTime(departure % ET_DAY_SECONDS), formatEorzeaTime(nextStart),
                tostring(departureReached)))
        end
        if not departureReached and not waitForEt(departure % ET_DAY_SECONDS,
            "early departure for slot " .. tostring(nextSlot) .. " (" .. SLOT_LABELS[nextSlot] .. ")") then
            return
        end
        slot = nextSlot
    end
end

main()
