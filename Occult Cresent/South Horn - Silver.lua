--[=====[
[[SND Metadata]]
author: Aniane | Modified by baanderson40
version: 2.0.2
description: >-
  Re-enter the Occult Crescent when you're booted, and spend your silver coins!
plugin_dependencies:
- vnavmesh
- BOCCHI
configs:
    Spend Silver:
        default: true
        description: Spend your silver coins automatically.
    Silver Cap:
        default: 9900
        description: The silver cap to dump at the vendor.
        min: 40
        max: 9999
    Silver Purchase Item:
        description: Which item to buy when dumping silver.
        is_choice: true
        choices:
          - Occult Potion
          - Occult Coffer
          - Aetherspun Silver
          - Savage Aim Materia XI
          - Savage Aim Materia XII
          - Savage Might Materia XI
          - Savage Might Materia XII
          - Heaven's Eye Materia XI
          - Heaven's Eye Materia XII
          - Quickarm Materia XI
          - Quickarm Materia XII
          - Quicktongue Materia XI
          - Quicktongue Materia XII
          - Battledance Materia XI
          - Battledance Materia XII
          - Piety Materia XI
          - Piety Materia XII
        default: Heaven's Eye Materia XI
    Self Repair:
        default: true
        description: Self-repair automatically. If this is unchecked, it will use the mender.
    Durability Amount:
        default: 25
        description: The durability amount to repair at.
        min: 1
        max: 75
    Auto Buy Dark Matter:
        default: true
        description: Automatically buy Dark Matter when self-repairing.
    Extract Materia:
        default: true
        description: Extract materia automatically.
    Instance Duration (Minutes):
        default: 90
        description: Max time to stay in an instance before leaving (minutes).
        min: 1
        max: 180
    Instance Limit:
        default: 2
        description: Number of instances to run before stopping the script. Set to 0 to disable limit.
        min: 0
        max: 20
    Enable AutoRetainer MultiMode When Finished:
        default: true
        description: Enable AutoRetainer MultiMode only when the script reaches instance limit.
    Autorotation Preset Name:
        default: "Occult"
        description: >-
          Optional: BMRAI preset name to set when engaged in an event/fate.
          Leave blank to not change preset.
[[End Metadata]]
--]=====]

--[[
    DO NOT TOUCH ANYTHING BELOW THIS UNLESS YOU KNOW WHAT YOU'RE DOING.
    THIS IS A SCRIPT FOR THE OCCULT CRESCENT AND IS NOT MEANT TO BE MODIFIED UNLESS YOU ARE FAMILIAR WITH LUA AND THE SND API.
    IF YOU DO NOT UNDERSTAND THE IMPLICATIONS OF CHANGING THESE VALUES, DO NOT MODIFY THEM.
  ]]

import("System.Numerics")

--Config Variables
local spendSilver = Config.Get("Spend Silver")
local selfRepair = Config.Get("Self Repair")
local durabilityAmount = Config.Get("Durability Amount")
local ShouldAutoBuyDarkMatter = Config.Get("Auto Buy Dark Matter")
local ShouldExtractMateria = Config.Get("Extract Materia")
local SILVER_DUMP_LIMIT = Config.Get("Silver Cap")
local SILVER_PURCHASE_ITEM = Config.Get("Silver Purchase Item")

-- Instance timer / counter config
local INSTANCE_DURATION_MIN = Config.Get("Instance Duration (Minutes)")
local INSTANCE_LIMIT = Config.Get("Instance Limit")

-- AutoRetainer config
local ENABLE_AR_MULTIMODE_WHEN_FINISHED = Config.Get("Enable AutoRetainer MultiMode When Finished")

-- Autorotation preset name
local AUTOROTATION_PRESET_NAME = Config.Get("Autorotation Preset Name")

-- Constants
local OCCULT_CRESCENT = 1252
local PHANTOM_VILLAGE = 1278
local INSTANCE_ENTRY_NPC = "Jeffroy"
local ENTRY_NPC_POS = Vector3(-77.958374, 5, 15.396423)
local REENTER_DELAY = 10

-- Items
local SILVER_ITEM_ID = 45043

-- Shop Config
local VENDOR_NAME = "Expedition Antiquarian"
local VENDOR_POS = Vector3(833.83, 72.73, -719.51)
local BaseAetheryte = Vector3(830.75, 72.98, -695.98)

