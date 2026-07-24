--[=====[
[[SND Metadata]]
author: baanderson40
version: 0.1.0
description: Changes Cosmic Exploration territories, starts ICE during selected weather, and advances after five minutes of normal condition.
plugin_dependencies:
- vnavmesh
- ICE
configs:
  Weather Wait Minutes:
    description: How long to wait for selected weather after entering a territory.
    default: 2
    min: 1
    max: 10
  Normal Condition Minutes:
    description: How long condition 1 must remain true before stopping ICE.
    default: 5
    min: 1
    max: 30
  Enable Sinus Ardorum:
    description: Include Sinus Ardorum in the territory route.
    default: true
  Enable Phaenna:
    description: Include Phaenna in the territory route.
    default: true
  Enable Oizys:
    description: Include Oizys in the territory route.
    default: true
  Enable Auxesia:
    description: Include Auxesia in the territory route.
    default: true
[[End Metadata]]
--]=====]

import("System.Numerics")

local PREFIX = "[Cosmic Weather ICE]"
local POLL_SECONDS = 0.10
local ADDON_POLL_SECONDS = 0.25
local MAX_ATTEMPTS = 3
local NPC_INTERACT_ATTEMPTS = 3
local NPC_NAME = "Cruisingway"
local NPC_STOP_DISTANCE = 3.0

local CONDITION_NORMAL = 1

local SPECIAL_WEATHER_IDS = {
    [149] = true,
    [196] = true,
    [194] = true,
    [195] = true,
    [197] = true,
    [10]  = true,
    [201] = true,
    [202] = true,
    [205] = true,
    [206] = true,
    [6]   = true,
    [28]  = true,
    [119] = true,
    [207] = true,
    [208] = true,
}

local TERRITORIES = {
    {
        name = "Sinus Ardorum",
        territoryId = 1237,
        planetIndex = 0,
        configName = "Enable Sinus Ardorum",
        npcPosition = Vector3(-42.01, 11.87, -95.75),
    },
    {
        name = "Phaenna",
        territoryId = 1291,
        planetIndex = 1,
        configName = "Enable Phaenna",
        npcPosition = Vector3(277.33, 52.03, -377.46),
    },
    {
        name = "Oizys",
        territoryId = 1310,
        planetIndex = 2,
        configName = "Enable Oizys",
        npcPosition = Vector3(-204.43, 0.50, 66.48),
    },
    {
        name = "Auxesia",
        territoryId = 1319,
        planetIndex = 3,
        configName = "Enable Auxesia",
        npcPosition = Vector3(366.11, 204.14, 395.62),
    },
}

local stopped = false

local function echo(message)
    yield("/echo " .. PREFIX .. " " .. tostring(message))
end

local function log(message)
    Dalamud.Log(PREFIX .. " " .. tostring(message))
end

local function report(message)
    log(message)
    echo(message)
end

local function sleep(seconds)
    seconds = math.max(0, tonumber(seconds) or 0)
    yield("/wait " .. tostring(math.floor(seconds * 10 + 0.5) / 10))
end

local function getAddon(name)
    local ok, addon = pcall(Addons.GetAddon, name)
    if ok then return addon end
    return nil
end

local function isAddonReady(name)
    local addon = getAddon(name)
    return addon ~= nil and addon.Exists == true and addon.Ready == true
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
    local ok, territoryId = pcall(function()
        return Svc.ClientState.TerritoryType
    end)
    return ok and tonumber(territoryId) or nil
end

local function currentTerritoryIndex()
    local territoryId = currentTerritory()
    for index, territory in ipairs(TERRITORIES) do
        if territory.territoryId == territoryId then
            return index
        end
    end
    return nil
end

local function readWeatherId()
    local ok, weatherId = pcall(function()
        return tonumber(Instances.EnvManager.ActiveWeather)
    end)
    return ok and weatherId or nil
end

local function isSpecialWeather(weatherId)
    return weatherId ~= nil and SPECIAL_WEATHER_IDS[weatherId] == true
end

local function stopVnav()
    if not (IPC and IPC.vnavmesh) then return end
    pcall(function()
        if IPC.vnavmesh.IsRunning() or IPC.vnavmesh.PathfindInProgress() then
            IPC.vnavmesh.Stop()
        end
    end)
end

local function moveTo(position)
    if not (IPC and IPC.vnavmesh and IPC.vnavmesh.PathfindAndMoveTo) then
        log("vnavmesh is unavailable")
        return false
    end

    local ok, started = pcall(function()
        return IPC.vnavmesh.PathfindAndMoveTo(position, false)
    end)
    if not ok or started == false then
        log("vnavmesh could not start movement")
        return false
    end

    local arrived = waitUntil(function()
        local player = Entity and Entity.Player
        if not (player and player.Position) then return false end
        return Vector3.Distance(player.Position, position) <= NPC_STOP_DISTANCE
    end, 60)

    stopVnav()
    return arrived
end

local function targetAndInteract(territory)
    for attempt = 1, NPC_INTERACT_ATTEMPTS do
        yield('/target "' .. NPC_NAME .. '"')

        local targeted = waitUntil(function()
            local target = Entity and Entity.Target
            local player = Entity and Entity.Player
            if not (target and player and target.Name == NPC_NAME and target.Position and player.Position) then
                return false
            end
            return Vector3.Distance(player.Position, target.Position) <= 8.0
        end, 5, ADDON_POLL_SECONDS)

        if targeted then
            local target = Entity and Entity.Target
            local ok = pcall(function()
                target:Interact()
            end)

            if ok and waitUntil(function()
                local addon = getAddon("SelectString")
                return addon ~= nil and addon.Exists == true
            end, 5, ADDON_POLL_SECONDS) then
                return true
            end
        end

        if attempt < NPC_INTERACT_ATTEMPTS then
            log("NPC interaction did not open SelectString in " .. territory.name
                .. "; retrying (" .. tostring(attempt + 1) .. "/"
                .. tostring(NPC_INTERACT_ATTEMPTS) .. ")")
            sleep(0.5)
        end
    end

    log("NPC interaction did not open SelectString in " .. territory.name)
    return false
