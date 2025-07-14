--[=====[
[[SND Metadata]]
author: Baanderson40
version: 0.0.2
description: Restart pot0to Fate Farming Script

configs:
    Fate Farming Script Name:
        default: Fate Farming - pot0to
        description: The name for your fate farming script.
        type: string
        required: true
    Wait Interval:
        default: 30
        description: Number of seconds between checks. 
        type: number
        required: true
    Max Cycle Count:
        default: 2
        description: How many times to count before determing script is stuck. Wait * Cycle = Max Wait Time
        type: number
        required: true
    Display Debug in chat:
        default: false
        description: False - Debug in XLLog only. | True - Debug in game chat via echo.
        type: boolean
        required: true

[[End Metadata]]
--]=====]

-- Imports
import("System.Numerics")
loadfiyel = os.getenv("appdata").."\\XIVLauncher\\pluginConfigs\\SomethingNeedDoing\\_functions.lua"
functionsToLoad = loadfile(loadfiyel)
functionsToLoad()

--Config variables
local Fate_Script = Config.Get("Fate Farming Script Name")
local Wait_Interval = Config.Get("Wait Interval")
local Max_Cycle_Count = Config.Get("Max Cycle Count")
local Display_Debug = Config.Get("Display Debug")
local Cycle_Counter = 0


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

-- Helper Functions
local function Sleep(seconds)
    yield('/wait ' .. tostring(seconds))
end

function CharacterState.restartFateScript()
	-- Stop Fate Farming script to restart it
	Dalamud.LogDebug("[Unstick - Fate] - turning off " .. tostring(Fate_Script))
	if Display_Debug == true then 
		yield("/echo [Unstick - Fate] - turning off " .. tostring(Fate_Script))
	end
	yield("/snd stop " .. tostring(Fate_Script))
	Sleep(2)
	Dalamud.LogDebug("[Unstick - Fate] - turning on " .. tostring(Fate_Script))
	if Display_Debug == true then
		yield("/echo [Unstick - Fate] - turning on " .. tostring(Fate_Script))
	end
	yield("/snd run " .. tostring(Fate_Script))
	Cycle_Counter = 0
end

-- Startup

-- Main loop
while true do
	while Svc.Condition[CharacterCondition.betweenAreas] do
        Sleep(1)
    end
	x1 = EntityPlayerPositionX()
	y1 = EntityPlayerPositionY()
	z1 = EntityPlayerPositionZ()
	Sleep(Wait_Interval)
	if Svc.Condition[26] == false then
		if math.abs(x1 - EntityPlayerPositionX()) < 3 and math.abs(y1 - EntityPlayerPositionY()) < 3 and math.abs(z1 - EntityPlayerPositionZ()) < 3 then
			Cycle_Counter = Cycle_Counter + 1
			Dalamud.LogDebug("[Unstick - Fate] We havent moved very much something is up -> "..Cycle_Counter.."/"..Max_Cycle_Count.." cycles till restart!")
			if Display_Debug == true then
				yield("/echo [Unstick - Fate] We havent moved very much something is up -> "..Cycle_Counter.."/"..Max_Cycle_Count.." cycles till restart!")
			end
		else
			Cycle_Counter = 0
		end
		if Cycle_Counter >= Max_Cycle_Count then
			CharacterState.restartFateScript()
		end
	
	else
		Cycle_Counter = 0
	end
	Dalamud.LogDebug("[Unstick - Fate] - Status Checked - Cycle Count: " .. tostring(Cycle_Counter))
	if Display_Debug == true then
		yield("/echo [Unstick - Fate] - Status Checked - Cycle Count: " .. tostring(Cycle_Counter))
	end
end
