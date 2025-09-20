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
- onlogin
[[End Metadata]]
]=====]--

------------------------------------------------------------
--Config
------------------------------------------------------------
local CFG = {
  DEBUG = true,               -- When true, enables debug logs via dbg()/Dalamud.Log (e.g., "OpenItem:", prices read, state transitions).

  UNDERCUT = 1,               -- Amount subtracted from the current lowest market price when the lowest seller is not one of MY_RETAINERS.
                              -- Used by DecideNewPrice(): new price = max(1, lowestPrice - UNDERCUT). If lowest seller is yours, price is kept.

  FAST = {
    maxWaitSec      = 2,      -- Upper bound (seconds) for ReadLowestListing_Fast() to find and parse the first row’s price/seller.
    refreshAfterSec = 1,      -- If the first row isn’t readable by this age (seconds), trigger one “Compare prices” refresh and try again.
  },

  OpenBell = {
    maxAttempts = 50,         -- Maximum loop iterations to target and interact with the Summoning Bell until RetainerList is open/ready.
    targetWait  = 0.5,        -- Delay (seconds) after “/target Summoning Bell” before attempting to interact.
    interactWait= 1.0,        -- Delay (seconds) after “/pinteract” before checking if RetainerList appeared.
  },

  CloseBack = {
    graceWaitSec = 0.5,       -- Small wait used by CloseBackToRetainerList() when returning from a retainer’s Sell List,
                              -- allowing the intermediate “SelectString” window to appear before closing it.
  },

  -- AutoRetainer wait config
  AutoRetainer = {
    enabled     = true,       -- If true and AutoRetainer IPC is available, EnsureAutoRetainerIdle() waits for AutoRetainer to be not busy.
    maxWaitSec  = 60,         -- Overall timeout (seconds) to wait for AutoRetainer to become idle before aborting an auto run.
    settleSec   = 1.5,        -- Once AutoRetainer reports not busy, it must remain not busy for this many seconds to confirm “idle”.
    pollSec     = 0.5,        -- Polling interval (seconds) while checking AutoRetainer busy/idle state.
  },

  -- Auto Bell polling loop
  Auto = {
    enabled      = true,      -- Master toggle for the auto-run loop that watches the Summoning Bell condition and triggers repricing.
    debounceSec  = 3.0,       -- Minimum seconds between successive auto runs (prevents rapid re-triggering).
    postDelaySec = 0.8,       -- Short delay (seconds) after deciding to fire but before starting, to let UI settle.
    bellSettleSec= 0.5,       -- The Summoning Bell must be continuously “occupied” for at least this long before arming the run.
    pollSec      = 0.5,       -- Cadence (seconds) of the auto loop’s polling cycle (both for bell state and between loop iterations).
  },
}

-- Only reprice these retainers by name. Leave EMPTY to process **all** retainers.
local TARGET_RETAINERS = {
   "",
   "",
  -- "",
}
-- Used by: is_target_retainer() to decide which retainers to include during a run.
-- Behavior per code: if this table has length 0, every retainer on the Retainer List is considered a target.

-- Your own retainer names (used to avoid undercutting yourself on market listings)
local MY_RETAINERS = {
  "",
  "",
  "",
}
-- Used by: is_my_retainer() and DecideNewPrice(). If the current lowest seller matches any of these names,
-- the script keeps the lowest price instead of undercutting it.

------------------------------------------------------------
--Node map (single source of truth)
------------------------------------------------------------
local N = {
  SellList = {
    count = {1,14,19},           -- "N/20"
  },
  Market = {
    firstPrice  = {1,26,4,5},
    firstSeller = {1,26,4,10},
    footer      = {26},          -- "No items found."
  },
  RetainerName = function(slot)
    local mid = (slot == 1) and 4 or (41000 + (slot - 1))
    return {1,27,mid,2,3}
  end,
}

------------------------------------------------------------
--Addon utils
------------------------------------------------------------
local function dbg(msg) if CFG.DEBUG then Dalamud.Log("[Repricer][DBG] "..tostring(msg)) end end

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
    yield(string.format("/wait %.2f", interval))
    t=t+1
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

function GetTargetName()
    return (Entity and Entity.Target and Entity.Target.Name) or ""
end

------------------------------------------------------------
--Parsing & timing helpers
------------------------------------------------------------
local function parse_price(text)
  if not text or text=="" then return nil end
  local cleaned = string.gsub(text, "[,%s%.]", "")
  cleaned = string.gsub(cleaned, "[^0-9]", "")
  if cleaned=="" then return nil end
  return tonumber(cleaned)
end

local function parse_ratio_head(text)
  if not text or text=="" then return 0 end
  local m = string.match(text, "^(%d+)")
  return tonumber(m or "0") or 0
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
--AutoRetainer IPC helpers
------------------------------------------------------------
local function AR_IsAvailable()
  return (IPC and IPC.AutoRetainer and IPC.AutoRetainer.IsBusy) and true or false
end

local function AR_IsBusy()
  local ok, busy = pcall(function() return IPC.AutoRetainer.IsBusy() end)
  if not ok then return false end
  return busy and true or false
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

------------------------------------------------------------
--Open Summoning Bell -> RetainerList
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
--Item open / search open / fast read / close panels
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
    pcall_addon("RetainerSell", true, 4) -- Compare prices
  else
    dbg("EnsureSearchOpen: exists but not ready; no fallback, just waiting.")
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
    local price    = parse_price(rawPrice)
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
--Pricing
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
  local current    = parse_price(rawCurrent) or -1

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
--Per-retainer batch repricer (Sell List must be open)
------------------------------------------------------------
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
--Retainer list helpers + roundtrip
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
  pcall_addon("SelectString", true, 3) -- "Sell items"
  if not wait_ready("RetainerSellList", 120) then
    dbg("OpenRetainerBySlot: RetainerSellList failed to open."); return false end
  return true
end

local function CloseBackToRetainerList(graceWaitSec)
  graceWaitSec = graceWaitSec or CFG.CloseBack.graceWaitSec
  dbg("CloseBackToRetainerList: begin")

  close_addon("RetainerSellList", 80, 0.05)

  local ticks = math.max(1, math.floor(graceWaitSec / 0.1 + 0.5))
  for i=1,ticks do
    if exists("SelectString") then break end
    yield("/wait 0.1")
  end

  local ok = wait_until(function() return exists("SelectString") and ready("SelectString") end, 5.0, 0.1)
  if ok then
    for i=1,10 do
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

  -- Defensive: make sure nothing upstream is left open
  close_addon("RetainerSellList", 80, 0.05)
  close_addon("SelectString",    80, 0.05)

  -- Now close the Retainer List itself
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
      RepriceAllOnThisRetainer(CFG.FAST.maxWaitSec, CFG.FAST.refreshAfterSec)
    end
    CloseBackToRetainerList()
    yield("/wait 0.1")
  end
  CloseRetainerList()
  yield("/echo [Repricer] All target retainers processed.")
end

------------------------------------------------------------
--Auto trigger via polling Svc.Condition[50]
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
    return Svc and Svc.Condition and Svc.Condition[50]
  end)
  if not ok then return false end
  return val and true or false
end

function AutoEnable()  AUTO_ENABLED = true;  yield("/echo [Repricer] Auto trigger ENABLED")  end
function AutoDisable() AUTO_ENABLED = false; yield("/echo [Repricer] Auto trigger DISABLED") end


yield("/echo [Repricer] AutoBell polling loop started.")
while true do
local occupied = IsBellOccupied()
local SummoningBell = GetTargetName() == "Summoning Bell"

if occupied and SummoningBell then
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
