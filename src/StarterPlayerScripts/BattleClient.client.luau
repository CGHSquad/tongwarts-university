--!strict
--[[
	BattleClient — client entry point for the combat prototype.

	The client renders and requests, nothing more (GDD Step 5): every StateUpdate from the server
	is the whole truth and gets drawn as-is, and the buttons only send requests (SubmitAction) that
	the server validates and resolves. Fights start on the server too, when your character walks
	into an overworld enemy; only the players in a fight see it.

	Flags.NewHud picks the HUD: the new one (UI/Screens/CombatHUD) or the old BattleUI, until the
	new one reaches parity and the old one goes (docs/ui/M0_REPORT.md, Q1).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BattleTypes = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("BattleTypes"))
local Flags = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Flags"))
local Combat = script.Parent:WaitForChild("Combat")
local BattleUI = require(Combat:WaitForChild("BattleUI"))
local BattleView = require(Combat:WaitForChild("BattleView"))
local UIFolder = script.Parent:WaitForChild("UI")
local Controls = require(UIFolder:WaitForChild("Core"):WaitForChild("Controls"))
local CombatHUD = require(UIFolder:WaitForChild("Screens"):WaitForChild("CombatHUD"))

local remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Battle")
local submitActionRemote = remotes:WaitForChild("SubmitAction") :: RemoteEvent
local requestSyncRemote = remotes:WaitForChild("RequestSync") :: RemoteEvent
local stateUpdateRemote = remotes:WaitForChild("StateUpdate") :: RemoteEvent
local noticeRemote = remotes:WaitForChild("Notice") :: RemoteEvent

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
-- The new HUD draws the enemies' plates itself (M0 report R19).
local view = BattleView.new({ enemyNameplates = not Flags.NewHud })
local callbacks = {
	onAction = function(abilityId: string, targetId: string) -- any move from the HUD; the server decides what happens
		submitActionRemote:FireServer(abilityId, targetId)
	end,
	onTargetChanged = function(targetId: string?, friendly: boolean)
		view:setTarget(targetId, friendly)
	end,
}
local ui: CombatHUD.Hud = if Flags.NewHud
	then (CombatHUD.new(playerGui, localPlayer.UserId, callbacks) :: any)
	else (BattleUI.new(playerGui, localPlayer.UserId, callbacks) :: any)

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
	local mine = myBattle(snapshot)
	view:render(mine)
	ui:render(snapshot)
	-- Touch controls off while in a fight, keyed off every snapshot (M0 report R21).
	Controls.setEnabled(mine == nil)
end)

-- A fresh character (a reset mid-fight, the respawn after a loss) gets the same controls back.
localPlayer.CharacterAdded:Connect(function()
	Controls.reapply()
end)

noticeRemote.OnClientEvent:Connect(function(message: string)
	ui:showNotice(message)
end)

RunService.Heartbeat:Connect(function()
	ui:tick(Workspace:GetServerTimeNow())
end)

-- The overworld panel pops up for a few seconds each time you arrive on the grass (ZoneClient sets "Zone").
local OVERWORLD_BANNER_SECONDS = 6
local function onZone()
	if localPlayer:GetAttribute("Zone") == "Overworld" then
		ui:showOverworldBanner(OVERWORLD_BANNER_SECONDS)
	end
end
localPlayer:GetAttributeChangedSignal("Zone"):Connect(onZone)
onZone()

-- Ask for the current state now that we're listening (a battle may already be running).
requestSyncRemote:FireServer()
