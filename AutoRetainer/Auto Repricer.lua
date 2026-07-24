--[=====[
[[SND Metadata]]
version: 1.0.0
description: >-
  This is a custom Lua macro script for Login Repricer. It is NOT supported by the

  plugin author(s) or by the official Dalamud / XIVLauncher / Puni.sh Discord communities.

  DO NOT ask for help with this script in Discord or support chats!

  No support will be provided by developers and will lead to a ban.

  Use at your own risk
triggers:
- onterritorychange

[[End Metadata]]
--]=====]

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------
import("System.Numerics")
echoLog = false
PREFIX  = "[Auto Repricer]"

local CFG = {
  AutoRetainer = {
    enabled    = true,
    maxWaitSec = 120,
    settleSec  = 2,
    pollSec    = 0.5, -- polling interval used by AR_WaitDone
  },
  Auto = {
    enabled      = true,  -- master toggle for auto polling mode
    debounceSec  = 3.0,   -- debounce time to avoid double-triggers
    postDelaySec = 1.0,   -- delay after detection before waiting/starting
    bellSettleSec= 0.5,   -- bell must remain occupied this long before firing
    pollSec      = 0.5,   -- main loop interval
  },
}

-- ==============================================================
-- Echo / Log Helpers (ALL code should call Log(...) / Echo(...))
-- ==============================================================
local function _echo(s)
    yield("/echo " .. tostring(s))
end

local function _log(s)
    local msg = tostring(s)
    Dalamud.Log(msg)
    if echoLog then _echo(msg) end
end

local function _fmt(msg, ...)
    return string.format("%s %s", PREFIX, string.format(msg, ...))
end

function Logf(msg, ...)   _log(_fmt(msg, ...))  end
function Echof(msg, ...)  _echo(_fmt(msg, ...)) end

Log,  log  = Logf,  Logf
Echo, echo = Echof, Echof

function EchoOnce(msg, ...)
    if echoLog then
        Log(msg, ...)
    else
        Echo(msg, ...)
        Log(msg, ...)
    end
end

-- =========================================================
-- Timing constants + Sleep
-- =========================================================
TIME = {
    POLL    = 0.20,  -- canonical polling step
    TIMEOUT = 10.0,  -- default time budget
    STABLE  = 0.30   -- default stability window
}

local function _sleep(seconds)
    local s = seconds
    if s == nil then s = 0 end
    s = tonumber(s) or 0
    if s < 0 then s = 0 end
    s = math.floor(s * 10 + 0.5) / 10
    yield("/wait " .. s)
end

Sleep, sleep = _sleep, _sleep

------------------------------------------------------------
-- UTIL
------------------------------------------------------------
local function now_s() return os.clock() end

-- WaitUntil compatible with SND Lua (no external TIME/toNumberSafe dependencies).
function WaitUntil(predicateFn, timeoutSec, pollSec, stableSec)
  timeoutSec = tonumber(timeoutSec) or 1.5
  pollSec    = tonumber(pollSec) or 0.05
  stableSec  = tonumber(stableSec) or 0.0

  local start     = os.clock()
  local holdStart = nil

  while (os.clock() - start) < timeoutSec do
    local ok, res = pcall(predicateFn)
    if ok and res then
      if not holdStart then holdStart = os.clock() end
      if (os.clock() - holdStart) >= stableSec then return true end
    else
      holdStart = nil
    end
    yield(string.format("/wait %.2f", pollSec))
  end
  return false
end

-- =========================================================
-- Addon Helpers
-- =========================================================
local function _get_addon(name)
    local ok, addon = pcall(Addons.GetAddon, name)
    if ok and addon ~= nil then
        return addon
    else
        return nil
    end
end

local function _addon_ready(a)
    if not a then return false end
    if a.Ready == true then return true end
    if a.IsReady == true then return true end
    if a.Loaded == true then return true end

    if type(a.Ready) == "function" then
        local ok, v = pcall(a.Ready, a); if ok and v then return true end
    end
    if type(a.IsReady) == "function" then
        local ok, v = pcall(a.IsReady, a); if ok and v then return true end
    end

    return false
end

local function _addon_exists(a)
    if not a then return false end
    -- common boolean fields
    if a.Exists == true then return true end
    if a.Visible == true then return true end
    if a.IsVisible == true then return true end
    if a.IsOpen == true then return true end
    if a.IsShown == true then return true end

    -- some wrappers expose functions
    if type(a.Exists) == "function" then
        local ok, v = pcall(a.Exists, a); if ok and v then return true end
    end
    if type(a.IsVisible) == "function" then
        local ok, v = pcall(a.IsVisible, a); if ok and v then return true end
    end

    -- fallback: if it's "Ready" it's effectively open
    if _addon_ready(a) then return true end
    return false
end

function IsAddonReady(name)
    local addon = _get_addon(name)
    return _addon_ready(addon)
end

function IsAddonVisible(name)
    local addon = _get_addon(name)
    return _addon_exists(addon)
end

