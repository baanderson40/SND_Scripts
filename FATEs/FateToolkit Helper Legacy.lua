--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.5.1
description: |
  Toolkit Helper adds support utilities around Fate Tool Kit automation:
  - AutoRetainer monitoring and Limsa bell handling
  - Gemstone stockpile checks and exchange automation
  - Optional self-repair / NPC repair flow with Dark Matter purchasing
  - Gemstone purchase cycle limits with optional follow-up scripts or AutoRetainer multi-mode
plugin_dependencies:
- AutoRetainer
- vnavmesh
- Automaton
configs:
  Gearset Slot:
    description: Optional gearset slot number to equip before farming (0 disables).
    default: 0
    min: 0
    max: 100
  FATE starting area:
    description: Optional Lifestream destination text to run once after startup gearset handling.
    default: ""
  Pause for retainers?:
    description: Pause FATE Toolkit to process retainers with AutoRetainer.
    default: true
  Close Retainer List when done?:
    description: Close the retainer list when retainers are complete.
    default: true
  Maintain gemstone stockpile?:
    description: Restart FATE Toolkit after spending Bicolor gemstones.
    default: true
  Gemstone stockpile target:
    description: Target amount of Bicolor gemstones before performing purchase.
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
  Gemstone purchase cycle limit:
    description: Stop the script after this many purchases (0 disables the limit).
    default: 0
    min: 0
    max: 999
  Use Return for Solution Nine?:
    description: |
      Use the Return instead of teleporting when traveling to Solution Nine.
      Solution Nine must be set as your home point.
    default: false
  Chocobo stance:
    description: Desired chocobo stance.
    default: "Free Stance"
    is_choice: true
    choices: ["Disabled", "Free Stance", "Defender Stance", "Attacker Stance", "Healer Stance"]
  Self repair?:
    description: "Enabled: Self repair | Disabled: NPC repair"
    default: true
  Auto-buy dark matter?:
    description:
    default: true
  Repair durability threshold (%):
    description:
    default: 10
    min: 1
    max: 99
  Enable stuck monitoring?:
    description: Restart VFATE if the character is stuck for 15 seconds.
    default: false
  Follow-up script:
    description: |
      SND script to run after this helper stops.
      Must be a valid script name that already exists.
    default: ""
  Enable AutoRetainer multi-mode after limit?:
    description: Turn on AutoRetainer multi-mode when the purchase limit stops this script.
    default: false
  Echo logs:
    description:
    default: "None"
    is_choice: true
    choices: ["All", "None"]
  Check interval (seconds):
    description: How often to poll for completed retainers.
    default: 60
    min: 5
    max: 300
[[End Metadata]]
--]=====]

import("System.Numerics")

--#region Utilities

function Vec3(x, y, z)
    return Vector3(x, y, z)
end

function TrimString(value)
    if type(value) ~= "string" then
        return value
    end
    local trimmed = value:match("^%s*(.-)%s*$")
    if trimmed == nil then
        return value
    end
    return trimmed
end

--#endregion Utilities

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
    rowId = 2000401,
    name = "Summoning Bell",
    position = Vector3(-122.72, 18.00, 20.39),
    territoryId = 129,
    aetheryteRowId = 8,
    aetheryteName = nil,
    aetheryteId = nil
}

local BICOLOR_GEM_ITEM_ID = 26807
local DARK_MATTER_ITEM_ID = 33916
local REPAIR_GENERAL_ACTION_ID = 6
local RETURN_GENERAL_ACTION_ID = 8
local BUDDY_ACTION_TYPE_ID = 6
local GADFRID_VENDOR_ID = 1037055
local GADFRID_POSITION = Vec3(78.355, 5.150, -36.790)
local CHOCOBO_STANCE_CHECK_INTERVAL_SECONDS = 15
local UNSYNRAEL_ROW_ID = 1001207
local ALISTAIR_ROW_ID = 1001206
local HAWKERS_ALLEY_POSITION = Vector3(-213.95, 15.99, 49.35)
local UNSYNRAEL_POSITION = Vector3(-257.71, 16.19, 50.11)
local ALISTAIR_POSITION = Vector3(-246.87, 16.19, 49.83)
local HAWKERS_MINI_AETHERYTE_ID = 49
local SOLUTION_NINE_AETHERYTE_ROW_ID = 217

local ChocoboStanceActionMap = {
    ["Free Stance"] = 4,
    ["Defender Stance"] = 5,
    ["Attacker Stance"] = 6,
    ["Healer Stance"] = 7
}

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

function GetItemNameByRowId(rowId)
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

function GetNpcNameByRowId(rowId)
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

function GetLocalizedNpcName(rowId, fallback)
    local resolved = GetNpcNameByRowId(rowId)
    if resolved ~= nil and resolved ~= "" then
        return resolved
    end
    return fallback
end

function GetEObjNameByRowId(rowId)
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
    selfRepair = true,
    autoBuyDarkMatter = true,
    repairThreshold = 10,
    bicolorItem = "None",
    exchangeGemstones = false,
    purchaseCycleLimit = 0,
    purchaseLimitFollowUp = "",
    enableMultiModeOnLimit = false,
    startAreaCommand = "",
    useReturnToSolutionNine = false,
    enableStuckMonitor = false,
    chocoboStance = "Free Stance",
    chocoboStanceActionId = 4
}

local equipGearsetSlot = -1
local gearsetEquipped = false

function RefreshSettings()
    local previousExchange = Settings.exchangeGemstones
    local previousLimit = Settings.purchaseCycleLimit or 0
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

    local selfRepair = Config.Get("Self repair?")
    if selfRepair ~= nil then
        Settings.selfRepair = selfRepair
    end

    local autoBuyDarkMatter = Config.Get("Auto-buy dark matter?")
    if autoBuyDarkMatter ~= nil then
        Settings.autoBuyDarkMatter = autoBuyDarkMatter
    end

    local repairThreshold = Config.Get("Repair durability threshold (%)")
    if type(repairThreshold) == "number" then
        Settings.repairThreshold = math.max(1, math.min(100, math.floor(repairThreshold)))
    end

    local gemstoneTarget = Config.Get("Gemstone stockpile target")
    if type(gemstoneTarget) == "number" then
        Settings.gemstoneTarget = math.max(0, gemstoneTarget)
    end

    local bicolorItem = Config.Get("Exchange bicolor gemstones for")
    if type(bicolorItem) == "string" then
        Settings.bicolorItem = bicolorItem
    end

    local purchaseLimit = Config.Get("Gemstone purchase cycle limit")
    if type(purchaseLimit) == "number" then
        purchaseLimit = math.max(0, math.floor(purchaseLimit))
    else
        purchaseLimit = 0
    end
    Settings.purchaseCycleLimit = purchaseLimit

    local followUpScript = Config.Get("Follow-up script")
    if type(followUpScript) == "string" then
        followUpScript = TrimString(followUpScript)
        if followUpScript ~= nil and followUpScript ~= "" then
            if string.lower(followUpScript) == "none" then
                followUpScript = ""
            end
        end
    else
        followUpScript = ""
    end
    Settings.purchaseLimitFollowUp = followUpScript or ""

    local startAreaCommand = Config.Get("FATE starting area")
    if type(startAreaCommand) == "string" then
        startAreaCommand = TrimString(startAreaCommand)
        if startAreaCommand ~= nil and startAreaCommand ~= "" then
            if string.lower(startAreaCommand) == "none" then
                startAreaCommand = ""
            end
        end
    else
        startAreaCommand = ""
    end
    Settings.startAreaCommand = startAreaCommand or ""

    local enableMultiMode = Config.Get("Enable AutoRetainer multi-mode after limit?")
    if enableMultiMode ~= nil then
        Settings.enableMultiModeOnLimit = enableMultiMode == true
    else
        Settings.enableMultiModeOnLimit = false
    end

    local useReturn = Config.Get("Use Return for Solution Nine?")
    if useReturn ~= nil then
        Settings.useReturnToSolutionNine = useReturn == true
    else
        Settings.useReturnToSolutionNine = false
    end

    local chocoboStance = Config.Get("Chocobo stance")
    if type(chocoboStance) == "string" and chocoboStance ~= "" then
        Settings.chocoboStance = chocoboStance
    end
    if type(Settings.chocoboStance) ~= "string" or Settings.chocoboStance == "" then
        Settings.chocoboStance = "Free Stance"
    end
    Settings.chocoboStanceActionId = ChocoboStanceActionMap[Settings.chocoboStance]

    local gearsetConfig = Config.Get("Gearset Slot")
    local numericGearset = nil
    if type(gearsetConfig) == "number" or type(gearsetConfig) == "string" then
        numericGearset = tonumber(gearsetConfig)
    end
    local newGearsetSlot = -1
    if numericGearset ~= nil then
        numericGearset = math.floor(numericGearset)
        if numericGearset >= 1 then
            numericGearset = math.min(100, numericGearset)
            newGearsetSlot = numericGearset - 1
        end
    end
    if equipGearsetSlot ~= newGearsetSlot then
        equipGearsetSlot = newGearsetSlot
        gearsetEquipped = false
    end

    Settings.exchangeGemstones = Settings.maintainGemstones
        and type(Settings.bicolorItem) == "string"
        and Settings.bicolorItem ~= "None"

    local limitChanged = previousLimit ~= Settings.purchaseCycleLimit
    local exchangeChanged = previousExchange ~= Settings.exchangeGemstones
    if Runtime ~= nil and ResetPurchaseCycleTracking ~= nil then
        if limitChanged then
            ResetPurchaseCycleTracking()
        elseif exchangeChanged or not Settings.exchangeGemstones then
            ResetPurchaseCycleTracking()
        end
    end

    if not gearsetEquipped then
        EquipConfiguredGearset()
    end

    AttemptStartupAreaTravel()

    local stuckMonitor = Config.Get("Enable stuck monitoring?")
    Settings.enableStuckMonitor = stuckMonitor == true
    if Runtime ~= nil and Runtime.stuckMonitor ~= nil then
        if Settings.enableStuckMonitor then
            Runtime.stuckMonitor.enabled = true
        else
            ResetStuckMonitor("feature disabled")
            Runtime.stuckMonitor.enabled = false
        end
    end
end

Runtime = {
    stopScript = false,
    nextCheck = 0,
    lastTeleport = -math.huge,
    teleportLockActive = false,
    teleportLockDestination = nil,
    teleportLockStarted = 0,
    teleportLockExpires = 0,
    nextTeleportLockLog = 0,
    returnAetheryteName = nil,
    returnTerritoryId = nil,
    returnAetheryteId = nil,
    returnDestinationTerritoryId = nil,
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
    lastLifestreamCommand = 0,
    initialToolkitStarted = false,
    pendingRepair = false,
    repairToolkitStopped = false,
    nextRepairCheck = 0,
    repairActionPending = false,
    repairActionStartedAt = 0,
    repairConditionSeen = false,
    repairRetryCount = 0,
    repairUseNpcFallback = false,
    startAreaHandled = false,
    nextChocoboStanceCheck = 0,
    purchaseCycleCount = 0,
    purchaseLimitReached = false,
    purchaseLimitHandled = false,
    purchaseLimitFollowUpIssued = false,
    deferredFollowUpScript = nil,
    deferredEnableMultiMode = false,
    textAdvanceEnabledByScript = false,
    bossmodRecordedState = nil,
    bossmodStateChanged = false,
    stuckMonitor = {
        enabled = false,
        lastPosition = nil,
        lastMovementTime = 0,
        lastRestartTime = 0,
        lastRecoveryType = nil,
        consecutiveTriggers = 0,
        triggered = false,
        lastLogMessage = nil,
        lastLogTime = 0
    }
}

--#endregion Config & Runtime

--#region Helpers

--## Logging & Toolkit Control

function EchoAll(message)
    if Settings.echoLevel == "all" then
        yield("/echo [Toolkit Helper] "..message)
    end
end

function SetAutoRetainerMultiMode(enabled)
    if not IPC or not IPC.AutoRetainer or not IPC.AutoRetainer.SetMultiModeEnabled then
        Dalamud.Log("[Toolkit Helper] Unable to set AutoRetainer multi-mode; IPC unavailable")
        return false
    end
    local ok, err = pcall(function()
        return IPC.AutoRetainer.SetMultiModeEnabled(enabled)
    end)
    if not ok then
        Dalamud.Log("[Toolkit Helper] Failed to set AutoRetainer multi-mode: "..tostring(err))
        return false
    end
    return true
end

--## Gearset Helpers

