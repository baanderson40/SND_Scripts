--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.0.0
description: | 
  Support via https://ko-fi.com/baanderson40
  Trade Omega 5 Normal (O5N) sigmascape parts in for GC seals.

  Dependencies:
       AutoRetainer - Grand Company Delivery | https://love.puni.sh/ment.json
       Lifestream - teleport to and from Rhalgr's Reach | https://raw.githubusercontent.com/NightmareXIV/MyDalamudPlugins/main/pluginmaster.json
       Pandora's Box - Auto-select Turn-Ins; Automatically Confirm | https://love.puni.sh/ment.json
       SomethingNeedDoing - given
plugin_dependencies:
- AutoRetainer
- Lifestream
- PandorasBox
- SomethingNeedDoing

[[End Metadata]]

********************************************************************************
*                                  Changelog                                   *
********************************************************************************
    1.0.0 -> Initial release


--------------------------------------------------------------------------------
--]=====]

--[[
********************************************************************************
*           Code: Don't touch this unless you know what you're doing           *
********************************************************************************
]]

-- Imports
import("System.Numerics")


-- Constant variables
local rhalgr_reach = 635
local vendor_name = "Gelfradus"
local vendor_pos = Vector3(125.993,0.652,40.001)


-- Character Conditions
CharacterCondition = {
    mounted = 4,
    betweenAreas = 45,
}


-- Item Table
local shop_head = {
    { item_name = "Carborundum Circle of Fending",     sub_menu = 0, item_index = 0 },
    { item_name = "Carborundum Helm of Maiming",       sub_menu = 0, item_index = 1 },
    { item_name = "Carborundum Bandana of Striking",   sub_menu = 0, item_index = 2 },
    { item_name = "Carborundum Bandana of Scouting",   sub_menu = 1, item_index = 0 },
    { item_name = "Carborundum Helm of Aiming",        sub_menu = 1, item_index = 1 },
    { item_name = "Carborundum Hat of Casting",        sub_menu = 2, item_index = 0 },
    { item_name = "Carborundum Circlet of Healing",    sub_menu = 2, item_index = 1 },
}
local shop_body = {
    { item_name = "Carborundum Armor of Fending",      sub_menu = 0, item_index = 3 },
    { item_name = "Carborundum Armor of Maiming",      sub_menu = 0, item_index = 4 },
    { item_name = "Carborundum Armor of Striking",     sub_menu = 0, item_index = 5 },
    { item_name = "Carborundum Armor of Scouting",     sub_menu = 1, item_index = 2 },
    { item_name = "Carborundum Coat of Aiming",        sub_menu = 1, item_index = 3 },
    { item_name = "Carborundum Robe of Casting",       sub_menu = 2, item_index = 2 },
    { item_name = "Carborundum Robe of Healing",       sub_menu = 2, item_index = 3 },
}
local shop_hand = {
    { item_name = "Carborundum Gauntles of Fending",   sub_menu = 0, item_index = 6 },
    { item_name = "Carborundum Gauntles of Maiming",   sub_menu = 0, item_index = 7 },
    { item_name = "Carborundum Gauntles of Striking",  sub_menu = 0, item_index = 8 },
    { item_name = "Carborundum Gauntles of Scouting",  sub_menu = 1, item_index = 4 },
    { item_name = "Carborundum Gauntles of Aiming",    sub_menu = 1, item_index = 5 },
    { item_name = "Carborundum Gloves of Casting",     sub_menu = 2, item_index = 4 },
    { item_name = "Carborundum Gloves of Healing",     sub_menu = 2, item_index = 5 },
}
local shop_leg = {
    { item_name = "Carborundum Trousers of Fending",   sub_menu = 0, item_index = 9 },
    { item_name = "Carborundum Trousers of Maiming",   sub_menu = 0, item_index = 10 },
    { item_name = "Carborundum Trousers of Striking",  sub_menu = 0, item_index = 11 },
    { item_name = "Carborundum Trousers of Scouting",  sub_menu = 1, item_index = 6 },
    { item_name = "Carborundum Trousers of Aiming",    sub_menu = 1, item_index = 7 },
    { item_name = "Carborundum Trousers of Casting",   sub_menu = 2, item_index = 6 },
    { item_name = "Carborundum Trousers of Healing",   sub_menu = 2, item_index = 7 },
}
local shop_feet = {
    { item_name = "Carborundum Greaves of Fending",    sub_menu = 0, item_index = 12 },
    { item_name = "Carborundum Greaves of Maiming",    sub_menu = 0, item_index = 13 },
    { item_name = "Carborundum Greaves of Striking",   sub_menu = 0, item_index = 14 },
    { item_name = "Carborundum Boots of Scouting",     sub_menu = 1, item_index = 8 },
    { item_name = "Carborundum Boots of Aiming",       sub_menu = 1, item_index = 9 },
    { item_name = "Carborundum Boots of Casting",      sub_menu = 2, item_index = 8 },
    { item_name = "Carborundum Boots of Healing",      sub_menu = 2, item_index = 9 },
}
local shop_ear = {
    { item_name = "Carborundum Earring of Fending",    sub_menu = 0, item_index = 15 },
    { item_name = "Carborundum Earring of Slaying",    sub_menu = 0, item_index = 16 },
    { item_name = "Carborundum Earring of Aiming",     sub_menu = 1, item_index = 10 },
    { item_name = "Carborundum Earring of Casting",    sub_menu = 2, item_index = 10 },
    { item_name = "Carborundum Earring of Healing",    sub_menu = 2, item_index = 11 },
}
local shop_neck = {
    { item_name = "Carborundum Necklace of Fending",   sub_menu = 0, item_index = 17 },
    { item_name = "Carborundum Necklace of Slaying",   sub_menu = 0, item_index = 18 },
    { item_name = "Carborundum Necklace of Aiming",    sub_menu = 1, item_index = 11 },
    { item_name = "Carborundum Necklace of Casting",   sub_menu = 2, item_index = 12 },
    { item_name = "Carborundum Necklace of Healing",   sub_menu = 2, item_index = 13 },
}
local shop_wrist = {
    { item_name = "Carborundum Bracelet of Fending",   sub_menu = 0, item_index = 19 },
    { item_name = "Carborundum Bracelet of Slaying",   sub_menu = 0, item_index = 20 },
    { item_name = "Carborundum Bracelet of Aiming",    sub_menu = 1, item_index = 12 },
    { item_name = "Carborundum Bracelet of Casting",   sub_menu = 2, item_index = 14 },
    { item_name = "Carborundum Bracelet of Healing",   sub_menu = 2, item_index = 15 },
}
local shop_ring = {
    { item_name = "Carborundum Ring of Fending",       sub_menu = 0, item_index = 21 },
    { item_name = "Carborundum Ring of Slaying",       sub_menu = 0, item_index = 22 },
    { item_name = "Carborundum Ring of Aiming",        sub_menu = 1, item_index = 13 },
    { item_name = "Carborundum Ring of Casting",       sub_menu = 2, item_index = 16 },
    { item_name = "Carborundum Ring of Healing",       sub_menu = 2, item_index = 17 },
}


