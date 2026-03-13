--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.0.0
description: |
  Toolkit Helper pairs with Fate Tool Kit automation to pause farming whenever retainers finish ventures.
  - Polls AutoRetainer venture timers while Tool Kit runs other tasks
  - Teleports to the Limsa summoning bell and interacts automatically
  - Hands UI back to AutoRetainer, then resumes idle monitoring for the toolkit
plugin_dependencies:
- AutoRetainer
- vnavmesh
- TextAdvance
configs:
  Pause for retainers?:
    description:
    default: true
  Close Retainer List when done?:
    description:
    default: true
  Echo logs:
    description:
    default: "None"
    is_choice: true
    choices: ["All", "None"]
  Check interval (seconds):
    description:
    default: 60
    min: 5
    max: 300
  Maintain gemstone stockpile?:
    description:
    default: true
  Gemstone stockpile target:
    description:
    default: 1500
    min: 100
    max: 2000
  Exchange bicolor gemstones for:
    description:
    default: "Turali Bicolor Gemstone Voucher"
    is_choice: true
    choices: ["None",
        "Alexandrian Axe Beak Wing",
        "Alpaca Fillet",
        "Almasty Fur",
        "Amra",
        "Berkanan Sap",
        "Bicolor Gemstone Voucher",
        "Bird of Elpis Breast",
        "Branchbearer Fruit",
        "Br'aax Hide",
        "Dynamis Crystal",
        "Dynamite Ash",
        "Egg of Elpis",
        "Gaja Hide",
        "Gargantua Hide",
        "Gomphotherium Skin",
        "Hammerhead Crocodile Skin",
        "Hamsa Tenderloin",
        "Kumbhira Skin",
        "Lesser Apollyon Shell",
        "Lunatender Blossom",
        "Luncheon Toad Skin",
        "Megamaguey Pineapple",
        "Mousse Flesh",
        "Nopalitender Tuna",
        "Ovibos Milk",
        "Ophiotauros Hide",
        "Petalouda Scales",
        "Poison Frog Secretions",
        "Rroneek Chuck",
        "Rroneek Fleece",
        "Saiga Hide",
        "Silver Lobo Hide",
        "Swampmonk Thigh",
        "Tumbleclaw Weeds",
        "Turali Bicolor Gemstone Voucher",
        "Ty'aitya Wingblade"]
[[End Metadata]]
--]=====]

import("System.Numerics")

--#region Data

CharacterCondition = {
    dead=2,
    mounted=4,
    inCombat=26,
    casting=27,
    occupiedInEvent=31,
    occupiedInQuestEvent=32,
    occupied=33,
    boundByDuty34=34,
    occupiedMateriaExtractionAndRepair=39,
    betweenAreas=45,
    jumping48=48,
    jumping61=61,
    occupiedSummoningBell=50,
    betweenAreasForDuty=51,
    boundByDuty56=56,
    mounting57=57,
    mounting64=64,
    beingMoved=70,
    flying=77
}

local SUMMONING_BELL = {
    rowId = 20000401,
    name = "Summoning Bell",
    position = Vector3(-122.72, 18.00, 20.39),
    territoryId = 129,
    aetheryteRowId = 8,
    aetheryteName = nil,
    aetheryteId = nil
}

local function Vec3(x, y, z)
    return Vector3(x, y, z)
end