local ShopItems = {
    { itemName = "Occult Potion",              menuIndex = 1, itemIndex = 5,  price = 40   },
    { itemName = "Occult Coffer",              menuIndex = 1, itemIndex = 6,  price = 40   },
    { itemName = "Aetherspun Silver",          menuIndex = 1, itemIndex = 7,  price = 1200 },
    { itemName = "Savage Aim Materia XI",      menuIndex = 1, itemIndex = 8,  price = 100  },
    { itemName = "Savage Aim Materia XII",     menuIndex = 1, itemIndex = 9,  price = 200  },
    { itemName = "Savage Might Materia XI",    menuIndex = 1, itemIndex = 10, price = 100  },
    { itemName = "Savage Might Materia XII",   menuIndex = 1, itemIndex = 11, price = 200  },
    { itemName = "Heaven's Eye Materia XI",    menuIndex = 1, itemIndex = 12, price = 100  },
    { itemName = "Heaven's Eye Materia XII",   menuIndex = 1, itemIndex = 13, price = 200  },
    { itemName = "Quickarm Materia XI",        menuIndex = 1, itemIndex = 14, price = 100  },
    { itemName = "Quickarm Materia XII",       menuIndex = 1, itemIndex = 15, price = 200  },
    { itemName = "Quicktongue Materia XI",     menuIndex = 1, itemIndex = 16, price = 100  },
    { itemName = "Quicktongue Materia XII",    menuIndex = 1, itemIndex = 17, price = 200  },
    { itemName = "Battledance Materia XI",     menuIndex = 1, itemIndex = 18, price = 100  },
    { itemName = "Battledance Materia XII",    menuIndex = 1, itemIndex = 19, price = 200  },
    { itemName = "Piety Materia XI",           menuIndex = 1, itemIndex = 20, price = 100  },
    { itemName = "Piety Materia XII",          menuIndex = 1, itemIndex = 21, price = 200  },
}

local ShopItemsByName = {}
for _, it in ipairs(ShopItems) do
    ShopItemsByName[it.itemName] = it
end

--Repair module variables
local MENDER_NAME = "Expedition Supplier"
local MENDER_POS = Vector3(821.47, 72.73, -669.12)

-- Character Conditions (pruned to only used entries; keep existing names)
CharacterCondition = {
    dead = 2,
    mounted = 4,
    inCombat = 26,
    casting = 27,
    occupiedInQuestEvent = 32,
    boundByDuty34 = 34,
    occupiedMateriaExtractionAndRepair = 39,
    betweenAreas = 45,
}

-- State Machine
local State = nil
local CharacterState = {}

-- Timer + instance counter tracking
local running = true
local instanceStartTime = nil
local completedInstances = 0
local wasInInstance = false

-- track natural finish (instance limit reached)
local finishedNaturally = false

-- Helper-return watchdog (OCH return verification)
local awaitingHelperReturn = false
local helperDisengagedAt = nil
local HELPER_RETURN_TIMEOUT_SEC = 30

-- Latch: saw betweenAreas at any point (even while main loop is waiting)
local sawBetweenAreas = false

-- Engagement hysteresis
local lastOccultEngagedAt = 0
local OCCULT_DISENGAGE_GRACE_SEC = 3

local lastFateAt = 0
local FATE_DISENGAGE_GRACE_SEC = 2

local lastEngaged = false

-- Movement heuristics
local VENDOR_WALK_RADIUS = 60.0
local RETURN_COOLDOWN_SEC = 30
local lastReturnAt = 0

-- YesAlready restore
local YA_NAME = "ContentsFinderConfirm"
local yaHadState = false
local yaPrevEnabled = true

-- Helper Functions
local function Sleep(seconds)
    yield('/wait ' .. tostring(seconds))
end

local function WaitForAddon(addonName, timeout)
    local elapsed = 0
    while (not Addons.GetAddon(addonName) or not Addons.GetAddon(addonName).Ready) and elapsed < timeout do
        Sleep(0.5)
        elapsed = elapsed + 0.5
    end
    return Addons.GetAddon(addonName) and Addons.GetAddon(addonName).Ready
end

-- GeneralAction guard
local function ExecGeneralAction(id)
    if Actions and Actions.ExecuteGeneralAction then
        Actions.ExecuteGeneralAction(id)
        return true
    end
    return false
end

-- plugin enable check (simple)
local function HasPlugin(name)
    for plugin in luanet.each(Svc.PluginInterface.InstalledPlugins) do
        if plugin.InternalName == name and plugin.IsLoaded then
            return true
        end
    end
    return false
end

local function WaitForPluginEnabled(name, timeoutSeconds)
    local waited = 0
    while waited < timeoutSeconds do
        if HasPlugin(name) then return true end
        Sleep(0.5)
        waited = waited + 0.5
    end
    return false
