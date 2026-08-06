--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.0.0
description: Watch an inventory item while Fate Toolkit runs and stop at a configured quantity.
plugin_dependencies:
- AutoRetainer
- Lifestream
- vnavmesh
configs:
  Target item DataId:
    description: Item DataId to watch in the inventory.
    default: 0
    min: 0
    max: 999999
  Stop quantity:
    description: Stop when the inventory count reaches this quantity.
    default: 1
    min: 1
    max: 999999
  Enable stuck monitoring?:
    description: Apply Fate Toolkit stuck recovery while watching.
    default: false
  Follow-up script:
    description: SND script to run after the target quantity stops this watcher.
    default: ""
  Enable AutoRetainer multi-mode after target?:
    description: Enable AutoRetainer multi-mode after the target quantity stops this watcher.
    default: false
[[End Metadata]]
--]=====]

import("System.Numerics")

local CharacterCondition = {
    mounted = 4,
    inCombat = 26,
    casting = 27,
    occupiedInEvent = 31,
    occupiedInQuestEvent = 32,
    occupied = 33,
    occupiedSummoningBell = 50,
    betweenAreas = 45,
    occupiedMateriaExtractionAndRepair = 39,
    mounting57 = 57,
    mounting64 = 64,
    beingMoved = 70
}

local Settings = {
    itemDataId = 0,
    stopQuantity = 1,
    enableStuckMonitor = false,
    followUpScript = "",
    enableMultiMode = false
}

local Runtime = {
    stopping = false,
    stopIssued = false,
    thresholdDetected = false,
    lastLoggedCount = nil,
    deferredFollowUp = nil,
    deferredMultiMode = false,
    stuck = {
        lastPosition = nil,
        lastMovementTime = 0,
        lastRestartTime = 0,
        lastRecoveryType = nil,
        consecutiveTriggers = 0,
        lastTargetHp = nil
    }
}

local STUCK_THRESHOLD_SECONDS = 10
local STUCK_MOVE_TOLERANCE = 4.0
local STUCK_TELEPORT_COOLDOWN = 15
local MONITOR_STEP_SECONDS = 0.25
local INVENTORY_POLL_SECONDS = 1.0
local VFATE_RUN_COUNT = 1000

local function Trim(value)
    if type(value) ~= "string" then return value end
    return value:match("^%s*(.-)%s*$") or value
end

local function ReadSettings()
    local item = tonumber(Config.Get("Target item DataId"))
    local quantity = tonumber(Config.Get("Stop quantity"))
    Settings.itemDataId = math.max(0, math.floor(item or 0))
    Settings.stopQuantity = math.max(1, math.floor(quantity or 1))
    Settings.enableStuckMonitor = Config.Get("Enable stuck monitoring?") == true
    Settings.followUpScript = Trim(Config.Get("Follow-up script")) or ""
    if string.lower(Settings.followUpScript) == "none" then Settings.followUpScript = "" end
    Settings.enableMultiMode = Config.Get("Enable AutoRetainer multi-mode after target?") == true
end

local function Log(message)
    Dalamud.Log("[FATE Inventory Watcher] "..message)
end

local function StopVnav()
    if not IPC or not IPC.vnavmesh then return end
    local running = false
    if IPC.vnavmesh.PathfindInProgress then
        local ok, value = pcall(IPC.vnavmesh.PathfindInProgress)
        running = ok and value == true
    end
    if not running and IPC.vnavmesh.IsRunning then
        local ok, value = pcall(IPC.vnavmesh.IsRunning)
        running = ok and value == true
    end
    if running and IPC.vnavmesh.Stop then pcall(IPC.vnavmesh.Stop) end
end

local function Dismount()
    if not Svc or not Svc.Condition or not Svc.Condition[CharacterCondition.mounted] then return true end
    if Actions and Actions.ExecuteGeneralAction then
        local ok = pcall(function() Actions.ExecuteGeneralAction(23) end)
        if ok then
            local deadline = os.clock() + 5
            while Svc.Condition[CharacterCondition.mounted] and os.clock() < deadline do
                yield("/wait 0.25")
            end
            return not Svc.Condition[CharacterCondition.mounted]
        end
    end
    yield("/generalaction dismount")
    return true
