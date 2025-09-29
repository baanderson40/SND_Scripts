--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.3.3a
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
- vnavmesh
- TextAdvance
- SimpleTweaksPlugin
configs:
  Jump if stuck:
    description: Makes the character jump if it has been stuck in the same spot for too long.
    default: false
  Jobs:
    description: |
      A list of jobs to cycle through when EXP or class score thresholds are reached,
      depending on the settings configured in ICE.
      Enter short or full job name and press enter. One job per line.
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
  Report Failed Missions:
    description: |
      Enable to report missions that failed to reach scoreing tier.
    default: false
  EX+ 4hr Timed Missions:
    description: |
      Enable to swap crafting jobs to the current EX+ 4hr long timed mission job.
      ARM -> GSM -> LTW -> WVR -> CRP -> BSM -> repeat
    default: false
  EX+ 2hr Timed Missions:
    description: |
      Enable to swap crafting jobs to the current EX+ 2hr long timed mission job.
      LTW -> WVR -> ALC -> CUL -> ARM -> GSM -> repeat
    default: false
  Delay Moving Spots:
    description: |
      Number of minutes to remain at one spot before moving randomly to another.
      Use 0 to disable automatic spot movement.
    default: 0
    min: 0
    max: 1440
  Process Retainers Ventures:
    description: |
      Pause cosmic missions when retainers’ ventures are ready.
      -- Doesn't return to Sinus moon after leaving --
      Set to N/A to disable.
    default: "N/A"
    is_choice: true
    choices: ["N/A","Glassblowers' Beacon (Pharnna)", "Moongate Hub (Sinus)", "Inn", "Gridania", "Limsa Lominsa", "Ul'Dah"]
  Research Turnin:
    description: |
      Enable to automatically turn in research for relic.
    default: false
  Use Alt Job:
    description: |
      Enable to use an alternative crafter during turning in research for relic. 
      Doesn't work if the tool is saved to the gear set. 
    default: false
  Relic Jobs:
    description: |
      A list of jobs to cycle through when relic tool is completed.
      Don't include the starting/current job. Start the list with the next intended job. 
      Enter short or full job name and press enter. One job per line.
      -- Enable equip job command in Simple Tweaks and leave it as the default. --
      Leave blank to disable job cycling.
    default: []
[[End Metadata]]
--]=====]

