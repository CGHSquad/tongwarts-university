--!strict
--[[
	BattleView — the 3D side of the prototype: one colored block per summon, an outline on whoever
	is acting and on your chosen target, a small hit effect, and a fixed battle camera.

	Everything here exists only on this client and is redrawn from server snapshots: the blocks are
	a picture of the BattleSession, not the real thing. Swapping them for real summon models later
	won't touch any combat code.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local BattleTypes = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("BattleTypes"))
local BattleTheme = require(script.Parent:WaitForChild("BattleTheme"))

type BattleState = BattleTypes.BattleState
type ParticipantState = BattleTypes.ParticipantState

-- The stage sits in front of the spawn point. The camera looks across it with the party on the
-- left and the enemies on the right, matching the HUD panels.
local STAGE_CENTER = Vector3.new(0, 0, -60)
local BLOCK_SIZE = Vector3.new(5, 5, 5)
local CAMERA_POSITION = STAGE_CENTER + Vector3.new(0, 20, 40)
local CAMERA_FOCUS = STAGE_CENTER + Vector3.new(0, 3, 0)

type Block = {
	part: Part,
	home: CFrame,
	highlight: Highlight,
	hpLabel: TextLabel,
}

local BattleView = {}
BattleView.__index = BattleView

type ViewFields = {
	folder: Folder?,
	blocks: { [string]: Block },
	battle: BattleState?,
	lastActionSeen: number,
	targetId: string?,
	cameraActive: boolean,
}

export type BattleView = typeof(setmetatable({} :: ViewFields, BattleView))

-- Slot 2 stands further out and nearer the camera so the two blocks on a side don't overlap.
local function slotCFrame(side: string, slot: number): CFrame
	local direction = if side == "Party" then -1 else 1
	local position = STAGE_CENTER + Vector3.new(direction * (9 + (slot - 1) * 5), BLOCK_SIZE.Y / 2, (slot - 1.5) * 10)
	return CFrame.lookAt(position, position - Vector3.new(direction, 0, 0)) -- face the other side
end

local function newBillboardLabel(parent: Instance, size: UDim2, position: UDim2, font: Enum.Font): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextScaled = true
	label.TextColor3 = BattleTheme.Text
	label.TextStrokeTransparency = 0.2
	label.Parent = parent
	return label
end

local function createBlock(participant: ParticipantState, parent: Instance): Block
	local home = slotCFrame(participant.side, participant.slot)

	local part = Instance.new("Part")
	part.Name = participant.id
	part.Size = BLOCK_SIZE
	part.CFrame = home
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = BattleTheme.colorFor(participant.side, participant.slot)

	local highlight = Instance.new("Highlight")
	highlight.Adornee = part
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.OutlineTransparency = 0
	highlight.Enabled = false
	highlight.Parent = part

	local nameplate = Instance.new("BillboardGui")
	nameplate.Name = "Nameplate"
	nameplate.Adornee = part
	nameplate.Size = UDim2.fromOffset(180, 44)
	nameplate.StudsOffset = Vector3.new(0, BLOCK_SIZE.Y / 2 + 1.8, 0)
	nameplate.AlwaysOnTop = true
	nameplate.LightInfluence = 0
	nameplate.Parent = part

	local nameLabel = newBillboardLabel(nameplate, UDim2.fromScale(1, 0.55), UDim2.fromScale(0, 0), BattleTheme.FontBold)
	nameLabel.Text = participant.name
	local hpLabel = newBillboardLabel(nameplate, UDim2.fromScale(1, 0.45), UDim2.fromScale(0, 0.55), BattleTheme.Font)

	part.Parent = parent
	return { part = part, home = home, highlight = highlight, hpLabel = hpLabel }
end

function BattleView.new(): BattleView
	local fields: ViewFields = {
		folder = nil,
		blocks = {},
		battle = nil,
		lastActionSeen = 0,
		targetId = nil,
		cameraActive = false,
	}
	return setmetatable(fields, BattleView)
end

-- Draws the latest battle state (nil = no battle running).
function BattleView.render(self: BattleView, battle: BattleState?)
	local previous = self.battle
	self.battle = battle
	if battle == nil then
		self:_clear()
		self:_setBattleCamera(false)
		return
	end

	if previous == nil or previous.battleId ~= battle.battleId or self.folder == nil then
		self:_build(battle)
	end
	self:_setBattleCamera(true)
	self:_refreshBlocks()

	local action = battle.lastAction
	if action ~= nil and action.sequence > self.lastActionSeen then
		self.lastActionSeen = action.sequence
		self:_playAction(action)
	end
end

-- Outlines the target you've picked in the HUD (nil clears it).
function BattleView.setTarget(self: BattleView, targetId: string?)
	if self.targetId == targetId then
		return
	end
	self.targetId = targetId
	self:_refreshBlocks()
end

function BattleView._build(self: BattleView, battle: BattleState)
	self:_clear()
	local folder = Instance.new("Folder")
	folder.Name = "BattleStage"
	for _, participant in battle.participants do
		self.blocks[participant.id] = createBlock(participant, folder)
	end
	folder.Parent = Workspace
	self.folder = folder
	-- Don't replay an action that happened before this client started watching.
	self.lastActionSeen = if battle.lastAction then battle.lastAction.sequence else 0
end

function BattleView._clear(self: BattleView)
	if self.folder then
		self.folder:Destroy()
		self.folder = nil
	end
	table.clear(self.blocks)
end

function BattleView._refreshBlocks(self: BattleView)
	local battle = self.battle
	if battle == nil then
		return
	end

	for _, participant in battle.participants do
		local block = self.blocks[participant.id]
		if block == nil then
			continue
		end

		if participant.status == "KnockedOut" then
			block.part.Color = BattleTheme.KnockedOut
			block.part.Transparency = 0.35
			block.hpLabel.Text = "Knocked out"
		elseif participant.status == "Left" then
			block.part.Color = BattleTheme.colorFor(participant.side, participant.slot)
			block.part.Transparency = 0.75
			block.hpLabel.Text = "Left the battle"
		else
			block.part.Color = BattleTheme.colorFor(participant.side, participant.slot)
			block.part.Transparency = 0
			block.hpLabel.Text = `HP {participant.hp}/{participant.maxHp}`
		end

		local acting = battle.phase == "input" and battle.currentActorId == participant.id
		if acting then
			block.highlight.OutlineColor = BattleTheme.Accent
			block.highlight.FillTransparency = 1
			block.highlight.Enabled = true
		elseif self.targetId == participant.id then
			block.highlight.OutlineColor = BattleTheme.Danger
			block.highlight.FillColor = BattleTheme.Danger
			block.highlight.FillTransparency = 0.6
			block.highlight.Enabled = true
		else
			block.highlight.Enabled = false
		end
	end
end

-- The attacker lunges, the target recoils, and the damage number floats up.
function BattleView._playAction(self: BattleView, action: BattleTypes.ActionRecord)
	local attacker = self.blocks[action.actorId]
	local target = self.blocks[action.targetId]
	if attacker == nil or target == nil then
		return
	end

	local toward = (target.home.Position - attacker.home.Position).Unit
	attacker.part.CFrame = attacker.home
	TweenService:Create(
		attacker.part,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true),
		{ CFrame = attacker.home + toward * 4 }
	):Play()

	target.part.CFrame = target.home
	TweenService:Create(
		target.part,
		TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true, 0.12),
		{ CFrame = target.home + toward * 1.5 }
	):Play()

	local popup = Instance.new("BillboardGui")
	popup.Name = "DamagePopup"
	popup.Adornee = target.part
	popup.Size = UDim2.fromOffset(120, 40)
	popup.StudsOffset = Vector3.zero
	popup.AlwaysOnTop = true
	popup.LightInfluence = 0
	local label = newBillboardLabel(popup, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), BattleTheme.FontHeavy)
	label.Text = `-{action.damage}`
	label.TextColor3 = if action.knockedOut then BattleTheme.Danger else BattleTheme.Text
	popup.Parent = target.part

	local rise = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(popup, rise, { StudsOffset = Vector3.new(0, 3.5, 0) }):Play()
	TweenService:Create(label, rise, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(popup, 1)
end

function BattleView._setBattleCamera(self: BattleView, active: boolean)
	if self.cameraActive == active then
		return
	end
	self.cameraActive = active

	local camera = Workspace.CurrentCamera
	if active then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(CAMERA_POSITION, CAMERA_FOCUS)
	else
		camera.CameraType = Enum.CameraType.Custom
	end
end

return BattleView
