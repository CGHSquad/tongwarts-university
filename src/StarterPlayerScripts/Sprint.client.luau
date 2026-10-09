-- Sprint: hold Shift (or the on-screen Sprint button on mobile) to run faster.
-- Leaves the speed alone while something else has the player stopped (WalkSpeed 0, e.g. during a fight).
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local WALK_SPEED = 16
local SPRINT_SPEED = 26
local SPRINT_FOV_BOOST = 8

local player = Players.LocalPlayer
local sprinting = false
local baseFov: number? = nil

local function humanoid(): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

-- extra speed from a food buff (the server sets the player's "SpeedBonus" attribute)
local function bonus(): number
	return player:GetAttribute("SpeedBonus") or 0
end
local function wanted(): number
	return (if sprinting then SPRINT_SPEED else WALK_SPEED) + bonus()
end

local function setSprint(on: boolean)
	sprinting = on
	local hum = humanoid()
	if hum and hum.WalkSpeed > 0 then
		hum.WalkSpeed = wanted()
	end
	local cam = workspace.CurrentCamera
	if cam then
		baseFov = baseFov or cam.FieldOfView
		TweenService:Create(cam, TweenInfo.new(0.25), {FieldOfView = (baseFov :: number) + (if on then SPRINT_FOV_BOOST else 0)}):Play()
	end
end

-- Keyboard / gamepad: watched directly, so nothing else bound to Shift can swallow it.
local SPRINT_KEYS = { [Enum.KeyCode.LeftShift] = true, [Enum.KeyCode.RightShift] = true, [Enum.KeyCode.ButtonL3] = true }
UserInputService.InputBegan:Connect(function(input, typing)
	if SPRINT_KEYS[input.KeyCode] and not typing then setSprint(true) end
end)
UserInputService.InputEnded:Connect(function(input)
	if SPRINT_KEYS[input.KeyCode] then setSprint(false) end
end)

-- Touch: an on-screen hold button.
if UserInputService.TouchEnabled then
	ContextActionService:BindAction("Sprint", function(_, state)
		if state == Enum.UserInputState.Begin then
			setSprint(true)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			setSprint(false)
		end
		return Enum.ContextActionResult.Pass
	end, true)
	ContextActionService:SetTitle("Sprint", "Sprint")
	ContextActionService:SetPosition("Sprint", UDim2.new(1, -170, 1, -150))
end

-- if a fight freezes you mid-sprint, you come back walking
local function onCharacter(char: Model)
	sprinting = false
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		-- something reset us to a plain walk/sprint speed (e.g. after a fight): put the right one back
		if hum.WalkSpeed > 0 and hum.WalkSpeed ~= wanted() and (hum.WalkSpeed == WALK_SPEED or hum.WalkSpeed == SPRINT_SPEED) then
			hum.WalkSpeed = wanted()
		end
	end)
	if hum.WalkSpeed > 0 then hum.WalkSpeed = wanted() end
end
player:GetAttributeChangedSignal("SpeedBonus"):Connect(function()
	local hum = humanoid()
	if hum and hum.WalkSpeed > 0 then hum.WalkSpeed = wanted() end
end)
if player.Character then task.spawn(onCharacter, player.Character) end
player.CharacterAdded:Connect(onCharacter)
