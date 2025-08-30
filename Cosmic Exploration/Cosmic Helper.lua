--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.0.6
description: |
  Support via https://ko-fi.com/baanderson40
  Features:
  - Automatically jump if you get stuck while moving
  - Switch between jobs when EXP or class score goals are met (based on ICE settings)
  - Pause missions once the Lunar Credits limit is reached and spend them on Gamba
  - Optionally wait at random spot for a set time before moving
plugin_dependencies:
- ICE
configs:
  Jump if stuck:
    default: false
    description: Makes the character jump if it has been stuck in the same spot for too long.
  Jobs:
    description: |
      A list of jobs to cycle through when EXP or class score thresholds are reached,
      depending on the settings configured in ICE.
      Leave blank to disable job cycling.
    default: []
  Lunar Credits Limit:
    default: 0
    description: |
      Maximum number of Lunar Credits before missions will pause for Gamba.
      Match this with "Stop at Lunar Credits" in ICE to synchronize behavior.
      Enable Gamba under Gamble Wheel in ICE settings.
      Set to 0 to disable the limit.
    min: 0
    max: 10000
  Delay Moving Spots:
    default: 0
    description: |
      Number of minutes to remain at one spot before moving randomly to another.
      Use 0 to disable automatic spot movement.
    min: 0
    max: 1440
  Process Retainers Ventures:
    description: |
      Pause Cosmic Missions when retainers’ ventures are ready.
      Set to N/A to disable.
    is_choice: true
    choices: ["N/A", "Moongate Hub", "Inn", "Gridania", "Limsa Lominsa", "Ul'Dah"]
    default: "N/A"
[[End Metadata]]
--]=====]

--[[
********************************************************************************
*                                  Changelog                                   *
********************************************************************************
    -> 1.0.6 Added Retainer ventrues processing
    -> 1.0.5 Removed types from config settings
    -> 1.0.4 Improved Job cycling logic
    -> 1.0.3 Added random locations to move between with delay timer
    -> 1.0.2 Improved stuck detection
    -> 1.0.1 Added Gamba support
    -> 1.0.0 Initial Release

]]

-- Imports
import("System.Numerics") -- leave this alone....

--[[
********************************************************************************
*                            Advance User Settings                             *
********************************************************************************
]]


local loopDelay  = .5            -- Controls how fast the script runs; lower = faster, higher = slower (in seconds per loop)
local cycleLoops = 20           -- How many loop iterations to run before cycling to the next job
local moveOffSet = 5            -- Adds a random offset to spot movement time, up to ±5 minutes.
local spotRadius = 3            -- Defines the movement radius; the player will move within this distance when selecting a new spot


SpotPos = { -- Random positions for crafting 
    Vector3(9.521,1.705,14.300),            -- Summoning bell
    Vector3(8.870, 1.642, -13.272),         -- Cosmic Fortunes
    Vector3(-9.551, 1.705, -13.721),        -- Starward Standings
    Vector3(-12.039, 1.612, 16.360),        -- Cosmic Research
    Vector3(7.002, 1.674, -7.293),          -- Cosmic Fortunes inside loop
    Vector3(5.471, 1.660, 5.257),           -- Inside loop Summoning bell
    Vector3(-6.257, 1.660, 6.100),          -- Inside loop Cosmic Research
    Vector3(-5.919, 1.660, -5.678),         -- Inside loop Starward Standings
}


--[[
********************************************************************************
*                       Don't touch anything below here                        *
********************************************************************************
]]

-- Config veriables
JumpConfig      = Config.Get("Jump if stuck")
JobsConfig      = Config.Get("Jobs")
LimitConfig     = Config.Get("Lunar Credits Limit")
MoveConfig      = Config.Get("Delay Moving Spots")
RetainerConfig  = Config.Get("Process Retainers Ventures")

-- Veriables
local Run_script        = true
local lastPos           = nil
local totalJobs         = JobsConfig.Count
local cycleCount        = 0
local jobCount          = 0
local lunarCredits      = 0
local lunarCycleCount   = 0
local lastSpotIndex     = nil
local lastMoveTime      = nil
local offSet            = nil
local minRadius         = .5
local SelectedBell      = nil
local classScore        = {}