local GemstoneExchangeMap = {
    ["Alexandrian Axe Beak Wing"] = {
        itemId = 44072,
        itemIndex = 21,
        price = 3,
        vendorId = 1049082,
        vendorName = "Beryl",
        territoryId = 1186,
        position = Vec3(-198.47, 0.92, -6.95),
        aetheryte = { rowId = 217, name = "Solution Nine" },
        miniAetheryte = { rowId = 235, name = "Nexus Arcade", isMini = true }
    },
    ["Alpaca Fillet"] = {
        itemId = 44063,
        itemIndex = 7,
        price = 3,
        vendorId = 1049082,
        vendorName = "Beryl",
        territoryId = 1186,
        position = Vec3(-198.47, 0.92, -6.95),
        aetheryte = { rowId = 217, name = "Solution Nine" },
        miniAetheryte = { rowId = 235, name = "Nexus Arcade", isMini = true }
    },
    ["Almasty Fur"] = {
        itemId = 36203,
        itemIndex = 16,
        price = 2,
        vendorId = 1037055,
        vendorName = "Gadfrid",
        territoryId = 962,
        position = Vec3(78, 5, -37),
        aetheryte = { rowId = 182, name = "Old Sharlayan" }
    },
    ["Amra"] = {
        itemId = 36264,
        itemIndex = 14,
        price = 2,
        vendorId = 1037055,
        vendorName = "Gadfrid",
        territoryId = 962,
        position = Vec3(78, 5, -37),
        aetheryte = { rowId = 182, name = "Old Sharlayan" }
    },
    ["Berkanan Sap"] = {
        itemId = 36261,
        itemIndex = 22,
        price = 2,
        vendorId = 1037055,
        vendorName = "Gadfrid",
        territoryId = 962,
        position = Vec3(78, 5, -37),
        aetheryte = { rowId = 182, name = "Old Sharlayan" }
    },
    ["Bicolor Gemstone Voucher"] = {
        itemId = 35833,
        itemIndex = 8,
        price = 100,
        vendorId = 1037055,
        vendorName = "Gadfrid",
        territoryId = 962,
        position = Vec3(78, 5, -37),
        aetheryte = { rowId = 182, name = "Old Sharlayan" }
    },
    ["Bird of Elpis Breast"] = {
        itemId = 36630,
        itemIndex = 12,
        price = 2,
        vendorId = 1037055,
        vendorName = "Gadfrid",
        territoryId = 962,
        position = Vec3(78, 5, -37),
        aetheryte = { rowId = 182, name = "Old Sharlayan" }
    },
    ["Branchbearer Fruit"] = {
        itemId = 44065,
        itemIndex = 11,
        price = 3,
        vendorId = 1049082,
        vendorName = "Beryl",
        territoryId = 1186,
        position = Vec3(-198.47, 0.92, -6.95),
        aetheryte = { rowId = 217, name = "Solution Nine" },
        miniAetheryte = { rowId = 235, name = "Nexus Arcade", isMini = true }
    },
    ["Br'aax Hide"] = {
        itemId = 44055,
        itemIndex = 16,
        price = 3,
        vendorId = 1049082,
        vendorName = "Beryl",
        territoryId = 1186,
        position = Vec3(-198.47, 0.92, -6.95),
        aetheryte = { rowId = 217, name = "Solution Nine" },
        miniAetheryte = { rowId = 235, name = "Nexus Arcade", isMini = true }
    },
    ["Dynamis Crystal"] = {
        itemId = 36262,
        itemIndex = 15,
        price = 2,
        vendorId = 1037055,
        vendorName = "Gadfrid",
        territoryId = 962,
        position = Vec3(78, 5, -37),
        aetheryte = { rowId = 182, name = "Old Sharlayan" }
    },
    ["Dynamite Ash"] = {
        itemId = 36259,
        itemIndex = 23,
        price = 2,
        vendorId = 1037055,
        vendorName = "Gadfrid",
        territoryId = 962,
        position = Vec3(78, 5, -37),
        aetheryte = { rowId = 182, name = "Old Sharlayan" }
    },
    ["Egg of Elpis"] = {
        itemId = 36256,
        itemIndex = 13,
        price = 2,
        vendorId = 1037055,
        vendorName = "Gadfrid",
        territoryId = 962,
        position = Vec3(78, 5, -37),
        aetheryte = { rowId = 182, name = "Old Sharlayan" }
    },
    ["Gaja Hide"] = {
        itemId = 36242,
        itemIndex = 17,
        price = 2,
        vendorId = 1037055,
        vendorName = "Gadfrid",
        territoryId = 962,
        position = Vec3(78, 5, -37),
        aetheryte = { rowId = 182, name = "Old Sharlayan" }
    },
    ["Gargantua Hide"] = {
        itemId = 44057,
        itemIndex = 18,
        price = 3,
        vendorId = 1049082,
        vendorName = "Beryl",
        territoryId = 1186,
        position = Vec3(-198.47, 0.92, -6.95),
        aetheryte = { rowId = 217, name = "Solution Nine" },
        miniAetheryte = { rowId = 235, name = "Nexus Arcade", isMini = true }
    },
    ["Gomphotherium Skin"] = {
        itemId = 44056,
        itemIndex = 17,
        price = 3,
        vendorId = 1049082,
        vendorName = "Beryl",
        territoryId = 1186,
        position = Vec3(-198.47, 0.92, -6.95),
        aetheryte = { rowId = 217, name = "Solution Nine" },
        miniAetheryte = { rowId = 235, name = "Nexus Arcade", isMini = true }
    },
    ["Hammerhead Crocodile Skin"] = {
        itemId = 44054,
        itemIndex = 15,
        price = 3,
        vendorId = 1049082,
        vendorName = "Beryl",
        territoryId = 1186,
        position = Vec3(-198.47, 0.92, -6.95),
        aetheryte = { rowId = 217, name = "Solution Nine" },
        miniAetheryte = { rowId = 235, name = "Nexus Arcade", isMini = true }
    },
    ["Hamsa Tenderloin"] = {
        itemId = 36253,
        itemIndex = 10,
        price = 2,
        vendorId = 1037055,
        vendorName = "Gadfrid",
        territoryId = 962,
        position = Vec3(78, 5, -37),
        aetheryte = { rowId = 182, name = "Old Sharlayan" }
    },
    ["Kumbhira Skin"] = {
        itemId = 36245,
        itemIndex = 20,
        price = 2,
        vendorId = 1037055,
        vendorName = "Gadfrid",
        territoryId = 962,
        position = Vec3(78, 5, -37),
        aetheryte = { rowId = 182, name = "Old Sharlayan" }
    },
    ["Lesser Apollyon Shell"] = {
        itemId = 44069,
        itemIndex = 22,
        price = 3,
        vendorId = 1049082,
        vendorName = "Beryl",
        territoryId = 1186,
        position = Vec3(-198.47, 0.92, -6.95),
        aetheryte = { rowId = 217, name = "Solution Nine" },
        miniAetheryte = { rowId = 235, name = "Nexus Arcade", isMini = true }
    },
    ["Lunatender Blossom"] = {
        itemId = 36258,
        itemIndex = 24,
        price = 2,
        vendorId = 1037055,
        vendorName = "Gadfrid",
        territoryId = 962,
        position = Vec3(78, 5, -37),
        aetheryte = { rowId = 182, name = "Old Sharlayan" }
    },
    ["Luncheon Toad Skin"] = {
        itemId = 36243,
        itemIndex = 18,
        price = 2,
        vendorId = 1037055,
        vendorName = "Gadfrid",
        territoryId = 962,
        position = Vec3(78, 5, -37),
        aetheryte = { rowId = 182, name = "Old Sharlayan" }
    },
    ["Megamaguey Pineapple"] = {
        itemId = 44067,
        itemIndex = 10,
        price = 3,
        vendorId = 1049082,
        vendorName = "Beryl",
        territoryId = 1186,
        position = Vec3(-198.47, 0.92, -6.95),
        aetheryte = { rowId = 217, name = "Solution Nine" },
        miniAetheryte = { rowId = 235, name = "Nexus Arcade", isMini = true }
    },
    ["Mousse Flesh"] = {
        itemId = 36257,
        itemIndex = 25,
        price = 2,
        vendorId = 1037055,
        vendorName = "Gadfrid",
        territoryId = 962,
        position = Vec3(78, 5, -37),
        aetheryte = { rowId = 182, name = "Old Sharlayan" }
    },
    ["Nopalitender Tuna"] = {
        itemId = 44066,
        itemIndex = 12,
        price = 3,
        vendorId = 1049082,
        vendorName = "Beryl",
        territoryId = 1186,
        position = Vec3(-198.47, 0.92, -6.95),
        aetheryte = { rowId = 217, name = "Solution Nine" },
        miniAetheryte = { rowId = 235, name = "Nexus Arcade", isMini = true }
    },
    ["Ovibos Milk"] = {
        itemId = 36255,
        itemIndex = 9,
        price = 2,
        vendorId = 1037055,
        vendorName = "Gadfrid",
        territoryId = 962,
        position = Vec3(78, 5, -37),
        aetheryte = { rowId = 182, name = "Old Sharlayan" }
    },
    ["Ophiotauros Hide"] = {
        itemId = 36246,
        itemIndex = 21,
        price = 2,
        vendorId = 1037055,
        vendorName = "Gadfrid",
        territoryId = 962,
        position = Vec3(78, 5, -37),
        aetheryte = { rowId = 182, name = "Old Sharlayan" }
    },
    ["Petalouda Scales"] = {
        itemId = 36260,
        itemIndex = 26,
        price = 2,
        vendorId = 1037055,
        vendorName = "Gadfrid",
        territoryId = 962,
        position = Vec3(78, 5, -37),
        aetheryte = { rowId = 182, name = "Old Sharlayan" }
    },
    ["Poison Frog Secretions"] = {
        itemId = 44068,
        itemIndex = 20,
        price = 3,
        vendorId = 1049082,
        vendorName = "Beryl",
        territoryId = 1186,
        position = Vec3(-198.47, 0.92, -6.95),
        aetheryte = { rowId = 217, name = "Solution Nine" },
        miniAetheryte = { rowId = 235, name = "Nexus Arcade", isMini = true }
    },
    ["Rroneek Chuck"] = {
        itemId = 44106,
        itemIndex = 9,
        price = 3,
        vendorId = 1049082,
        vendorName = "Beryl",
        territoryId = 1186,
        position = Vec3(-198.47, 0.92, -6.95),
        aetheryte = { rowId = 217, name = "Solution Nine" },
        miniAetheryte = { rowId = 235, name = "Nexus Arcade", isMini = true }
    },
    ["Rroneek Fleece"] = {
        itemId = 44027,
        itemIndex = 13,
        price = 3,
        vendorId = 1049082,
        vendorName = "Beryl",
        territoryId = 1186,
        position = Vec3(-198.47, 0.92, -6.95),
        aetheryte = { rowId = 217, name = "Solution Nine" },
        miniAetheryte = { rowId = 235, name = "Nexus Arcade", isMini = true }
    },
    ["Saiga Hide"] = {
        itemId = 36244,
        itemIndex = 19,
        price = 2,
        vendorId = 1037055,
        vendorName = "Gadfrid",
        territoryId = 962,
        position = Vec3(78, 5, -37),
        aetheryte = { rowId = 182, name = "Old Sharlayan" }
    },
    ["Silver Lobo Hide"] = {
        itemId = 44053,
        itemIndex = 14,
        price = 3,
        vendorId = 1049082,
        vendorName = "Beryl",
        territoryId = 1186,
        position = Vec3(-198.47, 0.92, -6.95),
        aetheryte = { rowId = 217, name = "Solution Nine" },
        miniAetheryte = { rowId = 235, name = "Nexus Arcade", isMini = true }
    },
    ["Swampmonk Thigh"] = {
        itemId = 44064,
        itemIndex = 8,
        price = 3,
        vendorId = 1049082,
        vendorName = "Beryl",
        territoryId = 1186,
        position = Vec3(-198.47, 0.92, -6.95),
        aetheryte = { rowId = 217, name = "Solution Nine" },
        miniAetheryte = { rowId = 235, name = "Nexus Arcade", isMini = true }
    },
    ["Tumbleclaw Weeds"] = {
        itemId = 44071,
        itemIndex = 23,
        price = 3,
        vendorId = 1049082,
        vendorName = "Beryl",
        territoryId = 1186,
        position = Vec3(-198.47, 0.92, -6.95),
        aetheryte = { rowId = 217, name = "Solution Nine" },
        miniAetheryte = { rowId = 235, name = "Nexus Arcade", isMini = true }
    },
    ["Turali Bicolor Gemstone Voucher"] = {
        itemId = 43961,
        itemIndex = 6,
        price = 100,
        vendorId = 1049082,
        vendorName = "Beryl",
        territoryId = 1186,
        position = Vec3(-198.47, 0.92, -6.95),
        aetheryte = { rowId = 217, name = "Solution Nine" },
        miniAetheryte = { rowId = 235, name = "Nexus Arcade", isMini = true }
    },
    ["Ty'aitya Wingblade"] = {
        itemId = 44070,
        itemIndex = 19,
        price = 3,
        vendorId = 1049082,
        vendorName = "Beryl",
        territoryId = 1186,
        position = Vec3(-198.47, 0.92, -6.95),
        aetheryte = { rowId = 217, name = "Solution Nine" },
        miniAetheryte = { rowId = 235, name = "Nexus Arcade", isMini = true }
    }
}

