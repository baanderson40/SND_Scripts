--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.0.1
description: |
  Support via https://ko-fi.com/baanderson40
  Bare bones script to sell Triple Triad cards to Trader NPC. 
  Must be standing within targeting range of the NPC.

[[End Metadata]]
--]=====]

--[[
********************************************************************************
*                                  Changelog                                   *
********************************************************************************
  -> 1.0.1 Resolved crashing after last card sell  
  -> 1.0.0 Initial Release

]]

--Trader NPC Name
NpcName = "Triple Triad Trader"

--Start echo for user.
yield("/echo Starting TT card sell script.")
Dalamud.LogDebug("Starting TT card sell script.")

--Target NPC by name
Dalamud.Log("[TT Sale] Attempting to target NPC")
local e = Entity.GetEntityByName(NpcName)
if e then
    e:SetAsTarget()
    Dalamud.Log("[TT Sale] Target set -> " .. NpcName)
else
    Dalamud.Log("[TT Sale] NPC not found yet: " .. tostring(NpcName))
end
yield("/wait .35")

--Interact with NPC to open menu
Dalamud.Log("[TT Sale] Interacting with " .. Entity.Target.Name)
Entity.Target:Interact()
yield("/wait .35")

--Handle card option menu
Dalamud.Log("[TT Sale] Handling Card option menu")
yield("/callback SelectIconString true 1")
yield("/wait 1")

--Cycle through cards to sell
Dalamud.Log("[TT Sale] Starting to sell cards")

local function noCardsForSale()
  local vis = Addons.GetAddon("TripleTriadCoinExchange"):GetNode(1,11).IsVisible
return vis
end

local function readQty()
  local txt = (Addons.GetAddon("TripleTriadCoinExchange"):GetNode(1,10,5,6).Text or "")
  return tonumber(txt:match("%d+")) or 0
end

while not noCardsForSale() do
  local qty = readQty()
  Dalamud.Log("[TT Sale] Cards to sell: " .. qty)
  yield("/callback TripleTriadCoinExchange true 0")
  yield("/wait .35")
  yield("/callback ShopCardDialog true 0 " .. qty)
  yield("/wait .25")
end

--Close card sells window
Dalamud.Log("[TT Sale] Closing card sell window")
yield("/callback TripleTriadCoinExchange true -1")

--Stop script echo
yield("/echo All TT cards sold. Stoping script")
