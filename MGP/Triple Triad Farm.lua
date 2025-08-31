--[=====[
[[SND Metadata]]
author: baanderson40
version: 1.0.2
description: | 
  Support via https://ko-fi.com/baanderson40
  Farm MGP by playing Triple Triad NPCs and Saucy.
plugin_dependencies:
- Saucy
- vnavmesh
configs:
  Klynthota:
    description: Number of games to play. Set to 0 to skip NPC.
    default: 125
    min: 0
    max: 1000
  Vorsaile Heuloix:
    description: Number of games to play. Set to 0 to skip NPC.
    default: 125
    min: 0
    max: 1000
  Hanagasa:
    description: Number of games to play. Set to 0 to skip NPC.
    default: 125
    min: 0
    max: 1000
[[End Metadata]]
--]=====]

--[[
********************************************************************************
*                                  Changelog                                   *
********************************************************************************
    -> 1.0.2 Updated meta data config settings
    -> 1.0.1 Added Gold Saucer VIP Card support
    -> 1.0.0 Initial Release

]]

--#region Data
-- Imports Vector3 and related math utilities for position handling
import("System.Numerics")

-- Maps character condition flags used by Svc.Condition[] to readable keys
CharacterCondition = {
    normalConditions = 1,
    mounted = 4,
    playingMinigame = 13,
    casting = 27,
    betweenAreas = 45,
    flying=77
}

--[[
    List of Triple Triad NPCs to farm.
    Each entry includes:
      - npcName: Name of the NPC to interact with
      - npcPosition: World coordinates for movement
      - npcGames: Number of games to play (from config)
      - aetheryteId: Aetheryte used to teleport to the zone
      - territoryId: Zone identifier
      - zoneFly: Whether flying is allowed (used to determine mount usage)
]]
TripleTriadNpc = {
    {
        npcName = "Klynthota",
        npcPosition = Vector3(451.611,-11.830,-384.520),
        npcGames = Config.Get("Klynthota"),
        aetheryteId = 24,
        territoryId = 156,
        zoneFly = true,
    },
    {
        npcName = "Vorsaile Heuloix",
        npcPosition = Vector3(-72.803,-0.502,-3.159),
        npcGames = Config.Get("Vorsaile Heuloix"),
        aetheryteId = 2,
        territoryId = 132,
        zoneFly = false,
    },
    {
        npcName = "Hanagasa",
        npcPosition = Vector3(-37.760,15.000,34.752),
        npcGames = Config.Get("Hanagasa"),
        aetheryteId = 111,
        territoryId = 628,
        zoneFly = false,
    },
}
--#regionend Data


--#region Global State Variables

-- State control variables used to track script status and progression
State = nil
StopFlag = false
CurrentNpc = nil
NpcCount = 0
CurrentNpcDone = false
TriadRequested = false
GoldSaucerVipCard = 14947
--#endregion Global State Variables


--#region Utility Functions

-- Pauses execution using in-game wait command
local function Sleep(seconds)
    yield('/wait ' .. tostring(seconds))
end

-- Returns true if the SelectIconString menu is open and ready
local function IsSelectIconOpen()
    local a = Addons.GetAddon("SelectIconString")
    return a and a.Ready
end

-- Returns true if the Triple Triad request dialog is visible
local function IsTripleTriadRequestOpen()
    local a = Addons.GetAddon("TripleTriadRequest")
    return a and a.Ready
end

-- Generic helper to check readiness of any named addon
local function IsAddonReady(name)
    local a = Addons.GetAddon(name)
    return a and a.Ready
end

-- Checks if any Triple Triad window is currently open
local function IsTripleTriadOpen()
    return IsAddonReady("TripleTriadRequest")
        or IsAddonReady("TripleTriadSelDeck")
        or IsAddonReady("TripleTriad")
        or IsAddonReady("TripleTriadResult")
end

-- Handles mounting and dismounting using action commands
function Mount()
    Dalamud.Log("[TT Farm] Mount()")
    Engines.Run('/gaction "mount roulette"')
end

function Dismount()
    Dalamud.Log("[TT Farm] Dismount()")
    if not (Svc.Condition[CharacterCondition.mounted] or Svc.Condition[CharacterCondition.flying]) then
        Dalamud.Log("[TT Farm] Dismount(): skip, not mounted or flying")
        return
    end
    Engines.Run('/ac dismount')
end

