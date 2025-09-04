--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.1.1d
description: |
  Support via https://ko-fi.com/baanderson40
  Features:
  - Automatically jump if you get stuck while moving
  - Switch between jobs when EXP or class score goals are met (based on ICE settings)
  - Pause missions once the Lunar Credits limit is reached and spend them on Gamba
  - Optionally wait at random spot for a set time before moving
  - Automatically turn in research points for relic
plugin_dependencies:
- ICE
configs:
  Jump if stuck:
    description: Makes the character jump if it has been stuck in the same spot for too long.
    default: false
  Jobs:
    description: |
      A list of jobs to cycle through when EXP or class score thresholds are reached,
      depending on the settings configured in ICE.
      -- Enable equip job command in Simple Tweaks and leave it as the default. --
      Leave blank to disable job cycling.
    default: []
  Lunar Credits Limit:
    description: |
      Maximum number of Lunar Credits before missions will pause for Gamba.
      Match this with "Stop at Lunar Credits" in ICE to synchronize behavior.
      -- Enable Gamba under Gamble Wheel in ICE settings. --
      Set to 0 to disable the limit.
    default: 0
    min: 0
    max: 10000
  Delay Moving Spots:
    description: |
      Number of minutes to remain at one spot before moving randomly to another.
      Use 0 to disable automatic spot movement.
    default: 0
    min: 0
    max: 1440
  Process Retainers Ventures:
    description: |
      **Only moon locations function**
      Pause cosmic missions when retainers’ ventures are ready.
      Set to N/A to disable.
    default: "N/A"
    is_choice: true
    choices: ["N/A","Glassblowers' Beacon (Pharnna)", "Moongate Hub (Sinus)", "Inn", "Gridania", "Limsa Lominsa", "Ul'Dah"]
  Research Turnin:
    description: |
      Enable to automatically turn in research for relic.
    default: false
[[End Metadata]]
--]=====]

