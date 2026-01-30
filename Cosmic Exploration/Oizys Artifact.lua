--[=====[
[[SND Metadata]]
author: baanderson40
version: 0.0.7
description: Automatic purchase Oizys Drone Modules, retrive artifacts, and appraise ancient records.
plugin_dependencies:
- vnavmesh
- TextAdvance

[[End Metadata]]
--]=====]

-- =========================================================
-- Config
-- =========================================================
import("System.Numerics")
echoLog = false
PREFIX  = "[Oizys Artifact]"

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
    POLL    = 0.10,  -- canonical polling step
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

-- =========================================================
-- Number helper (parsing + optional clamping)
-- =========================================================
function toNumberSafe(s, default, min, max)
    if s == nil then return default end
    local str = tostring(s):gsub("[^%d%-%.]", "")
    local n = tonumber(str)  -- force only one argument
    if n == nil then return default end
    if min ~= nil and n < min then n = min end
    if max ~= nil and n > max then n = max end
    return n
end

-- =========================================================
-- Inventory / Item Helper
-- =========================================================
local function ItemCount(itemId)
    return tonumber(Inventory.GetItemCount(itemId)) or 0
end

local function ItemUse(itemId)
    local it = Inventory.GetInventoryItem(itemId)
    if it then it:Use() end
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

function IsAddonReady(name)
    local addon = _get_addon(name)
    return addon and addon.Ready or false
end

function IsAddonVisible(name)
    local addon = _get_addon(name)
    return addon and addon.Exists or false
end

-- =========================================================
-- WaitUntil Helper
-- =========================================================
-- Usage Recap:
-- WaitUntil(predicateFn, timeoutSec, pollSec, stableSec)
--
--   predicateFn : function() -> true/false  (checked each poll)
--   timeoutSec  : max seconds before giving up (default 10)
--   pollSec     : seconds between checks (default 0.10)
--   stableSec   : must remain true for this many seconds
--                 continuously before success (default 0)
--
-- Returns: true if condition satisfied, false on timeout
--
-- Examples:
--   Wait until addon "Talk" is ready (10s max):
--     WaitUntil(function()
--         local addon = _get_addon("Talk")
--         return addon and addon.Ready
--     end, 10.0)
--
--   Wait until crafting condition holds for 2s (15s max):
--     WaitUntil(function()
--         return GetCharacterCondition(CharacterCondition.crafting, true)
--     end, 15.0, 0.10, 2.0)
--
--   Quick one-off wait (target = "NPC Bob"):
--     WaitUntil(function()
--         return Entity.Target and Entity.Target.Name == "NPC Bob"
--     end, 5.0, 0.10)
--
function WaitUntil(predicateFn, timeoutSec, pollSec, stableSec)
    timeoutSec = toNumberSafe(timeoutSec, TIME.TIMEOUT, 0.1)
    pollSec    = toNumberSafe(pollSec,    TIME.POLL,   0.01)
    stableSec  = toNumberSafe(stableSec,  TIME.STABLE, 0.0)

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
        sleep(pollSec)
    end
    return false
end

function AwaitAddonReady(name, timeoutSec)
    Log("awaiting ready: %s", tostring(name))
    local ok = WaitUntil(function()
        local addon = _get_addon(name)
        return addon and addon.Ready
    end, timeoutSec or TIME.TIMEOUT, TIME.POLL, 0.0)
    if not ok then Log("AwaitAddonReady timeout: %s", tostring(name)) end
    return ok
end

function AwaitAddonVisible(name, timeoutSec)
    Log("awaiting visible: %s", tostring(name))
    local ok = WaitUntil(function()
        local addon = _get_addon(name)
        return addon and addon.Exists
    end, timeoutSec or TIME.TIMEOUT, TIME.POLL, 0.0)
    if not ok then Log("AwaitAddonVisible timeout: %s", tostring(name)) end
    return ok
end

function WaitAddonStable(addonName, stableSec, timeoutSec, pollSec)
    return WaitUntil(function()
        local addon = _get_addon(addonName)
        return addon and addon.Exists
    end, timeoutSec or TIME.TIMEOUT, pollSec or TIME.POLL, stableSec or 2.0)
end

function WaitConditionStable(idx, want, stableSec, timeoutSec, pollSec)
    want       = (want ~= false)
    stableSec  = toNumberSafe(stableSec,  2.0,   0.0)
    timeoutSec = toNumberSafe(timeoutSec, 15.0,  0.1)
    pollSec    = toNumberSafe(pollSec,    TIME.POLL, 0.01)

    if not (Svc and Svc.Condition) then
        Log("WaitConditionStable: Svc.Condition unavailable")
        return false
    end

    local ok = WaitUntil(function()
        return GetCharacterCondition(idx, want)
    end, timeoutSec, pollSec, stableSec)

    if not ok then
        Log("WaitConditionStable: timeout (idx=%s want=%s stable=%.2fs)",
            tostring(idx), tostring(want), stableSec)
    end
    return ok