end

local function IsInFate()
    local ok, fate = pcall(function() return Fates and Fates.CurrentFate end)
    if not ok or not fate then return false end
    local okInFate, value = pcall(function() return fate.InFate end)
    return okInFate and value == true
end

local function CopyPosition(position)
    if not position then return nil end
    return Vector3(position.X, position.Y, position.Z)
end

local function FlatDistance(a, b)
    if not a or not b then return math.huge end
    local dx, dz = a.X - b.X, a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

local function ClosestLocalAetheryte(position)
    if not Svc or not Svc.ClientState or not Svc.AetheryteList then return nil end
    if not Instances or not Instances.Telepo or not Instances.Telepo.GetAetherytePosition then return nil end
    local territory = Svc.ClientState.TerritoryType
    local closest, distance = nil, math.huge
    for _, aetheryte in ipairs(Svc.AetheryteList) do
        if tonumber(aetheryte.TerritoryId) == tonumber(territory) then
            local id = tonumber(aetheryte.AetheryteId)
            if id then
                local ok, aetherytePosition = pcall(Instances.Telepo.GetAetherytePosition, Instances.Telepo, id)
                if ok and aetherytePosition then
                    local candidateDistance = FlatDistance(position, aetherytePosition)
                    if candidateDistance < distance then
                        closest, distance = { id = id, distance = candidateDistance }, candidateDistance
                    end
                end
            end
        end
    end
    return closest
end

local function TeleportToClosestLocalAetheryte(position)
    local aetheryte = ClosestLocalAetheryte(position)
    if not aetheryte or aetheryte.distance <= 25 then return aetheryte ~= nil end
    if not IPC or not IPC.Lifestream or not IPC.Lifestream.Teleport then return false end
    local ok = pcall(function() IPC.Lifestream.Teleport(aetheryte.id, 0) end)
    if not ok then return false end
    local deadline = os.clock() + 30
    while IPC.Lifestream.IsBusy and IPC.Lifestream.IsBusy() and os.clock() < deadline do
        yield("/wait 0.25")
    end
    return true
end

local function RestartVfate()
    StopVnav()
    yield("/vfate stop")
    yield("/wait 2")
    yield(string.format("/vfate run %d", VFATE_RUN_COUNT))
end

local function UpdateStuckMonitor()
    if not Settings.enableStuckMonitor or Runtime.stopping then return end
    local monitor = Runtime.stuck
    local condition = Svc and Svc.Condition
    local position = Entity and Entity.Player and Entity.Player.Position
    if not condition or not position then
        monitor.lastPosition = nil
        monitor.lastMovementTime = os.clock()
        return
    end
    if condition[CharacterCondition.inCombat] then
        local target = Svc.Targets and Svc.Targets.Target
        local hp = target and target.CurrentHp
        if hp and monitor.lastTargetHp and hp < monitor.lastTargetHp and hp > 0 then
            monitor.lastPosition = CopyPosition(position)
            monitor.lastMovementTime = os.clock()
        end
        monitor.lastTargetHp = hp
        return
    end
    monitor.lastTargetHp = nil
    if condition[CharacterCondition.casting]
        or condition[CharacterCondition.mounting57]
        or condition[CharacterCondition.mounting64]
        or condition[CharacterCondition.betweenAreas]
        or condition[CharacterCondition.occupiedInEvent]
        or condition[CharacterCondition.occupiedInQuestEvent]
        or condition[CharacterCondition.occupied]
        or condition[CharacterCondition.beingMoved]
        or condition[CharacterCondition.occupiedSummoningBell]
        or condition[CharacterCondition.occupiedMateriaExtractionAndRepair]
    then
        monitor.lastPosition = CopyPosition(position)
        monitor.lastMovementTime = os.clock()
        return
    end
    if not monitor.lastPosition then
        monitor.lastPosition = CopyPosition(position)
        monitor.lastMovementTime = os.clock()
        return
    end
    if FlatDistance(position, monitor.lastPosition) >= STUCK_MOVE_TOLERANCE then
        monitor.lastPosition = CopyPosition(position)
        monitor.lastMovementTime = os.clock()
        monitor.consecutiveTriggers = 0
        monitor.lastRecoveryType = nil
        return
    end
    local now = os.clock()
    if now - monitor.lastMovementTime < STUCK_THRESHOLD_SECONDS then return end
    if condition[CharacterCondition.mounted] and IsInFate() then
        Log("Mounted in FATE for 10s; dismounting")
        Dismount()
        monitor.lastPosition = CopyPosition(position)
        monitor.lastMovementTime = now
        return
    end
    local cooldown = monitor.lastRecoveryType == "teleport" and STUCK_TELEPORT_COOLDOWN or 0
    if now - monitor.lastRestartTime < cooldown then return end
    monitor.lastRestartTime = now
    monitor.consecutiveTriggers = math.min(monitor.consecutiveTriggers + 1, 2)
    if monitor.consecutiveTriggers >= 2 then
        Log("Stuck trigger 2/2; teleporting to closest local aetheryte")
        StopVnav()
        yield("/vfate stop")
        if TeleportToClosestLocalAetheryte(position) then
            monitor.lastRecoveryType = "teleport"
            monitor.consecutiveTriggers = 0
        else
            monitor.lastRecoveryType = "restart"
            yield("/wait 2")
        end
        yield(string.format("/vfate run %d", VFATE_RUN_COUNT))
    else
        Log("Stuck trigger 1/2; restarting vfate")
        monitor.lastRecoveryType = "restart"
        RestartVfate()
    end
    monitor.lastPosition = CopyPosition(position)
    monitor.lastMovementTime = os.clock()