--[[
********************************************************************************
*                                  Changelog                                   *
********************************************************************************
    -> 1.1.1 Added additonal addon for relic excahnge and cycling research UI window
    -> 1.1.0 Added ability to turn in research for relic
    -> 1.0.8 Fixed meta data config settings
    -> 1.0.7 Fixed a typo for Moongate Hub in retainer processing
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


local loopDelay  = .5           -- Controls how fast the script runs; lower = faster, higher = slower (in seconds per loop)
local cycleLoops = 20           -- How many loop iterations to run before cycling to the next job
local moveOffSet = 5            -- Adds a random offset to spot movement time, up to ±5 minutes.
local spotRadius = 3            -- Defines the movement radius; the player will move within this distance when selecting a new spot

if Svc.ClientState.TerritoryType == 1237 then -- Sinus 
    SpotPos = { -- Sinus random spots for crafting 
        Vector3(9.521,1.705,14.300),            -- Summoning bell
        Vector3(8.870, 1.642, -13.272),         -- Cosmic Fortunes
        Vector3(-9.551, 1.705, -13.721),        -- Starward Standings
        Vector3(-12.039, 1.612, 16.360),        -- Cosmic Research
        Vector3(7.002, 1.674, -7.293),          -- Cosmic Fortunes inside loop
        Vector3(5.471, 1.660, 5.257),           -- Inside loop Summoning bell
        Vector3(-6.257, 1.660, 6.100),          -- Inside loop Cosmic Research
        Vector3(-5.919, 1.660, -5.678),         -- Inside loop Starward Standings
}
elseif Svc.ClientState.TerritoryType == 1291 then
    SpotPos = {
        Vector3(355.522, 52.625, -409.623), -- Summoning bell
        Vector3(353.649, 52.625, -403.039), -- Credit Exchange
        Vector3(356.086, 52.625, -434.961), -- Cosmic Fortunes
        Vector3(330.380, 52.625, -436.684), -- Starward Standings
        Vector3(319.037, 52.625, -417.655), -- Mech Ops
    }
end


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
ResearchConfig  = Config.Get("Research Turnin")

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
local ClassScoreAll     = {}

local CharacterCondition = {
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
    betweenAreas                       = 45,
    jumping48                          = 48, -- moving
    occupiedSummoningBell              = 50,
    mounting57                         = 57, -- moving
    unknown85                          = 85, -- Part of gathering
}

--Position Information
SinusGateHub = Vector3(0,0,0)
PhaennaGateHub = Vector3(340.721, 52.864, -418.183)

SummoningBell = {
  --  {zone = "Inn", aethernet = "Inn", position = nil},
    {zone = "Glassblowers' Beacon (Pharnna)", aethernet = nil, position = Vector3(356.396, 52.625, -409.360)},
    {zone = "Moongate Hub (Sinus)", aethernet = nil, position = Vector3(9.870, 1.685, 14.865)},
    }--[[{zone = "Gridania", aethernet = "Leatherworkers' guild", position = Vector3(169.103, 15.500, -100.497)},
    {zone = "Limsa Lominsa", aethernet = "Limsa Lominsa", position = Vector3(-124.285, 18.000, 20.033)},
    {zone = "Ul'Dah", aethernet = "Sapphire Avenue Exchange", position = Vector3(148.241, 4.000, -41.936)},
}]]

if RetainerConfig ~= "N/A" then
    for _, bell in ipairs(SummoningBell) do
        if bell.zone == RetainerConfig then
            SelectedBell = bell
            break
        end
    end
end

--TerritoryType
SinusTerritory = 1237
PhaennaTerritory = 1291

--NPC information
SinusCreditNpc = {name = "Orbitingway", position = Vector3(18.845, 2.243, -18.906)}
SinusResearchNpc = {name = "Researchingway", position = Vector3(-18.906, 2.151, 18.845)}
PhaennaCreditNpc = {name = "Orbitingway", position = Vector3(358.816, 53.193, -438.865)}
PhaennaResearchNpc = {name = "Researchingway", position = Vector3(321.218, 53.193, -401.236)}

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

local function DistanctBetweenPositions(pos1, pos2)
  local distance = Vector3.Distance(pos1, pos2)
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
    local classScoreAll = {}
    if not IsAddonExists("WKSScoreList") then
        Engines.Run("/callback WKSHud true 18")
        sleep(.5)
    end
    local scoreAddon = Addons.GetAddon("WKSScoreList")
    local dohRows = {2, 21001, 21002, 21003, 21004, 21005, 21006, 21007}
    for _, dohRows in ipairs(dohRows) do
        local nameNode  = scoreAddon:GetNode(1, 2, 7, dohRows, 4)
        local scoreNode = scoreAddon:GetNode(1, 2, 7, dohRows, 5)
        if nameNode and scoreNode then
            table.insert(classScoreAll, {
                className  = string.lower(nameNode.Text),
                classScore = scoreNode.Text
            })
        end
    end
    local dolRows = {2, 21001, 21002}
    for _, dolRows in ipairs(dolRows) do
        local nameNode  = scoreAddon:GetNode(1, 8, 13, dolRows, 4)
        local scoreNode = scoreAddon:GetNode(1, 8, 13, dolRows, 5)
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

local function toNumber(s)
    if type(s) ~= "string" then return tonumber(s) end
    s = s:match("^%s*(.-)%s*$")
    s = s:gsub(",", "")
    return tonumber(s)
end

function RetrieveRelicResearch()
    if Svc.Condition[CharacterCondition.crafting]
       or Svc.Condition[CharacterCondition.gathering]
       or IsAddonExists("WKSMissionInfomation") then
        if IsAddonExists("WKSToolCustomize") then
            Engines.Run("/callback WKSToolCustomize true -1")
        end
        return false
    elseif not IsAddonExists("WKSToolCustomize") then
        if IsAddonExists("WKSHud") then
          Engines.Run("/callback WKSHud true 15")
          sleep(.5)
        end
    end
    if IsAddonExists("WKSToolCustomize") then
      local ToolAddon = Addons.GetAddon("WKSToolCustomize")
      local researchRows = {4, 41001, 41002, 41003, 41004, 41005, 41006, 41007}
      for _, row in ipairs(researchRows) do
          local currentNode  = ToolAddon:GetNode(1, 55, 68, row, 4, 5)
          local requiredNode = ToolAddon:GetNode(1, 55, 68, row, 4, 7)
          if not currentNode or not requiredNode then break end
          local current  = toNumber(currentNode.Text)
          local required = toNumber(requiredNode.Text)
          if current == nil or required == nil then break end
          if current < required then
              return false
          end
      end
      return true
    else
      return false
    end
end

--Worker Funcitons
local function ShouldJump()
    if Player.IsMoving then
        if lastPos == nil then
            lastPos = Svc.ClientState.LocalPlayer.Position
            return
        end
        local curPos = Svc.ClientState.LocalPlayer.Position
        if DistanctBetweenPositions(curPos, lastPos) < 3 then
            Engines.Run("/gaction jump")
            Dalamud.Log("[Cosmic Helper] Position hasn't changed jumping")
            lastPos = nil
        else
            lastPos = nil
        end
    else
        lastPos = nil
    end
end

local function ShouldRelic()
    if RetrieveRelicResearch() then
        if not IPC.TextAdvance.IsEnabled() then
            Engines.Run("/at enable")
            local EnabledAutoText = true
        end
        Dalamud.Log("[Cosmic Helper] Research level met!")
        Engines.Run("/echo [Cosmic Helper] Research level met!")
        local waitcount = 0
        while IsAddonReady("WKSMissionInfomation") do
            sleep(.1)
            waitcount = waitcount + 1
            Dalamud.Log("[Cosmic Helper] Waiting for mission to move")
            if waitcount >= 20 then
                Engines.Run("/echo [Cosmic Helper] Waiting for mission to move.")
                waitcount = 0
            end
        end
        Dalamud.Log("[Cosmic Helper] Stopping ICE")
        Engines.Run("/ice stop")
        local curPos = Svc.ClientState.LocalPlayer.Position
        if Svc.ClientState.TerritoryType == SinusTerritory then
            if DistanctBetweenPositions(curPos, SinusGateHub) > 75 then
                Dalamud.Log("[Cosmic Helper] Stellar Return")
                Engines.Run('/gaction "Duty Action"')
                sleep(5)
            end
            while Svc.Condition[CharacterCondition.betweenAreas] or Svc.Condition[CharacterCondition.casting] do
                sleep(.5)
            end
            IPC.vnavmesh.PathfindAndMoveTo(SinusResearchNpc.position, false)
            Dalamud.Log("[Cosmic Helper] Moving to Research bunny")
            sleep(1)
            while IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() do
                sleep(.01)
                local curPos = Svc.ClientState.LocalPlayer.Position
                if DistanctBetweenPositions(curPos, SinusResearchNpc.position) < 4 then
                    Dalamud.Log("[Cosmic Helper] Near Research bunny. Stopping vnavmesh.")
                    IPC.vnavmesh.Stop()
                    break
                end
            end
        elseif Svc.ClientState.TerritoryType == PhaennaTerritory then
            if DistanctBetweenPositions(curPos, PhaennaGateHub) > 75 then
                Dalamud.Log("[Cosmic Helper] Stellar Return")
                Engines.Run('/gaction "Duty Action"')
                sleep(5)
            end
            while Svc.Condition[CharacterCondition.betweenAreas] or Svc.Condition[CharacterCondition.casting] do
                sleep(.5)
            end
            IPC.vnavmesh.PathfindAndMoveTo(PhaennaResearchNpc.position, false)
            Dalamud.Log("[Cosmic Helper] Moving to Research bunny")
            sleep(1)
            while IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() do
                sleep(.01)
                local curPos = Svc.ClientState.LocalPlayer.Position
                if DistanctBetweenPositions(curPos, PhaennaResearchNpc.position) < 5 then
                    Dalamud.Log("[Cosmic Helper] Near Research bunny. Stopping vnavmesh.")
                    IPC.vnavmesh.Stop()
                    break
                end
            end
        end
        local e = Entity.GetEntityByName(SinusResearchNpc.name)
        if e then
            Dalamud.Log("[Cosmic Helper] Targetting: " .. SinusResearchNpc.name)
            e:SetAsTarget()
        end
        if Entity.Target and Entity.Target.Name == SinusResearchNpc.name then
            Dalamud.Log("[Cosmic Helper] Interacting: " .. SinusResearchNpc.name)
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
        while not IsAddonReady("SelectIconString") do
            sleep(1)
        end
        if IsAddonReady("SelectIconString") then
            StringId = Player.Job.Id - 8
            Engines.Run("/callback SelectIconString true " .. StringId)
        end
        while not IsAddonReady("SelectYesno") do
            sleep(1)
        end
        if IsAddonReady("SelectYesno") then
            Engines.Run("/callback SelectYesno true 0")
        end
        local job = Player.Job
        if job.IsCrafter then
            local aroundSpot = GetRandomSpotAround(spotRadius, minRadius)
            IPC.vnavmesh.PathfindAndMoveTo(aroundSpot, false)
            Dalamud.Log("[Cosmic Helper] Moving to random spot " .. tostring(aroundSpot))
            lastMoveTime = os.time()
            sleep(2)
        end
        if EnabledAutoText then
            Engines.Run("/at disable")
            EnabledAutoText = false
        end
        Dalamud.Log("[Cosmic Helper] Starting ICE")
        Engines.Run("/ice start")
        sleep(2)
        Engines.Run("/ice start")
    end
end

local function ShouldRetainer()
    if IPC.AutoRetainer.AreAnyRetainersAvailableForCurrentChara() then
        local waitcount = 0
        while IsAddonExists("WKSMissionInfomation") do
            sleep(.2)
            waitcount = waitcount + 1
            Dalamud.Log("[Cosmic Helper] Waiting for mission to process retainers")
            if waitcount >= 10 then
                Engines.Run("/echo [Cosmic Helper] Waiting for mission to process retainers")
                waitcount = 0
            end
        end
        Dalamud.Log("[Cosmic Helper] Stopping ICE")
        Engines.Run("/ice stop")
        if SelectedBell.zone == "Moongate Hub" then
            local curPos = Svc.ClientState.LocalPlayer.Position
            if DistanctBetweenPositions(curPos, SinusGateHub) > 75 then
                Dalamud.Log("[Cosmic Helper] Stellar Return")
                Engines.Run('/gaction "Duty Action"')
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
            if DistanctBetweenPositions(Svc.ClientState.LocalPlayer.Position, SelectedBell.position) < 2 then
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
        if Svc.ClientState.TerritoryType ~= SinusTerritory then
            Dalamud.Log("[Cosmic Helper] Teleport to Cosmic")
            Engines.Run("/li Cosmic")
            sleep(3)
        end
        local cosmicCount = 0
        while Svc.ClientState.TerritoryType ~= SinusTerritory do
            if Svc.ClientState.TerritoryType ~= SinusTerritory then
                cosmicCount = cosmicCount + 1
                if cosmicCount >=  70 then
                    Dalamud.Log("[Cosmic Helper] Failed to teleport to Cosmic. Trying agian.")
                    Engines.Run("/echo [Cosmic Helper] Failed to teleport to Cosmic. Trying agian.")
                    Engines.Run("/li Cosmic")
                    cosmicCount = 0
                end
            else
                break
            end
            sleep(.5)
        end
        if Svc.ClientState.TerritoryType == SinusTerritory then
            while Svc.Condition[CharacterCondition.betweenAreas]
               or Svc.Condition[CharacterCondition.casting]
               or Svc.Condition[CharacterCondition.occupied33] do
                sleep(.5)
            end
            Dalamud.Log("[Cosmic Helper] Stellar Return")
            Engines.Run('/gaction "Duty Action"')
            sleep(5)
            while Svc.Condition[CharacterCondition.betweenAreas] or Svc.Condition[CharacterCondition.casting] do
                sleep(.5)
            end
            Dalamud.Log("[Cosmic Helper] Start ICE")
            Engines.Run("/ice start")
            sleep(2)
            Engines.Run("/ice start")
        end
    end
end

local function ShouldCredit()
    if lunarCredits >= LimitConfig and Svc.Condition[CharacterCondition.normalConditions] and not Player.IsBusy then
        if not IPC.TextAdvance.IsEnabled() then
            Engines.Run("/at enable")
            local EnabledAutoText = true
        end
        Dalamud.Log("[Cosmic Helper] Lunar credits: " .. tostring(lunarCredits) .. "/" .. LimitConfig .. " Going to Gamba!")
        Engines.Run("/echo Lunar credits: " .. tostring(lunarCredits) .. "/" .. LimitConfig .. " Going to Gamba!")
        local curPos = Svc.ClientState.LocalPlayer.Position
        if Svc.ClientState.TerritoryType == SinusTerritory then
        if DistanctBetweenPositions(curPos, SinusGateHub) > 75 then
            Dalamud.Log("[Cosmic Helper] Stellar Return")
            Engines.Run('/gaction "Duty Action"')
            sleep(5)
        end
        while Svc.Condition[CharacterCondition.betweenAreas] or Svc.Condition[CharacterCondition.casting] do
            sleep(.5)
        end
        IPC.vnavmesh.PathfindAndMoveTo(SinusCreditNpc.position, false)
        Dalamud.Log("[Cosmic Helper] Moving to Gamba bunny")
        sleep(1)
        while IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() do
            sleep(.01)
            local curPos = Svc.ClientState.LocalPlayer.Position
            if DistanctBetweenPositions(curPos, SinusCreditNpc.position) < 5 then
                Dalamud.Log("[Cosmic Helper] Near Gamba bunny. Stopping vnavmesh.")
                IPC.vnavmesh.Stop()
            end
        end
        elseif Svc.ClientState.TerritoryType == PhaennaTerritory then
            if DistanctBetweenPositions(curPos, PhaennaGateHub) > 75 then
                Dalamud.Log("[Cosmic Helper] Stellar Return")
                Engines.Run('/gaction "Duty Action"')
                sleep(5)
            end
            while Svc.Condition[CharacterCondition.betweenAreas] or Svc.Condition[CharacterCondition.casting] do
                sleep(.5)
            end
            IPC.vnavmesh.PathfindAndMoveTo(PhaennaCreditNpc.position, false)
            Dalamud.Log("[Cosmic Helper] Moving to Gamba bunny")
            sleep(1)
            while IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() do
                sleep(.01)
                local curPos = Svc.ClientState.LocalPlayer.Position
                if DistanctBetweenPositions(curPos, PhaennaCreditNpc.position) < 4 then
                    Dalamud.Log("[Cosmic Helper] Near Gamba bunny. Stopping vnavmesh.")
                    IPC.vnavmesh.Stop()
                    break
                end
            end
        end
        local e = Entity.GetEntityByName(SinusCreditNpc.name)
        if e then
            Dalamud.Log("[Cosmic Helper] Targetting: " .. SinusCreditNpc.name)
            e:SetAsTarget()
        end
        if Entity.Target and Entity.Target.Name == SinusCreditNpc.name then
            Dalamud.Log("[Cosmic Helper] Interacting: " .. SinusCreditNpc.name)
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
                Engines.Run("/at disable")
                EnabledAutoText = false
            end
            Dalamud.Log("[Cosmic Helper] Starting ICE")
            Engines.Run("/ice start")
            sleep(2)
            Engines.Run("/ice start")
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
        while IsAddonExists("WKSMissionInfomation") do
            sleep(.1)
            waitcount = waitcount + 1
            Dalamud.Log("[Cosmic Helper] Waiting for mission to move")
            if waitcount >= 10 then
                Engines.Run("/echo [Cosmic Helper] Waiting for mission to move.")
                waitcount = 0
            end
        end
        Dalamud.Log("[Cosmic Helper] Stopping ICE")
        Engines.Run("/ice stop")        
        local curPos = Svc.ClientState.LocalPlayer.Position
        if Svc.ClientState.TerritoryType == SinusTerritory then
            if DistanctBetweenPositions(curPos, SinusGateHub) > 75 then
                Dalamud.Log("[Cosmic Helper] Stellar Return")
                Engines.Run('/gaction "Duty Action"')
                sleep(5)
            end
        elseif Svc.ClientState.TerritoryType == PhaennaTerritory then
            if DistanctBetweenPositions(curPos, PhaennaGateHub) > 75 then
                Dalamud.Log("[Cosmic Helper] Stellar Return")
                Engines.Run('/gaction "Duty Action"')
                sleep(5)
            end
        end
        while Svc.Condition[CharacterCondition.betweenAreas] or Svc.Condition[CharacterCondition.casting] do
            sleep(.5)
        end
        local aroundSpot = GetRandomSpotAround(spotRadius, minRadius)
        IPC.vnavmesh.PathfindAndMoveTo(aroundSpot, false)
        Dalamud.Log("[Cosmic Helper] Moving to random spot " .. tostring(aroundSpot))
        sleep(2)
        while IPC.vnavmesh.IsRunning do
            local curPos = Svc.ClientState.LocalPlayer.Position
            if DistanctBetweenPositions(curPos, aroundSpot) < 2 then
                Dalamud.Log("[Cosmic Helper] Near random spot. Stopping vnavmesh")
                IPC.vnavmesh.Stop()
                break
            end
            sleep(1)
        end
        Engines.Run("/ice start")
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
            Engines.Run("/echo [Cosmic Helper] Job Cycle ticks: " .. cycleCount .. "/" .. cycleLoops)
    end
    if cycleCount >= cycleLoops then
        if jobCount == totalJobs then
            Dalamud.Log("[Cosmic Helper] End of job list reached. Exiting script.")
            Engines.Run("/echo [Cosmic Helper] End of job list reached. Exiting script.")
            Run_script = false
            return
        end
        Dalamud.Log("[Cosmic Helper] Swapping to -> " .. JobsConfig[jobCount])
        Engines.Run("/echo [Cosmic Helper] Swapping to -> " .. JobsConfig[jobCount])
        Engines.Run("/equipjob " .. JobsConfig[jobCount])
        sleep(2)
        Dalamud.Log("[Cosmic Helper] Starting ICE")
        Engines.Run("/ice start")
        jobCount = jobCount + 1
        cycleCount = 0
    end
end

Engines.Run("/echo Cosmic Helper started!")

--Plugin Check
if JobsConfig.Count > 0 and not HasPlugin("SimpleTweaksPlugin") then
    Engines.Run("/echo [Cosmic Helper] Cycling jobs requires SimpleTweaks plugin. Script will continue without changing jobs.")
    JobsConfig = nil
end
if LimitConfig > 0 and not HasPlugin("TextAdvance") then
    Engines.Run("/echo [Cosmic Helper] Lunar Credit spending for Gamba requires TextAdvance plugin. Script will continue without playing Gamba.")
    LimitConfig = 0
end
if ResearchConfig and not HasPlugin("TextAdvance") then
    Engines.Run("/echo [Cosmic Helper] Research turnin requires TextAdvance plugin. Script will continue without turning in research for relics.")
    ResearchConfig = 0
end
if RetainerConfig ~= "N/A" and not HasPlugin("AutoRetainer") then
    Engines.Run("/echo [Cosmic Helper] Retainer processing requires TextAdvance plugin. Script will continue without processing retainers.")
    RetainerConfig = "N/A"
end
local job = Player.Job
if not job.IsCrafter and MoveConfig > 0 then
    Engines.Run("/echo [Cosmic Helper] Only crafters should move. Script will continue.")
    MoveConfig = 0
end

--Enable plugin options
Engines.Run("/tweaks enable EquipJobCommand true")

--Main Loop
while Run_script do
    lunarCredits = Addons.GetAddon("WKSHud"):GetNode(1, 15, 17, 3).Text:gsub("[^%d]", "")
    lunarCredits = tonumber(lunarCredits)
    if JumpConfig then
        ShouldJump()
    end
    if ResearchConfig then
        ShouldRelic()
    end
    if RetainerConfig ~= "N/A" then
        --ShouldRetainer()
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