local CharacterCondition = {
    normalConditions                   = 1, -- moving or standing still
    mounted                            = 4, -- moving
    crafting                           = 5,
    gathering                          = 6,
    casting                            = 27,
    occupiedInQuestEvent               = 32,
    occupiedMateriaExtractionAndRepair = 39,
    executingCraftingAction            = 40,
    preparingToCraft                   = 41,
    executingGatheringAction           = 42,
    betweenAreas                       = 45,
    jumping48                          = 48, -- moving
    occupiedSummoningBell              = 50,
    mounting57                         = 57, -- moving
    unknown85                          = 85, -- Part of gathering
}

--Position Information
GateHub = Vector3(0,0,0)
SummoningBell = {
    {zone = "Inn", aethernet = "Inn", position = nil},
    {zone = "Cosmic", aethernet = nil, position = Vector3(9.870, 1.685, 14.865)},
    {zone = "Gridania", aethernet = "Leatherworkers' guild", position = Vector3(169.103, 15.500, -100.497)},
    {zone = "Limsa Lominsa", aethernet = "Limsa Lominsa", position = Vector3(-124.285, 18.000, 20.033)},
    {zone = "Ul'Dah", aethernet = "Sapphire Avenue Exchange", position = Vector3(148.241, 4.000, -41.936)},
}

if RetainerConfig ~= "N/A" then
    for _, bell in ipairs(SummoningBell) do
        if bell.zone == RetainerConfig then
            SelectedBell = bell
            break
        end
    end
end

--NPC information
CreditNpc = {name = "Orbitingway", position = Vector3(16.3421, 1.695, -16.394)}

--Helper Funcitons
local function sleep(seconds)
    yield('/wait ' .. tostring(seconds))
end

local function IsAddonReady(name)
    local a = Addons.GetAddon(name)
    return a and a.Ready
end

local function IsAddonExists(name)
    local a = Addons.GetAddon(name)
    return a and a.Exists
end

local function DistanctBetweenPositions(cur, last)
  local distance = Vector3.Distance(cur, last)
  return distance
end

function HasPlugin(name)
    for plugin in luanet.each(Svc.PluginInterface.InstalledPlugins) do
        if plugin.InternalName == name and plugin.IsLoaded then
            return true
        end
    end
    return false
end

