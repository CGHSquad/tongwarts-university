-- ZoneTravel: moves a player between the lobby and the overworld (both live in this one place).
-- The screen fades out, the area around the destination is streamed in, the character is moved,
-- and the screen fades back in. Server-only.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local events = ReplicatedStorage:WaitForChild("LobbyEvents")
local ZoneFade = events:WaitForChild("ZoneFade")
local Summon = events:WaitForChild("Summon")

local lobby = workspace:WaitForChild("CaveLobby")
local circle = lobby:WaitForChild("SpawnPad"):WaitForChild("SpawnCircle")
local arrival = workspace:WaitForChild("OverworldArrival")
local overworldCircle = workspace:WaitForChild("OverworldSpawnPad"):WaitForChild("SpawnCircle")

local FADE_SECONDS = 0.35

local ZoneTravel = {}
local busy: { [Player]: boolean } = {}

local function move(player: Player, target: CFrame): Model?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (char and hrp) or busy[player] then return nil end
	busy[player] = true
	ZoneFade:FireClient(player, FADE_SECONDS)
	pcall(function() player:RequestStreamAroundAsync(target.Position) end)
	task.wait(FADE_SECONDS)
	if char.Parent then
		hrp.AssemblyLinearVelocity = Vector3.zero
		char:PivotTo(target)
	end
	task.delay(1, function() busy[player] = nil end)
	return char
end

-- Out to the grass, standing on the overworld's magic circle and looking out toward the tung tungs (+X).
function ZoneTravel.toOverworld(player: Player)
	local pos = arrival.Position + Vector3.new(0, 4, 0)
	local char = move(player, CFrame.lookAt(pos, pos + Vector3.new(1, 0, 0)))
	if char then
		Summon:FireAllClients(char, overworldCircle.Position)
	end
end

-- Up to the college's sky island, onto the magic circle by the front gate, facing the gate.
function ZoneTravel.toCampus(player: Player)
	local college = workspace:FindFirstChild("SahurCollege")
	local pad = college and college:FindFirstChild("CampusSpawnPad")
	local circle2 = pad and pad:FindFirstChild("SpawnCircle")
	if not circle2 then return end
	local pos = circle2.Position + Vector3.new(0, 3.2, 0)
	local char = move(player, CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1)))
	if char then
		Summon:FireAllClients(char, circle2.Position)
	end
end

-- Down to Tralala Tralalero University at the bottom of the sea: onto the magic circle in the arrival
-- dome, facing the tunnel to the courtyard.
function ZoneTravel.toTralala(player: Player)
	local uni = workspace:FindFirstChild("TralalaUniversity")
	local arrival = uni and uni:FindFirstChild("Arrival")
	local pad = arrival and arrival:FindFirstChild("TralalaSpawnPad")
	local circle3 = pad and pad:FindFirstChild("SpawnCircle")
	if not circle3 then return end
	local pos = circle3.Position + Vector3.new(0, 3.2, 0)
	local char = move(player, CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1)))
	if char then
		Summon:FireAllClients(char, circle3.Position)
	end
end

-- To Cappuccino Assassino University on its basalt mesas over the lava: onto the magic circle in the
-- arrival court, facing north toward the courtyard and the volcano.
function ZoneTravel.toCappuccino(player: Player)
	local uni = workspace:FindFirstChild("CappuccinoUniversity")
	local arrival = uni and uni:FindFirstChild("Arrival")
	local pad = arrival and arrival:FindFirstChild("CappuccinoSpawnPad")
	local circle4 = pad and pad:FindFirstChild("SpawnCircle")
	if not circle4 then return end
	local pos = circle4.Position + Vector3.new(0, 3.2, 0)
	local char = move(player, CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1)))
	if char then
		Summon:FireAllClients(char, circle4.Position)
	end
end

-- Cappuccino Ballerina Academy: onto its spawn circle on the mountainside ledge, facing the gate and the academy.
function ZoneTravel.toBallerina(player: Player)
	local uni = workspace:FindFirstChild("BallerinaAcademy")
	local arrival = uni and uni:FindFirstChild("Arrival")
	local pad = arrival and arrival:FindFirstChild("BallerinaSpawnPad")
	local circle5 = pad and pad:FindFirstChild("SpawnCircle")
	if not circle5 then return end
	local pos = circle5.Position + Vector3.new(0, 3.2, 0)
	local char = move(player, CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1)))
	if char then
		Summon:FireAllClients(char, circle5.Position)
	end
end

-- Back to the lobby, onto the magic circle, with the circle's summoning effect.
function ZoneTravel.toLobby(player: Player)
	local center = lobby:GetAttribute("Center") or Vector3.zero
	local pos = circle.Position + Vector3.new(0, 3.2, 0)
	local char = move(player, CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z)))
	if char then
		Summon:FireAllClients(char, circle.Position)
	end
end

Players.PlayerRemoving:Connect(function(p) busy[p] = nil end)

return ZoneTravel