end

-- Restart BOCCHI on instance entry and wait until it's loaded again
local function RestartBOCCHI()
    while Svc.Condition[CharacterCondition.betweenAreas] do
        Sleep(0.5)
    end

    yield("/echo [OCM] Restarting BOCCHI plugin...")
    yield("/xldisableplugin BOCCHI")
    Sleep(1.0)
    yield("/xlenableplugin BOCCHI")

    if not WaitForPluginEnabled("BOCCHI", 20) then
        yield("/echo [OCM] WARNING: BOCCHI did not report as loaded within timeout.")
    else
        yield("/echo [OCM] BOCCHI loaded.")
    end
end

local function TurnOnOCH()
    Dalamud.LogDebug("[OCM] Turning on OCH...")

    -- Wait until BOCCHI is loaded so its slash commands exist
    WaitForPluginEnabled("BOCCHI", 20)

    if not IllegalMode then
        IllegalMode = true
        yield("/bocchillegal on")
        yield("/echo [OCM] Turned on OCH")
    end
end

local function TurnOffOCH()
    Dalamud.LogDebug("[OCM] Turning off OCH...")

    if IllegalMode then
        IllegalMode = false
        yield("/bocchillegal off")
    end

    if IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() then
        yield("/vnav stop")
    end

    if IPC.Lifestream.IsBusy() then
        yield("/li stop")
    end

    yield("/bmrai off")
end

-- Return to base then vnav to BaseAetheryte within 3 yalms (stop short) + timeout/watchdog
local function ReturnToBase()
    yield("/gaction Return")

    -- Wait for cast + zone transition to complete
    repeat Sleep(0.5) until not Svc.Condition[CharacterCondition.casting]
    repeat Sleep(0.5) until not Svc.Condition[CharacterCondition.betweenAreas]

    local stopDist = 3.0
    local timeout = 45 -- seconds
    local start = os.time()

    local lastDist = Vector3.Distance(Entity.Player.Position, BaseAetheryte)
    local lastImproveAt = os.time()

    while Vector3.Distance(Entity.Player.Position, BaseAetheryte) > stopDist do
        if os.time() - start > timeout then
            yield("/echo [OCM] ReturnToBase timeout; stopping vnav.")
            break
        end

        local d = Vector3.Distance(Entity.Player.Position, BaseAetheryte)
        if d < lastDist - 0.5 then
            lastDist = d
            lastImproveAt = os.time()
        elseif os.time() - lastImproveAt > 10 then
            yield("/echo [OCM] ReturnToBase stalled; stopping vnav.")
            break
        end

        if not IPC.vnavmesh.PathfindInProgress() and not IPC.vnavmesh.IsRunning() then
            IPC.vnavmesh.PathfindAndMoveTo(BaseAetheryte, false)
        end

        Sleep(0.25)
    end

    if IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() then
        yield("/vnav stop")
    end
end

local function ReturnToBaseIfAllowed()
    local now = os.time()
    if (now - lastReturnAt) < RETURN_COOLDOWN_SEC then
        return false
    end
    lastReturnAt = now
    ReturnToBase()
    return true
end

local function WaitUntilOutOfCombat()
    while Svc.Condition[CharacterCondition.inCombat] do
        Sleep(0.5)
    end
end

local function LeaveInstanceSafely()
    yield("/echo [OCM] Instance timer reached. Waiting to be out of combat before leaving...")
    WaitUntilOutOfCombat()

    yield("/echo [OCM] Leaving current instanced content...")
    InstancedContent.LeaveCurrentContent()

    local start = os.time()
    local timeout = 60
    local retried = false

    while Svc.Condition[CharacterCondition.boundByDuty34] do
        if os.time() - start > timeout then
            if not retried then
                retried = true
                yield("/echo [OCM] WARNING: Leave did not complete in time. Retrying leave once...")
                InstancedContent.LeaveCurrentContent()
                start = os.time()
                timeout = 30
            else
                yield("/echo [OCM] ERROR: Still in duty after retries. Stopping script.")
                running = false
                break
            end
        end
        Sleep(1)
    end
end

-- Engagement helpers
local function IsInFate()
    local cf = Fates.CurrentFate
    if cf ~= nil and cf.InFate then
        lastFateAt = os.time()
        return true
    end

    if lastFateAt > 0 and (os.time() - lastFateAt) <= FATE_DISENGAGE_GRACE_SEC then
        return true
    end

    return false
end

