-- Gather all plugins with their status
local plugins = {}
for plugin in luanet.each(Svc.PluginInterface.InstalledPlugins) do
    table.insert(plugins, { name = plugin.InternalName, loaded = plugin.IsLoaded })
end

-- Sort alphabetically (case-insensitive)
table.sort(plugins, function(a, b)
    return string.lower(a.name) < string.lower(b.name)
end)

-- Log each plugin's name and loaded status
for i, plugin in ipairs(plugins) do
    Dalamud.Log(string.format("Plugin: %s | Enabled: %s", plugin.name, tostring(plugin.loaded)))
    yield("/wait 0.1")
end


--Test for plugin and state
function HasPlugin(name)
    for plugin in luanet.each(Svc.PluginInterface.InstalledPlugins) do
        if plugin.InternalName == name and plugin.IsLoaded then
            return true
        end
    end
    return false
end
