--[=====[
[[SND Metadata]]
author: Aniane | Modified by baanderson40
version: 2.0.0
description: >-
  Re-enter the Occult Crescent when you're booted, and spend your silver coins! Instance timer and entries. 
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
[[End Metadata]]
--]=====]

--[[
    DO NOT TOUCH ANYTHING BELOW THIS UNLESS YOU KNOW WHAT YOU'RE DOING.
    THIS IS A SCRIPT FOR THE OCCULT CRESCENT AND IS NOT MEANT TO BE MODIFIED UNLESS YOU ARE FAMILIAR WITH LUA AND THE SND API.
    IF YOU DO NOT UNDERSTAND THE IMPLICATIONS OF CHANGING THESE VALUES, DO NOT MODIFY THEM.
  ]]

-- Imports
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

-- Constants
local OCCULT_CRESCENT = 1252
local PHANTOM_VILLAGE = 1278
local INSTANCE_ENTRY_NPC = "Jeffroy"
local ENTRY_NPC_POS = Vector3(-77.958374, 5, 15.396423)
local REENTER_DELAY = 10

--Currency variables
local silverCount = Inventory.GetItemCount(45043)

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

-- Character Conditions
CharacterCondition = {
    dead = 2,
    mounted = 4,
    inCombat = 26,
    casting = 27,
    occupiedInEvent = 31,
    occupiedInQuestEvent = 32,
    occupied = 33,
    boundByDuty34 = 34,
    occupiedMateriaExtractionAndRepair = 39,
    betweenAreas = 45,
    jumping48 = 48,
    jumping61 = 61,
    occupiedSummoningBell = 50,
    betweenAreasForDuty = 51,
    boundByDuty56 = 56,
    mounting57 = 57,
    mounting64 = 64,
    beingMoved = 70,
    flying = 77
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

-- NEW: plugin enable check (simple)
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

-- NEW: Restart BOCCHI on instance entry and wait until it's loaded again
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
        Dalamud.LogDebug("[OCM] Setting IllegalMode to false.")
        IllegalMode = false
        Dalamud.LogDebug("[OCM] Turning off BOCCHI Illegal Mode.")
        yield("/bocchillegal off")
        return
    end
    if IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() then
        Dalamud.LogDebug("[OCM] Stopping pathfinding...")
        yield("/vnav stop")
        return
    end
    if IPC.Lifestream.IsBusy() then
        Dalamud.LogDebug("[OCM] Stopping Lifestream...")
        yield("/li stop")
        return
    end
    Dalamud.LogDebug("[OCM] Turning off BMR.")
    yield("/bmrai off")
end

local function ReturnToBase()
    yield("/gaction Return")
    repeat
        Sleep(1)
    until not Svc.Condition[CharacterCondition.casting]
    repeat
        Sleep(1)
    until not Svc.Condition[CharacterCondition.betweenAreas]
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

    while Svc.Condition[CharacterCondition.boundByDuty34] do
        Sleep(1)
    end
end

function OnStop()
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
    yield("/echo [OCM] Script stopped.")
end

-- State Implementations
IllegalMode = false
function CharacterState.ready()
    while Svc.Condition[CharacterCondition.betweenAreas] do
        Sleep(0.1)
    end

    local inInstance = Svc.Condition[CharacterCondition.boundByDuty34] and Svc.ClientState.TerritoryType == OCCULT_CRESCENT
    local silverCountNow = Inventory.GetItemCount(45043)
    local itemsToRepair = Inventory.GetItemsInNeedOfRepairs(tonumber(durabilityAmount))
    local needsRepair = false
    local shopAddon = Addons.GetAddon("ShopExchangeCurrency")

    -- If for some reason the shop addon is visible, close it
    if silverCountNow < tonumber(SILVER_DUMP_LIMIT) and shopAddon and shopAddon.Ready then
        yield("/callback ShopExchangeCurrency true -1")
    end

    -- Instance enter/exit tracking
    if inInstance and not wasInInstance then
        -- Restart BOCCHI on entry (covers re-entry and starting script already inside)
        RestartBOCCHI()

        instanceStartTime = os.time()
        yield("/echo [OCM] Entered instance. Timer started (" .. tostring(INSTANCE_DURATION_MIN) .. "m).")
    end

    if (not inInstance) and wasInInstance then
        completedInstances = completedInstances + 1
        yield("/echo [OCM] Instance ended. Completed instances: " .. tostring(completedInstances) .. "/" .. tostring(INSTANCE_LIMIT))
        instanceStartTime = nil

        local limit = tonumber(INSTANCE_LIMIT) or 0
        if limit > 0 and completedInstances >= limit then
            yield("/echo [OCM] Instance limit reached. Stopping script.")
            finishedNaturally = true
            running = false
            return
        end
    end

    wasInInstance = inInstance

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
    elseif not inInstance and Svc.ClientState.TerritoryType == PHANTOM_VILLAGE then
        State = CharacterState.reenterInstance
        Dalamud.LogDebug("[OCM] State changed to reenterInstance")
    elseif needsRepair then
        Dalamud.LogDebug("[OCM] State changed to repair")
        State = CharacterState.repair
    elseif ShouldExtractMateria and Inventory.GetSpiritbondedItems().Count > 0 then
        Dalamud.LogDebug("[OCM] State changed to extract materia")
        State = CharacterState.materia
    elseif spendSilver and silverCountNow >= tonumber(SILVER_DUMP_LIMIT) then
        Dalamud.LogDebug("[OCM] State changed to dumpSilver")
        State = CharacterState.dumpSilver
    elseif not IllegalMode then
        Dalamud.LogDebug("[OCM] State changed to ready")
        TurnOnOCH()
    end
end

function CharacterState.zoneIn()
    local instanceEntryAddon = Addons.GetAddon("ContentsFinderConfirm")
    local SelectString = Addons.GetAddon("SelectString")
    local Talked = false
    if Svc.Condition[CharacterCondition.betweenAreas] then
        Sleep(3)
    elseif Svc.ClientState.TerritoryType == PHANTOM_VILLAGE then
        LogInfo("[OCM] Already in Phantom Village")
        if Vector3.Distance(Entity.Player.Position, ENTRY_NPC_POS) >= 5 then
            IPC.vnavmesh.PathfindAndMoveTo(ENTRY_NPC_POS, false)
        elseif IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.PathIsRunning() then
            yield("/vnav stop")
        elseif Entity.GetEntityByName(INSTANCE_ENTRY_NPC) ~= INSTANCE_ENTRY_NPC then
            yield("/target " .. INSTANCE_ENTRY_NPC)
        elseif instanceEntryAddon and instanceEntryAddon.ready then
            yield("/callback ContentsFinderConfirm true 8")
            yield("/echo [OCM] Re-entry confirmed.")
        elseif SelectString and SelectString.ready then
            yield("/callback SelectString true 0")
        elseif not Talked then
            Talked = true
            yield("/interact")
        end
    elseif Svc.ClientState.TerritoryType ~=OCCULT_CRESCENT then
        yield("/li occult")
        repeat
            Sleep(1)
        until not IPC.Lifestream.IsBusy()
    elseif Svc.ClientState.TerritoryType == OCCULT_CRESCENT then
        if Player.Available then
            Talked = false
            TurnOnOCH()
        end
    end
    State = CharacterState.ready
end

function CharacterState.reenterInstance()
    local YesAlready = IPC.YesAlready.IsPluginEnabled()
    if YesAlready then
        IPC.YesAlready.PauseBother("ContentsFinderConfirm", 120000) -- Pause YesAlready for 2 minutes to prevent instance entry issues
    end

    yield("/echo [OCM] Detected exit from duty. Waiting " .. REENTER_DELAY .. " seconds before re-entry...")
    IllegalMode = false
    Sleep(REENTER_DELAY)

    local npc = Entity.GetEntityByName(INSTANCE_ENTRY_NPC)
    if not npc then
        yield("/echo [OCM] Could not find " .. INSTANCE_ENTRY_NPC .. ". Retrying in 10 seconds...")
        Sleep(10)
        return
    end

    yield("/target " .. INSTANCE_ENTRY_NPC)
    Sleep(1)
    yield("/interact")
    Sleep(1)

    if WaitForAddon("SelectString", 5) then
        Sleep(0.5)
        yield("/callback SelectString true 0")
        Sleep(0.5)
        yield("/callback SelectString true 0")
        Sleep(0.5)

        while not Svc.Condition[CharacterCondition.boundByDuty34] do
            Sleep(1)
        end

        yield("/echo [OCM] Instance loaded.")

        Sleep(5)
        State = CharacterState.ready
    else
        yield("/echo [OCM] Dialog options did not appear.")
        Sleep(5)
    end
end

function CharacterState.dumpSilver()
    local silverCountNow = Inventory.GetItemCount(45043)
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
    local baseToShop = Vector3.Distance(BaseAetheryte, VENDOR_POS) + 50
    local distanceToShop = Vector3.Distance(Entity.Player.Position, VENDOR_POS)

    if distanceToShop > baseToShop then
        ReturnToBase()
    elseif distanceToShop > 7 then
        yield("/target " .. VENDOR_NAME)
        if not IPC.vnavmesh.PathfindInProgress() and not IPC.vnavmesh.IsRunning() then
            IPC.vnavmesh.PathfindAndMoveTo(VENDOR_POS, false)
        end
    end

    -- Buy selected item
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

    elseif shopAddon and shopAddon.Ready then
        silverCountNow = Inventory.GetItemCount(45043)
        if silverCountNow < tonumber(SILVER_DUMP_LIMIT) then
            yield("/echo [OCM] Silver below threshold, returning to ready state.")
            yield("/callback ShopExchangeCurrency true -1")
            State = CharacterState.ready
            return
        end

        local qty = math.floor(silverCountNow / selectedItem.price)
        if qty < 1 then qty = 1 end

        yield("/echo [OCM] Purchasing " .. qty .. " " .. selectedItem.itemName)
        yield("/callback ShopExchangeCurrency true 0 " .. selectedItem.itemIndex .. " " .. qty .. " 0")
        State = CharacterState.ready
        return

    elseif iconStringAddon and iconStringAddon.Ready then
        yield("/callback SelectIconString true " .. tostring(selectedItem.menuIndex))
        State = CharacterState.ready
        return
    end

    yield("/interact")
    Sleep(1)

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
        Dalamud.LogDebug("[OCM] Checking if repairs are needed...")
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
        Dalamud.LogDebug("[OCM] Checking for Dark Matter...")
        if Inventory.GetItemCount(DarkMatterItemId) > 0 then
            Dalamud.LogDebug("[OCM] Dark Matter in inventory...")
            if shopAddon and shopAddon.Ready then
                yield("/callback Shop true -1")
                return
            end

            if (type(itemsToRepair) == "number" and itemsToRepair ~= 0) or (type(itemsToRepair) == "table" and next(itemsToRepair) ~= nil) then
                Dalamud.LogDebug("[OCM] Items in need of repair...")
                while not (repairAddon and repairAddon.Ready) do
                    Dalamud.LogDebug("[OCM] Opening repair menu...")
                    Actions.ExecuteGeneralAction(6)
                    repeat
                        Sleep(0.1)
                        repairAddon = Addons.GetAddon("Repair")
                    until repairAddon and repairAddon.Ready
                end
                State = CharacterState.ready
                Dalamud.LogDebug("[OCM] State Change: Ready")
            else
                State = CharacterState.ready
                Dalamud.LogDebug("[OCM] State Change: Ready")
            end
        elseif ShouldAutoBuyDarkMatter then
            local baseToMender = Vector3.Distance(BaseAetheryte, MENDER_POS) + 50
            local distanceToMender = Vector3.Distance(Entity.Player.Position, MENDER_POS)
            if distanceToMender > baseToMender then
                ReturnToBase()
                return
            elseif distanceToMender > 7 then
                yield("/target " .. MENDER_NAME)
                if not IPC.vnavmesh.PathfindInProgress() and not IPC.vnavmesh.IsRunning() then
                    IPC.vnavmesh.PathfindAndMoveTo(MENDER_POS, false)
                end
            else
                if not Svc.Condition[CharacterCondition.occupiedInQuestEvent] then
                    yield("/interact")
                elseif Addons.GetAddon("SelectIconString") then
                    yield("/callback SelectIconString true 0")
                elseif Addons.GetAddon("SelectYesno") then
                    yield("/callback SelectYesno true 0")
                elseif Addons.GetAddon("Shop") then
                    yield("/callback Shop true 0 10 99")
                end
            end
        else
            yield("/echo Out of Dark Matter and ShouldAutoBuyDarkMatter is false. Switching to mender.")
            SelfRepair = false
        end
    else
        if (type(itemsToRepair) == "number" and itemsToRepair ~= 0) or (type(itemsToRepair) == "table" and next(itemsToRepair) ~= nil) then
            local baseToMender = Vector3.Distance(BaseAetheryte, MENDER_POS) + 50
            local distanceToMender = Vector3.Distance(Entity.Player.Position, MENDER_POS)
            if distanceToMender > baseToMender then
                ReturnToBase()
                return
            elseif distanceToMender > 7 then
                if not IPC.vnavmesh.PathfindInProgress() and not IPC.vnavmesh.IsRunning() then
                    IPC.vnavmesh.PathfindAndMoveTo(MENDER_POS, false)
                end
            elseif Addons.GetAddon("SelectIconString") then
                yield("/callback SelectIconString true 1")
            else
                yield("/target "..MENDER_NAME)
                if not Svc.Condition[CharacterCondition.occupiedInQuestEvent] then
                    yield("/interact")
                end
            end
        else
            State = CharacterState.ready
            Dalamud.LogDebug("[OCM] State Change: Ready")
        end
    end
end

function CharacterState.materia()
    local materiaAddon = Addons.GetAddon("Materialize")
    local materiaDialogAddon = Addons.GetAddon("MaterializeDialog")

    TurnOffOCH()

    if Svc.Condition[CharacterCondition.occupiedMateriaExtractionAndRepair] then
        Dalamud.LogDebug("[OCM] Already extracting materia...")
        return
    end

    if Inventory.GetSpiritbondedItems().Count >= 1 and Inventory.GetFreeInventorySlots() > 1 then
        if not materiaAddon or not materiaAddon.Ready then
            yield("/echo [OCM] Opening Materia Extraction menu...")
            Actions.ExecuteGeneralAction(14)
            repeat
                Sleep(0.1)
                materiaAddon = Addons.GetAddon("Materialize")
            until materiaAddon and materiaAddon.Ready
        end

        if materiaDialogAddon and materiaDialogAddon.Ready then
            yield("/callback MaterializeDialog true 0")
            repeat
                Sleep(0.1)
            until not Svc.Condition[CharacterCondition.occupiedMateriaExtractionAndRepair]
        else
            yield("/callback Materialize true 2 0")
        end
    else
        if materiaAddon and materiaAddon.Ready then
            yield("/callback Materialize true -1")
            Dalamud.LogDebug("[OCM] No spiritbonded items to extract materia from.")
        else
            State = CharacterState.ready
        end
    end
end

-- Startup
State = CharacterState.ready

-- Main loop
while running do
    while Svc.Condition[CharacterCondition.betweenAreas] do
        Sleep(1)
    end
    State()
    Sleep(1)
end

OnStop()

-- Enable AutoRetainer MultiMode ONLY when we finished naturally (instance limit reached)
if finishedNaturally and ENABLE_AR_MULTIMODE_WHEN_FINISHED then
    Dalamud.LogDebug("[OCM] Enabling AutoRetainer MultiMode (finished naturally)...")
    IPC.AutoRetainer.SetMultiModeEnabled(true)
    yield("/echo [OCM] AutoRetainer MultiMode enabled.")
end

return