local ItemNameCache = {}
local NpcNameCache = {}
local EObjNameCache = {}

local function GetItemNameByRowId(rowId)
    if not rowId then return nil end
    if ItemNameCache[rowId] ~= nil then
        return ItemNameCache[rowId]
    end
    if not Excel or not Excel.GetSheet then
        return nil
    end
    local sheet = Excel.GetSheet("Item")
    if not sheet then return nil end
    local row = sheet:GetRow(rowId)
    if not row or not row.Name then return nil end
    local rawName = row.Name
    local text = rawName
    if rawName and rawName.GetText then
        text = rawName:GetText()
    end
    text = tostring(text or "")
    if text ~= nil and text ~= "" then
        ItemNameCache[rowId] = text
        return text
    end
    return nil
end

local function GetNpcNameByRowId(rowId)
    if not rowId then return nil end
    if NpcNameCache[rowId] ~= nil then
        return NpcNameCache[rowId]
    end
    if not Excel or not Excel.GetSheet then
        return nil
    end
    local sheet = Excel.GetSheet("ENpcResident")
    if not sheet then return nil end
    local row = sheet:GetRow(rowId)
    if not row then return nil end
    local name = row.Singular or row.Name
    if name == nil then return nil end
    local text = name
    if name.GetText then
        text = name:GetText()
    end
    text = tostring(text or "")
    if text ~= nil and text ~= "" then
        NpcNameCache[rowId] = text
        return text
    end
    return nil
end

local function GetEObjNameByRowId(rowId)
    if not rowId then return nil end
    if EObjNameCache[rowId] ~= nil then
        return EObjNameCache[rowId]
    end
    if not Excel or not Excel.GetSheet then
        return nil
    end
    local sheet = Excel.GetSheet("EObjName")
    if not sheet then return nil end
    local row = sheet:GetRow(rowId)
    if not row then return nil end
    local textSource = row.Singular or row.Name or row.Unknown0
    if textSource == nil and row.Text then
        textSource = row.Text
    end
    local text = textSource
    if textSource and textSource.GetText then
        text = textSource:GetText()
    end
    text = tostring(text or "")
    if text ~= nil and text ~= "" then
        EObjNameCache[rowId] = text
        return text
    end
    return nil
end

FateState = {
    None       = 0,
    Preparing  = 1,
    Waiting    = 2,
    Spawning   = 3,
    Running    = 4,
    Ending     = 5,
    Ended      = 6,
    Failed     = 7
}

--#endregion Data

--#region Config & Runtime

Settings = {
    echoLevel = "none",
    checkInterval = 60,
    closeRetainerList = true,
    waitIfBonusBuff = true,
    pauseRetainers = true,
    maintainGemstones = false,
    gemstoneTarget = 1000,
    gemstonesPerRun = 14,
    maxGemstoneRunWait = 900,
    bicolorItem = "None",
    exchangeGemstones = false
}

local function RefreshSettings()
    local echo = Config.Get("Echo logs")
    if type(echo) == "string" then
        Settings.echoLevel = string.lower(echo)
    end

    local interval = Config.Get("Check interval (seconds)")
    if type(interval) == "number" then
        Settings.checkInterval = math.max(5, math.min(300, interval))
    end

    local closeList = Config.Get("Close Retainer List when done?")
    if closeList ~= nil then
        Settings.closeRetainerList = closeList
    end

    local pauseRetainers = Config.Get("Pause for retainers?")
    if pauseRetainers ~= nil then
        Settings.pauseRetainers = pauseRetainers
    end

    local maintainGemstones = Config.Get("Maintain gemstone stockpile?")
    if maintainGemstones ~= nil then
        Settings.maintainGemstones = maintainGemstones
    end

    local gemstoneTarget = Config.Get("Gemstone stockpile target")
    if type(gemstoneTarget) == "number" then
        Settings.gemstoneTarget = math.max(0, gemstoneTarget)
    end

    local bicolorItem = Config.Get("Exchange bicolor gemstones for")
    if type(bicolorItem) == "string" then
        Settings.bicolorItem = bicolorItem
    end

    Settings.exchangeGemstones = Settings.maintainGemstones
        and type(Settings.bicolorItem) == "string"
        and Settings.bicolorItem ~= "None"
end

RefreshSettings()

Runtime = {
    stopScript = false,
    nextCheck = 0,
    lastTeleport = -math.huge,
    returnAetheryteName = nil,
    returnTerritoryId = nil,
    returnAetheryteId = nil,
    pendingGemstoneGoal = nil,
    lastGemstoneCheck = 0,
    gemstoneRunIssuedAt = nil,
    featureLogPrinted = false,
    exchangeInProgress = false,
    exchangeStarted = false,
    usedMiniTeleport = false,
    nextExchangeCheck = 0,
    retainerToolkitStopped = false,
    exchangeDelayActive = false,
    lastExchangeDelayLog = 0,
    lastLifestreamCommand = 0
}

--#endregion Config & Runtime

--#region Helpers

local function EchoAll(message)
    if Settings.echoLevel == "all" then
        yield("/echo [Toolkit Helper] "..message)
    end
end

function DistanceBetween(pos1, pos2)
    local dx = pos1.X - pos2.X
    local dy = pos1.Y - pos2.Y
    local dz = pos1.Z - pos2.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function GetDistanceToPoint(vec3)
    if Svc.ClientState.LocalPlayer == nil then
        return math.maxinteger
    end
    return DistanceBetween(Svc.ClientState.LocalPlayer.Position, vec3)
end

function GetTargetName()
    if Svc.Targets.Target == nil then
        return ""
    end
    local nameNode = Svc.Targets.Target.Name
    if nameNode ~= nil then
        local text = nameNode:GetText()
        if text ~= nil then
            return text
        end
    end
    return ""
end

local function _get_addon(name)
    local ok, addon = pcall(Addons.GetAddon, name)
    if ok and addon ~= nil then
        return addon
    end
    return nil
end

local function _addon_ready(addon)
    if not addon then return false end
    if addon.Ready == true or addon.IsReady == true or addon.Loaded == true then
        return true
    end
    if type(addon.Ready) == "function" then
        local ok, v = pcall(addon.Ready, addon)
        if ok and v then return true end
    end
    if type(addon.IsReady) == "function" then
        local ok, v = pcall(addon.IsReady, addon)
        if ok and v then return true end
    end
    return false
end

local function _addon_exists(addon)
    if not addon then return false end
    if addon.Exists == true or addon.Visible == true or addon.IsVisible == true or addon.IsOpen == true or addon.IsShown == true then
        return true
    end
    if type(addon.Exists) == "function" then
        local ok, v = pcall(addon.Exists, addon)
        if ok and v then return true end
    end
    if type(addon.IsVisible) == "function" then
        local ok, v = pcall(addon.IsVisible, addon)
        if ok and v then return true end
    end
    if _addon_ready(addon) then return true end
    return false
end

local function WaitForAddonReady(name, timeout)
    local untilTime = os.clock() + (timeout or 5)
    repeat
        local addon = _get_addon(name)
        if _addon_ready(addon) then
            return addon
        end
        yield("/wait 0.1")
    until os.clock() > untilTime
    return nil
end

local function WaitForAddonVisible(name, timeout)
    local untilTime = os.clock() + (timeout or 5)
    repeat
        local addon = _get_addon(name)
        if _addon_exists(addon) then
            return addon
        end
        yield("/wait 0.1")
    until os.clock() > untilTime
    return nil
end

local function WaitForAddonClosed(name, timeout)
    local untilTime = os.clock() + (timeout or 5)
    repeat
        local addon = _get_addon(name)
        if not _addon_exists(addon) then
            return true
        end
        yield("/wait 0.1")
    until os.clock() > untilTime
    return false