function EquipConfiguredGearset()
    if gearsetEquipped then
        return true
    end
    local slot = tonumber(equipGearsetSlot)
    if slot == nil or slot < 0 then
        gearsetEquipped = true
        return true
    end
    local slotDisplay = slot + 1
    if not Player or not Player.GetGearset then
        Dalamud.Log("[Toolkit Helper] Gearset equip requested but Player module unavailable")
        return false
    end
    local gearset = Player.GetGearset(slot)
    if not gearset or gearset.IsValid ~= true then
        Dalamud.Log(string.format("[Toolkit Helper] Configured gearset slot %d invalid or unavailable", slotDisplay))
        return false
    end
    local gearsetName = gearset.Name
    if gearsetName and gearsetName.GetText then
        local ok, resolved = pcall(function()
            return gearsetName:GetText()
        end)
        if ok and type(resolved) == "string" and resolved ~= "" then
            gearsetName = resolved
        end
    end
    gearsetName = tostring(gearsetName or "Gearset "..slotDisplay)
    Dalamud.Log(string.format("[Toolkit Helper] Equipping gearset slot %d (%s)", slotDisplay, gearsetName))
    local ok, err = pcall(function()
        return gearset:Equip()
    end)
    if not ok then
        Dalamud.Log(string.format("[Toolkit Helper] Failed to equip gearset slot %d: %s", slotDisplay, tostring(err)))
        return false
    end
    yield("/wait 1")
    gearsetEquipped = true
    return true
end

function AttemptStartupAreaTravel()
    if Runtime == nil or Runtime.startAreaHandled then
        return true
    end

    local command = Settings.startAreaCommand
    if type(command) ~= "string" then
        command = ""
    end
    command = TrimString(command) or ""
    if command == "" then
        return true
    end

    Runtime.startAreaHandled = true

    if not IPC or not IPC.Lifestream or not IPC.Lifestream.ExecuteCommand then
        Dalamud.Log("[Toolkit Helper] Startup area command skipped; Lifestream ExecuteCommand unavailable")
        return false
    end

    if not WaitForTeleportIdle(15) then
        Dalamud.Log("[Toolkit Helper] Startup area command skipped; teleport channel busy")
        return false
    end

    local startTerritoryId = GetCurrentTerritoryType()
    Dalamud.Log(string.format("[Toolkit Helper] Running startup area command via Lifestream: %s", command))

    local ok, err = pcall(function()
        IPC.Lifestream.ExecuteCommand(command)
    end)
    if not ok then
        Dalamud.Log("[Toolkit Helper] Failed to run startup area command: "..tostring(err))
        return false
    end

    Runtime.lastLifestreamCommand = os.clock()
    yield("/wait 1")

    if not WaitForTeleportStart(startTerritoryId, nil, 8) then
        Dalamud.Log("[Toolkit Helper] Startup area command did not begin a zone transition; continuing")
        return false
    end

    local completed = WaitForTeleportCompletion(nil, 30, "startup area command")
    if completed then
        Dalamud.Log("[Toolkit Helper] Startup area command completed")
    else
        Dalamud.Log("[Toolkit Helper] Startup area command timed out waiting for completion")
    end
    return completed
end

--## Position & Movement

function DistanceBetween(pos1, pos2)
    local dx = pos1.X - pos2.X
    local dy = pos1.Y - pos2.Y
    local dz = pos1.Z - pos2.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function GetDistanceToPoint(vec3)
    if vec3 == nil or Entity == nil or Entity.Player == nil or Entity.Player.Position == nil then
        return math.huge
    end
    return DistanceBetween(Entity.Player.Position, vec3)
end

function Dismount()
    if not Svc or not Svc.Condition or not Svc.Condition[CharacterCondition.mounted] then
        return
    end
    if Actions ~= nil and Actions.ExecuteGeneralAction ~= nil then
        local ok = pcall(function()
            Actions.ExecuteGeneralAction(23)
        end)
        if ok then
            return
        end
    end
    yield("/generalaction dismount")
end

function EnsureDismounted()
    if not Svc or not Svc.Condition then
        return false
    end
    local mountedFlags = {
        CharacterCondition.mounted,
        CharacterCondition.mounting57,
        CharacterCondition.mounting64
    }
    local function isMountedState()
        for _, flag in ipairs(mountedFlags) do
            if flag ~= nil and Svc.Condition[flag] then
                return true
            end
        end
        return false
    end

    for attempt = 1, 2 do
        Dismount()
        local deadline = os.clock() + 5
        repeat
            if not isMountedState() then
                return true
            end
            yield("/wait 0.25")
        until os.clock() > deadline
        if not isMountedState() then
            return true
        end
        yield("/wait 0.5")
    end

    return not isMountedState()
end

--## Targeting & Status

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

--## Addon Helpers

function _get_addon(name)
    local ok, addon = pcall(Addons.GetAddon, name)
    if ok and addon ~= nil then
        return addon
    end
    return nil
end

function _addon_ready(addon)
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

function _addon_exists(addon)
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

function WaitForAddonReady(name, timeout)
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

function WaitForAddonVisible(name, timeout)
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

--## Teleportation & Travel

function EnsureInLimsa(reason)
    if Svc.ClientState.TerritoryType == SUMMONING_BELL.territoryId then
        Dalamud.Log(string.format("[Toolkit Helper] Already in Limsa for %s", reason or "repair workflow"))
        return true
    end
    SaveReturnLocationForCurrentTerritory()
    StopVnav()
    EnsureSummoningBellAetheryte()
    local limsaDestination = {
        name = SUMMONING_BELL.aetheryteName or "Limsa Lominsa Lower Decks",
        aetheryteId = SUMMONING_BELL.aetheryteRowId,
        rowId = SUMMONING_BELL.aetheryteRowId,
        territoryId = SUMMONING_BELL.territoryId
    }
    if TeleportTo(limsaDestination) then
        EchoAll("Teleporting to "..limsaDestination.name)
        Dalamud.Log(string.format("[Toolkit Helper] Teleporting to %s for %s", limsaDestination.name, reason or "repair workflow"))
    end
    return false
end

function EorzeaTimeToUnixTime(eorzeaTime)
    return eorzeaTime/(144/7)
end

function WaitForAddonClosed(name, timeout)
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

function GetNodeText(addonName, nodePath, ...)
    local addon = Addons.GetAddon(addonName)
    repeat
        yield("/wait 0.1")
    until addon.Ready
    return addon:GetNode(nodePath, ...).Text
end

function CloseAddonIfMounted(addonName)
    if Addons == nil then return end
    local addon = Addons.GetAddon(addonName)
    if addon ~= nil and addon.Ready then
        yield(string.format("/callback %s true -1", addonName))
        WaitForAddonClosed(addonName, 2)
        yield("/wait 0.5")
    end
end

function IsAddonReady(name)
    return _addon_ready(_get_addon(name))
end

function IsLifestreamBusy()
    if IPC and IPC.Lifestream and IPC.Lifestream.IsBusy then
        local ok, busy = pcall(IPC.Lifestream.IsBusy)
        return ok and busy == true
    end
    return false
end

function IsPlayerAvailable()
    return Player ~= nil and Player.Available == true
end

function DescribeZoneTransitionState()
    local states = {}
    if Svc and Svc.Condition then
        if Svc.Condition[CharacterCondition.casting] then
            table.insert(states, "casting")
        end
        if Svc.Condition[CharacterCondition.betweenAreas] then
            table.insert(states, "betweenAreas")
        end
        if CharacterCondition.betweenAreasForDuty ~= nil and Svc.Condition[CharacterCondition.betweenAreasForDuty] then
            table.insert(states, "betweenAreasForDuty")
        end
    end
    if IsLifestreamBusy() then
        table.insert(states, "lifestreamBusy")
    end
    if #states == 0 then
        return "idle"
    end
    return table.concat(states, ",")
end

function IsZoneTransitionActive()
    if not Svc or not Svc.Condition then
        return IsLifestreamBusy()
    end
    return Svc.Condition[CharacterCondition.casting]
        or Svc.Condition[CharacterCondition.betweenAreas]
        or (CharacterCondition.betweenAreasForDuty ~= nil and Svc.Condition[CharacterCondition.betweenAreasForDuty])
        or IsLifestreamBusy()
end

function IsZoneTransitionComplete()
    return (not IsAddonReady("FadeMiddle"))
        and (not IsLifestreamBusy())
        and (not (Svc and Svc.Condition and Svc.Condition[CharacterCondition.casting]))
        and (not (Svc and Svc.Condition and Svc.Condition[CharacterCondition.betweenAreas]))
        and (not (Svc and Svc.Condition and CharacterCondition.betweenAreasForDuty ~= nil and Svc.Condition[CharacterCondition.betweenAreasForDuty]))
        and IsPlayerAvailable()
end

function WaitForTeleportCompletion(targetTerritoryId, timeoutSec, sourceLabel)
    timeoutSec = tonumber(timeoutSec) or 30
    sourceLabel = tostring(sourceLabel or "teleport")
    local deadline = os.clock() + timeoutSec
    local sawCastEnd = false
    local sawBetweenAreas = false
    local stableStart = nil

    Dalamud.Log(string.format("[Toolkit Helper] Waiting up to %.2fs for %s to complete", timeoutSec, sourceLabel))

    while os.clock() < deadline do
        local currentTerritoryId = GetCurrentTerritoryType()
        local casting = Svc and Svc.Condition and Svc.Condition[CharacterCondition.casting]
        local betweenAreas = Svc and Svc.Condition and Svc.Condition[CharacterCondition.betweenAreas]
        local betweenAreasForDuty = Svc and Svc.Condition and CharacterCondition.betweenAreasForDuty ~= nil and Svc.Condition[CharacterCondition.betweenAreasForDuty]
        local lifestreamBusy = IsLifestreamBusy()
        local fadeReady = IsAddonReady("FadeMiddle")

        if not casting and not sawCastEnd then
            sawCastEnd = true
            Dalamud.Log(string.format("[Toolkit Helper] %s cast phase finished", sourceLabel))
        end

        if betweenAreas or betweenAreasForDuty then
            if not sawBetweenAreas then
                sawBetweenAreas = true
                Dalamud.Log(string.format(
                    "[Toolkit Helper] %s entered zone transition state (betweenAreas=%s, betweenAreasForDuty=%s)",
                    sourceLabel,
                    tostring(betweenAreas),
                    tostring(betweenAreasForDuty)
                ))
            end
            stableStart = nil
        end

        local fullySettled = sawCastEnd
            and (not casting)
            and (not betweenAreas)
            and (not betweenAreasForDuty)
            and (not lifestreamBusy)
            and (not fadeReady)
            and IsPlayerAvailable()
            and (targetTerritoryId == nil or currentTerritoryId == targetTerritoryId)

        if fullySettled then
            if stableStart == nil then
                stableStart = os.clock()
                Dalamud.Log(string.format("[Toolkit Helper] %s appears settled; starting stability confirmation", sourceLabel))
            elseif (os.clock() - stableStart) >= 1.0 then
                Dalamud.Log(string.format(
                    "[Toolkit Helper] %s completion confirmed in territory %s after castEnd=%s, sawBetweenAreas=%s",
                    sourceLabel,
                    tostring(currentTerritoryId),
                    tostring(sawCastEnd),
                    tostring(sawBetweenAreas)
                ))
                if Instances ~= nil and Instances.Framework ~= nil then
                    Runtime.lastTeleport = EorzeaTimeToUnixTime(Instances.Framework.EorzeaTime)
                end
                return true
            end
        else
            stableStart = nil
        end

        yield("/wait 0.25")
    end

    Dalamud.Log(string.format(
        "[Toolkit Helper] %s completion timed out after castEnd=%s, sawBetweenAreas=%s, finalState=%s",
        sourceLabel,
        tostring(sawCastEnd),
        tostring(sawBetweenAreas),
        DescribeZoneTransitionState()
    ))
    return false
end

function StopVnav()
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

function WaitForPlayerStationary(timeout)
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

