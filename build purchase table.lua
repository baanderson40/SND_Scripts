-- Item purchase script: trades parts for items via NPC shop pages

local page_limits = { 3, 2, 2 }
local vendor_name = "Gelfradus"
-- Imports
import("System.Numerics")
-- Shop item definitions
local shop_head = {
    { item_name = "Carborundum Circle of Fending", menu_index = 2, sub_menu = 0, item_index = 0, item_price = 2 },
    { item_name = "Carborundum Helm of Maiming", menu_index = 2, sub_menu = 0, item_index = 1, item_price = 2 },
    { item_name = "Carborundum Bandana of Striking", menu_index = 2, sub_menu = 0, item_index = 2, item_price = 2 },
    { item_name = "Carborundum Bandana of Scouting", menu_index = 2, sub_menu = 1, item_index = 0, item_price = 2 },
    { item_name = "Carborundum Helm of Aiming", menu_index = 2, sub_menu = 1, item_index = 1, item_price = 2 },
    { item_name = "Carborundum Hat of Casting", menu_index = 2, sub_menu = 2, item_index = 0, item_price = 2 },
    { item_name = "Carborundum Circlet of Healing", menu_index = 2, sub_menu = 2, item_index = 1, item_price = 2 },
}
local shop_body = {
    { item_name = "Carborundum Armor of Fending", menu_index = 2, sub_menu = 0, item_index = 3, item_price = 4 },
    { item_name = "Carborundum Armor of Maiming", menu_index = 2, sub_menu = 0, item_index = 4, item_price = 4 },
    { item_name = "Carborundum Armor of Striking", menu_index = 2, sub_menu = 0, item_index = 5, item_price = 4 },
    { item_name = "Carborundum Armor of Scouting", menu_index = 2, sub_menu = 1, item_index = 2, item_price = 4 },
    { item_name = "Carborundum Coat of Aiming", menu_index = 2, sub_menu = 1, item_index = 3, item_price = 4 },
    { item_name = "Carborundum Robe of Casting", menu_index = 2, sub_menu = 2, item_index = 2, item_price = 4 },
    { item_name = "Carborundum Robe of Healing", menu_index = 2, sub_menu = 2, item_index = 3, item_price = 4 },
}
local shop_hand = {
    { item_name = "Carborundum Gauntles of Fending", menu_index = 2, sub_menu = 0, item_index = 6, item_price = 2 },
    { item_name = "Carborundum Gauntles of Maiming", menu_index = 2, sub_menu = 0, item_index = 7, item_price = 2 },
    { item_name = "Carborundum Gauntles of Striking", menu_index = 2, sub_menu = 0, item_index = 8, item_price = 2 },
    { item_name = "Carborundum Gauntles of Scouting", menu_index = 2, sub_menu = 1, item_index = 4, item_price = 2 },
    { item_name = "Carborundum Gauntles of Aiming", menu_index = 2, sub_menu = 1, item_index = 5, item_price = 2 },
    { item_name = "Carborundum Gloves of Casting", menu_index = 2, sub_menu = 2, item_index = 4, item_price = 2 },
    { item_name = "Carborundum Gloves of Healing", menu_index = 2, sub_menu = 2, item_index = 5, item_price = 2 },
}
local shop_leg = {
    { item_name = "Carborundum Trousers of Fending", menu_index = 2, sub_menu = 0, item_index = 9, item_price = 4 },
    { item_name = "Carborundum Trousers of Maiming", menu_index = 2, sub_menu = 0, item_index = 10, item_price = 4 },
    { item_name = "Carborundum Trousers of Striking", menu_index = 2, sub_menu = 0, item_index = 11, item_price = 4 },
    { item_name = "Carborundum Trousers of Scouting", menu_index = 2, sub_menu = 1, item_index = 6, item_price = 4 },
    { item_name = "Carborundum Trousers of Aiming", menu_index = 2, sub_menu = 1, item_index = 7, item_price = 4 },
    { item_name = "Carborundum Trousers of Casting", menu_index = 2, sub_menu = 2, item_index = 6, item_price = 4 },
    { item_name = "Carborundum Trousers of Healing", menu_index = 2, sub_menu = 2, item_index = 7, item_price = 4 },
}
local shop_feet = {
    { item_name = "Carborundum Greaves of Fending", menu_index = 2, sub_menu = 0, item_index = 12, item_price = 2 },
    { item_name = "Carborundum Greaves of Maiming", menu_index = 2, sub_menu = 0, item_index = 13, item_price = 2 },
    { item_name = "Carborundum Greaves of Striking", menu_index = 2, sub_menu = 0, item_index = 14, item_price = 2 },
    { item_name = "Carborundum Boots of Scouting", menu_index = 2, sub_menu = 1, item_index = 8, item_price = 2 },
    { item_name = "Carborundum Boots of Aiming", menu_index = 2, sub_menu = 1, item_index = 9, item_price = 2 },
    { item_name = "Carborundum Boots of Casting", menu_index = 2, sub_menu = 2, item_index = 8, item_price = 2 },
    { item_name = "Carborundum Boots of Healing", menu_index = 2, sub_menu = 2, item_index = 9, item_price = 2 },
}
local shop_jewel = {
    { item_name = "Carborundum Earring of Fending", menu_index = 2, sub_menu = 0, item_index = 15, item_price = 1 },
    { item_name = "Carborundum Earring of Slaying", menu_index = 2, sub_menu = 0, item_index = 16, item_price = 1 },
    { item_name = "Carborundum Earring of Aiming", menu_index = 2, sub_menu = 1, item_index = 10, item_price = 1 },
    { item_name = "Carborundum Earring of Casting", menu_index = 2, sub_menu = 2, item_index = 10, item_price = 1 },
    { item_name = "Carborundum Earring of Healing", menu_index = 2, sub_menu = 2, item_index = 11, item_price = 1 },
    { item_name = "Carborundum Necklace of Fending", menu_index = 2, sub_menu = 0, item_index = 17, item_price = 1 },
    { item_name = "Carborundum Necklace of Slaying", menu_index = 2, sub_menu = 0, item_index = 18, item_price = 1 },
    { item_name = "Carborundum Necklace of Aiming", menu_index = 2, sub_menu = 1, item_index = 11, item_price = 1 },
    { item_name = "Carborundum Necklace of Casting", menu_index = 2, sub_menu = 2, item_index = 12, item_price = 1 },
    { item_name = "Carborundum Necklace of Healing", menu_index = 2, sub_menu = 2, item_index = 13, item_price = 1 },
    { item_name = "Carborundum Bracelet of Fending", menu_index = 2, sub_menu = 0, item_index = 19, item_price = 1 },
    { item_name = "Carborundum Bracelet of Slaying", menu_index = 2, sub_menu = 0, item_index = 20, item_price = 1 },
    { item_name = "Carborundum Bracelet of Aiming", menu_index = 2, sub_menu = 1, item_index = 12, item_price = 1 },
    { item_name = "Carborundum Bracelet of Casting", menu_index = 2, sub_menu = 2, item_index = 14, item_price = 1 },
    { item_name = "Carborundum Bracelet of Healing", menu_index = 2, sub_menu = 2, item_index = 15, item_price = 1 },
    { item_name = "Carborundum Ring of Fending", menu_index = 2, sub_menu = 0, item_index = 21, item_price = 1 },
    { item_name = "Carborundum Ring of Slaying", menu_index = 2, sub_menu = 0, item_index = 22, item_price = 1 },
    { item_name = "Carborundum Ring of Aiming", menu_index = 2, sub_menu = 1, item_index = 13, item_price = 1 },
    { item_name = "Carborundum Ring of Casting", menu_index = 2, sub_menu = 2, item_index = 16, item_price = 1 },
    { item_name = "Carborundum Ring of Healing", menu_index = 2, sub_menu = 2, item_index = 17, item_price = 1 },
}