end

local function StopVnav()
    if not IPC or not IPC.vnavmesh then
        return
    end
    local shouldStop = false
    if IPC.vnavmesh.PathfindInProgress then
        local ok, pathing = pcall(IPC.vnavmesh.PathfindInProgress)
        if ok and pathing then
            shouldStop = true
        end
    end
    if not shouldStop and IPC.vnavmesh.IsRunning then
        local ok, running = pcall(IPC.vnavmesh.IsRunning)
        if ok and running then
            shouldStop = true
        end
    end
    if shouldStop and IPC.vnavmesh.Stop then
        pcall(IPC.vnavmesh.Stop)
    end
end

local function WaitForPlayerStationary(timeout)
    local deadline = os.clock() + (timeout or 5)
    while Player ~= nil and Player.Available and Player.IsMoving do
        StopVnav()
        if os.clock() > deadline then
            Dalamud.Log("[Toolkit Helper] Timed out waiting for movement to stop before teleport")
            return false
        end
        yield("/wait 0.1")
    end
    return true
end

local function ChangeState(newState, label)
    if type(newState) == "function" then
        State = newState
        if label then
            Dalamud.Log("[Toolkit Helper] State Change: "..label)
        end
        return true
    end
    local warningLabel = label and (" "..label) or ""
    Dalamud.Log("[Toolkit Helper] Failed to change state"..warningLabel.."; reverting to idle")
    if CharacterState and type(CharacterState.idle) == "function" then
        State = CharacterState.idle
    else
        State = Idle
    end
    return false
end

function HasPlugin(name)
    for plugin in luanet.each(Svc.PluginInterface.InstalledPlugins) do
        if plugin.InternalName == name and plugin.IsLoaded then
            return true
        end
    end
    return false
end

function HasStatusId(statusId)
    if Svc.ClientState == nil or Svc.ClientState.LocalPlayer == nil then
        return false
    end
    local statusList = Svc.ClientState.LocalPlayer.StatusList
    if statusList == nil then
        return false
    end
    for i=0, statusList.Length-1 do
        local status = statusList[i]
        if status ~= nil and status.StatusId == statusId then
            return true
        end
    end
    return false
end

function GetAetherytesInTerritory(territoryId)
    local aetherytesInZone = {}
    if Svc.AetheryteList == nil then
        return aetherytesInZone
    end
    for _, aetheryte in ipairs(Svc.AetheryteList) do
        if aetheryte.TerritoryId == territoryId then
            table.insert(aetherytesInZone, aetheryte)
        end
    end
    return aetherytesInZone
end

function GetAetheryteName(aetheryte)
    if aetheryte == nil or aetheryte.AetheryteData == nil then
        return ""
    end
    local placeName = aetheryte.AetheryteData.Value.PlaceName
    if placeName ~= nil and placeName.Value ~= nil then
        local name = placeName.Value.Name:GetText()
        if name ~= nil then
            return name
        end
    end
    return ""
end

local function GetAetherytePlaceNameByRowId(rowId)
    local numericId = tonumber(rowId)
    if not numericId then return nil end
    if not Excel or not Excel.GetSheet then return nil end
    local sheet = Excel.GetSheet("Aetheryte")
    if not sheet then return nil end
    local row = sheet:GetRow(numericId)
    if not row or not row.PlaceName or not row.PlaceName.Value then return nil end
    local name = row.PlaceName.Value.Name
    if name == nil then return nil end
    local text = name.GetText and name:GetText() or tostring(name)
    if text == nil or text == "" then return nil end
    return text
end

local function ExtractAetheryteRowId(aetheryte)
    if not aetheryte then return nil end

    local function normalize(value)
        if value == nil then return nil end
        local valueType = type(value)
        if valueType == "number" then
            return value
        end
        if valueType == "string" then
            local numeric = tonumber(value)
            if numeric ~= nil then
                return numeric
            end
        end
        if valueType == "userdata" then
            local ok, numeric = pcall(tonumber, value)
            if ok and numeric ~= nil then
                return numeric
            end
        end
        if valueType == "table" then
            local candidates = {"Id", "id", "Value", "value", "RowId", "rowId"}
            for _, key in ipairs(candidates) do
                if value[key] ~= nil then
                    local resolved = normalize(value[key])
                    if resolved ~= nil then
                        return resolved
                    end
                end
            end
        end
        return nil
    end

    local id = normalize(aetheryte.AetheryteId)
        or normalize(aetheryte.AetheryteID)
        or normalize(aetheryte.RowId)

    if id == nil then
        local data = aetheryte.AetheryteData
        if data then
            id = normalize(data.RowId)
                or (data.Value and (
                    normalize(data.Value.RowId)
                    or normalize(data.Value.Id)
                ))
        end
    end

    return id
end

function GetPreferredReturnAetheryteName(territoryId)
    if territoryId == nil or territoryId == 0 or territoryId == SUMMONING_BELL.territoryId then
        return nil
    end
    local candidates = GetAetherytesInTerritory(territoryId)
    if #candidates > 0 then
        local candidate = candidates[1]
        local name = GetAetheryteName(candidate)
        if name ~= nil and name ~= "" then
            local rowId = ExtractAetheryteRowId(candidate)
            return {
                name = name,
                aetheryteId = rowId
            }
        end
    end
    return nil
end

local function ClearReturnTarget()
    Runtime.returnAetheryteName = nil
    Runtime.returnTerritoryId = nil
    Runtime.returnAetheryteId = nil
end

local function SaveReturnLocationForCurrentTerritory()
    if Runtime.returnAetheryteName ~= nil then
        return
    end
    local territory = Svc.ClientState.TerritoryType
    if territory == nil or territory == 0 then
        return
    end
    local preferred = GetPreferredReturnAetheryteName(territory)
    if preferred == nil then
        Dalamud.Log("[Toolkit Helper] No known aetheryte for territory "..tostring(territory).."; return teleport unavailable")
        return
    else
        Runtime.returnTerritoryId = territory
        Runtime.returnAetheryteName = preferred.name
        Runtime.returnAetheryteId = preferred.aetheryteId
        Dalamud.Log(string.format("[Toolkit Helper] Saved return target %s (id=%s) for territory %s", preferred.name, tostring(preferred.aetheryteId), tostring(territory)))
    end
end

local function AttemptReturnToSavedLocation(context)
    if Runtime.returnAetheryteName == nil then
        return false
    end
    if Runtime.returnTerritoryId ~= nil and Runtime.returnTerritoryId == Svc.ClientState.TerritoryType then
        ClearReturnTarget()
        return true
    end
    local destination = {
        name = Runtime.returnAetheryteName,
        aetheryteId = Runtime.returnAetheryteId
    }
    Dalamud.Log("[Toolkit Helper] Attempting to return to "..destination.name..(context and (" ("..context..")") or "").." id="..tostring(destination.aetheryteId))
    local returned = false
    if TeleportTo(destination) then
        EchoAll("Returning to "..destination.name)
        returned = true
    else
        Dalamud.Log("[Toolkit Helper] Teleport back to "..destination.name.." failed")
    end
    if returned then
        ClearReturnTarget()
    end
    return returned
end

local function EnsureSummoningBellAetheryte()
    if SUMMONING_BELL.aetheryteName ~= nil and SUMMONING_BELL.aetheryteId ~= nil then
        return true
    end

    local resolvedName = GetAetherytePlaceNameByRowId(SUMMONING_BELL.aetheryteRowId)
        or SUMMONING_BELL.aetheryteName
        or "Limsa Lominsa Lower Decks"
    SUMMONING_BELL.aetheryteName = resolvedName
    SUMMONING_BELL.aetheryteId = SUMMONING_BELL.aetheryteRowId
    Dalamud.Log("[Toolkit Helper] Resolved Limsa aetheryte to "..resolvedName.." (id="..tostring(SUMMONING_BELL.aetheryteId)..")")
    return true
end