function WaitForMountStable(stabilitySeconds, timeoutSeconds)
    stabilitySeconds = stabilitySeconds or 2
    timeoutSeconds = timeoutSeconds or 10
    local initialClearSeconds = 0.25
    if not Svc or not Svc.Condition then
        return true
    end

    local function isMounting()
        local flags = {
            CharacterCondition.mounting57,
            CharacterCondition.mounting64
        }
        for _, flag in ipairs(flags) do
            if flag ~= nil and Svc.Condition[flag] then
                return true
            end
        end
        return false
    end

    local function isMounted()
        return CharacterCondition.mounted ~= nil and Svc.Condition[CharacterCondition.mounted]
    end

    local function waitForStableClear()
        local clearStart = os.clock()
        while os.clock() - clearStart < initialClearSeconds do
            if isMounting() then
                return false
            end
            yield("/wait 0.05")
        end
        return true
    end

    if waitForStableClear() then
        return true
    end

    Dalamud.Log("[Toolkit Helper] Mounting detected; waiting for animation to finish before teleport")
    local start = os.clock()
    while isMounting() do
        if os.clock() - start > timeoutSeconds then
            Dalamud.Log("[Toolkit Helper] Mounting wait timed out before teleport")
            return false
        end
        yield("/wait 0.2")
    end

    Dalamud.Log("[Toolkit Helper] Mount animation ended; verifying mount stability")
    local stableStart = nil
    local stabilityDeadline = os.clock() + timeoutSeconds
    while os.clock() < stabilityDeadline do
        if isMounted() then
            if stableStart == nil then
                stableStart = os.clock()
            end
            local elapsed = os.clock() - stableStart
            if elapsed >= stabilitySeconds then
                Dalamud.Log(string.format("[Toolkit Helper] Mount stability confirmed after %.2fs", elapsed))
                return true
            end
        else
            stableStart = nil
        end
        yield("/wait 0.2")
    end

    Dalamud.Log("[Toolkit Helper] Mount stability verification timed out before teleport")
    return false
end

local STUCK_MONITOR_THRESHOLD_SECONDS = 10
local STUCK_MONITOR_MOVE_TOLERANCE = 4.0
local STUCK_MONITOR_RESTART_COOLDOWN_AFTER_RESTART = 0
local STUCK_MONITOR_RESTART_COOLDOWN_AFTER_TELEPORT = 15
local STUCK_MONITOR_LOCAL_AETHERYTE_SKIP_DISTANCE = 25.0

local function CloneVector3(vec)
    if vec == nil then
        return nil
    end
    return Vector3(vec.X, vec.Y, vec.Z)
end

local function StuckMonitorLog(message, verboseOnly)
    if not Settings.enableStuckMonitor then
        return
    end
    if Runtime == nil or Runtime.stuckMonitor == nil then
        return
    end
    local monitor = Runtime.stuckMonitor
    local now = os.clock()
    local lastMessage = monitor.lastLogMessage
    local lastTime = monitor.lastLogTime or 0
    if message ~= lastMessage or (now - lastTime) >= 5 then
        local text = "[Toolkit Helper][Stuck] "..message
        if verboseOnly == true and Dalamud ~= nil and Dalamud.LogVerbose ~= nil then
            Dalamud.LogVerbose(text)
        else
            Dalamud.Log(text)
        end
        monitor.lastLogMessage = message
        monitor.lastLogTime = now
    end
end

function ResetStuckMonitor(reason)
    if Runtime == nil or Runtime.stuckMonitor == nil then
        return
    end
    local monitor = Runtime.stuckMonitor
    monitor.lastPosition = nil
    monitor.lastMovementTime = os.clock()
    monitor.triggered = false
    if reason ~= nil and reason ~= "" then
        StuckMonitorLog("Reset: "..reason, true)
    end
end

function ClearStuckMonitor(reason)
    if Runtime == nil or Runtime.stuckMonitor == nil then
        return
    end
    Runtime.stuckMonitor.consecutiveTriggers = 0
    Runtime.stuckMonitor.lastRecoveryType = nil
    ResetStuckMonitor(reason)
end

local function UpdateStuckMonitorMovement(position)
    if Runtime == nil or Runtime.stuckMonitor == nil then
        return
    end
    if position == nil then
        return
    end
    local monitor = Runtime.stuckMonitor
    monitor.lastPosition = CloneVector3(position)
    monitor.lastMovementTime = os.clock()
    monitor.consecutiveTriggers = 0
    monitor.lastRecoveryType = nil
    monitor.triggered = false
end

local function PrimeStuckMonitorPosition(position)
    if Runtime == nil or Runtime.stuckMonitor == nil then
        return
    end
    if position == nil then
        return
    end
    local monitor = Runtime.stuckMonitor
    monitor.lastPosition = CloneVector3(position)
    monitor.lastMovementTime = os.clock()
    monitor.triggered = false
end

local function GetStuckMonitorCooldown(monitor)
    if monitor == nil then
        return 0
    end
    if monitor.lastRecoveryType == "teleport" then
        return STUCK_MONITOR_RESTART_COOLDOWN_AFTER_TELEPORT
    end
    return STUCK_MONITOR_RESTART_COOLDOWN_AFTER_RESTART
end

local function IsPlayerInFateArea()
    local okCurrent, currentFate = pcall(function()
        return Fates and Fates.CurrentFate
    end)
    if not okCurrent or currentFate == nil then
        return false
    end
    local okInFate, inFate = pcall(function()
        return currentFate.InFate
    end)
    return okInFate and inFate == true
end

local function DistanceBetweenFlat(pos1, pos2)
    if pos1 == nil or pos2 == nil then
        return math.huge
    end
    local dx = pos1.X - pos2.X
    local dz = pos1.Z - pos2.Z
    return math.sqrt(dx * dx + dz * dz)
end

local function GetAetherytesInTerritory(territoryId)
    local results = {}
    if territoryId == nil or not (Svc and Svc.AetheryteList) then
        return results
    end
    for _, aetheryte in ipairs(Svc.AetheryteList) do
        if tonumber(aetheryte.TerritoryId) == tonumber(territoryId) then
            table.insert(results, aetheryte)
        end
    end
    return results
end

local function GetAetheryteName(aetheryte)
    if aetheryte == nil then
        return nil
    end
    local data = aetheryte.AetheryteData
    local value = data and data.Value
    local placeName = value and value.PlaceName
    local placeValue = placeName and placeName.Value
    local name = placeValue and placeValue.Name
    if name and name.GetText then
        local ok, text = pcall(function()
            return name:GetText()
        end)
        if ok and text and text ~= "" then
            return tostring(text)
        end
    end
    return tostring(name or "")
end

local function BuildTerritoryAetheryteList(territoryId)
    local results = {}
    if territoryId == nil or not (Instances and Instances.Telepo and Instances.Telepo.GetAetherytePosition) then
        return results
    end
    local aetherytes = GetAetherytesInTerritory(territoryId)
    for _, aetheryte in ipairs(aetherytes) do
        local aetheryteId = tonumber(aetheryte.AetheryteId)
        local name = GetAetheryteName(aetheryte)
        if aetheryteId ~= nil and name ~= nil and name ~= "" then
            local ok, position = pcall(function()
                return Instances.Telepo:GetAetherytePosition(aetheryteId)
            end)
            if ok and position ~= nil then
                table.insert(results, {
                    aetheryteId = aetheryteId,
                    aetheryteName = name,
                    position = position,
                    territoryId = tonumber(territoryId)
                })
            end
        end
    end
    return results
end

local function GetClosestAetheryteToPlayer(territoryId, playerPosition)
    local aetherytes = BuildTerritoryAetheryteList(territoryId)
    local closestAetheryte = nil
    local closestDistance = math.huge
    for _, aetheryte in ipairs(aetherytes) do
        local comparisonDistance = DistanceBetweenFlat(aetheryte.position, playerPosition)
        if comparisonDistance < closestDistance then
            closestDistance = comparisonDistance
            closestAetheryte = aetheryte
        end
    end
    return closestAetheryte, closestDistance
end

local function TeleportToClosestLocalAetheryte(position)
    local territoryId = GetCurrentTerritoryType()
    if territoryId == nil or position == nil then
        return false
    end
    local aetheryte, distance = GetClosestAetheryteToPlayer(territoryId, position)
    if aetheryte == nil or aetheryte.aetheryteId == nil then
        StuckMonitorLog("Local aetheryte recovery unavailable: no aetheryte found")
        return false
    end
    if distance ~= nil and distance <= STUCK_MONITOR_LOCAL_AETHERYTE_SKIP_DISTANCE then
        StuckMonitorLog(string.format(
            "Local aetheryte recovery skipped: already within %.1f yalms of %s (%.1f yalms)",
            STUCK_MONITOR_LOCAL_AETHERYTE_SKIP_DISTANCE,
            tostring(aetheryte.aetheryteName),
            tonumber(distance) or -1
        ))
        return true
    end
    StuckMonitorLog(string.format("Local aetheryte recovery: teleporting to %s (%.1f yalms)", tostring(aetheryte.aetheryteName), tonumber(distance) or -1))
    local destination = {
        name = aetheryte.aetheryteName,
        aetheryteId = aetheryte.aetheryteId,
        rowId = aetheryte.aetheryteId,
        territoryId = territoryId,
        forceTeleport = true
    }
    return TeleportTo(destination)
end

local function HandleMountedFateStuck(position)
    StuckMonitorLog("Mounted in FATE for "..STUCK_MONITOR_THRESHOLD_SECONDS.."s; dismounting")
    if not EnsureDismounted() then
        StuckMonitorLog("Mounted FATE recovery failed to dismount")
        return false
    end
    PrimeStuckMonitorPosition(position)
    return true
end

local function HandleStuckMonitorTrigger(position)
    local monitor = Runtime.stuckMonitor
    monitor.lastRestartTime = os.clock()
    monitor.triggered = true
    monitor.consecutiveTriggers = math.min((monitor.consecutiveTriggers or 0) + 1, 2)
    if monitor.consecutiveTriggers >= 2 then
        StuckMonitorLog("Trigger 2/2: teleporting to closest local aetheryte")
        StopToolkitRun("stuck monitor local teleport")
        local teleported = TeleportToClosestLocalAetheryte(position)
        if teleported then
            monitor.lastRecoveryType = "teleport"
            ResumeToolkitRun("stuck local teleport recovery")
            monitor.consecutiveTriggers = 0
        else
            StuckMonitorLog("Local aetheryte recovery failed; falling back to restart")
            monitor.lastRecoveryType = "restart"
            yield("/wait 2")
            ResumeToolkitRun("stuck recovery")
        end
    else
        StuckMonitorLog("Trigger 1/2: no movement for "..STUCK_MONITOR_THRESHOLD_SECONDS.."s")
        StopToolkitRun("stuck monitor")
        monitor.lastRecoveryType = "restart"
        yield("/wait 2")
        ResumeToolkitRun("stuck recovery")
    end
    monitor.lastPosition = CloneVector3(position)
    monitor.lastMovementTime = os.clock()
end

function UpdateStuckMonitor()
    if Runtime == nil or Runtime.stuckMonitor == nil then
        return
    end
    local monitor = Runtime.stuckMonitor
    if not Settings.enableStuckMonitor then
        if monitor.enabled then
            ClearStuckMonitor("disabled")
            monitor.enabled = false
        end
        return
    end
    monitor.enabled = true

    if Runtime.stopScript then
        ClearStuckMonitor("script stopping")
        return
    end

    if State == nil then
        ResetStuckMonitor("state unavailable")
        return
    end

    if CharacterState == nil then
        ResetStuckMonitor("state table unavailable")
        return
    end

    local allowedState = State == CharacterState.idle or State == CharacterState.maintainGemstones
    if not allowedState then
        ClearStuckMonitor("state unmonitored")
        return
    end

    if not Svc or not Svc.ClientState then
        ResetStuckMonitor("client unavailable")
        return
    end

    local condition = Svc.Condition
    if condition == nil then
        ResetStuckMonitor("condition unavailable")
        return
    end

    if condition[CharacterCondition.inCombat] then
        ResetStuckMonitor("in combat")
        return
    end

    if condition[CharacterCondition.casting] then
        ResetStuckMonitor("casting")
        return
    end

    if condition[CharacterCondition.mounting57] or condition[CharacterCondition.mounting64] then
        ResetStuckMonitor("mounting")
        return
    end

    local busyStates = {
        CharacterCondition.betweenAreas,
        CharacterCondition.occupiedInEvent,
        CharacterCondition.occupiedInQuestEvent,
        CharacterCondition.occupied,
        CharacterCondition.beingMoved,
        CharacterCondition.occupiedSummoningBell,
        CharacterCondition.occupiedMateriaExtractionAndRepair
    }
    for _, flag in ipairs(busyStates) do
        if flag ~= nil and condition[flag] then
            ResetStuckMonitor("busy state")
            return
        end
    end

    local playerPos = Entity and Entity.Player and Entity.Player.Position
    if playerPos == nil then
        StuckMonitorLog("player unavailable", true)
        return
    end

    if monitor.lastPosition == nil then
        PrimeStuckMonitorPosition(playerPos)
        return
    end

    local distance = DistanceBetweenFlat(playerPos, monitor.lastPosition)
    if distance >= STUCK_MONITOR_MOVE_TOLERANCE then
        UpdateStuckMonitorMovement(playerPos)
        return
    end

    local now = os.clock()
    local stagnantFor = now - (monitor.lastMovementTime or now)
    if stagnantFor < STUCK_MONITOR_THRESHOLD_SECONDS then
        return
    end

    if condition[CharacterCondition.mounted] and IsPlayerInFateArea() then
        HandleMountedFateStuck(playerPos)
        return
    end

    local cooldown = GetStuckMonitorCooldown(monitor)
    local restartCooldown = now - (monitor.lastRestartTime or 0)
    if restartCooldown < cooldown then
        return
    end

    HandleStuckMonitorTrigger(playerPos)
