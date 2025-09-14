local function _get_addon(name)
    local ok, addon = pcall(Addons.GetAddon, name)
    if ok and addon ~= nil then
        return addon
    else
        return nil
    end
end

local _unpack = table.unpack or unpack

function SafeCallback(...)
    local args = {...}
    local idx = 1

    local addon = args[idx]; idx = idx + 1
    if type(addon) ~= "string" then
        Dalamud.Log("SafeCallback: first arg must be addon name (string)")
        return
    end

    local update = args[idx]; idx = idx + 1
    local updateStr = "true"

    if type(update) == "boolean" then
        updateStr = update and "true" or "false"
    elseif type(update) == "string" then
        local s = update:lower()
        if s == "false" or s == "f" or s == "0" or s == "off" then
            updateStr = "false"
        else
            updateStr = "true"
        end
    else
        idx = idx - 1
    end

    local call = "/callback " .. addon .. " " .. updateStr
    for i = idx, #args do
        local v = args[i]
        if type(v) == "number" then
            call = call .. " " .. tostring(v)
        end
    end

    Dalamud.Log("calling: " .. call)
    if IsAddonReady(addon) then
        yield(call)
    else
        Dalamud.Log("SafeCallback: addon not ready/visible: " .. addon)
    end
end

function IsAddonReady(name)
    local a = Addons.GetAddon(name)
    return a and a.Ready
end

local function _get_node(addonName, path)
    if type(path) ~= "table" then return nil end
    local addon = _get_addon(addonName)
    if not (addon and addon.Ready) then return nil end
    local ok, node = pcall(function() return addon:GetNode(_unpack(path)) end)
    if ok then return node end
    return nil
end

function GetNodeText(addonName, path)
    local node = _get_node(addonName, path)
    return node and tostring(node.Text or "") or ""
end

function close_yes_no(accept, expected_text)
    accept = accept or false
    if IsAddonReady("SelectYesno") then
        if expected_text ~= nil then
            local node = GetNodeText("SelectYesno", {1, 2})
            if node == nil or not node:lower():find(expected_text:lower(), 1, true) then
                Dalamud.Log("Expected yesno text (fuzzy) '" .. expected_text .. "' not found in actual text:" .. node)
                return
            end
        end
        if accept then
            SafeCallback("SelectYesno", true, 0) -- Yes
        else
            SafeCallback("SelectYesno", true, 1) -- No
        end
    end
end

msg = "Your item level is below average"
while true do
    close_yes_no(true, msg)
    yield("/wait .5")
end
