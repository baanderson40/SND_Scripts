--[=====[
[[SND Metadata]]
version: 0.0.5
description: |
  Generic tester for /pcall on a single addon.
  Supports sweeping a START..END opcode range, plus arg2/arg3 ranges.
  Useful for probing addons (InventoryGrid, RetainerSell, InputNumeric, etc.).
[[End Metadata]]
]=====]--

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------
local ADDON_NAME     = "InventoryGrid"   -- e.g., "InventoryGrid", "RetainerSell", "InputNumeric"

-- Opcode range (inclusive)
local OPCODE_START   = 15
local OPCODE_END     = 15

-- Argument 2 range (inclusive)
local ARG2_START     = 0
local ARG2_END       = 0

-- Argument 3 range (inclusive)
-- set ARG3_START/END = nil to skip arg3 entirely
local ARG3_START     = 0
local ARG3_END       = 0

local DELAY          = 0.5               -- delay between calls (sec)

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------
local function log(msg) pcall(function() Dalamud.Log('[Tester] '..tostring(msg)) end) end
local function echo(msg) yield('/echo [Tester] '..tostring(msg)) end

local function exists(name)
  local ok,res = pcall(function() return Addons.GetAddon(name) end)
  return ok and res and res.Exists or false
end
local function ready(name)
  local ok,res = pcall(function() return Addons.GetAddon(name) end)
  return ok and res and res.Ready or false
end
local function wait_ready(name, ticks, interval)
  ticks = ticks or 80
  interval = interval or 0.05
  local t=0
  while t<ticks do
    if exists(name) and ready(name) then return true end
    yield(string.format('/wait %.2f', interval))
    t=t+1
  end
  return false
end

local function pcall_addon(op, a2, a3)
  local cmd
  if a3 ~= nil then
    cmd = string.format('/pcall %s true %d %d %d', ADDON_NAME, op, a2, a3)
  else
    cmd = string.format('/pcall %s true %d %d', ADDON_NAME, op, a2)
  end
  log('PCALL -> '..cmd)
  yield(cmd)
end

------------------------------------------------------------
-- CORE TEST
------------------------------------------------------------
local function TestArgs(op, a2, a3)
  echo(string.format(
    'Testing %s opcode=%d args=(%d%s)',
    ADDON_NAME, op, a2, (a3 and (","..a3) or "")
  ))
  pcall_addon(op, a2, a3)
  yield(string.format('/wait %.2f', DELAY))
end

local function SweepTest()
  echo(string.format(
    'Sweep %s opcode=%d..%d arg2=%d..%d%s',
    ADDON_NAME,
    OPCODE_START, OPCODE_END,
    ARG2_START, ARG2_END,
    (ARG3_START and (" arg3="..ARG3_START..".."..ARG3_END) or "")
  ))

  for op = OPCODE_START, OPCODE_END do
    if ARG3_START ~= nil and ARG3_END ~= nil then
      for a2 = ARG2_START, ARG2_END do
        for a3 = ARG3_START, ARG3_END do
          TestArgs(op, a2, a3)
        end
      end
    else
      for a2 = ARG2_START, ARG2_END do
        TestArgs(op, a2, nil)
      end
    end
  end

  echo('Sweep complete.')
end

------------------------------------------------------------
-- AUTO-RUN
------------------------------------------------------------
SweepTest()