local function IsOccultEventActive()
    local evts = InstancedContent.OccultCrescent.Events
    if evts == nil then return false end

    for i = 0, evts.Count - 1 do
        local e = evts[i]
        if e ~= nil and e.IsActive then
            return true
        end
    end
    return false
end

local function IsEngagedInEventOrFate()
    if IsInFate() then
        return true
    end

    if Svc.Condition[CharacterCondition.inCombat]
       and (not Svc.Condition[CharacterCondition.mounted])
       and IsOccultEventActive()
    then
        lastOccultEngagedAt = os.time()
        return true
    end

    if lastOccultEngagedAt > 0 and (os.time() - lastOccultEngagedAt) <= OCCULT_DISENGAGE_GRACE_SEC then
        return true
    end

    return false
end

-- BossMod behavior
local function ApplyBossModEngageBehavior()
    local engaged = IsEngagedInEventOrFate()

    if engaged then
        local preset = tostring(AUTOROTATION_PRESET_NAME or "")
        if preset ~= "" then
            IPC.BossMod.SetActive(preset)
        end
    else
        local active = IPC.BossMod.GetActive()
        if active ~= nil and tostring(active) ~= "" then
            IPC.BossMod.ClearActive()
        end
    end

    return engaged
end

-- YesAlready IPC safety
local function YesAlreadyAvailable()
    return IPC.YesAlready
       and IPC.YesAlready.IsPluginEnabled
       and IPC.YesAlready.IsBotherEnabled
       and IPC.YesAlready.SetBotherEnabled
       and IPC.YesAlready.IsPluginEnabled()
end

local function DisableYesAlreadyBother()
    if YesAlreadyAvailable() then
        yaPrevEnabled = IPC.YesAlready.IsBotherEnabled(YA_NAME)
        yaHadState = true
        IPC.YesAlready.SetBotherEnabled(YA_NAME, false)
    end
end

local function RestoreYesAlreadyBother()
    if yaHadState and YesAlreadyAvailable() then
        IPC.YesAlready.SetBotherEnabled(YA_NAME, yaPrevEnabled)
        yaHadState = false
    end
end

function OnStop()
    RestoreYesAlreadyBother()

    Dalamud.LogDebug("[OCM] Stopping OCH Silver script...")
    Dalamud.LogDebug("[OCM] Turning off BOCCHI Illegal Mode...")
    yield("/bocchillegal off")
    yield("/wait 0.1")
    Dalamud.LogDebug("[OCM] Stopping pathfinding...")
    yield("/vnav stop")
    yield("/wait 0.1")
    Dalamud.LogDebug("[OCM] Stopping Lifestream...")
    yield("/li stop")
    yield("/wait 0.1")
    Dalamud.LogDebug("[OCM] Turning off BMRAI...")
    yield("/bmrai off")

    -- Always unset preset name on stop (manual or natural)
    yield("/bmrai setpresetname")

    yield("/echo [OCM] Script stopped.")
end

-- State Implementations
IllegalMode = false

