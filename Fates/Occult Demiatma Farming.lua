--[=====[
[[SND Metadata]]
author: 'pot0to || Updated by: baanderson40'
version: 2.0.1
description: Occult Demiatma Farming - Companion script for Fate Farming
plugin_dependencies:
- Lifestream
- vnavmesh
- TextAdvance
configs:
  FateMacro:
    description: Name of the primary fate macro script.
    default: ""
  NumberToFarm:
    description: How many of each atma to farm?
    default: 3

[[End Metadata]]
--]=====]

--[[

********************************************************************************
*                           Occult Demiatma Farming                            *
*                                Version 2.0.1                                 *
********************************************************************************

Demiatma Farming script meant to be used with `Fate Farming.lua`. This will go down
the list of Demiatma Farming zones and farm fates until you have 18 of the required
atmas in your inventory, then teleport to the next zone and restart the fate
farming script.

Created by: pot0to (https://ko-fi.com/pot0to)
Updated by: baanderson40 (https://ko-fi.com/baanderson40)

    -> 2.0.1    Updated CharacterCondition
    -> 2.0.0    Updated for Latest SnD
    -> 1.0.1    Added check for death and unexpected combat
                First release

--#region Settings

--[[
********************************************************************************
*                                   Settings                                   *
********************************************************************************
]]

FateMacro = Config.Get("FateMacro")
NumberToFarm = Config.Get("NumberToFarm")

--#endregion Settings

------------------------------------------------------------------------------------------------------------------------------------------------------

--[[
**************************************************************
*  Code: Don't touch this unless you know what you're doing  *
**************************************************************
]]
Atmas =
{
    { zoneName = "Urqopacha", zoneId = 1187, itemName="Azurite Demiatma", itemId=47744 },
    { zoneName = "Kozama'uka", zoneId = 1188, itemName="Verdigris Demiatma", itemId=47745 },
    { zoneName = "Yak T'el", zoneId = 1189, itemName="Malachite Demiatma", itemId=47746 },
    { zoneName = "Shaaloani", zoneId = 1190, itemName="Realgar Demiatma", itemId=47747 },
    { zoneName = "Heritage Found", zoneId = 1191, itemName="Caput Mortuum Demiatma", itemId=47748 },
    { zoneName = "Living Memory", zoneId = 1192, itemName="Orpiment Demiatma", itemId=47749 }
}

CharacterCondition = {
    casting=27,
    betweenAreas=45
}

function OnChatMessage()
    local message = TriggerData.message
    local patternToMatch = "%[Fate%] Loop Ended !!"

    if message and message:find(patternToMatch) then
        Dalamud.Log("[Demiatma Farm] OnChatMessage triggered")
        FateMacroRunning = false
        Dalamud.Log("[Demiatma Farm] FateMacro has stopped")
    end
end

function GetAetheryteName(ZoneID)
    local territoryData = Excel.GetRow("TerritoryType", ZoneID)

    if territoryData and territoryData.Aetheryte and territoryData.Aetheryte.PlaceName then
        return tostring(territoryData.Aetheryte.PlaceName.Name)
    end
end

function GetNextAtmaTable()
    for _, atmaTable in pairs(Atmas) do
        if Inventory.GetItemCount(atmaTable.itemId) < NumberToFarm then
            return atmaTable
        end
    end
end

function TeleportTo(aetheryteName)
    yield("/tp "..aetheryteName)
    yield("/wait 1") -- wait for casting to begin
    while Svc.Condition[CharacterCondition.casting] do
        Dalamud.Log("[Demiatma Farm] Casting teleport...")
        yield("/wait 1")
    end
    yield("/wait 1") -- wait for that microsecond in between the cast finishing and the transition beginning
    while Svc.Condition[CharacterCondition.betweenAreas] do
        Dalamud.Log("[Demiatma Farm] Teleporting...")
        yield("/wait 1")
    end
    yield("/wait 1")
end

yield("/at y")
NextAtmaTable = GetNextAtmaTable()
while NextAtmaTable ~= nil do
    if not Player.IsBusy and not FateMacroRunning then
        Dalamud.Log("[Demiatma Farm] Starting FateMacro")
        yield("/snd run " .. FateMacro)
        FateMacroRunning = true

        while FateMacroRunning do
            yield("/wait 3")
        end

        if Inventory.GetItemCount(NextAtmaTable.itemId) >= NumberToFarm then
            NextAtmaTable = GetNextAtmaTable()
        elseif not Svc.ClientState.LocalPlayer.TerritoryType == (NextAtmaTable.zoneId) then
            TeleportTo(GetAetheryteName(NextAtmaTable.zoneId)[0])
        else
            yield("/snd run "..FateMacro)
        end
    end
    yield("/wait 1")
end