--Mapping categories to their shop entries
local item_tables = {
  head  = shop_head,
  hand  = shop_hand,
  body  = shop_body,
  leg   = shop_leg,
  feet  = shop_feet,
  ear   = shop_ear,
  neck  = shop_neck,
  wrist = shop_wrist,
  ring  = shop_ring,
}


--Setting item limits per page
local page_limits = {
  [1] = { head=3, hand=3, body=3, leg=3, feet=3,
          ear=2, neck=2, wrist=2, ring=2 },
  [2] = { head=2, hand=2, body=2, leg=2, feet=2,
          ear=1, neck=1, wrist=1, ring=1 },
  [3] = { head=2, hand=2, body=2, leg=2, feet=2,
          ear=2, neck=2, wrist=2, ring=2 },
}


--Addons
local exchange_item_addon = Addons.GetAddon("ShopExchangeItem")
local select_string_addon = Addons.GetAddon("SelectString")
local icon_string_addon = Addons.GetAddon("SelectIconString")


--State Machine
local character_state = {}
stop_script = false
enabled_feature = false
enabled_config = false


-- Helper Functions
--Sleep 
local function sleep(seconds)
    yield('/wait ' .. tostring(seconds))
end

-- Calculate Trades
local function calc_trades()
    local o5n_head  = math.floor(Inventory.GetItemCount(21774) / 2)
    local o5n_body  = math.floor(Inventory.GetItemCount(21775) / 4)
    local o5n_hand  = math.floor(Inventory.GetItemCount(21776) / 2)
    local o5n_leg   = math.floor(Inventory.GetItemCount(21777) / 4)
    local o5n_feet  = math.floor(Inventory.GetItemCount(21778) / 2)
    local o5n_jewel = math.floor(Inventory.GetItemCount(21780))
    local o5n_total = o5n_head+o5n_body+o5n_hand+o5n_leg+o5n_feet+o5n_jewel

  return { head = o5n_head,
        body = o5n_body,
        hand = o5n_hand,
        leg = o5n_leg,
        feet = o5n_feet,
        jewel = o5n_jewel,
        total = o5n_total
    }
end

