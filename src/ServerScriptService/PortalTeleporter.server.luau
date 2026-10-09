-- Touching any part named "PortalSurface" inside CaveLobby sends the player to that portal's place.
-- The "Overworld" portal is different: it walks the player out to the grass area of this place (ZoneTravel).
-- Set the PlaceId attribute on a PortalSurface to hook it up. PlaceId 0 = "coming soon".
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PortalMessage = ReplicatedStorage:WaitForChild("LobbyEvents"):WaitForChild("PortalMessage")
local lobby = workspace:WaitForChild("CaveLobby")
local ZoneTravel = require(script.Parent:WaitForChild("ZoneTravel"))
local cooldown = {}

local function bounce(hrp, portal)
	local center = lobby:GetAttribute("Center") or Vector3.zero
	local away = Vector3.new(center.X - portal.Position.X, 0, center.Z - portal.Position.Z)
	if away.Magnitude < 0.1 then away = -portal.CFrame.LookVector end
	hrp.AssemblyLinearVelocity = away.Unit * 45 + Vector3.new(0, 35, 0)
end

local function onTouched(portal, hit)
	local char = hit:FindFirstAncestorOfClass("Model")
	local player = char and Players:GetPlayerFromCharacter(char)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (player and hrp) or cooldown[player] then return end
	cooldown[player] = true
	task.delay(3, function() cooldown[player] = nil end)
	local name = portal:GetAttribute("Destination") or "This portal"
	local placeId = portal:GetAttribute("PlaceId") or 0
	if name == "TungTungTungSahurCollege" then
		-- The college campus is in this same place, up on its sky island.
		PortalMessage:FireClient(player, "Tung Tung Tung Sahur College", "Travelling...")
		ZoneTravel.toCampus(player)
		return
	end
	if name == "TralalaTralaleroUniversity" then
		-- The underwater university is in this same place too, at the bottom of its sea.
		PortalMessage:FireClient(player, "Tralala Tralalero University", "Diving down...")
		ZoneTravel.toTralala(player)
		return
	end
	if name == "CappuccinoAssassinoUniversity" then
		-- The volcano university is in this same place as well, on its basalt mesas over the lava.
		PortalMessage:FireClient(player, "Cappuccino Assassino University", "Brewing...")
		ZoneTravel.toCappuccino(player)
		return
	end
	if name == "CappuccinoBallerinaAcademy" then
		-- The ballet academy is in this same place too, on a ledge high on its snowy mountainside.
		PortalMessage:FireClient(player, "Cappuccino Ballerina Academy", "Pirouetting...")
		ZoneTravel.toBallerina(player)
		return
	end
	if name == "Overworld" then
		-- The overworld is in this same place: walk through and you're on the grass.
		PortalMessage:FireClient(player, name, "Travelling...")
		ZoneTravel.toOverworld(player)
		return
	end
	if placeId > 0 then
		if RunService:IsStudio() then
			PortalMessage:FireClient(player, name, "Teleports only work in the live game")
			bounce(hrp, portal)
			return
		end
		PortalMessage:FireClient(player, name, "Travelling...")
		local ok, err = pcall(function() TeleportService:TeleportAsync(placeId, {player}) end)
		if not ok then
			warn("Portal teleport failed:", err)
			PortalMessage:FireClient(player, name, "The portal flickered... try again")
			bounce(hrp, portal)
		end
	else
		PortalMessage:FireClient(player, name, "Coming soon!")
		bounce(hrp, portal)
	end
end

local function hook(d)
	if d:IsA("BasePart") and d.Name == "PortalSurface" then
		d.CanTouch = true
		d.Touched:Connect(function(hit) onTouched(d, hit) end)
	end
end
for _, d in ipairs(lobby:GetDescendants()) do hook(d) end
lobby.DescendantAdded:Connect(hook)