function GetRandomSpotAround(radius, minDist)
    minDist = minDist or 0
    if #SpotPos == 0 then return nil end
    if #SpotPos == 1 then
        lastSpotIndex = 1
        return SpotPos[1]
    end
    local spotIndex
    repeat
        spotIndex = math.random(1, #SpotPos)
    until spotIndex ~= lastSpotIndex
    lastSpotIndex = spotIndex
    local center = SpotPos[spotIndex]
    local u = math.random()
    local distance = math.sqrt(u) * (radius - minDist) + minDist
    local angle = math.random() * 2 * math.pi
    local offsetX = math.cos(angle) * distance
    local offsetZ = math.sin(angle) * distance
    return Vector3(center.X + offsetX, center.Y, center.Z + offsetZ)
end

function RetrieveClassScore()
    local addon = Addons.GetAddon("WKSScoreList")
    if not IsAddonExists("WKSScoreList") then
        Engines.Run("/callback WKSHud true 18")
        yield("/wait .5")
    end
    local addon = Addons.GetAddon("WKSScoreList")
    local dohRows = {2, 21001, 21002, 21003, 21004, 21005, 21006, 21007}
    for _, dohRows in ipairs(dohRows) do
        local nameNode  = addon:GetNode(1, 2, 7, dohRows, 4)
        local scoreNode = addon:GetNode(1, 2, 7, dohRows, 5)
        if nameNode and scoreNode then
            table.insert(classScoreAll, {
                className  = string.lower(nameNode.Text),
                classScore = scoreNode.Text
            })
        end
    end
    local dolRows = {2, 21001, 21002}
    for _, dolRows in ipairs(dolRows) do
        local nameNode  = addon:GetNode(1, 8, 13, dolRows, 4)
        local scoreNode = addon:GetNode(1, 8, 13, dolRows, 5)
        if nameNode and scoreNode then
            table.insert(classScoreAll, {
                className  = string.lower(nameNode.Text),
                classScore = scoreNode.Text
            })
        end
    end
    for i, entry in ipairs(classScoreAll) do
        if Player.Job.Name == entry.className then
            currentScore = entry.classScore
            break
        end
    end
    return currentScore
end

--Worker Funcitons
local function ShouldJump()
    if Player.IsMoving then
        if lastPos == nil then
            lastPos = Player.Entity.Position
            return
        end
        local curPos = Player.Entity.Position
        if DistanctBetweenPositions(curPos, lastPos) < 3 then
            yield("/gaction jump")
            Dalamud.Log("[Cosmic Helper] Position hasn't changed jumping")
            lastPos = nil
        else
            lastPos = nil
        end
    else
        lastPos = nil
    end
end

local function ShouldRetainer()
    if IPC.AutoRetainer.AreAnyRetainersAvailableForCurrentChara() then
        local waitcount = 0
        while IsAddonReady("WKSMissionInfomation") do
            sleep(.2)
            waitcount = waitcount + 1
            Dalamud.Log("[Cosmic Helper] Waiting for mission to process retainers")
            if waitcount >= 10 then
                yield("/echo [Cosmic Helper] Waiting for mission to process retainers")
                waitcount = 0
            end
        end
        Dalamud.Log("[Cosmic Helper] Stopping ICE")
        yield("/ice stop")
        if SelectedBell.zone == "Moongate Hub" then
            local curPos = Player.Entity.Position
            if DistanctBetweenPositions(curPos, GateHub) > 75 then
                Dalamud.Log("[Cosmic Helper] Stellar Return")
                yield('/gaction "Duty Action"')
                sleep(5)
            end
        else
            IPC.Lifestream.ExecuteCommand(SelectedBell.aethernet)
            Dalamud.Log("[Cosmic Helper] Moving to " .. tostring(SelectedBell.aethernet))
            sleep(2)
        end
        while Svc.Condition[CharacterCondition.betweenAreas]
            or Svc.Condition[CharacterCondition.casting]
            or Svc.Condition[CharacterCondition.betweenAreasForDuty]
            or IPC.Lifestream.IsBusy() do
            sleep(.5)
        end
        sleep(2)
        if SelectedBell.position ~= nil then
            IPC.vnavmesh.PathfindAndMoveTo(SelectedBell.position, false)
            Dalamud.Log("[Cosmic Helper] Moving to summoning bell")
            sleep(2)
        end
        while IPC.vnavmesh.IsRunning() do
            sleep(.5)
            if DistanctBetweenPositions(Player.Entity.Position, SelectedBell.position) < 2 then
                Dalamud.Log("[Cosmic Helper] Close enough to summoning bell")
                IPC.vnavmesh.Stop()
                break
            end
        end
        while Svc.Targets.Target == nil or Svc.Targets.Target.Name:GetText() ~= "Summoning Bell" do
            Dalamud.Log("[Cosmic Helper] Targeting summoning bell")
            Engines.Run("/target Summoning Bell")
            sleep(1)
        end
        if not Svc.Condition[CharacterCondition.occupiedSummoningBell] then
            Dalamud.Log("[Cosmic Helper] Interacting with summoning bell")
            while not IsAddonReady("RetainerList") do
                Engines.Run("/interact")
                sleep(1)
            end
            if IsAddonReady("RetainerList") then
                Dalamud.Log("[Cosmic Helper] Enable AutoRetainer")
                Engines.Run("/ays e")
                sleep(1)
            end
        end
        while IPC.AutoRetainer.IsBusy() or Svc.Condition[CharacterCondition.occupiedSummoningBell] do
                sleep(1)
        end
        if IsAddonExists("RetainerList") then
            Dalamud.Log("[Cosmic Helper] Closeing RetainerList window")
            Engines.Run("/callback RetainerList true -1")
            sleep(1)
        end
        if Svc.ClientState.TerritoryType ~= 1237 then
            Dalamud.Log("[Cosmic Helper] Teleport to Cosmic")
            yield("/li Cosmic")
            sleep(3)
        end
        local cosmicCount = 0
        while Svc.ClientState.TerritoryType ~= 1237 do
            if Svc.ClientState.TerritoryType ~= 1237 then
                cosmicCount = cosmicCount + 1
                if cosmicCount >=  70 then
                    Dalamud.Log("[Cosmic Helper] Failed to teleport to Cosmic. Trying agian.")
                    yield("/echo [Cosmic Helper] Failed to teleport to Cosmic. Trying agian.")
                    yield("/li Cosmic")
                    cosmicCount = 0
                end
            else
                break
            end
            sleep(.5)
        end
        if Svc.ClientState.TerritoryType == 1237 then
            Dalamud.Log("[Cosmic Helper] Stellar Return")
            yield('/gaction "Duty Action"')
            sleep(5)
            while Svc.Condition[CharacterCondition.betweenAreas] or Svc.Condition[CharacterCondition.casting] do
                sleep(.5)
            end
            Dalamud.Log("[Cosmic Helper] Start ICE")
            yield("/ice start")
            sleep(2)
            yield("/ice start")
        end
    end
end

local function ShouldCredit()
    if lunarCredits >= LimitConfig and Svc.Condition[CharacterCondition.normalConditions] and not Player.IsBusy then
        lunarCycleCount = lunarCycleCount + 1
        Dalamud.Log("[Cosmic Helper] Lunar Credit ticks: " .. lunarCycleCount)
    else
        lunarCycleCount = 0
        return
    end
    if lunarCycleCount > 0 and lunarCycleCount % 5 == 0 then
            yield("/echo Lunar Credit ticks: " .. lunarCycleCount .. "/ 10")
    end
    if lunarCycleCount >= 10 then
        if not IPC.TextAdvance.IsEnabled() then
            yield("/at enable")
            local EnabledAutoText = true
        end
        Dalamud.Log("[Cosmic Helper] Lunar credits: " .. tostring(lunarCredits) .. "/" .. LimitConfig .. " Going to Gamba!")
        yield("/echo Lunar credits: " .. tostring(lunarCredits) .. "/" .. LimitConfig .. " Going to Gamba!")
        lunarCycleCount = 0
        local curPos = Player.Entity.Position
        if DistanctBetweenPositions(curPos, GateHub) > 75 then
            Dalamud.Log("[Cosmic Helper] Stellar Return")
            yield('/gaction "Duty Action"')
            sleep(5)
        end
        while Svc.Condition[CharacterCondition.betweenAreas] or Svc.Condition[CharacterCondition.casting] do
            sleep(.5)
        end
        IPC.vnavmesh.PathfindAndMoveTo(CreditNpc.position, false)
        Dalamud.Log("[Cosmic Helper] Moving to Gamba bunny")
        sleep(1)
        while IPC.vnavmesh.IsRunning() do
            sleep(.5)
            local curPos = Player.Entity.Position
            if DistanctBetweenPositions(curPos, CreditNpc.position) < 3 then
                Dalamud.Log("[Cosmic Helper] Near Gamba bunny. Stopping vnavmesh.")
                IPC.vnavmesh.Stop()
            end
        end
        local e = Entity.GetEntityByName(CreditNpc.name)
        if e then
            Dalamud.Log("[Cosmic Helper] Targetting: " .. CreditNpc.name)
            e:SetAsTarget()
        end
        if Entity.Target and Entity.Target.Name == CreditNpc.name then
            Dalamud.Log("[Cosmic Helper] Interacting: " .. CreditNpc.name)
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
        while Svc.Condition[CharacterCondition.occupiedInQuestEvent] do
            sleep(1)
            Dalamud.Log("[Cosmic Helper] Waiting for Gamba to finish")
        end
        if not Svc.Condition[CharacterCondition.occupiedInQuestEvent] then
            local job = Player.Job
            if job.IsCrafter then
                local aroundSpot = GetRandomSpotAround(spotRadius, minRadius)
                IPC.vnavmesh.PathfindAndMoveTo(aroundSpot, false)
                Dalamud.Log("[Cosmic Helper] Moving to random spot " .. tostring(aroundSpot))
                lastMoveTime = os.time()
                sleep(2)
            end
            if EnabledAutoText then
                yield("/at disable")
                EnabledAutoText = false
            end
            Dalamud.Log("[Cosmic Helper] Starting ICE")
            yield("/ice start")
            sleep(2)
            yield("/ice start")
        end
    end
end

local function ShouldMove()
    if LimitConfig > 0 and lunarCredits >= LimitConfig then
        return
    end
    if lastMoveTime == nil then
        lastMoveTime = os.time()
        return
    end
    if offSet == nil then
        offSet = math.random(-moveOffSet, moveOffSet)
    end
    local interval = math.max(1, MoveConfig + offSet)
    if os.time() - lastMoveTime >= interval * 60 then
        local waitcount = 0
        while IsAddonReady("WKSMissionInfomation") do
            sleep(.2)
            waitcount = waitcount + 1
            Dalamud.Log("[Cosmic Helper] Waiting for mission to move")
            if waitcount >= 10 then
                yield("/echo [Cosmic Helper] Waiting for mission to move.")
                waitcount = 0
            end
        end
        Dalamud.Log("[Cosmic Helper] Stopping ICE")
        yield("/ice stop")
        local curPos = Player.Entity.Position
        if DistanctBetweenPositions(curPos, GateHub) > 75 then
            Dalamud.Log("[Cosmic Helper] Stellar Return")
            yield('/gaction "Duty Action"')
            sleep(5)
        end
        while Svc.Condition[CharacterCondition.betweenAreas] or Svc.Condition[CharacterCondition.casting] do
            sleep(.5)
        end
        local aroundSpot = GetRandomSpotAround(spotRadius, minRadius)
        IPC.vnavmesh.PathfindAndMoveTo(aroundSpot, false)
        Dalamud.Log("[Cosmic Helper] Moving to random spot " .. tostring(aroundSpot))
        sleep(2)
        while IPC.vnavmesh.IsRunning do
            local curPos = Player.Entity.Position
            if DistanctBetweenPositions(curPos, aroundSpot) < 2 then
                Dalamud.Log("[Cosmic Helper] Near random spot. Stopping vnavmesh")
                IPC.vnavmesh.Stop()
                break
            end
            sleep(1)
        end
        yield("/ice start")
        Dalamud.Log("[Cosmic Helper] Starting ICE")
        lastMoveTime = os.time()
        offSet = nil
    end
end

local function ShouldCycle()
    if LimitConfig > 0 and lunarCredits >= LimitConfig then
        return
    end
    if Svc.Condition[CharacterCondition.normalConditions] then
        if (IsAddonExists("WKSMission")
        or IsAddonExists("WKSMissionInfomation")
        or IsAddonExists("WKSReward")
        or Player.IsBusy) then
            cycleCount = 0
            return
        else
            cycleCount = cycleCount + 1
            Dalamud.Log("[Cosmic Helper] Job Cycle ticks: " .. cycleCount)
        end
    end
    if cycleCount > 0 and cycleCount % 5 == 0 then
            yield("/echo [Cosmic Helper] Job Cycle ticks: " .. cycleCount .. "/" .. cycleLoops)
    end
    if cycleCount >= cycleLoops then
        if jobCount == totalJobs then
            Dalamud.Log("[Cosmic Helper] End of job list reached. Exiting script.")
            yield("/echo [Cosmic Helper] End of job list reached. Exiting script.")
            Run_script = false
            return
        end
        Dalamud.Log("[Cosmic Helper] Swapping to -> " .. JobsConfig[jobCount])
        yield("/echo [Cosmic Helper] Swapping to -> " .. JobsConfig[jobCount])
        yield("/equipjob " .. JobsConfig[jobCount])
        yield("/wait 2")
        Dalamud.Log("[Cosmic Helper] Starting ICE")
        yield("/ice start")
        jobCount = jobCount + 1
        cycleCount = 0
    end
end

yield("/echo Cosmic Helper started!")

--Plugin Check
if JobsConfig.Count > 0 and not HasPlugin("SimpleTweaksPlugin") then
    yield("/echo [Cosmic Helper] Cycling jobs requires SimpleTweaks plugin. Script will continue without changing jobs.")
    JobsConfig = nil
end
if LimitConfig > 0 and not HasPlugin("TextAdvance") then
    yield("/echo [Cosmic Helper] Lunar Credit spending for Gamba requires TextAdvance plugin. Script will continue without playing Gamba.")
    LimitConfig = 0
end
if RetainerConfig ~= "N/A" and not HasPlugin("AutoRetainer") then
    yield("/echo [Cosmic Helper] Retainer processing requires TextAdvance plugin. Script will continue without processing retainers.")
    RetainerConfig = "N/A"
end
local job = Player.Job
if not job.IsCrafter and MoveConfig > 0 then
    yield("/echo [Cosmic Helper] Only crafters should move. Script will continue without moving.")
    MoveConfig = false
end

--Main Loop
while Run_script do
    lunarCredits = Addons.GetAddon("WKSHud"):GetNode(1, 15, 17, 3).Text:gsub("[^%d]", "")
    lunarCredits = tonumber(lunarCredits)
    if JumpConfig then
        ShouldJump()
    end
    if RetainerConfig ~= "N/A" then
        ShouldRetainer()
    end
    if LimitConfig > 0 then
        ShouldCredit()
    end
    if MoveConfig > 0 then
        ShouldMove()
    end
    if totalJobs > 0 then
        ShouldCycle()
    end
    sleep(loopDelay)
end
