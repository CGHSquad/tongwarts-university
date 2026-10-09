--[[
	TralalaServer — keeps swimmers at Tralala Tralalero University (Workspace.TralalaUniversity), the
	underwater campus at the bottom of its sea.

	The campus sits in real terrain water: the domed Dorms, Dining Hall and Gym, the Main Building, the
	domed Library are dry inside (carved out as air); the courtyard and everywhere else
	is open sea, so you swim between buildings. Anyone who swims too far up toward the
	surface, too far out past the campus, or somehow ends up under the seabed is pulled back to the
	arrival dome's spawn circle.

	Beds, food, the gym sparring partners and AFK tags are shared with the Tung Tung campus
	(CampusServer, Overworld.EnemySpawns).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ZoneTravel = require(script.Parent:WaitForChild("ZoneTravel"))
local PortalMessage = ReplicatedStorage:WaitForChild("LobbyEvents"):WaitForChild("PortalMessage")

local uni = workspace:WaitForChild("TralalaUniversity")
local CENTER: Vector3 = uni:GetAttribute("Center") or Vector3.new(-4000, 100.6, 0)
local MIDDLE = CENTER + Vector3.new(0, 0, 30) -- middle of the valley (the campus spreads a little south)

local AREA = 900 -- anyone this close (across the ground) counts as being at the university
local MAX_OUT = 620 -- swim further out than this and the current brings you back (the library sits ~600 out)
local MAX_UP = 215 -- studs above the campus floor (the surface is 255 up)
local MIN_DOWN = -45 -- under the seabed

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.25 then return end
	acc = 0
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 then
			local rel = root.Position - MIDDLE
			local out = Vector3.new(rel.X, 0, rel.Z).Magnitude
			if out < AREA then
				local why = nil
				if rel.Y > MAX_UP then
					why = "You swam too close to the surface!"
				elseif out > MAX_OUT then
					why = "The current carried you back to campus"
				elseif rel.Y < MIN_DOWN then
					why = "Back to campus"
				end
				if why then
					PortalMessage:FireClient(player, "Tralala Tralalero University", why)
					ZoneTravel.toTralala(player)
				end
			end
		end
	end
end)