end

-- =========================================================
-- Node Helpers (path = {i,j,k})
-- =========================================================
local _unpack = table.unpack or unpack

local function _get_node(addonName, path)
    if type(path) ~= "table" then return nil end
    local addon = _get_addon(addonName)
    if not (addon and addon.Ready) then return nil end
    local ok, node = pcall(function() return addon:GetNode(_unpack(path)) end)
    if ok then return node end
    return nil
end

-- matcher can be:
--   1) function(text) -> true/false (preferred)
--   2) string 'expected' + mode ('equals'|'contains'|'pattern') + caseInsensitive
function AwaitAddonNodeVisible(addonName, timeoutSec, path, expectedOrMatcher, mode, caseInsensitive)
    if type(addonName) ~= "string" or addonName == "" then
        Log("AwaitAddonNodeVisible: invalid addonName '%s'", tostring(addonName)); return false
    end
    if type(path) ~= "table" or #path == 0 then
        Log("AwaitAddonNodeVisible: invalid path for %s", addonName); return false
    end
    Log("awaiting node visible: %s", addonName)

    if type(expectedOrMatcher) == "function" then
        local ok = WaitUntil(function()
            local node = _get_node(addonName, path)
            return node and node.IsVisible and expectedOrMatcher(tostring(node.Text or ""))
        end, timeoutSec or TIME.TIMEOUT, TIME.POLL, 0.0)

        if not ok then
            local node = _get_node(addonName, path)
            local lastText = node and tostring(node.Text or "") or ""
            Log("AwaitAddonNodeVisible timeout: %s (last Text='%s')", tostring(addonName), lastText)
        end
        return ok
    end

    local expected = expectedOrMatcher
    mode = mode or "equals"
    if caseInsensitive == nil then caseInsensitive = true end

    local lower, find = string.lower, string.find
    local rhs = tostring(expected or "")
    local rhsCI = caseInsensitive and lower(rhs) or rhs

    local function matches(text)
        if expected == nil then return true end
        local lhs = tostring(text or "")
        local lhsCI = caseInsensitive and lower(lhs) or lhs
        if mode == "equals"   then return lhsCI == rhsCI end
        if mode == "contains" then return (find(lhsCI, rhsCI, 1, true) ~= nil) end
        if mode == "pattern"  then return (find(lhsCI, rhsCI) ~= nil) end
        return lhsCI == rhsCI
    end

    local ok = WaitUntil(function()
        local node = _get_node(addonName, path)
        return node and node.IsVisible and matches(node.Text)
    end, timeoutSec or TIME.TIMEOUT, TIME.POLL, 0.0)

    if not ok then
        local node = _get_node(addonName, path)
        local lastText = node and tostring(node.Text or "") or ""
        Log("AwaitAddonNodeVisible timeout: %s (last Text='%s')", tostring(addonName), lastText)
    end
    return ok
end

function IsNodeVisible(addonName, path)
    local node = _get_node(addonName, path)
    return node and node.IsVisible or false
end

function GetNodeText(addonName, path, waitSec)
    waitSec = toNumberSafe(waitSec, 0, 0)
    if waitSec > 0 and not AwaitAddonReady(addonName, waitSec) then return "" end
    local node = _get_node(addonName, path)
    return node and tostring(node.Text or "") or ""
end

function GetNodeType(addonName, path, waitSec)
    waitSec = toNumberSafe(waitSec, 0, 0)
    if waitSec > 0 and not AwaitAddonReady(addonName, waitSec) then return "" end
    local node = _get_node(addonName, path)
    return node and tostring(node.NodeType or "") or ""
end

function GetMyNode(addonName, index)
    local addon = _get_addon(addonName)
    if not (addon and addon.Ready) then return nil end
    local nodes = addon.Nodes
    return nodes and nodes[index] or nil
end

-- =========================================================
-- Character / Mount / Target / Position Helpers
-- =========================================================
function GetCharacterCondition(i, bool)
    if bool == nil then bool = true end
    return Svc and Svc.Condition and (Svc.Condition[i] == bool) or false
end

function WaitConditionStable(idx, want, stableSec, timeoutSec, pollSec)
    want       = (want ~= false)
    stableSec  = tonumber(stableSec)  or 2.0
    timeoutSec = tonumber(timeoutSec) or 15.0
    pollSec    = tonumber(pollSec)    or TIME.POLL

    if not (Svc and Svc.Condition) then
        log("WaitConditionStable: Svc.Condition unavailable"); return false
    end

    local t, startHold = 0.0, nil
    while t < timeoutSec do
        local ok = GetCharacterCondition(idx, want)
        if ok then
            if not startHold then startHold = t end
            if (t - startHold) >= stableSec then return true end
        else
            startHold = nil
        end
        sleep(pollSec); t = t + pollSec
    end

    Log(string.format("WaitConditionStable timeout (idx=%s want=%s stable=%.2fs)",
        tostring(idx), tostring(want), stableSec))
    return false
