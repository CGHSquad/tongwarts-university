--[[
	SeaLifeClient — the living sea around Tralala Tralalero University, on your own screen only.

	While you're at the university (ZoneClient sets the player's "Zone" attribute to "Tralala") it
	spawns glowing jellyfish that drift and pulse, schools of fish circling over the reef, and sharks
	cruising high above the domes. It also sways the kelp (tagged "Kelp") and bobs the Dining Hall's
	floating candles. Everything it made is cleaned up when you leave.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local C = Vector3.new(-4000, 100.6, 0) -- campus floor centre
local rng = Random.new(31)

local folder: Folder? = nil
local jellies, fish, sharks = {}, {}, {}

local function part(size, cf, color, mat, transp, shape)
	local p = Instance.new("Part")
	p.Anchored = true p.CanCollide = false p.CanQuery = false p.CanTouch = false p.CastShadow = false
	p.Size = size p.CFrame = cf p.Color = color p.Material = mat or Enum.Material.SmoothPlastic
	p.Transparency = transp or 0
	if shape == "ball" then p.Shape = Enum.PartType.Ball
	elseif shape == "egg" then local m = Instance.new("SpecialMesh") m.MeshType = Enum.MeshType.Sphere m.Parent = p end
	p.Parent = folder
	return p
end

local JELLY_COLORS = { Color3.fromRGB(255, 130, 220), Color3.fromRGB(120, 220, 255), Color3.fromRGB(190, 140, 255), Color3.fromRGB(140, 255, 220) }
local FISH_COLORS = { Color3.fromRGB(255, 210, 70), Color3.fromRGB(255, 140, 60), Color3.fromRGB(120, 220, 255), Color3.fromRGB(220, 230, 245), Color3.fromRGB(255, 120, 170) }

local function build()
	local newFolder = Instance.new("Folder")
	newFolder.Name = "SeaLife"
	newFolder.Parent = workspace
	folder = newFolder
	-- jellyfish (kept out of the dry buildings)
	local JDRY = { { 0, 235, 36 }, { 0, -175, 138 }, { -270, 50, 84 }, { 260, -80, 70 }, { 270, 175, 90 }, { 300, -360, 118 } }
	for i = 1, 34 do
		local r, th = rng:NextNumber(40, 420), rng:NextNumber(0, 2 * math.pi)
		for _ = 1, 30 do
			local x, z = r * math.cos(th), 50 + r * math.sin(th)
			local clear = true
			for _, d in JDRY do if (Vector2.new(x, z) - Vector2.new(d[1], d[2])).Magnitude < d[3] + 8 then clear = false end end
			if clear then break end
			r, th = rng:NextNumber(40, 420), rng:NextNumber(0, 2 * math.pi)
		end
		local base = C + Vector3.new(r * math.cos(th), rng:NextNumber(30, 200), 50 + r * math.sin(th))
		local s = rng:NextNumber(0.7, 1.6)
		local color = JELLY_COLORS[rng:NextInteger(1, #JELLY_COLORS)]
		local j = { base = base, s = s, phase = rng:NextNumber(0, 6.28), parts = {}, offs = {}, sizes = {} }
		local bell = part(Vector3.new(4, 2.6, 4) * s, CFrame.new(base), color, Enum.Material.Glass, 0.25, "egg")
		local glow = part(Vector3.new(1.8, 1.2, 1.8) * s, CFrame.new(base), color:Lerp(Color3.new(1, 1, 1), 0.4), Enum.Material.Neon, 0.1, "egg")
		local light = Instance.new("PointLight") light.Color = color light.Range = 10 * s light.Brightness = 1.2 light.Shadows = false light.Parent = glow
		table.insert(j.parts, bell) table.insert(j.offs, CFrame.new())
		table.insert(j.parts, glow) table.insert(j.offs, CFrame.new(0, -0.2 * s, 0))
		for k = 0, 5 do
			local a = k / 6 * 2 * math.pi
			local len = rng:NextNumber(4, 8) * s
			local t = part(Vector3.new(0.15, len, 0.15), CFrame.new(base), color, Enum.Material.Neon, 0.35)
			table.insert(j.parts, t) table.insert(j.offs, CFrame.new(math.cos(a) * 1.1 * s, -len / 2 - 0.6 * s, math.sin(a) * 1.1 * s))
		end
		j.bell = bell
		table.insert(jellies, j)
	end
	-- fish schools: { centre, radius, count, size }
	local schools = {}
	-- keep the open-water schools out of the dry domes and the Main Hall
	local DRY = { { 0, 235, 36 }, { 0, -175, 138 }, { -270, 50, 84 }, { 260, -80, 70 }, { 270, 175, 90 }, { 300, -360, 118 } }
	local tries = 0
	while #schools < 12 and tries < 400 do
		tries += 1
		local r, th = rng:NextNumber(60, 400), rng:NextNumber(0, 2 * math.pi)
		local x, z, y = r * math.cos(th), 50 + r * math.sin(th), rng:NextNumber(14, 120)
		local radius = rng:NextNumber(10, 26)
		local ok = true
		for _, d in DRY do
			if (Vector2.new(x, z) - Vector2.new(d[1], d[2])).Magnitude < d[3] + radius + 6 then ok = false end
		end
		if ok then table.insert(schools, { C + Vector3.new(x, y, z), radius, rng:NextInteger(10, 16), rng:NextNumber(0.8, 1.4) }) end
	end
	table.insert(schools, { C + Vector3.new(-270, 12, 50), 2.6, 7, 0.35 }) -- the dorm atrium's fish tank
	table.insert(schools, { C + Vector3.new(260, 12, -80), 3, 7, 0.4 }) -- the dining hall's aquarium column
	for _, sc in schools do
		local color = FISH_COLORS[rng:NextInteger(1, #FISH_COLORS)]
		local dir = if rng:NextNumber() < 0.5 then 1 else -1
		local speed = rng:NextNumber(0.25, 0.5) * dir
		for k = 1, sc[3] do
			local sz = sc[4]
			local body = part(Vector3.new(0.6, 0.8, 1.8) * sz, CFrame.new(sc[1]), color, Enum.Material.SmoothPlastic, 0, "egg")
			local tail = part(Vector3.new(0.1, 0.9, 0.7) * sz, CFrame.new(sc[1]), color:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.SmoothPlastic, 0, "egg")
			table.insert(fish, {
				body = body, tail = tail, c = sc[1], r = sc[2] * rng:NextNumber(0.7, 1.15), y = rng:NextNumber(-3, 3) * math.min(1, sc[2] / 10),
				phase = rng:NextNumber(0, 2 * math.pi), speed = speed * rng:NextNumber(0.9, 1.1), size = sz, dir = dir,
			})
		end
	end
	-- sharks cruising high above the spires
	for i = 1, 4 do
		local len = rng:NextNumber(14, 22)
		local col = Color3.fromRGB(105, 135, 170):Lerp(Color3.fromRGB(70, 90, 130), rng:NextNumber())
		local sh = { len = len, r = rng:NextNumber(140, 320), y = rng:NextNumber(185, 210), phase = rng:NextNumber(0, 6.28), speed = rng:NextNumber(0.03, 0.05) * (if i % 2 == 0 then 1 else -1), parts = {}, offs = {} }
		local function add(p, off) table.insert(sh.parts, p) table.insert(sh.offs, off) end
		add(part(Vector3.new(len * 0.3, len * 0.3, len), CFrame.new(), col, nil, 0, "egg"), CFrame.new())
		add(part(Vector3.new(len * 0.24, len * 0.18, len * 0.8), CFrame.new(), Color3.fromRGB(230, 236, 245), nil, 0, "egg"), CFrame.new(0, -len * 0.07, -len * 0.05))
		add(part(Vector3.new(len * 0.16, len * 0.16, len * 0.5), CFrame.new(), col, nil, 0, "egg"), CFrame.new(0, 0, len * 0.42))
		local fin = Instance.new("WedgePart") fin.Anchored = true fin.CanCollide = false fin.CastShadow = false fin.CanQuery = false
		fin.Size = Vector3.new(len * 0.04, len * 0.24, len * 0.2) fin.Color = col fin.Parent = folder
		add(fin, CFrame.new(0, len * 0.24, len * 0.02) * CFrame.Angles(0, math.pi, 0))
		local tail1 = fin:Clone() tail1.Size = Vector3.new(len * 0.04, len * 0.26, len * 0.18) tail1.Parent = folder
		add(tail1, CFrame.new(0, len * 0.12, len * 0.68) * CFrame.Angles(math.rad(-30), math.pi, 0))
		local tail2 = fin:Clone() tail2.Size = Vector3.new(len * 0.04, len * 0.18, len * 0.14) tail2.Parent = folder
		add(tail2, CFrame.new(0, -len * 0.1, len * 0.66) * CFrame.Angles(math.rad(200), math.pi, 0))
		for _, sd in { -1, 1 } do
			local pec = fin:Clone() pec.Size = Vector3.new(len * 0.03, len * 0.16, len * 0.2) pec.Parent = folder
			add(pec, CFrame.new(sd * len * 0.2, -len * 0.08, -len * 0.08) * CFrame.Angles(0, math.pi, math.rad(sd * 70)))
			add(part(Vector3.new(1, 1, 1) * len * 0.035, CFrame.new(), Color3.fromRGB(15, 18, 30), nil, 0, "ball"), CFrame.new(sd * len * 0.105, len * 0.04, -len * 0.36))
		end
		table.insert(sharks, sh)
	end
end

local function clear()
	if folder then folder:Destroy() end
	folder = nil
	table.clear(jellies) table.clear(fish) table.clear(sharks)
end

-- kelp sway and candle bob work on the server-built models
local kelpBase: { [Model]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local candleBase: { [BasePart]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

local active = false
local function onZone()
	local now = player:GetAttribute("Zone") == "Tralala"
	if now == active then return end
	active = now
	if active then build() else clear() end
end
player:GetAttributeChangedSignal("Zone"):Connect(onZone)
onZone()

local t, acc = 0, 0
RunService.RenderStepped:Connect(function(dt)
	if not active then return end
	t += dt
	local parts, cfs = {}, {}
	for _, j in jellies do
		local pulse = 1 + 0.14 * math.sin(t * 2.2 + j.phase)
		local pos = j.base + Vector3.new(math.sin(t * 0.13 + j.phase) * 6, math.sin(t * 0.5 + j.phase) * 4, math.cos(t * 0.11 + j.phase) * 6)
		local root = CFrame.new(pos) * CFrame.Angles(math.sin(t * 0.7 + j.phase) * 0.12, t * 0.2, 0)
		j.bell.Size = Vector3.new(4 * pulse, 2.6 / pulse, 4 * pulse) * j.s
		for k, p in j.parts do
			local off = j.offs[k]
			if k > 2 then off = off * CFrame.Angles(math.sin(t * 2 + k + j.phase) * 0.15, 0, math.cos(t * 1.7 + k) * 0.15) end
			table.insert(parts, p) table.insert(cfs, root * off)
		end
	end
	for _, f in fish do
		local a = t * f.speed + f.phase
		local pos = f.c + Vector3.new(math.cos(a) * f.r, f.y + math.sin(t * 0.8 + f.phase) * 0.8, math.sin(a) * f.r)
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a)) * f.dir
		local cf = CFrame.lookAt(pos, pos + tangent)
		table.insert(parts, f.body) table.insert(cfs, cf)
		table.insert(parts, f.tail) table.insert(cfs, cf * CFrame.new(0, 0, 1.05 * f.size) * CFrame.Angles(0, math.sin(t * 9 + f.phase) * 0.5, 0))
	end
	for _, sh in sharks do
		local a = t * sh.speed + sh.phase
		local pos = C + Vector3.new(math.cos(a) * sh.r, sh.y + math.sin(t * 0.2 + sh.phase) * 6, 60 + math.sin(a) * sh.r)
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a)) * math.sign(sh.speed)
		local root = CFrame.lookAt(pos, pos + tangent) * CFrame.Angles(0, math.sin(t * 1.6 + sh.phase) * 0.08, math.sin(a) * 0.1)
		for k, p in sh.parts do
			local off = sh.offs[k]
			if k == 5 or k == 6 then off = CFrame.Angles(0, math.sin(t * 1.6 + sh.phase) * 0.25, 0) * off end
			table.insert(parts, p) table.insert(cfs, root * off)
		end
	end
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)

	acc += dt
	if acc < 1 / 30 then return end
	acc = 0
	local camPos = workspace.CurrentCamera.CFrame.Position
	for _, m in CollectionService:GetTagged("Kelp") do
		if m:IsA("Model") and m.PrimaryPart then
			local base = kelpBase[m]
			if not base then base = m:GetPivot() kelpBase[m] = base end
			if (base.Position - camPos).Magnitude < 260 then
				local ph = base.Position.X * 0.13 + base.Position.Z * 0.07
				m:PivotTo(base * CFrame.Angles(math.sin(t * 0.7 + ph) * 0.05, 0, math.cos(t * 0.55 + ph) * 0.05))
			end
		end
	end
	local uni = workspace:FindFirstChild("TralalaUniversity")
	local dining = uni and uni:FindFirstChild("DiningHall")
	local candles = dining and dining:FindFirstChild("Candles")
	if candles and (dining:GetPivot().Position - camPos).Magnitude < 160 then
		for _, c in candles:GetChildren() do
			if c:IsA("BasePart") then
				local base = candleBase[c]
				if not base then base = c.CFrame candleBase[c] = base end
				c.CFrame = base + Vector3.new(0, math.sin(t * 1.3 + (c:GetAttribute("Bob") or 0)) * 0.4, 0)
			end
		end
	end
end)