end

local function ItemCount()
    local ok, count = pcall(Inventory.GetItemCount, Settings.itemDataId)
    return ok and tonumber(count) or 0
end

local function StopForTarget(count)
    if Runtime.thresholdDetected then return end
    Runtime.thresholdDetected = true
    Runtime.stopping = true
    if Settings.followUpScript ~= "" then
        Runtime.deferredFollowUp = Settings.followUpScript
    elseif Settings.enableMultiMode then
        Runtime.deferredMultiMode = true
    end
    Log(string.format("Target reached: %d/%d; stopping vfate", count, Settings.stopQuantity))
end

local function RunFollowUpScript(scriptName)
    local sanitized = Trim(scriptName):gsub('"', '\\"')
    yield(string.format('/snd run "%s"', sanitized))
end

local function SetAutoRetainerMultiMode()
    if not IPC or not IPC.AutoRetainer or not IPC.AutoRetainer.SetMultiModeEnabled then return false end
    local ok = pcall(function() IPC.AutoRetainer.SetMultiModeEnabled(true) end)
    return ok
end

function OnStop()
    if not Runtime.stopIssued then
        Runtime.stopIssued = true
        yield("/vfate stop")
    end
    StopVnav()
    if IPC and IPC.Lifestream and IPC.Lifestream.Abort then
        pcall(function() IPC.Lifestream.Abort() end)
    end
    local followUp = Runtime.deferredFollowUp
    Runtime.deferredFollowUp = nil
    if Runtime.thresholdDetected and followUp and followUp ~= "" then
        RunFollowUpScript(followUp)
    elseif Runtime.thresholdDetected and Runtime.deferredMultiMode then
        SetAutoRetainerMultiMode()
    end
end

ReadSettings()
local initialCount = ItemCount()
Runtime.lastLoggedCount = initialCount
Log(string.format("Watching item %d: %d/%d", Settings.itemDataId, initialCount, Settings.stopQuantity))
yield(string.format("/vfate run %d", VFATE_RUN_COUNT))

local nextInventoryPoll = os.clock()
while not Runtime.stopping do
    local now = os.clock()
    if now >= nextInventoryPoll then
        local count = ItemCount()
        if count > (Runtime.lastLoggedCount or 0) then
            Log(string.format("Item %d quantity updated: %d/%d", Settings.itemDataId, count, Settings.stopQuantity))
        end
        Runtime.lastLoggedCount = count
        if count >= Settings.stopQuantity then
            StopForTarget(count)
            break
        end
        nextInventoryPoll = now + INVENTORY_POLL_SECONDS
    end
    UpdateStuckMonitor()
    yield(string.format("/wait %.2f", MONITOR_STEP_SECONDS))
end
