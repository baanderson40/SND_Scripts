--[=====[
[[SND Metadata]]
author: baanderson40
version: 0.1.0
description: Jumps between Cosmic Exploration territories for configured normal weather and runs ICE during each matching window.
plugin_dependencies:
- vnavmesh
- ICE
configs:
  Early Departure Minutes:
    description: Real-world minutes before a matching weather window to leave for its territory.
    default: 5
    min: 0
    max: 15
  Normal Condition Minutes:
    description: Continuous time with neither normal condition nor movement before moving to the next weather window.
    default: 1
    min: 1
    max: 10
  Sinus Ardorum - Moon Dust:
    description: Target Moon Dust in Sinus Ardorum.
    default: false
  Sinus Ardorum - Fair Skies:
    description: Target Fair Skies in Sinus Ardorum.
    default: false
  Sinus Ardorum - Umbral Wind:
    description: Target Umbral Wind in Sinus Ardorum.
    default: false
  Phaenna - Fair Skies:
    description: Target Fair Skies in Phaenna.
    default: false
  Phaenna - Clouds:
    description: Target Clouds in Phaenna.
    default: false
  Phaenna - Rain:
    description: Target Rain in Phaenna.
    default: false
  Oizys - Clouds:
    description: Target Clouds in Oizys.
    default: false
  Oizys - Fair Skies:
    description: Target Fair Skies in Oizys.
    default: false
  Oizys - Clear Skies:
    description: Target Clear Skies in Oizys.
    default: false
  Auxesia - Clouds:
    description: Target Clouds in Auxesia.
    default: false
  Auxesia - Fair Skies:
    description: Target Fair Skies in Auxesia.
    default: false
  Auxesia - Clear Skies:
    description: Target Clear Skies in Auxesia.
    default: false
[[End Metadata]]
--]=====]

import("System.Numerics")

local PREFIX = "[Cosmic Weather Jumper]"
local POLL_SECONDS = 0.10
local ADDON_POLL_SECONDS = 0.25
local MAX_ATTEMPTS = 3
local NPC_INTERACT_ATTEMPTS = 3
local NPC_NAME = "Cruisingway"
local NPC_STOP_DISTANCE = 3.0
local STELLAR_RETURN_DISTANCE = 100.0
local ZONE_TIMEOUT = 60
local STABLE_SECONDS = 1.0
local NORMAL_CONDITION = 1
local WEATHER_PERIOD_SECONDS = 1400
local WEATHER_DEPARTURE_SECONDS = 5 * 60
local UINT32 = 4294967296

local TERRITORIES = {
    {
        name = "Sinus Ardorum", territoryId = 1237, planetIndex = 0,
        npcPosition = Vector3(-42.01, 11.87, -95.75),
        weather = {
            ["Moon Dust"] = { 0, 15 },
            ["Fair Skies"] = { 15, 85 },
            ["Umbral Wind"] = { 85, 100 },
        },
    },
    {
        name = "Phaenna", territoryId = 1291, planetIndex = 1,
        npcPosition = Vector3(277.33, 52.03, -377.46),
        weather = {
            ["Fair Skies"] = { 0, 60 },
            ["Clouds"] = { 60, 80 },
            ["Rain"] = { 80, 100 },
        },
    },
    {
        name = "Oizys", territoryId = 1310, planetIndex = 2,
        npcPosition = Vector3(-204.43, 0.50, 66.48),
        weather = {
            ["Clouds"] = { 0, 20 },
            ["Fair Skies"] = { 20, 80 },
            ["Clear Skies"] = { 80, 100 },
        },
    },
    {
        name = "Auxesia", territoryId = 1319, planetIndex = 3,
        npcPosition = Vector3(366.11, 204.14, 395.62),
        weather = {
            ["Clouds"] = { 0, 20 },
            ["Fair Skies"] = { 20, 80 },
            ["Clear Skies"] = { 80, 100 },
        },
    },
}