end

function WaitWithStuckMonitor(duration)
    duration = duration or 0
    if duration <= 0 then
        UpdateStuckMonitor()
        return
    end
    local step = 0.5
    local deadline = os.clock() + duration
    while os.clock() < deadline do
        UpdateStuckMonitor()
        local remaining = deadline - os.clock()
        if remaining <= 0 then
            break
        end
        local wait = math.min(step, remaining)
        yield(string.format("/wait %.2f", wait))
    end
end

local TELEPORT_LOCK_TIMEOUT = 180
local TELEPORT_SUCCESS_COOLDOWN = 2
local TELEPORT_FAILURE_COOLDOWN = 3

function TeleportIndicatorsActive()
    if IPC and IPC.Lifestream and IPC.Lifestream.IsBusy then
        local ok, busy = pcall(IPC.Lifestream.IsBusy)
        if ok and busy == true then
            return true
        end
    end
    if Svc and Svc.Condition then
        if Svc.Condition[CharacterCondition.casting] then
            return true
        end
        if Svc.Condition[CharacterCondition.betweenAreas] then
            return true
        end
    end
    return false
end

function AcquireTeleportLock(destName)
    local now = os.clock()
    if Runtime.teleportLockActive then
        if (Runtime.nextTeleportLockLog or 0) <= now then
            Dalamud.Log(string.format("[Toolkit Helper] Teleport request for %s deferred; %s already in progress",
                tostring(destName or "destination"),
                tostring(Runtime.teleportLockDestination or "another teleport")))
            Runtime.nextTeleportLockLog = now + 1
        end
        return false
    end
    local cooldown = Runtime.teleportLockExpires or 0
    if cooldown > now then
        if (Runtime.nextTeleportLockLog or 0) <= now then
            Dalamud.Log(string.format("[Toolkit Helper] Teleport request for %s throttled for %.1fs",
                tostring(destName or "destination"),
                cooldown - now))
            Runtime.nextTeleportLockLog = now + 1
        end
        return false
    end
    Runtime.teleportLockActive = true
    Runtime.teleportLockDestination = destName
    Runtime.teleportLockStarted = now
    Runtime.nextTeleportLockLog = 0
    Dalamud.Log(string.format("[Toolkit Helper] Teleport lock acquired for %s", tostring(destName or "destination")))
    return true
end

function ReleaseTeleportLock(success)
    Runtime.teleportLockActive = false
    Runtime.teleportLockDestination = nil
    Runtime.teleportLockStarted = 0
    local cooldown = success and TELEPORT_SUCCESS_COOLDOWN or TELEPORT_FAILURE_COOLDOWN
    Runtime.teleportLockExpires = os.clock() + cooldown
end

function WaitForTeleportIdle(timeout)
    local deadline = os.clock() + (timeout or 10)
    repeat
        if Runtime.teleportLockActive then
            local started = Runtime.teleportLockStarted or 0
            if started > 0 and os.clock() - started > TELEPORT_LOCK_TIMEOUT then
                Dalamud.Log("[Toolkit Helper] Teleport lock timed out; forcing release")
                ReleaseTeleportLock(false)
            end
        end
        local cooldown = Runtime.teleportLockExpires or 0
        if not Runtime.teleportLockActive and cooldown <= os.clock() and not TeleportIndicatorsActive() then
            return true
        end
        yield("/wait 0.1")
    until os.clock() > deadline
    return false
end

function ChangeState(newState, label)
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

function StopToolkitRun(reason)
    local suffix = ""
    if reason ~= nil and reason ~= "" then
        suffix = " ("..reason..")"
    end
    Dalamud.Log("[Toolkit Helper] Issuing /vfate stop"..suffix)
    yield("/vfate stop")
    StopVnav()
    yield("/wait 0.5")
    Dalamud.Log("[Toolkit Helper] Confirming /vfate stop"..suffix)
    yield("/vfate stop")
    -- Toolkit resumes explicitly via ResumeToolkitRun when appropriate.
end

function EnsureRetainerToolkitStopped(reason)
    if not Runtime.retainerToolkitStopped then
        StopToolkitRun(reason or "retainer pause")
        Runtime.retainerToolkitStopped = true
    end
end

function ResumeToolkitAfterRetainers(reason)
    if Runtime.retainerToolkitStopped then
        Runtime.retainerToolkitStopped = false
        ResumeToolkitRun(reason or "retainer resume")
    end
end

function EnsureRepairToolkitStopped(reason)
    if not Runtime.repairToolkitStopped then
        StopToolkitRun(reason or "repair start")
        Runtime.repairToolkitStopped = true
    end
end

function ResumeToolkitAfterRepair(reason)
    if Runtime.repairToolkitStopped then
        Runtime.repairToolkitStopped = false
        ResumeToolkitRun(reason or "repair resume")
    end
end

function HasPlugin(name)
    for plugin in luanet.each(Svc.PluginInterface.InstalledPlugins) do
        if plugin.InternalName == name and plugin.IsLoaded then
            return true
        end
    end
    return false
end

function GetPluginEnabledState(name)
    if not Svc or not Svc.PluginInterface or not Svc.PluginInterface.InstalledPlugins then
        return nil
    end
    for plugin in luanet.each(Svc.PluginInterface.InstalledPlugins) do
        if plugin.InternalName == name then
            return plugin.IsLoaded == true
        end
    end
    return false
end

function SetPluginEnabledState(name, enabled)
    local command = enabled and ("/xlenableplugin "..name) or ("/xldisableplugin "..name)
    Dalamud.Log(string.format("[Toolkit Helper] %s plugin %s", enabled and "Enabling" or "Disabling", name))
    yield(command)
    yield("/wait 2")
end

function EnsureTextAdvanceEnabled()
    if not IPC or not IPC.TextAdvance or not IPC.TextAdvance.IsEnabled then
        return
    end
    local ok, enabled = pcall(IPC.TextAdvance.IsEnabled)
    if not ok or enabled then
        enabled = ok and enabled
    else
        Dalamud.Log("[Toolkit Helper] Enabling TextAdvance")
        yield("/at y")
        Runtime.textAdvanceEnabledByScript = true
    end
    if not IPC.TextAdvance.GetEnableTalkSkip then
        return
    end
    local talkSkipOk, talkSkipEnabled = pcall(IPC.TextAdvance.GetEnableTalkSkip)
    if talkSkipOk and talkSkipEnabled == false then
        yield("/echo [Toolkit Helper] Warning: TextAdvance TalkSkip is disabled; NPC text boxes will not be accepted.")
    end
end

function RestoreTextAdvanceState()
    if not Runtime.textAdvanceEnabledByScript then
        return
    end
    Dalamud.Log("[Toolkit Helper] Disabling TextAdvance")
    yield("/at n")
    Runtime.textAdvanceEnabledByScript = false
end

function EnsureBossModPreferredState()
    local bossModEnabled = GetPluginEnabledState("BossMod")
    local rebornEnabled = GetPluginEnabledState("BossModReborn")
    if bossModEnabled == nil or rebornEnabled == nil then
        return
    end
    if Runtime.bossmodRecordedState == nil then
        Runtime.bossmodRecordedState = {
            bossModEnabled = bossModEnabled,
            bossModRebornEnabled = rebornEnabled
        }
    end
    if bossModEnabled == true and rebornEnabled == false then
        return
    end
    if bossModEnabled == false and rebornEnabled == true then
        Dalamud.Log("[Toolkit Helper] Switching BossMod plugin pair (BossMod disabled, BossModReborn enabled)")
        SetPluginEnabledState("BossModReborn", false)
        SetPluginEnabledState("BossMod", true)
        yield("/wait 2")
        Runtime.bossmodStateChanged = true
    end
end

function RestoreBossModPreferredState()
    if not Runtime.bossmodStateChanged or Runtime.bossmodRecordedState == nil then
        return
    end
    local original = Runtime.bossmodRecordedState
    Dalamud.Log("[Toolkit Helper] Restoring BossMod plugin configuration")
    local currentBossMod = GetPluginEnabledState("BossMod")
    if currentBossMod ~= nil and currentBossMod ~= original.bossModEnabled then
        SetPluginEnabledState("BossMod", original.bossModEnabled)
    end
    local currentReborn = GetPluginEnabledState("BossModReborn")
    if currentReborn ~= nil and currentReborn ~= original.bossModRebornEnabled then
        SetPluginEnabledState("BossModReborn", original.bossModRebornEnabled)
    end
    yield("/wait 2")
    Runtime.bossmodStateChanged = false
end

function HasStatusId(statusId)
    if Svc == nil or Svc.Objects == nil or Svc.Objects.LocalPlayer == nil then
        return false
    end
    local statusList = Svc.Objects.LocalPlayer.StatusList
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

--## Aetheryte & Return Handling

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

function GetAetherytePlaceNameByRowId(rowId)
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

function ExtractAetheryteRowId(aetheryte)
    if not aetheryte then return nil end

    function normalize(value)
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

function ClearReturnTarget()
    Runtime.returnAetheryteName = nil
    Runtime.returnTerritoryId = nil
    Runtime.returnAetheryteId = nil
    Runtime.returnDestinationTerritoryId = nil
end

function SaveReturnLocationForCurrentTerritory()
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
        Runtime.returnDestinationTerritoryId = territory
        Dalamud.Log(string.format("[Toolkit Helper] Saved return target %s (id=%s) for territory %s", preferred.name, tostring(preferred.aetheryteId), tostring(territory)))
    end
end