function CharacterState.ready()
    local inInstance = Svc.Condition[CharacterCondition.boundByDuty34] and Svc.ClientState.TerritoryType == OCCULT_CRESCENT
    local silverCountNow = Inventory.GetItemCount(SILVER_ITEM_ID)
    local itemsToRepair = Inventory.GetItemsInNeedOfRepairs(tonumber(durabilityAmount))
    local needsRepair = false
    local shopAddon = Addons.GetAddon("ShopExchangeCurrency")

    -- If mounted and BossMod has an active preset, clear it (requested safety)
    if Svc.Condition[CharacterCondition.mounted] then
        local active = IPC.BossMod.GetActive()
        if active ~= nil and tostring(active) ~= "" then
            IPC.BossMod.ClearActive()
        end
    end

    -- Apply engage behavior and helper-return watchdog (uses sawBetweenAreas latch)
    local engagedNow = ApplyBossModEngageBehavior()

    if engagedNow then
        awaitingHelperReturn = false
        helperDisengagedAt = nil
    else
        if lastEngaged and not awaitingHelperReturn then
            awaitingHelperReturn = true
            helperDisengagedAt = os.time()
            sawBetweenAreas = false -- clear stale latch on arm
        end

        if awaitingHelperReturn then
            if sawBetweenAreas then
                sawBetweenAreas = false
                awaitingHelperReturn = false
                helperDisengagedAt = nil
            else
                local elapsed = os.time() - (helperDisengagedAt or os.time())
                if elapsed >= HELPER_RETURN_TIMEOUT_SEC then
                    if inInstance then
                        ReturnToBase()
                    end
                    awaitingHelperReturn = false
                    helperDisengagedAt = nil
                end
            end
        end
    end

    lastEngaged = engagedNow

    -- If for some reason the shop addon is visible, close it
    if silverCountNow < tonumber(SILVER_DUMP_LIMIT) and shopAddon and shopAddon.Ready then
        yield("/callback ShopExchangeCurrency true -1")
    end

    -- Instance enter tracking (ensure only once)
    if inInstance and not wasInInstance then
        wasInInstance = true
        TurnOffOCH()
        RestartBOCCHI()

        instanceStartTime = os.time()
        yield("/echo [OCM] Entered instance. Timer started (" .. tostring(INSTANCE_DURATION_MIN) .. "m).")
    end

    -- Instance exit tracking (count only if timer started)
    if (not inInstance) and wasInInstance then
        wasInInstance = false

        if instanceStartTime ~= nil then
            completedInstances = completedInstances + 1
            yield("/echo [OCM] Instance ended. Completed instances: " .. tostring(completedInstances) .. "/" .. tostring(INSTANCE_LIMIT))
        end

        instanceStartTime = nil

        local limit = tonumber(INSTANCE_LIMIT) or 0
        if limit > 0 and completedInstances >= limit then
            yield("/echo [OCM] Instance limit reached. Stopping script.")
            finishedNaturally = true
            running = false
            return
        end
    end

    -- Timer check while in instance
    if inInstance and instanceStartTime ~= nil then
        local elapsedSeconds = os.time() - instanceStartTime
        local limitSeconds = tonumber(INSTANCE_DURATION_MIN) * 60
        if elapsedSeconds >= limitSeconds then
            TurnOffOCH()
            LeaveInstanceSafely()
            State = CharacterState.ready
            return
        end
    end

    if type(itemsToRepair) == "number" then
        needsRepair = itemsToRepair ~= 0
    elseif type(itemsToRepair) == "table" then
        needsRepair = next(itemsToRepair) ~= nil
    end

    if not inInstance and Svc.ClientState.TerritoryType ~= PHANTOM_VILLAGE then
        State = CharacterState.zoneIn
        Dalamud.LogDebug("[OCM] State changed to zoneIn")
        return
    elseif not inInstance and Svc.ClientState.TerritoryType == PHANTOM_VILLAGE then
        State = CharacterState.reenterInstance
        Dalamud.LogDebug("[OCM] State changed to reenterInstance")
        return
    elseif needsRepair then
        Dalamud.LogDebug("[OCM] State changed to repair")
        State = CharacterState.repair
        return
    elseif ShouldExtractMateria and Inventory.GetSpiritbondedItems().Count > 0 then
        Dalamud.LogDebug("[OCM] State changed to extract materia")
        State = CharacterState.materia
        return
    elseif spendSilver and silverCountNow >= tonumber(SILVER_DUMP_LIMIT) then
        Dalamud.LogDebug("[OCM] State changed to dumpSilver")
        State = CharacterState.dumpSilver
        return
    elseif not IllegalMode then
        Dalamud.LogDebug("[OCM] State changed to ready")
        TurnOnOCH()
        return
    end
end

function CharacterState.zoneIn()
    local instanceEntryAddon = Addons.GetAddon("ContentsFinderConfirm")
    local SelectString = Addons.GetAddon("SelectString")

    if Svc.Condition[CharacterCondition.betweenAreas] then
        Sleep(3)
        State = CharacterState.zoneIn
        return
    end

    if Svc.ClientState.TerritoryType == PHANTOM_VILLAGE then
        Dalamud.Log("[OCM] Already in Phantom Village")

        if Vector3.Distance(Entity.Player.Position, ENTRY_NPC_POS) >= 5 then
            IPC.vnavmesh.PathfindAndMoveTo(ENTRY_NPC_POS, false)
            State = CharacterState.zoneIn
            return
        end

        if IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() then
            yield("/vnav stop")
            State = CharacterState.zoneIn
            return
        end

        if not Entity.Target or Entity.Target.Name ~= INSTANCE_ENTRY_NPC then
            yield("/target " .. INSTANCE_ENTRY_NPC)
            State = CharacterState.zoneIn
            return
        end

        if instanceEntryAddon and instanceEntryAddon.Ready then
            yield("/callback ContentsFinderConfirm true 8")
            yield("/echo [OCM] Re-entry confirmed.")
            State = CharacterState.ready
            return
        end

        if SelectString and SelectString.Ready then
            yield("/callback SelectString true 0")
            State = CharacterState.zoneIn
            return
        end

        -- Option A interact gate
        if (not instanceEntryAddon or not instanceEntryAddon.Ready)
           and (not SelectString or not SelectString.Ready)
           and Entity.Target and Entity.Target.Name == INSTANCE_ENTRY_NPC
           and Vector3.Distance(Entity.Player.Position, ENTRY_NPC_POS) <= 5
           and not Svc.Condition[CharacterCondition.occupiedInQuestEvent]
        then
            yield("/interact")
            Sleep(0.5)
        end

        State = CharacterState.zoneIn
        return
    end

    if Svc.ClientState.TerritoryType ~= OCCULT_CRESCENT then
        yield("/li occult")
        repeat Sleep(1) until not IPC.Lifestream.IsBusy()
        State = CharacterState.zoneIn
        return
    end

    if Svc.ClientState.TerritoryType == OCCULT_CRESCENT then
        if Player.Available then
            TurnOnOCH()
            State = CharacterState.ready
            return
        end
    end

    State = CharacterState.zoneIn
