--!strict
--[[
	Harness — the Studio preview: every base component in every state, on the real safe-zone layout,
	plus a party stack that cycles through MockData's states (1, 2 solo, 2 and 4 members, every
	scenario) so the layouts the handoff asks for can be checked in the Device Emulator without a
	fight running (handoff section 11, M0 report R12). The layout tests open the same harness on the
	fake Roblox and measure it.

	Open it from the command bar during Play:
		require(game.Players.LocalPlayer.PlayerScripts.UI.Preview.Harness).open(game.Players.LocalPlayer.PlayerGui)
	or set Flags.UIHarness and it opens on start (HarnessLauncher).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UI = ReplicatedStorage:WaitForChild("UI")
local Flags = require(UI:WaitForChild("Flags"))
local MockData = require(UI:WaitForChild("MockData"))
local Strings = require(UI:WaitForChild("Strings"))
local Theme = require(UI:WaitForChild("Theme"))
local Combat = ReplicatedStorage:WaitForChild("Combat")
local BattleTypes = require(Combat:WaitForChild("BattleTypes"))
local StatusEffects = require(Combat:WaitForChild("StatusEffects"))

local Core = script.Parent.Parent:WaitForChild("Core")
local Gui = require(Core:WaitForChild("Gui"))
local Layout = require(Core:WaitForChild("Layout"))
local ScreenManager = require(Core:WaitForChild("ScreenManager"))
local Components = script.Parent.Parent:WaitForChild("Components")
local Capsule = require(Components:WaitForChild("Capsule"))
local HeadIcon = require(Components:WaitForChild("HeadIcon"))
local IconMedallion = require(Components:WaitForChild("IconMedallion"))
local ListRow = require(Components:WaitForChild("ListRow"))
local SlicedPanel = require(Components:WaitForChild("SlicedPanel"))
local StatBar = require(Components:WaitForChild("StatBar"))
local Tag = require(Components:WaitForChild("Tag"))
local TallyPlate = require(Components:WaitForChild("TallyPlate"))
local TapButton = require(Components:WaitForChild("TapButton"))
local Toast = require(Components:WaitForChild("Toast"))
local SafeZoneDebug = require(script.Parent:WaitForChild("SafeZoneDebug"))

export type Handle = {
	gui: ScreenGui,
	safeArea: Frame,
	setState: (index: number) -> (),
	next: () -> (),
	prev: () -> (),
	stateIndex: () -> number,
	stateName: () -> string,
	toggleSafeZones: () -> boolean,
	relayout: () -> (),
	close: () -> (),
}

local Harness = {}

local CARD_HEIGHT = 56
local CARD_GAP = 6
local MIN_CARD_HEIGHT = 44

local open: Handle? = nil

type Card = {
	panel: SlicedPanel.SlicedPanel,
	head: HeadIcon.HeadIcon,
	name: TextLabel,
	hp: StatBar.StatBar,
	mana: StatBar.StatBar,
	tag: Tag.Tag,
}

function Harness.isOpen(): boolean
	return open ~= nil
end

function Harness.open(playerGui: PlayerGui): Handle
	if open then
		return open
	end
	local states = MockData.states()
	local index = 1

	-- Everything is placed in Layout's regions, recomputed when the screen changes size.
	local relayout: () -> () = function() end
	local gui, safeArea = ScreenManager.newScreenGui("UIHarness", ScreenManager.DISPLAY_ORDER.Harness, function()
		relayout()
	end)
	local debug = SafeZoneDebug.attach(safeArea)

	--[[ Top bar: title, the state's name, and the controls ]]
	local topBar = Gui.frame(safeArea, "TopBar")
	local title = Gui.label(topBar, "Title", { text = Strings.HarnessTitle, size = Theme.Sizes.TextTitle, font = Theme.Fonts.Display, align = Enum.TextXAlignment.Left, stroke = 1 })
	title.Size = UDim2.new(0.4, 0, 0, 32)
	local stateLabel = Gui.label(topBar, "State", { size = Theme.Sizes.TextBody, font = Theme.Fonts.Bold, color = Theme.Colors.Gold, align = Enum.TextXAlignment.Left })
	stateLabel.Size = UDim2.new(0.4, 0, 0, 24)
	stateLabel.Position = UDim2.fromOffset(0, 32)
	local controls = Gui.frame(topBar, "Controls")
	controls.AnchorPoint = Vector2.new(1, 0)
	controls.Position = UDim2.fromScale(1, 0)
	controls.Size = UDim2.new(0.6, 0, 0, 48)
	Gui.list(controls, Enum.FillDirection.Horizontal, Theme.Sizes.Gap).HorizontalAlignment = Enum.HorizontalAlignment.Right

	--[[ The party stack: one card per party member of the current mock state ]]
	local partyStack = Gui.frame(safeArea, "PartyStack")
	local cards: { Card } = {}

	--[[ The gallery: every component, every state ]]
	local gallery = Instance.new("ScrollingFrame")
	gallery.Name = "Gallery"
	gallery.BackgroundColor3 = Theme.Colors.Obsidian
	gallery.BackgroundTransparency = 0.5
	gallery.BorderSizePixel = 0
	gallery.ScrollBarThickness = 6
	gallery.AutomaticCanvasSize = Enum.AutomaticSize.Y
	gallery.CanvasSize = UDim2.new()
	gallery.Parent = safeArea
	Gui.padding(gallery, Theme.Sizes.Gap)
	Gui.list(gallery, Enum.FillDirection.Vertical, Theme.Sizes.Gap)

	local function section(name: string, height: number): Frame
		local frame = Gui.frame(gallery, name)
		frame.Size = UDim2.new(1, -12, 0, height)
		frame.LayoutOrder = #gallery:GetChildren()
		Gui.list(frame, Enum.FillDirection.Horizontal, Theme.Sizes.Gap).VerticalAlignment = Enum.VerticalAlignment.Center
		return frame
	end

	local toast = Toast.new(safeArea)

	local buttons = section("Buttons", 56)
	TapButton.new(buttons, { name = "Normal", text = Strings.Confirm, keyHint = "Confirm", onTap = function()
		toast.show(Strings.NotEnoughMana)
	end })
	TapButton.new(buttons, { name = "Selected", text = Strings.Attack, color = Theme.Colors.CommandAttack }).setSelected(true)
	TapButton.new(buttons, { name = "Disabled", text = Strings.Guard, color = Theme.Colors.CommandGuard }).setEnabled(false)
	TapButton.new(buttons, { name = "Tiny", text = "48", size = UDim2.fromOffset(20, 20) }) -- bumped to the minimum

	local bars = section("Bars", 40)
	local hpSample = StatBar.new(bars, { name = "Hp", color = Theme.Colors.HpGreen, trail = true, size = UDim2.new(0.5, -4, 0, Theme.Sizes.BarHeight), textFormat = Strings.format.hp })
	hpSample.set(82, 100)
	local manaSample = StatBar.new(bars, { name = "Mana", color = Theme.Colors.ManaBlue, size = UDim2.new(0.5, -4, 0, Theme.Sizes.BarHeight), textFormat = Strings.format.mana })
	manaSample.set(14, 20)

	local capsules = section("Capsules", 32)
	Capsule.new(capsules, { name = "Cost", text = Strings.format.manaCost(8) })
	Capsule.new(capsules, { name = "Dimmed", text = Strings.format.manaCost(40) }).setDimmed(true)
	Capsule.new(capsules, { name = "Quantity", text = Strings.format.quantity(3), color = Theme.Colors.Gold })

	local tags = section("Tags", 30)
	local tagKinds: { Tag.Kind } = { "Weak", "Resist", "Null", "Down", "Front", "KnockedOut" }
	for _, kind in tagKinds do
		Tag.new(tags, { name = kind, kind = kind :: Tag.Kind })
	end

	local medallions = section("Medallions", 48)
	IconMedallion.new(medallions, { name = "Wind", iconKey = "Icon_Wind", glyph = "W" })
	IconMedallion.new(medallions, { name = "Strike", iconKey = "Icon_Physical", glyph = "S", selected = true })
	IconMedallion.new(medallions, { name = "Heal", iconKey = "Icon_Heal", glyph = "+" })

	local rows = Gui.frame(gallery, "Rows")
	rows.Size = UDim2.new(1, -12, 0, 4 * (Theme.Sizes.RowHeight + 24) + 3 * Theme.Sizes.Gap)
	rows.LayoutOrder = #gallery:GetChildren()
	Gui.list(rows, Enum.FillDirection.Vertical, Theme.Sizes.Gap)
	ListRow.new(rows, { name = "Normal", title = "Gale Clap", description = "A harder hit that can daze.", capsule = Strings.format.manaCost(8), glyph = "W", layoutOrder = 1 })
	ListRow.new(rows, { name = "Selected", title = "Strike", description = "A blunt-force bonk. Cheap and reliable.", capsule = Strings.format.manaCost(2), glyph = "S", state = "Selected", weak = Flags.ShowAffinities, layoutOrder = 2 })
	ListRow.new(rows, { name = "Dimmed", title = "Sap Mend", description = "Heals an ally and clears ailments.", capsule = Strings.format.manaCost(6), glyph = "+", state = "Dimmed", layoutOrder = 3 })
	ListRow.new(rows, { name = "Locked", title = "Holy Arrow", capsule = Strings.format.manaCost(12), glyph = "L", state = "Locked", layoutOrder = 4 })

	local misc = section("Misc", 60)
	HeadIcon.new(misc, { name = "Head", userId = nil, fallbackText = "KA" })
	local tally = TallyPlate.new(misc, { name = "Tally", label = Strings.Exp, format = Strings.format.gained, size = UDim2.new(1, -72, 0, 56) })
	tally.countTo(1240)

	--[[ States ]]
	local function clearCards()
		for _, card in cards do
			card.panel.destroy()
		end
		table.clear(cards)
	end

	local function statusLine(battle: BattleTypes.BattleState): string
		local phase = if battle.phase == "setup" then "Initiative" elseif battle.phase == "reward" then (if battle.winner == "Party" then Strings.Victory else Strings.Defeat) else Strings.format.round(battle.round)
		return `{phase}  ·  {battle.log[#battle.log] or ""}`
	end

	local function setState(newIndex: number)
		index = ((newIndex - 1) % #states) + 1
		local state = states[index]
		local snapshot = MockData.snapshot(state.size, state.scenario)
		local battle = snapshot.battle :: BattleTypes.BattleState
		stateLabel.Text = `{index}/{#states}  {state.name}  ·  {statusLine(battle)}`

		clearCards()
		for _, participant in battle.participants do
			if participant.side ~= "Party" then
				continue
			end
			local active = battle.currentActorId == participant.id
			local panel = SlicedPanel.new(partyStack, {
				name = `Card_{participant.id}`,
				assetKey = if active then "Party_CardActive" else "Party_CardNormal",
				look = { trim = if active then Theme.Colors.Cyan else Theme.Colors.Gold, trimThickness = if active then 2 else 1 },
				padding = 4,
			})
			local head = HeadIcon.new(panel.content, { name = "Head", userId = nil, fallbackText = string.sub(participant.ownerName or "?", 1, 2):upper(), size = 40 })
			-- "Title", not "Name": a child called Name can't be reached by dot (it shadows the property).
			local name = Gui.label(panel.content, "Title", { text = participant.name, size = Theme.Sizes.TextLabel + 1, font = Theme.Fonts.Bold, align = Enum.TextXAlignment.Left })
			name.Position = UDim2.fromOffset(46, 0)
			name.Size = UDim2.new(1, -110, 0, 16)
			local hp = StatBar.new(panel.content, { name = "Hp", color = Theme.Colors.HpGreen, trail = true, height = 10, size = UDim2.new(1, -46, 0, 10), position = UDim2.fromOffset(46, 18), textFormat = Strings.format.hp })
			hp.set(participant.hp, participant.maxHp)
			local mana = StatBar.new(panel.content, { name = "Mana", color = Theme.Colors.ManaBlue, height = 10, size = UDim2.new(1, -46, 0, 10), position = UDim2.fromOffset(46, 31), textFormat = Strings.format.mana })
			mana.set(participant.mana, participant.maxMana)
			local statusKind: Tag.Kind = if participant.status == "Left" then "Left" else "KnockedOut"
			local tag = Tag.new(panel.content, { name = "Status", kind = statusKind, position = UDim2.new(1, -4, 0, 0), anchor = Vector2.new(1, 0), size = UDim2.fromOffset(44, 18) })
			tag.frame.Visible = participant.status ~= "Active"
			if participant.statuses[1] then
				local def = StatusEffects[participant.statuses[1].id]
				name.Text = `{participant.name}  ·  {if def then def.name else participant.statuses[1].id}`
			end
			table.insert(cards, { panel = panel, head = head, name = name, hp = hp, mana = mana, tag = tag })
		end
		relayout()
	end

	relayout = function()
		local virtual = ScreenManager.virtualSize(safeArea)
		local regions = Layout.regions(virtual)
		local top, center, right = regions.topCenter, regions.center, regions.right
		topBar.Position = UDim2.fromOffset(top.x, top.y)
		topBar.Size = UDim2.fromOffset(top.w, top.h)
		gallery.Position = UDim2.fromOffset(center.x, center.y)
		gallery.Size = UDim2.fromOffset(center.w, math.floor(virtual.Y * (1 - Layout.KEEP_OUT.bottomLeft.h)) - center.y - Theme.Sizes.Gap)
		partyStack.Position = UDim2.fromOffset(right.x, right.y)
		partyStack.Size = UDim2.fromOffset(right.w, right.h)
		-- Cards fit the column: shrink them (never below the minimum) when four won't fit at full size.
		local count = #cards
		local height = CARD_HEIGHT
		if count > 0 then
			height = math.max(MIN_CARD_HEIGHT, math.min(CARD_HEIGHT, (right.h - CARD_GAP * (count - 1)) / count))
		end
		for i, card in cards do
			card.panel.frame.Position = UDim2.fromOffset(0, (i - 1) * (height + CARD_GAP))
			card.panel.frame.Size = UDim2.fromOffset(right.w, height)
		end
	end

	local handle: Handle
	TapButton.new(controls, { name = "Prev", text = Strings.HarnessPrev, size = UDim2.fromOffset(72, 48), layoutOrder = 1, onTap = function()
		setState(index - 1)
	end })
	TapButton.new(controls, { name = "Next", text = Strings.HarnessNext, size = UDim2.fromOffset(72, 48), layoutOrder = 2, onTap = function()
		setState(index + 1)
	end })
	TapButton.new(controls, { name = "SafeZones", text = Strings.HarnessSafeZones, size = UDim2.fromOffset(120, 48), layoutOrder = 3, onTap = function()
		debug.toggle()
	end })
	TapButton.new(controls, { name = "Close", text = Strings.Close, size = UDim2.fromOffset(84, 48), layoutOrder = 4, color = Theme.Colors.Crimson, onTap = function()
		handle.close()
	end })

	-- The combat HUD stays out of the way while the harness is up.
	local battleUi = playerGui:FindFirstChild("BattleUI")
	local battleUiWasEnabled = if battleUi and battleUi:IsA("ScreenGui") then battleUi.Enabled else nil
	if battleUi and battleUi:IsA("ScreenGui") then
		battleUi.Enabled = false
	end

	gui.Parent = playerGui
	gui.Enabled = true
	setState(1)

	handle = {
		gui = gui,
		safeArea = safeArea,
		setState = setState,
		next = function()
			setState(index + 1)
		end,
		prev = function()
			setState(index - 1)
		end,
		stateIndex = function()
			return index
		end,
		stateName = function()
			return states[index].name
		end,
		toggleSafeZones = debug.toggle,
		relayout = relayout,
		close = function()
			if open ~= handle then
				return
			end
			open = nil
			if battleUi and battleUi:IsA("ScreenGui") and battleUiWasEnabled ~= nil then
				battleUi.Enabled = battleUiWasEnabled
			end
			gui:Destroy()
		end,
	}
	open = handle
	return handle
end

function Harness.close()
	if open then
		open.close()
	end
end

return Harness