function AttemptReturnToSavedLocation(context)
    if Runtime.returnAetheryteName == nil then
        return false
    end
    if Runtime.returnTerritoryId ~= nil and Runtime.returnTerritoryId == Svc.ClientState.TerritoryType then
        ClearReturnTarget()
        return true
    end
    local destination = {
        name = Runtime.returnAetheryteName,
        aetheryteId = Runtime.returnAetheryteId,
        territoryId = Runtime.returnDestinationTerritoryId
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

function EnsureSummoningBellAetheryte()
    if SUMMONING_BELL.aetheryteName ~= nil and SUMMONING_BELL.aetheryteId ~= nil then
        return true
    end

    local resolvedName = nil
    if Svc.AetheryteList ~= nil then
        for _, aetheryte in ipairs(Svc.AetheryteList) do
            local rowId = ExtractAetheryteRowId(aetheryte)
            if rowId == SUMMONING_BELL.aetheryteRowId then
                resolvedName = GetAetheryteName(aetheryte)
                break
            end
        end
    end

    if resolvedName == nil or resolvedName == "" then
        resolvedName = GetAetherytePlaceNameByRowId(SUMMONING_BELL.aetheryteRowId)
            or SUMMONING_BELL.aetheryteName
            or "Limsa Lominsa Lower Decks"
    end

    SUMMONING_BELL.aetheryteName = resolvedName
    SUMMONING_BELL.aetheryteId = SUMMONING_BELL.aetheryteRowId
    Dalamud.Log("[Toolkit Helper] Resolved Limsa aetheryte to "..resolvedName.." (id="..tostring(SUMMONING_BELL.aetheryteId)..")")
    return true
end

function EnsureSummoningBellNameLocalized()
    if SUMMONING_BELL.localizedNameResolved then
        return SUMMONING_BELL.name
    end
    local localized = GetEObjNameByRowId(SUMMONING_BELL.rowId)
    if localized ~= nil and localized ~= "" then
        SUMMONING_BELL.name = localized
    end
    SUMMONING_BELL.localizedNameResolved = true
    Dalamud.Log("[Toolkit Helper] Summoning bell entity name resolved to "..tostring(SUMMONING_BELL.name).." (rowId="..tostring(SUMMONING_BELL.rowId)..")")
    return SUMMONING_BELL.name
end

function AcceptTeleportOfferLocation(destinationAetheryte)
    local notification = Addons.GetAddon("_NotificationTelepo")
    local yesno = Addons.GetAddon("SelectYesno")
    if notification ~= nil and notification.Ready and yesno ~= nil and yesno.Ready then
        Dalamud.Log("[Toolkit Helper] Accepting party teleport offer"..(destinationAetheryte and (" for "..tostring(destinationAetheryte)) or ""))
        yield("/callback SelectYesno true 0")
        return
    end
end

function ResolveDestinationName(dest)
    if type(dest) ~= "table" then
        return dest, false, nil
    end

    local isMini = dest.isMiniAetheryte == true or dest.isMini == true or dest.mini == true
    local name = dest.name or dest.aetheryteName or dest.destinationName or dest.miniAetheryteName
    local id = dest.aetheryteId or dest.rowId or dest.aetheryteRowId
    local miniId = dest.miniAetheryteId or dest.miniRowId or dest.miniAetheryteRowId

    function tryRow(rowId)
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

function ExecuteLifestreamCommand(destName, destId, isMini)
    if not IPC or not IPC.Lifestream then
        return false
    end

    function WaitForLifestreamBusyState(desiredBusy, timeout)
        local deadline = os.clock() + (timeout or 3)
        repeat
            local indicators = TeleportIndicatorsActive()
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

    function WaitForLifestreamReady(timeout)
        return WaitForLifestreamBusyState(false, timeout or 5)
    end

    function dispatchCall(label, fn)
        Dalamud.Log(string.format("[Toolkit Helper] %s preparing", label))
        local ready = WaitForLifestreamReady(5)
        if not ready then
            Dalamud.Log("[Toolkit Helper] Lifestream is still busy before "..label.."; delaying attempt")
            yield("/wait 0.5")
        end
        local sinceLast = os.clock() - (Runtime.lastLifestreamCommand or 0)
        if sinceLast < 2 then
            local waitTime = 2 - sinceLast
            Dalamud.Log(string.format("[Toolkit Helper] %s throttling %.3fs", label, waitTime))
            yield(string.format("/wait %.3f", waitTime))
        end
        Runtime.lastLifestreamCommand = os.clock()
        local ok, err = pcall(fn)
        if not ok then
            Dalamud.Log(string.format("[Toolkit Helper] %s error: %s", label, tostring(err)))
            return false
        end
        Dalamud.Log(string.format("[Toolkit Helper] %s dispatched", label))
        return true
    end

    function tryTeleportById()
        if not destId then
            Dalamud.Log("[Toolkit Helper] tryTeleportById skipped: destId missing")
            return false
        end
        if not IPC.Lifestream.Teleport then
            Dalamud.Log("[Toolkit Helper] tryTeleportById skipped: IPC.Lifestream.Teleport unavailable")
            return false
        end
        return dispatchCall(
            "IPC.Lifestream.Teleport (id="..tostring(destId)..")",
            function()
                IPC.Lifestream.Teleport(destId, isMini and 1 or 0)
            end
        )
    end

    function tryMiniAethernetTeleport()
        if not isMini then
            Dalamud.Log("[Toolkit Helper] tryMiniAethernetTeleport skipped: not mini destination")
            return false
        end
        if not destId then
            Dalamud.Log("[Toolkit Helper] tryMiniAethernetTeleport skipped: no destId")
            return false
        end
        if not IPC.Lifestream.AethernetTeleportById then
            Dalamud.Log("[Toolkit Helper] tryMiniAethernetTeleport skipped: IPC method unavailable")
            return false
        end
        return dispatchCall(
            "IPC.Lifestream.AethernetTeleportById (id="..tostring(destId)..")",
            function()
                IPC.Lifestream.AethernetTeleportById(destId)
            end
        )
    end

    function tryTeleportByName()
        if not destName then
            Dalamud.Log("[Toolkit Helper] tryTeleportByName skipped: no destination name")
            return false
        end
        if not IPC.Lifestream.ExecuteCommand then
            Dalamud.Log("[Toolkit Helper] tryTeleportByName skipped: IPC execute command unavailable")
            return false
        end
        return dispatchCall(
            "IPC.Lifestream.ExecuteCommand ("..tostring(destName)..")",
            function()
                IPC.Lifestream.ExecuteCommand(destName)
            end
        )
    end

    if isMini and tryMiniAethernetTeleport() then
        return true
    end

    if tryTeleportById() then
        return true
    end

    if tryTeleportByName() then
        return true
    end

    Dalamud.Log("[Toolkit Helper] Lifestream could not teleport to "..tostring(destName).." (id="..tostring(destId)..")")
    return false
end

function GetCurrentTerritoryType()
    if Svc == nil or Svc.ClientState == nil then
        return nil
    end
    return Svc.ClientState.TerritoryType
end

function IsInExpectedTerritory(expectedTerritoryId)
    if expectedTerritoryId == nil then
        return false
    end
    local currentTerritory = GetCurrentTerritoryType()
    return currentTerritory ~= nil and currentTerritory == expectedTerritoryId
end

function WaitForTeleportStart(startTerritoryId, expectedTerritoryId, timeout)
    local sourceLabel = "teleport"
    local deadline = os.clock() + (timeout or 8)
    Dalamud.Log(string.format(
        "[Toolkit Helper] Waiting up to %.2fs for %s to start (from %s to %s)",
        (timeout or 8),
        sourceLabel,
        tostring(startTerritoryId),
        tostring(expectedTerritoryId)
    ))
    repeat
        local currentTerritory = GetCurrentTerritoryType()
        local transitionState = DescribeZoneTransitionState()
        if transitionState ~= "idle" then
            Dalamud.Log(string.format("[Toolkit Helper] %s start detected via state: %s", sourceLabel, transitionState))
            return true
        end
        if expectedTerritoryId ~= nil and currentTerritory == expectedTerritoryId and currentTerritory ~= startTerritoryId then
            Dalamud.Log(string.format("[Toolkit Helper] %s start detected via territory arrival: %s", sourceLabel, tostring(currentTerritory)))
            return true
        end
        if startTerritoryId ~= nil and currentTerritory ~= nil and currentTerritory ~= 0 and currentTerritory ~= startTerritoryId then
            Dalamud.Log(string.format("[Toolkit Helper] %s start detected via territory change: %s -> %s", sourceLabel, tostring(startTerritoryId), tostring(currentTerritory)))
            return true
        end
        yield("/wait 0.25")
    until os.clock() > deadline
    Dalamud.Log(string.format("[Toolkit Helper] %s did not start within %.2fs", sourceLabel, (timeout or 8)))
    return false
end

function TeleportTo(destination)
    local destName
    local isMini = false
    local destId = nil
    local expectedTerritoryId = nil
    local forceTeleport = false
    if type(destination) == "table" then
        destName, isMini, destId = ResolveDestinationName(destination)
        expectedTerritoryId = destination.territoryId or destination.destinationTerritoryId
        forceTeleport = destination.forceTeleport == true
    else
        destName = destination
    end

    if destName == nil or destName == "" then
        Dalamud.Log("[Toolkit Helper] TeleportTo called without a valid destination")
        return false
    end

    if not forceTeleport and IsInExpectedTerritory(expectedTerritoryId) then
        Dalamud.Log(string.format("[Toolkit Helper] Already in destination territory for %s", tostring(destName)))
        return true
    end

    local maxAttempts = 3
    for attempt = 1, maxAttempts do
        Dalamud.Log(string.format("[Toolkit Helper] Teleport attempt %d/%d to %s", attempt, maxAttempts, tostring(destName)))
        if not forceTeleport and IsInExpectedTerritory(expectedTerritoryId) then
            Dalamud.Log(string.format("[Toolkit Helper] Destination territory already reached before attempt %d for %s", attempt, tostring(destName)))
            return true
        end
        if not WaitForTeleportIdle(15) then
            Dalamud.Log(string.format("[Toolkit Helper] Teleport to %s aborted; teleport channel busy", tostring(destName)))
            return false
        end
        if not WaitForPlayerStationary(5) then
            return false
        end
        if not WaitForMountStable(2, 10) then
            Dalamud.Log("[Toolkit Helper] Mount stability check failed; teleport aborted")
            return false
        end
        if Svc and Svc.Condition and Svc.Condition[CharacterCondition.casting] then
            Dalamud.Log(string.format("[Toolkit Helper] Teleport to %s aborted; character is casting", tostring(destName)))
            return false
        end
        if Svc and Svc.Condition and Svc.Condition[CharacterCondition.betweenAreas] then
            Dalamud.Log(string.format("[Toolkit Helper] Teleport to %s aborted; character changing zones", tostring(destName)))
            return false
        end

        AcceptTeleportOfferLocation(destName)
        local start = os.clock()
        local startTerritoryId = GetCurrentTerritoryType()

        while Instances ~= nil and Instances.Framework ~= nil and EorzeaTimeToUnixTime(Instances.Framework.EorzeaTime) - Runtime.lastTeleport < 5 do
            Dalamud.Log("[Toolkit Helper] Too soon since last teleport. Waiting...")
            yield("/wait 5.001")
            if os.clock() - start > 30 then
                EchoAll("Teleport failed: timeout while waiting to cast")
                return false
            end
        end

        if not AcquireTeleportLock(destName) then
            return false
        end

        local executed = ExecuteLifestreamCommand(destName, destId, isMini)
        local success = false
        if executed then
            yield("/wait 1")
            if WaitForTeleportStart(startTerritoryId, expectedTerritoryId, 8) then
                success = WaitForTeleportCompletion(expectedTerritoryId, 30, tostring(destName))
                Dalamud.Log(string.format("[Toolkit Helper] TeleportTo completion for %s success=%s", tostring(destName), tostring(success)))
            elseif IsInExpectedTerritory(expectedTerritoryId) then
                Dalamud.Log(string.format("[Toolkit Helper] Destination territory reached for %s without observable start conditions", tostring(destName)))
                success = true
            else
                Dalamud.Log(string.format("[Toolkit Helper] No teleport start detected for %s; retrying if attempts remain", tostring(destName)))
            end
        else
            Dalamud.Log(string.format("[Toolkit Helper] Unable to dispatch teleport command for %s", tostring(destName)))
        end
        ReleaseTeleportLock(success)

        if success then
            return true
        end

        if attempt < maxAttempts then
            if not forceTeleport and IsInExpectedTerritory(expectedTerritoryId) then
                Dalamud.Log(string.format("[Toolkit Helper] Destination territory reached after attempt %d for %s", attempt, tostring(destName)))
                return true
            end
            Dalamud.Log(string.format("[Toolkit Helper] Teleport retry scheduled for %s", tostring(destName)))
        end
    end

    Dalamud.Log(string.format("[Toolkit Helper] Teleport to %s failed after %d attempts", tostring(destName), maxAttempts))
    return false
end

function IsSolutionNineAetheryte(dest)
    if dest == nil then
        return false
    end
    local candidates = {
        dest.aetheryteRowId,
        dest.rowId,
        dest.aetheryteId,
        dest.miniAetheryteId,
        dest.miniRowId
    }
    for _, candidate in ipairs(candidates) do
        local numeric = tonumber(candidate)
        if numeric ~= nil and numeric == SOLUTION_NINE_AETHERYTE_ROW_ID then
            return true
        end
    end
    return false
end

function ShouldUseReturnForSolutionNine(entry)
    if not Settings.useReturnToSolutionNine then
        return false
    end
    if entry == nil or entry.aetheryteTeleport == nil then
        return false
    end
    return IsSolutionNineAetheryte(entry.aetheryteTeleport)
end

function TryReturnToSolutionNine(expectedTerritoryId)
    if not Settings.useReturnToSolutionNine then
        return false
    end
    if not WaitForTeleportIdle(15) then
        Dalamud.Log("[Toolkit Helper] Return to Solution Nine aborted; teleport channel busy")
        return false
    end
    if not WaitForPlayerStationary(5) then
        return false
    end
    if not WaitForMountStable(2, 10) then
        Dalamud.Log("[Toolkit Helper] Mount stability check failed; return aborted")
        return false
    end
    if Svc and Svc.Condition and Svc.Condition[CharacterCondition.casting] then
        Dalamud.Log("[Toolkit Helper] Return to Solution Nine aborted; character is casting")
        return false
    end
    if Svc and Svc.Condition and Svc.Condition[CharacterCondition.betweenAreas] then
        Dalamud.Log("[Toolkit Helper] Return to Solution Nine aborted; character changing zones")
        return false
    end
    if not AcquireTeleportLock("Return (Solution Nine)") then
        return false
    end
    local lockHeld = true
    local startTerritoryId = GetCurrentTerritoryType()
    local usedNative = false
    if Actions ~= nil and Actions.ExecuteGeneralAction ~= nil then
        local ok, err = pcall(function()
            Actions.ExecuteGeneralAction(RETURN_GENERAL_ACTION_ID)
        end)
        usedNative = ok
        if not ok then
            Dalamud.Log("[Toolkit Helper] Failed to execute Return general action: "..tostring(err))
        end
    end
    if not usedNative then
        Dalamud.Log("[Toolkit Helper] Using /generalaction return fallback")
        yield("/generalaction return")
    end
    yield("/wait 1")
    local success = false
    if WaitForTeleportStart(startTerritoryId, expectedTerritoryId, 8) then
        success = WaitForTeleportCompletion(expectedTerritoryId, 30, "return")
    elseif expectedTerritoryId ~= nil and GetCurrentTerritoryType() == expectedTerritoryId then
        success = true
    end
    if success and expectedTerritoryId ~= nil then
        local confirmDeadline = os.clock() + 5
        repeat
            if Svc and Svc.ClientState and Svc.ClientState.TerritoryType == expectedTerritoryId then
                break
            end
            yield("/wait 0.5")
        until os.clock() > confirmDeadline
        if not (Svc and Svc.ClientState and Svc.ClientState.TerritoryType == expectedTerritoryId) then
            Dalamud.Log(string.format("[Toolkit Helper] Return completed but territory %s != expected %s",
                tostring(Svc and Svc.ClientState and Svc.ClientState.TerritoryType),
                tostring(expectedTerritoryId)))
            success = false
        end
    end
    if lockHeld then
        ReleaseTeleportLock(success)
    end
    Dalamud.Log(string.format("[Toolkit Helper] Return to Solution Nine success=%s", tostring(success)))
    return success
end

--## Repair Utilities

function ExecuteRepairGeneralAction()
    local usedNative = false
    if Actions ~= nil and Actions.ExecuteGeneralAction ~= nil then
        local ok, err = pcall(function()
            Actions.ExecuteGeneralAction(REPAIR_GENERAL_ACTION_ID)
        end)
        usedNative = ok
        if not ok then
            Dalamud.Log("[Toolkit Helper] Actions.ExecuteGeneralAction failed: "..tostring(err))
        end
    end
    if not usedNative then
        Dalamud.Log("[Toolkit Helper] Actions.ExecuteGeneralAction unavailable; falling back to /generalaction command")
        yield("/generalaction repair")
    end
    yield("/wait 0.5")
end

function GetCurrentChocoboStanceCommand()
    if Instances == nil or Instances.Buddy == nil or Instances.Buddy.CompanionInfo == nil then
        return nil
    end
    local ok, activeCommand = pcall(function()
        return Instances.Buddy.CompanionInfo.ActiveCommand
    end)
    if not ok or activeCommand == nil then
        return nil
    end
    local numericCommand = tonumber(activeCommand)
    if numericCommand == nil then
        return nil
    end
    return math.floor(numericCommand)
end

function ExecuteBuddyAction(actionId)
    if Actions == nil or Actions.ExecuteAction == nil then
        return false, "Actions.ExecuteAction unavailable"
    end
    local ok, err = pcall(function()
        if ActionType ~= nil and ActionType.BuddyAction ~= nil then
            Actions.ExecuteAction(actionId, ActionType.BuddyAction)
        else
            Actions.ExecuteAction(actionId, BUDDY_ACTION_TYPE_ID)
        end
    end)
    if not ok then
        return false, tostring(err)
    end
    return true
end

function ApplyChocoboStanceIfNeeded()
    local now = os.clock()
    if now < (Runtime.nextChocoboStanceCheck or 0) then
        return
    end
    Runtime.nextChocoboStanceCheck = now + CHOCOBO_STANCE_CHECK_INTERVAL_SECONDS

    local desiredCommand = Settings.chocoboStanceActionId
    if desiredCommand == nil then
        return
    end

    local currentCommand = GetCurrentChocoboStanceCommand()
    if currentCommand == nil or currentCommand == desiredCommand then
        return
    end

    local ok, err = ExecuteBuddyAction(desiredCommand)
    if not ok then
        Dalamud.Log("[Toolkit Helper] Failed to set chocobo stance: "..tostring(err))
        return
    end

    EchoAll(string.format("Set chocobo stance to %s", tostring(Settings.chocoboStance)))
end

--## Retainer & Runtime Checks

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

function ReadyToProcess()
    return CurrentCharacterRetainersReady() and Inventory.GetFreeInventorySlots() > 1
end

function ShouldWaitForBonusBuff()
    return Settings.waitIfBonusBuff and (HasStatusId(1288) or HasStatusId(1289))
end

function GetCurrentFateInfo()
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

function ShouldDelayProcessing()
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
local SelectedGemstoneEntry = nil

function ResetPurchaseCycleTracking()
    if Runtime == nil then
        return
    end
    Runtime.purchaseCycleCount = 0
    Runtime.purchaseLimitReached = false
    Runtime.purchaseLimitHandled = false
    Runtime.purchaseLimitFollowUpIssued = false
    Runtime.deferredFollowUpScript = nil
    Runtime.deferredEnableMultiMode = false
end

function GetPurchaseCycleLimit()
    local limit = Settings.purchaseCycleLimit or 0
    if type(limit) ~= "number" then
        return 0
    end
    return math.max(0, math.floor(limit))
end

function HasReachedPurchaseCycleLimit()
    local limit = GetPurchaseCycleLimit()
    if limit <= 0 then
        return false
    end
    if Runtime.purchaseLimitReached then
        return true
    end
    local count = Runtime.purchaseCycleCount or 0
    return count >= limit
end

function RegisterGemstonePurchaseCycle()
    Runtime.purchaseCycleCount = (Runtime.purchaseCycleCount or 0) + 1
    local limit = GetPurchaseCycleLimit()
    local hitLimit = limit > 0 and Runtime.purchaseCycleCount >= limit
    if hitLimit then
        Runtime.purchaseLimitReached = true
    end
    return Runtime.purchaseCycleCount, limit, hitLimit
end

function RunFollowUpScript(scriptName)
    if Runtime.purchaseLimitFollowUpIssued then
        return false
    end
    if type(scriptName) ~= "string" then
        return false
    end
    local trimmed = TrimString(scriptName) or ""
    if trimmed == "" then
        return false
    end
    local sanitized = trimmed:gsub('"', '\\"')
    Dalamud.Log(string.format("[Toolkit Helper] Running follow-up script '%s'", trimmed))
    yield(string.format('/snd run "%s"', sanitized))
    Runtime.purchaseLimitFollowUpIssued = true
    return true
end

function HandlePurchaseLimitReached()
    if Runtime.purchaseLimitHandled then
        return
    end
    Runtime.purchaseLimitReached = true
    Runtime.purchaseLimitHandled = true
    local count = Runtime.purchaseCycleCount or 0
    local limit = GetPurchaseCycleLimit()
    Dalamud.Log(string.format("[Toolkit Helper] Gemstone purchase limit reached (%d/%d)", count, limit))
    EchoAll("Gemstone purchase limit reached; stopping Toolkit Helper")
    local followUp = Settings.purchaseLimitFollowUp or ""
    if followUp ~= nil and followUp ~= "" then
        Runtime.deferredFollowUpScript = followUp
    elseif Settings.enableMultiModeOnLimit then
        Runtime.deferredEnableMultiMode = true
    end
    StopToolkitRun("purchase limit reached")
    Runtime.stopScript = true
end

function GetBicolorGemCount()
    local ok, count = pcall(function()
        return Inventory.GetItemCount(BICOLOR_GEM_ITEM_ID)
    end)
    if not ok or count == nil then
        return 0
    end
    return count
end

function NeedsGemstones()
    if not Settings.maintainGemstones then
        return false
    end
    local target = Settings.gemstoneTarget or 0
    if target <= 0 then
        return false
    end
    return GetBicolorGemCount() < target
end

function GetDarkMatterCount()
    local ok, count = pcall(function()
        return Inventory.GetItemCount(DARK_MATTER_ITEM_ID)
    end)
    if not ok or count == nil then
        return 0
    end
    return count
end

function GetRequiredDarkMatterCount(needsCount)
    local required = tonumber(needsCount) or 0
    if required < 0 then
        required = 0
    end
    return math.floor(required)
end

function ResetRepairActionState()
    Runtime.repairActionPending = false
    Runtime.repairActionStartedAt = 0
    Runtime.repairConditionSeen = false
    Runtime.repairRetryCount = 0
end

function BeginRepairActionAttempt()
    Runtime.repairActionPending = true
    Runtime.repairActionStartedAt = os.clock()
    Runtime.repairConditionSeen = false
end

function HandlePendingRepairAction(maxWaitSeconds, maxRetries)
    maxWaitSeconds = maxWaitSeconds or 5
    maxRetries = maxRetries or 2

    if not Runtime.repairActionPending then
        return false, false
    end

    if Svc.Condition[CharacterCondition.occupiedMateriaExtractionAndRepair] then
        if not Runtime.repairConditionSeen then
            Dalamud.Log("[Toolkit Helper] Repair condition detected; waiting for repair to finish")
            Runtime.repairConditionSeen = true
        end
        return true, false
    end

    if Runtime.repairConditionSeen then
        Dalamud.Log("[Toolkit Helper] Repair condition cleared")
        Runtime.repairActionPending = false
        Runtime.repairActionStartedAt = 0
        Runtime.repairConditionSeen = false
        Runtime.repairRetryCount = 0
        return false, true
    end

    if (os.clock() - (Runtime.repairActionStartedAt or 0)) < maxWaitSeconds then
        return true, false
    end

    Runtime.repairRetryCount = (Runtime.repairRetryCount or 0) + 1
    if Runtime.repairRetryCount >= maxRetries then
        Dalamud.Log(string.format("[Toolkit Helper] Repair condition timeout after %d attempts; falling back to NPC repair", Runtime.repairRetryCount))
        Runtime.repairActionPending = false
        Runtime.repairActionStartedAt = 0
        Runtime.repairConditionSeen = false
        Runtime.repairRetryCount = 0
        Runtime.repairUseNpcFallback = true
        return false, false
    end

    Dalamud.Log(string.format("[Toolkit Helper] Repair condition timeout; retrying repair callback (%d/%d)", Runtime.repairRetryCount, maxRetries))
    Runtime.repairActionStartedAt = os.clock()
    return false, false
end

function GetRepairItemsCount()
    local threshold = Settings.repairThreshold or 0
    if threshold <= 0 then
        return 0
    end
    local items = Inventory.GetItemsInNeedOfRepairs(threshold)
    if not items then
        return 0
    end
    local count = items.Count or 0
    return count
end

function NeedsRepair()
    return GetRepairItemsCount() > 0
end

function ShouldRepairNow()
    local threshold = Settings.repairThreshold or 0
    if threshold <= 0 then
        return false
    end
    local count = GetRepairItemsCount()
    if count <= 0 then
        return false
    end
    local delay = ShouldDelayProcessing()
    if delay == true then
        return false
    end
    return true, count
end

function ShouldProcessRetainersNow()
    if not Settings.pauseRetainers then
        return false
    end
    if not ReadyToProcess() then
        return false
    end
    local delay = ShouldDelayProcessing()
    if delay == true then
        return false
    end
    return true
end

function ComputeGemstoneRunCount(goal)
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

function DetermineToolkitRunCount()
    if Settings.maintainGemstones and (Settings.gemstoneTarget or 0) > 0 then
        local runs = ComputeGemstoneRunCount(Settings.gemstoneTarget)
        if runs <= 0 then
            runs = 1
        end
        return runs
    end
    return 1000
end

function _ResumeToolkitRun(reason)
    local runs = DetermineToolkitRunCount()
    local suffix = ""
    if reason ~= nil and reason ~= "" then
        suffix = " ("..reason..")"
    end
    Dalamud.Log(string.format("[Toolkit Helper] Issuing /vfate run %d%s", runs, suffix))
    yield(string.format("/vfate run %d", runs))
    Runtime.initialToolkitStarted = true
end

ResumeToolkitRun = _ResumeToolkitRun


function IssueToolkitGemstoneRun(runCount, goal)
    local count = math.max(1, runCount)
    local gemstoneGoal = goal or Settings.gemstoneTarget or 0
    Dalamud.Log(string.format("[Toolkit Helper] Issuing /vfate run %d to reach %d gemstones", count, gemstoneGoal))
    yield(string.format("/vfate run %d", count))
    Runtime.pendingGemstoneGoal = gemstoneGoal
    Runtime.gemstoneRunIssuedAt = os.clock()
end

function WaitForGemstoneGoal(goal)
    local gemstoneGoal = goal or Settings.gemstoneTarget or 0
    if gemstoneGoal <= 0 then
        return true
    end
    while true do
        if Runtime.stopScript then
            return GetBicolorGemCount() >= gemstoneGoal
        end
        ApplyChocoboStanceIfNeeded()
        if GetBicolorGemCount() >= gemstoneGoal then
            return true
        end
        if ShouldRepairNow() then
            return false, "repair"
        end
        if ShouldProcessRetainersNow() then
            return false, "retainer"
        end
        WaitWithStuckMonitor(5)
    end
end

function EnsureGemstoneSelection()
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

function ShouldExchangeGemstones()
    if not Settings.exchangeGemstones then
        return false
    end
    if HasReachedPurchaseCycleLimit() then
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

function MoveNearPosition(targetPos, stopDistance)
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

function MoveWithinLimsaTarget(targetPos)
    if targetPos == nil then
        return true
    end
    if GetDistanceToPoint(targetPos) > (DistanceBetween(HAWKERS_ALLEY_POSITION, targetPos) + 10) then
        Dalamud.Log("[Toolkit Helper] Using mini aetheryte to reach Limsa vendor")
        local miniDest = {
            name = "Hawkers' Alley",
            isMiniAetheryte = true,
            isMini = true,
            mini = true,
            aetheryteId = HAWKERS_MINI_AETHERYTE_ID,
            miniAetheryteId = HAWKERS_MINI_AETHERYTE_ID
        }
        local teleported = TeleportTo(miniDest)
        if not teleported then
            Dalamud.Log("[Toolkit Helper] Mini aetheryte teleport failed; will retry shortly")
        end
        yield("/wait 1")
        return false
    end
    local tele = Addons.GetAddon("TelepotTown")
    if tele ~= nil and tele.Ready then
        Dalamud.Log("[Toolkit Helper] Closing TelepotTown before moving to vendor")
        yield("/callback TelepotTown false -1")
        return false
    end
    if GetDistanceToPoint(targetPos) > 5 then
        if not (IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning()) then
            Dalamud.Log("[Toolkit Helper] Pathing to Limsa vendor location")
            IPC.vnavmesh.PathfindAndMoveTo(targetPos, false)
        end
        return false
    end
    return true
end

function TargetNpcByName(name)
    if name == nil or name == "" then
        return false
    end
    local current = GetTargetName()
    if current == name then
        return true
    end
    local sanitized = name:gsub('"', '\\"')
    yield('/target "'..sanitized..'"')
    return GetTargetName() == name
end

function InteractWithNpcAtPosition(position, npcRowId, fallbackName)
    if not MoveWithinLimsaTarget(position) then
        return false
    end
    if not EnsureDismounted() then
        Dalamud.Log("[Toolkit Helper] Unable to dismount before interacting with NPC")
        return false
    end
    local npcName = GetLocalizedNpcName(npcRowId, fallbackName)
    if npcName == nil or npcName == "" then
        Dalamud.Log(string.format("[Toolkit Helper] Unable to resolve NPC name for rowId=%s", tostring(npcRowId)))
        return false
    end
    if not TargetNpcByName(npcName) then
        Dalamud.Log("[Toolkit Helper] Could not target NPC "..npcName)
        return false
    end
    if not Svc.Condition[CharacterCondition.occupiedInQuestEvent] then
        Dalamud.Log("[Toolkit Helper] Interacting with NPC "..npcName)
        yield("/interact")
        return false
    end
    return true
end

function InteractWithGemstoneVendor(entry)
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

function InteractWithSummoningBell()
    local bellName = EnsureSummoningBellNameLocalized()
    if bellName == nil or bellName == "" then
        return false
    end
    Dalamud.Log("[Toolkit Helper] Attempting to interact with summoning bell named "..bellName)
    local deadline = os.clock() + 2
    if Entity and Entity.GetEntityByName then
        repeat
            local bell = Entity.GetEntityByName(bellName)
            if bell ~= nil then
                bell:SetAsTarget()
                yield("/wait 0.2")
                bell:Interact()
                return true
            end
            yield("/wait 0.1")
        until os.clock() > deadline
    end

    local attempts = 0
    repeat
        attempts = attempts + 1
        yield('/target "'..bellName..'"')
        yield("/wait 0.2")
        if Svc.Targets.Target ~= nil and GetTargetName() == bellName then
            yield("/interact")
            return true
        end
        yield("/wait 0.2")
    until attempts >= 3

    Dalamud.Log("[Toolkit Helper] Unable to locate summoning bell entity for interaction")
    return false
end

function EnsureGemstoneShopOpen(entry)
    local shop = WaitForAddonReady("ShopExchangeCurrency", 3)
    if shop ~= nil then
        return shop
    end
    InteractWithGemstoneVendor(entry)
    return WaitForAddonReady("ShopExchangeCurrency", 5)
end

function PurchaseGemstoneItem(entry, shop)
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

function ResetExchangeState()
    Runtime.exchangeInProgress = false
    Runtime.exchangeStarted = false
    Runtime.usedMiniTeleport = false
    Runtime.exchangeDelayActive = false
    Runtime.lastExchangeDelayLog = 0
end

function FinishGemstoneExchange(reason, options)
    options = options or {}
    local suppressResume = options.suppressResume == true
    local skipReturnTeleport = options.skipReturnTeleport == true
    ResetExchangeState()
    Runtime.nextExchangeCheck = os.clock() + 30
    if reason then
        Dalamud.Log("[Toolkit Helper] "..reason)
    end
    if not skipReturnTeleport then
        AttemptReturnToSavedLocation("gemstone exchange")
    end
    if not suppressResume then
        ResumeToolkitRun("after gemstone exchange")
    end
    ChangeState(CharacterState.idle)
end

function FinishRepairWorkflow(reason)
    if reason then
        Dalamud.Log("[Toolkit Helper] "..reason)
    end
    ResetRepairActionState()
    Runtime.repairUseNpcFallback = false
    Runtime.pendingRepair = false
    Runtime.nextRepairCheck = os.clock() + 120
    AttemptReturnToSavedLocation("repair workflow")
    ResumeToolkitAfterRepair("repair workflow complete")
    ChangeState(CharacterState.idle, "Idle")
end

function LogFeatureFlagsOnce()
    if Runtime.featureLogPrinted then return end
    local entries = {}

    local function flagLabel(value)
        return value and "enabled" or "disabled"
    end

    local function yesNo(value)
        return value and "yes" or "no"
    end

    local gearsetLabel = "disabled"
    if equipGearsetSlot ~= nil and equipGearsetSlot >= 0 then
        gearsetLabel = tostring(equipGearsetSlot + 1)
    end
    table.insert(entries, string.format("Gearset slot: %s", gearsetLabel))

    table.insert(entries, string.format("Pause for retainers: %s (close list: %s, check interval: %ds)",
        flagLabel(Settings.pauseRetainers),
        yesNo(Settings.closeRetainerList),
        Settings.checkInterval or 0))

    table.insert(entries, string.format("Maintain gemstone stockpile: %s (target=%d)",
        flagLabel(Settings.maintainGemstones),
        Settings.gemstoneTarget or 0))

    table.insert(entries, string.format("Exchange gemstones: %s (item=%s)",
        flagLabel(Settings.exchangeGemstones),
        Settings.bicolorItem or "None"))

    table.insert(entries, string.format("Gemstone purchase cycle limit: %d", Settings.purchaseCycleLimit or 0))

    local followUp = Settings.purchaseLimitFollowUp
    if followUp == nil or followUp == "" then
        followUp = "none"
    end
    table.insert(entries, string.format("Follow-up script: %s", followUp))

    table.insert(entries, string.format("Enable AutoRetainer multi-mode after limit: %s",
        flagLabel(Settings.enableMultiModeOnLimit)))

    table.insert(entries, string.format("Use Return for Solution Nine: %s",
        flagLabel(Settings.useReturnToSolutionNine)))

    table.insert(entries, string.format("Chocobo stance: %s (check interval=%ds)",
        Settings.chocoboStance or "Disabled",
        CHOCOBO_STANCE_CHECK_INTERVAL_SECONDS))

    table.insert(entries, string.format("Self repair: %s (auto-buy dark matter: %s, threshold=%d%%)",
        flagLabel(Settings.selfRepair),
        flagLabel(Settings.autoBuyDarkMatter),
        Settings.repairThreshold or 0))

    table.insert(entries, string.format("Enable stuck monitoring: %s (threshold=%ds)",
        flagLabel(Settings.enableStuckMonitor),
        STUCK_MONITOR_THRESHOLD_SECONDS))

    table.insert(entries, string.format("Echo logs level: %s",
        Settings.echoLevel or "none"))

    for _, msg in ipairs(entries) do
        Dalamud.Log("[Toolkit Helper] "..msg)
    end
    Runtime.featureLogPrinted = true
end

function OnStop()
    if not Runtime.purchaseLimitHandled then
        StopToolkitRun("script stop")
    end
    Runtime.pendingRepair = false
    Runtime.repairToolkitStopped = false
    if IPC and IPC.Lifestream and IPC.Lifestream.Abort then
        pcall(function()
            IPC.Lifestream.Abort()
        end)
    end
    StopVnav()
    RestoreTextAdvanceState()
    RestoreBossModPreferredState()

    local deferredFollowUp = Runtime.deferredFollowUpScript
    local deferredEnableMultiMode = Runtime.deferredEnableMultiMode == true
    Runtime.deferredFollowUpScript = nil
    Runtime.deferredEnableMultiMode = false

    if deferredFollowUp ~= nil and deferredFollowUp ~= "" then
        local started = RunFollowUpScript(deferredFollowUp)
        if not started then
            Dalamud.Log("[Toolkit Helper] Failed to run deferred follow-up script after stop")
        end
    elseif deferredEnableMultiMode then
        local enabled = SetAutoRetainerMultiMode(true)
        if enabled then
            Dalamud.Log("[Toolkit Helper] AutoRetainer multi-mode enabled due to purchase limit")
            EchoAll("AutoRetainer multi-mode enabled for follow-up automation")
        else
            Dalamud.Log("[Toolkit Helper] Failed to enable AutoRetainer multi-mode after purchase limit")
        end
    end
end
--#endregion Helpers

--#region State Functions

function Idle()
    RefreshSettings()
    if Runtime.stopScript then return end

    if not Player.Available or Svc.Condition[CharacterCondition.betweenAreas] then
        return
    end

    ApplyChocoboStanceIfNeeded()

    if HasReachedPurchaseCycleLimit() then
        HandlePurchaseLimitReached()
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

    local repairThreshold = Settings.repairThreshold or 0
    if repairThreshold > 0 then
        local nowCheck = os.clock()
        if nowCheck >= (Runtime.nextRepairCheck or 0) then
            Runtime.nextRepairCheck = nowCheck + 30
            local shouldRepair, repairCount = ShouldRepairNow()
            if shouldRepair then
                Dalamud.Log(string.format("[Toolkit Helper] Repair check: %d items at/below %d%% durability", repairCount or 0, repairThreshold))
                Dalamud.Log("[Toolkit Helper] Durability threshold reached; entering RepairGear state")
                Runtime.pendingRepair = true
                ChangeState(CharacterState.repairGear, "RepairGear")
                return
            elseif Settings.echoLevel == "all" then
                Dalamud.Log(string.format("[Toolkit Helper] Repair check: no items below %d%%", repairThreshold))
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

    if Settings.maintainGemstones and Runtime.pendingGemstoneGoal == nil then
        if os.clock() >= Runtime.lastGemstoneCheck then
            Runtime.lastGemstoneCheck = os.clock() + 30
            if NeedsGemstones() then
                local delay, reason = ShouldDelayProcessing()
                if delay then
                    Dalamud.Log("[Toolkit Helper] Need gemstones but delaying because "..reason)
                    return
                end
                Dalamud.Log("[Toolkit Helper] Gemstones below target; entering MaintainGemestones state")
                ChangeState(CharacterState.maintainGemstones, "MaintainGemestones")
                return
            end
        end
    end

    if not Runtime.initialToolkitStarted then
        ResumeToolkitRun("initial start")
    end
end

function ProcessRetainers()
    RefreshSettings()
    EnsureSummoningBellNameLocalized()
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
        local limsaDestination = {
            name = SUMMONING_BELL.aetheryteName or "Limsa Lominsa Lower Decks",
            aetheryteId = SUMMONING_BELL.aetheryteRowId,
            rowId = SUMMONING_BELL.aetheryteRowId,
            territoryId = SUMMONING_BELL.territoryId
        }
        if TeleportTo(limsaDestination) then
            EchoAll("Teleporting to "..limsaDestination.name)
            Dalamud.Log("[Toolkit Helper] Teleporting to "..limsaDestination.name.." for retainer processing")
        end
        return
    end

    if GetDistanceToPoint(SUMMONING_BELL.position) > 4.5 then
        IPC.vnavmesh.PathfindAndMoveTo(SUMMONING_BELL.position, false)
        return
    end

    if not Svc.Condition[CharacterCondition.occupiedSummoningBell] then
        if not InteractWithSummoningBell() then
            return
        end
        local retainerList = WaitForAddonReady("RetainerList", 5)
        if retainerList ~= nil then
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

    if HasReachedPurchaseCycleLimit() then
        Runtime.pendingGemstoneGoal = nil
        ChangeState(CharacterState.idle)
        HandlePurchaseLimitReached()
        return
    end

    ApplyChocoboStanceIfNeeded()

    if ShouldProcessRetainersNow() then
        Dalamud.Log("[Toolkit Helper] Interrupting gemstone maintenance for retainer processing")
        Runtime.pendingGemstoneGoal = nil
        ChangeState(CharacterState.processRetainers, "ProcessRetainers")
        return
    end

    if ShouldRepairNow() then
        Dalamud.Log("[Toolkit Helper] Interrupting gemstone maintenance for repairs")
        Runtime.pendingGemstoneGoal = nil
        ChangeState(CharacterState.repairGear, "RepairGear")
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
    local reached, interrupt = WaitForGemstoneGoal(target)
    if reached == true then
        Dalamud.Log(string.format("[Toolkit Helper] Gemstone goal of %d reached (current=%d)", target, GetBicolorGemCount()))
        StopToolkitRun("gemstone goal reached")
    elseif interrupt == "repair" then
        Dalamud.Log("[Toolkit Helper] Stopping gemstone run to handle repairs")
        StopToolkitRun("repair priority")
        Runtime.pendingGemstoneGoal = nil
        ChangeState(CharacterState.repairGear, "RepairGear")
        return
    elseif interrupt == "retainer" then
        Dalamud.Log("[Toolkit Helper] Stopping gemstone run to process retainers")
        StopToolkitRun("retainer priority")
        Runtime.pendingGemstoneGoal = nil
        ChangeState(CharacterState.processRetainers, "ProcessRetainers")
        return
    else
        Dalamud.Log(string.format("[Toolkit Helper] Timed out waiting for gemstone goal (%d). Current=%d", target, GetBicolorGemCount()))
        StopToolkitRun("gemstone goal timeout")
    end
    Runtime.pendingGemstoneGoal = nil
    ChangeState(CharacterState.idle, "Idle")
end

function RepairGear()
    RefreshSettings()
    local threshold = Settings.repairThreshold or 0
    if threshold <= 0 then
        ResetRepairActionState()
        Runtime.repairUseNpcFallback = false
        Runtime.pendingRepair = false
        ResumeToolkitAfterRepair("repair disabled")
        ChangeState(CharacterState.idle)
        return
    end

    local needsRepair = Inventory.GetItemsInNeedOfRepairs(threshold)
    local needsCount = needsRepair and needsRepair.Count or 0
    local darkMatterCount = GetDarkMatterCount()
    local requiredDarkMatter = GetRequiredDarkMatterCount(needsCount)
    Dalamud.Log(string.format("[Toolkit Helper] RepairGear state: threshold=%d%%, needs=%d, darkMatter=%d, requiredDarkMatter=%d", threshold, needsCount or 0, darkMatterCount, requiredDarkMatter))

    local yesno = Addons.GetAddon("SelectYesno")
    if yesno ~= nil and yesno.Ready then
        Dalamud.Log("[Toolkit Helper] Confirming repair prompt")
        yield("/callback SelectYesno true 0")
        WaitForAddonClosed("SelectYesno", 3)
        yield("/wait 0.5")
        return
    end

    local repairAddon = Addons.GetAddon("Repair")
    if repairAddon ~= nil and repairAddon.Ready then
        if Svc.Condition[CharacterCondition.mounted] or Svc.Condition[CharacterCondition.mounting57] or Svc.Condition[CharacterCondition.mounting64] then
            Dalamud.Log("[Toolkit Helper] Mount detected while repair addon open; closing and retrying")
            CloseAddonIfMounted("Repair")
            ResetRepairActionState()
            return
        end
        if needsCount == nil or needsCount == 0 then
            ResetRepairActionState()
            Dalamud.Log("[Toolkit Helper] Repairs complete; closing repair menu")
            yield("/callback Repair true -1")
            WaitForAddonClosed("Repair", 3)
            FinishRepairWorkflow("repair menu closed")
        else
            if Runtime.repairUseNpcFallback then
                Dalamud.Log("[Toolkit Helper] Repair menu open; issuing repair callback")
                yield("/callback Repair true 0")
                local confirmAddon = WaitForAddonVisible("SelectYesno", 3)
                if confirmAddon ~= nil and confirmAddon.Ready then
                    Dalamud.Log("[Toolkit Helper] Confirming repair after repair callback")
                    yield("/callback SelectYesno true 0")
                    WaitForAddonClosed("SelectYesno", 3)
                    yield("/wait 0.5")
                else
                    Dalamud.Log("[Toolkit Helper] Repair confirmation did not appear; retrying")
                end
            else
                local waitingOnRepair, repairFinished = HandlePendingRepairAction(5, 2)
                if waitingOnRepair then
                    if Runtime.repairConditionSeen then
                        yield("/wait 0.5")
                    end
                    return
                end
                if Runtime.repairUseNpcFallback then
                    Dalamud.Log("[Toolkit Helper] Closing self-repair menu before NPC fallback")
                    yield("/callback Repair true -1")
                    WaitForAddonClosed("Repair", 3)
                    return
                end
                if repairFinished then
                    yield("/wait 0.5")
                    return
                end

                Dalamud.Log("[Toolkit Helper] Repair menu open; issuing repair callback")
                yield("/callback Repair true 0")
                BeginRepairActionAttempt()
            end
        end
        return
    end

    if needsCount == nil or needsCount == 0 then
        FinishRepairWorkflow("durability restored")
        return
    end

    EnsureRepairToolkitStopped("repair start")
    SaveReturnLocationForCurrentTerritory()

    if Svc.Condition[CharacterCondition.occupiedMateriaExtractionAndRepair] then
        Dalamud.Log("[Toolkit Helper] Repair UI indicates character is busy repairing; waiting")
        yield("/wait 1")
        return
    end

    local shopAddon = Addons.GetAddon("Shop")
    if shopAddon ~= nil and shopAddon.Ready and darkMatterCount >= requiredDarkMatter then
        Dalamud.Log("[Toolkit Helper] Closing vendor shop before resuming repairs")
        yield("/callback Shop true -1")
        WaitForAddonClosed("Shop", 2)
        yield("/wait 0.5")
        return
    end

    if Settings.selfRepair then
        if darkMatterCount >= requiredDarkMatter and not Runtime.repairUseNpcFallback then
            Dalamud.Log("[Toolkit Helper] Ensuring character is dismounted before repair")
            if not EnsureDismounted() then
                Dalamud.Log("[Toolkit Helper] Dismount failed; retrying later")
                return
            end
            Dalamud.Log("[Toolkit Helper] Executing self-repair general action")
            ResetRepairActionState()
            ExecuteRepairGeneralAction()
            return
        elseif Settings.autoBuyDarkMatter then
            Dalamud.Log(string.format("[Toolkit Helper] Insufficient Dark Matter for self-repair (have=%d, need=%d); purchasing more", darkMatterCount, requiredDarkMatter))
            if not EnsureInLimsa("dark matter purchase") then
                return
            end
            shopAddon = Addons.GetAddon("Shop")
            if shopAddon == nil or not shopAddon.Ready then
                if not EnsureDismounted() then
                    Dalamud.Log("[Toolkit Helper] Unable to dismount before vendor interaction; retrying")
                    return
                end
                if not InteractWithNpcAtPosition(UNSYNRAEL_POSITION, UNSYNRAEL_ROW_ID, "Unsynrael") then
                    return
                end
                shopAddon = WaitForAddonReady("Shop", 3)
                if shopAddon == nil then
                    Dalamud.Log("[Toolkit Helper] Waiting for Shop addon to open before purchasing Dark Matter")
                    return
                end
            end
            Dalamud.Log("[Toolkit Helper] Purchasing Grade 8 Dark Matter from "..GetLocalizedNpcName(UNSYNRAEL_ROW_ID, "Unsynrael"))
            yield("/callback Shop true 0 9 99")
            local purchaseConfirm = WaitForAddonVisible("SelectYesno", 3)
            if purchaseConfirm ~= nil and purchaseConfirm.Ready then
                Dalamud.Log("[Toolkit Helper] Confirming Dark Matter purchase")
                yield("/callback SelectYesno true 0")
                WaitForAddonClosed("SelectYesno", 3)
                yield("/wait 0.5")
            else
                Dalamud.Log("[Toolkit Helper] Dark Matter purchase confirmation did not appear yet; retrying")
            end
            return
        end
    end

    if Runtime.repairUseNpcFallback then
        Dalamud.Log("[Toolkit Helper] Self-repair failed; falling back to Limsa mender")
    elseif Settings.selfRepair and not Settings.autoBuyDarkMatter then
        Dalamud.Log(string.format("[Toolkit Helper] Insufficient Dark Matter (have=%d, need=%d) and auto-buy disabled; falling back to Limsa mender", darkMatterCount, requiredDarkMatter))
    end
    if not EnsureInLimsa("mender repair") then
        return
    end
    if not EnsureDismounted() then
        Dalamud.Log("[Toolkit Helper] Unable to dismount before mender interaction; retrying")
        return
    end
    InteractWithNpcAtPosition(ALISTAIR_POSITION, ALISTAIR_ROW_ID, "Alistair")
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

    if HasReachedPurchaseCycleLimit() then
        ResetExchangeState()
        ChangeState(CharacterState.idle)
        HandlePurchaseLimitReached()
        return
    end

    if ShouldProcessRetainersNow() then
        Dalamud.Log("[Toolkit Helper] Interrupting gemstone exchange for retainer processing")
        ResetExchangeState()
        ChangeState(CharacterState.processRetainers, "ProcessRetainers")
        return
    end

    if ShouldRepairNow() then
        Dalamud.Log("[Toolkit Helper] Interrupting gemstone exchange for repairs")
        ResetExchangeState()
        ChangeState(CharacterState.repairGear, "RepairGear")
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
            if ShouldUseReturnForSolutionNine(entry) then
                local returned = TryReturnToSolutionNine(entry.territoryId)
                if returned then
                    return
                else
                    Dalamud.Log("[Toolkit Helper] Return to Solution Nine failed; falling back to teleport")
                end
            end
            TeleportTo(entry.aetheryteTeleport)
        end
        return
    end

    if entry.miniAetheryteTeleport and not Runtime.usedMiniTeleport then
        TeleportTo(entry.miniAetheryteTeleport)
        Runtime.usedMiniTeleport = true
        return
    end

    local targetPosition = entry.position
    local stopDistance = 4.5
    if entry.vendorId == GADFRID_VENDOR_ID then
        targetPosition = GADFRID_POSITION
        stopDistance = 5.5
    end

    if not MoveNearPosition(targetPosition, stopDistance) then
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

    local count, limit, hitLimit = RegisterGemstonePurchaseCycle()
    local completionMessage = string.format("Completed gemstone exchange #%d for %s", count or 0, entry.localizedItemName)
    if hitLimit then
        FinishGemstoneExchange(
            completionMessage.." (purchase limit reached)",
            { suppressResume = true, skipReturnTeleport = true }
        )
        HandlePurchaseLimitReached()
        return
    end

    FinishGemstoneExchange(completionMessage)
end

--#endregion State Functions

--#region Main

EnsureTextAdvanceEnabled()

EnsureBossModPreferredState()

RefreshSettings()

LogFeatureFlagsOnce()

CharacterState = {
    idle = Idle,
    processRetainers = ProcessRetainers,
    maintainGemstones = MaintainGemstones,
    repairGear = RepairGear,
    exchangeGemstones = ExchangeGemstones
}

State = CharacterState.idle

Dalamud.Log("[Toolkit Helper] Starting toolkit helper loop")

yield("/vfate")

while not Runtime.stopScript do
    local allowRepairBusy = State == CharacterState.repairGear
    if not Svc.Condition[CharacterCondition.betweenAreas]
        and (allowRepairBusy or not Svc.Condition[CharacterCondition.occupiedMateriaExtractionAndRepair])
    then
        State()
    end
    UpdateStuckMonitor()
    yield("/wait 0.25")
end

--#endregion Main