end

function CharacterState.reenterInstance()
    DisableYesAlreadyBother()

    yield("/echo [OCM] Detected exit from duty. Waiting " .. REENTER_DELAY .. " seconds before re-entry...")
    IllegalMode = false
    Sleep(REENTER_DELAY)

    local npc = Entity.GetEntityByName(INSTANCE_ENTRY_NPC)
    if not npc then
        RestoreYesAlreadyBother()
        yield("/echo [OCM] Could not find " .. INSTANCE_ENTRY_NPC .. ". Retrying in 10 seconds...")
        Sleep(10)
        return
    end

    yield("/target " .. INSTANCE_ENTRY_NPC)
    Sleep(1)
    yield("/interact")
    Sleep(1)

    if WaitForAddon("SelectString", 5) then
        local ss = Addons.GetAddon("SelectString")
        if ss and ss.Ready then
            Sleep(0.2)
            yield("/callback SelectString true 0")
        end

        -- wait for next menu or duty transition (bounded)
        local t0 = os.time()
        while os.time() - t0 < 5 do
            if Svc.Condition[CharacterCondition.boundByDuty34] or Svc.Condition[CharacterCondition.betweenAreas] then
                break
            end
            local ssx = Addons.GetAddon("SelectString")
            if ssx and ssx.Ready then
                break
            end
            Sleep(0.2)
        end

        -- if SelectString still ready, click again (second layer)
        local ss2 = Addons.GetAddon("SelectString")
        if ss2 and ss2.Ready then
            yield("/callback SelectString true 0")
            Sleep(0.2)
        end

        -- bounded wait for duty
        local start = os.time()
        local timeout = 30
        while not Svc.Condition[CharacterCondition.boundByDuty34] do
            if os.time() - start > timeout then
                RestoreYesAlreadyBother()
                yield("/echo [OCM] ERROR: Timed out waiting for duty entry.")
                return
            end
            Sleep(1)
        end

        yield("/echo [OCM] Instance loaded.")
        Sleep(5)

        RestoreYesAlreadyBother()
        State = CharacterState.ready
        return
    else
        RestoreYesAlreadyBother()
        yield("/echo [OCM] Dialog options did not appear.")
        Sleep(5)
        return
    end
end