--[[
********************************************************************************
*                                  Changelog                                   *
********************************************************************************
    -> 1.3.4 Modified the Alt job option to use a different crafting job for turnin.
    -> 1.3.3 Fixed Summoning Bell position in Sinus
    -> 1.3.2 Added localization support -- mostly
    -> 1.3.1 Adjustments for relic turn-in due to failed mission reporting
    -> 1.3.0 Released failed mission reporting
    -> 1.2.1 Fixed EX+ enabled automatically
    -> 1.2.0 Release job swapping support for EX+ timed missions for crafters
    -> 1.1.4 Added support for retainer processing off of the moon
    -> 1.1.3 Adjusted speed/timing for relic turn-in & added Alt job for turn-in
    -> 1.1.2 Updates related to relic turnin and retainer processing
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

loopDelay  = .1           -- Controls how fast the script runs; lower = faster, higher = slower (in seconds per loop)
cycleLoops = 100          -- How many loop iterations to run before cycling to the next job
moveOffSet = 5            -- Adds a random offset to spot movement time, up to ±5 minutes.
spotRadius = 3            -- Defines the movement radius; the player will move within this distance when selecting a new spot
extraRetainerDelay = false

if Svc.ClientState.TerritoryType == 1237 then -- Sinus 
    SpotPos = {
        Vector3(9.521,1.705,14.300),            -- Summoning bell
        Vector3(8.870, 1.642, -13.272),         -- Cosmic Fortunes
        Vector3(-9.551, 1.705, -13.721),        -- Starward Standings
        Vector3(-12.039, 1.612, 16.360),        -- Cosmic Research
        Vector3(7.002, 1.674, -7.293),          -- Cosmic Fortunes inside loop
        Vector3(5.471, 1.660, 5.257),           -- Inside loop Summoning bell
        Vector3(-6.257, 1.660, 6.100),          -- Inside loop Cosmic Research
        Vector3(-5.919, 1.660, -5.678),         -- Inside loop Starward Standings
}
elseif Svc.ClientState.TerritoryType == 1291 then --Phaenna
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

--Helper Funcitons
function currentexJobs2H()
    local h = getEorzeaHour()
    local slot = math.floor(h / 2) * 2
    local jobs = exJobs2H[slot]
    return jobs and jobs[1] or nil
end

function currentexJobs4H()
    local h = getEorzeaHour()
    local slot = math.floor(h / 4) * 4
    local jobs = exJobs4H[slot]
    return jobs and jobs[1] or nil
end

function DistanceBetweenPositions(pos1, pos2)
  local distance = Vector3.Distance(pos1, pos2)
  return distance
end

function getEorzeaHour()
  local et = os.time() * 1440 / 70
  return math.floor((et % 86400) / 3600)
end

-- Resolve an ENpcResident name directly by DataId
function GetENpcResidentName(dataId)
    local sheet = Excel.GetSheet("ENpcResident")
    if not sheet then return nil, "ENpcResident sheet not available" end

    local row = sheet:GetRow(dataId)
    if not row then return nil, "no row for id "..tostring(dataId) end

    local name = row.Singular or row.Name
    return name, "ENpcResident"
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

function HasPlugin(name)
    for plugin in luanet.each(Svc.PluginInterface.InstalledPlugins) do
        if plugin.InternalName == name and plugin.IsLoaded then
            return true
        end
    end
    return false
end

function IsAddonReady(name)
    local a = Addons.GetAddon(name)
    return a and a.Ready
end

function IsAddonExists(name)
    local a = Addons.GetAddon(name)
    return a and a.Exists
end

function JumpReset()
  lastPos, jumpCount = nil, 0
end

--TerritoryType ID -> localized PlaceName (string or nil)
function PlaceNameByTerritory(id)
    local terr = Excel.GetSheet("TerritoryType"); if not terr then return nil end
    local row  = terr:GetRow(id);                  if not row  then return nil end
    local pn   = row.PlaceName;                    if not pn   then return nil end

    if type(pn) == "string" and #pn > 0 then return pn end

    if type(pn) == "userdata" then
        local ok,val = pcall(function() return pn.Value end)
        if ok and val then
            local ok2,name = pcall(function() return val.Singular or val.Name or val:ToString() end)
            if ok2 and name and name ~= "" then return name end
        end
        local okId,rid = pcall(function() return pn.RowId end)
        if okId and type(rid) == "number" then
            local place = Excel.GetSheet("PlaceName"); if not place then return nil end
            local prow  = place:GetRow(rid);           if not prow  then return nil end
            local ok3,name = pcall(function() return prow.Singular or prow.Name or prow:ToString() end)
            if ok3 and name and name ~= "" then return name end
        end
        return nil
    end

    if type(pn) == "number" then
        local place = Excel.GetSheet("PlaceName"); if not place then return nil end
        local prow  = place:GetRow(pn);            if not prow  then return nil end
        local ok,name = pcall(function() return prow.Singular or prow.Name or prow:ToString() end)
        if ok and name and name ~= "" then return name end
    end

    return nil
end

function RetrieveClassScore()
    classScoreAll = {}
    if not IsAddonExists("WKSScoreList") then
        yield("/callback WKSHud true 18")
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

function RetrieveRelicResearch()
    if Svc.Condition[CharacterCondition.crafting]
       or Svc.Condition[CharacterCondition.gathering]
       or IsAddonExists("WKSMissionInfomation") then
        if IsAddonExists("WKSToolCustomize") then
            yield("/callback WKSToolCustomize true -1")
        end
        return 0
    end
    if not IsAddonExists("WKSToolCustomize") and IsAddonExists("WKSHud") then
        yield("/callback WKSHud true 15")
        sleep(.25)
    end
    if not IsAddonExists("WKSToolCustomize") then
        return 0
    end
        local ToolAddon = Addons.GetAddon("WKSToolCustomize")
        local rows = {4, 41001, 41002, 41003, 41004, 41005, 41006, 41007}
        local checked = 0
        for _, row in ipairs(rows) do
            local currentNode = ToolAddon:GetNode(1, 55, 68, row, 4, 5)
            local requiredNode = ToolAddon:GetNode(1, 55, 68, row, 4, 7)
            if not currentNode or not requiredNode then break end
            local current  = toNumber(currentNode.Text)
            local required = toNumber(requiredNode.Text)
            if current == nil or required == nil then break end
            if required == 0 then return 1 end --Relic complete
            if current < required then return 0 end --Phase not done
            checked = checked + 1
        end
    return (checked > 0) and 2 or 0  -- 2 = phase complete
end

function sleep(seconds)
    yield('/wait ' .. tostring(seconds))
end

function toNumber(s)
    if type(s) ~= "string" then return tonumber(s) end
    s = s:match("^%s*(.-)%s*$")
    s = s:gsub(",", "")
    return tonumber(s)
end

--Worker Funcitons
function ShouldCredit()
    if lunarCredits >= LimitConfig and Svc.Condition[CharacterCondition.normalConditions] and not Player.IsBusy then
        if not IPC.TextAdvance.IsEnabled() then
            yield("/at enable")
            EnabledAutoText = true
        end
        Dalamud.Log("[Cosmic Helper] Lunar credits: " .. tostring(lunarCredits) .. "/" .. LimitConfig .. " Going to Gamba!")
        yield("/echo Lunar credits: " .. tostring(lunarCredits) .. "/" .. LimitConfig .. " Going to Gamba!")
        curPos = Svc.ClientState.LocalPlayer.Position
        if Svc.ClientState.TerritoryType == SinusTerritory then
            if DistanceBetweenPositions(curPos, SinusGateHub) > 75 then
                Dalamud.Log("[Cosmic Helper] Stellar Return")
                yield('/gaction "Duty Action"')
                sleep(5)
            end
            while Svc.Condition[CharacterCondition.betweenAreas] or Svc.Condition[CharacterCondition.casting] do
                sleep(.5)
            end
            IPC.vnavmesh.PathfindAndMoveTo(SinusCreditNpc.position, false)
            Dalamud.Log("[Cosmic Helper] Moving to Gamba bunny")
            sleep(1)
            while IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() do
                sleep(.02)
                curPos = Svc.ClientState.LocalPlayer.Position
                if DistanceBetweenPositions(curPos, SinusCreditNpc.position) < 5 then
                    Dalamud.Log("[Cosmic Helper] Near Gamba bunny. Stopping vnavmesh.")
                    IPC.vnavmesh.Stop()
                end
            end
        elseif Svc.ClientState.TerritoryType == PhaennaTerritory then
            if DistanceBetweenPositions(curPos, PhaennaGateHub) > 75 then
                Dalamud.Log("[Cosmic Helper] Stellar Return")
                yield('/gaction "Duty Action"')
                sleep(5)
            end
            while Svc.Condition[CharacterCondition.betweenAreas] or Svc.Condition[CharacterCondition.casting] do
                sleep(.5)
            end
            IPC.vnavmesh.PathfindAndMoveTo(PhaennaCreditNpc.position, false)
            Dalamud.Log("[Cosmic Helper] Moving to Gamba bunny")
            sleep(1)
            while IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() do
                sleep(.02)
                curPos = Svc.ClientState.LocalPlayer.Position
                if DistanceBetweenPositions(curPos, PhaennaCreditNpc.position) < 5 then
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
            e:Interact()
            sleep(1)
        end
        while not IsAddonReady("SelectString") do
            sleep(1)
        end
        if IsAddonReady("SelectString") then
            yield("/callback SelectString true 0")
            sleep(1)
        end
        while not IsAddonReady("SelectString") do
            sleep(1)
        end
        if IsAddonReady("SelectString") then
            yield("/callback SelectString true 0")
            sleep(1)
        end
        while Svc.Condition[CharacterCondition.occupiedInQuestEvent] do
            sleep(1)
            Dalamud.Log("[Cosmic Helper] Waiting for Gamba to finish")
        end
        if not Svc.Condition[CharacterCondition.occupiedInQuestEvent] then
            job = Player.Job
            if job.IsCrafter then
                aroundSpot = GetRandomSpotAround(spotRadius, minRadius)
                IPC.vnavmesh.PathfindAndMoveTo(aroundSpot, false)
                Dalamud.Log("[Cosmic Helper] Moving to random spot " .. tostring(aroundSpot))
                lastMoveTime = os.time()
                sleep(1)
            end
            while IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() do
                sleep(.2)
                curPos = Svc.ClientState.LocalPlayer.Position
                if DistanceBetweenPositions(curPos, aroundSpot) < 3 then
                    Dalamud.Log("[Cosmic Helper] Near random spot. Stopping vnavmesh")
                    IPC.vnavmesh.Stop()
                    break
                end
            end
            if EnabledAutoText then
                yield("/at disable")
                EnabledAutoText = false
            end
            sleep(1)
            Dalamud.Log("[Cosmic Helper] Start ICE")
            yield("/ice start")
        end
    end
end

function ShouldCycle()
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
    if cycleCount > 0 and cycleCount % 20 == 0 then
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
        sleep(2)
        Dalamud.Log("[Cosmic Helper] Starting ICE")
        yield("/ice start")
        jobCount = jobCount + 1
        cycleCount = 0
    end
end

function ShouldExTime()
    CurJob = Player.Job.Abbreviation
    if Ex4TimeConfig then
        Cur4ExJob = currentexJobs4H()
        if Cur4ExJob and CurJob ~= Cur4ExJob then
            local waitcount = 0
            while IsAddonExists("WKSMissionInfomation") do
                sleep(.1)
                waitcount = waitcount + 1
                if waitcount >= 50 then
                    Dalamud.Log("[Cosmic Helper] Waiting for mission to end to swap to EX+ job.")
                    yield("/echo [Cosmic Helper] Waiting for mission to end to swap to EX+ job.")
                    waitcount = 0
                end
            end
            Dalamud.Log("[Cosmic Helper] Stopping ICE")
            yield("/ice stop")
            sleep(1)
            yield("/echo Current EX+ time: " .. getEorzeaHour() .. " swapping to " .. Cur4ExJob)
            yield("/equipjob " .. Cur4ExJob)
            sleep(1)
            yield("/ice start")
            Dalamud.Log("[Cosmic Helper] Starting ICE")
        end
    elseif Ex2TimeConfig then
        Cur2ExJob = currentexJobs2H()
        if Cur2ExJob and CurJob ~= Cur2ExJob then
            local waitcount = 0
            while IsAddonExists("WKSMissionInfomation") do
                sleep(.1)
                waitcount = waitcount + 1
                if waitcount >= 50 then
                    Dalamud.Log("[Cosmic Helper] Waiting for mission to end to swap to EX+ job.")
                    yield("/echo [Cosmic Helper] Waiting for mission to end to swap to EX+ job.")
                    waitcount = 0
                end
            end
            Dalamud.Log("[Cosmic Helper] Stopping ICE")
            yield("/ice stop")
            sleep(1)
            yield("/echo Current EX+ time: " .. getEorzeaHour() .. " swapping to " .. Cur2ExJob)
            yield("/equipjob " .. Cur2ExJob)
            sleep(1)
            yield("/ice start")
            Dalamud.Log("[Cosmic Helper] Starting ICE")
        end
    end
end

function ShouldJump()
  if not Player.IsMoving then JumpReset(); return end
  local pos = Svc.ClientState.LocalPlayer.Position
  if not lastPos then lastPos = pos; jumpCount = 0; return end
  if DistanceBetweenPositions(pos, lastPos) >= 4 then
    JumpReset(); return
  end
  jumpCount = (jumpCount or 0) + 1
  if jumpCount >= 5 then
    yield("/gaction jump")
    Dalamud.Log("[Cosmic Helper] Position hasn't changed; jumping")
    JumpReset()
  end
end

function ShouldMove()
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
                yield("/echo [Cosmic Helper] Waiting for mission to move.")
                waitcount = 0
            end
        end
        Dalamud.Log("[Cosmic Helper] Stopping ICE")
        yield("/ice stop")
        curPos = Svc.ClientState.LocalPlayer.Position
        if Svc.ClientState.TerritoryType == SinusTerritory then
            if DistanceBetweenPositions(curPos, SinusGateHub) > 75 then
                Dalamud.Log("[Cosmic Helper] Stellar Return")
                yield('/gaction "Duty Action"')
                sleep(5)
            end
        elseif Svc.ClientState.TerritoryType == PhaennaTerritory then
            if DistanceBetweenPositions(curPos, PhaennaGateHub) > 75 then
                Dalamud.Log("[Cosmic Helper] Stellar Return")
                yield('/gaction "Duty Action"')
                sleep(5)
            end
        end
        while Svc.Condition[CharacterCondition.betweenAreas] or Svc.Condition[CharacterCondition.casting] do
            sleep(.5)
        end
        aroundSpot = GetRandomSpotAround(spotRadius, minRadius)
        IPC.vnavmesh.PathfindAndMoveTo(aroundSpot, false)
        Dalamud.Log("[Cosmic Helper] Moving to random spot " .. tostring(aroundSpot))
        sleep(1)
        while IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() do
            sleep(.2)
            curPos = Svc.ClientState.LocalPlayer.Position
            if DistanceBetweenPositions(curPos, aroundSpot) < 3 then
                Dalamud.Log("[Cosmic Helper] Near random spot. Stopping vnavmesh")
                IPC.vnavmesh.Stop()
                break
            end
        end
        yield("/ice start")
        Dalamud.Log("[Cosmic Helper] Starting ICE")
        lastMoveTime = os.time()
        offSet = nil
    end
end

function ShouldRelic()
    if RetrieveRelicResearch() == 0 then
        return
    elseif RetrieveRelicResearch() == 1 then
        yield("/ice stop")
        if IsAddonExists("WKSMission") then
            yield("/callback WKSMission true -1")
        end
        if IsAddonExists("WKSToolCustomize") then
            yield("/callback WKSToolCustomize true -1")
        end
        if jobCount == totalRelicJobs then
            Dalamud.Log("[Cosmic Helper] End of job list reached. Exiting script.")
            yield("/echo [Cosmic Helper] End of job list reached. Exiting script.")
            Run_script = false
            return
        end
        Dalamud.Log("[Cosmic Helper] Swapping to -> " .. RelicJobsConfig[jobCount])
        yield("/echo [Cosmic Helper] Swapping to -> " .. RelicJobsConfig[jobCount])
        yield("/equipjob " .. RelicJobsConfig[jobCount])
        sleep(1)
        jobCount = jobCount + 1
        if RetrieveRelicResearch() == 0 then
            Dalamud.Log("[Cosmic Helper] Starting ICE")
            yield("/ice start")
        end
        return
    elseif RetrieveRelicResearch() == 2 then
        if not IPC.TextAdvance.IsEnabled() then
            yield("/at enable")
            EnabledAutoText = true
        end
        Dalamud.Log("[Cosmic Helper] Research level met!")
        yield("/echo [Cosmic Helper] Research level met!")
        local waitcount = 0
        while IsAddonReady("WKSMissionInfomation") do
            sleep(.1)
            waitcount = waitcount + 1
            Dalamud.Log("[Cosmic Helper] Waiting for mission to move")
            if waitcount >= 20 then
                yield("/echo [Cosmic Helper] Waiting for mission to move.")
                waitcount = 0
            end
        end
        Dalamud.Log("[Cosmic Helper] Stopping ICE")
        yield("/ice stop")
        curPos = Svc.ClientState.LocalPlayer.Position
        if Svc.ClientState.TerritoryType == SinusTerritory then
            if DistanceBetweenPositions(curPos, SinusGateHub) > 75 then
                Dalamud.Log("[Cosmic Helper] Stellar Return")
                yield('/gaction "Duty Action"')
                sleep(5)
            end
            while Svc.Condition[CharacterCondition.betweenAreas] or Svc.Condition[CharacterCondition.casting] do
                sleep(.5)
            end
            IPC.vnavmesh.PathfindAndMoveTo(SinusResearchNpc.position, false)
            Dalamud.Log("[Cosmic Helper] Moving to Research bunny")
            sleep(1)
            while IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() do
                sleep(.02)
                curPos = Svc.ClientState.LocalPlayer.Position
                if DistanceBetweenPositions(curPos, SinusResearchNpc.position) < 5 then
                    Dalamud.Log("[Cosmic Helper] Near Research bunny. Stopping vnavmesh.")
                    IPC.vnavmesh.Stop()
                    break
                end
            end
        elseif Svc.ClientState.TerritoryType == PhaennaTerritory then
            if DistanceBetweenPositions(curPos, PhaennaGateHub) > 75 then
                Dalamud.Log("[Cosmic Helper] Stellar Return")
                yield('/gaction "Duty Action"')
                sleep(5)
            end
            while Svc.Condition[CharacterCondition.betweenAreas] or Svc.Condition[CharacterCondition.casting] do
                sleep(.5)
            end
            IPC.vnavmesh.PathfindAndMoveTo(PhaennaResearchNpc.position, false)
            Dalamud.Log("[Cosmic Helper] Moving to Research bunny")
            sleep(1)
            while IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() do
                sleep(.02)
                curPos = Svc.ClientState.LocalPlayer.Position
                if DistanceBetweenPositions(curPos, PhaennaResearchNpc.position) < 5 then
                    Dalamud.Log("[Cosmic Helper] Near Research bunny. Stopping vnavmesh.")
                    IPC.vnavmesh.Stop()
                    break
                end
            end
        end
        CurJob = Player.Job
        sleep(.1)
        if AltJobConfig and CurJob.Id ~= 8 then
            yield("/equipjob " .. Jobs[8].abbr)
        elseif AltJobConfig and CurJob.Id == 8 then
            yield("/equipjob " .. Jobs[9].abbr)
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
            yield("/callback SelectString true 0")
            sleep(1)
        end
        while not IsAddonReady("SelectIconString") do
            sleep(1)
        end
        if IsAddonReady("SelectIconString") then
            StringId = CurJob.Id - 8
            yield("/callback SelectIconString true " .. StringId)
        end
        while not IsAddonReady("SelectYesno") do
            sleep(1)
        end
        if IsAddonReady("SelectYesno") then
            yield("/callback SelectYesno true 0")
        end
        while IsAddonExists("SelectYesno") do
            sleep(1)
        end
        if AltJobConfig then yield("/equipjob " .. CurJob.Name) end
        if CurJob.IsCrafter then
            aroundSpot = GetRandomSpotAround(spotRadius, minRadius)
            IPC.vnavmesh.PathfindAndMoveTo(aroundSpot, false)
            Dalamud.Log("[Cosmic Helper] Moving to random spot " .. tostring(aroundSpot))
            lastMoveTime = os.time()
            sleep(2)
            while IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() do
                sleep(.2)
                curPos = Svc.ClientState.LocalPlayer.Position
                if DistanceBetweenPositions(curPos, aroundSpot) < 3 then
                    Dalamud.Log("[Cosmic Helper] Near random spot. Stopping vnavmesh")
                    IPC.vnavmesh.Stop()
                    break
                end
            end
        end
        if EnabledAutoText then
            yield("/at disable")
            EnabledAutoText = false
        end
        if RetrieveRelicResearch() == 0 then
            Dalamud.Log("[Cosmic Helper] Starting ICE")
            yield("/ice start")
        end
    end
end

function ShouldReport()
    curJob = Player.Job
    while IsAddonExists("WKSMissionInfomation") and curJob.IsCrafter do
        while IsAddonExists("WKSRecipeNotebook") and Svc.Condition[CharacterCondition.normalConditions] do
            sleep(.1)
            reportCount = reportCount + 1
            if reportCount >= 50 then
                yield("/callback WKSMissionInfomation true 11")
                Dalamud.Log("[Cosmic Helper] Reporting failed mission.")
                yield("/echo [Cosmic Helper] Reporting failed mission.")
                reportCount = 0
            end
        end
        reportCount = 0
        sleep(.1)
    end
    if Ex4TimeConfig or Ex2TimeConfig then
        ShouldExTime()
    end
end

function ShouldRetainer()
    if IPC.AutoRetainer.AreAnyRetainersAvailableForCurrentChara() then
        local waitcount = 0
        while IsAddonExists("WKSMissionInfomation") do
            sleep(.2)
            waitcount = waitcount + 1
            Dalamud.Log("[Cosmic Helper] Waiting for mission to process retainers")
            if waitcount >= 15 then
                yield("/echo [Cosmic Helper] Waiting for mission to process retainers")
                waitcount = 0
            end
        end
        Dalamud.Log("[Cosmic Helper] Stopping ICE")
        yield("/ice stop")
        if SelectedBell.zone == "Moongate Hub (Sinus)" then
            curPos = Svc.ClientState.LocalPlayer.Position
            if DistanceBetweenPositions(curPos, SinusGateHub) > 75 then
                Dalamud.Log("[Cosmic Helper] Stellar Return")
                yield('/gaction "Duty Action"')
                sleep(5)
            end
        elseif SelectedBell.zone == "Glassblowers' Beacon (Pharnna)" then
            curPos = Svc.ClientState.LocalPlayer.Position
            if DistanceBetweenPositions(curPos, PhaennaGateHub) > 75 then
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
        while IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() do
                sleep(.2)
            curPos = Svc.ClientState.LocalPlayer.Position
            if DistanceBetweenPositions(curPos, SelectedBell.position) < 3 then
                Dalamud.Log("[Cosmic Helper] Close enough to summoning bell")
                IPC.vnavmesh.Stop()
                break
            end
        end
        while Svc.Targets.Target == nil or Svc.Targets.Target.Name:GetText() ~= "Summoning Bell" do
            Dalamud.Log("[Cosmic Helper] Targeting summoning bell")
            yield("/target Summoning Bell")
            sleep(1)
        end
        if not Svc.Condition[CharacterCondition.occupiedSummoningBell] then
            Dalamud.Log("[Cosmic Helper] Interacting with summoning bell")
            while not IsAddonReady("RetainerList") do
                yield("/interact")
                sleep(1)
            end
            if IsAddonReady("RetainerList") then
                Dalamud.Log("[Cosmic Helper] Enable AutoRetainer")
                yield("/ays e")
                sleep(1)
            end
        end
        while IPC.AutoRetainer.IsBusy() do
            sleep(1)
        end
        sleep(2)
        if IsAddonExists("RetainerList") then
            Dalamud.Log("[Cosmic Helper] Closing RetainerList window")
            yield("/callback RetainerList true -1")
            sleep(1)
        end
        if extraRetainerDelay then
            sleep(5) -- Sleep for script
            while Svc.Condition[CharacterCondition.occupiedSummoningBell] do
                sleep(.1)
            end
            sleep(2)
            while Svc.Condition[CharacterCondition.occupiedSummoningBell] do
                sleep(.1)
            end
        end
        if Svc.ClientState.TerritoryType == SinusTerritory then
            aroundSpot = GetRandomSpotAround(spotRadius, minRadius)
            IPC.vnavmesh.PathfindAndMoveTo(aroundSpot, false)
            Dalamud.Log("[Cosmic Helper] Moving to random spot " .. tostring(aroundSpot))
            sleep(1)
            while IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() do
                sleep(.2)
                curPos = Svc.ClientState.LocalPlayer.Position
                if DistanceBetweenPositions(curPos, aroundSpot) < 3 then
                    Dalamud.Log("[Cosmic Helper] Near random spot. Stopping vnavmesh")
                    IPC.vnavmesh.Stop()
                    break
                end
            end
            sleep(1)
            Dalamud.Log("[Cosmic Helper] Start ICE")
            yield("/ice start")
            return
        elseif Svc.ClientState.TerritoryType == PhaennaTerritory then
            aroundSpot = GetRandomSpotAround(spotRadius, minRadius)
            IPC.vnavmesh.PathfindAndMoveTo(aroundSpot, false)
            Dalamud.Log("[Cosmic Helper] Moving to random spot " .. tostring(aroundSpot))
            sleep(1)
            while IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() do
                sleep(.2)
                curPos = Svc.ClientState.LocalPlayer.Position
                if DistanceBetweenPositions(curPos, aroundSpot) < 3 then
                    Dalamud.Log("[Cosmic Helper] Near random spot. Stopping vnavmesh")
                    IPC.vnavmesh.Stop()
                    break
                end
            end
            sleep(1)
            Dalamud.Log("[Cosmic Helper] Start ICE")
            yield("/ice start")
            return
        else
            Dalamud.Log("[Cosmic Helper] Teleport to Cosmic")
            yield("/li Cosmic")
            sleep(3)
        end
        local cosmicCount = 0
        while not Svc.ClientState.TerritoryType ~= SinusTerritory
            and Svc.ClientState.TerritoryType ~= PhaennaTerritory do
            if not IPC.Lifestream.IsBusy() then
                    cosmicCount = cosmicCount + 1
                    if cosmicCount >=  20 then
                        Dalamud.Log("[Cosmic Helper] Failed to teleport to Cosmic. Trying agian.")
                        yield("/echo [Cosmic Helper] Failed to teleport to Cosmic. Trying agian.")
                        yield("/li Cosmic")
                        cosmicCount = 0
                    end
            else
                cosmicCount = 0
            end
            sleep(.5)
        end
        if Svc.ClientState.TerritoryType == SinusTerritory
            or Svc.ClientState.TerritoryType == PhaennaTerritory then
            while Svc.Condition[CharacterCondition.betweenAreas]
               or Svc.Condition[CharacterCondition.casting]
               or Svc.Condition[CharacterCondition.occupied33] do
                sleep(.5)
            end
            Dalamud.Log("[Cosmic Helper] Stellar Return")
            yield('/gaction "Duty Action"')
            sleep(5)
            while Svc.Condition[CharacterCondition.betweenAreas] or Svc.Condition[CharacterCondition.casting] do
                sleep(.5)
            end
            sleep(1)
            Dalamud.Log("[Cosmic Helper] Start ICE")
            yield("/ice start")
        end
    end
end

--[[
********************************************************************************
*                                Scritp Settings                               *
********************************************************************************
]]

-- Config veriables
JumpConfig      = Config.Get("Jump if stuck")
JobsConfig      = Config.Get("Jobs")
LimitConfig     = Config.Get("Lunar Credits Limit")
FailedConfig    = Config.Get("Report Failed Missions")
Ex4TimeConfig   = Config.Get("EX+ 4hr Timed Missions")
Ex2TimeConfig   = Config.Get("EX+ 2hr Timed Missions")
MoveConfig      = Config.Get("Delay Moving Spots")
RetainerConfig  = Config.Get("Process Retainers Ventures")
ResearchConfig  = Config.Get("Research Turnin")
AltJobConfig    = Config.Get("Use Alt Job")
RelicJobsConfig = Config.Get("Relic Jobs")

-- Veriables
Run_script        = true
lastPos           = nil
totalJobs         = JobsConfig.Count
totalRelicJobs    = RelicJobsConfig.Count
reportCount       = 0
cycleCount        = 0
jobCount          = 0
lunarCredits      = 0
lunarCycleCount   = 0
lastSpotIndex     = nil
lastMoveTime      = nil
offSet            = nil
minRadius         = .5
SelectedBell      = nil
ClassScoreAll     = {}

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
    betweenAreas                       = 45,
    jumping48                          = 48, -- moving
    occupiedSummoningBell              = 50,
    mounting57                         = 57, -- moving
    unknown85                          = 85, -- Part of gathering
}

--Read Excel sheets for jobs
local sheet = Excel.GetSheet("ClassJob")
assert(sheet, "ClassJob sheet not found")
Jobs = {}
for id = 8, 18 do
    local row = sheet:GetRow(id)
    if row then
        local name = row.Name or row["Name"]
        local abbr = row.Abbreviation or row["Abbreviation"]
        if name and abbr then
            Jobs[id] = { name = name, abbr = abbr }
        else
            print(("ClassJob %d: missing Name/Abbreviation"):format(id))
        end
    else
        print(("ClassJob %d: row not found"):format(id))
    end
end

--[[Job Reference
Jobs[id].name or Jobs[id].abbr
8  - CRP
9  - BSM
10 - ARM
11 - GSM
12 - LTW
13 - WVR
14 - ALC
15 - CUL
16 - MIN
17 - BTN
18 - FSH
]]

--Position Information
SinusGateHub = Vector3(0,0,0)
PhaennaGateHub = Vector3(340.721, 52.864, -418.183)

SummoningBell = {
    {zone = "Inn", aethernet = "Inn", position = nil},
    {zone = "Glassblowers' Beacon (Pharnna)", aethernet = nil, position = Vector3(358.380, 52.625, -409.429)},
    {zone = "Moongate Hub (Sinus)", aethernet = nil, position = Vector3(10.531, 1.612, 17.287)},
    {zone = "Gridania", aethernet = "Leatherworkers' guild", position = Vector3(171.008, 15.488, -101.488)},
    {zone = "Limsa Lominsa", aethernet = "Limsa Lominsa", position = Vector3(-123.888, 17.990, 21.469)},
    {zone = "Ul'Dah", aethernet = "Sapphire Avenue Exchange", position = Vector3(148.913, 3.983, -44.205)},
}

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
SinusCreditNpc = {name = GetENpcResidentName(1052612), position = Vector3(18.845, 2.243, -18.906)}
SinusResearchNpc = {name = GetENpcResidentName(1052605), position = Vector3(-18.906, 2.151, 18.845)}
PhaennaCreditNpc = {name = GetENpcResidentName(1052642), position = Vector3(358.816, 53.193, -438.865)}
PhaennaResearchNpc = {name = GetENpcResidentName(1052629), position = Vector3(321.218, 53.193, -401.236)}

--Timed mission jobs
exJobs4H = {
  [0]  = {Jobs[10].abbr},   -- ARM 00:00–03:59
  [4]  = {Jobs[11].abbr},   -- GSM 04:00–07:59
  [8]  = {Jobs[12].abbr},   -- LTW 08:00–11:59
  [12] = {Jobs[13].abbr},   -- WVR 12:00–15:59
  [16] = {Jobs[8].abbr},    -- CRP 16:00–19:59
  [20] = {Jobs[9].abbr},    -- BSM 20:00–23:59
}

exJobs2H = {
  [0]  = {Jobs[12].abbr},   -- LTW 00:00-02:59
  [4]  = {Jobs[13].abbr},   -- WVR 04:00-05:59
  [8]  = {Jobs[14].abbr},   -- ALC 08:00-09:59
  [12] = {Jobs[15].abbr},   -- CUL 12:00-13:59
  [16] = {Jobs[10].abbr},   -- ARM 16:00-17:59
  [20] = {Jobs[11].abbr},   -- GSM 20:00-21:59
}

--[[
********************************************************************************
*                            Start of script loop                              *
********************************************************************************
]]


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
if ResearchConfig and not HasPlugin("TextAdvance") then
    yield("/echo [Cosmic Helper] Research turnin requires TextAdvance plugin. Script will continue without turning in research for relics.")
    ResearchConfig = 0
end
if RetainerConfig ~= "N/A" and not HasPlugin("AutoRetainer") then
    yield("/echo [Cosmic Helper] Retainer processing requires AutoRetainer plugin. Script will continue without processing retainers.")
    RetainerConfig = "N/A"
end
local job = Player.Job
if not job.IsCrafter and MoveConfig > 0 then
    yield("/echo [Cosmic Helper] Only crafters should move. Script will continue.")
    MoveConfig = 0
end
if RelicJobsConfig.Count > 0 and not HasPlugin("SimpleTweaksPlugin") then
    yield("/echo [Cosmic Helper] Cycling jobs requires SimpleTweaks plugin. Script will continue without changing jobs.")
    RelicJobsConfig = nil
end
if Ex4TimeConfig and Ex2TimeConfig then
    yield("/echo [Cosmic Helper] Having both EX+ timed missions enabled is not supported. The script will continue with only doing the EX+ 4HR missions.")
    Ex2TimeConfig = false
end

--Enable plugin options
yield("/tweaks enable EquipJobCommand true")

--Main Loop
while Run_script do
    if IsAddonExists("WKSHud") then
        lunarCredits = Addons.GetAddon("WKSHud"):GetNode(1, 15, 17, 3).Text:gsub("[^%d]", "")
        lunarCredits = tonumber(lunarCredits)
    end
    if JumpConfig then
        ShouldJump()
    end
    if ResearchConfig then
        ShouldRelic()
    end
    if RetainerConfig ~= "N/A" then
        ShouldRetainer()
    end
    if LimitConfig > 0 then
        ShouldCredit()
    end
    if FailedConfig then
        ShouldReport()
    end
    if Ex2TimeConfig or Ex4TimeConfig then
        ShouldExTime()
    end
    if MoveConfig > 0 then
        ShouldMove()
    end
    if totalJobs > 0 then
        ShouldCycle()
    end
    sleep(loopDelay)
end
