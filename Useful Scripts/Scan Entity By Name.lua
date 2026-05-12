--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.0.0
description: Continuously scans for a configured entity by name and echoes when it returns.
configs:
  Entity Name:
    description: Name of the entity to scan for
    default: Example NPC
  Poll Interval:
    description: Seconds between scan attempts
    default: 1
    min: 0.1
    max: 10
[[End Metadata]]
--]=====]

local PREFIX = "[Entity Scanner]"

local function sleep(seconds)
    yield(string.format("/wait %.1f", tonumber(seconds) or 0))
end

local function log(message)
    local text = string.format("%s %s", PREFIX, tostring(message))
    pcall(function()
        Dalamud.Log(text)
    end)
    yield(string.format("/echo %s", text))
end

local function getConfigValue(name, fallback)
    local ok, value = pcall(function()
        return Config and Config.Get and Config.Get(name)
    end)

    if ok and value ~= nil then
        return value
    end

    return fallback
end

local function safeGetEntityByName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    if not (Entity and Entity.GetEntityByName) then
        return nil
    end

    local ok, entity = pcall(function()
        return Entity.GetEntityByName(name)
    end)

    if not ok then
        return nil
    end

    return entity
end

local function safeGetPosition(entity)
    if not entity then
        return nil
    end

    local ok, position = pcall(function()
        return entity.Position
    end)

    if not ok or not position then
        return nil
    end

    local x = tonumber(position.X)
    local y = tonumber(position.Y)
    local z = tonumber(position.Z)

    if x == nil or y == nil or z == nil then
        return nil
    end

    return x, y, z
end

local function safeGetTerritoryId()
    local ok, territoryId = pcall(function()
        return Svc and Svc.ClientState and Svc.ClientState.TerritoryType
    end)

    territoryId = ok and tonumber(territoryId) or nil
    if not territoryId or territoryId <= 0 then
        return nil
    end

    return territoryId
end

local function safeSetFlagMapMarker(territoryId, x, y)
    territoryId = tonumber(territoryId)
    x = tonumber(x)
    y = tonumber(y)

    if not territoryId or not x or not y then
        return false
    end

    if not (Instances and Instances.Map and Instances.Map.Flag and Instances.Map.Flag.SetFlagMapMarker) then
        return false
    end

    local ok = pcall(function()
        Instances.Map.Flag:SetFlagMapMarker(territoryId, x, y)
    end)

    return ok
end

local entityName = tostring(getConfigValue("Entity Name", "") or ""):match("^%s*(.-)%s*$")
local pollInterval = tonumber(getConfigValue("Poll Interval", 1)) or 1
pollInterval = math.max(0.1, math.min(10, pollInterval))

if entityName == "" then
    log("Config 'Entity Name' is blank; exiting.")
    return
end

log(string.format("Scanning for '%s' every %.1f second(s).", entityName, pollInterval))

local wasMissing = true

while true do
    local entity = safeGetEntityByName(entityName)

    if entity then
        if wasMissing then
            local x, y, z = safeGetPosition(entity)
            if x and y and z then
                local territoryId = safeGetTerritoryId()
                local flagPlaced = territoryId and safeSetFlagMapMarker(territoryId, x, z)

                if flagPlaced then
                    log(string.format("'%s' returned at %.2f, %.2f, %.2f. Flag placed in territory %d.", entityName, x, y, z, territoryId))
                else
                    log(string.format("'%s' returned at %.2f, %.2f, %.2f. Flag placement unavailable.", entityName, x, y, z))
                end
            else
                log(string.format("'%s' returned, but position is unavailable.", entityName))
            end
        end

        wasMissing = false
    else
        wasMissing = true
    end

    sleep(pollInterval)
end
