--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.0.2
description: |
  Support via https://ko-fi.com/baanderson40
  Features:
  Jump if stuck during movement
  Cycle through jobs for class score
  Spend Lunar Credits on Gamba
plugin_dependencies:
- ICE
configs:
  Jump if stuck:
    default: false
    description: Will cause you to jump is stuck in position for too long.
    type: boolean
  Jobs:
    description: |
      Jobs to cycle through.
      Leave blank to disable.
    type: list
  Lunar Credits Limit:
    default: 0
    description: |
      Set this to the same number as "Stop at Lunar Credits" in ICE. 
      Leave at 0 to disable.
    type: int
    min: 0
    max: 10000
[[End Metadata]]
--]=====]

--[[
********************************************************************************
*                                  Changelog                                   *
********************************************************************************
    -> 1.0.2 Improved stuck detection
    -> 1.0.1 Added Gamba support
    -> 1.0.0 Initial Release

]]

-- Imports
import("System.Numerics")

-- Definitions
-- Config veriables
JumpConfig = Config.Get("Jump if stuck")
JobsConfig = Config.Get("Jobs")
LimitConfig = Config.Get("Lunar Credits Limit")

-- Veriables
local loopDelay = .5 -- Script's speed/delay
local cycleLoops = 30 -- Number of ticks before switching to the next job

local Run_script = true
local lastPos = nil
local totalJobs = JobsConfig.Count
local cycleCount = 0
local jobCount = 0
local lunarCredits = 0
local lunarCycleCount = 0

local CharacterCondition = {
    normalConditions                   = 1, -- moving or standing still
    mounted                            = 4, -- moving
    crafting                           = 5,
    gathering                          = 6,
    casting                            = 27,
    occupiedMateriaExtractionAndRepair = 39,
    executingCraftingAction            = 40,
    preparingToCraft                   = 41,
    executingGatheringAction           = 42,
    betweenAreas                       = 45,
    jumping48                          = 48, -- moving
    mounting57                         = 57, -- moving
    unknown85                          = 85, -- Part of gathering
}

--NPC information
CreditNpc = {name = "Orbitingway", position = Vector3(16.3421, 1.695, -16.394)}

--Helper Funcitons
--Sleep 
local function sleep(seconds)
    yield('/wait ' .. tostring(seconds))
end

--Generic helper to check readiness of any named addon
local function IsAddonReady(name)
    local a = Addons.GetAddon(name)
    return a and a.Ready
end

--Get distance from two points
local function DistanctBetweenPositions(cur, last)
  local distance = Vector3.Distance(cur, last)
  return distance
end

-- Plugin detection and enabled
function HasPlugin(name)
    for plugin in luanet.each(Svc.PluginInterface.InstalledPlugins) do
        if plugin.InternalName == name and plugin.IsLoaded then
            return true
        end
    end
    return false
end

--Worker Funcitons
local function ShouldJump()
    if IPC.vnavmesh.IsRunning() then
            if lastPos == nil then
                lastPos = Player.Entity.Position
                return
            end
        local curPos = Player.Entity.Position
        if DistanctBetweenPositions(curPos, lastPos) < 3.25 then
            yield("/gaction jump")
            Dalamud.Log("[Cosmic Helper] Position hasn't changed jumping.")
            lastPos = nil
        else
            lastPos = nil
        end
    else
        lastPos = nil
    end
end

local function ShouldCycle()
    if Svc.Condition[CharacterCondition.normalConditions] == false then
        cycleCount = 0
        return
    elseif not IsAddonReady("WKSMission") then
        cycleCount = cycleCount + 1
    end
    if cycleCount % 10 == 0 
        and Svc.Condition[CharacterCondition.normalConditions] 
        and not IsAddonReady("WKSMission") then
            yield("/echo Job Cycle ticks: " .. cycleCount .. "/" .. cycleLoops)
    end
    if cycleCount > cycleLoops then
        if jobCount == totalJobs then
            yield("/echo End of list reached exiting script.")
            Run_script = false
            return
        end
        yield("/echo Swapping to -> " .. JobsConfig[jobCount])
        yield("/equipjob " .. JobsConfig[jobCount])
        yield("/wait 2")
        yield("/ice start")
        jobCount = jobCount + 1
        cycleCount = 0
    end
end

local function ShouldCredit()
    lunarCredits = Addons.GetAddon("WKSHud"):GetNode(1, 15, 17, 3).Text:gsub("[^%d]", "")
    if tonumber(lunarCredits) >= LimitConfig and Svc.Condition[CharacterCondition.normalConditions] then
        lunarCycleCount = lunarCycleCount + 1
    else
        lunarCycleCount = 0
        return
    end
    if lunarCycleCount > 0 and lunarCycleCount % 5 == 0 then
            yield("/echo Lunar Credit ticks: " .. lunarCycleCount .. "/ 10")
    end
    if lunarCycleCount >= 10 then
        yield("/echo Lunar credits: " .. tostring(lunarCredits) .. "/" .. LimitConfig .. " Going to Gamba!")
        lunarCycleCount = 0
        yield('/gaction "Duty Action"')
        sleep(5)
        while Svc.Condition[CharacterCondition.betweenAreas] or Svc.Condition[CharacterCondition.casting] do
            sleep(.5)
        end
        IPC.vnavmesh.PathfindAndMoveTo(CreditNpc.position, false)
        sleep(1)
        while IPC.vnavmesh.IsRunning() do
            sleep(.5)
            local curPos = Player.Entity.Position
            if DistanctBetweenPositions(curPos, CreditNpc.position) < 3 then
                IPC.vnavmesh.Stop()
            end
        end
        local e = Entity.GetEntityByName(CreditNpc.name)
        if e then
            e:SetAsTarget()
        end
        if Entity.Target and Entity.Target.Name == CreditNpc.name then
        Entity.Target:Interact()
        sleep(1)
        end
        while not IsAddonReady("SelectString") do
            sleep(1)
        end
        if IsAddonReady("SelectString") then
            Engines.Run("/callback SelectString true 0")
            sleep(1)
        end
        while not IsAddonReady("SelectString") do
            sleep(1)
        end
        if IsAddonReady("SelectString") then
            Engines.Run("/callback SelectString true 0")
            sleep(1)
        end
        while IsAddonReady("WKSLottery") do
            sleep(5)
        end
        if not IsAddonReady("WKSLottery") then
            yield("/ice start")
        end
    end
end

yield("/echo Cosmic Helper started!")

--Plugin Check
if JobsConfig.Count > 0 and not HasPlugin("SimpleTweaksPlugin") then
    yield("/echo [Cosmic Helper] Cycling jobs need SimpleTweaks plugin. Script will continue without playing Gamba.")
    JobsConfig = nil
end
if LimitConfig > 0 and not HasPlugin("TextAdvance") then
    yield("/echo [Cosmic Helper] Lunar Credit spending for Gamba needs TextAdvance plugin. Script will continue without playing Gamba.")
    LimitConfig = 0
end

--Main Loop
while Run_script do
  if JumpConfig then
    ShouldJump()
  end
  if JobsConfig ~= nil then
    ShouldCycle()
  end
  if LimitConfig > 0 then
    ShouldCredit()
  end
  sleep(loopDelay)
end