-- Build pages of purchases based on budgets and page limits
local function build_purchase_pages(item_tables, avail_counts, page_limits)
  local pages     = {}
  -- Clone avail_counts so we can decrement independently
  local remaining = {}
  for cat, cnt in pairs(avail_counts) do
    remaining[cat] = cnt
  end
  -- Shared pool for all four accessory slots
  local accessoryRem = remaining.jewel or 0

  for page_num, slot_limits in ipairs(page_limits) do
    local picks = {}

    for cat, tbl in pairs(item_tables) do
      -- Gather this page’s entries
      local bucket = {}
      for _, entry in ipairs(tbl) do
        if entry.sub_menu == page_num - 1 then
          bucket[#bucket+1] = entry
        end
      end

      -- Determine how many seals remain for this category
      local haveLeft
      if cat == "ear" or cat == "neck" or cat == "wrist" or cat == "ring" then
        haveLeft = accessoryRem
      else
        haveLeft = remaining[cat] or 0
      end

      -- Look up this slot’s cap for the current page
      local slot_limit = slot_limits[cat] or 0
      -- We can only take up to the minimum of (slot cap, seals left, items available)
      local canTake = math.min(slot_limit, haveLeft, #bucket)

      -- Collect picks and decrement the proper counter
      for i = 1, canTake do
        picks[#picks+1] = bucket[i].item_index
        if cat == "ear" or cat == "neck" or cat == "wrist" or cat == "ring" then
          accessoryRem = accessoryRem - 1
        else
          remaining[cat] = remaining[cat] - 1
        end
      end
    end

    pages[page_num] = picks
  end

  return pages
end

-- State  Functions

--Zone to Rhalgr's Reach
function character_state.zone_in()
    if Svc.Condition[CharacterCondition.betweenAreas] then
        sleep(3)
    elseif Svc.ClientState.TerritoryType == rhalgr_reach then
        Dalamud.LogDebug("[Omega Trade] Already in Rhalgr's Reach")
        if not IPC.vnavmesh.IsReady() then
            Engines.Run("/echo Waiting for vnavmesh to build...")
            Dalamud.Log("Waiting for vnavmesh to build...")
            repeat
                yield("/wait 1")
            until IPC.vnavmesh.IsReady()
        elseif Vector3.Distance(Entity.Player.Position, vendor_pos) >= 3 and not IPC.vnavmesh.IsRunning() then
            Dalamud.LogDebug("[Omega Trade] Moving to vendor")
            IPC.vnavmesh.PathfindAndMoveTo(vendor_pos, false)
        elseif Vector3.Distance(Entity.Player.Position, vendor_pos) < 3 and (IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning()) then
            Dalamud.LogDebug("[Omega Trade] Near vendor but vnav still running")
            Engines.Run("/vnav stop")
        elseif Svc.Condition[CharacterCondition.mounted] and Vector3.Distance(Entity.Player.Position, vendor_pos) < 3 then
            Dalamud.LogDebug("[Omega Trade] Mounted near vendor")
            Engines.Run("/ac dismount")
        elseif Entity.GetEntityByName(vendor_name).Name == (vendor_name) and Entity.GetEntityByName(vendor_name).DistanceTo < 5 then
            Dalamud.LogDebug("[Omega Trade] At vendor and targeting")
            Entity.GetEntityByName(vendor_name):SetAsTarget()
            state = character_state.trade_parts
        end
    elseif Svc.ClientState.TerritoryType ~= rhalgr_reach then
        IPC.Lifestream.Teleport(104, 0) --Rhalgr's Reach Aetheryte Plaza
        repeat
            sleep(1)
        until not IPC.Lifestream.IsBusy()
    end
end

-- Trade Omega Parts
function character_state.trade_parts()
    Dalamud.LogDebug("[Omega Trade] Trade Started")
    local avail_counts = calc_trades()
    local pages = build_purchase_pages(item_tables, avail_counts, page_limits)
    --Target NPC
    Dalamud.LogDebug("[Omega Trade] Target Vendor")
    Entity.GetEntityByName(vendor_name):SetAsTarget()
    sleep(.5)
    --Open shop
    Dalamud.LogDebug("[Omega Trade] Open vendor menu")
    Engines.Run("/interact")
    sleep(.5)
    --Select main menu
    Dalamud.LogDebug("[Omega Trade] Selecting Sigmascape Part Exchange (IL350)")
    Engines.Run("/callback SelectIconString true 2")
    sleep(.6)
    for page_num, list in ipairs(pages) do
        --Select submenu
        Dalamud.LogDebug("[Omega Trade] Selecting Sigma Part Exchange" .. page_num)
        Engines.Run("/callback SelectString true " .. (page_num - 1))
        sleep(.5)
        --Purchase each item
        table.sort(list)
        for _, idx in ipairs(list) do
            Dalamud.LogDebug("[Omega Trade] Selecting gear item.")
            Dalamud.LogDebug("[Omega Trade] Buying page " .. page_num .. " item_index " .. idx)
            Engines.Run("/callback ShopExchangeItem true 0 " .. idx .. " 1")
            sleep(.5)
            Dalamud.LogDebug("[Omega Trade] Confirming gear selection.")
            Engines.Run("/callback ShopExchangeItemDialog true 0")
            sleep(.5)
            Dalamud.LogDebug("[Omega Trade] Proceeding with the transaction.")
            Engines.Run("/callback SelectYesno true 0")
            sleep(1)
        end
    --Close submenu dialog
    Dalamud.LogDebug("[Omega Trade] Closing the select gear item menu.")
    Engines.Run("/callback ShopExchangeItem true -1")
    sleep(1)
    end
    --Close main menu
    Dalamud.LogDebug("[Omega Trade] Closing the job specific menu")
    Engines.Run("/callback SelectString true -1")
    state = character_state.gc_turnin
end

-- Trade Omega gear in for GC Seals
function character_state.gc_turnin()
    --Verify all shop windows are closed
    Dalamud.LogDebug("[Omega Trade] Closing all shop windows are closed")
    while (icon_string_addon and icon_string_addon.Ready) or (select_string_addon and select_string_addon.Ready) or (exchange_item_addon and exchange_item_addon.Ready) do
        Dalamud.LogDebug("[Omega Trade] A window is still")
        Engines.Run("/callback SelectIconString true -1")
        Engines.Run("/callback ShopExchangeItem true -1")
        Engines.Run("/callback SelectString true -1")
        sleep(.5)
    end
    if IPC.Lifestream and IPC.Lifestream.ExecuteCommand then
        IPC.Lifestream.ExecuteCommand("gc")
        Dalamud.Log("[FATE] Executed Lifestream teleport to GC.")
    else
        yield("/echo [FATE] Lifestream IPC not available! Cannot teleport to GC.")
        return
    end
    sleep(1)
    while (IPC.Lifestream.IsBusy and IPC.Lifestream.IsBusy())
        or (Svc.Condition[CharacterCondition.betweenAreas]) do
        sleep(1)
    end
    Dalamud.Log("[FATE] Lifestream complete, standing at GC NPC.")
    if IPC.AutoRetainer and IPC.AutoRetainer.EnqueueInitiation then
        IPC.AutoRetainer.EnqueueInitiation()
        Dalamud.Log("[FATE] Called AutoRetainer.EnqueueInitiation() for GC handin.")
    else
        yield("/echo [FATE] AutoRetainer IPC not available! Cannot process GC turnin.")
    end
    local trades = calc_trades()
    local parts_left = false
    for _, v in pairs(trades) do
        if v > 0 then
            parts_left = true
            break
        end
    end
    if parts_left then
        Dalamud.LogDebug("[Omega Trade] Additional Omega trades detected, repeating process.")
        state = character_state.ready
    else
        Dalamud.LogDebug("[Omega Trade] All trades complete.")
        if enabled_config then IPC.PandorasBox.SetConfigEnabled("Auto-select Turn-ins", "AutoConfirm", false) end
        if enabled_feature then IPC.PandorasBox.SetFeatureEnabled("Auto-select Turn-ins", false) end
        stop_script = true
    end
end

--Ready
function character_state.ready()
    local feature_enabled = IPC.PandorasBox.GetFeatureEnabled("Auto-select Turn-ins")
    local config_enabled = IPC.PandorasBox.GetConfigEnabled("Auto-select Turn-ins", "AutoConfirm")

    if feature_enabled and config_enabled then
        Dalamud.LogDebug("[Omega Trade] Pandora's Box - Auto-select Turn-ins and AutoConfirm are enabled.")
    else
        Dalamud.LogDebug("[Omega Trade] Pandora's Box - Enabling required Pandora's Box settings.")
        if not feature_enabled then
            IPC.PandorasBox.SetFeatureEnabled("Auto-select Turn-ins", true)
            enabled_feature = true
        end
        if not config_enabled then
            IPC.PandorasBox.SetConfigEnabled("Auto-select Turn-ins", "AutoConfirm", true)
            enabled_config = true
        end
    end

    while Svc.Condition[CharacterCondition.betweenAreas] do
            sleep(1)
    end

    local trades = calc_trades()
    if trades.total > 0 then
        Engines.Run("/echo Trades -> head="..trades.head..", body="..trades.body..", hand="..trades.hand..", leg="..trades.leg..", feet="..trades.feet..", jewel="..trades.jewel..", total="..trades.total)
        state = character_state.zone_in
    else
        Dalamud.LogDebug("[Omega Trade] No trades available.")
        Engines.Run("/echo No trades available. STOPPING SCRIPT!")
        stop_script = true
    end

end

--Set ready state
state = character_state.ready

--Main script
while not stop_script do
    state()
    sleep(1)
end
IPC.Lifestream.ExecuteCommand("inn")
