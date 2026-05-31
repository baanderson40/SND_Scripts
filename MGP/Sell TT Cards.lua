--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.1.0
description: |
  Support via https://ko-fi.com/baanderson40
  Bare bones script to sell Triple Triad cards.
  Requires the card trade-in window to already be open.

[[End Metadata]]
--]=====]

--[[
********************************************************************************
*                                  Changelog                                   *
********************************************************************************
  -> 1.1.0 Simplified flow to start from open card trade-in window
  -> 1.0.1 Resolved crashing after last card sell  
  -> 1.0.0 Initial Release

]]

local function getAddon(name)
    local addon = Addons.GetAddon(name)
    if addon and addon.Ready then
        return addon
    end

    return nil
end

local function waitForAddon(name, attempts, delay)
    attempts = tonumber(attempts) or 20
    delay = tonumber(delay) or 0.25

    for _ = 1, attempts do
        local addon = getAddon(name)
        if addon then
            return addon
        end
        yield("/wait " .. tostring(delay))
    end

    return nil
end

local MAX_CONFIRM_RETRIES = 3
local POST_CONFIRM_DELAY = 0.35

--Start echo for user.
yield("/echo Starting TT card sell script.")
Dalamud.LogDebug("Starting TT card sell script.")
Dalamud.Log("[TT Sale] Waiting for TripleTriadCoinExchange to already be open")

if not waitForAddon("TripleTriadCoinExchange", 4, 0.25) then
    yield("/echo Open the Triple Triad card trade-in window first. Stopping script")
    Dalamud.Log("[TT Sale] TripleTriadCoinExchange addon is not open")
    return
end

--Cycle through cards to sell
Dalamud.Log("[TT Sale] Starting to sell cards")

local function noCardsForSale()
    local addon = getAddon("TripleTriadCoinExchange")
    if not addon then
        return true
    end

    local node = addon:GetNode(1,11)
    if not node then
        return true
    end

    return node.IsVisible == true
end

local function readQty()
    local addon = getAddon("TripleTriadCoinExchange")
    if not addon then
        return 0
    end

    local node = addon:GetNode(1,10,5,6)
    if not node then
        return 0
    end

    local txt = node.Text or ""
    return tonumber(txt:match("%d+")) or 0
end

while not noCardsForSale() do
    local qty = readQty()
    Dalamud.Log("[TT Sale] Cards to sell: " .. qty)

    if qty <= 0 then
        Dalamud.Log("[TT Sale] Quantity read as 0; ending sell loop")
        break
    end

    local confirmed = false

    for attempt = 1, MAX_CONFIRM_RETRIES do
        yield("/callback TripleTriadCoinExchange true 0")

        if waitForAddon("ShopCardDialog", 20, 0.1) then
            yield("/callback ShopCardDialog true 0 " .. qty)
            yield("/wait " .. tostring(POST_CONFIRM_DELAY))
            waitForAddon("TripleTriadCoinExchange", 10, 0.1)
            confirmed = true
            break
        end

        Dalamud.Log("[TT Sale] ShopCardDialog did not open on attempt " .. tostring(attempt) .. "; retrying")
        waitForAddon("TripleTriadCoinExchange", 10, 0.1)
        yield("/wait .2")
        qty = readQty()
        if qty <= 0 or noCardsForSale() then
            confirmed = true
            break
        end
    end

    if not confirmed then
        yield("/echo Sell confirmation did not open after retries. Leaving window open")
        Dalamud.Log("[TT Sale] ShopCardDialog addon did not become ready after retries")
        return
    end
end

--Close card sells window
Dalamud.Log("[TT Sale] Closing card sell window")
if getAddon("TripleTriadCoinExchange") then
    yield("/callback TripleTriadCoinExchange true -1")
end

--Stop script echo
yield("/echo All TT cards sold. Stoping script")