local function EnsureSummoningBellNameLocalized()
    if SUMMONING_BELL.localizedNameResolved then
        return SUMMONING_BELL.name
    end
    local localized = GetEObjNameByRowId(SUMMONING_BELL.rowId)
    if localized ~= nil and localized ~= "" then
        SUMMONING_BELL.name = localized
    end
    SUMMONING_BELL.localizedNameResolved = true
    return SUMMONING_BELL.name
end

local function StopToolkitRun(reason)
    local suffix = ""
    if reason ~= nil and reason ~= "" then
        suffix = " ("..reason..")"
    end
    Dalamud.Log("[Toolkit Helper] Issuing /vfate stop"..suffix)
    yield("/vfate stop")
    -- Toolkit resumes explicitly via ResumeToolkitRun when appropriate.
end

local function EnsureRetainerToolkitStopped(reason)
    if not Runtime.retainerToolkitStopped then
        StopToolkitRun(reason or "retainer pause")
        Runtime.retainerToolkitStopped = true
    end
end

local function ResumeToolkitAfterRetainers(reason)
    if Runtime.retainerToolkitStopped then
        Runtime.retainerToolkitStopped = false
        ResumeToolkitRun(reason or "retainer resume")
    end
end


function EorzeaTimeToUnixTime(eorzeaTime)
    return eorzeaTime/(144/7)
end

function GetNodeText(addonName, nodePath, ...)
    local addon = Addons.GetAddon(addonName)
    repeat
        yield("/wait 0.1")
    until addon.Ready
    return addon:GetNode(nodePath, ...).Text
end

function AcceptTeleportOfferLocation(destinationAetheryte)
    local notification = Addons.GetAddon("_NotificationTelepo")
    if notification ~= nil and notification.Ready then
        local location = GetNodeText("_NotificationTelepo", 3, 4)
        yield("/callback _Notification true 0 16 "..location)
        yield("/wait 1")
    end

    local yesno = Addons.GetAddon("SelectYesno")
    if yesno ~= nil and yesno.Ready then
        local teleportOfferMessage = GetNodeText("SelectYesno", 1, 2)
        if type(teleportOfferMessage) == "string" then
            local teleportOfferLocation = teleportOfferMessage:match("Accept Teleport to (.+)%?")
            if teleportOfferLocation ~= nil then
                if string.lower(teleportOfferLocation) == string.lower(destinationAetheryte) then
                    yield("/callback SelectYesno true 0")
                    return
                else
                    Dalamud.Log("[Toolkit Helper] Offer for "..teleportOfferLocation.." and destination "..destinationAetheryte.." differ. Declining teleport.")
                end
            end
            yield("/callback SelectYesno true 2")
            return
        end
    end
end

local function ResolveDestinationName(dest)
    if type(dest) ~= "table" then
        return dest, false, nil
    end

    local isMini = dest.isMiniAetheryte == true or dest.isMini == true or dest.mini == true
    local name = dest.name or dest.aetheryteName or dest.destinationName or dest.miniAetheryteName
    local id = dest.aetheryteId or dest.rowId or dest.aetheryteRowId
    local miniId = dest.miniAetheryteId or dest.miniRowId or dest.miniAetheryteRowId

    local function tryRow(rowId)
        if name ~= nil and name ~= "" then return name end
        if rowId == nil then return nil end
        local resolved = GetAetherytePlaceNameByRowId(rowId)
        if resolved and resolved ~= "" then
            name = resolved
        end
    end

    tryRow(dest.aetheryteRowId)
    tryRow(dest.rowId)
    tryRow(dest.aetheryteId)
    if dest.miniAetheryteRowId then
        isMini = true
        tryRow(dest.miniAetheryteRowId)
        miniId = dest.miniAetheryteRowId
    end
    if dest.miniRowId then
        isMini = true
        tryRow(dest.miniRowId)
        miniId = dest.miniRowId
    end

    if isMini and miniId then
        id = miniId
    end

    return name, isMini, id
end

local function ExecuteLifestreamCommand(destName, destId, isMini)
    if not IPC or not IPC.Lifestream then
        return false
    end

    local function HasTeleportIndicators()
        if IPC and IPC.Lifestream and IPC.Lifestream.IsBusy then
            local ok, busy = pcall(IPC.Lifestream.IsBusy)
            if ok and busy == true then
                return true
            end
        end
        if Svc.Condition[CharacterCondition.casting] then
            return true
        end
        if Svc.Condition[CharacterCondition.betweenAreas] then
            return true
        end
        return false
    end

    local function WaitForLifestreamBusyState(desiredBusy, timeout)
        local deadline = os.clock() + (timeout or 3)
        repeat
            local indicators = HasTeleportIndicators()
            if desiredBusy and indicators then
                return true
            end
            if not desiredBusy and not indicators then
                return true
            end
            yield("/wait 0.05")
        until os.clock() > deadline
        return false
    end

    local function WaitForLifestreamReady(timeout)
        return WaitForLifestreamBusyState(false, timeout or 5)
    end

    local function retryableCall(label, fn, maxAttempts)
        maxAttempts = maxAttempts or 1
        for attempt = 1, maxAttempts do
            local ready = WaitForLifestreamReady(5)
            if not ready then
                Dalamud.Log("[Toolkit Helper] Lifestream is still busy before "..label.."; delaying attempt")
                yield("/wait 0.5")
            end
            local sinceLast = os.clock() - (Runtime.lastLifestreamCommand or 0)
            if sinceLast < 2 then
                yield(string.format("/wait %.3f", 2 - sinceLast))
            end
            Runtime.lastLifestreamCommand = os.clock()
            local ok, result = pcall(fn)
            if not ok then
                Dalamud.Log(string.format("[Toolkit Helper] %s error: %s", label, tostring(result)))
            elseif result == true then
                yield("/wait 0.3")
                if WaitForLifestreamBusyState(true, 3) then
                    Dalamud.Log(string.format("[Toolkit Helper] %s succeeded%s", label, attempt > 1 and string.format(" on attempt %d", attempt) or ""))
                    return true
                else
                    Dalamud.Log(string.format("[Toolkit Helper] %s reported success but never became busy", label))
                end
            else
                Dalamud.Log(string.format("[Toolkit Helper] %s attempt %d returned false", label, attempt))
            end
            if attempt < maxAttempts then
                yield("/wait 0.3")
            end
        end
        return false
    end

    local function tryTeleportById(maxAttempts)
        if not destId or not IPC.Lifestream.Teleport then
            return false
        end
        return retryableCall(
            "IPC.Lifestream.Teleport (id="..tostring(destId)..")",
            function()
                return IPC.Lifestream.Teleport(destId, isMini and 1 or 0)
            end,
            maxAttempts
        )
    end

    local function tryMiniAethernetTeleport(maxAttempts)
        if not isMini or not destId or not IPC.Lifestream.AethernetTeleportById then
            return false
        end
        return retryableCall(
            "IPC.Lifestream.AethernetTeleportById (id="..tostring(destId)..")",
            function()
                return IPC.Lifestream.AethernetTeleportById(destId)
            end,
            maxAttempts
        )
    end

    local function tryTeleportByName()
        if not destName or not IPC.Lifestream.ExecuteCommand then
            return false
        end
        return retryableCall(
            "IPC.Lifestream.ExecuteCommand ("..tostring(destName)..")",
            function()
                return IPC.Lifestream.ExecuteCommand(destName)
            end,
            1
        )
    end

    local retryAttempts = 2

    if isMini and tryMiniAethernetTeleport(retryAttempts) then
        return true
    end

    if tryTeleportById(retryAttempts) then
        return true
    end

    if tryTeleportByName() then
        return true
    end

    Dalamud.Log("[Toolkit Helper] Lifestream could not teleport to "..tostring(destName).." (id="..tostring(destId)..")")
    return false
end

