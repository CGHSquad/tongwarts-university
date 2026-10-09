-- SummonFX: the beam of light, shockwave rings, rising sparks and screen flash when anyone is summoned onto
-- a spawn circle (lobby, campuses, overworld) and the flash when you fall into an abyss or off a campus.
-- Lives here (not on each spawn plate) so it runs exactly once and always cleans itself up.
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local player = Players.LocalPlayer

---------------------------------------------------------------- summoning effect
local CYAN, MINT, WHITE = Color3.fromRGB(110, 230, 255), Color3.fromRGB(130, 255, 190), Color3.fromRGB(235, 250, 255)
local fx = workspace:FindFirstChild("SummonFX_Local") or Instance.new("Folder"); fx.Name = "SummonFX_Local"; fx.Parent = workspace

local function fxPart(props)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in pairs(props) do p[k] = v end
	p.Parent = fx
	return p
end

local THEMES = {
	{ center = Vector3.new(0, 500, 4450), radius = 1400, a = Color3.fromRGB(255, 150, 60), b = Color3.fromRGB(255, 210, 120), core = Color3.fromRGB(255, 240, 210), tint = Color3.fromRGB(255, 220, 190) }, -- Cappuccino Assassino
	{ center = Vector3.new(-4400, 500, 4450), radius = 1400, a = Color3.fromRGB(255, 120, 200), b = Color3.fromRGB(255, 200, 235), core = Color3.fromRGB(255, 240, 250), tint = Color3.fromRGB(255, 220, 240) }, -- Cappuccino Ballerina
}
local function themeAt(pos)
	for _, t in THEMES do
		local d = pos - t.center
		if Vector3.new(d.X, 0, d.Z).Magnitude < t.radius then return t end
	end
	return { a = CYAN, b = MINT, core = WHITE, tint = Color3.fromRGB(200, 245, 255) }
end