function CharacterState.dumpSilver()
    local silverCountNow = Inventory.GetItemCount(SILVER_ITEM_ID)
    if silverCountNow < tonumber(SILVER_DUMP_LIMIT) then
        yield("/echo [OCM] Silver below threshold, returning to ready state.")
        State = CharacterState.ready
        return
    end

    TurnOffOCH()

    local selectedItem = ShopItemsByName[SILVER_PURCHASE_ITEM] or ShopItems[1]

    local shopAddon = Addons.GetAddon("ShopExchangeCurrency")
    local yesnoAddon = Addons.GetAddon("SelectYesno")
    local iconStringAddon = Addons.GetAddon("SelectIconString")
    local distanceToShop = Vector3.Distance(Entity.Player.Position, VENDOR_POS)

    if distanceToShop > VENDOR_WALK_RADIUS then
        ReturnToBaseIfAllowed()
        State = CharacterState.ready
        return
    end

    if distanceToShop > 7 then
        yield("/target " .. VENDOR_NAME)
        if not IPC.vnavmesh.PathfindInProgress() and not IPC.vnavmesh.IsRunning() then
            IPC.vnavmesh.PathfindAndMoveTo(VENDOR_POS, false)
        end
    end

    if yesnoAddon and yesnoAddon.Ready then
        yield("/callback SelectYesno true 0")

        while not (shopAddon and shopAddon.Ready) do
            Sleep(1)
            shopAddon = Addons.GetAddon("ShopExchangeCurrency")
        end

        while shopAddon and shopAddon.Ready do
            yield("/echo [OCM] Buying complete.")
            yield("/callback ShopExchangeCurrency true -1")
            shopAddon = Addons.GetAddon("ShopExchangeCurrency")
        end

        State = CharacterState.ready
        return
    end

    if shopAddon and shopAddon.Ready then
        silverCountNow = Inventory.GetItemCount(SILVER_ITEM_ID)
        if silverCountNow < tonumber(SILVER_DUMP_LIMIT) then
            yield("/echo [OCM] Silver below threshold, returning to ready state.")
            yield("/callback ShopExchangeCurrency true -1")
            State = CharacterState.ready
            return
        end

        if silverCountNow < selectedItem.price then
            yield("/echo [OCM] Not enough silver to buy selected item.")
            yield("/callback ShopExchangeCurrency true -1")
            State = CharacterState.ready
            return
        end

        local qty = math.floor(silverCountNow / selectedItem.price)
        if qty < 1 then qty = 1 end
        if qty > 99 then qty = 99 end

        yield("/echo [OCM] Purchasing " .. qty .. " " .. selectedItem.itemName)
        yield("/callback ShopExchangeCurrency true 0 " .. selectedItem.itemIndex .. " " .. qty .. " 0")
        State = CharacterState.ready
        return
    end

    if iconStringAddon and iconStringAddon.Ready then
        yield("/callback SelectIconString true " .. tostring(selectedItem.menuIndex))
        State = CharacterState.ready
        return
    end

    -- Prevent interact spam
    local shopOpen = (shopAddon and shopAddon.Ready)
    local iconOpen = (iconStringAddon and iconStringAddon.Ready)
    local yesnoOpen = (yesnoAddon and yesnoAddon.Ready)

    if not shopOpen and not iconOpen and not yesnoOpen then
        if Entity.Target and Entity.Target.Name == VENDOR_NAME
           and Vector3.Distance(Entity.Player.Position, VENDOR_POS) <= 7
           and not Svc.Condition[CharacterCondition.occupiedInQuestEvent]
        then
            yield("/interact")
            Sleep(0.5)
        end
    end

    State = CharacterState.ready
end

