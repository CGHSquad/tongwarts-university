-- MainHallTVs: the TVs in both universities' Main Halls (Tung Tung Tung Sahur's on the mountain,
-- Tralala Tralalero's under the sea) flip between "channels" every few seconds, with a scrolling ticker
-- along the bottom. Purely for looks, and only on your own screen.
local RunService = game:GetService("RunService")

local TUNG = {
	{ "TUNG TUNG NEWS", "BREAKING: Wild Elder spotted in the university gym!", Color3.fromRGB(80, 170, 255), Color3.fromRGB(30, 60, 160) },
	{ "SAHUR FIELD LIVE", "Timbers vs. Saplings · Bottom of the 9th · Bases loaded", Color3.fromRGB(90, 200, 110), Color3.fromRGB(20, 90, 50) },
	{ "TUNG KART", "Player 1 wins! · Press A to race again", Color3.fromRGB(255, 120, 200), Color3.fromRGB(120, 30, 120) },
	{ "WEATHER", "Above the clouds: sunny all day · Below the clouds: you'll never know", Color3.fromRGB(255, 200, 90), Color3.fromRGB(200, 90, 40) },
	{ "GROVE COOKING", "Today: Mushroom Stew, the Dining Hall classic", Color3.fromRGB(240, 150, 80), Color3.fromRGB(120, 60, 30) },
}
local TRALALA = {
	{ "TRALALA NEWS", "BREAKING: Wild Tung Tungs have taken over the gym arena!", Color3.fromRGB(70, 200, 255), Color3.fromRGB(20, 50, 140) },
	{ "REEF STADIUM LIVE", "Sharks 3 - 2 Jellies · 89th minute · Corner kick!", Color3.fromRGB(80, 210, 140), Color3.fromRGB(20, 90, 80) },
	{ "TIDE REPORT", "Currents strong past the beacon towers · Stay close to campus", Color3.fromRGB(120, 230, 255), Color3.fromRGB(30, 90, 170) },
	{ "SHARK KART", "New lap record on Kelp Canyon! · Press A to race again", Color3.fromRGB(255, 120, 200), Color3.fromRGB(110, 30, 130) },
	{ "DEEP COOKING", "Today: Kelp Stew and Jelly Pudding in the Dining Hall", Color3.fromRGB(255, 170, 110), Color3.fromRGB(140, 60, 60) },
}
local CAPPUCCINO = {
	{ "CAPPUCCINO NEWS", "BREAKING: Wild challengers are sparring in the arena gym!", Color3.fromRGB(255, 170, 90), Color3.fromRGB(110, 40, 20) },
	{ "LAVA REPORT", "Volcano rumbling · Lava falls flowing · Do not swim", Color3.fromRGB(255, 110, 40), Color3.fromRGB(90, 20, 10) },
	{ "ISLAND BOWL LIVE", "Espressos 21 - 17 Mochas · 4th quarter · 2 minutes left", Color3.fromRGB(110, 200, 120), Color3.fromRGB(30, 80, 40) },
	{ "BARISTA KART", "New lap record on Volcano Run! · Press A to race again", Color3.fromRGB(255, 120, 200), Color3.fromRGB(110, 30, 90) },
	{ "BREW COOKING", "Today: Mocha Mochi and Tiramisu in the Dining Pavilion", Color3.fromRGB(230, 180, 120), Color3.fromRGB(90, 50, 30) },
}
local BALLERINA = {
	{ "BALLERINA NEWS", "BREAKING: Wild challengers spotted on the Grand Theatre stage!", Color3.fromRGB(255, 150, 210), Color3.fromRGB(130, 40, 100) },
	{ "SNOW REPORT", "Fresh powder on the peaks · Ice rink open all day · Bundle up!", Color3.fromRGB(190, 225, 255), Color3.fromRGB(70, 100, 170) },
	{ "ICE RINK LIVE", "Pirouettes 4 - 3 Pliés · Overtime · Penalty shot!", Color3.fromRGB(160, 230, 220), Color3.fromRGB(40, 110, 120) },
	{ "TUTU KART", "New lap record on Avalanche Pass! · Press A to race again", Color3.fromRGB(255, 120, 200), Color3.fromRGB(110, 30, 110) },
	{ "BALLET KITCHEN", "Today: Blini, Pelmeni and Medovik in the Dining Hall", Color3.fromRGB(255, 200, 150), Color3.fromRGB(140, 70, 70) },
}

local screens = {}
local function watch(hall: Instance, channels)
	local function track(d)
		if d:IsA("BasePart") and d:GetAttribute("TV") then
			for _, s in screens do if s.part == d then return end end
			local gui = d:FindFirstChildOfClass("SurfaceGui")
			local bg = gui and gui:FindFirstChildOfClass("Frame")
			if bg then table.insert(screens, { part = d, bg = bg, list = channels, ch = #screens % #channels + 1 }) end
		end
	end
	for _, d in hall:GetDescendants() do track(d) end
	hall.DescendantAdded:Connect(track)
end
task.spawn(function()
	local h = workspace:WaitForChild("SahurCollege"):WaitForChild("MainHall", 60)
	if h then watch(h, TUNG) end
end)
task.spawn(function()
	local h = workspace:WaitForChild("TralalaUniversity", 60)
	h = h and h:WaitForChild("MainHall", 60)
	if h then watch(h, TRALALA) end
end)
task.spawn(function()
	local h = workspace:WaitForChild("CappuccinoUniversity", 60)
	h = h and h:WaitForChild("MainHall", 60)
	if h then watch(h, CAPPUCCINO) end
end)
task.spawn(function()
	local h = workspace:WaitForChild("BallerinaAcademy", 60)
	h = h and h:WaitForChild("MainHall", 60)
	if h then watch(h, BALLERINA) end
end)

local function show(s)
	local c = s.list[s.ch]
	local title = s.bg:FindFirstChild("Title")
	local bar = s.bg:FindFirstChildOfClass("Frame")
	local ticker = bar and bar:FindFirstChild("Ticker")
	if title then title.Text = c[1] end
	if ticker then ticker.Text = c[2] end
	local grad = s.bg:FindFirstChildOfClass("UIGradient")
	if grad then grad.Color = ColorSequence.new(c[3], c[4]) end
end

local t = 0
RunService.Heartbeat:Connect(function(dt)
	t += dt
	for _, s in screens do
		local bar = s.bg:FindFirstChildOfClass("Frame")
		local ticker = bar and bar:FindFirstChild("Ticker")
		if ticker then
			bar.ClipsDescendants = true
			ticker.Size = UDim2.fromScale(2, 1)
			ticker.Position = UDim2.fromScale(1 - ((t * 0.12) % 3), 0)
		end
	end
end)
task.wait(1)
for _, s in screens do show(s) end
while true do
	task.wait(8)
	for i = #screens, 1, -1 do
		local s = screens[i]
		if s.part.Parent == nil then table.remove(screens, i) else
			s.ch = s.ch % #s.list + 1
			show(s)
		end
	end
end
