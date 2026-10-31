--[=====[
[[SND Metadata]]
author: baanderson40
version: 0.0.17
description: >-
  Enables AutoDuty multibox on the current character. When configured as the host,
  sends an activation tell to each configured client. When configured as a client,
  listens for the activation message through SND chat triggers and accepts BossMod
  preset and Lifestream commands from the host in party chat. After loading or
  updating this macro, disable and re-enable the OnChatMessage trigger in SND to
  refresh its trigger registration.
plugin_dependencies:
- AutoDuty
configs:
  Host:
    description: Enable this when running the script on the AutoDuty multibox host.
    default: false
  Client Names:
    description: Comma-separated world-qualified targets, for example Character Name@Kraken.
    default: ""
  Activation Message:
    description: Exact tell message used by the host to activate clients.
    default: AUTODUTY_MULTIBOX_ENABLE
triggers:
- OnChatMessage
chat_message_filter:
  channels:
    - TellIncoming
function_chat_filters:
  OnChatMessage_AutoDuty: {}

[[End Metadata]]
--]=====]

-- AutoDuty exposes Run/Stop IPC, but not its Multibox setting. The setting is
-- intentionally accessed through the plugin's public reflection surface here.
local AUTO_DUTY_PLUGIN = "AutoDuty"
local MULTIBOX_TYPE = "AutoDuty.Multibox.MultiboxUtility"
local MULTIBOX_CONFIG_PROPERTY = "Config"
local MULTIBOX_ENABLED_PROPERTY = "MultiBox"
local TELL_DELAY_SECONDS = 2.0
local trustedHostName = ""
local stopRequested = false
local pendingCommands = {}

local function log(message)
    local text = "[AutoDuty Multibox] " .. tostring(message)
    Dalamud.Log(text)
    yield("/echo " .. text)
end

local function log_without_yield(message)
    Dalamud.Log("[AutoDuty Multibox] " .. tostring(message))
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function get_config(name, fallback)
    local value = Config.Get(name)
    if value == nil then
        return fallback
    end
    return value
end

local function find_auto_duty_plugin()
    -- SND's InstalledPlugins entries expose load state, but not always Assembly.
    -- ECommons' reflector returns the actual Dalamud plugin wrapper.
    local okLoad = pcall(function()
        luanet.load_assembly("ECommons")
    end)
    if okLoad then
        local okReflector, reflector = pcall(function()
            return luanet.import_type("ECommons.Reflection.DalamudReflector")
        end)
        if okReflector and reflector then
            local okManager, manager = pcall(function()
                return reflector.GetPluginManager()
            end)
            if okManager and manager then
                for plugin in luanet.each(manager.InstalledPlugins) do
                    if plugin.Name == AUTO_DUTY_PLUGIN and plugin.IsLoaded then
                        return plugin
                    end
                end
            end
        end
    end

    -- Fallback for environments where the reflector assembly is unavailable.
    for plugin in luanet.each(Svc.PluginInterface.InstalledPlugins) do
        if plugin.InternalName == AUTO_DUTY_PLUGIN and plugin.IsLoaded then
            return plugin
        end
    end
    return nil
end

local function get_multibox_config()
    local plugin = find_auto_duty_plugin()
    if not plugin then
        return nil, "AutoDuty is not loaded"
    end

    local okAssembly, assembly = pcall(function()
        return plugin.Assembly
    end)
    if not okAssembly or not assembly then
        return nil, "AutoDuty assembly is unavailable"
    end

    local multiboxType = assembly:GetType(MULTIBOX_TYPE)
    if not multiboxType then
        return nil, "AutoDuty multibox type was not found"
    end

    local configProperty = multiboxType:GetProperty(MULTIBOX_CONFIG_PROPERTY)
    if not configProperty then
        return nil, "AutoDuty multibox Config property was not found"
    end

    local ok, config = pcall(function()
        return configProperty:GetValue(nil)
    end)
    if not ok or not config then
        return nil, "AutoDuty multibox Config could not be read"
    end

    local enabledProperty = config:GetType():GetProperty(MULTIBOX_ENABLED_PROPERTY)
    if not enabledProperty then
        return nil, "AutoDuty MultiBox property was not found"
    end

    return config, enabledProperty
end

local function is_multibox_enabled(config, enabledProperty)
    local ok, value = pcall(function()
        return enabledProperty:GetValue(config)
    end)
    if not ok then
        return nil
    end
    return value == true