end

function GetCharacterName()
    return (Entity and Entity.Player and Entity.Player.Name)
end

function GetCharacterCondition(i, bool)
    if bool == nil then bool = true end
    return Svc and Svc.Condition and (Svc.Condition[i] == bool) or false
end

function GetCharacterPosition()
    local player = Svc and Svc.ClientState and Svc.ClientState.LocalPlayer
    return player and player.Position or nil
end

function GetCharacterJob()
    return Player and Player.Job or nil
end

function GetZoneId()
    local cs = Svc and Svc.ClientState
    return cs and cs.TerritoryType or nil
end

function Mount()
    if not Svc.Condition[CharacterCondition.mounted] then
        yield('/gaction "mount roulette"')
    end
end

function Dismount()
    if Svc.Condition[CharacterCondition.mounted] then
        yield('/ac dismount')
    end
end

-- =========================================================
-- Distance Helpers
-- =========================================================
function GetTargetName()
    return (Entity and Entity.Target and Entity.Target.Name) or ""
end

function GetDistanceToTarget()
    if not (Entity and Entity.Player and Entity.Target) then return math.huge end
    return Vector3.Distance(Entity.Player.Position, Entity.Target.Position)
end

function DistanceBetweenPositions(pos1, pos2)
    if not (pos1 and pos2) then return math.huge end
    return Vector3.Distance(pos1, pos2)
end

function IsWithinDistance(pos1, pos2, maxDist)
    if not (pos1 and pos2 and maxDist) then return false end
    local distSq
    if Vector3.DistanceSquared then
        distSq = Vector3.DistanceSquared(pos1, pos2)
    else
        local dx, dy, dz = (pos1.X - pos2.X), (pos1.Y - pos2.Y), (pos1.Z - pos2.Z)
        distSq = dx*dx + dy*dy + dz*dz
    end
    return distSq <= (maxDist * maxDist)
end

function IsTargetWithin(maxDist)
    if not (Entity and Entity.Player and Entity.Target and maxDist) then return false end
    return IsWithinDistance(Entity.Player.Position, Entity.Target.Position, maxDist)
end

-- =========================================================
-- Interaction Helper
-- =========================================================
function InteractByName(name, timeout)
    if type(name) ~= "string" or name == "" then
        Log("InteractByName: invalid name '%s'", tostring(name)); return false
    end
    timeout = toNumberSafe(timeout, 5, 0.1)

    local e = Entity and Entity.GetEntityByName and Entity.GetEntityByName(name)
    if not e then
        Log("InteractByName: entity not found '%s'", name); return false
    end

    local start = os.clock()
    while (os.clock() - start) < timeout do
        e:SetAsTarget()
        sleep(TIME.POLL)
        local tgt = Entity and Entity.Target
        if tgt and tgt.Name == name then
            e:Interact()
            return true
        end
        sleep(TIME.POLL)
    end
    Log("InteractByName: timeout '%s'", name)
    return false
end

-- =========================================================
-- Safe Callback
-- =========================================================
local function _quoteArg(s)
    s = tostring(s)
    s = s:gsub("\\", "\\\\"):gsub('"', '\\"')
    return '"' .. s .. '"'
end

function SafeCallback(...)
    local args = {...}
    local idx  = 1
    local addon = args[idx]; idx = idx + 1
    if type(addon) ~= "string" or addon == "" then
        Log("SafeCallback: invalid addon name"); return false
    end

    local update = args[idx]; idx = idx + 1
    local updateStr = "true"
    if type(update) == "boolean" then
        updateStr = update and "true" or "false"
    elseif type(update) == "string" then
        local s = update:lower()
        if s == "false" or s == "f" or s == "0" or s == "off" then updateStr = "false" end
    else
        idx = idx - 1
    end

    local call = "/callback " .. addon .. " " .. updateStr
    for i = idx, #args do
        local v = args[i]
        local t = type(v)
        if t == "number" then
            call = call .. " " .. tostring(v)
        elseif t == "boolean" then
            call = call .. " " .. (v and "true" or "false")
        elseif t == "string" then
            call = call .. " " .. _quoteArg(v)
        else
            Log("SafeCallback: ignoring unsupported arg #%d (type=%s)", i, t)
        end
    end

    Log("calling: %s", call)
    if IsAddonReady(addon) and IsAddonVisible(addon) then
        yield(call)
        return true
    else
        Log("SafeCallback: addon not ready/visible: %s", addon)
        return false
    end
end

-- =========================================================
-- Plugin helpers
-- =========================================================
function HasPlugin(name)
    for plugin in luanet.each(Svc.PluginInterface.InstalledPlugins) do
        if plugin.InternalName == name and plugin.IsLoaded then return true end
    end
    return false
end

