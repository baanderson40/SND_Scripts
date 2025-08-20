--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.0.0
description: Helper script for ICE and cosmic exploration.
plugin_dependencies:
- ICE
- SimpleTweaksPlugin
configs:
  Jump if stuck:
    default: true
    description: Will cause you to jump is stuck in position for too long.
    type: bool
  Jobs:
    description: Jobs to cycle through.
    type: list

[[End Metadata]]
--]=====]

--[[
********************************************************************************
*                                  Changelog                                   *
********************************************************************************
  -> 1.0.0 Initial Release

]]

-- Imports
import("System.Numerics")

-- Definitions
-- Config veriables
JumpConfig = Config.Get("Jump if stuck")
JobsConfig = Config.Get("Jobs")

-- Veriables
local loopDelay = .5 -- Script's speed/delay
local cycleLoops = 30 -- Number of ticks before switching to the next job

local Run_script = true
local lastPos = nil
local totalJobs = JobsConfig.Count
local cycleCount = 0
local jobCount = 0

local CharacterCondition = {
    normalConditions                   = 1, -- moving or standing still
    mounted                            = 4, -- moving
    crafting                           = 5, --
    gathering                          = 6, --
    occupiedMateriaExtractionAndRepair = 39, --
    executingCraftingAction            = 40, --
    preparingToCraft                   = 41, --
    executingGatheringAction           = 42, --
    jumping48                          = 48, -- moving
    mounting57                         = 57, -- moving
    unknown85                          = 85, -- Part of gathering
}

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

--Worker Funcitons

-- Jump if stuck
local function ShouldJump()
    if (Svc.Condition[CharacterCondition.normalConditions] -- Checks if should be moving or not based on conditions and missions window being open.
        or Svc.Condition[CharacterCondition.mounted]
        or Svc.Condition[CharacterCondition.jumping48]
        or Svc.Condition[CharacterCondition.mounting57])
        and IsAddonReady("WKSMission") then
            if lastPos == nil then -- Gets position and returns to main loop
                lastPos = Player.Entity.Position
                return
            end
        local curPos = Player.Entity.Position -- Gets position again after first time to compare
        if DistanctBetweenPositions(curPos, lastPos) < 3.25 then -- Compares difference between loops. 3.25 is enough for walking not to jump.
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
    elseif not IsAddonReady("WKSMission") then
        cycleCount = cycleCount + 1
    end
    if cycleCount % 10 == 0 
        and Svc.Condition[CharacterCondition.normalConditions] 
        and not IsAddonReady("WKSMission") then
            yield("/echo waiting " .. cycleCount .. "/" .. cycleLoops .. " ticks")
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

yield("/echo Cosmic Helper started!")
--Main Loop
while Run_script do
  if JumpConfig then
    ShouldJump()
  end
  if JobConfig ~= nil or JobConfig ~="" then
    ShouldCycle()
  end
  sleep(loopDelay)
end
