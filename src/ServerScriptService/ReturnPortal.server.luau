-- Portals home: touching any part tagged "ReturnToLobby" (the little portal on the grass, the one by the
-- college gate) sends you back to the lobby.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ZoneTravel = require(script.Parent:WaitForChild("ZoneTravel"))
local PortalMessage = ReplicatedStorage:WaitForChild("LobbyEvents"):WaitForChild("PortalMessage")

local cooldown = {}

local function hook(surface: Instance)
	if not surface:IsA("BasePart") then return end
	surface.CanTouch = true
	surface.Touched:Connect(function(hit)
		local char = hit:FindFirstAncestorOfClass("Model")
		local player = char and Players:GetPlayerFromCharacter(char)
		if not player or cooldown[player] then return end
		cooldown[player] = true
		task.delay(3, function() cooldown[player] = nil end)
		PortalMessage:FireClient(player, "Lobby", "Heading home...")
		ZoneTravel.toLobby(player)
	end)
end
for _, s in CollectionService:GetTagged("ReturnToLobby") do hook(s) end
CollectionService:GetInstanceAddedSignal("ReturnToLobby"):Connect(hook)

Players.PlayerRemoving:Connect(function(p) cooldown[p] = nil end)
