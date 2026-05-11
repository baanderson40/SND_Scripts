local TARGET_PLUGIN = "Artisan"

local function isPluginEnabled(name)
    for plugin in luanet.each(Svc.PluginInterface.InstalledPlugins) do
        if plugin.InternalName == name and plugin.IsLoaded then
            return true
        end
    end
    return false
end

local function logAndEcho(message)
    Dalamud.Log(message)
    yield(string.format("/echo %s", message))
end

local function togglePlugin(name)
    if isPluginEnabled(name) then
        logAndEcho(string.format("Disabling %s", name))
        yield(string.format("/xldisableplugin %s", name))
    else
        logAndEcho(string.format("Enabling %s", name))
        yield(string.format("/xlenableplugin %s", name))
    end

    yield("/wait 0.5")

    if isPluginEnabled(name) then
        logAndEcho(string.format("%s is now enabled", name))
    else
        logAndEcho(string.format("%s is now disabled", name))
    end
end

togglePlugin(TARGET_PLUGIN)
