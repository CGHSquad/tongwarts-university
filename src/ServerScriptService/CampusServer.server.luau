--[[
	CampusServer — what you can do at Tung Tung Tung Sahur University (Workspace.SahurCollege):

		Dorms        beds (tagged "CampusBed"): Rest to heal fully
		Dining Hall  food on the counter (tagged "CampusFood"): Eat to heal and get a short boost
		Gym          a wild version of every Tung Tung on the sparring stage (EnemySpawns "GymWild*"):
		             walk into one to spar
		Courtyard    benches and gazebos to sit on; anyone idle for a while shows as AFK

	Anyone who goes down into the clouds (off a cliff, or down the spiral staircase) is summoned back to
	the university's spawn circle.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ZoneTravel = require(script.Parent:WaitForChild("ZoneTravel"))
local events = ReplicatedStorage:WaitForChild("LobbyEvents")
local PortalMessage = events:WaitForChild("PortalMessage")
local SetAFK = events:WaitForChild("SetAFK")

local college = workspace:WaitForChild("SahurCollege")
local CENTER: Vector3 = college:GetAttribute("Center") or Vector3.new(4000, 300, 0)

local REST_COOLDOWN = 4
local EAT_COOLDOWN = 8
local FALL_BELOW = 112 -- studs under the mountain top: just under the cloud sea (its top is at y = 300)
local ISLAND_AREA = 3000 -- how far out (across the ground) still counts as the university's mountains

-- Food buffs: what each one does, and for how long.
local BUFFS = {
	Hearty = { seconds = 120, text = "Hearty: +25 max health for 2 minutes" },
	Energized = { seconds = 90, text = "Energized: run faster for 90 seconds" },
	Springy = { seconds = 90, text = "Springy: jump higher for 90 seconds" },
}
local SPEED_BONUS = 6
local JUMP_HEIGHT = 12 -- normal is 7.2
local EXTRA_HEALTH = 25

local lastRest: { [Player]: number } = {}
local lastEat: { [Player]: number } = {}
local buffToken: { [Player]: { [string]: number } } = {}

local function humanoidOf(player: Player): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function sparkle(player: Player, color: Color3)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local att = Instance.new("Attachment"); att.Parent = root
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(color); pe.LightEmission = 1; pe.Rate = 0
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.8, 1.3); pe.Speed = NumberRange.new(3, 7); pe.SpreadAngle = Vector2.new(180, 180)
	pe.Parent = att
	pe:Emit(40)
	task.delay(2, function() att:Destroy() end)
end

--[[ Dorms: rest ]]
local function onRest(player: Player)
	local now = os.clock()
	if now - (lastRest[player] or 0) < REST_COOLDOWN then return end
	lastRest[player] = now
	local hum = humanoidOf(player)
	if not hum or hum.Health <= 0 then return end
	hum.Health = hum.MaxHealth
	sparkle(player, Color3.fromRGB(150, 255, 190))
	PortalMessage:FireClient(player, "Dorms", "Well rested: you're fully healed")
end

--[[ Dining Hall: eat ]]
local function startBuff(player: Player, buff: string)
	local tokens = buffToken[player] or {}
	buffToken[player] = tokens
	tokens[buff] = (tokens[buff] or 0) + 1
	local token = tokens[buff]
	local hum = humanoidOf(player)
	if buff == "Energized" then
		player:SetAttribute("SpeedBonus", SPEED_BONUS)
	elseif buff == "Springy" and hum then
		hum.UseJumpPower = false
		hum.JumpHeight = JUMP_HEIGHT
	elseif buff == "Hearty" and hum then
		if not hum:GetAttribute("HeartyBase") then hum:SetAttribute("HeartyBase", hum.MaxHealth) end
		hum.MaxHealth = hum:GetAttribute("HeartyBase") + EXTRA_HEALTH
	end
	task.delay(BUFFS[buff].seconds, function()
		if tokens[buff] ~= token then return end -- eaten again since: that one's timer wins
		local h = humanoidOf(player)
		if buff == "Energized" then
			player:SetAttribute("SpeedBonus", nil)
		elseif buff == "Springy" and h and h.JumpHeight == JUMP_HEIGHT then
			h.JumpHeight = 7.2
		elseif buff == "Hearty" and h and h:GetAttribute("HeartyBase") then
			h.MaxHealth = h:GetAttribute("HeartyBase")
			h:SetAttribute("HeartyBase", nil)
		end
		if player.Parent then PortalMessage:FireClient(player, "Dining Hall", buff .. " wore off") end
	end)
end

local function onEat(player: Player, food: BasePart)
	local now = os.clock()
	if now - (lastEat[player] or 0) < EAT_COOLDOWN then
		PortalMessage:FireClient(player, "Dining Hall", "Still full! Try again in a few seconds")
		return
	end
	lastEat[player] = now
	local hum = humanoidOf(player)
	if not hum or hum.Health <= 0 then return end
	local buff = food:GetAttribute("Buff")
	if buff and BUFFS[buff] then startBuff(player, buff) end
	hum.Health = hum.MaxHealth
	sparkle(player, Color3.fromRGB(255, 220, 120))
	PortalMessage:FireClient(player, food:GetAttribute("FoodName") or "Dining Hall", if buff and BUFFS[buff] then "Healed! " .. BUFFS[buff].text else "Healed!")
end

local function hookPrompt(part: Instance, handler: (Player, BasePart) -> ())
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if prompt and part:IsA("BasePart") then
		prompt.Triggered:Connect(function(player) handler(player, part) end)
	end
end
for _, bed in CollectionService:GetTagged("CampusBed") do hookPrompt(bed, function(p) onRest(p) end) end
CollectionService:GetInstanceAddedSignal("CampusBed"):Connect(function(bed) hookPrompt(bed, function(p) onRest(p) end) end)
for _, food in CollectionService:GetTagged("CampusFood") do hookPrompt(food, onEat) end
CollectionService:GetInstanceAddedSignal("CampusFood"):Connect(function(food) hookPrompt(food, onEat) end)

--[[ AFK tags (the client reports when it's been idle) ]]
local function setAfkTag(player: Player, afk: boolean)
	player:SetAttribute("AFK", afk or nil)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	local tag = head and head:FindFirstChild("AFKTag")
	if afk and head and not tag then
		local bb = Instance.new("BillboardGui"); bb.Name = "AFKTag"; bb.Size = UDim2.fromOffset(90, 32)
		bb.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0); bb.MaxDistance = 80; bb.LightInfluence = 0
		local t = Instance.new("TextLabel"); t.BackgroundTransparency = 1; t.Size = UDim2.fromScale(1, 1)
		t.Font = Enum.Font.FredokaOne; t.TextScaled = true; t.Text = "AFK zzz"
		t.TextColor3 = Color3.fromRGB(200, 230, 255); t.TextStrokeTransparency = 0.3; t.Parent = bb
		bb.Parent = head
	elseif not afk and tag then
		tag:Destroy()
	end
end
SetAFK.OnServerEvent:Connect(function(player, afk)
	if typeof(afk) ~= "boolean" then return end
	setAfkTag(player, afk)
end)

--[[ Down into the clouds ]]
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.25 then return end
	acc = 0
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local rel = root.Position - CENTER
			if Vector3.new(rel.X, 0, rel.Z).Magnitude < ISLAND_AREA and rel.Y < -FALL_BELOW then
				ZoneTravel.toCampus(player)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(p)
	lastRest[p] = nil; lastEat[p] = nil; buffToken[p] = nil
end)
