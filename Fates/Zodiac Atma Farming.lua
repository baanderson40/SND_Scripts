--[=====[
[[SND Metadata]]
author: 'pot0to || Updated by: baanderson40'
version: 2.0.1
description: Zodiac Atma Farming - Companion script for Fate Farming
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
    default: 1

[[End Metadata]]
--]=====]

--[[

********************************************************************************
*                             Zodiac Atma Farming                              *
*                                Version 2.0.1                                 *
********************************************************************************

Atma farming script meant to be used with `Fate Farming.lua`. This will go down
the list of atma farming zones and farm fates until you have 12 of the required
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
    {zoneName = "Middle La Noscea", zoneId = 134, itemName = "Atma of the Ram", itemId = 7856},
    {zoneName = "Lower La Noscea", zoneId = 135, itemName = "Atma of the Fish", itemId = 7859},
    {zoneName = "Western La Noscea", zoneId = 138, itemName = "Atma of the Crab", itemId = 7862},
    {zoneName = "Upper La Noscea", zoneId = 139, itemName = "Atma of the Water-bearer", itemId = 7853},
    {zoneName = "Western Thanalan", zoneId = 140, itemName = "Atma of the Twins", itemId = 7857},
    {zoneName = "Central Thanalan", zoneId = 141, itemName = "Atma of the Scales", itemId = 7861},
    {zoneName = "Eastern Thanalan", zoneId = 145, itemName = "Atma of the Bull", itemId = 7855},
    {zoneName = "Southern Thanalan", zoneId = 146, itemName = "Atma of the Scorpion", itemId = 7852, flying=false},
    {zoneName = "Central Shroud", zoneId = 148, itemName = "Atma of the Maiden", itemId = 7851},
    {zoneName = "East Shroud", zoneId = 152, itemName = "Atma of the Goat", itemId = 7854},
    {zoneName = "North Shroud", zoneId = 154, itemName = "Atma of the Archer", itemId = 7860},
    {zoneName = "Outer La Noscea", zoneId = 180, itemName = "Atma of the Lion", itemId = 7858, flying=false}
}

CharacterCondition = {
    casting=27,
    betweenAreas=45
}

function OnChatMessage()
    local message = TriggerData.message
    local patternToMatch = "%[Fate%] Loop Ended !!"

    if message and message:find(patternToMatch) then
        Dalamud.Log("[Atma Farm] OnChatMessage triggered")
        FateMacroRunning = false
        Dalamud.Log("[Atma Farm] FateMacro has stopped")
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
        Dalamud.Log("[Atma Farm] Casting teleport...")
        yield("/wait 1")
    end
    yield("/wait 1") -- wait for that microsecond in between the cast finishing and the transition beginning
    while Svc.Condition[CharacterCondition.betweenAreas] do
        Dalamud.Log("[Atma Farm] Teleporting...")
        yield("/wait 1")
    end
    yield("/wait 1")
end

yield("/at y")
NextAtmaTable = GetNextAtmaTable()
while NextAtmaTable ~= nil do
    if not Player.IsBusy and not FateMacroRunning then
        Dalamud.Log("[Atma Farm] Starting FateMacro")
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