-- Returns distance from player to a target Vector3
-- Returns math.huge if no position or local player is found
function GetDistanceToPoint(vec3)
    local lp = Svc.ClientState.LocalPlayer
    if not lp or not vec3 then
        Dalamud.Log("[TT Farm] GetDistanceToPoint(): missing LocalPlayer or target; returning inf")
        return math.huge
    end
    return Vector3.Distance(lp.Position, vec3)
end

-- Checks if under Gold Saucer VIP Card Status
function PlayerStatusCheck()
    local targetId = 1079  -- change this to the statusId you’re looking for
    local found = false

    local list = Player.Status
    if not list or not list.Count or list.Count == 0 then
        return false
    end

    for i = 0, list.Count - 1 do  -- zero-based index
        local s = list[i] or list:get_Item(i)
        if s and s.StatusId == targetId then
            found = true
            break
        end
    end
    return found
end

-- User Gold Saucer VIP Card
function UseVIPCard()
    Engines.Run("/item Gold Saucer VIP Card")
end
--#endregion Utility Functions


--#region NPC Selection Logic
--[[
    Iterates through the configured NPCs in order.
    Sets the first eligible NPC as the current target and prepares state.
    If no NPCs meet the criteria, sets StopFlag to stop the loop.
]]
function NextNpc()
    Dalamud.Log("[TT Farm] NextNpc(): start")
    local total = #TripleTriadNpc
    for _ = 1, total do
        NpcCount = (NpcCount % total) + 1
        local candidate = TripleTriadNpc[NpcCount]
        Dalamud.Log("[TT Farm] NextNpc(): evaluating " .. tostring(candidate.npcName) ..
                 " with games=" .. tostring(candidate.npcGames))
        if candidate and candidate.npcGames and candidate.npcGames > 0 then
            CurrentNpc = candidate
            CurrentNpcDone = false
            TriadRequested = false
            Dalamud.Log("[TT Farm] Next NPC: " .. candidate.npcName .. " (" .. tostring(candidate.npcGames) .. " games)")
            State = CharacterState.ready
            return State
        end
        Dalamud.Log("[TT Farm] NextNpc(): skipping " .. candidate.npcName .. " (0 games)")
    end

    -- falls through only if all NPCs were disabled
    Dalamud.Log("[TT Farm] All NPCs disabled (0 games). Stopping.")
    StopFlag = true
    State = CharacterState.ready
    return State
end
--#endregion NPC Selection Logic


--#region Navigation and Movement
--[[
    Teleports to the NPC’s zone using the given Aetheryte ID.
    Waits for both the cast and zone transition to complete.
    Updates state to 'ready' when teleport is finished.
]]
function TeleportTo(aetheryteId)
    Actions.Teleport(aetheryteId)
    Dalamud.Log("[TT Farm] TeleportTo(): aetheryteId=" .. tostring(aetheryteId))
    Sleep(.5)
    Dalamud.Log("[TT Farm] Casting teleport...")
    while Svc.Condition[CharacterCondition.casting] do
        Sleep(.25)
    end
    Sleep(.5)
    Dalamud.Log("[TT Farm] Teleporting...")
    while Svc.Condition[CharacterCondition.betweenAreas] do
        Sleep(.25)
    end
    Dalamud.Log("[TT Farm] TeleportTo(): zone load complete, territory=" .. tostring(Svc.ClientState.TerritoryType))
    Dalamud.Log("[TT Farm] State Change: Ready")
    State = CharacterState.ready
    return State
end

