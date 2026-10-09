-- SnowfallClient: gentle snow falling around you while you're at Cappuccino Ballerina Academy (only on your screen).
local RunService = game:GetService("RunService")
local CENTER = Vector3.new(-4400, 597, 4450)
local RADIUS = 1500

local cloud = Instance.new("Part")
cloud.Name = "SnowCloud" cloud.Anchored = true cloud.CanCollide = false cloud.CanQuery = false cloud.CanTouch = false
cloud.Transparency = 1 cloud.Size = Vector3.new(220, 1, 220)
local pe = Instance.new("ParticleEmitter")
pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
pe.Color = ColorSequence.new(Color3.new(1, 1, 1))
pe.LightEmission = 0.4
pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.25) })
pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0.1), NumberSequenceKeypoint.new(0.9, 0.2), NumberSequenceKeypoint.new(1, 1) })
pe.Lifetime = NumberRange.new(9, 12)
pe.Rate = 220
pe.Speed = NumberRange.new(5, 8)
pe.SpreadAngle = Vector2.new(20, 20)
pe.EmissionDirection = Enum.NormalId.Bottom
pe.Acceleration = Vector3.new(1.5, 0, 0.8)
pe.RotSpeed = NumberRange.new(-60, 60)
pe.Enabled = false
pe.Parent = cloud
cloud.Parent = workspace

RunService.RenderStepped:Connect(function()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local p = cam.CFrame.Position
	local d = Vector3.new(p.X - CENTER.X, 0, p.Z - CENTER.Z).Magnitude
	local on = d < RADIUS
	if pe.Enabled ~= on then pe.Enabled = on end
	if on then cloud.CFrame = CFrame.new(p.X, p.Y + 60, p.Z) end
end)
