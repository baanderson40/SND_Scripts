-- =========================
-- Big Dump: Player / Targets / ClientState
-- =========================

-- Pretty heading
local function head(label) print(("\n== %s =="):format(label)) end

-- Reflect & dump an instance's properties (name, CLR type, current value)
local function dumpInstance(label, obj)
  if obj == nil then print(label .. ": <nil>"); return end
  local okT, t = pcall(function() return obj:GetType() end)
  if not okT or not t then print(label .. ": no GetType()"); return end
  head(label); print("Type:", t.FullName)
  local props = t:GetProperties()
  for i = 0, props.Length - 1 do
    local p = props[i]
    local okV, val = pcall(function() return p:GetValue(obj, nil) end)
    local v = okV and val or "<error>"
    local vstr = (v == nil and "<nil>")
              or ((type(v)=="boolean" or type(v)=="number") and tostring(v))
              or tostring(v)
    print(string.format("%-22s : %-12s = %s", p.Name, p.PropertyType.Name, vstr))
  end
end

-- Dump only the *type* (shape) of a property on a parent object
local function dumpPropertyType(label, parentObj, propName)
  if not parentObj then print(label .. ": parent <nil>"); return end
  local ok, pt = pcall(function()
    local t = parentObj:GetType()
    local p = t:GetProperty(propName)
    return p and p.PropertyType or nil
  end)
  if not ok or not pt then print(label .. ": no type available"); return end
  head(label .. " (property type)"); print("Type:", pt.FullName)
  local props = pt:GetProperties()
  for i = 0, props.Length - 1 do
    local p = props[i]
    print(string.format("%-22s : %s", p.Name, p.PropertyType.Name))
  end
end

-- Describe an IGameObject briefly (works on Svc.Targets slots)
local function describeIGameObject(label, go)
  if not go then print(label .. ": <none>"); return end
  head(label)
  local function try(fn) local ok,v=pcall(fn); return ok and v or nil end
  local name = try(function() return go.Name:ToString() end) or tostring(go)
  local kind = try(function() return go.ObjectKind end)
  local gid  = try(function() return go.GameObjectId end) or try(function() return go.EntityId end)
  local data = try(function() return go.DataId end)
  local hp   = try(function() return go.CurrentHp end)
  local max  = try(function() return go.MaxHp end)
  local pos  = try(function() return go.Position end)
  print(("Name: %s"):format(name))
  if kind ~= nil then print(("Kind: %s"):format(tostring(kind))) end
  if gid  ~= nil then print(("GameObjectId: %s"):format(tostring(gid))) end
  if data ~= nil then print(("DataId: %s"):format(tostring(data))) end
  if hp and max then print(("HP: %s/%s"):format(tostring(hp), tostring(max))) end
  if pos then print(("Pos: x=%.2f y=%.2f z=%.2f"):format(pos.X or 0, pos.Y or 0, pos.Z or 0)) end
end

-- List property names & CLR types on an object without invoking getters
local function dumpPropertyTypes(label, obj)
  if not obj then print(label .. ": <nil>"); return end
  local okT, t = pcall(function() return obj:GetType() end)
  if not okT or not t then print(label .. ": no GetType()"); return end
  head(label .. " (property types)"); print("Type:", t.FullName)
  local props = t:GetProperties()
  for i = 0, props.Length - 1 do
    local p = props[i]
    print(string.format("%-22s : %s", p.Name, p.PropertyType.Name))
  end
end

-- Safely fetch Svc.Targets slots (avoid getters that can throw)
local function getTargetSlot(name)
  local ok, val = pcall(function() return Svc.Targets[name] end)
  if not ok then return nil end
  return val
end

-- ========== RUN: Player.X ==========
dumpInstance("Player.Job", Player.Job)
dumpInstance("Player.Entity", Player.Entity)
dumpPropertyType("Player.Entity.Target", Player.Entity, "Target")   -- shape, even if nil
if Player.Entity and Player.Entity.Target then
  dumpInstance("Player.Entity.Target (instance)", Player.Entity.Target)
else
  print("Player.Entity.Target (instance): <nil>")
end

-- ========== RUN: Svc.Targets ==========
dumpPropertyTypes("Svc.Targets", Svc.Targets)  -- show what slots exist & their types

local slots = {
  "Target", "CurrentTarget", "PreviousTarget",
  "SoftTarget", "MouseOverTarget", "MouseOverNameplateTarget",
  "FocusTarget", "GPoseTarget",
}

for _, slot in ipairs(slots) do
  local obj = getTargetSlot(slot)
  describeIGameObject("Svc.Targets." .. slot, obj)
end

-- ========== RUN: Svc.ClientState ==========
dumpInstance("Svc.ClientState", Svc.ClientState)

-- Useful bits from LocalPlayer if present
do
  local lp = Svc.ClientState and Svc.ClientState.LocalPlayer or nil
  dumpInstance("Svc.ClientState.LocalPlayer (instance)", lp)
  if lp then
    local function try(fn) local ok,v=pcall(fn); return ok and v or nil end
    local curWorld = try(function() return lp.CurrentWorld.Value.Name:ToString() end)
    local homeWorld= try(function() return lp.HomeWorld.Value.Name:ToString() end)
    if curWorld or homeWorld then
      print(("Worlds: current=%s, home=%s"):format(curWorld or "<nil>", homeWorld or "<nil>"))
    end
    local cjId   = try(function() return lp.ClassJob.RowId end)
                or try(function() return lp.ClassJob.Value.RowId end)
    local cjAbbr = try(function() return lp.ClassJob.Value.Abbreviation:ToString() end)
    local cjName = try(function() return lp.ClassJob.Value.Name:ToString() end)
    if cjId or cjAbbr or cjName then
      print(("ClassJob: id=%s, abbr=%s, name=%s"):format(
        tostring(cjId or "<nil>"), tostring(cjAbbr or "<nil>"), tostring(cjName or "<nil>")
      ))
    end
    print(("TerritoryType=%s  MapId=%s  LoggedIn=%s"):format(
      tostring(Svc.ClientState and Svc.ClientState.TerritoryType),
      tostring(Svc.ClientState and Svc.ClientState.MapId),
      tostring(Svc.ClientState and Svc.ClientState.IsLoggedIn)
    ))
  end
end
