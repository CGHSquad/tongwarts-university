-- LoadingScreen: covers the screen while the lobby streams in, so players never see the empty dark
-- cave, then fades away once they're standing in it. Runs first (ReplicatedFirst).
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local MAX_WAIT = 20 -- seconds; never trap someone on the loading screen

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"; gui.IgnoreGuiInset = true; gui.ResetOnSpawn = false; gui.DisplayOrder = 100
local bg = Instance.new("Frame")
bg.Size = UDim2.fromScale(1, 1); bg.BorderSizePixel = 0; bg.BackgroundColor3 = Color3.fromRGB(14, 16, 30); bg.Parent = gui
local grad = Instance.new("UIGradient"); grad.Rotation = 90
grad.Color = ColorSequence.new(Color3.fromRGB(30, 36, 70), Color3.fromRGB(10, 12, 22)); grad.Parent = bg
local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0.5); title.Position = UDim2.fromScale(0.5, 0.45); title.Size = UDim2.fromScale(0.7, 0.12)
title.BackgroundTransparency = 1; title.Font = Enum.Font.FredokaOne; title.TextScaled = true
title.Text = "Midnight Mushroom"; title.TextColor3 = Color3.fromRGB(255, 240, 200); title.Parent = bg
local sub = Instance.new("TextLabel")
sub.AnchorPoint = Vector2.new(0.5, 0.5); sub.Position = UDim2.fromScale(0.5, 0.56); sub.Size = UDim2.fromScale(0.5, 0.045)
sub.BackgroundTransparency = 1; sub.Font = Enum.Font.GothamMedium; sub.TextScaled = true
sub.Text = "Entering the lobby"; sub.TextColor3 = Color3.fromRGB(150, 240, 220); sub.Parent = bg
gui.Parent = player:WaitForChild("PlayerGui")
ReplicatedFirst:RemoveDefaultLoadingScreen()

local dots = 0
local running = true
task.spawn(function()
	while running do
		dots = dots % 3 + 1
		sub.Text = "Entering the lobby" .. string.rep(".", dots)
		task.wait(0.4)
	end
end)

local start = os.clock()
local function timedOut() return os.clock() - start > MAX_WAIT end

if not game:IsLoaded() then game.Loaded:Wait() end
-- the lobby (streams in as one piece) and our character standing in it
local lobby = workspace:WaitForChild("CaveLobby", MAX_WAIT)
while not timedOut() and not (lobby and lobby:FindFirstChild("SpawnPad") and player.Character and player.Character:FindFirstChild("HumanoidRootPart")) do
	task.wait(0.1)
end
task.wait(0.5) -- let the lighting switch and the first frames settle

running = false
local fade = TweenInfo.new(0.8)
TweenService:Create(bg, fade, {BackgroundTransparency = 1}):Play()
TweenService:Create(title, fade, {TextTransparency = 1}):Play()
TweenService:Create(sub, fade, {TextTransparency = 1}):Play()
task.wait(0.9)
gui:Destroy()
