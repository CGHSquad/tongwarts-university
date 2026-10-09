-- ZoneClient: the lobby (a night-time cave), the overworld (afternoon on the grass), the college
-- campus (a sunny mountain top) and Tralala Tralalero University (under the sea) share one place,
-- so each player's own lighting is switched to match the area they're standing in.
-- It also runs the cel-shading outlines, and plays the quick fade-to-black when ZoneTravel moves the
-- player between areas.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local presets = ReplicatedStorage:WaitForChild("ZoneLighting")
local ZoneFade = ReplicatedStorage:WaitForChild("LobbyEvents"):WaitForChild("ZoneFade")
local lobby = workspace:WaitForChild("CaveLobby", 30)
local center = (lobby and lobby:GetAttribute("Center")) or Vector3.new(0, 0, -4000)

local LOBBY_RADIUS = 320 -- across the ground from the lobby's center
local college = workspace:WaitForChild("SahurCollege", 30)
local campusCenter = (college and college:GetAttribute("Center")) or Vector3.new(4000, 402, 0)
local CAMPUS_RADIUS = 1400 -- the university's mountain, the ballpark peak and the sky around them
local CLOUD_TOP = 300 -- top of the cloud sea under the university
local OUTLINE_COLOR = Color3.fromRGB(22, 16, 40)
-- Tralala Tralalero University, at the bottom of its own sea (underwater lighting, no day/night)
local TRALALA_CENTER = Vector3.new(-4000, 100.6, 30)
local TRALALA_RADIUS = 900
-- Cappuccino Assassino University, on basalt mesas over a lava sea at the foot of a volcano (sunset, no day/night)
local CAPPUCCINO_CENTER = Vector3.new(0, 500, 4450)
local CAPPUCCINO_RADIUS = 1300
-- Cappuccino Ballerina Academy, on a ledge high on a snowy mountainside (crisp winter afternoon, no day/night)
local BALLERINA_CENTER = Vector3.new(-4400, 597, 4450)
local BALLERINA_RADIUS = 1500

local current: string? = nil
local showCampusSky

local function zoneAt(pos: Vector3): string
	local rel = pos - center
	if Vector3.new(rel.X, 0, rel.Z).Magnitude < LOBBY_RADIUS then return "Lobby" end
	local c = pos - campusCenter
	if Vector3.new(c.X, 0, c.Z).Magnitude < CAMPUS_RADIUS then return "Campus" end
	local t = pos - TRALALA_CENTER
	if Vector3.new(t.X, 0, t.Z).Magnitude < TRALALA_RADIUS then return "Tralala" end
	local k = pos - CAPPUCCINO_CENTER
	if Vector3.new(k.X, 0, k.Z).Magnitude < CAPPUCCINO_RADIUS then return "Cappuccino" end
	local b = pos - BALLERINA_CENTER
	if Vector3.new(b.X, 0, b.Z).Magnitude < BALLERINA_RADIUS then return "Ballerina" end
	return "Overworld"
end

--[[ Cel shading: every Highlight named "CelOutline" is only switched on in the area you're standing
     in, because Roblox draws at most 31 Highlights at once and the lobby alone has 25. Characters
     always get one and always keep it. ]]
local outlines: { [Highlight]: boolean } = {}

local function outlineZone(h: Highlight): string?
	local target = h.Adornee or h.Parent
	if target and target:IsA("Model") then
		if Players:GetPlayerFromCharacter(target) then return nil end
		return zoneAt(target:GetPivot().Position)
	elseif target and target:IsA("BasePart") then
		return zoneAt(target.Position)
	end
	return nil
end

local function updateOutline(h: Highlight)
	local z = outlineZone(h)
	h.Enabled = z == nil or z == current
end

local function refreshOutlines()
	for h in outlines do
		if h.Parent == nil then outlines[h] = nil else updateOutline(h) end
	end
end