function GetPlugins()
    local plugins = {}
    for plugin in luanet.each(Svc.PluginInterface.InstalledPlugins) do
        table.insert(plugins, { name = plugin.InternalName, loaded = plugin.IsLoaded })
    end
    table.sort(plugins, function(a,b) return a.name:lower() < b.name:lower() end)

    Log("Installed plugins:")
    for _, p in ipairs(plugins) do
        Log("  %s | Enabled: %s", p.name, tostring(p.loaded))
    end
end

changedTextAdvance = false
textAdvanceOriginalState = nil
function ToggleTextAdvance(wanted)
    local desired = nil

    if wanted == "enable" then
        desired = true
    elseif wanted == "disable" then
        desired = false
    elseif wanted == "restore" then
        if changedTextAdvance and textAdvanceOriginalState ~= nil then
            local current = IPC.TextAdvance.IsEnabled()
            if current ~= textAdvanceOriginalState then
                Log("TextAdvance: restoring enabled=%s", tostring(textAdvanceOriginalState))
                yield(textAdvanceOriginalState and "/at yes" or "/at no")
            else
                Log("TextAdvance: already in original state")
            end
        end

        changedTextAdvance = false
        textAdvanceOriginalState = nil
        return
    else
        Log("TextAdvance: invalid wanted=%s (use enable|disable|restore)", tostring(wanted))
        return
    end

    local current = IPC.TextAdvance.IsEnabled()

    if textAdvanceOriginalState == nil then
        textAdvanceOriginalState = current
    end

    if current ~= desired then
        Log("TextAdvance: setting enabled=%s (script-owned)", tostring(desired))
        yield(desired and "/at yes" or "/at no")
        changedTextAdvance = true
    else
        Log("TextAdvance: already enabled=%s (no change)", tostring(desired))
    end
end

changedYesAlready = false
yesAlreadyOriginalState = nil
function ToggleYesAlready(wanted)
    local desired = nil

    if wanted == "enable" then
        desired = true
    elseif wanted == "disable" then
        desired = false
    elseif wanted == "restore" then
        -- restore only if we changed it
        if changedYesAlready and yesAlreadyOriginalState ~= nil then
            local current = IPC.YesAlready.IsPluginEnabled()
            if current ~= yesAlreadyOriginalState then
                Log("YesAlready: restoring enabled=%s", tostring(yesAlreadyOriginalState))
                IPC.YesAlready.SetPluginEnabled(yesAlreadyOriginalState)
            else
                Log("YesAlready: already in original state")
            end
        end

        changedYesAlready = false
        yesAlreadyOriginalState = nil
        return
    else
        Log("YesAlready: invalid wanted=%s (use enable|disable|restore)", tostring(wanted))
        return
    end

    local current = IPC.YesAlready.IsPluginEnabled()

    if yesAlreadyOriginalState == nil then
        yesAlreadyOriginalState = current
    end

    if current ~= desired then
        Log("YesAlready: setting enabled=%s (script-owned)", tostring(desired))
        IPC.YesAlready.SetPluginEnabled(desired)
        changedYesAlready = true
    else
        Log("YesAlready: already enabled=%s (no change)", tostring(desired))
    end
end

-- =========================================================
-- VNAV Helpers
-- =========================================================
function PathandMoveVnav(dest, fly)
    fly = (fly == true)
    local t, timeout = 0, TIME.TIMEOUT
    while not IPC.vnavmesh.IsReady() and t < timeout do
        sleep(TIME.POLL); t = t + TIME.POLL
    end
    if not IPC.vnavmesh.IsReady() then
        log("%s VNAV not ready (timeout)", PREFIX)
        return false
    end

    local ok = IPC.vnavmesh.PathfindAndMoveTo(dest, fly)
    if not ok then
        log("%s VNAV pathfind failed", PREFIX)
    end

    if ok then
        local me = Entity and Entity.Player
        if me and me.Position and Vector3.Distance(me.Position, dest) > 25 then
            Mount()
        end
    end
    return ok and true or false
end

function StopCloseVnav(dest, stopDistance)
    stopDistance = tonumber(stopDistance) or 3.0
    if not dest then return false end

    local t, timeout = 0, TIME.TIMEOUT
    while not IPC.vnavmesh.IsRunning() and t < timeout do
        sleep(TIME.POLL); t = t + TIME.POLL
    end
    if not IPC.vnavmesh.IsRunning() then
        log("%s VNAV not running (timeout)", PREFIX)
        return false
    end

    while IPC.vnavmesh.IsRunning() do
        local me = Entity and Entity.Player
        if me and me.Position then
            if OnCosmoLiner() then
                IPC.vnavmesh.Stop()
                return false
            end

            if Vector3.Distance(me.Position, dest) < 20
                and GetCharacterCondition(CharacterCondition.mounted) then
                Dismount()
            end
            if Vector3.Distance(me.Position, dest) < stopDistance then
                IPC.vnavmesh.Stop()
                return true
            end
        end
        sleep(TIME.POLL)
    end

    return true
end

function MoveNearVnav(dest, stopDistance, fly)
    stopDistance = tonumber(stopDistance) or 3.0
    if PathandMoveVnav(dest, fly) then
        return StopCloseVnav(dest, stopDistance)
    end
    return false