local WEATHER_IDS = {
    ["Moon Dust"] = { 148 },
    ["Fair Skies"] = { 2, 30, 31, 32, 33, 34, 52, 63, 65, 90, 105, 106, 107, 108, 132 },
    ["Umbral Wind"] = { 49 },
    ["Clouds"] = { 3, 21, 139, 140 },
    ["Rain"] = { 7, 62, 64 },
    ["Clear Skies"] = { 1, 91, 209 },
}

-- Red Alert weather temporarily overrides the normal weather without changing
-- the underlying weather schedule used by the forecast calculation.
local SPECIAL_WEATHER_IDS = {
    [149] = true,
    [196] = true,
    [194] = true,
    [195] = true,
    [197] = true,
    [10] = true,
    [201] = true,
    [202] = true,
    [205] = true,
    [206] = true,
    [6] = true,
    [28] = true,
    [119] = true,
    [207] = true,
    [208] = true,
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

local function isAddonReady(name)
    local addon = getAddon(name)
    return addon ~= nil and addon.Ready == true
end

local function currentTerritory()
    local ok, value = pcall(function() return Svc.ClientState.TerritoryType end)
    return ok and tonumber(value) or nil
end

local function currentTerritoryById(territoryId)
    for _, territory in ipairs(TERRITORIES) do
        if territory.territoryId == territoryId then return territory end
    end
    return nil
end

local function readActiveWeatherId()
    local ok, value = pcall(function()
        return tonumber(Instances.EnvManager.ActiveWeather)
    end)
    return ok and value or nil
end

local function readClockSeconds()
    return os.time()
end

-- Lua does not need native bitwise operators for this small 32-bit hash.
local function xor32(a, b)
    local result = 0
    local bit = 1
    a = math.floor(a) % UINT32
    b = math.floor(b) % UINT32
    for _ = 1, 32 do
        local abit = a % 2
        local bbit = b % 2
        if abit ~= bbit then result = result + bit end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bit = bit * 2
    end
    return result % UINT32
end

local function forecastTarget(timestamp)
    local unix = math.floor(timestamp)
    local bell = math.floor(unix / 175)
    local increment = (bell + 8 - (bell % 8)) % 24
    local totalDays = math.floor(unix / 4200) % UINT32
    local calcBase = (totalDays * 100 + increment) % UINT32
    local step1 = xor32((calcBase * 2048) % UINT32, calcBase)
    local step2 = xor32(math.floor(step1 / 256), step1)
    return step2 % 100
end

local function weatherAt(territory, timestamp)
    local target = forecastTarget(timestamp)
    for weatherName, range in pairs(territory.weather) do
        if target >= range[1] and target < range[2] then return weatherName end
    end
    return nil
end

local function weatherIdMatches(weatherName, weatherId)
    if weatherId == nil then return false end
    for _, candidate in ipairs(WEATHER_IDS[weatherName] or {}) do
        if candidate == weatherId then return true end
    end
    return false
end

local function weatherNameFromId(weatherId)
    for weatherName, ids in pairs(WEATHER_IDS) do
        for _, candidate in ipairs(ids) do
            if candidate == weatherId then return weatherName end
        end
    end
    return nil
end

local function isSpecialWeather(weatherId)
    return weatherId ~= nil and SPECIAL_WEATHER_IDS[weatherId] == true
end

local function configKey(territory, weatherName)
    return territory.name .. " - " .. weatherName
end

local function isWeatherEnabled(territory, weatherName)
    return Config.Get(configKey(territory, weatherName)) == true
end

local function hasEnabledWeather(territory)
    for weatherName in pairs(territory.weather) do
        if isWeatherEnabled(territory, weatherName) then return true end
    end
    return false
end

local function countEnabledWeather()
    local count = 0
    for _, territory in ipairs(TERRITORIES) do
        for weatherName in pairs(territory.weather) do
            if isWeatherEnabled(territory, weatherName) then count = count + 1 end
        end
    end
    return count
end

local function currentWeatherWindow(now)
    return math.floor(now / WEATHER_PERIOD_SECONDS) * WEATHER_PERIOD_SECONDS
end

local function findNextWindow(now, currentTerritoryId)
    local currentWindow = currentWeatherWindow(now)
    local currentMatches = {}

    for _, territory in ipairs(TERRITORIES) do
        local weatherName = weatherAt(territory, currentWindow)
        if weatherName and isWeatherEnabled(territory, weatherName) then
            table.insert(currentMatches, { territory = territory, weather = weatherName, start = currentWindow })
        end
    end

    if #currentMatches > 0 then
        for _, match in ipairs(currentMatches) do
            if match.territory.territoryId == currentTerritoryId then return match end
        end
        return currentMatches[1]
    end

    for offset = 1, 144 do
        local windowStart = currentWindow + (offset * WEATHER_PERIOD_SECONDS)
        for _, territory in ipairs(TERRITORIES) do
            local weatherName = weatherAt(territory, windowStart)
            if weatherName and isWeatherEnabled(territory, weatherName) then
                return { territory = territory, weather = weatherName, start = windowStart }
            end
        end
    end

    return nil
end

local function describeWeather(weatherId)
    return weatherNameFromId(weatherId) or ("ID " .. tostring(weatherId or "unknown"))
end

local function isPlayerAvailable()
    return Player ~= nil and Player.Available == true
end

local function isLifestreamBusy()
    if IPC and IPC.Lifestream and IPC.Lifestream.IsBusy then
        local ok, busy = pcall(IPC.Lifestream.IsBusy)
        return ok and busy == true
    end
    return false
end

local function describeTransitionState()
    local states = {}
    if Svc and Svc.Condition then
        if Svc.Condition[27] then table.insert(states, "casting") end
        if Svc.Condition[45] then table.insert(states, "betweenAreas") end
        if Svc.Condition[51] then table.insert(states, "betweenAreasForDuty") end
    end
    if isLifestreamBusy() then table.insert(states, "lifestreamBusy") end
    return #states > 0 and table.concat(states, ",") or "idle"
end

local function isTransitionActive()
    return Svc and Svc.Condition and (
        Svc.Condition[27] == true
        or Svc.Condition[45] == true
        or Svc.Condition[51] == true
        or isLifestreamBusy()
    ) or false
end

local function isTransitionComplete()
    return not isAddonReady("FadeMiddle")
        and not isLifestreamBusy()
        and not (Svc and Svc.Condition and Svc.Condition[27] == true)
        and not (Svc and Svc.Condition and Svc.Condition[45] == true)
        and not (Svc and Svc.Condition and Svc.Condition[51] == true)
        and isPlayerAvailable()
end

local function waitForZoneCompletion(targetTerritoryId, timeoutSeconds, sourceLabel)
    local deadline = os.clock() + (tonumber(timeoutSeconds) or ZONE_TIMEOUT)
    local stableStart = nil
    local sawActivity = false
    sourceLabel = tostring(sourceLabel or "zone transition")

    while not stopped and os.clock() < deadline do
        local current = currentTerritory()
        if isTransitionActive() then
            sawActivity = true
            stableStart = nil
        end

        local territoryReady = targetTerritoryId == nil or current == targetTerritoryId
        if territoryReady and isTransitionComplete() then
            stableStart = stableStart or os.clock()
            if os.clock() - stableStart >= STABLE_SECONDS then
                log(sourceLabel .. " completion confirmed; state=" .. describeTransitionState())
                return true
            end
        else
            stableStart = nil
        end
        sleep(POLL_SECONDS)
    end

    local fadeMiddle = getAddon("FadeMiddle")
    log(sourceLabel .. " timed out; activity=" .. tostring(sawActivity)
        .. " state=" .. describeTransitionState()
        .. " territory=" .. tostring(currentTerritory())
        .. " playerAvailable=" .. tostring(isPlayerAvailable())
        .. " fadeReady=" .. tostring(fadeMiddle and fadeMiddle.Ready == true)
        .. " fadeExists=" .. tostring(fadeMiddle and fadeMiddle.Exists == true))
    return false
end

local function flatDistance(positionA, positionB)
    if not (positionA and positionB) then return math.huge end
    local dx = positionA.X - positionB.X
    local dz = positionA.Z - positionB.Z
    return math.sqrt((dx * dx) + (dz * dz))
end

local function stopVnav()
    if not (IPC and IPC.vnavmesh) then return end
    pcall(function()
        if IPC.vnavmesh.IsRunning() or IPC.vnavmesh.PathfindInProgress() then
            IPC.vnavmesh.Stop()
        end
    end)
end

local function stellarReturnIfFar(territory)
    local player = Entity and Entity.Player
    if not (player and player.Position) then
        log("Player position unavailable before Stellar Return check")
        return false
    end

    local distance = flatDistance(player.Position, territory.npcPosition)
    if distance <= STELLAR_RETURN_DISTANCE then return true end

    report(string.format("%.1f yalms from %s NPC; using Stellar Return", distance, territory.name))
    stopVnav()

    local ok = pcall(function() Actions.ExecuteAction(42149) end)
    if not ok then
        log("Stellar Return action failed")
        return false
    end

    sleep(4)
    if not waitForZoneCompletion(currentTerritory(), ZONE_TIMEOUT, "Stellar Return") then return false end

    local nearNpc = waitUntil(function()
        local currentPlayer = Entity and Entity.Player
        return currentPlayer and currentPlayer.Position
            and flatDistance(currentPlayer.Position, territory.npcPosition) <= STELLAR_RETURN_DISTANCE
    end, 30)
    if not nearNpc then
        log("Stellar Return completed but player is still outside the NPC radius")
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

    if not waitForZoneCompletion(destination.territoryId, ZONE_TIMEOUT, "Cosmic territory change") then
        return false
    end

    report("Arrived in " .. destination.name)
    sleep(1)
    return true
end

local function changeTerritoryWithRetries(destination)
    for attempt = 1, MAX_ATTEMPTS do
        local current = currentTerritoryById(currentTerritory())
        if not current then
            report("Current territory is not a known Cosmic territory; cannot change to " .. destination.name)
            return false
        end
        if current.territoryId == destination.territoryId then
            return true
        end

        report("Territory change attempt " .. tostring(attempt) .. "/" .. tostring(MAX_ATTEMPTS)
            .. ": " .. current.name .. " -> " .. destination.name)
        if changeTerritory(current, destination) then return true end
        if attempt < MAX_ATTEMPTS then sleep(2) end
    end

    report("Territory change failed after " .. tostring(MAX_ATTEMPTS) .. " attempts")
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

local function currentWeatherMatches(weatherName)
    return weatherIdMatches(weatherName, readActiveWeatherId())
end

local function waitForTargetWeather(target, windowStart)
    local lastReport = 0

    while not stopped do
        local now = readClockSeconds()
        if now >= windowStart + WEATHER_PERIOD_SECONDS then return false end

        local weatherId = readActiveWeatherId()
        if currentWeatherMatches(target.weather) then return true end

        if isSpecialWeather(weatherId) then
            if os.clock() - lastReport >= 30 then
                report("Red Alert weather is active in " .. target.territory.name
                    .. "; waiting for " .. target.weather)
                lastReport = os.clock()
            end
            sleep(1)
        else
            report("Expected " .. target.weather .. " in " .. target.territory.name
                .. ", got " .. describeWeather(weatherId) .. "; resynchronizing")
            return false
        end
    end

    return false
end

local function waitForDeparture(windowStart, target)
    local departureAt = windowStart - WEATHER_DEPARTURE_SECONDS
    while not stopped do
        local now = readClockSeconds()
        local liveWindow = currentWeatherWindow(now)
        if liveWindow > windowStart then return false end
        if now >= departureAt then return true end

        local remaining = departureAt - now
        log(string.format("Waiting for %s in %s; departure in %.0fs", target.weather, target.territory.name, remaining))
        sleep(math.min(10, math.max(0.25, remaining / 2)))
    end
    return false
end

local function waitForWindowStart(windowStart)
    while not stopped do
        local now = readClockSeconds()
        if currentWeatherWindow(now) > windowStart then return false end
        if now >= windowStart then return true end
        sleep(math.min(5, math.max(0.25, (windowStart - now) / 2)))
    end
    return false
end

local function waitForIceToStop()
    local required = (tonumber(Config.Get("Normal Condition Minutes")) or 1) * 60
    local inactiveSince = nil

    report("ICE monitor started; waiting for inactive state")
    while not stopped do
        local normal = Svc and Svc.Condition and Svc.Condition[NORMAL_CONDITION] == true
        local moving = Player and Player.IsMoving == true
        local active = normal or moving

        if active then
            inactiveSince = nil
        else
            inactiveSince = inactiveSince or os.clock()
            if os.clock() - inactiveSince >= required then return true end
        end

        sleep(POLL_SECONDS)
    end
    return false
end

local function targetIsStillValid(target, windowStart)
    local now = readClockSeconds()
    return now < (windowStart + WEATHER_PERIOD_SECONDS)
        and weatherAt(target.territory, windowStart) == target.weather
end

local function currentWeatherIsSynchronized(territory, now)
    local actualWeatherId = readActiveWeatherId()
    if isSpecialWeather(actualWeatherId) then return true end

    local actualName = weatherNameFromId(actualWeatherId)
    if actualName == nil then return true end

    local predictedName = weatherAt(territory, currentWeatherWindow(now))
    if actualName == predictedName then return true end

    log("Live weather/time mismatch; live=" .. actualName
        .. " predicted=" .. tostring(predictedName))
    return false
end

function OnStop()
    stopped = true
    stopVnav()
    stopIce()
end

local function main()
    stopIce()

    local initialTerritory = currentTerritoryById(currentTerritory())
    if not initialTerritory then
        report("Current territory is not one of the four Cosmic territories")
        return
    end

    if countEnabledWeather() == 0 then
        report("All weather targets are disabled; stopping")
        return
    end

    report("Starting in " .. initialTerritory.name)

    while not stopped do
        ::continue_loop::
        if countEnabledWeather() == 0 then
            report("All weather targets are disabled; stopping")
            return
        end

        local now = readClockSeconds()
        local currentId = currentTerritory()
        local current = currentTerritoryById(currentId)
        if not current then
            report("Current territory is no longer a known Cosmic territory; stopping")
            return
        end
        if not currentWeatherIsSynchronized(current, now) then
            sleep(2)
            goto continue_loop
        end

        local target = findNextWindow(now, currentId)
        if not target then
            report("No matching weather window found; stopping")
            return
        end

        local liveWeatherId = readActiveWeatherId()
        local liveWeather = describeWeather(liveWeatherId)
        report(string.format("Next target: %s in %s; current weather=%s", target.weather, target.territory.name, liveWeather))

        if target.start > now then
            if not waitForDeparture(target.start, target) then goto continue_loop end
        end

        current = currentTerritoryById(currentTerritory())
        if not current then
            report("Current territory is no longer a known Cosmic territory; stopping")
            return
        end

        if current.territoryId ~= target.territory.territoryId then
            if not changeTerritoryWithRetries(target.territory) then
                sleep(5)
                goto continue_loop
            end
        end

        if not targetIsStillValid(target, target.start) then
            report("Weather target became stale during travel; resynchronizing")
            goto continue_loop
        end

        if target.start > readClockSeconds() and not waitForWindowStart(target.start) then
            goto continue_loop
        end

        if not waitForTargetWeather(target, target.start) then
            goto continue_loop
        end

        startIce()
        waitForIceToStop()
        stopIce()
        sleep(1)
    end
end

main()
