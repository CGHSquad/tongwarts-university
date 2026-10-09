local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local PortalMessage = ReplicatedStorage:WaitForChild("LobbyEvents"):WaitForChild("PortalMessage")

local gui = Instance.new("ScreenGui"); gui.Name = "PortalToast"; gui.ResetOnSpawn = false; gui.DisplayOrder = 40
local frame = Instance.new("Frame"); frame.AnchorPoint = Vector2.new(0.5, 0); frame.Position = UDim2.new(0.5, 0, 0, -200); frame.Visible = false
frame.Size = UDim2.fromOffset(420, 86); frame.BackgroundColor3 = Color3.fromRGB(22, 20, 34); frame.BackgroundTransparency = 0.1; frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 14)
local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(220, 180, 105); stroke.Thickness = 2; stroke.Parent = frame
local title = Instance.new("TextLabel"); title.BackgroundTransparency = 1; title.Size = UDim2.new(1, -24, 0, 40); title.Position = UDim2.fromOffset(12, 6)
title.Font = Enum.Font.FredokaOne; title.TextScaled = true; title.TextColor3 = Color3.fromRGB(255, 240, 200); title.Text = ""; title.Parent = frame
local sub = Instance.new("TextLabel"); sub.BackgroundTransparency = 1; sub.Size = UDim2.new(1, -24, 0, 28); sub.Position = UDim2.fromOffset(12, 48)
sub.Font = Enum.Font.GothamMedium; sub.TextScaled = true; sub.TextColor3 = Color3.fromRGB(150, 240, 220); sub.Text = ""; sub.Parent = frame
gui.Parent = player:WaitForChild("PlayerGui")

local token = 0
PortalMessage.OnClientEvent:Connect(function(name, msg)
	token += 1; local my = token
	title.Text = string.upper(name); sub.Text = msg
	frame.Visible = true
	TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Back), {Position = UDim2.new(0.5, 0, 0, 24)}):Play()
	task.delay(2.6, function()
		if my == token then
			local out = TweenService:Create(frame, TweenInfo.new(0.3), {Position = UDim2.new(0.5, 0, 0, -200)})
			out.Completed:Connect(function() if my == token then frame.Visible = false end end)
			out:Play()
		end
	end)
end)
