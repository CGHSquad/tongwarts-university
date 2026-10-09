--!strict
--[[
	Results — S6, the screen after a battle (docs/ui/UI_HANDOFF.md section 7, M0 report R24 and Q3).
	The VICTORY lettering (or DEFEAT, as live text; the same layout, no new design) with the RESULT
	ribbon, three stacked tallies (EXP, the currency, the items with their counts), the party list
	(head, name, level, EXP gained, a LEVEL UP! badge), and in place of CONTINUE the "Returning in
	N..." countdown from the snapshot's overworldReturnAt: the server brings everyone back by itself
	and there is no remote to leave early. The tallies count up one after another; a tap anywhere
	skips the count.

	The rewards are mock data until the server has a reward payload (Q3); only the outcome, the
	party and the countdown come from the snapshot (Bindings.reward).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UI = ReplicatedStorage:WaitForChild("UI")
local Strings = require(UI:WaitForChild("Strings"))
local Theme = require(UI:WaitForChild("Theme"))
local UITypes = require(UI:WaitForChild("UITypes"))

local Root = script.Parent.Parent
local Core = Root:WaitForChild("Core")
local Fallbacks = require(Core:WaitForChild("Fallbacks"))
local Gui = require(Core:WaitForChild("Gui"))
local Layout = require(Core:WaitForChild("Layout"))
local ScreenManager = require(Core:WaitForChild("ScreenManager"))
local Components = Root:WaitForChild("Components")
local Capsule = require(Components:WaitForChild("Capsule"))
local HeadIcon = require(Components:WaitForChild("HeadIcon"))
local SlicedPanel = require(Components:WaitForChild("SlicedPanel"))
local TallyPlate = require(Components:WaitForChild("TallyPlate"))

type RewardView = UITypes.RewardView

export type Props = {
	won: boolean,
	reward: RewardView,
	returnAt: number?, -- server clock; nil shows no countdown
}

export type Callbacks = {
	onSkip: (() -> ())?,
}

export type Results = {
	screen: ScreenManager.Screen,
	tick: (now: number) -> (), -- the countdown
	setReturnAt: (returnAt: number?) -> (),
	skip: () -> (),
	isCounting: () -> boolean,
}

type ItemSlot = { frame: ImageLabel, icon: ImageLabel, glyph: TextLabel, quantity: Capsule.Capsule }
type MemberRow = { panel: SlicedPanel.SlicedPanel, head: HeadIcon.HeadIcon, name: TextLabel, level: TextLabel, gained: TextLabel, badge: ImageLabel }

local Results = {}

Results.NAME = "Results"
Results.MAX_ITEMS = 4
Results.MAX_MEMBERS = 4

local TALLY_HEIGHT = 40
local ROW_HEIGHT = 40

local function secondsLeft(at: number, now: number): number
	return math.max(0, math.ceil(at - now))
end

-- Builds the screen into a ScreenGui the ScreenManager created.
function Results.build(gui: ScreenGui, safeArea: Frame, callbacks: Callbacks): Results
	-- A tap anywhere skips the count (handoff S6). Transparent, under everything else.
	local catcher = Instance.new("ImageButton")
	catcher.Name = "TapToSkip"
	catcher.Image = ""
	catcher.BackgroundTransparency = 1
	catcher.AutoButtonColor = false
	catcher.BorderSizePixel = 0
	catcher.Size = UDim2.fromScale(1, 1)
	catcher.Parent = safeArea

	--[[ Title: the lettering (art) or live text, and the RESULT ribbon ]]
	local title = Gui.frame(safeArea, "Title")
	local lettering = Fallbacks.image(title, "Lettering", "Results_VictoryLettering", { fillTransparency = 1, trimThickness = 0 })
	lettering.BackgroundTransparency = 1
	lettering.Size = UDim2.fromScale(1, 1)
	lettering.Rotation = -4
	local titleText = Gui.label(title, "Text", { size = 48, font = Theme.Fonts.Display, color = Theme.Colors.Gold, align = Enum.TextXAlignment.Left, stroke = Theme.Sizes.StrokeDisplay })
	titleText.Rotation = -4
	local ribbon = SlicedPanel.new(title, { name = "Ribbon", assetKey = "Results_SubtitleRibbon", look = { fill = Theme.Colors.Navy, fillTransparency = 0, trim = Theme.Colors.Cyan, trimThickness = 1, corner = 4 }, padding = 2 })
	ribbon.frame.AnchorPoint = Vector2.new(1, 1)
	ribbon.frame.Position = UDim2.fromScale(1, 1)
	ribbon.frame.Size = UDim2.fromOffset(110, 24)
	Gui.label(ribbon.content, "Label", { text = Strings.Result, size = Theme.Sizes.TextLabel + 1, font = Theme.Fonts.Display, stroke = 1 })

	--[[ Tallies: EXP, the currency, the items ]]
	local tallies = Gui.frame(safeArea, "Tallies")
	Gui.list(tallies, Enum.FillDirection.Vertical, Theme.Sizes.Gap)
	local exp = TallyPlate.new(tallies, { name = "Exp", label = Strings.Exp, assetKey = "Results_TallyGold", trim = Theme.Colors.Gold, format = Strings.format.gained, size = UDim2.new(1, 0, 0, TALLY_HEIGHT), layoutOrder = 1 })
	local currency = TallyPlate.new(tallies, { name = "Currency", label = Strings.Currency, assetKey = "Results_TallyNormal", trim = Theme.Colors.Cyan, format = Strings.format.gained, size = UDim2.new(1, 0, 0, TALLY_HEIGHT), layoutOrder = 2 })
	local itemsRow = SlicedPanel.new(tallies, { name = "Items", assetKey = "Results_TallyGreen", look = { fill = Theme.Colors.Obsidian, fillTransparency = 0.05, trim = Theme.Colors.HpGreen, trimThickness = 2 }, padding = 4, size = UDim2.new(1, 0, 0, TALLY_HEIGHT + 8), layoutOrder = 3 })
	local itemsLabel = Gui.label(itemsRow.content, "Label", { text = Strings.Items, size = Theme.Sizes.TextTitle, font = Theme.Fonts.Display, align = Enum.TextXAlignment.Left, stroke = 1 })
	itemsLabel.Size = UDim2.new(0, 72, 1, 0)
	itemsLabel.Position = UDim2.fromOffset(6, 0)
	local slotsFrame = Gui.frame(itemsRow.content, "Slots")
	slotsFrame.Position = UDim2.fromOffset(84, 0)
	slotsFrame.Size = UDim2.new(1, -84, 1, 0)
	Gui.list(slotsFrame, Enum.FillDirection.Horizontal, Theme.Sizes.Gap).VerticalAlignment = Enum.VerticalAlignment.Center
	local slots: { ItemSlot } = {}
	for index = 1, Results.MAX_ITEMS do
		local frame = Fallbacks.image(slotsFrame, `Slot{index}`, "Results_ItemSlot", { fill = Theme.Colors.Navy, fillTransparency = 0, trim = Theme.Colors.Gold, trimThickness = 1, corner = 6 })
		frame.Size = UDim2.fromOffset(40, 40)
		frame.LayoutOrder = index
		frame.Visible = false
		local icon = Fallbacks.image(frame, "Icon", "", { fillTransparency = 1, trimThickness = 0 })
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.new(1, -8, 1, -8)
		icon.Position = UDim2.fromOffset(4, 4)
		local glyph = Gui.label(frame, "Glyph", { size = Theme.Sizes.TextBody, font = Theme.Fonts.Display, stroke = 1 })
		local quantity = Capsule.new(frame, { name = "Quantity", text = "", assetKey = "Results_QuantityTag", color = Theme.Colors.Gold, position = UDim2.new(1, 4, 1, 4), anchor = Vector2.new(1, 1), size = UDim2.fromOffset(30, 16) })
		table.insert(slots, { frame = frame, icon = icon, glyph = glyph, quantity = quantity })
	end

	--[[ Party: one row per player ]]
	local party = Gui.frame(safeArea, "Party")
	local partyHeader = Gui.label(party, "Header", { text = Strings.Party, size = Theme.Sizes.TextTitle, font = Theme.Fonts.Display, color = Theme.Colors.Gold, align = Enum.TextXAlignment.Left, stroke = 1 })
	partyHeader.Size = UDim2.new(1, 0, 0, 26)
	local rowsFrame = Gui.frame(party, "Rows")
	rowsFrame.Position = UDim2.fromOffset(0, 30)
	rowsFrame.Size = UDim2.new(1, 0, 1, -30)
	Gui.list(rowsFrame, Enum.FillDirection.Vertical, 6)
	local rows: { MemberRow } = {}
	for index = 1, Results.MAX_MEMBERS do
		local panel = SlicedPanel.new(rowsFrame, { name = `Row{index}`, assetKey = "Results_PartyRow", look = { fill = Theme.Colors.Obsidian, fillTransparency = 0.05, trim = Theme.Colors.Gold, trimThickness = 1 }, padding = 4, size = UDim2.new(1, 0, 0, ROW_HEIGHT), layoutOrder = index })
		panel.frame.Visible = false
		local head = HeadIcon.new(panel.content, { name = "Head", userId = nil, fallbackText = "", size = 32 })
		-- The name on the first line, the level and the EXP gained on the second, the badge at the right:
		-- fits a small phone's half column.
		local name = Gui.label(panel.content, "Title", { size = Theme.Sizes.TextLabel + 2, font = Theme.Fonts.Bold, align = Enum.TextXAlignment.Left })
		name.Position = UDim2.fromOffset(38, 0)
		name.Size = UDim2.new(1, -38 - 80, 0, 18)
		local level = Gui.label(panel.content, "Level", { size = Theme.Sizes.TextLabel, color = Theme.Colors.TextDim, align = Enum.TextXAlignment.Left })
		level.Position = UDim2.fromOffset(38, 18)
		level.Size = UDim2.fromOffset(52, 16)
		local gained = Gui.label(panel.content, "Gained", { size = Theme.Sizes.TextLabel + 2, font = Theme.Fonts.Display, color = Theme.Colors.Gold, align = Enum.TextXAlignment.Left, stroke = 1 })
		gained.Position = UDim2.fromOffset(94, 17)
		gained.Size = UDim2.fromOffset(70, 18)
		local badge = Fallbacks.image(panel.content, "LevelUp", "Badge_LevelUp", { fill = Theme.Colors.HpGreen, fillTransparency = 0, trim = Theme.Colors.Ink, trimThickness = 1, corner = 4 })
		badge.AnchorPoint = Vector2.new(1, 0.5)
		badge.Position = UDim2.new(1, 0, 0.5, 0)
		badge.Size = UDim2.fromOffset(76, 22)
		badge.Visible = false
		local badgeText = Gui.label(badge, "Label", { text = Strings.LevelUp, size = Theme.Sizes.TextLabel, font = Theme.Fonts.Display, stroke = 1 })
		badgeText.Visible = badge.Image == ""
		table.insert(rows, { panel = panel, head = head, name = name, level = level, gained = gained, badge = badge })
	end

	--[[ Right-center: the countdown in place of CONTINUE (R24), and the skip hint ]]
	local returning = Gui.label(safeArea, "Returning", { size = Theme.Sizes.TextBody, font = Theme.Fonts.Bold, color = Theme.Colors.Gold, wrap = true, stroke = 1 })
	local skipHint = Gui.label(safeArea, "SkipHint", { text = Strings.TapToSkip, size = Theme.Sizes.TextLabel, color = Theme.Colors.TextDim })

	local returnAt: number? = nil
	local counting = false
	local shownItems = 0
	local shownMembers: { UITypes.RewardMember } = {}

	local function pop(object: GuiObject)
		object.Visible = true
		local scale = object:FindFirstChildOfClass("UIScale") or Gui.scale(object)
		scale.Scale = 0.6
		TweenService:Create(scale, TweenInfo.new(Theme.motion(Theme.Motion.StampPop), Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end

	-- The end state: every item and badge showing.
	local function revealTheRest()
		for index, slot in slots do
			slot.frame.Visible = index <= shownItems
		end
		for index, row in rows do
			local member = shownMembers[index]
			if member and member.leveledUp and not row.badge.Visible then
				pop(row.badge)
			end
		end
		counting = false
		skipHint.Visible = false
	end

	local function skip()
		if not counting then
			return
		end
		exp.skip()
		currency.skip()
		revealTheRest()
		if callbacks.onSkip then
			callbacks.onSkip()
		end
	end

	local function start(reward: RewardView)
		counting = true
		skipHint.Visible = true
		for _, slot in slots do
			slot.frame.Visible = false
		end
		for _, row in rows do
			row.badge.Visible = false
		end
		-- One tally after another (handoff S6); a zero lands at once.
		exp.countTo(reward.exp, nil, function()
			currency.countTo(reward.currency, nil, function()
				if counting then
					revealTheRest()
				end
			end)
		end)
	end

	catcher.Activated:Connect(skip)

	local function layout(virtual: Vector2)
		local safe = Layout.safeArea(virtual)
		local keepOut = Layout.keepOut(virtual)
		local gap = Theme.Sizes.Gap
		local x0 = math.ceil(safe.x)
		local y0 = math.ceil(safe.y)
		local topClear = math.ceil(keepOut.topLeft.y + keepOut.topLeft.h) + 6 -- under Roblox's menu
		local bottomClear = math.floor(keepOut.bottomLeft.y) -- above the thumbstick and jump button
		local rightClear = math.floor(keepOut.bottomRight.x)
		local columnWidth = math.floor((rightClear - x0 - 2 * gap) / 2)
		local columnHeight = bottomClear - topClear - 6

		-- The title to the right of the top-left keep-out, above the columns.
		local titleX = math.ceil(keepOut.topLeft.x + keepOut.topLeft.w)
		title.Position = UDim2.fromOffset(titleX, y0)
		title.Size = UDim2.fromOffset(columnWidth + gap + 60, topClear - y0 - 4)

		tallies.Position = UDim2.fromOffset(x0, topClear)
		tallies.Size = UDim2.fromOffset(columnWidth, columnHeight)
		party.Position = UDim2.fromOffset(x0 + columnWidth + gap, topClear)
		party.Size = UDim2.fromOffset(columnWidth, columnHeight)

		-- Right-center, where CONTINUE sits in the mockup: never a corner.
		local rightWidth = math.floor(safe.x + safe.w) - rightClear - gap
		returning.Position = UDim2.fromOffset(rightClear + gap, math.floor(virtual.Y * 0.4))
		returning.Size = UDim2.fromOffset(math.max(rightWidth, 120), 60)
		skipHint.Position = UDim2.fromOffset(rightClear + gap, math.floor(virtual.Y * 0.4) + 64)
		skipHint.Size = UDim2.fromOffset(math.max(rightWidth, 120), 20)
	end
	layout(ScreenManager.virtualSize(safeArea))

	local function show(props: Props)
		local reward = props.reward
		returnAt = props.returnAt
		local art = props.won and lettering.Image ~= ""
		lettering.Visible = art
		titleText.Visible = not art
		titleText.Text = if props.won then Strings.Victory else Strings.Defeat
		titleText.TextColor3 = if props.won then Theme.Colors.Gold else Theme.Colors.Crimson

		shownItems = math.min(#reward.items, Results.MAX_ITEMS)
		for index, slot in slots do
			local item = reward.items[index]
			if item then
				if not Fallbacks.skin(slot.icon, item.iconKey) then
					slot.icon.Image = ""
				end
				slot.glyph.Visible = slot.icon.Image == ""
				slot.glyph.Text = string.upper(string.sub(item.name, 1, 1))
				slot.quantity.setText(Strings.format.quantity(item.count))
			end
		end
		shownMembers = reward.members
		for index, row in rows do
			local member = reward.members[index]
			row.panel.frame.Visible = member ~= nil
			if member then
				row.head.setUser(member.userId, string.upper(string.sub(member.name, 1, 2)))
				row.name.Text = member.name
				row.level.Text = Strings.format.level(if member.leveledUp then member.newLevel else member.level)
				row.gained.Text = Strings.format.gained(member.expGained)
			end
		end
		start(reward)
	end

	local function tick(now: number)
		local at = returnAt
		returning.Text = if at then Strings.format.returningIn(secondsLeft(at, now)) else ""
	end

	local screen: ScreenManager.Screen = {
		onOpen = function(props: any?)
			show(props :: Props)
		end,
		onClose = function()
			exp.skip()
			currency.skip()
			counting = false
		end,
		onBack = function()
			skip() -- Back during the count skips it; the screen itself stays until the server returns everyone
			return true
		end,
		onResize = layout,
	}

	return {
		screen = screen,
		tick = tick,
		setReturnAt = function(at: number?)
			returnAt = at
		end,
		skip = skip,
		isCounting = function()
			return counting
		end,
	}
end

return Results