local function summonFX(pos, isMe)
	local th = themeAt(pos)
	local CYAN, MINT, WHITE = th.a, th.b, th.core
	local up = CFrame.Angles(0, 0, math.rad(90))
	-- beam of light slamming down onto the circle
	local beam = fxPart({Shape = Enum.PartType.Cylinder, Color = CYAN, Transparency = 0.15, Size = Vector3.new(70, 0.5, 0.5), CFrame = CFrame.new(pos + Vector3.new(0, 35, 0)) * up})
	local core = fxPart({Shape = Enum.PartType.Cylinder, Color = WHITE, Transparency = 0.05, Size = Vector3.new(70, 0.2, 0.2), CFrame = beam.CFrame})
	TweenService:Create(beam, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {Size = Vector3.new(70, 9, 9)}):Play()
	TweenService:Create(core, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {Size = Vector3.new(70, 3.5, 3.5)}):Play()
	task.delay(0.45, function()
		TweenService:Create(beam, TweenInfo.new(1.1, Enum.EasingStyle.Quad), {Size = Vector3.new(70, 0.2, 0.2), Transparency = 1}):Play()
		TweenService:Create(core, TweenInfo.new(0.9, Enum.EasingStyle.Quad), {Size = Vector3.new(70, 0.1, 0.1), Transparency = 1}):Play()
	end)
	-- shockwave rings across the floor
	for i = 0, 1 do
		task.delay(0.15 + i * 0.2, function()
			local ring = fxPart({Shape = Enum.PartType.Cylinder, Color = (i == 0) and CYAN or MINT, Transparency = 0.2, Size = Vector3.new(0.15, 3, 3), CFrame = CFrame.new(pos + Vector3.new(0, 0.25 + i * 0.05, 0)) * up})
			TweenService:Create(ring, TweenInfo.new(0.9, Enum.EasingStyle.Quart), {Size = Vector3.new(0.15, 34, 34), Transparency = 1}):Play()
			Debris:AddItem(ring, 1)
		end)
	end
	-- rising rune sparks + orbiting motes spiralling up
	local emitPart = fxPart({Size = Vector3.new(12, 0.2, 12), CFrame = CFrame.new(pos + Vector3.new(0, 0.3, 0)), Transparency = 1})
	local pe = Instance.new("ParticleEmitter")
	pe.Shape = Enum.ParticleEmitterShape.Box; pe.EmissionDirection = Enum.NormalId.Top
	pe.Speed = NumberRange.new(10, 22); pe.Lifetime = NumberRange.new(0.8, 1.6); pe.Rate = 0
	pe.LightEmission = 1; pe.Drag = 2; pe.SpreadAngle = Vector2.new(10, 10)
	pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0)})
	pe.Color = ColorSequence.new(CYAN, MINT); pe.Parent = emitPart
	pe:Emit(140)
	local motes = {}
	for i = 1, 10 do
		table.insert(motes, fxPart({Shape = Enum.PartType.Ball, Color = (i % 2 == 0) and CYAN or MINT, Size = Vector3.new(0.7, 0.7, 0.7), Position = pos}))
	end
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		for i, m in ipairs(motes) do
			local a = t * 7 + i * (math.pi * 2 / #motes)
			local r = 6.5 * (1 - math.min(t / 1.3, 1)) + 1
			m.Position = pos + Vector3.new(math.cos(a) * r, t * 7, math.sin(a) * r)
			m.Transparency = math.min(t / 1.3, 1)
		end
		if t > 1.35 then conn:Disconnect(); for _, m in ipairs(motes) do m:Destroy() end end
	end)
	-- light flash
	local flashPart = fxPart({Size = Vector3.new(1, 1, 1), Position = pos + Vector3.new(0, 4, 0), Transparency = 1})
	local l = Instance.new("PointLight"); l.Range = 40; l.Brightness = 10; l.Color = CYAN; l.Parent = flashPart
	TweenService:Create(l, TweenInfo.new(1.4), {Brightness = 0}):Play()
	for _, x in { beam, core, emitPart, flashPart } do Debris:AddItem(x, 1.8) end
	-- for the summoned player: colour flash + camera punch
	if isMe then
		local cc = Instance.new("ColorCorrectionEffect"); cc.Brightness = 0.5; cc.TintColor = th.tint; cc.Parent = Lighting
		TweenService:Create(cc, TweenInfo.new(1), {Brightness = 0, TintColor = Color3.new(1, 1, 1)}):Play()
		task.delay(1.1, function() cc:Destroy() end)
		local cam = workspace.CurrentCamera
		local fov = cam.FieldOfView
		cam.FieldOfView = fov + 18
		TweenService:Create(cam, TweenInfo.new(0.7, Enum.EasingStyle.Back), {FieldOfView = fov}):Play()
	end
end

-- full-screen flash for the player who fell, right before they vanish
local function abyssFlash()
	local sg = Instance.new("ScreenGui"); sg.Name = "AbyssFlash"; sg.IgnoreGuiInset = true; sg.DisplayOrder = 50
	local f = Instance.new("Frame"); f.Size = UDim2.fromScale(1, 1); f.BackgroundColor3 = Color3.fromRGB(180, 240, 255); f.BackgroundTransparency = 1; f.BorderSizePixel = 0; f.Parent = sg
	local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(Color3.fromRGB(120, 230, 255), Color3.fromRGB(150, 255, 200)); g.Rotation = 90; g.Parent = f
	sg.Parent = player:WaitForChild("PlayerGui")
	TweenService:Create(f, TweenInfo.new(0.25), {BackgroundTransparency = 0.1}):Play()
	task.delay(0.45, function()
		TweenService:Create(f, TweenInfo.new(0.7), {BackgroundTransparency = 1}):Play()
		task.delay(0.75, function() sg:Destroy() end)
	end)
end

local events = ReplicatedStorage:WaitForChild("LobbyEvents")
events:WaitForChild("Summon").OnClientEvent:Connect(function(char, pos)
	summonFX(pos, char == player.Character)
end)
events:WaitForChild("AbyssFlash").OnClientEvent:Connect(abyssFlash)
