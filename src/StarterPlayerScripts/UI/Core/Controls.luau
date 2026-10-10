--!strict
--[[
	Controls — the touch movement controls during a fight (M0 report R21). In combat the server
	freezes the character, but Roblox's thumbstick and jump button, and the Sprint button
	(Sprint.client), would stay on screen over the HUD's bottom corners. This turns them off while
	the local player is in a battle and back on when they're not, keyed off every snapshot rather
	than the battle's happy path (BattleClient), and re-applies the same state to a fresh character
	(a reset mid-fight, the respawn after a loss). Client-only: nothing the server decides changes.
	Every Roblox call is guarded, so where the PlayerModule doesn't exist (the tests' fake Roblox)
	it only keeps track of the state.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Controls = {}

local enabled = true
local modalBefore: boolean? = nil -- UserInputService.ModalEnabled before a fight switched it on
local changes = 0
local listeners: { [number]: (boolean) -> () } = {}
local nextListener = 0

-- Roblox's ControlModule, from the PlayerModule it puts in PlayerScripts.
local function playerControls(): any?
	local ok, controls = pcall(function()
		local player = Players.LocalPlayer :: any
		local scripts = player:WaitForChild("PlayerScripts", 1)
		local module = scripts:WaitForChild("PlayerModule", 1)
		return (require :: any)(module):GetControls()
	end)
	return if ok then controls else nil
end

local function apply()
	local controls = playerControls()
	if controls then
		pcall(function()
			if enabled then
				controls:Enable()
			else
				controls:Disable()
			end
		end)
	end
	-- The Sprint button only exists on touch devices (Sprint.client); asking for it elsewhere logs a
	-- warning, so don't.
	pcall(function()
		if not UserInputService.TouchEnabled then
			return
		end
		local button = ContextActionService:GetButton("Sprint")
		if button then
			button.Visible = enabled
		end
	end)
	-- Belt and braces for the thumbstick and jump button: Roblox hides them for a modal UI, and
	-- their own ScreenGui (TouchGui) can be switched off outright, which the ControlModule's
	-- Disable doesn't always do (Studio's device emulator kept them on screen). ModalEnabled is a
	-- global flag, so whatever it was before the fight is put back after.
	pcall(function()
		if enabled then
			if modalBefore ~= nil then
				UserInputService.ModalEnabled = modalBefore
				modalBefore = nil
			end
		elseif modalBefore == nil then
			modalBefore = UserInputService.ModalEnabled
			UserInputService.ModalEnabled = true
		end
	end)
	pcall(function()
		local player = Players.LocalPlayer
		local playerGui = if player then player:FindFirstChildOfClass("PlayerGui") else nil
		local touchGui = if playerGui then playerGui:FindFirstChild("TouchGui") else nil
		if touchGui and touchGui:IsA("ScreenGui") then
			touchGui.Enabled = enabled
		end
	end)
end

function Controls.setEnabled(on: boolean)
	if on == enabled then
		return
	end
	enabled = on
	changes += 1
	apply()
	for _, listener in listeners do
		listener(on)
	end
end

-- Puts the current state back, for a character that was just (re)spawned.
function Controls.reapply()
	apply()
end

function Controls.isEnabled(): boolean
	return enabled
end

-- How many times the state has flipped (for the tests).
function Controls.changes(): number
	return changes
end

function Controls.onChanged(listener: (boolean) -> ()): () -> ()
	nextListener += 1
	local id = nextListener
	listeners[id] = listener
	return function()
		listeners[id] = nil
	end
end

return Controls
