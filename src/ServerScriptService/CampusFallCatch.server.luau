--[[
	CampusFallCatch — the cliff-top campuses (Cappuccino Assassino over its lava sea, Cappuccino Ballerina on
	its snowy mountainside). Anyone who drops off an edge starts glowing, then — like the lobby abyss — is
	frozen, flashed and summoned back onto that campus's spawn circle well before the lava / the valley floor.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ZoneTravel = require(script.Parent:WaitForChild("ZoneTravel"))
local events = ReplicatedStorage:WaitForChild("LobbyEvents")
local AbyssFlash = events:WaitForChild("AbyssFlash")
local PortalMessage = events:WaitForChild("PortalMessage")

local CAMPUSES = {
	{
		name = "Cappuccino Assassino University", message = "Too hot! Back to campus",
		center = Vector3.new(0, 500, 4450), area = 1100,
		glowBelow = 500 - 14, summonBelow = 500 - 30, -- lava sea is at y 462
		glow = Color3.fromRGB(255, 140, 60), glow2 = Color3.fromRGB(255, 210, 120),
		send = function(p) ZoneTravel.toCappuccino(p) end,
	},
}
-- other campuses register here once they exist
if ZoneTravel.toBallerina then
	table.insert(CAMPUSES, {
		name = "Cappuccino Ballerina Academy", message = "Whoops! Back to the academy",
		center = Vector3.new(-4400, 597, 4450), area = 1100,
		glowBelow = 597 - 16, summonBelow = 597 - 40, -- the mountainside drops ~80+ below the ledge
		glow = Color3.fromRGB(255, 130, 210), glow2 = Color3.fromRGB(255, 220, 245),
		send = function(p) ZoneTravel.toBallerina(p) end,
	})
end

local busy = {}

local function addGlow(char, c)
	if char:FindFirstChild("AbyssGlow") then return end
	local h = Instance.new("Highlight")
	h.Name = "AbyssGlow"; h.FillColor = c.glow; h.FillTransparency = 0.3
	h.OutlineColor = c.glow2; h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Parent = char
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local l = Instance.new("PointLight"); l.Name = "AbyssLight"; l.Range = 20; l.Brightness = 4; l.Color = c.glow; l.Parent = hrp
		local att = Instance.new("Attachment"); att.Name = "AbyssFX"; att.Parent = hrp
		local pe = Instance.new("ParticleEmitter")
		pe.Rate = 70; pe.Lifetime = NumberRange.new(0.8, 1.4); pe.Speed = NumberRange.new(1, 4)
		pe.SpreadAngle = Vector2.new(180, 180); pe.LightEmission = 1
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
		pe.Color = ColorSequence.new(c.glow, c.glow2)
		pe.Parent = att
	end
end

local function removeFX(char)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then for _, n in { "AbyssLight", "AbyssFX" } do local x = hrp:FindFirstChild(n) if x then x:Destroy() end end end
end

local function setHidden(char, hidden, fadeTime)
	for _, d in char:GetDescendants() do
		if (d:IsA("BasePart") and d.Name ~= "HumanoidRootPart") or d:IsA("Decal") then
			if hidden then
				if d:GetAttribute("AbyssOrigT") == nil then d:SetAttribute("AbyssOrigT", d.Transparency) end
				d.Transparency = 1
			else
				local orig = d:GetAttribute("AbyssOrigT") or 0
				d:SetAttribute("AbyssOrigT", nil)
				TweenService:Create(d, TweenInfo.new(fadeTime or 0.7, Enum.EasingStyle.Quad), { Transparency = orig }):Play()
			end
		end
	end
end

local function summon(player, char, c)
	busy[player] = true
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then busy[player] = nil return end
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.Anchored = true -- freeze mid-air so they never reach the bottom
	addGlow(char, c)
	AbyssFlash:FireClient(player)
	PortalMessage:FireClient(player, c.name, c.message)
	task.wait(0.25)
	if not char.Parent then busy[player] = nil return end
	setHidden(char, true)
	c.send(player) -- moves them onto the spawn circle and fires the summoning effect for everyone
	hrp.Anchored = true
	task.wait(0.55)
	setHidden(char, false, 0.8)
	local glow = char:FindFirstChild("AbyssGlow")
	if glow then TweenService:Create(glow, TweenInfo.new(1.8), { FillTransparency = 1, OutlineTransparency = 1 }):Play() end
	task.wait(0.8)
	if hrp.Parent then hrp.Anchored = false end
	task.delay(1.1, function() if glow then glow:Destroy() end removeFX(char) end)
	task.wait(1)
	busy[player] = nil
end

RunService.Heartbeat:Connect(function(dt)
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 and not busy[player] then
			local p = hrp.Position + hrp.AssemblyLinearVelocity * math.min(dt * 2, 0.1)
			for _, c in CAMPUSES do
				local rel = p - c.center
				if Vector3.new(rel.X, 0, rel.Z).Magnitude < c.area and p.Y > c.center.Y - 450 then
					if p.Y < c.summonBelow then
						task.spawn(summon, player, char, c)
					elseif p.Y < c.glowBelow then
						addGlow(char, c)
					elseif p.Y > c.glowBelow + 4 and char:FindFirstChild("AbyssGlow") then
						char.AbyssGlow:Destroy() removeFX(char)
					end
					break
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(p) busy[p] = nil end)