--[[
    Moves to the NPC's world position using vnavmesh.
    Mounts if flying is allowed and not already mounted.
    Handles zone transition wait, dismount logic, and state cleanup after movement.
]]
function MoveToNpcPosition(position, fly)
    Dalamud.Log(string.format("[TT Farm] MoveToNpcPosition(): target=(%.3f, %.3f, %.3f), fly=%s",
    position.X, position.Y, position.Z, tostring(fly)))
    while Svc.Condition[CharacterCondition.betweenAreas] do Sleep(0.25) end
    Dalamud.Log("[TT Farm] MoveToNpcPosition(): waiting for vnavmesh readiness")
    while not IPC.vnavmesh.IsReady() do Sleep(0.25) end
    Dalamud.Log("[TT Farm] MoveToNpcPosition(): vnavmesh ready")
    if fly and not Svc.Condition[CharacterCondition.mounted] then
        Dalamud.Log("[TT Farm] MoveToNpcPosition(): Mount")
        Mount()
        Sleep(1.25)
        if not Svc.Condition[CharacterCondition.mounted] then
            return
        end
        Dalamud.Log("[TT Farm] MoveToNpcPosition(): mount status=" .. tostring(Svc.Condition[CharacterCondition.mounted]))
    elseif not fly then
        Dalamud.Log("[TT Farm] MoveToNpcPosition(): Sprint")
        Engines.Run("/gaction Sprint")
    end
    Dalamud.Log("[TT Farm] MoveToNpcPosition(): starting pathfind and move")
    IPC.vnavmesh.PathfindAndMoveTo(position, fly)
    Dalamud.Log("[TT Farm] Moving to NPC position")
    Sleep(2)
    while (IPC.vnavmesh.IsReady() and IPC.vnavmesh.IsRunning()) do Sleep(.25) end
    Dalamud.Log("[TT Farm] MoveToNpcPosition(): path complete")
    if Svc.Condition[CharacterCondition.flying] then
        Dalamud.Log("[TT Farm] MoveToNpcPosition(): dismounting (flying)")
            Dismount()
    elseif Svc.Condition[CharacterCondition.mounted] then
        Dalamud.Log("[TT Farm] MoveToNpcPosition(): dismounting (mounted)")
        Dismount()
    end
    Dalamud.Log("[FATE] State Change: Ready")
    State = CharacterState.ready
    return State
end
--#endregion Navigation and Movement


--#region Targeting and Interaction
-- Targets the NPC entity by name and sets it as current target
function TargetNpc(npcname)
    Dalamud.Log("[TT Farm] At npc and targeting")
    local e = Entity.GetEntityByName(npcname)
    if e then
        e:SetAsTarget()
        Dalamud.Log("[TT Farm] TargetNpc(): target set -> " .. npcname)
    else
        Dalamud.Log("[TT Farm] NPC not found yet: " .. tostring(npcname))
    end
    State = CharacterState.ready
    return State
end

-- Interacts with the current target if it's the expected NPC and the Triple Triad UI isn't already open
function TargetInteract()
    Dalamud.Log("[TT Farm] TargetInteract(): checking conditions")
    if Entity.Target and Entity.Target.Name == CurrentNpc.npcName and not IsTripleTriadOpen() then
        Dalamud.Log("[TT Farm] TargetInteract(): interacting with " .. Entity.Target.Name)
        Entity.Target:Interact()
        State = CharacterState.ready
        return State
    end
end
--#endregion Targeting and Interaction


--#region Game Interaction

-- Handles the SelectIconString menu by issuing a callback to start the Triple Triad request
function HandleSelectIconMenu()
    local addon = Addons.GetAddon("SelectIconString")
    if addon and addon.Ready then
        Dalamud.Log("[TT Farm] HandleSelectIconMenu(): sending SelectIconString callback")
        Engines.Run("/callback SelectIconString true 0")
    end
    State = CharacterState.ready
    return State
end

-- Starts the Triple Triad match via Saucy commands if the request window is open and match hasn't already been triggered
function StartTripleTriadMatch()
    Dalamud.Log("[TT Farm] StartTripleTriadMatch(): entered")
    local req = Addons.GetAddon("TripleTriadRequest")
    if req and req.Ready then
        Dalamud.Log("[TT Farm] StartTripleTriadMatch(): request window ready")
        if not TriadRequested then
            TriadRequested = true
            Dalamud.Log("[TT Farm] StartTripleTriadMatch(): queuing " .. tostring(CurrentNpc.npcGames) ..
            " games vs " .. tostring(CurrentNpc.npcName))
            yield("/saucy tt play " .. tostring(CurrentNpc.npcGames))
            Sleep(0.25)
            yield("/saucy tt go")
            Sleep(2)
            Dalamud.Log("[TT Farm] StartTripleTriadMatch(): go command sent; switching to waitForGames")
            State = CharacterState.waitForGames
            return State
        end
    end
    State = CharacterState.ready
    return State
end

