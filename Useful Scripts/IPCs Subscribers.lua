-- ipc_module.lua (refactored to single "subscribers" cache; same behavior)
import "System"

local M = {}

-- ===== Configuration / DI =====
-- Call once per script (optional); if not called, sane defaults are used.
-- M.init{
--   plugin_interface = Svc and Svc.PluginInterface,  -- required if no Svc.*
--   logger           = function(...) Svc.Chat:Print(M._logify(...)) end,
--   error_handler    = function(msg) error(msg, 2) end, -- no side effects by default
--   debug_level      = 3, -- 1..9 (default ERROR)
-- }
function M.init(opts)
  opts = opts or {}
  M._pi          = opts.plugin_interface or (Svc and Svc.PluginInterface)
  M._logger      = opts.logger or function(...) if Svc and Svc.Chat then Svc.Chat:Print(M._logify(...)) end end
  M._error       = opts.error_handler or function(msg) error(msg, 2) end
  M._debug_level = opts.debug_level or 3
end

-- ===== Private state =====
-- Single cache keyed by IPC signature -> { kind = "action"|"function", sub = <subscriber> }
local ipc_subscribers = {}

-- ===== Small util (local) =====
local function default(value, def) if value == nil then return def end return value end

local LEVEL_VERBOSE, LEVEL_DEBUG, LEVEL_INFO, LEVEL_ERROR, LEVEL_CRITICAL =
      9,              7,           5,           3,            1

function M._logify(first, ...)
  local rest = table.pack(...)
  local message = tostring(first)
  for i = 1, rest.n do message = message .. ' ' .. tostring(rest[i]) end
  return message
end

local function log_(lvl, ...)
  if (M._debug_level or LEVEL_ERROR) >= lvl then
    (M._logger or function() end)(...)
  end
end

local function CallerName(as_string)
  as_string = default(as_string, true)
  local info = debug.getinfo(3)
  local caller = info.name
  if caller == nil and not as_string then return nil end
  local file = tostring(info.short_src):gsub('.*\\','') .. ":" .. tostring(info.currentline)
  return tostring(caller) .. "(" .. file .. ")"
end

local function StopScript(message, caller, ...)
  caller = default(caller, CallerName())
  local msg = M._logify("Fatal error", message, "in", caller .. ":", ...)
  log_(LEVEL_ERROR, msg)
  -- IMPORTANT: No side effects here (no /qst stop, no IPC aborts).
  -- Let the caller decide what to do on errors:
  return (M._error or error)(msg)
end

-- ===== Reflection helpers (local) =====
local function get_generic_method(targetType, method_name, genericTypes)
  local genericArgsArr = luanet.make_array(Type, genericTypes)
  local methods = targetType:GetMethods()
  for i = 0, methods.Length - 1 do
    local m = methods[i]
    if m.Name == method_name and m.IsGenericMethodDefinition
       and m:GetGenericArguments().Length == genericArgsArr.Length then
      local constructed
      local ok, err = pcall(function() constructed = m:MakeGenericMethod(genericArgsArr) end)
      if ok then return constructed
      else return StopScript("Error constructing generic method", CallerName(false), err) end
    end
  end
  return StopScript("No generic method found", CallerName(false),
                    "No matching generic method for", method_name, "with", #genericTypes, "generic args")
end

-- ===== Public API =====

-- Ensure a cached IPC subscriber exists for a signature.
-- result_type: string .NET type for return (nil = action)
-- arg_types:   array of string .NET types for args (without the result)
function M.require_ipc(ipc_signature, result_type, arg_types)
  if ipc_subscribers[ipc_signature] ~= nil then
    log_(LEVEL_DEBUG, "IPC already loaded", ipc_signature); return
  end

  local pi = M._pi
  if not pi then
    return StopScript("PluginInterface missing", CallerName(false), "Set plugin_interface via M.init()")
  end

  arg_types = default(arg_types, {})
  -- Preserve original behavior: always append a "result" generic argument,
  -- defaulting to System.Object when result_type is nil (action IPC).
  arg_types[#arg_types + 1] = default(result_type, 'System.Object')

  for i, v in pairs(arg_types) do
    if type(v) ~= 'string' then
      return StopScript("Bad argument", CallerName(false), "argument types should be strings")
    end
    arg_types[i] = Type.GetType(v)
  end

  local method = get_generic_method(pi:GetType(), 'GetIpcSubscriber', arg_types)
  if not (method and method.Invoke) then
    return StopScript("GetIpcSubscriber not found", CallerName(false),
                      "No IPC subscriber for", #arg_types, "generic type arguments")
  end

  local sig = luanet.make_array(Object, { ipc_signature })
  local subscriber = method:Invoke(pi, sig)
  if subscriber == nil then
    return StopScript("IPC not found", CallerName(false), "signature:", ipc_signature)
  end

  local kind = (result_type == nil) and "action" or "function"
  ipc_subscribers[ipc_signature] = { kind = kind, sub = subscriber }

  if kind == "action" then
    log_(LEVEL_DEBUG, "loaded action IPC", ipc_signature)
  else
    log_(LEVEL_DEBUG, "loaded function IPC", ipc_signature)
  end
end

-- Invoke a previously required IPC by signature.
function M.invoke_ipc(ipc_signature, ...)
  local entry = ipc_subscribers[ipc_signature]
  if not entry then
    return StopScript("IPC not ready", CallerName(false), "signature:", ipc_signature, "is not loaded")
  end

  if entry.kind == "function" then
    local result = entry.sub:InvokeFunc(...)
    if result == entry.sub then
      return StopScript("Function IPC failed", CallerName(false), "signature:", ipc_signature)
    end
    return result
  end

  -- action
  local result = entry.sub:InvokeAction(...)
  if result == entry.sub then
    return StopScript("IPC failed", CallerName(false), "signature:", ipc_signature)
  end
  -- action returns nil on success
end

-- Optional convenience: clear cache (e.g., on reload)
function M.reset_cache()
  ipc_subscribers = {}
end

-- Provide levels if a caller wants to tweak M._debug_level meaningfully
M.LEVEL_VERBOSE  = LEVEL_VERBOSE
M.LEVEL_DEBUG    = LEVEL_DEBUG
M.LEVEL_INFO     = LEVEL_INFO
M.LEVEL_ERROR    = LEVEL_ERROR
M.LEVEL_CRITICAL = LEVEL_CRITICAL

-- Initialize with safe defaults immediately
M.init()

return M