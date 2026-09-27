--!strict
--[[
	BattleUI — the bare-bones combat HUD, built in code.

		lobby    who's here and who's ready, the Ready button, the start countdown
		battle   whose turn it is (with that player's time left), the turn order with initiative
		         totals, HP and Mana bars for every summon, and on your turn the ability buttons
		         (plus Guard, which every summon has), target picker and Attack button. Plus a
		         combat log and a victory/defeat screen.

	It renders server snapshots and nothing else. The only thing it remembers is the choice you're
	making right now (ability + target); Attack sends that choice to the server, which decides what
	happens. The client never computes an outcome.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Abilities = require(Combat:WaitForChild("Abilities"))
local BattleTypes = require(Combat:WaitForChild("BattleTypes"))
local CombatConfig = require(Combat:WaitForChild("CombatConfig"))
local StatusEffects = require(Combat:WaitForChild("StatusEffects"))
local Summons = require(Combat:WaitForChild("Summons"))
local BattleTheme = require(script.Parent:WaitForChild("BattleTheme"))

type Snapshot = BattleTypes.Snapshot
type BattleState = BattleTypes.BattleState
type LobbyState = BattleTypes.LobbyState
type ParticipantState = BattleTypes.ParticipantState

export type Callbacks = {
	onReadyChanged: (ready: boolean) -> (),
	onAction: (abilityId: string, targetId: string) -> (), -- an ability, or Guard
	onTargetChanged: (targetId: string?, friendly: boolean) -> (), -- friendly = picking an ally
}

-- The layout is designed at this size and scaled to fit smaller windows (like two Studio test
-- clients side by side).
local DESIGN_SIZE = Vector2.new(1280, 720)
local NOTICE_SECONDS = 3
local ACTION_PANEL_WIDTH = 520
local ACTION_PANEL_PADDING = 12

-- Guard is in no summon's ability list: every summon can use it (see Abilities), so it gets its
-- own button after the summon's abilities.
local GUARD = Abilities.Guard

-- What guarding does, from CombatConfig, so the button's explanation stays true when it's tuned.
local function describeGuard(): string
	local damage = math.round(CombatConfig.GuardDamageReduction * 100)
	local ailments = math.round((1 - CombatConfig.GuardAilmentChanceMultiplier) * 100)
	return `Until its next turn: {damage}% less damage, no critical hits, ailments {ailments}% less likely. `
		.. `+{CombatConfig.GuardManaBonus} Mana if it gets attacked.`
end

--[[ Small builders, so the layout code below stays readable ]]

local function addCorner(parent: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function addPadding(parent: GuiObject, pixels: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, pixels)
	padding.PaddingBottom = UDim.new(0, pixels)
	padding.PaddingLeft = UDim.new(0, pixels)
	padding.PaddingRight = UDim.new(0, pixels)
	padding.Parent = parent
end

local function addList(parent: GuiObject, direction: Enum.FillDirection, spacing: number): UIListLayout
	local list = Instance.new("UIListLayout")
	list.FillDirection = direction
	list.Padding = UDim.new(0, spacing)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = parent
	return list
end

local function addStroke(parent: GuiObject, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = parent
	return stroke
end

-- A dark rounded panel.
local function newPanel(parent: Instance, name: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = BattleTheme.Panel
	frame.BackgroundTransparency = BattleTheme.PanelTransparency
	frame.BorderSizePixel = 0
	frame.Parent = parent
	addCorner(frame, 10)
	return frame
end

-- An invisible frame, only there for layout.
local function newContainer(parent: Instance, name: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

-- A full-width label that grows taller if its text wraps.
local function newLabel(parent: Instance, text: string, textSize: number, font: Enum.Font?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, textSize + 6)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Font = font or BattleTheme.Font
	label.TextSize = textSize
	label.TextColor3 = BattleTheme.Text
	label.TextWrapped = true
	label.Text = text
	label.Parent = parent
	return label
end

local function newButton(parent: Instance, text: string, size: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Size = size
	button.BackgroundColor3 = BattleTheme.Button
	button.BorderSizePixel = 0
	button.Font = BattleTheme.FontBold
	button.TextSize = 17
	button.TextColor3 = BattleTheme.ButtonText
	button.Text = text
	button.Parent = parent
	addCorner(button, 8)
	return button
end

type ButtonLook = "normal" | "selected" | "target" | "ally" | "attack" | "disabled"

local function styleButton(button: TextButton, look: ButtonLook)
	button.Interactable = look ~= "disabled"
	button.AutoButtonColor = look ~= "disabled"
	if look == "selected" then
		button.BackgroundColor3 = BattleTheme.ButtonSelected
		button.TextColor3 = BattleTheme.ButtonSelectedText
	elseif look == "target" then
		button.BackgroundColor3 = BattleTheme.Danger
		button.TextColor3 = BattleTheme.ButtonSelectedText
	elseif look == "ally" then
		button.BackgroundColor3 = BattleTheme.HealthBar
		button.TextColor3 = BattleTheme.ButtonSelectedText
	elseif look == "attack" then
		button.BackgroundColor3 = BattleTheme.AttackButton
		button.TextColor3 = BattleTheme.ButtonText
	elseif look == "disabled" then
		button.BackgroundColor3 = BattleTheme.ButtonDisabled
		button.TextColor3 = BattleTheme.ButtonDisabledText
	else
		button.BackgroundColor3 = BattleTheme.Button
		button.TextColor3 = BattleTheme.ButtonText
	end
end

-- A resource bar with its value written on top. Returns the fill (sized by fraction) and the text.
local function newBar(parent: Instance, color: Color3, layoutOrder: number): (Frame, TextLabel)
	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, 0, 0, 16)
	back.BackgroundColor3 = BattleTheme.BarBackground
	back.BorderSizePixel = 0
	back.LayoutOrder = layoutOrder
	back.Parent = parent
	addCorner(back, 4)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back
	addCorner(fill, 4)

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = BattleTheme.FontBold
	text.TextSize = 13
	text.TextColor3 = BattleTheme.Text
	text.TextStrokeTransparency = 0.4
	text.ZIndex = 2
	text.Parent = back
	return fill, text
end

local function fraction(value: number, max: number): number
	if max <= 0 then
		return 0
	end
	return math.clamp(value / max, 0, 1)
end

local function secondsLeft(deadline: number, now: number): number
	return math.max(0, math.ceil(deadline - now))
end

--[[ Per-battle widgets ]]

type Row = {
	frame: Frame,
	stroke: UIStroke,
	swatch: Frame,
	statusLabel: TextLabel,
	ownerLabel: TextLabel,
	hpFill: Frame,
	hpText: TextLabel,
	manaFill: Frame,
	manaText: TextLabel,
	effectsLabel: TextLabel,
}

type Chip = {
	frame: Frame,
	stroke: UIStroke,
	label: TextLabel,
}

-- One summon's card in the party/enemy panel: name, controller and role, HP bar, Mana bar, and
-- any status effects.
local function createRow(parent: Instance, participant: ParticipantState): Row
	local frame = Instance.new("Frame")
	frame.Name = participant.id
	frame.Size = UDim2.fromScale(1, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = BattleTheme.Button
	frame.BorderSizePixel = 0
	frame.LayoutOrder = participant.slot
	frame.Parent = parent
	addCorner(frame, 8)
	addPadding(frame, 8)
	addList(frame, Enum.FillDirection.Vertical, 4)
	local stroke = addStroke(frame, BattleTheme.Accent, 3)
	stroke.Enabled = false

	local nameLine = newContainer(frame, "NameLine")
	nameLine.Size = UDim2.new(1, 0, 0, 22)
	nameLine.LayoutOrder = 1

	local swatch = Instance.new("Frame")
	swatch.AnchorPoint = Vector2.new(0, 0.5)
	swatch.Position = UDim2.fromScale(0, 0.5)
	swatch.Size = UDim2.fromOffset(14, 14)
	swatch.BackgroundColor3 = BattleTheme.colorFor(participant.side, participant.slot)
	swatch.BorderSizePixel = 0
	swatch.Parent = nameLine
	addCorner(swatch, 3)

	local nameLabel = newLabel(nameLine, participant.name, 16, BattleTheme.FontBold)
	nameLabel.Position = UDim2.fromOffset(22, 0)
	nameLabel.Size = UDim2.new(1, -80, 1, 0)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextWrapped = false
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

	local statusLabel = newLabel(nameLine, "", 15, BattleTheme.FontHeavy)
	statusLabel.AnchorPoint = Vector2.new(1, 0)
	statusLabel.Position = UDim2.fromScale(1, 0)
	statusLabel.Size = UDim2.new(0, 56, 1, 0)
	statusLabel.TextXAlignment = Enum.TextXAlignment.Right
	statusLabel.TextColor3 = BattleTheme.Danger

	local ownerLabel = newLabel(frame, "", 14)
	ownerLabel.TextXAlignment = Enum.TextXAlignment.Left
	ownerLabel.TextColor3 = BattleTheme.SubtleText
	ownerLabel.LayoutOrder = 2

	local hpFill, hpText = newBar(frame, BattleTheme.HealthBar, 3)
	local manaFill, manaText = newBar(frame, BattleTheme.ManaBar, 4)

	local effectsLabel = newLabel(frame, "", 14, BattleTheme.FontBold)
	effectsLabel.TextXAlignment = Enum.TextXAlignment.Left
	effectsLabel.RichText = true
	effectsLabel.LayoutOrder = 5
	effectsLabel.Visible = false

	return {
		frame = frame,
		stroke = stroke,
		swatch = swatch,
		statusLabel = statusLabel,
		ownerLabel = ownerLabel,
		hpFill = hpFill,
		hpText = hpText,
		manaFill = manaFill,
		manaText = manaText,
		effectsLabel = effectsLabel,
	}
end

-- "Dazed 2  ·  Tailwind 3" with ailments in red and buffs in gold (RichText).
local function formatStatuses(statuses: { BattleTypes.StatusState }): string
	local parts = {}
	for _, status in statuses do
		local def = StatusEffects[status.id]
		local color = if def ~= nil and def.kind == "Ailment" then BattleTheme.Danger else BattleTheme.Accent
		local name = if def ~= nil then def.name else status.id
		table.insert(parts, `<font color="#{color:ToHex()}">{name} {status.turnsLeft}</font>`)
	end
	return table.concat(parts, "  ·  ")
end

-- One entry in the turn-order strip: initiative total and name.
local function createChip(parent: Instance, participant: ParticipantState, position: number): Chip
	local frame = newPanel(parent, participant.id)
	frame.Size = UDim2.fromOffset(0, 28)
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.LayoutOrder = position
	local stroke = addStroke(frame, BattleTheme.Accent, 2)
	stroke.Enabled = false

	local initiative = participant.initiative
	local label = newLabel(frame, `{if initiative then initiative.total else "?"}  {participant.name}`, 14, BattleTheme.FontBold)
	label.Size = UDim2.fromScale(0, 1)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.TextWrapped = false
	label.TextColor3 = BattleTheme.colorFor(participant.side, participant.slot)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = label

	return { frame = frame, stroke = stroke, label = label }
end

--[[ BattleUI ]]

local BattleUI = {}
BattleUI.__index = BattleUI

type UIFields = {
	localUserId: number,
	callbacks: Callbacks,
	gui: ScreenGui,

	lobbyFrame: Frame,
	lobbyList: Frame,
	lobbyEntries: { TextLabel },
	readyButton: TextButton,
	lobbyStatus: TextLabel,
	lobbyHint: TextLabel,

	battleFrame: Frame,
	turnTitle: TextLabel,
	turnDetail: TextLabel,
	turnOrder: Frame,
	partyPanel: Frame,
	enemyPanel: Frame,
	actionPanel: Frame,
	actionTitle: TextLabel,
	abilityRow: Frame,
	abilityHint: TextLabel,
	targetCaption: TextLabel,
	targetRow: Frame,
	attackButton: TextButton,
	logLabel: TextLabel,
	resultPanel: Frame,
	resultTitle: TextLabel,
	resultDetail: TextLabel,
	noticeLabel: TextLabel,

	snapshot: Snapshot?,
	lobbyStatusBase: string,
	detailBase: string,
	detailDeadline: number?,
	builtBattleId: number?,
	rows: { [string]: Row },
	chips: { [string]: Chip },
	targetButtons: { [string]: TextButton },
	abilityButtons: { [string]: TextButton },
	abilityButtonsFor: string?, -- the summon the ability buttons were built for
	selectedAbilityId: string?,
	selectedTargetId: string?,
	submittedTurn: number?, -- turn we sent an action for and are waiting on the server
	noticeCount: number,
}

export type BattleUI = typeof(setmetatable({} :: UIFields, BattleUI))

function BattleUI.new(playerGui: PlayerGui, localUserId: number, callbacks: Callbacks): BattleUI
	local gui = Instance.new("ScreenGui")
	gui.Name = "BattleUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Every top-level panel gets a UIScale so the whole HUD shrinks together on small screens.
	local scales: { UIScale } = {}
	local function scaleWithScreen(panel: GuiObject)
		local uiScale = Instance.new("UIScale")
		uiScale.Parent = panel
		table.insert(scales, uiScale)
	end

	--[[ Lobby ]]
	local lobbyFrame = newPanel(gui, "Lobby")
	lobbyFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	lobbyFrame.Position = UDim2.fromScale(0.5, 0.5)
	lobbyFrame.Size = UDim2.fromOffset(440, 0)
	lobbyFrame.AutomaticSize = Enum.AutomaticSize.Y
	lobbyFrame.Visible = false -- until the first state arrives, so Ready can't be pressed blind
	addPadding(lobbyFrame, 18)
	addList(lobbyFrame, Enum.FillDirection.Vertical, 10)
	scaleWithScreen(lobbyFrame)

	newLabel(lobbyFrame, "TungWarts Arena", 30, BattleTheme.FontHeavy).LayoutOrder = 1
	local subtitle = newLabel(lobbyFrame, "Turn-based combat prototype: 2 summons per side", 16)
	subtitle.TextColor3 = BattleTheme.SubtleText
	subtitle.LayoutOrder = 2

	local lobbyList = newContainer(lobbyFrame, "Players")
	lobbyList.Size = UDim2.fromScale(1, 0)
	lobbyList.AutomaticSize = Enum.AutomaticSize.Y
	lobbyList.LayoutOrder = 3
	addList(lobbyList, Enum.FillDirection.Vertical, 4)

	local readyButton = newButton(lobbyFrame, "READY", UDim2.new(1, 0, 0, 46))
	readyButton.Name = "ReadyButton"
	readyButton.TextSize = 22
	readyButton.Font = BattleTheme.FontHeavy
	readyButton.LayoutOrder = 4

	local lobbyStatus = newLabel(lobbyFrame, "", 17, BattleTheme.FontBold)
	lobbyStatus.LayoutOrder = 5
	local lobbyHint = newLabel(lobbyFrame, "", 14)
	lobbyHint.Size = UDim2.fromScale(1, 0)
	lobbyHint.AutomaticSize = Enum.AutomaticSize.Y
	lobbyHint.TextColor3 = BattleTheme.SubtleText
	lobbyHint.LayoutOrder = 6

	--[[ Battle ]]
	local battleFrame = newContainer(gui, "Battle")
	battleFrame.Size = UDim2.fromScale(1, 1)
	battleFrame.Visible = false

	-- Header: whose turn it is, and the turn order under it.
	local header = newContainer(battleFrame, "Header")
	header.AnchorPoint = Vector2.new(0.5, 0)
	header.Position = UDim2.new(0.5, 0, 0, 10)
	header.Size = UDim2.fromOffset(640, 0)
	header.AutomaticSize = Enum.AutomaticSize.Y
	addList(header, Enum.FillDirection.Vertical, 8).HorizontalAlignment = Enum.HorizontalAlignment.Center
	scaleWithScreen(header)

	local turnPanel = newPanel(header, "Turn")
	turnPanel.Size = UDim2.fromOffset(560, 0)
	turnPanel.AutomaticSize = Enum.AutomaticSize.Y
	turnPanel.LayoutOrder = 1
	addPadding(turnPanel, 10)
	addList(turnPanel, Enum.FillDirection.Vertical, 2)
	local turnTitle = newLabel(turnPanel, "", 26, BattleTheme.FontHeavy)
	turnTitle.LayoutOrder = 1
	local turnDetail = newLabel(turnPanel, "", 17)
	turnDetail.TextColor3 = BattleTheme.SubtleText
	turnDetail.LayoutOrder = 2

	local turnOrder = newContainer(header, "TurnOrder")
	turnOrder.Size = UDim2.fromOffset(0, 28)
	turnOrder.AutomaticSize = Enum.AutomaticSize.X
	turnOrder.LayoutOrder = 2
	addList(turnOrder, Enum.FillDirection.Horizontal, 6)

	-- Party on the left, enemies on the right, matching the blocks in the world.
	local function newSidePanel(name: string, title: string, anchorX: number): Frame
		local panel = newPanel(battleFrame, name)
		panel.AnchorPoint = Vector2.new(anchorX, 0.5)
		panel.Position = UDim2.new(anchorX, if anchorX == 0 then 12 else -12, 0.5, 0)
		panel.Size = UDim2.fromOffset(290, 0)
		panel.AutomaticSize = Enum.AutomaticSize.Y
		addPadding(panel, 10)
		addList(panel, Enum.FillDirection.Vertical, 8)
		scaleWithScreen(panel)
		local heading = newLabel(panel, title, 18, BattleTheme.FontHeavy)
		heading.TextXAlignment = Enum.TextXAlignment.Left
		heading.LayoutOrder = 0
		return panel
	end
	local partyPanel = newSidePanel("Party", "YOUR PARTY", 0)
	local enemyPanel = newSidePanel("Enemies", "ENEMIES", 1)

	-- Your move: ability buttons, target picker, Attack button. Only shown on your turn.
	local actionPanel = newPanel(battleFrame, "Actions")
	actionPanel.AnchorPoint = Vector2.new(0.5, 1)
	actionPanel.Position = UDim2.new(0.5, 0, 1, -12)
	actionPanel.Size = UDim2.fromOffset(ACTION_PANEL_WIDTH, 0)
	actionPanel.AutomaticSize = Enum.AutomaticSize.Y
	actionPanel.Visible = false
	addPadding(actionPanel, ACTION_PANEL_PADDING)
	addList(actionPanel, Enum.FillDirection.Vertical, 6)
	addStroke(actionPanel, BattleTheme.Accent, 2)
	scaleWithScreen(actionPanel)

	local actionTitle = newLabel(actionPanel, "", 20, BattleTheme.FontHeavy)
	actionTitle.LayoutOrder = 1
	local abilityCaption = newLabel(actionPanel, "1. Choose an ability, or Guard", 14, BattleTheme.FontBold)
	abilityCaption.TextXAlignment = Enum.TextXAlignment.Left
	abilityCaption.TextColor3 = BattleTheme.SubtleText
	abilityCaption.LayoutOrder = 2
	local abilityRow = newContainer(actionPanel, "Abilities")
	abilityRow.Size = UDim2.new(1, 0, 0, 44)
	abilityRow.LayoutOrder = 3
	addList(abilityRow, Enum.FillDirection.Horizontal, 8)
	local abilityHint = newLabel(actionPanel, "", 14)
	abilityHint.TextXAlignment = Enum.TextXAlignment.Left
	abilityHint.TextColor3 = BattleTheme.SubtleText
	abilityHint.LayoutOrder = 4
	local targetCaption = newLabel(actionPanel, "2. Pick a target", 14, BattleTheme.FontBold)
	targetCaption.TextXAlignment = Enum.TextXAlignment.Left
	targetCaption.TextColor3 = BattleTheme.SubtleText
	targetCaption.LayoutOrder = 5
	local targetRow = newContainer(actionPanel, "Targets")
	targetRow.Size = UDim2.new(1, 0, 0, 44)
	targetRow.LayoutOrder = 6
	addList(targetRow, Enum.FillDirection.Horizontal, 8)
	local attackButton = newButton(actionPanel, "ATTACK!", UDim2.new(1, 0, 0, 46))
	attackButton.Name = "AttackButton"
	attackButton.Font = BattleTheme.FontHeavy
	attackButton.TextSize = 22
	attackButton.LayoutOrder = 7

	-- Combat log, newest line at the bottom.
	local logPanel = newPanel(battleFrame, "Log")
	logPanel.AnchorPoint = Vector2.new(0, 1)
	logPanel.Position = UDim2.new(0, 12, 1, -12)
	logPanel.Size = UDim2.fromOffset(330, 150)
	logPanel.ClipsDescendants = true
	addPadding(logPanel, 10)
	scaleWithScreen(logPanel)
	local logLabel = newLabel(logPanel, "", 14)
	logLabel.Size = UDim2.fromScale(1, 1)
	logLabel.AutomaticSize = Enum.AutomaticSize.None -- stay inside the panel; old lines clip at the top
	logLabel.TextXAlignment = Enum.TextXAlignment.Left
	logLabel.TextYAlignment = Enum.TextYAlignment.Bottom

	-- Victory/defeat, shown over everything at the end.
	local resultPanel = newPanel(battleFrame, "Result")
	resultPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	resultPanel.Position = UDim2.fromScale(0.5, 0.42)
	resultPanel.Size = UDim2.fromOffset(440, 0)
	resultPanel.AutomaticSize = Enum.AutomaticSize.Y
	resultPanel.Visible = false
	resultPanel.ZIndex = 3
	addPadding(resultPanel, 18)
	addList(resultPanel, Enum.FillDirection.Vertical, 6)
	scaleWithScreen(resultPanel)
	local resultTitle = newLabel(resultPanel, "", 44, BattleTheme.FontHeavy)
	resultTitle.LayoutOrder = 1
	local resultDetail = newLabel(resultPanel, "", 18)
	resultDetail.LayoutOrder = 2

	-- Why the server refused a request ("It's not your turn", "Not enough Mana", ...).
	local noticeLabel = newLabel(gui, "", 18, BattleTheme.FontBold)
	noticeLabel.Name = "Notice"
	noticeLabel.AnchorPoint = Vector2.new(0.5, 0)
	noticeLabel.Position = UDim2.new(0.5, 0, 0, 150)
	noticeLabel.Size = UDim2.fromOffset(0, 36)
	noticeLabel.AutomaticSize = Enum.AutomaticSize.X
	noticeLabel.TextWrapped = false
	noticeLabel.BackgroundColor3 = BattleTheme.Panel
	noticeLabel.BackgroundTransparency = 0.05
	noticeLabel.TextColor3 = BattleTheme.Danger
	noticeLabel.ZIndex = 5
	noticeLabel.Visible = false
	addPadding(noticeLabel, 8)
	addCorner(noticeLabel, 8)
	scaleWithScreen(noticeLabel)

	local fields: UIFields = {
		localUserId = localUserId,
		callbacks = callbacks,
		gui = gui,

		lobbyFrame = lobbyFrame,
		lobbyList = lobbyList,
		lobbyEntries = {},
		readyButton = readyButton,
		lobbyStatus = lobbyStatus,
		lobbyHint = lobbyHint,

		battleFrame = battleFrame,
		turnTitle = turnTitle,
		turnDetail = turnDetail,
		turnOrder = turnOrder,
		partyPanel = partyPanel,
		enemyPanel = enemyPanel,
		actionPanel = actionPanel,
		actionTitle = actionTitle,
		abilityRow = abilityRow,
		abilityHint = abilityHint,
		targetCaption = targetCaption,
		targetRow = targetRow,
		attackButton = attackButton,
		logLabel = logLabel,
		resultPanel = resultPanel,
		resultTitle = resultTitle,
		resultDetail = resultDetail,
		noticeLabel = noticeLabel,

		snapshot = nil,
		lobbyStatusBase = "",
		detailBase = "",
		detailDeadline = nil,
		builtBattleId = nil,
		rows = {},
		chips = {},
		targetButtons = {},
		abilityButtons = {},
		abilityButtonsFor = nil,
		selectedAbilityId = nil,
		selectedTargetId = nil,
		submittedTurn = nil,
		noticeCount = 0,
	}
	local self = setmetatable(fields, BattleUI)

	readyButton.Activated:Connect(function()
		self:_toggleReady()
	end)
	attackButton.Activated:Connect(function()
		self:_submitAttack()
	end)

	local camera = Workspace.CurrentCamera
	local function fitToScreen()
		local viewport = camera.ViewportSize
		local scale = math.clamp(math.min(viewport.X / DESIGN_SIZE.X, viewport.Y / DESIGN_SIZE.Y), 0.5, 1.25)
		for _, uiScale in scales do
			uiScale.Scale = scale
		end
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitToScreen)
	fitToScreen()

	gui.Parent = playerGui
	return self
end

-- Draws a fresh snapshot from the server.
function BattleUI.render(self: BattleUI, snapshot: Snapshot)
	self.snapshot = snapshot
	local battle = snapshot.battle
	self.lobbyFrame.Visible = battle == nil
	self.battleFrame.Visible = battle ~= nil

	if battle then
		self:_renderBattle(battle)
	else
		self:_clearBattle()
		self:_renderLobby(snapshot.lobby)
		self.callbacks.onTargetChanged(nil, false)
	end
	self:tick(Workspace:GetServerTimeNow())
end

-- Updates countdowns; called every frame.
function BattleUI.tick(self: BattleUI, now: number)
	local snapshot = self.snapshot
	if snapshot == nil then
		return
	end

	local battle = snapshot.battle
	if battle == nil then
		local endsAt = snapshot.lobby.countdownEndsAt
		self.lobbyStatus.Text = if endsAt then `Battle starting in {secondsLeft(endsAt, now)}...` else self.lobbyStatusBase
	elseif battle.phase == "reward" then
		local returnAt = battle.lobbyReturnAt
		self.resultDetail.Text = if returnAt then `Back to the lobby in {secondsLeft(returnAt, now)}...` else ""
	elseif self.detailDeadline then
		self.turnDetail.Text = `{self.detailBase}  ·  {secondsLeft(self.detailDeadline, now)}s left`
	end
end

-- Shows why the server refused a request, and lets the player try again.
function BattleUI.showNotice(self: BattleUI, message: string)
	self.submittedTurn = nil
	self.noticeLabel.Text = message
	self.noticeLabel.Visible = true
	self.noticeCount += 1
	local noticeCount = self.noticeCount
	task.delay(NOTICE_SECONDS, function()
		if self.noticeCount == noticeCount then
			self.noticeLabel.Visible = false
		end
	end)
	self:_rerender()
end

function BattleUI._rerender(self: BattleUI)
	local snapshot = self.snapshot
	if snapshot then
		self:render(snapshot)
	end
end

--[[ Lobby ]]

function BattleUI._renderLobby(self: BattleUI, lobby: LobbyState)
	for _, entry in self.lobbyEntries do
		entry:Destroy()
	end
	table.clear(self.lobbyEntries)

	local myEntry = nil
	local readyCount = 0
	local waitingOn = {}
	for index, member in lobby.members do
		local isMe = member.userId == self.localUserId
		if isMe then
			myEntry = member
		end
		if member.ready then
			readyCount += 1
		else
			table.insert(waitingOn, member.name)
		end

		local entry = newLabel(self.lobbyList, "", 18, BattleTheme.FontBold)
		entry.Text = `{member.name}{if isMe then " (you)" else ""}  ·  {if member.ready then "READY" else "not ready"}`
		entry.TextColor3 = if member.ready then BattleTheme.HealthBar else BattleTheme.SubtleText
		entry.LayoutOrder = index
		table.insert(self.lobbyEntries, entry)
	end

	local needed = math.min(#lobby.members, lobby.maxPartySize)
	if #lobby.members == 0 then
		self.lobbyStatusBase = "Waiting for players..."
	elseif readyCount == 0 then
		self.lobbyStatusBase = "Press READY to start"
	else
		self.lobbyStatusBase = `{readyCount}/{needed} ready. Waiting for {table.concat(waitingOn, ", ")}`
	end

	if #lobby.members <= 1 then
		self.lobbyHint.Text = "Playing solo? Press READY and you'll control both of your party's summons."
	else
		self.lobbyHint.Text = `The battle starts when everyone is ready. Up to {lobby.maxPartySize} players fight, `
			.. "each controlling one summon."
	end

	local isReady = myEntry ~= nil and myEntry.ready
	self.readyButton.Text = if isReady then "CANCEL READY" else "READY"
	styleButton(self.readyButton, if myEntry == nil then "disabled" elseif isReady then "normal" else "attack")
end

function BattleUI._toggleReady(self: BattleUI)
	local snapshot = self.snapshot
	if snapshot == nil or snapshot.battle ~= nil then
		return
	end
	for _, member in snapshot.lobby.members do
		if member.userId == self.localUserId then
			self.callbacks.onReadyChanged(not member.ready)
			return
		end
	end
end

--[[ Battle ]]

function BattleUI._buildBattle(self: BattleUI, battle: BattleState)
	self:_clearBattle()

	local byId: { [string]: ParticipantState } = {}
	for _, participant in battle.participants do
		byId[participant.id] = participant
		local panel = if participant.side == "Party" then self.partyPanel else self.enemyPanel
		self.rows[participant.id] = createRow(panel, participant)

		-- Every summon gets a (hidden) target button; each render shows the ones that are legal
		-- targets for the selected ability.
		local targetButton = newButton(self.targetRow, participant.name, UDim2.fromOffset(236, 44))
		targetButton.Name = participant.id
		targetButton.TextSize = 15
		targetButton.TextTruncate = Enum.TextTruncate.AtEnd
		targetButton.LayoutOrder = (if participant.side == "Party" then 0 else 10) + participant.slot
		targetButton.Visible = false
		targetButton.Activated:Connect(function()
			self.selectedTargetId = participant.id
			self:_rerender()
		end)
		self.targetButtons[participant.id] = targetButton
	end

	for position, id in battle.turnQueue do
		local participant = byId[id]
		if participant then
			self.chips[id] = createChip(self.turnOrder, participant, position)
		end
	end

	self.builtBattleId = battle.battleId
end

function BattleUI._clearBattle(self: BattleUI)
	if self.builtBattleId == nil then
		return
	end
	for _, row in self.rows do
		row.frame:Destroy()
	end
	for _, chip in self.chips do
		chip.frame:Destroy()
	end
	for _, button in self.targetButtons do
		button:Destroy()
	end
	for _, button in self.abilityButtons do
		button:Destroy()
	end
	table.clear(self.rows)
	table.clear(self.chips)
	table.clear(self.targetButtons)
	table.clear(self.abilityButtons)
	self.abilityButtonsFor = nil
	self.selectedAbilityId = nil
	self.selectedTargetId = nil
	self.submittedTurn = nil
	self.builtBattleId = nil
end

function BattleUI._renderBattle(self: BattleUI, battle: BattleState)
	if self.builtBattleId ~= battle.battleId then
		self:_buildBattle(battle)
	end

	local byId: { [string]: ParticipantState } = {}
	for _, participant in battle.participants do
		byId[participant.id] = participant
	end
	local actor = if battle.currentActorId then byId[battle.currentActorId] else nil
	local myTurn = battle.phase == "input" and actor ~= nil and actor.ownerUserId == self.localUserId

	-- The "Sending..." state only lasts until the server moves on.
	if self.submittedTurn ~= nil and (not myTurn or self.submittedTurn ~= battle.turnNumber) then
		self.submittedTurn = nil
	end
	if myTurn and actor then
		self:_validateChoices(battle, actor)
	end

	self:_renderHeader(battle, actor, myTurn)
	for _, participant in battle.participants do
		self:_renderRow(battle, participant, myTurn)
	end
	for _, participant in battle.participants do
		local chip = self.chips[participant.id]
		if chip then
			local active = participant.status == "Active"
			chip.stroke.Enabled = battle.phase ~= "reward" and battle.currentActorId == participant.id
			chip.frame.BackgroundTransparency = if active then BattleTheme.PanelTransparency else 0.7
			chip.label.TextTransparency = if active then 0 else 0.5
		end
	end
	self:_renderActions(byId, actor, myTurn)
	self.logLabel.Text = table.concat(battle.log, "\n")

	local over = battle.phase == "reward"
	self.resultPanel.Visible = over
	if over then
		local won = battle.winner == "Party"
		self.resultTitle.Text = if won then "VICTORY!" else "DEFEAT"
		self.resultTitle.TextColor3 = if won then BattleTheme.Accent else BattleTheme.Danger
	end

	local targetId, friendly = self:_highlightedTarget(myTurn)
	self.callbacks.onTargetChanged(targetId, friendly)
end

function BattleUI._renderHeader(self: BattleUI, battle: BattleState, actor: ParticipantState?, myTurn: boolean)
	local title, detail = "", ""
	self.detailDeadline = nil

	if battle.phase == "setup" then
		title = "Rolling initiative..."
		detail = "Everyone rolls 1-20 plus an Agility bonus. Highest total goes first."
	elseif battle.phase == "reward" then
		title = if battle.winner == "Party" then "Victory!" else "Defeat"
		detail = battle.log[#battle.log] or ""
	elseif actor then
		local round = `Round {battle.round}`
		if battle.phase == "resolve" then
			title = round
			detail = battle.log[#battle.log] or ""
		elseif myTurn then
			title = `{round}  ·  YOUR TURN`
			detail = `Choose an attack for {actor.name}`
			self.detailDeadline = battle.turnDeadline
		elseif actor.ownerUserId == nil then
			title = `{round}  ·  Enemy turn`
			detail = `{actor.name} is choosing a move...`
		else
			title = `{round}  ·  {actor.ownerName or "Your ally"}'s turn`
			detail = `Waiting for {actor.name}`
			self.detailDeadline = battle.turnDeadline
		end
	end

	self.turnTitle.Text = title
	self.turnTitle.TextColor3 = if myTurn then BattleTheme.Accent else BattleTheme.Text
	self.detailBase = detail
	self.turnDetail.Text = detail
end

function BattleUI._renderRow(self: BattleUI, battle: BattleState, participant: ParticipantState, myTurn: boolean)
	local row = self.rows[participant.id]
	if row == nil then
		return
	end

	row.hpFill.Size = UDim2.fromScale(fraction(participant.hp, participant.maxHp), 1)
	row.hpText.Text = `HP  {participant.hp} / {participant.maxHp}`
	row.manaFill.Size = UDim2.fromScale(fraction(participant.mana, participant.maxMana), 1)
	row.manaText.Text = `Mana  {participant.mana} / {participant.maxMana}`

	local active = participant.status == "Active"
	row.statusLabel.Text = if participant.status == "KnockedOut" then "KO" elseif participant.status == "Left" then "LEFT" else ""
	row.swatch.BackgroundColor3 = if participant.status == "KnockedOut"
		then BattleTheme.KnockedOut
		else BattleTheme.colorFor(participant.side, participant.slot)
	row.frame.BackgroundTransparency = if active then 0 else 0.6

	if participant.ownerUserId == nil then
		row.ownerLabel.Text = "Enemy (server AI)"
	else
		local controller = if participant.ownerUserId == self.localUserId
			then `{participant.ownerName or "You"} (you)`
			else participant.ownerName or "Ally"
		local summon = Summons[participant.summonId]
		row.ownerLabel.Text = if summon ~= nil then `{controller}  ·  {summon.role}` else controller
	end

	row.effectsLabel.Visible = #participant.statuses > 0
	row.effectsLabel.Text = formatStatuses(participant.statuses)

	local acting = battle.phase == "input" and battle.currentActorId == participant.id
	local targetId, friendly = self:_highlightedTarget(myTurn)
	row.stroke.Enabled = acting or targetId == participant.id
	row.stroke.Color = if acting then BattleTheme.Accent elseif friendly then BattleTheme.HealthBar else BattleTheme.Danger
end

-- Whether `target` is a legal pick for `ability`. Mirrors the server's rule so the picker only
-- offers sensible choices; the server still checks for itself.
local function canTarget(ability: Abilities.Ability, actor: ParticipantState, target: ParticipantState): boolean
	if target.status ~= "Active" then
		return false
	elseif ability.targets == "Enemy" then
		return target.side ~= actor.side
	elseif ability.targets == "Ally" then
		return target.side == actor.side
	end
	return false -- "Self" and "AllAllies" need no pick
end

-- The summon the current choice points at, and whether it's a friend (a heal). Abilities with no
-- pick highlight nothing.
function BattleUI._highlightedTarget(self: BattleUI, myTurn: boolean): (string?, boolean)
	local abilityId = self.selectedAbilityId
	local ability = if abilityId then Abilities[abilityId] else nil
	if not myTurn or ability == nil or (ability.targets ~= "Enemy" and ability.targets ~= "Ally") then
		return nil, false
	end
	return self.selectedTargetId, ability.targets == "Ally"
end

-- Keeps the current choice legal: an ability this summon has and can afford (or Guard), and a
-- target that ability can take. Falls back to the first affordable ability (Guard if none is), and
-- to the first enemy for an attack or the most hurt party member for a heal. Abilities with no pick
-- just name the actor.
function BattleUI._validateChoices(self: BattleUI, battle: BattleState, actor: ParticipantState)
	local function usable(abilityId: string?): boolean
		if abilityId == nil or (abilityId ~= GUARD.id and table.find(actor.abilities, abilityId) == nil) then
			return false
		end
		local ability = Abilities[abilityId]
		return ability ~= nil and actor.mana >= ability.manaCost
	end
	if not usable(self.selectedAbilityId) then
		self.selectedAbilityId = GUARD.id
		for _, abilityId in actor.abilities do
			if usable(abilityId) then
				self.selectedAbilityId = abilityId
				break
			end
		end
	end

	local ability = if self.selectedAbilityId then Abilities[self.selectedAbilityId] else nil
	if ability == nil then
		self.selectedTargetId = nil
		return
	elseif ability.targets == "Self" or ability.targets == "AllAllies" then
		self.selectedTargetId = actor.id
		return
	end

	for _, participant in battle.participants do
		if participant.id == self.selectedTargetId and canTarget(ability, actor, participant) then
			return -- still a good pick
		end
	end
	local best: ParticipantState? = nil
	for _, participant in battle.participants do
		if canTarget(ability, actor, participant) then
			if best == nil then
				best = participant
			elseif
				ability.targets == "Ally"
				and fraction(participant.hp, participant.maxHp) < fraction(best.hp, best.maxHp)
			then
				best = participant
			end
		end
	end
	self.selectedTargetId = if best then best.id else nil
end

function BattleUI._renderActions(
	self: BattleUI,
	byId: { [string]: ParticipantState },
	actor: ParticipantState?,
	myTurn: boolean
)
	self.actionPanel.Visible = myTurn
	if not myTurn or actor == nil then
		return
	end

	self.actionTitle.Text = `Your move: {actor.name}`

	-- Ability buttons, sized so all of this summon's abilities and Guard fit on one row.
	if self.abilityButtonsFor ~= actor.id then
		for _, button in self.abilityButtons do
			button:Destroy()
		end
		table.clear(self.abilityButtons)
		local choices = table.clone(actor.abilities)
		table.insert(choices, GUARD.id)
		local rowWidth = ACTION_PANEL_WIDTH - 2 * ACTION_PANEL_PADDING
		local width = math.floor((rowWidth - 8 * (#choices - 1)) / #choices)
		for index, abilityId in choices do
			local ability = Abilities[abilityId]
			if ability == nil then
				continue
			end
			local cost = if ability.manaCost > 0 then `{ability.manaCost} Mana` else "Free"
			local button = newButton(self.abilityRow, `{ability.name}\n{cost}`, UDim2.fromOffset(width, 44))
			button.Name = abilityId
			button.TextSize = 15
			button.LayoutOrder = index
			button.Activated:Connect(function()
				self.selectedAbilityId = abilityId
				self:_rerender()
			end)
			self.abilityButtons[abilityId] = button
		end
		self.abilityButtonsFor = actor.id
	end

	for abilityId, button in self.abilityButtons do
		local ability = Abilities[abilityId]
		local affordable = ability ~= nil and actor.mana >= ability.manaCost
		styleButton(
			button,
			if not affordable then "disabled" elseif abilityId == self.selectedAbilityId then "selected" else "normal"
		)
	end
	local selected = if self.selectedAbilityId then Abilities[self.selectedAbilityId] else nil
	self.abilityHint.Text = if selected == nil
		then ""
		elseif selected.kind == "Attack" then `{selected.damageType}: {selected.description}`
		elseif selected.kind == "Guard" then describeGuard()
		else selected.description

	-- Target picker: only the summons the selected ability can target.
	self.targetCaption.Text = if selected == nil or selected.targets == "Enemy"
		then "2. Pick an enemy"
		elseif selected.targets == "Ally" then "2. Pick a party member"
		elseif selected.targets == "Self" then "2. Target: itself"
		else "2. Target: the whole party"
	self.targetRow.Visible = selected ~= nil and (selected.targets == "Enemy" or selected.targets == "Ally")
	for id, button in self.targetButtons do
		local participant = byId[id]
		local legal = selected ~= nil and participant ~= nil and canTarget(selected, actor, participant)
		button.Visible = legal
		if selected and participant and legal then
			button.Text = `{participant.name}\n{participant.hp}/{participant.maxHp} HP`
			local chosenLook: ButtonLook = if selected.targets == "Ally" then "ally" else "target"
			styleButton(button, if id == self.selectedTargetId then chosenLook else "normal")
		end
	end

	local canAct = selected ~= nil and self.selectedTargetId ~= nil and self.submittedTurn == nil
	local verb = if selected == nil or selected.kind == "Attack"
		then "ATTACK!"
		elseif selected.kind == "Heal" then "HEAL!"
		elseif selected.kind == "Guard" then "GUARD!"
		else "USE!"
	self.attackButton.Text = if self.submittedTurn then "Sending..." else verb
	styleButton(self.attackButton, if canAct then "attack" else "disabled")
end

function BattleUI._submitAttack(self: BattleUI)
	local snapshot = self.snapshot
	local battle = if snapshot then snapshot.battle else nil
	local abilityId, targetId = self.selectedAbilityId, self.selectedTargetId
	if battle == nil or abilityId == nil or targetId == nil or self.submittedTurn ~= nil then
		return
	end
	-- Optimistic "Sending..." until the server answers; the server's result is what counts.
	self.submittedTurn = battle.turnNumber
	self.callbacks.onAction(abilityId, targetId)
	self:_rerender()
end

return BattleUI
