--!strict
--[[
	Input — which kind of input the player is using, and the key hints that go with it (handoff
	rule 3 and section 10). Touch, mouse, keyboard and gamepad are all supported; key hints like
	[Q] only show when a keyboard is the active input and there's no touch screen. Never a
	controller glyph.
]]

local UserInputService = game:GetService("UserInputService")

export type Mode = "Touch" | "Mouse" | "Keyboard" | "Gamepad"

local Input = {}

local mode: Mode = "Mouse"
local listeners: { [number]: (Mode) -> () } = {}
local nextListener = 0

-- Keys for the combat commands when a keyboard is in use (handoff section 10: 1 to 5).
local KEY_HINTS: { [string]: string } = {
	Attack = "1",
	Spell = "2",
	Item = "3",
	Guard = "4",
	Pass = "5",
	Confirm = "Enter",
	Back = "Esc",
}

local function fromInputType(inputType: Enum.UserInputType): Mode?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif inputType == Enum.UserInputType.Keyboard then
		return "Keyboard"
	elseif inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.MouseMovement or inputType == Enum.UserInputType.MouseWheel then
		return "Mouse"
	elseif string.find(inputType.Name, "Gamepad", 1, true) then
		return "Gamepad"
	end
	return nil
end

local function setMode(newMode: Mode)
	if newMode == mode then
		return
	end
	mode = newMode
	for _, listener in listeners do
		listener(mode)
	end
end

-- The starting guess, before any input arrives.
do
	local ok, touch = pcall(function()
		return UserInputService.TouchEnabled
	end)
	if ok and touch then
		mode = "Touch"
	else
		local okGamepad, gamepad = pcall(function()
			return UserInputService.GamepadEnabled
		end)
		if okGamepad and gamepad then
			mode = "Gamepad"
		else
			mode = "Mouse"
		end
	end
	pcall(function()
		UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
			local detected = fromInputType(inputType)
			if detected then
				setMode(detected :: Mode)
			end
		end)
	end)
end

function Input.mode(): Mode
	return mode
end

-- Key hints show only for keyboard players on a screen without touch.
function Input.showKeyHints(): boolean
	local touch = false
	pcall(function()
		touch = UserInputService.TouchEnabled
	end)
	return mode == "Keyboard" and not touch
end

-- "[1]" for Attack while key hints are shown, otherwise nil.
function Input.keyHint(command: string): string?
	if not Input.showKeyHints() then
		return nil
	end
	local key = KEY_HINTS[command]
	return if key then `[{key}]` else nil
end

function Input.keyFor(command: string): string?
	return KEY_HINTS[command]
end

-- Calls `listener` whenever the mode changes. Returns a function that stops the calls.
function Input.onChanged(listener: (Mode) -> ()): () -> ()
	nextListener += 1
	local id = nextListener
	listeners[id] = listener
	return function()
		listeners[id] = nil
	end
end

-- For the harness and tests: force a mode.
function Input.override(newMode: Mode)
	setMode(newMode)
end

return Input
