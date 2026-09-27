--!strict
--[[
	BattleServer — the server's entry point: connects the overworld, the battles and the network.

	- Players and the Battle RemoteEvents (ReplicatedStorage.Remotes.Battle, declared in
	  default.project.json) go to the BattleDirector.
	- The Overworld's enemies start fights: walking into one calls BattleDirector.startEncounter,
	  with who struck first worked out by Encounter. When the fight is over, the director tells the
	  Overworld, which frees the party and deals with the enemy.

	Everything a client sends is untrusted. Arguments are type-checked here, then BattleSession
	checks the action itself: is it that player's turn, do they have the Mana, is the target legal.
	Clients only ever request; the server decides every outcome. (Fights start from where
	characters are on the server, which Roblox replicates from each player's own client.)

		client -> server   SubmitAction(abilityId: string, targetId: string)
		                   RequestSync()      -- "send me the current state" (on client start)
		server -> client   StateUpdate(snapshot: BattleTypes.Snapshot)
		                   Notice(message: string)   -- why a request was refused
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage.Combat.CombatConfig)
local BattleDirector = require(script.Parent.Combat.BattleDirector)
local Encounter = require(script.Parent.Overworld.Encounter)
local Overworld = require(script.Parent.Overworld.Overworld)

local remotes = ReplicatedStorage.Remotes.Battle
local submitActionRemote = remotes.SubmitAction :: RemoteEvent
local requestSyncRemote = remotes.RequestSync :: RemoteEvent
local stateUpdateRemote = remotes.StateUpdate :: RemoteEvent
local noticeRemote = remotes.Notice :: RemoteEvent

local director: BattleDirector.BattleDirector

local overworld = Overworld.new(function(userId, spawn, contact)
	return director:startEncounter(userId, {
		enemies = spawn.enemies or CombatConfig.EnemySummons,
		opening = Encounter.openingFor(contact),
	})
end)

director = BattleDirector.new({
	now = function()
		return Workspace:GetServerTimeNow()
	end,
	delay = function(seconds, callback)
		task.delay(seconds, callback)
	end,
	rng = Random.new(),
	broadcast = function(snapshot)
		stateUpdateRemote:FireAllClients(snapshot)
	end,
	notify = function(userId, message)
		local player = Players:GetPlayerByUserId(userId)
		if player then
			noticeRemote:FireClient(player, message)
		end
	end,
	battleEnded = function(winner)
		overworld:endBattle(winner)
	end,
})

local function onPlayerAdded(player: Player)
	director:playerJoined(player.UserId, player.DisplayName)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	director:playerLeft(player.UserId)
end)
-- Anyone who joined before this script started running (common in Studio playtests).
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

submitActionRemote.OnServerEvent:Connect(function(player, abilityId, targetId)
	if typeof(abilityId) ~= "string" or typeof(targetId) ~= "string" then
		return
	end
	director:submitAction(player.UserId, abilityId, targetId)
end)

requestSyncRemote.OnServerEvent:Connect(function(player)
	stateUpdateRemote:FireClient(player, director:getSnapshot())
end)

overworld:start()