function AwaitAddonVisible(name, timeoutSec)
    Log("awaiting visible: %s", tostring(name))
    local ok = WaitUntil(function()
        local addon = _get_addon(name)
        return _addon_exists(addon)
    end, timeoutSec or TIME.TIMEOUT, TIME.POLL, 0.0)

    if not ok then
        local a = _get_addon(name)
        Log("AwaitAddonVisible timeout: %s (addon=%s Ready=%s Exists=%s Visible=%s IsVisible=%s IsOpen=%s)",
            tostring(name),
            tostring(a),
            tostring(a and a.Ready),
            tostring(a and a.Exists),
            tostring(a and a.Visible),
            tostring(a and a.IsVisible),
            tostring(a and a.IsOpen)
        )
    end
    return ok
end

------------------------------------------------------------
-- AUTORETAINER IPC
------------------------------------------------------------
local function AR_IsAvailable()
  return (IPC and IPC.AutoRetainer) and true or false
end

-- safe call helper (no type())
local function _safe_call_field(tbl, fieldName)
  if not tbl then return false, nil end

  local okF, f = pcall(function() return tbl[fieldName] end)
  if not okF or not f then return false, nil end

  local okV, v = pcall(function() return f() end)
  if not okV then return false, nil end

  return true, v
end

local function AR_AnyAvail()
  if not (IPC and IPC.AutoRetainer) then return false end
  local ok, anyAvail = _safe_call_field(IPC.AutoRetainer, "AreAnyRetainersAvailableForCurrentChara")
  return ok and anyAvail and true or false
end

local function AR_BusySignal()
  if not (IPC and IPC.AutoRetainer) then return false end
  local ok, busy = _safe_call_field(IPC.AutoRetainer, "IsBusy")
  return ok and busy and true or false
end

-- "Busy" if EITHER signal says so.
local function AR_IsBusy()
  return AR_BusySignal() or AR_AnyAvail()
end

-- Idle only when BOTH are false, stable for settleSec.
function EnsureAutoRetainerIdle(maxWaitSec, settleSec, pollSec)
  if not CFG.AutoRetainer.enabled then return true end
  if not AR_IsAvailable() then return true end

  maxWaitSec = maxWaitSec or CFG.AutoRetainer.maxWaitSec
  settleSec  = settleSec  or CFG.AutoRetainer.settleSec
  pollSec    = pollSec    or CFG.AutoRetainer.pollSec

  local waited = 0.0
  while waited < maxWaitSec do
    if (not AR_BusySignal()) and (not AR_AnyAvail()) then
      local idle = 0.0
      local stable = true
      while idle < settleSec do
        if AR_BusySignal() or AR_AnyAvail() then stable = false; break end
        yield(string.format("/wait %.2f", pollSec))
        idle = idle + pollSec
      end
      if stable then
        Log(string.format("AutoRetainer idle confirmed (%.1fs quiet).", settleSec))
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
-- BELL STATE
------------------------------------------------------------
-- Bell occupied: rely on condition only. Target name is not stable while interacting.
local function IsBellOccupied()
  local ok, val = pcall(function()
    return Svc and Svc.Condition and Svc.Condition[50]
  end)
  return ok and val and true or false
end

local function IsBellSessionActive()
  return IsBellOccupied() and IsAddonVisible("RetainerList")
end

------------------------------------------------------------
-- AUTO POLLING LOOP
------------------------------------------------------------
local AUTO_ENABLED       = CFG.Auto.enabled
local AUTO_DEBOUNCE_SEC  = CFG.Auto.debounceSec
local BELL_SETTLE_SEC    = CFG.Auto.bellSettleSec
local POST_DELAY_SEC     = CFG.Auto.postDelaySec

local _auto_in_progress  = false
local _auto_last_fire_t  = 0.0
local _bell_since        = 0.0

local function _auto_can_fire()
  if not AUTO_ENABLED then return false end
  if _auto_in_progress then return false end
  if (now_s() - _auto_last_fire_t) < AUTO_DEBOUNCE_SEC then return false end
  return true
end

EchoOnce("polling loop started.")
while true do

  local occupied = IsBellOccupied()
  local ar_busy = AR_IsBusy()

  if occupied and ar_busy then
    if _bell_since == 0 then _bell_since = now_s() end

    if _auto_can_fire() and (now_s() - _bell_since) >= BELL_SETTLE_SEC then
      _auto_in_progress = true
      Log("bell occupied (AR work detected) — preparing to start…")
      Sleep(POST_DELAY_SEC)

      if not EnsureAutoRetainerIdle() then
        Log("AutoRetainer stayed busy past timeout; skipping trigger.")
        _auto_in_progress = false
      else
        if IsBellSessionActive() or WaitUntil(IsBellSessionActive, 5, TIME.POLL, 0.0) then
            Log("starting Retainer Repricer")
            yield("/repricer start")
        else
            Log("failed to open bell Summoning Bell")
            return
        end

        _auto_last_fire_t = now_s()
        _auto_in_progress = false
        Log("run finished.")
      end

        -- Wait until bell is no longer occupied before allowing another run
        repeat
          Sleep(TIME.POLL)
        until not IsBellOccupied()
        _bell_since = 0.0
    end
  else
    _bell_since = 0.0
  end

  Sleep(TIME.POLL)
end