--[[ Waits for all games to complete by monitoring UI windows and condition state
     Sets current NPC as done once match finishes
]]
function WaitForGames()
    Dalamud.Log("[TT Farm] WaitForGames(): waiting for TT windows to close")
    while IsTripleTriadOpen() do
        Sleep(1)
    end
    Sleep(.25)
    Dalamud.Log("[TT Farm] WaitForGames(): TT windows closed; checking conditions")
    if Svc.Condition[CharacterCondition.normalConditions] or not Svc.Condition[CharacterCondition.playingMinigame] then
        Dalamud.Log("[TT Farm] WaitForGames(): match finished; marking NPC done")
        CurrentNpcDone = true
        State = CharacterState.ready
        return State
    end
end
--#endregion Game Interaction


--#region State Machine - Main Decision Logic
--[[
    Main control function that determines the next action based on player state and NPC context.
    Prioritizes NPC selection, interaction, movement, and match initiation in a stepwise manner.
]]
function Ready()
    -- 1) No NPC selected yet or finished current one: get next
    if NpcCount == 0 or CurrentNpc == nil then
        Dalamud.Log("[TT Farm] Ready(): selecting next NPC")
        return CharacterState.nextnpc()

    -- 2) Finished playing games with current NPC
    elseif CurrentNpcDone and not IsTripleTriadOpen() then
        Dalamud.Log("[TT Farm] Ready(): current NPC complete -> next")
        return CharacterState.nextnpc()

    -- 3) Ready to start Triple Triad match
    elseif IsTripleTriadRequestOpen() and not CurrentNpcDone then
        Dalamud.Log("[TT Farm] Ready(): starting Triple Triad")
        return CharacterState.starttripletriad()

    -- 4) Challenge menu is open, confirm it
    elseif IsSelectIconOpen() then
        Dalamud.Log("[TT Farm] Ready(): handling select icon menu")
        return CharacterState.handlemenu()

    -- 5) NPC is already targeted, initiate interaction
    elseif Entity.Target and Entity.Target.Name == CurrentNpc.npcName then
        Dalamud.Log("[TT Farm] Ready(): interacting with targeted NPC")
        return CharacterState.targetinteract()

    -- 6) NPC is found and close enough, target it
    elseif Entity.GetEntityByName(CurrentNpc.npcName)
       and Entity.GetEntityByName(CurrentNpc.npcName).DistanceTo <= 10 then
        Dalamud.Log("[TT Farm] Ready(): targeting nearby NPC")
        return CharacterState.targetnpc(CurrentNpc.npcName)

    -- 7) Use Gold Saucer VIP card if available.
    elseif not PlayerStatusCheck() and Inventory.GetItemCount(GoldSaucerVipCard) > 0 then
        UseVIPCard()
        Sleep(5)
        return

    -- 8) In the correct zone but not near NPC, move toward them
    elseif Svc.ClientState.TerritoryType == CurrentNpc.territoryId
       and GetDistanceToPoint(CurrentNpc.npcPosition) > 10 then
        Dalamud.Log("[TT Farm] Ready(): moving toward NPC")
        return CharacterState.movetonpcpos(CurrentNpc.npcPosition, CurrentNpc.zoneFly)

    -- 9) In wrong zone entirely, teleport
    elseif Svc.ClientState.TerritoryType ~= CurrentNpc.territoryId then
        Dalamud.Log("[TT Farm] Ready(): teleporting to NPC zone")
        return CharacterState.teleportto(CurrentNpc.aetheryteId)
    end

    return CharacterState.ready
end

-- Maps state names to their corresponding handler functions
CharacterState = {
    handlemenu = HandleSelectIconMenu,
    movetonpcpos = MoveToNpcPosition,
    nextnpc = NextNpc,
    ready = Ready,
    starttripletriad = StartTripleTriadMatch,
    targetinteract = TargetInteract,
    targetnpc = TargetNpc,
    teleportto = TeleportTo,
    waitForGames = WaitForGames,
}
--#endregion State Machine - Main Decision Logic


--#region Main Loop

--[[
    Main script loop.
    Continues running the current State function until StopFlag is set.
    Skips execution while teleporting, zoning, or if Lifestream is busy.
]]
State = CharacterState.ready
Dalamud.Log("[TT Farm] Starting Triple Triad Farm script.")
Engines.Run("/echo [TT Farm] Starting Triple Triad Farm script.")
while not StopFlag do
    if not (
        Svc.Condition[CharacterCondition.casting] or
        Svc.Condition[CharacterCondition.betweenAreas] or
        IPC.Lifestream.IsBusy())
    then
        State()
    end
    Sleep(.25)
end

--#endregion Main Loop
