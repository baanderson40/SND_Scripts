--[=====[
[[SND Metadata]]
version: 1.0.0
description: |
  This is a custom Lua macro script for SomethingNeedDoing. It is NOT supported by the
  plugin author(s) or by the official Dalamud / XIVLauncher / Puni.sh Discord communities.
  DO NOT ask for help with this script in Discord or support chats!
  No support will be provided by developers and will lead to a ban.
  Use at your own risk
triggers:
- onterritorychange
configs:
  GatherBuddy:
    default: false

[[End Metadata]]
]=====]--

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------
local CFG = {
  DEBUG = true,                 -- Enable verbose dbg() logging to Dalamud log.

  UNDERCUT = 1,                 -- Undercut amount. If lowest seller is not one of MY_RETAINERS, list at (lowest - UNDERCUT).

  FAST = {                      -- Market board read timing behavior.
    maxWaitSec      = 5,        -- Max seconds to wait for first row of ItemSearchResult to become readable.
    refreshAfterSec = 3,        -- If row not readable after this many seconds, trigger one refresh.
  },

  OpenBell = {                  -- Summoning Bell open timing.
    maxAttempts = 50,           -- Max attempts to open the Retainer List via targeting/interacting.
    targetWait  = 0.5,          -- Delay (sec) between /target and /pinteract.
    interactWait= 1.0,          -- Delay (sec) after /pinteract before checking UI state.
  },

  CloseBack = {                 -- When backing out to RetainerList.
    graceWaitSec = 0.5,         -- Grace delay after closing before checking RetainerList state.
  },

  AutoRetainer = {              -- Integration with AutoRetainer plugin.
    enabled     = true,         -- If true, wait for AutoRetainer to be idle before starting loop.
    maxWaitSec  = 60,           -- Max wait time for AutoRetainer to go idle.
    settleSec   = 2,            -- Seconds AutoRetainer must stay idle before considered safe.
    pollSec     = 0.5,          -- Interval for polling AutoRetainer state.
  },

  Auto = {                      -- Auto polling loop for bell-occupied trigger.
    enabled      = true,        -- Master toggle for auto polling mode.
    debounceSec  = 3.0,         -- Debounce time to avoid double-triggers.
    postDelaySec = 0.8,         -- Delay after finishing before next poll.
    bellSettleSec= 0.5,         -- Delay after bell interaction before processing.
    pollSec      = 0.5,         -- Interval for polling bell state.
  },

  NEW_SALES = {                 -- Add new items for sale
    enabled      = true,        -- Master toggle for all new-sale actions.

    -- Define items here with per-retainer stack limits.
    items = { --[item#] = { minQty = 99, defaultPrice = 1000, maxStacks = 1, perRetainer = { ["Retainer1"]=1, ["Retainer2"]=1, ["Retainer3"]=1 } }, -- 
},

    containers         = { "Inventory1","Inventory2","Inventory3","Inventory4","Crystal" }, -- Player inventories to check for saleable items (used for new sales).
    maxAddsPerRetainer = 20,    -- Safety cap: don’t add more than this many new listings per retainer.
    stepDelaySec       = 0.25,  -- Delay between posting each new listing.

    -- Global defaults/fallbacks if not specified per item.
    defaultMinQty      = 1,     -- Default minimum stack size to be considered saleable.
    defaultPrice       = 1000,  -- Default fallback price if no listings exist for the item.
    useDefaultIfNoList = true,  -- If true, use defaultPrice when no active listings are found.
  },
}

-- Process all retainers unless you restrict here
local TARGET_RETAINERS = {
   "Retainer1",
   "Retainer2",
   "Retainer3",
}

-- Your own retainers—don’t undercut these names
local MY_RETAINERS = {
  "Retainer1",
  "Retainer2",
  "Retainer3",
}

------------------------------------------------------------
-- NODE MAP
------------------------------------------------------------
local N = {
  SellList = {
    count = {1,14,19},        -- "N/20"
  },
  Market = {
    firstPrice  = {1,26,4,5},
    firstSeller = {1,26,4,10},
    footer      = {26},
  },
  RetainerName = function(slot)
    local mid = (slot == 1) and 4 or (41000 + (slot - 1))
    return {1,27,mid,2,3}
  end,
}

------------------------------------------------------------
-- ADDON / UTIL HELPERS
------------------------------------------------------------
local function dbg(msg) if CFG.DEBUG then Dalamud.Log("[Repricer][DBG] "..tostring(msg)) end end
local function echo(msg) yield("/echo [Repricer] "..tostring(msg)) end

local function addon(name)
  local ok,res = pcall(function() return Addons.GetAddon(name) end)
  if not ok then return nil end
  return res
end

local function exists(name) local a=addon(name) return a and a.Exists or false end
local function ready (name) local a=addon(name) return a and a.Ready  or false end

local function wait_ready(name, ticks, interval)
  ticks = ticks or 200
  interval = interval or 0.05
  local t=0
  while t<ticks do
    if exists(name) and ready(name) then return true end
    yield(string.format("/wait %.2f", interval)); t=t+1
  end
  return exists(name) and ready(name)
end

local function getnode(a,i1,i2,i3,i4,i5)
  if not a then return nil end
  local ok,node
  if i5~=nil then ok,node=pcall(function() return a:GetNode(i1,i2,i3,i4,i5) end)
  elseif i4~=nil then ok,node=pcall(function() return a:GetNode(i1,i2,i3,i4) end)
  elseif i3~=nil then ok,node=pcall(function() return a:GetNode(i1,i2,i3) end)
  elseif i2~=nil then ok,node=pcall(function() return a:GetNode(i1,i2) end)
  elseif i1~=nil then ok,node=pcall(function() return a:GetNode(i1) end)
  else ok,node=pcall(function() return a:GetNode() end) end
  if not ok then return nil end
  return node
end

local function node_text(node)
  if node==nil then return "" end
  local fields={"Text","Value","String","Label","Name"}
  for i=1,#fields do
    local ok,v=pcall(function() return node[fields[i]] end)
    if ok and type(v)=="string" and v~="" then return v end
  end
  local methods={"GetText","AsString","ToString"}
  for i=1,#methods do
    local ok,f=pcall(function() return node[methods[i]] end)
    if ok and type(f)=="function" then
      local ok2,v=pcall(function() return f(node) end)
      if ok2 and type(v)=="string" and v~="" then return v end
    end
  end
  local okTS,ts=pcall(function() return tostring(node) end)
  if okTS and type(ts)=="string" and not string.find(ts,"LuaMacro.Wrappers.NodeWrapper") then return ts end
  return ""
end

local function gettext(addonName, path)
  local a = addon(addonName); if not a then return "" end
  local n = getnode(a, table.unpack(path))
  return node_text(n)
end

local function pcall_addon(addonName, update, p1, p2, p3, p4, p5)
  local cmd = "/pcall "..addonName.." "..tostring(update)
  if type(p1)=="number" then cmd=cmd.." "..p1 end
  if type(p2)=="number" then cmd=cmd.." "..p2 end
  if type(p3)=="number" then cmd=cmd.." "..p3 end
  if type(p4)=="number" then cmd=cmd.." "..p4 end
  if type(p5)=="number" then cmd=cmd.." "..p5 end
  dbg("PCALL "..cmd.."  (Exists="..tostring(exists(addonName))..", Ready="..tostring(ready(addonName))..")")
  if exists(addonName) and ready(addonName) then yield(cmd) end
end

local function close_addon(name, attempts, waitSec)
  attempts = attempts or 80
  waitSec  = waitSec or 0.05
  local i=0
  while exists(name) and i<attempts do
    pcall_addon(name, true, -1)
    yield(string.format("/wait %.2f", waitSec))
    i=i+1
  end
  return not exists(name)
end

local function close_panels(list)
  for i=1,#list do close_addon(list[i]) end
end

local function wait_until(pred, maxSec, stepSec)
  maxSec  = maxSec or 1.5
  stepSec = stepSec or 0.05
  local elapsed = 0.0
  while elapsed < maxSec do
    if pred() then return true end
    yield(string.format("/wait %.2f", stepSec))
    elapsed = elapsed + stepSec
  end
  return pred()
end

local function now_s() return os.clock() end

------------------------------------------------------------
-- AUTORETAINER IPC
------------------------------------------------------------
local function AR_IsAvailable()
  return (IPC and IPC.AutoRetainer and IPC.AutoRetainer.IsBusy) and true or false
end

local function AR_IsBusy()
  local ok, busy = pcall(function() return IPC.AutoRetainer.IsBusy() end)
  if not ok then return false end
  return busy and true or false
end

local function AD_IsBusy()
  return IPC and IPC.AutoDuty and IPC.AutoDuty.IsStopped and not IPC.AutoDuty.IsStopped()
end

local function GBR_AutoOff()
    yield("/wait 0.1")
    yield("/gbr auto off")
    yield("/wait 0.1")
end

local function GBR_AutoOn()
    yield("/wait 0.1")
    yield("/gbr auto on")
    yield("/wait 0.1")
end

function EnsureAutoRetainerIdle(maxWaitSec, settleSec, pollSec)
  if not CFG.AutoRetainer.enabled then return true end
  if not AR_IsAvailable() then return true end

  maxWaitSec = maxWaitSec or CFG.AutoRetainer.maxWaitSec
  settleSec  = settleSec  or CFG.AutoRetainer.settleSec
  pollSec    = pollSec    or CFG.AutoRetainer.pollSec

  local waited = 0.0
  while waited < maxWaitSec do
    if not AR_IsBusy() then
      local idle = 0.0
      local stable = true
      while idle < settleSec do
        if AR_IsBusy() then stable = false; break end
        yield(string.format("/wait %.2f", pollSec))
        idle = idle + pollSec
      end
      if stable then
        dbg(string.format("AutoRetainer idle confirmed (%.1fs quiet).", settleSec))
        return true
      end
    end
    yield(string.format("/wait %.2f", pollSec))
    waited = waited + pollSec
  end

  if AR_IsBusy() then
    yield("/echo [Repricer] AutoRetainer stayed busy past timeout; not starting.")
    return false
  end
  return true
end

import("System.Numerics")
local function DistanceBetweenPositions(pos1, pos2) local distance = Vector3.Distance(pos1, pos2) return distance end

-- Stall Watchdog: abort AutoRetainer if player is "stuck"
local _stall_last_pos     = nil
local _stall_last_move_t  = now_s()
local STALL_TIMEOUT_SEC   = 15.0
local STALL_EPSILON_DIST  = 0.02

local function AutoRetainerAvailableForThisChara()
  return IPC and IPC.AutoRetainer
     and IPC.AutoRetainer.AreAnyRetainersAvailableForCurrentChara
     and IPC.AutoRetainer.AreAnyRetainersAvailableForCurrentChara()
end

function CheckPlayerStallAndResetAR()
  local cs = Svc and Svc.ClientState
  local lp = cs and cs.LocalPlayer or nil
  if not lp then return end

  local pos  = lp.Position
  local terr = cs.TerritoryType or 0

  if not _stall_last_pos then
    _stall_last_pos    = pos
    _stall_last_move_t = now_s()
    return
  end

  local dist = DistanceBetweenPositions(pos, _stall_last_pos) or 0
  if dist > STALL_EPSILON_DIST then
    _stall_last_pos    = pos
    _stall_last_move_t = now_s()
    return
  end

  if (now_s() - _stall_last_move_t) >= STALL_TIMEOUT_SEC
     and terr ~= 610
     and AutoRetainerAvailableForThisChara()
     and IPC and IPC.AutoRetainer and IPC.AutoRetainer.AbortAllTasks then
    yield("/echo [Repricer] Stall detected (≥5s, terr "..tostring(terr)..") — aborting AutoRetainer tasks.")
    IPC.AutoRetainer.AbortAllTasks()
    _stall_last_move_t = now_s()
    _stall_last_pos    = pos
  end
end

local _apartment_interact_timer = 0
local _apartment_interact_threshold = 5

function InteractWithApartmentEntrance()
  local target = Player.Entity and Player.Entity.Target
  if target and target.Name == "Apartment Building Entrance" then
    if _apartment_interact_timer == 0 then
      _apartment_interact_timer = now_s()
    elseif now_s() - _apartment_interact_timer >= _apartment_interact_threshold then
      local e = Entity.GetEntityByName("Apartment Building Entrance")
      if e then
        Dalamud.Log("[SomethingNeedDoing] Targetting: " .. e.Name)
        e:SetAsTarget()
      end
      if Entity.Target and Entity.Target.Name == "Apartment Building Entrance" then
        Dalamud.Log("[SomethingNeedDoing] Interacting: " .. e.Name)
        e:Interact()
        yield('/wait 1')
        _apartment_interact_timer = 0
      end
    end
  else
    _apartment_interact_timer = 0 
  end
end

------------------------------------------------------------
-- OPEN SUMMONING BELL -> RETAINER LIST
------------------------------------------------------------
function EnsureRetainerListOpen()
  if exists("RetainerList") and ready("RetainerList") then return true end
  yield("/echo [Repricer] Opening Summoning Bell…")

  local tries = 0
  while not (exists("RetainerList") and ready("RetainerList")) and tries < CFG.OpenBell.maxAttempts do
    yield("/target Summoning Bell")
    yield(string.format("/wait %.2f", CFG.OpenBell.targetWait))
    yield("/pinteract")
    yield(string.format("/wait %.2f", CFG.OpenBell.interactWait))
    tries = tries + 1
  end

  if exists("RetainerList") and ready("RetainerList") then
    yield("/echo [Repricer] Retainer List opened.")
    return true
  end
  yield("/echo [Repricer] Could not open Retainer List (Summoning Bell not found?).")
  return false
end

------------------------------------------------------------
-- ITEM OPEN / SEARCH OPEN / FAST READ
------------------------------------------------------------
function OpenItem(slot)
  dbg("OpenItem slot="..tostring(slot))
  if not (exists("RetainerSellList") and ready("RetainerSellList")) then
    dbg("OpenItem: RetainerSellList not ready."); return false
  end

  local idx = math.max(0, math.min(19, (slot or 1)-1))

  local function wait_retainer_sell()
    if exists("ContextMenu") then
      pcall_addon("ContextMenu", true, 0, 0)
      if not wait_ready("RetainerSell", 40) then
        pcall_addon("ContextMenu", true, 1, 0)
      end
    end
    return wait_ready("RetainerSell", 60)
  end

  pcall_addon("RetainerSellList", true, 0, idx, 1)
  if wait_retainer_sell() then dbg("OpenItem: success via (0, idx, 1)"); return true end

  dbg("OpenItem: failed to open item after attempts.")
  return false
end

function EnsureSearchOpen_AutoFriendly(preWaitTicks, graceReadyTicks, totalWaitTicks)
  preWaitTicks    = preWaitTicks    or 8
  graceReadyTicks = graceReadyTicks or 12
  totalWaitTicks  = totalWaitTicks  or 90

  if not (exists("RetainerSell") and ready("RetainerSell")) then
    dbg("EnsureSearchOpen: RetainerSell not ready."); return false
  end
  if exists("ItemSearchResult") and ready("ItemSearchResult") then
    dbg("EnsureSearchOpen: already open & ready."); return true
  end

  local t=0
  while t<preWaitTicks do
    if exists("ItemSearchResult") then
      if ready("ItemSearchResult") then
        dbg("EnsureSearchOpen: plugin opened within pre-wait."); return true
      end
      local g=0
      while g<graceReadyTicks do
        if ready("ItemSearchResult") then
          dbg("EnsureSearchOpen: plugin readied within grace."); return true
        end
        yield("/wait 0.1"); g=g+1
      end
      break
    end
    yield("/wait 0.1"); t=t+1
  end

  if not exists("ItemSearchResult") then
    pcall_addon("RetainerSell", true, 4) -- Compare Prices
  end

  local used=t; local budget=math.max(0, totalWaitTicks-used)
  local u=0
  while u<budget do
    if exists("ItemSearchResult") and ready("ItemSearchResult") then return true end
    yield("/wait 0.1"); u=u+1
  end

  dbg("EnsureSearchOpen: ItemSearchResult not ready within timeout.")
  return false
end

local function refresh_market()
  if exists("RetainerSell") and ready("RetainerSell") then
    pcall_addon("RetainerSell", true, 4)
  end
end

function ReadLowestListing_Fast(maxWaitSec, refreshAfterSec)
  maxWaitSec      = maxWaitSec      or CFG.FAST.maxWaitSec
  refreshAfterSec = refreshAfterSec or CFG.FAST.refreshAfterSec

  if exists("ItemHistory") then pcall_addon("ItemHistory", true, -1) end

  local start = os.clock()
  local refreshed = false

  while (os.clock() - start) < maxWaitSec do
    local rawPrice = gettext("ItemSearchResult", N.Market.firstPrice)
    local price    = (function(t)
      if not t or t=="" then return nil end
      local cleaned = string.gsub(t, "[,%s%.]", "")
      cleaned = string.gsub(cleaned, "[^0-9]", "")
      if cleaned=="" then return nil end
      return tonumber(cleaned)
    end)(rawPrice)
    if price ~= nil then
      local seller = gettext("ItemSearchResult", N.Market.firstSeller)
      dbg("firstRow priceCell='"..tostring(rawPrice).."' -> parsed="..tostring(price))
      dbg("firstRow sellerCell='"..tostring(seller).."'")
      return price, seller
    end
    if (not refreshed) and ((os.clock() - start) >= refreshAfterSec) then
      dbg("ReadLowestListing_Fast: stale row; refreshing once…")
      refresh_market(); refreshed = true
    end
    yield("/wait 0.05")
  end

  local footer = gettext("ItemSearchResult", N.Market.footer)
  if footer ~= "" and string.find(footer, "No items found") then
    dbg("ReadLowestListing_Fast: No items found.")
    return nil, nil
  end

  dbg("ReadLowestListing_Fast: timeout without first row.")
  return nil, nil
end

function CloseItemPanels()
  close_panels({"ItemSearchResult","ItemHistory"})
end

------------------------------------------------------------
-- PRICING
------------------------------------------------------------
local function is_my_retainer(name)
  if not name or name=="" then return false end
  for i=1,#MY_RETAINERS do if name==MY_RETAINERS[i] then return true end end
  return false
end

function DecideNewPrice(lowestPrice, lowestSeller)
  if not lowestPrice then return nil end
  if is_my_retainer(lowestSeller) then return lowestPrice end
  return math.max(1, lowestPrice - CFG.UNDERCUT)
end

function ApplyPrice(newPrice)
  if not (exists("RetainerSell") and ready("RetainerSell")) then
    dbg("ApplyPrice: RetainerSell not ready."); return false end

  local rawCurrent = gettext("RetainerSell", {6})
  local current
  if rawCurrent and rawCurrent~="" then
    local cleaned = string.gsub(rawCurrent, "[,%s%.]", "")
    cleaned = string.gsub(cleaned, "[^0-9]", "")
    current = tonumber(cleaned) or -1
  else
    current = -1
  end

  if not newPrice or newPrice <= 0 then
    dbg("ApplyPrice: invalid newPrice="..tostring(newPrice)); return false end

  if current == newPrice then
    yield("/echo [Repricer] Price already set: "..tostring(newPrice))
    return true
  end

  yield("/echo [Repricer] Set price: "..tostring(current).." → "..tostring(newPrice))
  pcall_addon("RetainerSell", true, 2, newPrice)
  pcall_addon("RetainerSell", true, 0)
  return true
end

function CloseItem()
  close_addon("RetainerSell", 60, 0.05)
  if exists("ContextMenu") then pcall_addon("ContextMenu", true, -1) end
end

------------------------------------------------------------
-- REPRICE EXISTING LISTINGS
------------------------------------------------------------
local function parse_ratio_head(text)
  if not text or text=="" then return 0 end
  local m = string.match(text, "^(%d+)")
  return tonumber(m or "0") or 0
end

local function CountItems()
  local t = gettext("RetainerSellList", N.SellList.count)
  local n = parse_ratio_head(t)
  dbg("CountItems: '"..tostring(t).."' -> "..tostring(n))
  return n
end

function RepriceAllOnThisRetainer(maxWaitSec, refreshAfterSec, startSlot, endSlot)
  if not (exists("RetainerSellList") and ready("RetainerSellList")) then
    yield("/echo [Repricer] Please open the retainer's Sell List first."); return end

  maxWaitSec      = maxWaitSec      or CFG.FAST.maxWaitSec
  refreshAfterSec = refreshAfterSec or CFG.FAST.refreshAfterSec

  local total = CountItems()
  if total <= 0 then yield("/echo [Repricer] No sale items to process."); return end

  local s = math.max(1, tonumber(startSlot or 1))
  local e = math.min(total, tonumber(endSlot or total))
  yield("/echo [Repricer] Processing slots "..s.."–"..e.." of "..total.."...")

  for slot = s, e do
    repeat
      if not OpenItem(slot) then
        yield("/echo [Repricer] Slot "..slot..": open failed, skipping."); break end
      if not EnsureSearchOpen_AutoFriendly(8, 12, 90) then
        yield("/echo [Repricer] Slot "..slot..": search failed, skipping."); CloseItem(); break end

      local low, seller = ReadLowestListing_Fast(maxWaitSec, refreshAfterSec)
      CloseItemPanels()

      if low then
        local want = DecideNewPrice(low, seller)
        ApplyPrice(want)
      else
        yield("/echo [Repricer] Slot "..slot..": no market data (or timeout).")
      end

      CloseItem()
    until true
    yield("/wait 0.05")
  end

  yield("/echo [Repricer] Done with this retainer.")
end

------------------------------------------------------------
-- SELL NEW ITEMS (consolidated: helpers + quota + runner)
------------------------------------------------------------
-- Convert helper container to 0..3 or 9.
local function to_cidx(v)
  if type(v) == 'number' then
    if v >= 0 and v <= 3 then return v end
    return nil
  end

  local s = tostring(v or "")
  if s == "" then return nil end

  -- hard block: ignore retainer containers
  if s:match('^Retainer') or s:match('^Market') then return nil end

  -- "Inventory2" -> 1
  local n = tonumber((s:gsub('%s+','')):match('[Ii]nventory(%d+)'))
  if n and n >= 1 and n <= 4 then return n - 1 end

  -- "Inventory1: 0" -> 0 (trailing number often present)
  local tail = s:match(':%s*(%d+)$')
  if tail then
    local tnum = tonumber(tail)
    if tnum and tnum >= 0 and tnum <= 3 then return tnum end
  end

  -- Crystal container
  if s:find("Crystal") then return 9 end

  -- final numeric fallback
  local asnum = tonumber(s)
  if asnum and asnum >= 0 and asnum <= 3 then return asnum end

  return nil
end

local function OpenRetainerSellForSource(containerIndex, slot0)
  -- Confirmed mapping: opens RetainerSell with max quantity auto-filled
  local cmd = string.format("/pcall InventoryGrid true 15 %d %d", containerIndex, slot0)
  dbg("SELL PCALL -> "..cmd)
  yield(cmd)
  return wait_ready("RetainerSell", 60)
end

local function EnsureSearchOpen_Sell()
  if not (exists("RetainerSell") and ready("RetainerSell")) then
    dbg("EnsureSearchOpen_Sell: RetainerSell not ready."); return false
  end
  if exists("ItemSearchResult") and ready("ItemSearchResult") then return true end
  for _=1,8 do
    if exists("ItemSearchResult") and ready("ItemSearchResult") then return true end
    yield("/wait 0.1")
  end
  if not exists("ItemSearchResult") then
    pcall_addon("RetainerSell", true, 4) -- Compare Prices
  end
  for _=1,90 do
    if exists("ItemSearchResult") and ready("ItemSearchResult") then return true end
    yield("/wait 0.1")
  end
  dbg("EnsureSearchOpen_Sell: ItemSearchResult not ready within timeout.")
  return false
end

-- Sell ONE item (by itemId), honoring per-item minQty/defaultPrice with global fallbacks.
function SellNewItem(itemId, perItemCfg)
  -- Per-item overrides, then global defaults, then hard fallback.
  local minQty       = tonumber(perItemCfg and perItemCfg.minQty) or tonumber(CFG.NEW_SALES.defaultMinQty) or 1
  local defaultPrice = tonumber(perItemCfg and perItemCfg.defaultPrice) or tonumber(CFG.NEW_SALES.defaultPrice)

  while true do
    local ok,res = pcall(function() return Inventory.GetInventoryItem(itemId) end)
    if not ok or not res then
      dbg(("SellNewItem: helper found no stack for %d; stop."):format(itemId))
      return false
    end

    -- Extract container index strictly from "Inventory1..4" and Crystal.
    local cidx = to_cidx(res.Container)
    if cidx == nil then
      dbg(("SellNewItem: helper returned non-player container '%s'; stop."):format(tostring(res.Container)))
      return false
    end

    local slot0 = tonumber(res.Slot) or 0
    local qty   = tonumber(res.Quantity or res.Count or res.StackSize or res.Amount or 0) or 0

    -- Respect min quantity threshold.
    if qty < minQty then
      dbg(("SellNewItem: qty %d < minQty %d for %d; skip."):format(qty, minQty, itemId))
      return false
    end

    -- Open RetainerSell with max-allowed quantity (game caps at 99 per listing).
    if not OpenRetainerSellForSource(cidx, slot0) then
      dbg(("SellNewItem: failed to open RetainerSell for cidx=%d slot=%d"):format(cidx, slot0))
      return false
    end

    -- Try to get market price; if none, fall back to defaultPrice (if provided).
    local priceToUse = nil
    if EnsureSearchOpen_Sell() then
      local low, seller = ReadLowestListing_Fast(CFG.FAST.maxWaitSec, CFG.FAST.refreshAfterSec)
      CloseItemPanels()
      if low then priceToUse = DecideNewPrice(low, seller) end
    end
    if not priceToUse then
      priceToUse = defaultPrice
      if not priceToUse or priceToUse <= 0 then
        dbg(("SellNewItem: no market data and no defaultPrice for %d; closing."):format(itemId))
        CloseItem()
        return false
      end
    end

    -- Apply price & close. Successful listing -> return true so caller counts it.
    ApplyPrice(priceToUse)
    CloseItem()

    -- Yield briefly to let inventory update before the next helper call.
    yield(("/wait %.2f"):format(CFG.NEW_SALES.stepDelaySec or 0.25))
    return true
  end
end

------------------------------------------------------------
-- PER-RETAINER QUOTA STATE (for new listings)
------------------------------------------------------------
-- Tracks current stacks listed per retainer: CURRENT_STACKS[retName][itemId] = count
local CURRENT_STACKS = {}

-- Build per-retainer stack map using the RetainerMarket indexer
local function BuildCurrentStacksForRetainer(retName)
  CURRENT_STACKS[retName] = {}
  local cont = Inventory.RetainerMarket         -- << key change (no string arg)
  for i = 0, cont.Count - 1 do
    local slot = cont[i]                        -- use indexer; includes empty slots
    local id = tonumber(slot.ItemId)
    if id and id > 0 then
      CURRENT_STACKS[retName][id] = (CURRENT_STACKS[retName][id] or 0) + 1
    end
  end
  local n=0 for _ in pairs(CURRENT_STACKS[retName]) do n=n+1 end
  dbg(("[%s] current stacks snapshot built (unique items=%d)."):format(retName, n))
end

local function GetQuota(retName, itemId)
  local cfgItems = (CFG.NEW_SALES and CFG.NEW_SALES.items) or {}
  local cfg = cfgItems[itemId] or {}
  local per = (cfg.perRetainer or {})[retName]
  return tonumber(per) or tonumber(cfg.maxStacks) or math.huge
end

local function GetCount(retName, itemId)
  local r = CURRENT_STACKS[retName]; if not r then return 0 end
  return tonumber(r[itemId]) or 0
end

local function CanListMore(retName, itemId)
  return GetCount(retName, itemId) < GetQuota(retName, itemId)
end

-- Runner: add new items to current retainer respecting capacity & quotas
function SellNewItemsOnThisRetainer(retName)
  if not (CFG.NEW_SALES and CFG.NEW_SALES.enabled) then return end
  if not (exists("RetainerSellList") and ready("RetainerSellList")) then
    echo("Open the retainer's Sell List first before selling new items."); return
  end

  local listedText = gettext("RetainerSellList", N.SellList.count)
  local listed     = parse_ratio_head(listedText) or 0
  local free       = math.max(0, 20 - listed)
  if free <= 0 then
    echo("Sell list full; skipping new sales.")
    return
  end

  local capacity = math.min(free, tonumber(CFG.NEW_SALES.maxAddsPerRetainer) or 100)
  local added = 0
  echo(("Adding up to %d new listing(s)."):format(capacity))

  for itemId, perCfg in pairs(CFG.NEW_SALES.items or {}) do
    while added < capacity do
      if not CanListMore(retName, itemId) then
        dbg(("[%s] quota reached for %d (%d/%d); skipping further stacks."):format(
          retName, itemId, GetCount(retName, itemId), GetQuota(retName, itemId)))
        break
      end

      if not SellNewItem(itemId, perCfg) then
        -- Could be: below minQty, no player stack, or no price path; move on to next itemId.
        break
      end

      added = added + 1
      CURRENT_STACKS[retName][itemId] = GetCount(retName, itemId) + 1

      if added >= capacity then break end
      if not CanListMore(retName, itemId) then break end

      yield(("/wait %.2f"):format(CFG.NEW_SALES.stepDelaySec or 0.25))
    end
    if added >= capacity then break end
  end

  echo("New sales added: "..tostring(added))
end

------------------------------------------------------------
-- RETAINER LIST HELPERS / ROUNDTRIP
------------------------------------------------------------
local function is_target_retainer(name)
  if not name or name=="" then return false end
  if #TARGET_RETAINERS==0 then return true end
  for i=1,#TARGET_RETAINERS do if name==TARGET_RETAINERS[i] then return true end end
  return false
end

local function RetainerNameAt(slot)
  return gettext("RetainerList", N.RetainerName(slot))
end

local function ReadRetainerList()
  if not (exists("RetainerList") and ready("RetainerList")) then
    yield("/echo [Repricer] Open the Retainer List at a Summoning Bell."); return {} end
  local res = {}
  for slot=1,12 do
    local nm = RetainerNameAt(slot)
    if nm ~= "" then
      table.insert(res, {slot=slot, name=nm})
      dbg(string.format("List slot %d: '%s'", slot, nm))
    else
      dbg(string.format("List slot %d: (empty / not purchased)", slot))
    end
  end
  return res
end

local function OpenRetainerBySlot(slot)
  dbg("Opening retainer slot "..tostring(slot).."...")
  pcall_addon("RetainerList", true, 2, slot-1)
  if not wait_ready("SelectString", 80) then
    dbg("OpenRetainerBySlot: SelectString did not appear."); return false end
  pcall_addon("SelectString", true, 2) -- "Sell items"
  if not wait_ready("RetainerSellList", 120) then
    dbg("OpenRetainerBySlot: RetainerSellList failed to open."); return false end
  return true
end

local function CloseBackToRetainerList(graceWaitSec)
  graceWaitSec = graceWaitSec or CFG.CloseBack.graceWaitSec
  dbg("CloseBackToRetainerList: begin")

  close_addon("RetainerSellList", 80, 0.05)

  local ticks = math.max(1, math.floor(graceWaitSec / 0.1 + 0.5))
  for _=1,ticks do
    if exists("SelectString") then break end
    yield("/wait 0.1")
  end

  local ok = wait_until(function() return exists("SelectString") and ready("SelectString") end, 5.0, 0.1)
  if ok then
    for _=1,10 do
      pcall_addon("SelectString", true, -1)
      yield("/wait 0.05")
      if not exists("SelectString") then break end
    end
  end

  if not wait_ready("RetainerList", 200) then
    dbg("CloseBackToRetainerList: RetainerList not ready after closing."); return false end
  dbg("CloseBackToRetainerList: done (RetainerList ready)")
  return true
end

local function CloseRetainerList()
  dbg("CloseRetainerList: begin")
  close_addon("RetainerSellList", 80, 0.05)
  close_addon("SelectString",    80, 0.05)

  local tries = 0
  while exists("RetainerList") and tries < 80 do
    pcall_addon("RetainerList", true, -1)
    yield("/wait 0.05")
    tries = tries + 1
  end

  if exists("RetainerList") then
    dbg("CloseRetainerList: RetainerList still open after attempts.")
    return false
  end

  dbg("CloseRetainerList: done (RetainerList closed).")
  return true
end

------------------------------------------------------------
-- PROCESS ONE RETAINER (repricing + new listings)
------------------------------------------------------------
local function ProcessThisRetainer(retName)
  if not (exists("RetainerSellList") and ready("RetainerSellList")) then
    echo("RetainerSellList not ready; aborting retainer process."); return end

  -- Snapshot current stacks from RetainerMarket so we can enforce quotas.
  BuildCurrentStacksForRetainer(retName)

  -- Phase A: reprice existing listings
  RepriceAllOnThisRetainer()

  -- Phase B: add new items with quota enforcement
  SellNewItemsOnThisRetainer(retName)
end

function RepriceTargetsOnRetainerList()
  if not EnsureRetainerListOpen() then return end

  yield("/echo [Repricer] Scanning Retainer List…")
  local entries = ReadRetainerList()
  if #entries==0 then yield("/echo [Repricer] No retainers found on this character."); return end

  local targets = {}
  for _,e in ipairs(entries) do if is_target_retainer(e.name) then table.insert(targets, e) end end
  if #targets==0 then yield("/echo [Repricer] No retainers matched TARGET_RETAINERS on this character."); return end

  yield("/echo [Repricer] Processing "..tostring(#targets).." retainer(s)…")
  for i,t in ipairs(targets) do
    yield(string.format("/echo [Repricer] [%d/%d] %s (slot %d)", i, #targets, t.name, t.slot))
    if OpenRetainerBySlot(t.slot) then
      ProcessThisRetainer(t.name)  -- pass retainer name for quotas
    end
    CloseBackToRetainerList()
    yield("/wait 0.1")
  end
  CloseRetainerList()
  yield("/echo [Repricer] All target retainers processed.")
  if AutoDutyRunning then
    yield('/snd run HelioFarm')
    AutoDutyRunning = false
  end

  if GatherEnabled then GBR_AutoOn() end
end

------------------------------------------------------------
-- AUTO POLLING LOOP
------------------------------------------------------------
local AUTO_ENABLED       = CFG.Auto.enabled
local AUTO_DEBOUNCE_SEC  = CFG.Auto.debounceSec
local AUTO_POST_DELAY    = CFG.Auto.postDelaySec
local BELL_SETTLE_SEC    = CFG.Auto.bellSettleSec
local POLL_INTERVAL_SEC  = CFG.Auto.pollSec

local _auto_in_progress  = false
local _auto_last_fire_t  = 0.0
local _bell_since        = 0.0

local function _auto_can_fire()
  if not AUTO_ENABLED then return false end
  if _auto_in_progress then return false end
  if (now_s() - _auto_last_fire_t) < AUTO_DEBOUNCE_SEC then return false end
  return true
end

local function IsBellOccupied()
  local ok, val = pcall(function()
    return Svc and Svc.Condition and Svc.Condition[50] and Entity.Target and Entity.Target.Name == "Summoning Bell"
  end)
  if not ok then return false end
  return val and true or false
end

function AutoEnable()  AUTO_ENABLED = true;  yield("/echo [Repricer] Auto trigger ENABLED")  end
function AutoDisable() AUTO_ENABLED = false; yield("/echo [Repricer] Auto trigger DISABLED") end

yield("/echo [Repricer] AutoBell polling loop started.")
while true do
    CheckPlayerStallAndResetAR()
    InteractWithApartmentEntrance()

    local occupied = IsBellOccupied()
    GatherEnabled = Config.Get("GatherBuddy")

    if occupied and AR_IsBusy() then
        if AD_IsBusy() then
        AutoDutyRunning = true
        yield('/snd stop HelioFarm')
        IPC.AutoDuty.Stop()
        end

    if GatherEnabled then GBR_AutoOff() end

        if _bell_since == 0 then _bell_since = now_s() end

        if _auto_can_fire() and (now_s() - _bell_since) >= BELL_SETTLE_SEC then
        _auto_in_progress = true
        yield("/echo [Repricer] Auto: Bell occupied — preparing to start…")

        yield(string.format("/wait %.2f", AUTO_POST_DELAY))

        if not EnsureAutoRetainerIdle() then
            _auto_in_progress = false
            yield("/echo [Repricer] Auto: aborted — AutoRetainer busy.")
        else
            RepriceTargetsOnRetainerList()
            _auto_last_fire_t = now_s()
            _auto_in_progress = false
            yield("/echo [Repricer] Auto: run finished.")
        end

        repeat
            yield("/wait 0.20")
        until not IsBellOccupied()
        _bell_since = 0.0
        end
    else
        _bell_since = 0.0
    end

    yield(string.format("/wait %.2f", POLL_INTERVAL_SEC))
end