end

local function set_multibox(enabled)
    local config, enabledPropertyOrError = get_multibox_config()
    if not config then
        return false, enabledPropertyOrError
    end

    local enabledProperty = enabledPropertyOrError
    if is_multibox_enabled(config, enabledProperty) == enabled then
        return true, enabled and "already enabled" or "already disabled"
    end

    local ok, err = pcall(function()
        enabledProperty:SetValue(config, enabled)
    end)
    if not ok then
        return false, "failed to set MultiBox to " .. tostring(enabled) .. ": " .. tostring(err)
    end

    if is_multibox_enabled(config, enabledProperty) ~= enabled then
        return false, "MultiBox did not report " .. tostring(enabled) .. " after setting it"
    end

    return true, enabled and "enabled" or "disabled"
end

local function enable_multibox()
    return set_multibox(true)
end

local function split_client_names(value)
    local names = {}
    for name in tostring(value or ""):gmatch("[^,]+") do
        name = trim(name)
        if name ~= "" then
            names[#names + 1] = name
        end
    end
    return names
end

local function validate_command_text(value, label)
    value = trim(value)
    if value == "" then
        return nil, label .. " cannot be empty"
    end
    if value:find("[\r\n]", 1) or value:find('"', 1) then
        return nil, label .. " cannot contain quotes or newlines"
    end
    return value
end

local function send_activation_tells(message)
    local names = split_client_names(get_config("Client Names", ""))
    if #names == 0 then
        return false, "Client Names is empty"
    end

    local sent = 0
    for _, name in ipairs(names) do
        local safeName, nameError = validate_command_text(name, "Client name")
        if not safeName then
            return false, nameError
        end
        local characterName, worldName = safeName:match("^(.+)%@([^%@]+)$")
        if not characterName or trim(characterName) == "" or trim(worldName) == "" then
            return false, "Client target must include a world, for example Character Name@Kraken"
        end
        local tellCommand = "/tell " .. safeName .. " " .. message
        Dalamud.Log("[AutoDuty Multibox] Sending tell command: " .. tellCommand)
        yield(tellCommand)
        sent = sent + 1
        yield("/wait " .. tostring(TELL_DELAY_SECONDS))
    end
    return true, "sent to " .. tostring(sent) .. " client(s)"
end

local function activation_message()
    return validate_command_text(get_config("Activation Message", "AUTODUTY_MULTIBOX_ENABLE"), "Activation Message")
end

local function is_chat_trigger()
    return type(TriggerData) == "table"
        and TriggerData.message ~= nil
end

local function chat_type_is(value, expectedName, expectedValue)
    local valueText = tostring(value or "")
    local enumName, enumValue = valueText:match("^([^:]+):%s*(%d+)$")
    if enumName == expectedName then
        return true
    end
    return tonumber(enumValue or valueText) == expectedValue
end

local function is_party_chat()
    return chat_type_is(TriggerData.type, "Party", 14)
        or chat_type_is(TriggerData.type, "CrossParty", 32)
end

local function debug_trigger_data(context)
    if type(TriggerData) ~= "table" then
        Dalamud.Log("[AutoDuty Multibox] DEBUG " .. context .. ": TriggerData is unavailable")
        return
    end

    Dalamud.Log(string.format(
        "[AutoDuty Multibox] DEBUG %s: eventType=%q type=%q sender=%q message=%q",
        context,
        tostring(TriggerData.eventType),
        tostring(TriggerData.type),
        tostring(TriggerData.sender),
        tostring(TriggerData.message)
    ))
end

local function remember_trusted_host()
    local sender = trim(TriggerData.sender or "")
    if sender == "" then
        return nil, "Activation tell did not include a sender"
    end

    trustedHostName = sender
    return sender
end

local function same_chat_name(left, right)
    left = trim(left):lower()
    right = trim(right):lower()
    if left == right then
        return true
    end

    -- Party sender names may include a leading role/chat icon that tells omit.
    if #right > 0 and left:sub(-#right) == right then
        return true
    end

    -- Party chat may abbreviate a two-part character name to "First L.".
    local firstName, lastName = right:match("^(.+)%s+([^%s]+)$")
    if not firstName or not lastName then
        return false
    end
    local abbreviated = firstName .. " " .. lastName:sub(1, 1) .. "."
    return left:sub(-#abbreviated) == abbreviated
end

local function local_character_name()
    local ok, name = pcall(function()
        return Entity.Player.Name
    end)
    if ok and name then
        return trim(name)
    end

    local okFallback, fallbackName = pcall(function()
        return Svc.Objects.LocalPlayer.Name
    end)
    if okFallback and fallbackName then
        return trim(fallbackName)
    end
    return ""
end

local function is_boss_mod_available()
    return IPC and IPC.BossMod
        and IPC.BossMod.SetActive
        and IPC.BossMod.ClearActive
end

local function is_lifestream_available()
    return IPC and IPC.Lifestream
        and IPC.Lifestream.ExecuteCommand
        and IPC.Lifestream.Abort
end

local function queue_command(command)
    pendingCommands[#pendingCommands + 1] = command
    log_without_yield("Queued host command: " .. command)
end

local function process_pending_commands()
    while #pendingCommands > 0 do
        local command = table.remove(pendingCommands, 1)
        if command == "leave" then
            if not (InstancedContent and InstancedContent.LeaveCurrentContent) then
                log("Host party command failed: InstancedContent.LeaveCurrentContent is unavailable")
            else
                local ok, err = pcall(function()
                    InstancedContent.LeaveCurrentContent()
                end)
                if ok then
                    log("Host party command left current instance")
                else
                    log("Host party command failed to leave current instance: " .. tostring(err))
                end
            end
        else
            log("Executing host party command: " .. command)
            yield(command)
        end
    end
end

local function handle_party_command(trustedHostOverride)
    debug_trigger_data("party command")
    local sender = trim(TriggerData.sender or "")
    local trustedHost = trim(trustedHostOverride or trustedHostName)
    if trustedHost == "" or sender == "" or not same_chat_name(sender, trustedHost) then
        Dalamud.Log(string.format(
            "[AutoDuty Multibox] DEBUG party command rejected: sender=%q trustedHost=%q",
            sender,
            trustedHost
        ))
        return false
    end

    local receivedMessage = trim(TriggerData.message or "")

    if receivedMessage:lower() == "snd stop" then
        stopRequested = true
        log_without_yield("Host requested AutoDuty multibox script shutdown")
        return true
    end

    local lowerMessage = receivedMessage:lower()
    if lowerMessage == "ad stop" then
        queue_command("/ad stop")
        return true
    end
    if lowerMessage == "qst start" then
        if get_config("Host", false) == true then
            log_without_yield("Client-only command ignored on host: qst start")
            return true
        end
        queue_command("/qst start")
        return true
    end
    if lowerMessage == "stylist all" then
        queue_command("/stylist all")
        return true
    end
    if lowerMessage == "leave" then
        if get_config("Host", false) == true then
            log_without_yield("Client-only command ignored on host: leave")
            return true
        end
        queue_command("leave")
        return true
    end

    if lowerMessage == "bm ai on" then
        queue_command("/vbm ai on")
        return true
    end
    if lowerMessage == "bm ai off" then
        queue_command("/vbm ai off")
        return true
    end

    local lifestreamCommand = receivedMessage:match("^[lL][sS]%s+(.+)$")
    if not lifestreamCommand then
        lifestreamCommand = receivedMessage:match("^/[lL][sS]%s+(.+)$")
    end
    if lifestreamCommand then
        lifestreamCommand = trim(lifestreamCommand)
        if lifestreamCommand == "" or lifestreamCommand:find("[\r\n]", 1) then
            return true
        end
        if not is_lifestream_available() then
            log_without_yield("Host party command ignored because Lifestream IPC is unavailable")
            return true
        end

        local lowerCommand = lifestreamCommand:lower()
        if lowerCommand == "abort" or lowerCommand == "stop" then
            local ok, err = pcall(IPC.Lifestream.Abort)
            if not ok then
                log_without_yield("Host party command failed to abort Lifestream: " .. tostring(err))
                return true
            end
            log_without_yield("Host party command aborted Lifestream")
            return true
        end

        local ok, err = pcall(function()
            IPC.Lifestream.ExecuteCommand(lifestreamCommand)
        end)
        if not ok then
            log_without_yield("Host party Lifestream command failed: " .. tostring(err))
        else
            log_without_yield("Host party command sent to Lifestream: " .. lifestreamCommand)
        end
        return true
    end

    local preset = receivedMessage:match("^[bB][mM]%s+(.+)$")
    if not preset then
        preset = receivedMessage:match("^/[bB][mM]%s+(.+)$")
    end
    if not preset then
        return false
    end
    preset = trim(preset)

    if not is_boss_mod_available() then
        log_without_yield("Host party command ignored because BossMod IPC is unavailable")
        return true
    end

    if preset:lower() == "clear" then
        local ok, err = pcall(IPC.BossMod.ClearActive)
        if not ok then
            log_without_yield("Host party command failed to clear BossMod preset: " .. tostring(err))
            return true
        end
        log_without_yield("Host party command cleared BossMod preset")
        return true
    end

    local safePreset, presetError = validate_command_text(preset, "BossMod preset")
    if not safePreset then
        log_without_yield(presetError)
        return true
    end

    local ok, err = pcall(function()
        IPC.BossMod.SetActive(safePreset)
    end)
    if not ok then
        log_without_yield("Host party command failed to activate BossMod preset " .. safePreset .. ": " .. tostring(err))
        return true
    end

    log_without_yield("Host party command activated BossMod preset " .. safePreset)
    return true
end

-- The host macro stays running so OnStop can disable AutoDuty multibox. SND
-- skips macro-level triggers for running macros, so the host handles party
-- commands through this function-level trigger instead. The suffix keeps the
-- function-level registration distinct from the macro-level OnChatMessage
-- trigger while retaining SND's OnChatMessage prefix matching.
function OnChatMessage_AutoDuty()
    if not is_party_chat() then
        return
    end
    debug_trigger_data("function OnChatMessage_AutoDuty party")

    if get_config("Host", false) == true then
        handle_party_command(local_character_name())
    else
        handle_party_command()
    end
end

local function run()
    local message, messageError = activation_message()
    if not message then
        log(messageError)
        return
    end

    local isHost = get_config("Host", false) == true
    local triggeredByChat = is_chat_trigger()
    if triggeredByChat then
        debug_trigger_data("macro run")
    end

    -- The host is started manually. Ignore incoming tells so the host does not
    -- accidentally restart and rebroadcast while its trigger is registered.
    if isHost and triggeredByChat then
        return
    end

    -- Clients are started by the macro-level chat trigger. Tell messages activate
    -- multibox; party messages are reserved for BossMod and Lifestream commands.
    if not isHost then
        if not triggeredByChat then
            log("Client is configured for macro-level chat activation")
            return
        end

        local receivedMessage = trim(TriggerData.message or "")
        if receivedMessage ~= message then
            return
        end

        local trustedHost, hostError = remember_trusted_host()
        if not trustedHost then
            log(hostError)
            return
        end
    end

    local enabled, enableResult = enable_multibox()
    if not enabled then
        log((isHost and "Host" or "Client") .. " activation failed: " .. tostring(enableResult))
        return
    end

    if not isHost then
        log("Client activation received; multibox " .. enableResult)

        -- Keep the client environment alive so the trusted host name captured
        -- from the activation tell remains available to function-level triggers.
        while not stopRequested do
            process_pending_commands()
            yield("/wait 1")
        end
        return
    end

    log("Host multibox " .. enableResult)

    local sent, sendResult = send_activation_tells(message)
    if sent then
        log("Activation " .. sendResult)
    else
        log("Host multibox enabled, but activation tells were not sent: " .. tostring(sendResult))
    end

    -- Keep this macro alive so OnStop can reliably clean up the host setting.
    while not stopRequested do
        process_pending_commands()
        yield("/wait 1")
    end
end

function OnStop()
    if is_boss_mod_available() then
        local cleared, err = pcall(IPC.BossMod.ClearActive)
        if cleared then
            Dalamud.Log("[AutoDuty Multibox] Cleanup: BossMod preset cleared")
        else
            Dalamud.Log("[AutoDuty Multibox] Cleanup failed to clear BossMod preset: " .. tostring(err))
        end
    else
        Dalamud.Log("[AutoDuty Multibox] Cleanup skipped BossMod clear because IPC is unavailable")
    end

    if get_config("Host", false) ~= true then
        return
    end

    local disabled, result = set_multibox(false)
    if disabled then
        Dalamud.Log("[AutoDuty Multibox] Host cleanup: MultiBox " .. result)
    else
        Dalamud.Log("[AutoDuty Multibox] Host cleanup failed: " .. tostring(result))
    end
end

run()
