--!strict
--[[
	BattleServer — the server's network edge for the combat prototype.

	Wires Players and the Battle RemoteEvents (ReplicatedStorage.Remotes.Battle, declared in
	default.project.json) to the BattleDirector.

	Everything a client sends is untrusted. Arguments are type-checked here, then BattleSession
	checks the action itself: is it that player's turn, do they have the Mana, is the target legal.
	Clients only ever request; the server decides every outcome.

		client -> server   SetReady(ready: boolean)
		                   SubmitAction(abilityId: string, targetId: string)
		                   RequestSync()      -- "send me the current state" (on client start)
		server -> client   StateUpdate(snapshot: BattleTypes.Snapshot)
		                   Notice(message: string)   -- why a request was refused
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BattleDirector = require(script.Parent.Combat.BattleDirector)

local remotes = ReplicatedStorage.Remotes.Battle
local setReadyRemote = remotes.SetReady :: RemoteEvent
local submitActionRemote = remotes.SubmitAction :: RemoteEvent
local requestSyncRemote = remotes.RequestSync :: RemoteEvent
local stateUpdateRemote = remotes.StateUpdate :: RemoteEvent
local noticeRemote = remotes.Notice :: RemoteEvent

local director = BattleDirector.new({
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

setReadyRemote.OnServerEvent:Connect(function(player, ready)
	if typeof(ready) ~= "boolean" then
		return
	end
	director:setReady(player.UserId, ready)
end)

submitActionRemote.OnServerEvent:Connect(function(player, abilityId, targetId)
	if typeof(abilityId) ~= "string" or typeof(targetId) ~= "string" then
		return
	end
	director:submitAction(player.UserId, abilityId, targetId)
end)

requestSyncRemote.OnServerEvent:Connect(function(player)
	stateUpdateRemote:FireClient(player, director:getSnapshot())
end)