function TeleportTo(destination)
    local destName
    local isMini = false
    local destId = nil
    if type(destination) == "table" then
        destName, isMini, destId = ResolveDestinationName(destination)
    else
        destName = destination
    end

    if destName == nil or destName == "" then
        Dalamud.Log("[Toolkit Helper] TeleportTo called without a valid destination")
        return false
    end

    WaitForPlayerStationary(5)
    AcceptTeleportOfferLocation(destName)
    local start = os.clock()

    while Instances ~= nil and Instances.Framework ~= nil and EorzeaTimeToUnixTime(Instances.Framework.EorzeaTime) - Runtime.lastTeleport < 5 do
        Dalamud.Log("[Toolkit Helper] Too soon since last teleport. Waiting...")
        yield("/wait 5.001")
        if os.clock() - start > 30 then
            EchoAll("Teleport failed: timeout while waiting to cast")
            return false
        end
    end

    if not ExecuteLifestreamCommand(destName, destId, isMini) then
        Dalamud.Log("[Toolkit Helper] Falling back to /li command for destination "..destName)
        local fallback = isMini and ("/li "..destName) or ("/li tp "..destName)
        yield(fallback)
    end
    yield("/wait 1")

    while Svc.Condition[CharacterCondition.casting] do
        yield("/wait 1")
        if os.clock() - start > 60 then
            EchoAll("Teleport failed: timeout during cast")
            return false
        end
    end

    yield("/wait 1")
    while Svc.Condition[CharacterCondition.betweenAreas] do
        yield("/wait 1")
        if os.clock() - start > 120 then
            EchoAll("Teleport failed: timeout during zone transition")
            return false
        end
    end

    if Instances ~= nil and Instances.Framework ~= nil then
        Runtime.lastTeleport = EorzeaTimeToUnixTime(Instances.Framework.EorzeaTime)
    end
    return true
end

function CurrentCharacterRetainersReady()
    local ok, result = pcall(function()
        return IPC.AutoRetainer.AreAnyRetainersAvailableForCurrentChara()
    end)
    if not ok then
        Dalamud.Log("[Toolkit Helper] Failed to query AreAnyRetainersAvailableForCurrentChara(): "..tostring(result))
        return false
    end
    return result == true
end

local function ReadyToProcess()
    return CurrentCharacterRetainersReady() and Inventory.GetFreeInventorySlots() > 1
end

local function ShouldWaitForBonusBuff()
    return Settings.waitIfBonusBuff and (HasStatusId(1288) or HasStatusId(1289))
end

local function GetCurrentFateInfo()
    local okCurrent, currentFate = pcall(function()
        return Fates and Fates.CurrentFate
    end)
    if not okCurrent or currentFate == nil then
        return nil
    end

    local okInFate, inFate = pcall(function()
        return currentFate.InFate
    end)

    local okId, fateId = pcall(function()
        return currentFate.Id
    end)

    local state = nil
    if okId and fateId ~= nil and fateId ~= 0 then
        local okFateObj, fateObj = pcall(function()
            return Fates.GetFateById(fateId)
        end)
        if okFateObj and fateObj ~= nil then
            state = fateObj.State
        end
    end

    return {
        inFate = okInFate and inFate == true,
        state = state
    }
end

local function ShouldDelayProcessing()
    if ShouldWaitForBonusBuff() then
        return true, "bonus buff active", false, nil
    end
    if Svc.Condition ~= nil and Svc.Condition[CharacterCondition.inCombat] then
        return true, "character is in combat", false, nil
    end

    local info = GetCurrentFateInfo()
    if info ~= nil then
        local state = info.state
        if state == FateState.Ending then
            return true, "awaiting fate rewards", true, 5
        end

        local isActive = info.inFate
            or (state ~= nil and state ~= FateState.Ended and state ~= FateState.Failed and state ~= FateState.None)
        if isActive then
            return true, "currently in a FATE", false, nil
        end
    end

    return false
end

-- Gemstone helpers
local BICOLOR_GEM_ITEM_ID = 26807
local SelectedGemstoneEntry = nil

local function GetBicolorGemCount()
    local ok, count = pcall(function()
        return Inventory.GetItemCount(BICOLOR_GEM_ITEM_ID)
    end)
    if not ok or count == nil then
        return 0
    end
    return count
end

local function NeedsGemstones()
    if not Settings.maintainGemstones then
        return false
    end
    local target = Settings.gemstoneTarget or 0
    if target <= 0 then
        return false
    end
    return GetBicolorGemCount() < target
end

local function ComputeGemstoneRunCount(goal)
    local target = goal or Settings.gemstoneTarget or 0
    local current = GetBicolorGemCount()
    local deficit = math.max(0, target - current)
    if deficit <= 0 then
        return 0
    end
    local average = Settings.gemstonesPerRun or 14
    average = math.max(1, average)
    return math.max(1, math.ceil(deficit / average))
end

local function DetermineToolkitRunCount()
    if Settings.maintainGemstones and (Settings.gemstoneTarget or 0) > 0 then
        local runs = ComputeGemstoneRunCount(Settings.gemstoneTarget)
        if runs <= 0 then
            runs = 1
        end
        return runs
    end
    return 1000
end

local function ResumeToolkitRun(reason)
    local runs = DetermineToolkitRunCount()
    local suffix = ""
    if reason ~= nil and reason ~= "" then
        suffix = " ("..reason..")"
    end
    Dalamud.Log(string.format("[Toolkit Helper] Issuing /vfate run %d%s", runs, suffix))
    yield(string.format("/vfate run %d", runs))
end

local function IssueToolkitGemstoneRun(runCount, goal)
    local count = math.max(1, runCount)
    local gemstoneGoal = goal or Settings.gemstoneTarget or 0
    Dalamud.Log(string.format("[Toolkit Helper] Issuing /vfate run %d to reach %d gemstones", count, gemstoneGoal))
    yield(string.format("/vfate run %d", count))
    Runtime.pendingGemstoneGoal = gemstoneGoal
    Runtime.gemstoneRunIssuedAt = os.clock()
end

local function WaitForGemstoneGoal(goal)
    local gemstoneGoal = goal or Settings.gemstoneTarget or 0
    if gemstoneGoal <= 0 then
        return true
    end
    local start = os.clock()
    local timeout = Settings.maxGemstoneRunWait or 900
    repeat
        if Runtime.stopScript then
            return false
        end
        if GetBicolorGemCount() >= gemstoneGoal then
            return true
        end
        yield("/wait 5")
    until os.clock() - start > timeout
    return GetBicolorGemCount() >= gemstoneGoal
end

local function EnsureGemstoneSelection()
    if not Settings.exchangeGemstones then
        SelectedGemstoneEntry = nil
        return false
    end
    local token = Settings.bicolorItem or "None"
    if token == "None" then
        SelectedGemstoneEntry = nil
        return false
    end
    if SelectedGemstoneEntry ~= nil and SelectedGemstoneEntry.token == token then
        return true
    end
    local base = GemstoneExchangeMap[token]
    if not base then
        Dalamud.Log("[Toolkit Helper] Unknown gemstone option '"..token.."'. Disabling exchange feature.")
        Settings.exchangeGemstones = false
        SelectedGemstoneEntry = nil
        return false
    end
    local entry = {
        token = token,
        itemId = base.itemId,
        itemIndex = base.itemIndex,
        price = base.price,
        vendorId = base.vendorId,
        vendorName = base.vendorName,
        territoryId = base.territoryId,
        position = base.position,
        aetheryte = base.aetheryte,
        miniAetheryte = base.miniAetheryte
    }
    entry.localizedItemName = GetItemNameByRowId(entry.itemId) or token
    entry.vendorLocalizedName = GetNpcNameByRowId(entry.vendorId) or entry.vendorName
    if entry.aetheryte then
        local aethName = GetAetherytePlaceNameByRowId(entry.aetheryte.rowId) or entry.aetheryte.name
        entry.aetheryteTeleport = {
            aetheryteRowId = entry.aetheryte.rowId,
            name = aethName,
            aetheryteId = entry.aetheryte.rowId
        }
    end
    if entry.miniAetheryte then
        local miniName = GetAetherytePlaceNameByRowId(entry.miniAetheryte.rowId) or entry.miniAetheryte.name
        entry.miniAetheryteTeleport = {
            aetheryteRowId = entry.miniAetheryte.rowId,
            name = miniName,
            isMiniAetheryte = true,
            aetheryteId = entry.miniAetheryte.rowId
        }
    end
    if Settings.gemstoneTarget < entry.price then
        Settings.gemstoneTarget = entry.price
        Dalamud.Log(string.format("[Toolkit Helper] Adjusted gemstone target to %d for %s pricing", Settings.gemstoneTarget, entry.localizedItemName))
    end
    SelectedGemstoneEntry = entry
    return true
