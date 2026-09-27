--!strict
--[[
	BattleClient — client entry point for the combat prototype.

	The client renders and requests, nothing more (GDD Step 5): every StateUpdate from the server
	is the whole truth and gets drawn as-is, and the buttons only send requests (SubmitAction) that
	the server validates and resolves. Fights start on the server too, when your character walks
	into an overworld enemy; only the players in a fight see it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BattleTypes = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("BattleTypes"))
local Combat = script.Parent:WaitForChild("Combat")
local BattleUI = require(Combat:WaitForChild("BattleUI"))
local BattleView = require(Combat:WaitForChild("BattleView"))

local remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Battle")
local submitActionRemote = remotes:WaitForChild("SubmitAction") :: RemoteEvent
local requestSyncRemote = remotes:WaitForChild("RequestSync") :: RemoteEvent
local stateUpdateRemote = remotes:WaitForChild("StateUpdate") :: RemoteEvent
local noticeRemote = remotes:WaitForChild("Notice") :: RemoteEvent

local localPlayer = Players.LocalPlayer
local view = BattleView.new()
local ui = BattleUI.new(localPlayer:WaitForChild("PlayerGui") :: PlayerGui, localPlayer.UserId, {
	onAction = function(abilityId, targetId) -- an ability or Guard; the server decides what happens
		submitActionRemote:FireServer(abilityId, targetId)
	end,
	onTargetChanged = function(targetId, friendly)
		view:setTarget(targetId, friendly)
	end,
})

-- The battle, if this player is in it.
local function myBattle(snapshot: BattleTypes.Snapshot): BattleTypes.BattleState?
	local battle = snapshot.battle
	if battle then
		for _, participant in battle.participants do
			if participant.ownerUserId == localPlayer.UserId then
				return battle
			end
		end
	end
	return nil
end

stateUpdateRemote.OnClientEvent:Connect(function(snapshot: BattleTypes.Snapshot)
	view:render(myBattle(snapshot))
	ui:render(snapshot)
end)

noticeRemote.OnClientEvent:Connect(function(message: string)
	ui:showNotice(message)
end)

RunService.Heartbeat:Connect(function()
	ui:tick(Workspace:GetServerTimeNow())
end)

-- Ask for the current state now that we're listening (a battle may already be running).
requestSyncRemote:FireServer()