-- Tables mapping categories to their shop entries
local item_tables = {
  head  = shop_head,
  hand  = shop_hand,
  body  = shop_body,
  leg   = shop_leg,
  feet  = shop_feet,
  jewel = shop_jewel,
}

-- Pause helper
local function sleep(seconds)
  yield('/wait ' .. tostring(seconds))
end

-- Compute how many trades you can make
local function calc_trades()
  local o5n_head  = math.floor(Inventory.GetItemCount(21774) / 2)
  local o5n_body  = math.floor(Inventory.GetItemCount(21775) / 4)
  local o5n_hand  = math.floor(Inventory.GetItemCount(21776) / 2)
  local o5n_leg   = math.floor(Inventory.GetItemCount(21777) / 4)
  local o5n_feet  = math.floor(Inventory.GetItemCount(21778) / 2)
  local o5n_jewel = math.floor(Inventory.GetItemCount(21780))
  local o5n_total = o5n_head+o5n_body+o5n_hand+o5n_leg+o5n_feet+o5n_jewel

  Engines.Run("/echo Trades -> head="..o5n_head..", body="..o5n_body..", hand="..o5n_hand..", leg="..o5n_leg..", feet="..o5n_feet..", jewel="..o5n_jewel..", total="..o5n_total)

  return { head = o5n_head, body = o5n_body, hand = o5n_hand, leg = o5n_leg, feet = o5n_feet, jewel = o5n_jewel }
end

-- Build pages of purchases based on budgets and page limits
local function build_purchase_pages(item_tables, avail_counts, page_limits)
  local pages = {}
  local remaining = {}
  for cat, cnt in pairs(avail_counts) do remaining[cat] = cnt end

  for page_num, limit in ipairs(page_limits) do
    local picks = {}
    for cat, tbl in pairs(item_tables) do
      local bucket = {}
      for _, entry in ipairs(tbl) do
        if entry.sub_menu == page_num - 1 then
          bucket[#bucket + 1] = entry
        end
      end
      local haveLeft = remaining[cat] or 0
      local canTake  = math.min(limit, haveLeft, #bucket)
      for i = 1, canTake do
        picks[#picks + 1] = bucket[i].item_index
        remaining[cat] = remaining[cat] - 1
      end
    end
    pages[page_num] = picks
  end

  return pages
end

-- Main purchase routine: open shop, buy items page by page, close shop
local function trade_parts()
    local avail_counts = calc_trades()
    local pages        = build_purchase_pages(item_tables, avail_counts, page_limits)
    --Target NPC
    yield("/echo trade Function")
    Engines.Run("/target " .. tostring(vendor_name))
    sleep(1)
    --Open shop
    Engines.Run("/interact")
    sleep(1)
    --Select main menu
    Engines.Run("/callback SelectIconString true 2")
    sleep(1)
    for page_num, list in ipairs(pages) do
        --Select submenu
        Engines.Run("/callback SelectString true " .. (page_num - 1))
        sleep(1)
        --Purchase each item
        table.sort(list)
        for _, idx in ipairs(list) do
            Engines.Run("/echo Buying page " .. page_num .. " item_index " .. idx)
            Engines.Run("/callback ShopExchangeItem true 0 " .. idx)
            sleep(1)
            Engines.Run("/callback ShopExchangeItemDialog true 0")
            sleep(1)
            Engines.Run("/callback SelectYesno true 0")
            sleep(2)
        end
    --Close submenu dialog
    Engines.Run("/callback ShopExchangeItem true -1")
    sleep(1)
    end
    --Close main menu
    Engines.Run("/callback SelectString true -1")
end

-- Execute the trade routine
trade_parts()