end

local function ShouldExchangeGemstones()
    if not Settings.exchangeGemstones then
        return false
    end
    if Runtime.pendingGemstoneGoal ~= nil then
        return false
    end
    local target = Settings.gemstoneTarget or 0
    if target <= 0 then
        return false
    end
    return GetBicolorGemCount() >= target
end

local function MoveNearPosition(targetPos, stopDistance)
    if targetPos == nil then
        return true
    end
    local distance = GetDistanceToPoint(targetPos)
    stopDistance = stopDistance or 4.5
    if distance > stopDistance then
        if not (IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning()) then
            IPC.vnavmesh.PathfindAndMoveTo(targetPos, false)
        end
        return false
    end
    return true
end

local function InteractWithGemstoneVendor(entry)
    if entry == nil then return false end
    local npcName = entry.vendorLocalizedName or entry.vendorName
    if npcName == nil or npcName == "" then
        return false
    end
    if Entity and Entity.GetEntityByName then
        local npc = Entity.GetEntityByName(npcName)
        if npc ~= nil then
            npc:SetAsTarget()
            yield("/wait 0.2")
            npc:Interact()
            return true
        end
    end
    yield('/target "'..npcName..'"')
    yield("/wait 0.2")
    yield("/interact")
    return true
end

local function EnsureGemstoneShopOpen(entry)
    local shop = WaitForAddonReady("ShopExchangeCurrency", 3)
    if shop ~= nil then
        return shop
    end
    InteractWithGemstoneVendor(entry)
    return WaitForAddonReady("ShopExchangeCurrency", 5)
end

local function PurchaseGemstoneItem(entry, shop)
    local gemstoneCount = GetBicolorGemCount()
    local quantity = math.floor(gemstoneCount / entry.price)
    if quantity <= 0 then
        Dalamud.Log(string.format("[Toolkit Helper] Not enough gemstones (%d) to buy %s", gemstoneCount, entry.localizedItemName))
        yield("/callback ShopExchangeCurrency true -1")
        WaitForAddonClosed("ShopExchangeCurrency", 2)
        return false, "insufficient"
    end
    Dalamud.Log(string.format("[Toolkit Helper] Purchasing %d x %s", quantity, entry.localizedItemName))
    yield(string.format("/callback ShopExchangeCurrency false 0 %d %d", entry.itemIndex, quantity))
    local yesno = WaitForAddonVisible("SelectYesno", 5)
    if yesno ~= nil then
        yield("/callback SelectYesno true 0")
        WaitForAddonClosed("SelectYesno", 3)
    end
    Runtime.lastGemstoneCheck = 0
    yield("/wait 0.3")
    yield("/callback ShopExchangeCurrency true -1")
    WaitForAddonClosed("ShopExchangeCurrency", 3)
    return true
end

local function ResetExchangeState()
    Runtime.exchangeInProgress = false
    Runtime.exchangeStarted = false
    Runtime.usedMiniTeleport = false
    Runtime.exchangeDelayActive = false
    Runtime.lastExchangeDelayLog = 0
end

local function FinishGemstoneExchange(reason)
    ResetExchangeState()
    Runtime.nextExchangeCheck = os.clock() + 30
    if reason then
        Dalamud.Log("[Toolkit Helper] "..reason)
    end
    AttemptReturnToSavedLocation("gemstone exchange")
    ResumeToolkitRun("after gemstone exchange")
    ChangeState(CharacterState.idle)
end

local function LogFeatureFlagsOnce()
    if Runtime.featureLogPrinted then return end
    local entries = {}
    if Settings.pauseRetainers then
        table.insert(entries, "Retainer processing enabled")
    end
    if Settings.maintainGemstones and (Settings.gemstoneTarget or 0) > 0 then
        table.insert(entries, string.format("Gemstone stockpile enabled (target=%d)", Settings.gemstoneTarget))
    end
    if Settings.exchangeGemstones and Settings.bicolorItem ~= "None" then
        table.insert(entries, string.format("Gemstone exchange enabled (%s)", Settings.bicolorItem))
    end
    if #entries == 0 then
        table.insert(entries, "No optional workflows enabled")
    end
    for _, msg in ipairs(entries) do
        Dalamud.Log("[Toolkit Helper] "..msg)
    end
    Runtime.featureLogPrinted = true
end

--#endregion Helpers

--#region State Functions

function Idle()
    RefreshSettings()
    if Runtime.stopScript then return end

    if not Player.Available or Svc.Condition[CharacterCondition.betweenAreas] then
        return
    end

    local now = os.clock()
    if Settings.pauseRetainers then
        if now >= Runtime.nextCheck then
            Runtime.nextCheck = now + Settings.checkInterval
            if ReadyToProcess() then
                local delay, reason, pauseToolkit, retryInterval = ShouldDelayProcessing()
                if delay then
                    if pauseToolkit then
                        EnsureRetainerToolkitStopped("retainer delay: "..tostring(reason))
                    end
                    if retryInterval ~= nil then
                        Runtime.nextCheck = os.clock() + retryInterval
                    end
                    Dalamud.Log("[Toolkit Helper] Ventures ready but delaying retainer processing because "..reason)
                    return
                end
                Dalamud.Log("[Toolkit Helper] Detected ventures ready and sufficient inventory space; entering ProcessRetainers state")
                ChangeState(CharacterState.processRetainers, "ProcessRetainers")
                return
            end
        end
    end

    if Settings.maintainGemstones and Runtime.pendingGemstoneGoal == nil then
        if os.clock() >= Runtime.lastGemstoneCheck then
            Runtime.lastGemstoneCheck = os.clock() + 30
            if NeedsGemstones() then
                local delay, reason = ShouldDelayProcessing()
                if delay then
                    Dalamud.Log("[Toolkit Helper] Need gemstones but delaying because "..reason)
                    return
                end
                Dalamud.Log("[Toolkit Helper] Gemstones below target; entering MaintainGemstones state")
                ChangeState(CharacterState.maintainGemstones, "MaintainGemstones")
                return
            end
        end
    end

    if Settings.exchangeGemstones then
        if Runtime.exchangeInProgress then
            ChangeState(CharacterState.exchangeGemstones)
            return
        elseif os.clock() >= (Runtime.nextExchangeCheck or 0) and ShouldExchangeGemstones() then
            if EnsureGemstoneSelection() then
                Runtime.exchangeInProgress = true
                Runtime.exchangeStarted = false
                Runtime.usedMiniTeleport = false
                Dalamud.Log("[Toolkit Helper] Gemstone threshold met; entering ExchangeGemstones state")
                ChangeState(CharacterState.exchangeGemstones, "ExchangeGemstones")
                return
            end
        end
    end
end

