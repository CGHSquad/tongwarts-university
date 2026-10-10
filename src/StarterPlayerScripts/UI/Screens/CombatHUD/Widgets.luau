--!strict
--[[
	Widgets — the combat HUD's own pieces (handoff S1), each built from the base components:
	the turn-order bar, the status line under it, the party cards, the hero Mana plate, the
	initiative reveal and the recent-actions feed.
	Everything is in design pixels inside the screen's SafeArea; CombatHUD places the pieces in
	Layout's regions.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UI = ReplicatedStorage:WaitForChild("UI")
local Strings = require(UI:WaitForChild("Strings"))
local Theme = require(UI:WaitForChild("Theme"))
local UITypes = require(UI:WaitForChild("UITypes"))

local Root = script.Parent.Parent.Parent
local Core = Root:WaitForChild("Core")
local Fallbacks = require(Core:WaitForChild("Fallbacks"))
local Gui = require(Core:WaitForChild("Gui"))
local Components = Root:WaitForChild("Components")
local HeadIcon = require(Components:WaitForChild("HeadIcon"))
local SlicedPanel = require(Components:WaitForChild("SlicedPanel"))
local StatBar = require(Components:WaitForChild("StatBar"))
local Tag = require(Components:WaitForChild("Tag"))

type HudBattle = UITypes.HudBattle
type HudParticipant = UITypes.HudParticipant

local Widgets = {}

local function initials(name: string?): string
	return string.upper(string.sub(name or "?", 1, 2))
end

-- "T2" for the second Tung Tung: the first letter plus the slot, so two of a kind read apart.
local function tokenLabel(p: HudParticipant): string
	return string.upper(string.sub(p.name, 1, 1)) .. p.slot
end

-- "F2C14E" for rich text.
local function hex(color: Color3): string
	return string.format("%02X%02X%02X", math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255))
end

--[[ Turn-order bar: "ROUND n", then one token per participant in queue order ]]

export type TurnOrderBar = {
	frame: Frame,
	update: (battle: HudBattle) -> (),
	destroy: () -> (),
}

type Token = { frame: ImageLabel, stroke: UIStroke?, label: TextLabel, now: TextLabel }

Widgets.TOKEN = 36
Widgets.TOKEN_GAP = 6

function Widgets.turnOrderBar(parent: Instance): TurnOrderBar
	local frame = Gui.frame(parent, "TurnBar")
	local plate = SlicedPanel.new(frame, { name = "Plate", assetKey = "Turn_BarFrame", padding = 6 })
	plate.frame.Size = UDim2.fromScale(1, 1)
	local round = Gui.label(plate.content, "Round", { size = Theme.Sizes.TextLabel + 2, font = Theme.Fonts.Display, color = Theme.Colors.Gold, align = Enum.TextXAlignment.Left, stroke = 1 })
	round.Size = UDim2.fromOffset(80, Widgets.TOKEN)
	local tokens = Gui.frame(plate.content, "Tokens")
	tokens.Position = UDim2.fromOffset(84, 0)
	tokens.Size = UDim2.new(1, -84, 1, 0)
	Gui.list(tokens, Enum.FillDirection.Horizontal, Widgets.TOKEN_GAP)

	local built: { [string]: Token } = {}
	local builtFor: string? = nil

	local function clear()
		for _, token in built do
			token.frame:Destroy()
		end
		table.clear(built)
	end

	local function build(battle: HudBattle)
		clear()
		for index, id in battle.turnQueue do
			local p = battle.byId[id]
			if p == nil then
				continue
			end
			local enemy = p.side == "Enemy"
			local token = Fallbacks.image(tokens, id, if enemy then "Turn_TokenEnemy" else "Turn_TokenNormal", {
				fill = Theme.Colors.Navy,
				fillTransparency = 0,
				trim = if enemy then Theme.Colors.Crimson else Theme.Colors.Gold,
				trimThickness = 2,
				corner = 4,
			})
			token.Size = UDim2.fromOffset(Widgets.TOKEN, Widgets.TOKEN)
			token.LayoutOrder = index
			local label = Gui.label(token, "Label", { text = tokenLabel(p), size = Theme.Sizes.TextLabel + 2, font = Theme.Fonts.Display, stroke = 1 })
			label.Size = UDim2.new(1, 0, 0, 22)
			local now = Gui.label(token, "Now", { text = Strings.Now, size = Theme.Sizes.TextLabel - 2, font = Theme.Fonts.Display, color = Theme.Colors.Cyan, stroke = 1 })
			now.Size = UDim2.new(1, 0, 0, 14)
			now.Position = UDim2.fromOffset(0, 22)
			now.Visible = false
			built[id] = { frame = token, stroke = token:FindFirstChildOfClass("UIStroke"), label = label, now = now }
		end
		builtFor = battle.rosterKey
	end

	local function update(battle: HudBattle)
		if builtFor ~= battle.rosterKey then
			build(battle)
		end
		round.Text = Strings.format.round(battle.round)
		for id, token in built do
			local p = battle.byId[id]
			local active = battle.phase ~= "Reward" and battle.activeId == id
			local out = p == nil or p.knockedOut or p.left
			token.now.Visible = active
			token.frame.ImageTransparency = if out then 0.6 else 0
			token.frame.BackgroundTransparency = if out then 0.6 else 0
			token.label.TextTransparency = if out then 0.5 else 0
			if token.stroke then
				token.stroke.Color = if active then Theme.Colors.Cyan elseif p and p.side == "Enemy" then Theme.Colors.Crimson else Theme.Colors.Gold
				token.stroke.Thickness = if active then 3 else 2
			end
		end
	end

	return {
		frame = frame,
		update = update,
		destroy = function()
			frame:Destroy()
		end,
	}
end

--[[ Status line: whose turn it is, and the countdown ]]

export type StatusLine = {
	frame: Frame,
	title: TextLabel,
	detail: TextLabel,
	destroy: () -> (),
}

function Widgets.statusLine(parent: Instance): StatusLine
	local frame = Gui.frame(parent, "Status")
	local title = Gui.label(frame, "Title", { size = Theme.Sizes.TextTitle, font = Theme.Fonts.Display, stroke = 1 })
	title.Size = UDim2.new(1, 0, 0, 30)
	-- The detail sits straight over the scene, often a bright sky: near-white with an Ink outline.
	local detail = Gui.label(frame, "Detail", { size = Theme.Sizes.TextBody, font = Theme.Fonts.Bold, color = Theme.Colors.TextOverScene, wrap = true, stroke = Theme.Sizes.StrokeOverScene })
	detail.Size = UDim2.new(1, 0, 0, 44)
	detail.Position = UDim2.fromOffset(0, 30)
	return {
		frame = frame,
		title = title,
		detail = detail,
		destroy = function()
			frame:Destroy()
		end,
	}
end

--[[ Party cards: one slanted card per party member ]]

export type Card = {
	button: ImageButton,
	head: HeadIcon.HeadIcon,
	title: TextLabel,
	owner: TextLabel,
	statuses: TextLabel,
	hp: StatBar.StatBar,
	mana: StatBar.StatBar,
	tag: Tag.Tag,
	stroke: UIStroke?,
}

export type PartyCards = {
	frame: Frame,
	cards: { [string]: Card },
	update: (battle: HudBattle, localUserId: number, targetId: string?, pickable: { [string]: boolean }) -> (),
	layout: (width: number, height: number) -> (),
	onPick: (callback: (id: string) -> ()) -> (),
	destroy: () -> (),
}

Widgets.CARD = 56
Widgets.CARD_MIN = 48 -- a card is a tap target while picking an ally
Widgets.CARD_GAP = 6

function Widgets.partyCards(parent: Instance): PartyCards
	local frame = Gui.frame(parent, "Party")
	local cards: { [string]: Card } = {}
	local order: { string } = {}
	local builtFor: string? = nil
	local pick: ((id: string) -> ())? = nil
	local connections: { RBXScriptConnection } = {}
	local columnWidth, columnHeight = 200, 200

	-- Stacks the cards to fit the column; they shrink (never below the minimum) when four won't fit.
	local function place()
		local count = #order
		if count == 0 then
			return
		end
		local cardHeight = math.floor(math.max(Widgets.CARD_MIN, math.min(Widgets.CARD, (columnHeight - Widgets.CARD_GAP * (count - 1)) / count)))
		for index, id in order do
			local card = cards[id]
			card.button.Position = UDim2.fromOffset(0, (index - 1) * (cardHeight + Widgets.CARD_GAP))
			card.button.Size = UDim2.fromOffset(columnWidth, cardHeight)
		end
	end

	local function clear()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		for _, card in cards do
			card.button:Destroy()
		end
		table.clear(cards)
		table.clear(order)
	end

	local function build(battle: HudBattle)
		clear()
		for _, p in battle.participants do
			if p.side ~= "Party" then
				continue
			end
			local button = Instance.new("ImageButton")
			button.Name = `Card_{p.id}`
			button.Image = ""
			button.AutoButtonColor = false
			button.BorderSizePixel = 0
			button.Interactable = false
			if not Fallbacks.skin(button, "Party_CardNormal") then
				Fallbacks.panel(button, { trim = Theme.Colors.Gold, trimThickness = 1 })
			end
			button.Parent = frame
			local content = Gui.frame(button, "Content")
			content.Size = UDim2.fromScale(1, 1)
			Gui.padding(content, 3)
			local head = HeadIcon.new(content, { name = "Head", userId = p.ownerUserId, fallbackText = initials(p.ownerName), size = 40 })
			local title = Gui.label(content, "Title", { text = p.name, size = Theme.Sizes.TextLabel + 1, font = Theme.Fonts.Bold, align = Enum.TextXAlignment.Left })
			title.Position = UDim2.fromOffset(46, 0)
			title.Size = UDim2.new(1, -100, 0, 16)
			local owner = Gui.label(content, "Owner", { size = Theme.Sizes.TextLabel - 2, color = Theme.Colors.TextDim, align = Enum.TextXAlignment.Right })
			owner.Position = UDim2.new(1, -4, 0, 0)
			owner.AnchorPoint = Vector2.new(1, 0)
			owner.Size = UDim2.fromOffset(80, 16)
			-- Four lines in a 56 px card: name, HP, Mana, statuses.
			local hp = StatBar.new(content, { name = "Hp", color = Theme.Colors.HpGreen, trackKey = "Bar_HpTrack", fillKey = "Bar_HpFill", trail = true, height = 9, size = UDim2.new(1, -46, 0, 9), position = UDim2.fromOffset(46, 15), textFormat = Strings.format.hp })
			local mana = StatBar.new(content, { name = "Mana", color = Theme.Colors.ManaBlue, trackKey = "Bar_ManaTrack", fillKey = "Bar_ManaFill", height = 9, size = UDim2.new(1, -46, 0, 9), position = UDim2.fromOffset(46, 26), textFormat = Strings.format.mana })
			local statuses = Gui.label(content, "Statuses", { size = Theme.Sizes.TextLabel, font = Theme.Fonts.Bold, color = Theme.Colors.Cyan, align = Enum.TextXAlignment.Left })
			statuses.Position = UDim2.fromOffset(46, 36)
			statuses.Size = UDim2.new(1, -46, 0, 14)
			local tag = Tag.new(content, { name = "StatusTag", kind = "KnockedOut", position = UDim2.new(1, -4, 1, -2), anchor = Vector2.new(1, 1), size = UDim2.fromOffset(44, 18) })
			tag.frame.Visible = false
			local id = p.id
			table.insert(connections, button.Activated:Connect(function()
				if pick and button.Interactable then
					pick(id)
				end
			end))
			cards[id] = { button = button, head = head, title = title, owner = owner, statuses = statuses, hp = hp, mana = mana, tag = tag, stroke = button:FindFirstChildOfClass("UIStroke") }
			table.insert(order, id)
		end
		builtFor = battle.rosterKey
		place()
	end

	local function update(battle: HudBattle, localUserId: number, targetId: string?, pickable: { [string]: boolean })
		if builtFor ~= battle.rosterKey then
			build(battle)
		end
		for id, card in cards do
			local p = battle.byId[id]
			if p == nil then
				continue
			end
			local active = battle.phase == "Input" and battle.activeId == id
			card.hp.set(p.hp.current, p.hp.max, true)
			card.mana.set(p.mana.current, p.mana.max, true)
			card.owner.Text = if p.ownerUserId == localUserId then Strings.format.you(p.ownerName or "") else (p.ownerName or "")
			local parts = {}
			for _, status in p.statuses do
				table.insert(parts, Strings.format.statusTurns(status.name, status.turnsLeft))
			end
			card.title.Text = p.name
			card.statuses.Text = table.concat(parts, "  ·  ")
			card.tag.frame.Visible = p.knockedOut or p.left
			card.tag.setKind(if p.left then "Left" else "KnockedOut")
			local targeted = targetId == id
			local canPick = pickable[id] == true
			card.button.Interactable = canPick
			if card.stroke then
				card.stroke.Color = if targeted then Theme.Colors.HpGreen elseif active then Theme.Colors.Cyan elseif canPick then Theme.Colors.TextLight else Theme.Colors.Gold
				card.stroke.Thickness = if targeted or active then 3 else 1
			end
			card.button.BackgroundTransparency = if p.knockedOut or p.left then 0.5 else Theme.Panel.FillTransparency
		end
	end

	local function layout(width: number, height: number)
		columnWidth, columnHeight = width, height
		place()
	end

	return {
		frame = frame,
		cards = cards,
		update = update,
		layout = layout,
		onPick = function(callback)
			pick = callback
		end,
		destroy = function()
			clear()
			frame:Destroy()
		end,
	}
end

--[[ Hero Mana plate: the current actor's summon, its owner, and its Mana ]]

export type ManaPlate = {
	frame: Frame,
	update: (actor: HudParticipant?, localUserId: number) -> (),
	destroy: () -> (),
}

function Widgets.manaPlate(parent: Instance): ManaPlate
	local frame = Gui.frame(parent, "ManaPlate")
	local plate = SlicedPanel.new(frame, { name = "Plate", assetKey = "Party_ManaPlate", padding = 6 })
	local head = HeadIcon.new(plate.content, { name = "Head", userId = nil, fallbackText = "", size = 36 })
	local title = Gui.label(plate.content, "Title", { size = Theme.Sizes.TextLabel + 1, font = Theme.Fonts.Bold, align = Enum.TextXAlignment.Left })
	title.Position = UDim2.fromOffset(44, 0)
	title.Size = UDim2.new(1, -44, 0, 16)
	local mana = StatBar.new(plate.content, { name = "Mana", color = Theme.Colors.ManaBlue, trackKey = "Bar_ManaTrack", fillKey = "Bar_ManaFill", height = 14, size = UDim2.new(1, -44, 0, 14), position = UDim2.fromOffset(44, 20), textFormat = Strings.format.mana })
	local shownFor: string? = nil

	return {
		frame = frame,
		update = function(actor: HudParticipant?, localUserId: number)
			frame.Visible = actor ~= nil
			if actor == nil then
				return
			end
			if shownFor ~= actor.id then
				shownFor = actor.id
				head.setUser(actor.ownerUserId, initials(actor.ownerName))
			end
			title.Text = actor.name
			mana.set(actor.mana.current, actor.mana.max, true)
		end,
		destroy = function()
			frame:Destroy()
		end,
	}
end

--[[ Initiative reveal: how the fight opened, and every roll ]]

export type Reveal = {
	frame: Frame,
	update: (battle: HudBattle) -> (),
	destroy: () -> (),
}

function Widgets.reveal(parent: Instance): Reveal
	local frame = Gui.frame(parent, "Reveal")
	local panel = SlicedPanel.new(frame, { name = "Panel", padding = Theme.Sizes.Margin })
	local title = Gui.label(panel.content, "Title", { size = Theme.Sizes.TextTitle, font = Theme.Fonts.Display, color = Theme.Colors.Gold, stroke = 1 })
	title.Size = UDim2.new(1, 0, 0, 30)
	local detail = Gui.label(panel.content, "Detail", { size = Theme.Sizes.TextLabel + 1, color = Theme.Colors.TextDim, wrap = true })
	detail.Size = UDim2.new(1, 0, 0, 40)
	detail.Position = UDim2.fromOffset(0, 32)
	local rolls = Gui.label(panel.content, "Rolls", { size = Theme.Sizes.TextLabel + 1, font = Theme.Fonts.Bold, wrap = true, align = Enum.TextXAlignment.Left })
	rolls.Size = UDim2.new(1, 0, 1, -76)
	rolls.Position = UDim2.fromOffset(0, 76)
	rolls.TextYAlignment = Enum.TextYAlignment.Top
	rolls.RichText = true

	return {
		frame = frame,
		update = function(battle: HudBattle)
			local headline, text = Strings.format.opening(battle.opening, battle.startedBy or "Someone")
			title.Text = headline
			detail.Text = text
			local lines = {}
			for _, id in battle.turnQueue do
				local p = battle.byId[id]
				local roll = p and p.initiative
				if p and roll then
					local color = if p.side == "Enemy" then Theme.Colors.Crimson else Theme.Colors.Gold
					table.insert(lines, `<font color="#{hex(color)}">{p.name}</font>  {Strings.format.initiative(roll.roll, roll.bonus, roll.total)}`)
				end
			end
			rolls.Text = table.concat(lines, "\n")
		end,
		destroy = function()
			frame:Destroy()
		end,
	}
end

--[[ Recent actions: the last few lines of the server's log, oldest first ]]

export type LogFeed = {
	frame: Frame,
	lines: TextLabel,
	update: (lines: { string }) -> (),
	destroy: () -> (),
}

function Widgets.logFeed(parent: Instance): LogFeed
	local frame = Gui.frame(parent, "Log")
	local lines = Gui.label(frame, "Lines", { size = Theme.Sizes.TextLabel, font = Theme.Fonts.Bold, color = Theme.Colors.TextDim, align = Enum.TextXAlignment.Left, stroke = 1, wrap = true })
	lines.TextYAlignment = Enum.TextYAlignment.Bottom
	return {
		frame = frame,
		lines = lines,
		update = function(text: { string })
			lines.Text = table.concat(text, "\n")
		end,
		destroy = function()
			frame:Destroy()
		end,
	}
end

-- A quick fade for panels that appear and vanish.
function Widgets.fadeIn(object: GuiObject)
	object.Visible = true
	local scale = object:FindFirstChildOfClass("UIScale") or Gui.scale(object)
	scale.Scale = 0.9
	TweenService:Create(scale, TweenInfo.new(Theme.motion(Theme.Motion.Tween), Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

return Widgets
