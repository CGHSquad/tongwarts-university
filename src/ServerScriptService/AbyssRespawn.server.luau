-- Anyone who falls into the chasm starts glowing, then is summoned back onto the spawn magic circle.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local events = ReplicatedStorage:WaitForChild("LobbyEvents")
local Summon = events:WaitForChild("Summon")
local AbyssFlash = events:WaitForChild("AbyssFlash")
local circle = workspace:WaitForChild("CaveLobby"):WaitForChild("SpawnPad"):WaitForChild("SpawnCircle")

local FLOOR_Y = 50
local GLOW_BELOW = FLOOR_Y - 18    -- start glowing once this far down
local SUMMON_BELOW = FLOOR_Y - 70  -- teleport well before reaching the water far below (water is ~125 down)
local CHASM_RADIUS = 116
local LOBBY_RADIUS = 300 -- only players this close to the lobby (across the ground) are watched
local CENTER = workspace.CaveLobby:GetAttribute("Center") or Vector3.zero -- the lobby was built around the origin, then moved here

local busy = {}

local function addGlow(char)
	if char:FindFirstChild("AbyssGlow") then return end
	local h = Instance.new("Highlight")
	h.Name = "AbyssGlow"
	h.FillColor = Color3.fromRGB(110, 230, 255)
	h.FillTransparency = 0.3
	h.OutlineColor = Color3.fromRGB(210, 255, 240)
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Parent = char
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local l = Instance.new("PointLight")
		l.Name = "AbyssLight"; l.Range = 20; l.Brightness = 4; l.Color = Color3.fromRGB(120, 230, 255); l.Parent = hrp
		local att = Instance.new("Attachment"); att.Name = "AbyssFX"; att.Parent = hrp
		local pe = Instance.new("ParticleEmitter")
		pe.Rate = 70; pe.Lifetime = NumberRange.new(0.8, 1.4); pe.Speed = NumberRange.new(1, 4)
		pe.SpreadAngle = Vector2.new(180, 180); pe.LightEmission = 1
		pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0)})
		pe.Color = ColorSequence.new(Color3.fromRGB(160, 240, 255), Color3.fromRGB(120, 255, 180))
		pe.Parent = att
	end
end

local function removeFX(char)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		for _, n in ipairs({"AbyssLight", "AbyssFX"}) do local x = hrp:FindFirstChild(n); if x then x:Destroy() end end
	end
end

local function setHidden(char, hidden, fadeTime)
	for _, d in ipairs(char:GetDescendants()) do
		if (d:IsA("BasePart") and d.Name ~= "HumanoidRootPart") or d:IsA("Decal") then
			if hidden then
				if d:GetAttribute("AbyssOrigT") == nil then d:SetAttribute("AbyssOrigT", d.Transparency) end
				d.Transparency = 1
			else
				local orig = d:GetAttribute("AbyssOrigT") or 0
				d:SetAttribute("AbyssOrigT", nil)
				TweenService:Create(d, TweenInfo.new(fadeTime or 0.7, Enum.EasingStyle.Quad), {Transparency = orig}):Play()
			end
		end
	end
end

local function summon(player, char)
	busy[player] = true
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then busy[player] = nil return end
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.Anchored = true -- freeze mid-air immediately so they never reach the bottom
	addGlow(char)
	AbyssFlash:FireClient(player)
	task.wait(0.25)
	if not char.Parent then busy[player] = nil return end
	setHidden(char, true)
	hrp.AssemblyLinearVelocity = Vector3.zero
	local pos = circle.Position + Vector3.new(0, 3.2, 0)
	char:PivotTo(CFrame.lookAt(pos, Vector3.new(CENTER.X, pos.Y, CENTER.Z)))
	hrp.Anchored = true
	Summon:FireAllClients(char, circle.Position)
	task.wait(0.55)
	setHidden(char, false, 0.8)
	local glow = char:FindFirstChild("AbyssGlow")
	if glow then TweenService:Create(glow, TweenInfo.new(1.8), {FillTransparency = 1, OutlineTransparency = 1}):Play() end
	task.wait(0.8)
	if hrp.Parent then hrp.Anchored = false end
	task.delay(1.1, function()
		if glow then glow:Destroy() end
		removeFX(char)
	end)
	task.wait(1)
	busy[player] = nil
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 and not busy[player] then
			local p = hrp.Position + hrp.AssemblyLinearVelocity * math.min(dt * 2, 0.1)
			local rel = p - CENTER
			local r = Vector3.new(rel.X, 0, rel.Z).Magnitude
			if r > LOBBY_RADIUS then
				-- out in the overworld: not this script's business
			elseif p.Y < SUMMON_BELOW then
				task.spawn(summon, player, char)
			elseif p.Y < GLOW_BELOW and r < CHASM_RADIUS then
				addGlow(char)
			elseif p.Y > GLOW_BELOW + 4 and char:FindFirstChild("AbyssGlow") then
				char.AbyssGlow:Destroy(); removeFX(char)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(p) busy[p] = nil end)