end

local function callbackWhenReady(addonName, callback)
    if not waitUntil(function()
        local addon = getAddon(addonName)
        return addon ~= nil and addon.Exists == true
    end, 15, ADDON_POLL_SECONDS) then
        log(addonName .. " did not appear")
        return false
    end

    local ok = pcall(callback)
    if not ok then
        log("callback failed for " .. addonName)
        return false
    end

    return true
end

local function waitAddonClosed(addonName)
    return waitUntil(function()
        local addon = getAddon(addonName)
        return addon == nil or addon.Exists ~= true
    end, 15, ADDON_POLL_SECONDS)
end

local function changeTerritory(fromTerritory, destination)
    report("Changing from " .. fromTerritory.name .. " to " .. destination.name)

    if not moveTo(fromTerritory.npcPosition) then
        log("could not reach NPC in " .. fromTerritory.name)
        return false
    end

    if not targetAndInteract(fromTerritory) then return false end

    if not callbackWhenReady("SelectString", function()
        yield("/callback SelectString true 0")
    end) then return false end
    if not waitAddonClosed("SelectString") then return false end

    if not callbackWhenReady("WKSPlanetSelect", function()
        yield("/callback WKSPlanetSelect true 11 " .. tostring(destination.planetIndex) .. " 1")
    end) then return false end

    if not callbackWhenReady("SelectYesno", function()
        log("Confirming selected Cosmic territory")
        yield("/callback SelectYesno true 0")
    end) then return false end
    if not waitAddonClosed("SelectYesno") then return false end

    local transitioned = waitUntil(function()
        return currentTerritory() == destination.territoryId
            and not (Svc.Condition and Svc.Condition[45] == true)
    end, 60)

    if not transitioned then
        log("territory transition timed out; current=" .. tostring(currentTerritory()))
        return false
    end

    report("Arrived in " .. destination.name)
    sleep(1)
    return true
end

local function stopIce()
    yield("/ice stop")
    sleep(1)
end

local function startIce()
    yield("/ice start")
    sleep(1)
end

local function weatherWait(territory)
    local waitSeconds = (tonumber(Config.Get("Weather Wait Minutes")) or 2) * 60
    local deadline = os.clock() + waitSeconds

    report("Waiting up to " .. tostring(waitSeconds / 60) .. " minutes for special weather in " .. territory.name)
    while not stopped and os.clock() < deadline do
        local weatherId = readWeatherId()
        if isSpecialWeather(weatherId) then
            report("Special weather " .. tostring(weatherId) .. " detected in " .. territory.name)
            return true
        end
        sleep(POLL_SECONDS)
    end

    report("No special weather in " .. territory.name)
    return false
end

local function monitorIce(territory)
    local normalSeconds = (tonumber(Config.Get("Normal Condition Minutes")) or 5) * 60
    local normalSince = nil

    report("ICE active in " .. territory.name .. "; waiting for " .. tostring(normalSeconds / 60) .. " minutes of normal condition")
    while not stopped do
        local isNormal = Svc and Svc.Condition and Svc.Condition[CONDITION_NORMAL] == true
        if isNormal then
            normalSince = normalSince or os.clock()
            if os.clock() - normalSince >= normalSeconds then
                report("Normal condition held for the full window in " .. territory.name)
                return true
            end
        else
            normalSince = nil
        end
        sleep(POLL_SECONDS)
    end
    return false
end

local function isTerritoryEnabled(territory)
    return Config.Get(territory.configName) ~= false
end

local function countEnabled()
    local count = 0
    for _, territory in ipairs(TERRITORIES) do
        if isTerritoryEnabled(territory) then count = count + 1 end
    end
    return count
end

local function nextEnabledIndex(currentIndex)
    for offset = 1, #TERRITORIES do
        local index = ((currentIndex + offset - 1) % #TERRITORIES) + 1
        if isTerritoryEnabled(TERRITORIES[index]) then
            return index
        end
    end
    return nil
end

local function retryChange(fromTerritory, destination)
    for attempt = 1, MAX_ATTEMPTS do
        if changeTerritory(fromTerritory, destination) then return true end
        if attempt < MAX_ATTEMPTS then
            report("Territory change failed; retrying (" .. tostring(attempt + 1) .. "/" .. tostring(MAX_ATTEMPTS) .. ")")
            sleep(2)
        end
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

    local currentIndex = currentTerritoryIndex()
    if not currentIndex then
        report("Current territory is not one of the four Cosmic territories")
        return
    end

    if countEnabled() == 0 then
        report("All territories are disabled; nothing to do")
        return
    end

    report("Starting in " .. TERRITORIES[currentIndex].name)

    while not stopped do
        local current = TERRITORIES[currentIndex]
        local weatherFound = false

        if not isTerritoryEnabled(current) then
            report(current.name .. " is disabled; advancing")
        else
            weatherFound = weatherWait(current)
        end

        if weatherFound then
            startIce()
            monitorIce(current)
            stopIce()
        end

        local nextIndex = nextEnabledIndex(currentIndex)
        if not nextIndex then
            report("No enabled territory remains; stopping")
            return
        end
        local nextTerritory = TERRITORIES[nextIndex]
        if not retryChange(current, nextTerritory) then
            report("Territory change failed after " .. tostring(MAX_ATTEMPTS) .. " attempts; stopping")
            return
        end
        currentIndex = nextIndex
    end
end

main()