function CharacterState.repair()
    local repairAddon = Addons.GetAddon("Repair")
    local yesnoAddon = Addons.GetAddon("SelectYesno")
    local shopAddon = Addons.GetAddon("Shop")
    local DarkMatterItemId = 33916
    local itemsToRepair = Inventory.GetItemsInNeedOfRepairs(tonumber(durabilityAmount))

    Dalamud.LogDebug("[OCM] Repairing items...")
    TurnOffOCH()

    if Svc.Condition[CharacterCondition.occupiedMateriaExtractionAndRepair] then
        Dalamud.LogDebug("[OCM] Repairing...")
        Sleep(1)
        return
    end

    if yesnoAddon and yesnoAddon.Ready then
        yield("/callback SelectYesno true 0")
        return
    end

    if repairAddon and repairAddon.Ready then
        local itemsToRepair2 = Inventory.GetItemsInNeedOfRepairs(tonumber(durabilityAmount))
        local needsRepair = false
        if type(itemsToRepair2) == "number" then
            needsRepair = itemsToRepair2 ~= 0
        elseif type(itemsToRepair2) == "table" then
            needsRepair = next(itemsToRepair2) ~= nil
        end

        if not needsRepair then
            yield("/callback Repair true -1")
        else
            yield("/callback Repair true 0")
        end
        return
    end

    if selfRepair then
        if Inventory.GetItemCount(DarkMatterItemId) > 0 then
            if shopAddon and shopAddon.Ready then
                yield("/callback Shop true -1")
                return
            end

            if (type(itemsToRepair) == "number" and itemsToRepair ~= 0) or (type(itemsToRepair) == "table" and next(itemsToRepair) ~= nil) then
                while not (repairAddon and repairAddon.Ready) do
                    if not ExecGeneralAction(6) then
                        yield("/echo [OCM] ERROR: Actions API unavailable (cannot open Repair).")
                        running = false
                        return
                    end
                    repeat
                        Sleep(0.1)
                        repairAddon = Addons.GetAddon("Repair")
                    until repairAddon and repairAddon.Ready
                end
                State = CharacterState.ready
            else
                State = CharacterState.ready
            end
        elseif ShouldAutoBuyDarkMatter then
            local distanceToMender = Vector3.Distance(Entity.Player.Position, MENDER_POS)

            if distanceToMender > VENDOR_WALK_RADIUS then
                ReturnToBaseIfAllowed()
                return
            elseif distanceToMender > 7 then
                yield("/target " .. MENDER_NAME)
                if not IPC.vnavmesh.PathfindInProgress() and not IPC.vnavmesh.IsRunning() then
                    IPC.vnavmesh.PathfindAndMoveTo(MENDER_POS, false)
                end
            else
                local icon = Addons.GetAddon("SelectIconString")
                local yn   = Addons.GetAddon("SelectYesno")
                local shop = Addons.GetAddon("Shop")

                if not Svc.Condition[CharacterCondition.occupiedInQuestEvent] then
                    yield("/interact")
                elseif icon and icon.Ready then
                    yield("/callback SelectIconString true 0")
                elseif yn and yn.Ready then
                    yield("/callback SelectYesno true 0")
                elseif shop and shop.Ready then
                    yield("/callback Shop true 0 10 99")
                end
            end
        else
            yield("/echo Out of Dark Matter and ShouldAutoBuyDarkMatter is false. Switching to mender.")
            selfRepair = false
        end
    else
        if (type(itemsToRepair) == "number" and itemsToRepair ~= 0) or (type(itemsToRepair) == "table" and next(itemsToRepair) ~= nil) then
            local distanceToMender = Vector3.Distance(Entity.Player.Position, MENDER_POS)

            if distanceToMender > VENDOR_WALK_RADIUS then
                ReturnToBaseIfAllowed()
                return
            elseif distanceToMender > 7 then
                if not IPC.vnavmesh.PathfindInProgress() and not IPC.vnavmesh.IsRunning() then
                    IPC.vnavmesh.PathfindAndMoveTo(MENDER_POS, false)
                end
            else
                local icon = Addons.GetAddon("SelectIconString")
                if icon and icon.Ready then
                    yield("/callback SelectIconString true 1")
                else
                    yield("/target " .. MENDER_NAME)
                    if not Svc.Condition[CharacterCondition.occupiedInQuestEvent] then
                        yield("/interact")
                    end
                end
            end
        else
            State = CharacterState.ready
        end
    end
end

function CharacterState.materia()
    local materiaAddon = Addons.GetAddon("Materialize")
    local materiaDialogAddon = Addons.GetAddon("MaterializeDialog")

    TurnOffOCH()

    if Svc.Condition[CharacterCondition.occupiedMateriaExtractionAndRepair] then
        return
    end

    if Inventory.GetSpiritbondedItems().Count >= 1 and Inventory.GetFreeInventorySlots() > 1 then
        if not materiaAddon or not materiaAddon.Ready then
            yield("/echo [OCM] Opening Materia Extraction menu...")
            if not ExecGeneralAction(14) then
                yield("/echo [OCM] ERROR: Actions API unavailable (cannot open Materialize).")
                running = false
                return
            end
            repeat
                Sleep(0.1)
                materiaAddon = Addons.GetAddon("Materialize")
            until materiaAddon and materiaAddon.Ready
        end

        if materiaDialogAddon and materiaDialogAddon.Ready then
            yield("/callback MaterializeDialog true 0")
            repeat Sleep(0.1) until not Svc.Condition[CharacterCondition.occupiedMateriaExtractionAndRepair]
        else
            yield("/callback Materialize true 2 0")
        end
    else
        if materiaAddon and materiaAddon.Ready then
            yield("/callback Materialize true -1")
        else
            State = CharacterState.ready
        end
    end
end

-- Startup
State = CharacterState.ready

-- Main loop (nil guard + betweenAreas latch)
while running do
    if Svc.Condition[CharacterCondition.betweenAreas] then
        sawBetweenAreas = true
        Sleep(1)
    else
        if type(State) == "function" then
            State()
        else
            yield("/echo [OCM] ERROR: State is invalid. Stopping script.")
            running = false
            break
        end
        Sleep(1)
    end
end

OnStop()

-- Enable AutoRetainer MultiMode ONLY when we finished naturally (instance limit reached)
if finishedNaturally and ENABLE_AR_MULTIMODE_WHEN_FINISHED then
    Dalamud.LogDebug("[OCM] Enabling AutoRetainer MultiMode (finished naturally)...")
    IPC.AutoRetainer.SetMultiModeEnabled(true)
    yield("/echo [OCM] AutoRetainer MultiMode enabled.")
end

return