end

-- =========================================================
-- Excel Sheet Lookups (guarded, return {ok,value|err})
-- =========================================================
local function ok(v)  return true, v end
local function err(m) return false, tostring(m or "unknown error") end

function GetENpcResidentName(dataId)
    local id = toNumberSafe(dataId, nil)
    if not id then return err("ENpcResident: invalid id '"..tostring(dataId).."'") end

    local sheet = Excel.GetSheet("ENpcResident")
    if not sheet then return err("ENpcResident sheet not available") end

    local row = sheet:GetRow(id)
    if not row then return err("ENpcResident: no row for id "..tostring(id)) end

    local name = row.Singular or row.Name
    if not name or name == "" then return err("ENpcResident: name missing for id "..tostring(id)) end

    return ok({ name = tostring(name), source = "ENpcResident", id = id })
end

function BuildJobTable(firstId, lastId)
    firstId = toNumberSafe(firstId, 1, 1)
    lastId  = toNumberSafe(lastId,  100, firstId)

    local sheet = Excel.GetSheet("ClassJob")
    if not sheet then return err("ClassJob sheet not found") end

    local job, missing = {}, {}
    for id = firstId, lastId do
        local row = sheet:GetRow(id)
        if row then
            local name = row.Name or row["Name"]
            local abbr = row.Abbreviation or row["Abbreviation"]
            if name and abbr then
                job[id] = { name = tostring(name), abbr = tostring(abbr) }
            else
                table.insert(missing, ("id=%d missing Name/Abbreviation"):format(id))
            end
        else
            table.insert(missing, ("id=%d row not found"):format(id))
        end
    end

    if next(job) == nil then
        return err("ClassJob table empty; " .. table.concat(missing, "; "))
    end
    return ok({ map = job, warnings = (#missing > 0) and missing or nil })
end

function PlaceNameByTerritory(id)
    local tid = toNumberSafe(id, nil, 1)
    if not tid then return err("invalid territory id: "..tostring(id)) end

    local terr = Excel.GetSheet("TerritoryType"); if not terr then return err("TerritoryType sheet not found") end
    local row  = terr:GetRow(tid);                if not row  then return err("TerritoryType row not found for id "..tid) end

    local pn = row.PlaceName
    if not pn then return err("PlaceName field missing for territory id "..tid) end

    if type(pn) == "string" and #pn > 0 then
        return ok({ name = pn, territoryId = tid, source = "TerritoryType.PlaceName:string" })
    end

    if type(pn) == "userdata" then
        local okv, val = pcall(function() return pn.Value end)
        if okv and val then
            local okn, nm = pcall(function() return val.Singular or val.Name or val:ToString() end)
            if okn and nm and nm ~= "" then
                return ok({ name = tostring(nm), territoryId = tid, source = "TerritoryType.PlaceName:userdata.Value" })
            end
        end
        local okid, rid = pcall(function() return pn.RowId end)
        if okid and type(rid) == "number" then
            local place = Excel.GetSheet("PlaceName"); if not place then return err("PlaceName sheet not found (RowId="..tostring(rid)..")") end
            local prow  = place:GetRow(rid);          if not prow  then return err("PlaceName row not found (RowId="..tostring(rid)..")") end
            local okn2, nm2 = pcall(function() return prow.Singular or prow.Name or prow:ToString() end)
            if okn2 and nm2 and nm2 ~= "" then
                return ok({ name = tostring(nm2), territoryId = tid, source = "PlaceName(RowId)" })
            end
            return err("PlaceName values empty (RowId="..tostring(rid)..")")
        end
        return err("unsupported PlaceName userdata shape for territory id "..tid)
    end

    if type(pn) == "number" then
        local place = Excel.GetSheet("PlaceName"); if not place then return err("PlaceName sheet not found") end
        local prow  = place:GetRow(pn);            if not prow  then return err("PlaceName row not found (id="..tostring(pn)..")") end
        local okn, nm = pcall(function() return prow.Singular or prow.Name or prow:ToString() end)
        if okn and nm and nm ~= "" then
            return ok({ name = tostring(nm), territoryId = tid, source = "PlaceName(numeric)" })
        end
        return err("PlaceName values empty (id="..tostring(pn)..")")
    end

    return err("unsupported PlaceName type: "..type(pn))
end

function GetZoneName(territoryType)
    local okRes, dataOrErr = PlaceNameByTerritory(territoryType)
    if not okRes then return false, "GetZoneName: " .. dataOrErr end
    return true, dataOrErr.name
end

-- =========================================================
-- Gearset cache
-- =========================================================
local _gearsetCache = nil
local _gearsetStamp = nil

function BuildGearsetTable(force)
    if _gearsetCache and not force then
        return _gearsetCache
    end

    local gearset = {}
    for idx = 1, 100 do
        local gs = Player.GetGearset(idx)
        if gs and gs.ClassJob and gs.ClassJob > 0 and gs.Name and gs.Name ~= "" then
            gearset[gs.ClassJob] = { index = idx, name = gs.Name }
        end
    end

    _gearsetCache = gearset
    _gearsetStamp = os.clock()
    return gearset
end

function InvalidateGearsetCache()
    _gearsetCache = nil
    _gearsetStamp = nil
    Log("Gearset cache invalidated")
end

-- =========================================================
-- Trigger Events
-- =========================================================
function OnStop()
    ToggleTextAdvance("restore")
    ToggleYesAlready("restore")
end

-- =========================================================
-- Script Settings 
-- =========================================================
CharacterCondition = {
    normalConditions                   = 1,
    dead                               = 2,
    emoting                            = 3,
    mounted                            = 4,
    crafting                           = 5,
    gathering                          = 6,
    meldingMateria                     = 7,
    operatingSiegeMachine              = 8,
    carryingObject                     = 9,
    mounted2                           = 10,
    inThatPosition                     = 11,
    chocoboRacing                      = 12,
    playingMiniGame                    = 13,
    playingLordOfVerminion             = 14,
    participatingInCustomMatch         = 15,
    performing                         = 16,
    occupied                           = 25,
    inCombat                           = 26,
    casting                            = 27,
    sufferingStatusAffliction          = 28,
    sufferingStatusAffliction2         = 29,
    occupied30                         = 30,
    occupiedInEvent                    = 31,
    occupiedInQuestEvent               = 32,
    occupied33                         = 33,
    boundByDuty34                      = 34,
    occupiedInCutSceneEvent            = 35,
    inDuelingArea                      = 36,
    tradeOpen                          = 37,
    occupied38                         = 38,
    occupiedMateriaExtractionAndRepair = 39,
    executingCraftingAction            = 40,
    preparingToCraft                   = 41,
    executingGatheringAction           = 42,
    fishing                            = 43,
    betweenAreas                       = 45,
    stealthed                          = 46,
    jumping48                          = 48,
    autorunActive                      = 49,
    usingChocoboTaxi                   = 49,
    occupiedSummoningBell              = 50,
    betweenAreasForDuty                = 51,
    systemError                        = 52,
    loggingOut                         = 53,
    conditionLocation                  = 54,
    waitingForDuty                     = 55,
    boundByDuty56                      = 56,
    mounting57                         = 57,
    watchingCutscene                   = 58,
    waitingForDutyFinder               = 59,
    creatingCharacter                  = 60,
    jumping61                          = 61,
    pvpDisplayActive                   = 62,
    sufferingStatusAffliction63        = 63,
    mounting64                         = 64,
    carryingItem                       = 65,
    usingPartyFinder                   = 66,
    usingHousingFunctions              = 67,
    transformed                        = 68,
    onFreeTrial                        = 69,
    beingMoved                         = 70,
    mounting71                         = 71,
    sufferingStatusAffliction72        = 72,
    sufferingStatusAffliction73        = 73,
    registeringForRaceOrMatch          = 74,
    waitingForRaceOrMatch              = 75,
    waitingForTripleTriadMatch         = 76,
    flying                             = 77,
    watchingCutscene78                 = 78,
    inDeepDungeon                      = 79,
    swimming                           = 80,
    diving                             = 81,
    registeringForTripleTriadMatch     = 82,
    waitingForTripleTriadMatch83       = 83,
    participatingInCrossWorldPartyOrAlliance = 84,
    unknown85                          = 85,
    dutyRecorderPlayback               = 86,
    casting87                          = 87,
    inThisState88                      = 88,
    inThisState89                      = 89,
    rolePlaying                        = 90,
    boundToDuty97                      = 91,
    inDutyQueue                        = 91,
    readyingVisitOtherWorld            = 92,
    waitingToVisitOtherWorld           = 93,
    usingFashionAccessory              = 94,
    boundByDuty95                      = 95,
    unknown96                          = 96,
    disguised                          = 97,
    recruitingWorldOnly                = 98,
    unknown99                          = 99,
    editingPortrait                    = 100,
    unknown101                         = 101,
    pilotingMech                       = 102,
}

-- =========================================================
-- Variable States
-- =========================================================
oizysDroneModule = {name = "Oizys Drone Module", itemId = 50414, price = 200 }
artifactNPC = { name = "Kaede", position = Vector3(-206.378, 0.500, 131.090) }

local cosmoWasOn = false

-- =========================================================
-- STATE MACHINE
-- =========================================================
STATE = {
    READY              = "READY",
    RETURN_BASE        = "RETURN_BASE",
    MODULE_PURCHASE    = "MODULE_PURCHASE",
    MODULE_USE         = "MODULE_USE",
    ARTIFACT_INTERACT  = "ARTIFACT_INTERACT",
    TURNIN_FLOW        = "TURNIN_FLOW",
    DONE               = "DONE",
    FAIL               = "FAIL",
}

local sm = { s = STATE.READY, t0 = os.clock() }

local function gotoState(s)
    sm.s = s
    sm.t0 = os.clock()
    Log("STATE -> %s", s)
end

local function timedOut(sec)
    return (os.clock() - sm.t0) > sec
end

-- =========================================================
-- Helpers specific to this flow
-- =========================================================
local BASE_POS = artifactNPC.position

local function getBits()
    return toNumberSafe(GetNodeText("WKSHud", {1,15,18,3}), 0, 0)
end

local function artifactEntity()
    return Entity.GetEntityByName("Artifact")
end

local function artifactActive()
    return artifactEntity() ~= nil
end

local function WaitEntityByName(name, timeoutSec)
    timeoutSec = toNumberSafe(timeoutSec, 5.0, 0.1)
    return WaitUntil(function()
        return Entity.GetEntityByName(name) ~= nil
    end, timeoutSec, TIME.POLL, 0.2)
end

local function WaitEntityGone(name, timeoutSec)
    timeoutSec = toNumberSafe(timeoutSec, 5.0, 0.1)
    return WaitUntil(function()
        return Entity.GetEntityByName(name) == nil
    end, timeoutSec, TIME.POLL, 0.2)
end

local function shouldReturnBaseBeforeArtifact()
    local art = artifactEntity()
    if not (art and art.Position) then return false end
    local me = Entity and Entity.Player
    if not (me and me.Position) then return false end
    return Vector3.Distance(me.Position, art.Position)
         > Vector3.Distance(BASE_POS, art.Position)
end

local function DistanceToBase()
    local me = Entity and Entity.Player
    if not (me and me.Position) then return math.huge end
    return Vector3.Distance(me.Position, BASE_POS)
end

local function StellarReturn()
    yield('/gaction "Duty Action"')
    sleep(4)
    return WaitConditionStable(45, false, 2, 10)
end

function OnCosmoLiner()
    return GetCharacterCondition(CharacterCondition.watchingCutscene)
       and GetCharacterCondition(CharacterCondition.unknown101)
end

-- =========================================================
-- Ancient Record helpers
-- =========================================================
ancientRecords = { 50411, 50412, 50413 } -- gold, silver, bronze

local RECORD_TO_LISTCOL = {
    [50413] = 0, -- bronze
    [50412] = 1, -- silver
    [50411] = 2, -- gold
}

local function AncientRecordCount()
    local total = 0
    for _, id in ipairs(ancientRecords) do
        total = total + ItemCount(id)
    end
    return total
end

local function NextAncientRecord()
    local order = { 50411, 50412, 50413 } -- gold -> silver -> bronze
    for _, id in ipairs(order) do
        if ItemCount(id) > 0 then
            return id, RECORD_TO_LISTCOL[id]
        end
    end
    return nil, nil
end

-- =========================================================
-- Main Loop
-- =========================================================
EchoOnce("Starting Oizys Artifact script.")
ToggleTextAdvance("enable") -- Enable TextAdvance if not
if HasPlugin("YesAlready") then ToggleYesAlready("disable") end -- Disable YesAlready if installed

while sm.s ~= STATE.DONE and sm.s ~= STATE.FAIL do
    if OnCosmoLiner() then
        cosmoWasOn = true
        Sleep(TIME.POLL)
        goto continue
    elseif cosmoWasOn then
        cosmoWasOn = false
        Sleep(TIME.STABLE)
    end

    -- ======================
    -- READY
    -- ======================
    if sm.s == STATE.READY then
        local bits    = getBits()
        local price   = toNumberSafe(oizysDroneModule.price, 0, 0)
        local modules = ItemCount(oizysDroneModule.itemId)

        if price > 0 and bits >= price then
            gotoState(STATE.MODULE_PURCHASE)

        elseif artifactActive() then
            gotoState(shouldReturnBaseBeforeArtifact() and STATE.RETURN_BASE
                      or STATE.ARTIFACT_INTERACT)

        elseif modules > 0 then
            gotoState(STATE.MODULE_USE)

        elseif AncientRecordCount() > 0 then
            gotoState(STATE.TURNIN_FLOW)

        else
            gotoState(STATE.DONE)
        end

    -- ======================
    -- RETURN_BASE
    -- ======================
    elseif sm.s == STATE.RETURN_BASE then
        if StellarReturn() then
            Sleep(TIME.POLL)
        else
            MoveNearVnav(BASE_POS, 3.0, false)
        end
        gotoState(STATE.ARTIFACT_INTERACT)
        Sleep(0.3)

    -- ======================
    -- MODULE_PURCHASE
    -- ======================
    elseif sm.s == STATE.MODULE_PURCHASE then
        MoveNearVnav(artifactNPC.position, 3.0, false)
        InteractByName(artifactNPC.name)

        local bits  = getBits()
        local price = toNumberSafe(oizysDroneModule.price, 0, 0)
        local purchase = (price > 0) and math.floor(bits / price) or 0

        if AwaitAddonReady("SelectString", 5) then
            SafeCallback("SelectString", 0)

            if purchase > 0 and AwaitAddonReady("ShopExchangeCurrency", 5) then
                SafeCallback("ShopExchangeCurrency", 0, 0, purchase)
                Sleep(TIME.STABLE)
            end

            if purchase > 0 and AwaitAddonReady("SelectYesno", 5) then
                SafeCallback("SelectYesno", 0)
                Sleep(TIME.STABLE)
            end

            if AwaitAddonVisible("ShopExchangeCurrency", 5) then
                SafeCallback("ShopExchangeCurrency", -1)
                Sleep(TIME.STABLE)
            end

            gotoState(STATE.READY)
            Sleep(TIME.STABLE)
        elseif timedOut(8) then
            gotoState(STATE.FAIL)
        end

    -- ======================
    -- MODULE_USE
    -- ======================
    elseif sm.s == STATE.MODULE_USE then
        if artifactActive() then
            gotoState(shouldReturnBaseBeforeArtifact() and STATE.RETURN_BASE
                    or STATE.ARTIFACT_INTERACT)
        else
            local usedOk = false

            local count = ItemCount(oizysDroneModule.itemId)
            if count <= 0 then
                gotoState(STATE.READY)
            else
                for i = 1, 10 do
                    ItemUse(oizysDroneModule.itemId)

                    if WaitUntil(function()
                        return IsAddonReady("SelectYesno") and IsAddonVisible("SelectYesno")
                    end, 0.6, TIME.POLL, 0.1) then
                        usedOk = true
                        break
                    end

                    Sleep(TIME.STABLE)
                end

                if not usedOk then
                    Log("MODULE_USE: SelectYesno never appeared (animation lock)")
                    gotoState(STATE.FAIL)
                end
            end

            if sm.s == STATE.MODULE_USE and usedOk then
                SafeCallback("SelectYesno", 0)

                if WaitEntityByName("Artifact", 10.0) then
                    Sleep(TIME.STABLE)
                    gotoState(shouldReturnBaseBeforeArtifact() and STATE.RETURN_BASE
                            or STATE.ARTIFACT_INTERACT)
                else
                    Log("MODULE_USE: Artifact did not spawn in time")
                    gotoState(STATE.FAIL)
                end
            end
        end

    -- ======================
    -- ARTIFACT_INTERACT
    -- ======================
    elseif sm.s == STATE.ARTIFACT_INTERACT then
        local ent = artifactEntity()
        if not (ent and ent.Position) then
            gotoState(STATE.READY)
        else
            if not MoveNearVnav(ent.Position, 3.0, false) then
                goto continue
            end

            if InteractByName("Artifact", 5) then
                WaitEntityGone("Artifact", 6.0)
                Sleep(TIME.STABLE)
                gotoState(STATE.READY)
            elseif timedOut(8) then
                gotoState(STATE.FAIL)
            end
        end

    -- ======================
    -- TURNIN_FLOW
    -- ======================
    elseif sm.s == STATE.TURNIN_FLOW then
        if DistanceToBase() >= 75 then
            Log("TURNIN: far from base, using StellarReturn")
            if not StellarReturn() then
                gotoState(STATE.FAIL)
            else
                Sleep(1.5)
                gotoState(STATE.TURNIN_FLOW)
            end
        else
            MoveNearVnav(artifactNPC.position, 3.0, false)
            InteractByName(artifactNPC.name)

            if AwaitAddonReady("SelectString", 5) then
                SafeCallback("SelectString", 1)

                local lastTotal = AncientRecordCount()
                local stuck = 0

                while AncientRecordCount() > 0 do
                    local id, col = NextAncientRecord()
                    if not id then break end

                    if not AwaitAddonReady("ItemInspectionList", 5) then gotoState(STATE.FAIL); break end
                    SafeCallback("ItemInspectionList", 0, col)

                    if not AwaitAddonReady("SelectYesno", 5) then gotoState(STATE.FAIL); break end
                    SafeCallback("SelectYesno", 0)

                    if not AwaitAddonReady("ItemInspectionResult", 5) then gotoState(STATE.FAIL); break end
                    SafeCallback("ItemInspectionResult", -1)

                    Sleep(0.3)

                    local now = AncientRecordCount()
                    if now >= lastTotal then
                        stuck = stuck + 1
                        if stuck >= 5 then gotoState(STATE.FAIL); break end
                    else
                        stuck = 0
                        lastTotal = now
                    end
                end

                if IsAddonReady("ItemInspectionList") then
                    SafeCallback("ItemInspectionList", -1)
                end

                if sm.s ~= STATE.FAIL then
                    gotoState(STATE.READY)
                    Sleep(0.5)
                end
            elseif timedOut(10) then
                gotoState(STATE.FAIL)
            end
        end
    end

    Sleep(0.1)
    ::continue::
end

EchoOnce("STATE MACHINE EXIT: %s", sm.s)
