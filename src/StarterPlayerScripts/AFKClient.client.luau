-- AFKClient: after a minute with no input (or when the Roblox window loses focus), tells the server
-- you're AFK so an "AFK zzz" tag shows over your head. Any input clears it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local SetAFK = ReplicatedStorage:WaitForChild("LobbyEvents"):WaitForChild("SetAFK")
local IDLE_SECONDS = 60

local lastInput = os.clock()
local afk = false
local function set(on: boolean)
	if on == afk then return end
	afk = on
	SetAFK:FireServer(on)
end
UserInputService.InputBegan:Connect(function() lastInput = os.clock(); set(false) end)
UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		lastInput = os.clock(); set(false)
	end
end)
UserInputService.WindowFocusReleased:Connect(function() set(true) end)
UserInputService.WindowFocused:Connect(function() lastInput = os.clock(); set(false) end)
Players.LocalPlayer.CharacterAdded:Connect(function() afk = false end)
while true do
	task.wait(2)
	if os.clock() - lastInput > IDLE_SECONDS then set(true) end
end