local function track(d: Instance)
	if d:IsA("Highlight") and d.Name == "CelOutline" then
		outlines[d] = true
		task.defer(updateOutline, d) -- once it's parented where it's going
	end
end
for _, d in workspace:GetDescendants() do track(d) end
workspace.DescendantAdded:Connect(track)

local function outlineCharacter(char: Model)
	if char:FindFirstChild("CelOutline") then return end
	local h = Instance.new("Highlight")
	h.Name = "CelOutline"; h.FillTransparency = 1; h.OutlineColor = OUTLINE_COLOR
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = char
end
local function watchPlayer(p: Player)
	if p.Character then outlineCharacter(p.Character) end
	p.CharacterAdded:Connect(outlineCharacter)
end
for _, p in Players:GetPlayers() do watchPlayer(p) end
Players.PlayerAdded:Connect(watchPlayer)

--[[ The university's sky dressing (cloud sea + far peaks) is huge; it only exists on your screen
     while you're at the university, so it never shows up over the overworld or the lobby. ]]
local stashed: { [Instance]: Instance } = {}
function showCampusSky(on: boolean)
	if not college then return end
	for _, name in { "CloudSea", "FarPeaks" } do
		local m = college:FindFirstChild(name)
		if m and not on then
			stashed[m] = college
			m.Parent = nil
		end
	end
	if on then
		for m, parent in stashed do m.Parent = parent end
		table.clear(stashed)
	end
end

--[[ Lighting ]]
local skies = presets:WaitForChild("Skies")
local NOT_LIGHTING = { DayNight = true }

local function apply(zone: string)
	if zone == current then return end
	current = zone
	local preset = presets:WaitForChild(zone)
	for _, c in Lighting:GetChildren() do
		if c:IsA("PostEffect") or c:IsA("Sky") or c:IsA("Atmosphere") or c:IsA("Clouds") then c:Destroy() end
	end
	for _, c in preset:GetChildren() do c:Clone().Parent = Lighting end
	for k, v in preset:GetAttributes() do
		if not NOT_LIGHTING[k] then Lighting[k] = v end
	end
	player:SetAttribute("Zone", zone) -- BattleClient listens for this
	refreshOutlines()
	showCampusSky(zone == "Campus")
end

--[[ Day and night (outdoor zones: the overworld and the university)

	Everyone shares one clock (the server's time), so it's the same time of day for all players.
	Roblox fades any custom skybox to black once ClockTime passes sunset, which would hide the night
	sky, so the sun always runs its daytime arc (6:12 -> 17:48): by day under the anime day sky, by
	night under the moonlit night sky, with darker, bluer light. Dawn and dusk get a warm tint, and the
	sky swaps while the tint is strongest. Tune the length in ReplicatedStorage.ZoneLighting
	(CycleMinutes, DayShare). ]]
local DAY_TINT = Color3.fromRGB(240, 240, 255)
local DUSK_TINT = Color3.fromRGB(255, 186, 150)
local NIGHT_TINT = Color3.fromRGB(160, 178, 255)
local NIGHT_AMBIENT = Color3.fromRGB(58, 64, 112)
local NIGHT_OUTDOOR = Color3.fromRGB(70, 82, 140)

local skyShown: string? = nil
local function setSky(which: string)
	if skyShown == which and Lighting:FindFirstChild("CycleSky") then return end
	skyShown = which
	for _, c in Lighting:GetChildren() do if c:IsA("Sky") then c:Destroy() end end
	local sky = skies[which]:Clone()
	sky.Name = "CycleSky"
	sky.Parent = Lighting
end

local function cycle()
	local preset = current and presets:FindFirstChild(current)
	if not (preset and preset:GetAttribute("DayNight")) then
		skyShown = nil
		return
	end
	local minutes = presets:GetAttribute("CycleMinutes") or 20
	local dayShare = presets:GetAttribute("DayShare") or 0.7
	local p = (workspace:GetServerTimeNow() / (minutes * 60)) % 1
	-- A fight has its own light: a clear afternoon on the battle stage whatever the time outside
	-- (BattleClient marks the player InBattle), so the stage never goes dark mid-fight. The cycle
	-- picks up where it is once the fight is over.
	local inBattle = player:GetAttribute("InBattle") == true
	local isDay = inBattle or p < dayShare
	local q = if inBattle then 0.55 elseif isDay then p / dayShare else (p - dayShare) / (1 - dayShare) -- progress through this half
	Lighting.ClockTime = 6.2 + q * 11.6
	-- how close we are to dawn/dusk (1 right at the switch, 0 from a little way in)
	local edge = math.clamp(1 - math.min(q, 1 - q) / 0.1, 0, 1)
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	local baseBright = preset:GetAttribute("Brightness") or 3
	if isDay then
		setSky("Day")
		Lighting.Brightness = baseBright * (0.55 + 0.45 * math.sin(q * math.pi))
		Lighting.OutdoorAmbient = preset:GetAttribute("OutdoorAmbient") or Lighting.OutdoorAmbient
		Lighting.Ambient = preset:GetAttribute("Ambient") or Lighting.Ambient
		if cc then cc.TintColor = DAY_TINT:Lerp(DUSK_TINT, edge) end
	else
		setSky("Night")
		Lighting.Brightness = 0.55
		Lighting.OutdoorAmbient = NIGHT_OUTDOOR
		Lighting.Ambient = NIGHT_AMBIENT
		if cc then cc.TintColor = NIGHT_TINT:Lerp(DUSK_TINT, edge * 0.6) end
	end
end

RunService.Heartbeat:Connect(function()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then apply(zoneAt(hrp.Position)) end
	cycle()
end)

--[[ Inside the clouds: below the cloud sea you can't see anything but white ]]
local cloudGui = Instance.new("ScreenGui")
cloudGui.Name = "CloudWhiteout"; cloudGui.IgnoreGuiInset = true; cloudGui.ResetOnSpawn = false; cloudGui.DisplayOrder = 55
local whiteout = Instance.new("Frame")
whiteout.Size = UDim2.fromScale(1, 1); whiteout.BorderSizePixel = 0; whiteout.BackgroundColor3 = Color3.fromRGB(246, 248, 255)
whiteout.BackgroundTransparency = 1; whiteout.Parent = cloudGui
cloudGui.Parent = player:WaitForChild("PlayerGui")
RunService.RenderStepped:Connect(function()
	local cam = workspace.CurrentCamera
	if current ~= "Campus" or not cam then whiteout.BackgroundTransparency = 1 return end
	local camPos = cam.CFrame.Position
	local rel = camPos - campusCenter
	if Vector3.new(rel.X, 0, rel.Z).Magnitude > CAMPUS_RADIUS then whiteout.BackgroundTransparency = 1 return end -- e.g. the battle stage
	local depth = (CLOUD_TOP + 4) - camPos.Y -- starts thickening just above the cloud tops
	whiteout.BackgroundTransparency = 1 - math.clamp(depth / 10, 0, 1)
end)

--[[ Fade ]]
local gui = Instance.new("ScreenGui")
gui.Name = "ZoneFade"; gui.IgnoreGuiInset = true; gui.ResetOnSpawn = false; gui.DisplayOrder = 60
local black = Instance.new("Frame")
black.Size = UDim2.fromScale(1, 1); black.BackgroundColor3 = Color3.new(0, 0, 0)
black.BackgroundTransparency = 1; black.BorderSizePixel = 0; black.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")

ZoneFade.OnClientEvent:Connect(function(seconds: number)
	TweenService:Create(black, TweenInfo.new(seconds), {BackgroundTransparency = 0}):Play()
	task.delay(seconds + 0.25, function()
		TweenService:Create(black, TweenInfo.new(0.5), {BackgroundTransparency = 1}):Play()
	end)
end)