function ProcessRetainers()
    RefreshSettings()
    local summoningBellName = EnsureSummoningBellNameLocalized()
    if not Settings.pauseRetainers then
        ChangeState(CharacterState.idle)
        ResumeToolkitAfterRetainers("retainer feature disabled")
        return
    end
    local delay, reason, pauseToolkit, retryInterval = ShouldDelayProcessing()
    if delay then
        if pauseToolkit then
            EnsureRetainerToolkitStopped("retainer abort delay: "..tostring(reason))
        end
        if retryInterval ~= nil then
            Runtime.nextCheck = os.clock() + retryInterval
        end
        Dalamud.Log("[Toolkit Helper] Abort ProcessRetainers due to "..reason.."; returning to idle")
        ChangeState(CharacterState.idle)
        ResumeToolkitAfterRetainers("retainer delay abort")
        return
    end

    EnsureRetainerToolkitStopped("retainer processing start")

    if not ReadyToProcess() then
        local retainerList = Addons.GetAddon("RetainerList")
        if retainerList ~= nil and retainerList.Ready then
            if Settings.closeRetainerList ~= false then
                Dalamud.Log("[Toolkit Helper] Closing RetainerList addon")
                yield("/callback RetainerList true -1")
                return
            else
                Dalamud.Log("[Toolkit Helper] Leaving RetainerList open per configuration")
            end
        end
        if Runtime.returnAetheryteName ~= nil then
            if Svc.ClientState.TerritoryType == SUMMONING_BELL.territoryId and not Svc.Condition[CharacterCondition.occupiedSummoningBell] then
                if AttemptReturnToSavedLocation("retainer workflow") then
                    ResumeToolkitAfterRetainers("resuming after retainer teleport")
                    return
                end
            elseif Svc.ClientState.TerritoryType ~= SUMMONING_BELL.territoryId then
                ResumeToolkitAfterRetainers("retainer return aetheryte cleared")
                ClearReturnTarget()
            end
        end
        if not Svc.Condition[CharacterCondition.occupiedSummoningBell] then
            ChangeState(CharacterState.idle, "Idle")
            ResumeToolkitAfterRetainers("retainer processing complete")
        end
        return
    end

    if IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() then
        return
    end

    if Svc.ClientState.TerritoryType ~= SUMMONING_BELL.territoryId then
        SaveReturnLocationForCurrentTerritory()
        EnsureRetainerToolkitStopped("retainer teleport to Limsa")
        StopVnav()
        EnsureSummoningBellAetheryte()
        local limsaAetheryteName = SUMMONING_BELL.aetheryteName or "Limsa Lominsa Lower Decks"
        if TeleportTo(limsaAetheryteName) then
            EchoAll("Teleporting to "..limsaAetheryteName)
            Dalamud.Log("[Toolkit Helper] Teleporting to "..limsaAetheryteName.." for retainer processing")
        end
        return
    end

    if GetDistanceToPoint(SUMMONING_BELL.position) > 4.5 then
        IPC.vnavmesh.PathfindAndMoveTo(SUMMONING_BELL.position, false)
        return
    end

    if Svc.Targets.Target == nil or GetTargetName() ~= summoningBellName then
        yield("/target "..summoningBellName)
        return
    end

    if not Svc.Condition[CharacterCondition.occupiedSummoningBell] then
        yield("/interact")
        local retainerList = Addons.GetAddon("RetainerList")
        if retainerList ~= nil and retainerList.Ready then
            yield("/ays e")
            EchoAll("Processing retainers")
            Dalamud.Log("[Toolkit Helper] Handed control to AutoRetainer via /ays e")
            yield("/wait 1")
        end
    end
end

function MaintainGemstones()
    RefreshSettings()
    if not Settings.maintainGemstones then
        Runtime.pendingGemstoneGoal = nil
        ChangeState(CharacterState.idle)
        return
    end

    local target = Settings.gemstoneTarget or 0
    if target <= 0 or not NeedsGemstones() then
        Runtime.pendingGemstoneGoal = nil
        ChangeState(CharacterState.idle)
        return
    end

    local delay, reason = ShouldDelayProcessing()
    if delay then
        Dalamud.Log("[Toolkit Helper] MaintainGemstones aborted due to "..reason)
        Runtime.pendingGemstoneGoal = nil
        ChangeState(CharacterState.idle)
        return
    end

    local runs = ComputeGemstoneRunCount(target)
    if runs <= 0 then
        Runtime.pendingGemstoneGoal = nil
        ChangeState(CharacterState.idle)
        return
    end

    IssueToolkitGemstoneRun(runs, target)
    local reached = WaitForGemstoneGoal(target)
    if reached then
        Dalamud.Log(string.format("[Toolkit Helper] Gemstone goal of %d reached (current=%d)", target, GetBicolorGemCount()))
        StopToolkitRun("gemstone goal reached")
    else
        Dalamud.Log(string.format("[Toolkit Helper] Timed out waiting for gemstone goal (%d). Current=%d", target, GetBicolorGemCount()))
        StopToolkitRun("gemstone goal timeout")
    end
    Runtime.pendingGemstoneGoal = nil
    ChangeState(CharacterState.idle, "Idle")
end

function ExchangeGemstones()
    RefreshSettings()
    if not Settings.exchangeGemstones then
        ResetExchangeState()
        if Runtime.exchangeStarted then
            ResumeToolkitRun("gemstone exchange disabled")
        end
        ChangeState(CharacterState.idle)
        return
    end

    if not EnsureGemstoneSelection() then
        ResetExchangeState()
        Runtime.nextExchangeCheck = os.clock() + 60
        ResumeToolkitRun("gemstone exchange unavailable")
        ChangeState(CharacterState.idle)
        return
    end

    if not ShouldExchangeGemstones() then
        ResetExchangeState()
        if Runtime.exchangeStarted then
            ResumeToolkitRun("gemstone threshold cleared")
        end
        ChangeState(CharacterState.idle)
        return
    end

    local delay, reason, pauseToolkit = ShouldDelayProcessing()
    if delay then
        if pauseToolkit then
            StopToolkitRun("gemstone exchange delay: "..tostring(reason))
            Runtime.exchangeDelayActive = false
        end
        if not pauseToolkit and not Runtime.exchangeDelayActive then
            ResumeToolkitRun("exchange delay: "..tostring(reason))
            Runtime.exchangeDelayActive = true
        end
        local now = os.clock()
        if now >= (Runtime.lastExchangeDelayLog or 0) then
            Dalamud.Log("[Toolkit Helper] Gemstone exchange waiting because "..tostring(reason))
            Runtime.lastExchangeDelayLog = now + 5
        end
        return
    end

    if Runtime.exchangeDelayActive then
        StopToolkitRun("gemstone exchange delay cleared")
        Runtime.exchangeDelayActive = false
    end

    if not Runtime.exchangeStarted then
        SaveReturnLocationForCurrentTerritory()
        StopToolkitRun("gemstone exchange start")
        Runtime.exchangeStarted = true
    end

    local entry = SelectedGemstoneEntry
    if entry == nil then
        ResetExchangeState()
        ResumeToolkitRun("gemstone entry missing")
        ChangeState(CharacterState.idle)
        return
    end

    if Svc.ClientState.TerritoryType ~= entry.territoryId then
        if entry.aetheryteTeleport ~= nil then
            TeleportTo(entry.aetheryteTeleport)
        end
        return
    end

    if entry.miniAetheryteTeleport and not Runtime.usedMiniTeleport then
        TeleportTo(entry.miniAetheryteTeleport)
        Runtime.usedMiniTeleport = true
        return
    end

    if not MoveNearPosition(entry.position, 4.5) then
        return
    end

    local shop = EnsureGemstoneShopOpen(entry)
    if not shop then
        return
    end

    local success, reason = PurchaseGemstoneItem(entry, shop)
    if not success then
        if reason == "insufficient" then
            Runtime.nextExchangeCheck = os.clock() + 60
            ResetExchangeState()
            ResumeToolkitRun("insufficient gemstones for exchange")
            ChangeState(CharacterState.idle)
        end
        return
    end

    FinishGemstoneExchange(string.format("Completed gemstone exchange for %s", entry.localizedItemName))
end

--#endregion State Functions

--#region Main

if not HasPlugin("AutoRetainer") then
    yield("/echo [Toolkit Helper] AutoRetainer is required for this script. Stopping.")
    return
end

if not IPC.vnavmesh.IsReady() then
    yield("/echo [Toolkit Helper] Waiting for vnavmesh to build...")
    repeat
        yield("/wait 1")
    until IPC.vnavmesh.IsReady()
end

CharacterState = {
    idle = Idle,
    processRetainers = ProcessRetainers,
    maintainGemstones = MaintainGemstones,
    exchangeGemstones = ExchangeGemstones
}

function OnStop()
    StopVnav()
    StopToolkitRun("script stop")
    if IPC and IPC.Lifestream and IPC.Lifestream.Abort then
        pcall(function()
            IPC.Lifestream.Abort()
        end)
    end
end

State = CharacterState.idle

LogFeatureFlagsOnce()

ResumeToolkitRun("initial start")

Dalamud.Log("[Toolkit Helper] Starting toolkit helper loop")

while not Runtime.stopScript do
    if not Svc.Condition[CharacterCondition.betweenAreas]
        and not Svc.Condition[CharacterCondition.occupiedMateriaExtractionAndRepair]
    then
        State()
    end
    yield("/wait 0.25")
end

yield("/echo [Toolkit Helper] Loop ended")

--#endregion Main
