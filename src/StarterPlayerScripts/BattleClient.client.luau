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
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local BattleTypes = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("BattleTypes"))
local Combat = script.Parent:WaitForChild("Combat")
local BattleView = require(Combat:WaitForChild("BattleView"))
local UIFolder = script.Parent:WaitForChild("UI")
local Controls = require(UIFolder:WaitForChild("Core"):WaitForChild("Controls"))
local Motion = require(UIFolder:WaitForChild("Core"):WaitForChild("Motion"))
local CombatHUD = require(UIFolder:WaitForChild("Screens"):WaitForChild("CombatHUD"))

local remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Battle")
local submitActionRemote = remotes:WaitForChild("SubmitAction") :: RemoteEvent
local requestSyncRemote = remotes:WaitForChild("RequestSync") :: RemoteEvent
local stateUpdateRemote = remotes:WaitForChild("StateUpdate") :: RemoteEvent
local noticeRemote = remotes:WaitForChild("Notice") :: RemoteEvent

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

-- Roblox's backpack hotbar claims the number keys whenever a Tool is in the backpack, and the HUD
-- uses 1-5 for its commands. Nothing in the game hands out Tools, so the Backpack is off for good.
-- (If Tools ever arrive, switch it per snapshot the way Controls handles the touch controls.)
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
-- The reduced-motion setting (Roblox's switch, or a ReducedMotion attribute on the player).
Motion.start()
-- The HUD draws the enemies' plates and the party's cards itself (M0 report R19), and holds the
-- command ring while the stage is still playing a beat. Both flags are attributes on PlayerGui so
-- the headless tests can read them.
local ui: CombatHUD.CombatHUD
local view = BattleView.new({
	enemyNameplates = false,
	partyNameplates = false,
	playerGui = playerGui,
	onBusyChanged = function(busy: boolean)
		playerGui:SetAttribute("StageBusy", busy)
		if ui then
			ui:setStageBusy(busy)
		end
	end,
})
local callbacks = {
	onAction = function(abilityId: string, targetId: string) -- any move from the HUD; the server decides what happens
		view:confirm(abilityId, targetId) -- the camera reacts at once; the server's answer is what plays out
		submitActionRemote:FireServer(abilityId, targetId)
	end,
	onTargetChanged = function(targetId: string?, friendly: boolean)
		view:setTarget(targetId, friendly)
	end,
}
ui = CombatHUD.new(playerGui, localPlayer.UserId, callbacks)

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

-- The latest snapshot, kept so a respawn can be drawn again without a round trip.
local lastSnapshot: BattleTypes.Snapshot? = nil

local hudRenders = 0
local lastRendered: BattleTypes.Snapshot? = nil -- what the HUD was last given (for the masked render)
local function render(snapshot: BattleTypes.Snapshot)
	lastSnapshot = snapshot
	local mine = myBattle(snapshot)
	local impactIn = view:render(mine)
	-- The HUD's numbers (HP bars, the status line, the plates) show an action's outcome when its
	-- blow lands on the stage, not when the server's snapshot arrives; a newer snapshot cancels
	-- the wait. HudPendingUntil (server clock) tells the tests when the HUD will have caught up.
	hudRenders += 1
	local serial = hudRenders
	local previous = lastRendered
	lastRendered = snapshot
	if impactIn > 0.05 and previous and previous.battle and snapshot.battle then
		-- Meanwhile the HUD shows the new phase (the ring folds, the status says what's resolving)
		-- with the previous snapshot's numbers, statuses and log: nothing is given away early.
		local masked = table.clone(snapshot)
		local battle = table.clone(snapshot.battle :: BattleTypes.BattleState)
		battle.participants = previous.battle.participants
		battle.log = previous.battle.log
		battle.lastAction = previous.battle.lastAction
		masked.battle = battle
		ui:render(masked)
		playerGui:SetAttribute("HudPendingUntil", Workspace:GetServerTimeNow() + impactIn)
		task.delay(impactIn, function()
			if hudRenders == serial then
				playerGui:SetAttribute("HudPendingUntil", nil)
				ui:render(snapshot)
			end
		end)
	else
		playerGui:SetAttribute("HudPendingUntil", nil)
		ui:render(snapshot)
	end
	-- Touch controls off while in a fight, keyed off every snapshot (M0 report R21). (BattleView
	-- marks the player InBattle for the world's other client scripts, once the wipe covers the screen.)
	Controls.setEnabled(mine == nil)
end

stateUpdateRemote.OnClientEvent:Connect(render)

-- A fresh character (a reset mid-fight, the respawn after a loss) gets the same controls back.
-- A respawn also clears PlayerGui of everything but the opted-out ScreenGuis (the HUD's enemy
-- plates among the casualties) and the server sends nothing for it, so the last snapshot is
-- drawn again at once: the plates, and the pick being made, come straight back.
localPlayer.CharacterAdded:Connect(function()
	Controls.reapply()
	if lastSnapshot then
		render(lastSnapshot)
	end
end)

noticeRemote.OnClientEvent:Connect(function(message: string)
	ui:showNotice(message)
	view:refocus() -- a refused move: back from wherever confirm sent the camera
end)

local ownedShown = -1
RunService.Heartbeat:Connect(function(dt: number)
	view:update(dt)
	ui:tick(Workspace:GetServerTimeNow())
	local owned = view:ownedCount()
	if owned ~= ownedShown then
		ownedShown = owned
		playerGui:SetAttribute("StageOwned", owned) -- what the presentation still holds (the tests check it's nothing after a fight)
	end
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
