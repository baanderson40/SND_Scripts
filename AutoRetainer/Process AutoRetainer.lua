--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.0.0
description: Teleport to Limsa and process retainers when they are ready.

[[End Metadata]]
--]=====]
import("System.Numerics")

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

SummoningBell = {
    {zone = "Limsa Lominsa", aethernet = "Limsa Lominsa", position = Vector3(-123.888, 17.990, 21.469)},
    }

function IsAddonExists(name)
    local a = Addons.GetAddon(name)
    return a and a.Exists
end

function sleep(seconds)
    yield('/wait ' .. tostring(seconds))
end

function DistanceBetweenPositions(pos1, pos2)
  local distance = Vector3.Distance(pos1, pos2)
  return distance
end

function ShouldRetainer()
    if IPC.AutoRetainer.AreAnyRetainersAvailableForCurrentChara() then
        local waitcount = 0
        repeat
            sleep(1)
            waitcount = waitcount + 1
            if waitcount >= 10 then
                Dalamud.Log("[AR processing] Waiting for Gathering to finish to process retainers.")
                yield("/echo [AR processing] Waiting for Gathering to finish to process retainers.")
                waitcount = 5
            end
        until not Svc.Condition[CharacterCondition.gathering]
        sleep(2)
        IPC.Lifestream.ExecuteCommand(SummoningBell[1].aethernet)
        Dalamud.Log("[AR processing] Teleporting to " .. tostring(SummoningBell[1].aethernet))
        sleep(2)
        while Svc.Condition[CharacterCondition.betweenAreas]
            or Svc.Condition[CharacterCondition.casting]
            or Svc.Condition[CharacterCondition.betweenAreasForDuty]
            or IPC.Lifestream.IsBusy() do
            sleep(.5)
        end
        sleep(1)
        if SummoningBell[1].position ~= nil then
            IPC.vnavmesh.PathfindAndMoveTo(SummoningBell[1].position, false)
            Dalamud.Log("[AR processing] Moving to summoning bell")
            sleep(2)
        end
        while IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() do
                sleep(.2)
            curPos = Svc.ClientState.LocalPlayer.Position
            if DistanceBetweenPositions(curPos, SummoningBell[1].position) < 3 then
                Dalamud.Log("[AR processing] Close enough to summoning bell")
                IPC.vnavmesh.Stop()
                break
            end
        end
        while Svc.Targets.Target == nil or Svc.Targets.Target.Name:GetText() ~= "Summoning Bell" do
            Dalamud.Log("[AR processing] Targeting summoning bell")
            yield("/target Summoning Bell")
            sleep(1)
        end
        if not Svc.Condition[CharacterCondition.occupiedSummoningBell] then
            Dalamud.Log("[AR processing] Interacting with summoning bell")
            while not IsAddonExists("RetainerList") do
                yield("/interact")
                sleep(1)
            end
            if IsAddonExists("RetainerList") then
                Dalamud.Log("[AR processing] Enable AutoRetainer")
                yield("/ays e")
                sleep(1)
            end
        end
        while IPC.AutoRetainer.IsBusy() do
            sleep(1)
        end
        sleep(2)
        if IsAddonExists("RetainerList") then
            Dalamud.Log("[AR processing] Closing RetainerList window")
            yield("/callback RetainerList true -1")
            sleep(1)
        end
    end
end

while true do
    ShouldRetainer()
    sleep(1)
end
