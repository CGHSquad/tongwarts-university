--!strict
--[[
	SkillList — S7: the list Spell opens (handoff section 7). A header plate, one ListRow per
	ability from the summon's own kit (name, element medallion, Mana cost), six rows on screen and
	more by scrolling; a selected row widens and shows its description; a row the player can't
	afford is dimmed and says why when tapped; BACK returns to the ring. Confirm hands the chosen
	ability back to the combat screen, which handles targeting and the request to the server.

	The same list serves a read-only Skill menu later (rows can be Locked) and the Item variant
	behind its flag.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UI = ReplicatedStorage:WaitForChild("UI")
local Strings = require(UI:WaitForChild("Strings"))
local Theme = require(UI:WaitForChild("Theme"))
local UITypes = require(UI:WaitForChild("UITypes"))

local Root = script.Parent.Parent
local Core = Root:WaitForChild("Core")
local Gui = require(Core:WaitForChild("Gui"))
local Layout = require(Core:WaitForChild("Layout"))
local ScreenManager = require(Core:WaitForChild("ScreenManager"))
local Components = Root:WaitForChild("Components")
local ListRow = require(Components:WaitForChild("ListRow"))
local SlicedPanel = require(Components:WaitForChild("SlicedPanel"))
local TapButton = require(Components:WaitForChild("TapButton"))
local Toast = require(Components:WaitForChild("Toast"))

type AbilityRow = UITypes.AbilityRow

export type Props = {
	title: string, -- Strings.Spell, or the Skill menu's / Item's title
	rows: { AbilityRow },
	readOnly: boolean?,
}

export type Callbacks = {
	onConfirm: (abilityId: string) -> (),
	onBack: () -> (),
}

export type SkillList = {
	screen: ScreenManager.Screen,
	selectedId: () -> string?,
	refresh: (rows: { AbilityRow }) -> (), -- the same list with fresh affordability
	confirm: () -> (), -- the Confirm button, for the keyboard
}

local SkillList = {}

SkillList.NAME = "SkillList"
SkillList.ROWS_ON_SCREEN = 6

-- Builds the screen into a ScreenGui the ScreenManager created. Register it with
-- manager:register(SkillList.NAME, ScreenManager.DISPLAY_ORDER.SkillList, function(...) return SkillList.build(...).screen end).
function SkillList.build(gui: ScreenGui, safeArea: Frame, callbacks: Callbacks): SkillList
	local header = Gui.frame(safeArea, "Header")
	local headerPlate = SlicedPanel.new(header, { name = "Plate", assetKey = "SkillList_Header", look = { fill = Theme.Colors.Purple, fillTransparency = 0.1, trim = Theme.Colors.Gold }, padding = 4 })
	local title = Gui.label(headerPlate.content, "Title", { size = Theme.Sizes.TextTitle, font = Theme.Fonts.Display, stroke = 2 })

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = safeArea
	local rowsFrame = Gui.frame(list, "Rows")
	rowsFrame.Size = UDim2.new(1, -8, 0, 0)
	rowsFrame.AutomaticSize = Enum.AutomaticSize.Y
	Gui.list(rowsFrame, Enum.FillDirection.Vertical, Theme.Sizes.Gap)

	local toast = Toast.new(safeArea)
	local rows: { [string]: ListRow.ListRow } = {}
	local rowData: { [string]: AbilityRow } = {}
	local selected: string? = nil
	local readOnly = false

	local confirm: TapButton.TapButton
	local back: TapButton.TapButton

	local function restyle()
		for id, row in rows do
			local data = rowData[id]
			local state: ListRow.State = if data.locked then "Locked" elseif not data.canAfford then "Dimmed" elseif id == selected then "Selected" else "Normal"
			row.setState(state)
		end
		local chosen = if selected then rowData[selected :: string] else nil
		confirm.setEnabled(not readOnly and chosen ~= nil and chosen.canAfford and not chosen.locked)
	end

	local function clearRows()
		for _, row in rows do
			row.destroy()
		end
		table.clear(rows)
		table.clear(rowData)
	end

	local function setRows(data: { AbilityRow })
		clearRows()
		for index, ability in data do
			rowData[ability.id] = ability
			local id = ability.id
			rows[id] = ListRow.new(rowsFrame, {
				name = id,
				title = ability.name,
				description = ability.description,
				capsule = Strings.format.manaCost(ability.cost.mana),
				iconKey = ability.iconKey,
				glyph = string.sub(ability.elementId or ability.name, 1, 1),
				weak = ability.hitsKnownWeakness,
				layoutOrder = index,
				onTap = function()
					local row = rowData[id]
					if row.locked then
						return
					elseif not row.canAfford then
						toast.show(Strings.NotEnoughMana)
						return
					end
					if selected == id and not readOnly then
						callbacks.onConfirm(id) -- a second tap confirms
						return
					end
					selected = id
					restyle()
				end,
			})
		end
		if selected == nil or rowData[selected :: string] == nil then
			selected = nil
			for _, ability in data do
				if ability.canAfford and not ability.locked then
					selected = ability.id
					break
				end
			end
		end
		restyle()
	end

	local function confirmSelected()
		if selected and confirm.isEnabled() then
			callbacks.onConfirm(selected :: string)
		end
	end

	confirm = TapButton.new(safeArea, {
		name = "Confirm",
		text = Strings.Confirm,
		keyHint = "Confirm",
		color = Theme.Colors.Gold,
		textColor = Theme.Colors.Obsidian,
		sound = "Confirm",
		onTap = confirmSelected,
	})
	back = TapButton.new(safeArea, {
		name = "Back",
		text = Strings.Back,
		keyHint = "Back",
		color = Theme.Colors.Obsidian,
		assetKey = "Button_BackNormal",
		pressedKey = "Button_BackPressed",
		sound = "Back",
		onTap = callbacks.onBack,
	})

	local function layout(virtual: Vector2)
		local regions = Layout.regions(virtual)
		local right, topRight = regions.right, regions.topRight
		back.button.Size = UDim2.fromOffset(88, Theme.Sizes.TapMin)
		back.button.Position = UDim2.fromOffset(topRight.x + topRight.w - 88, topRight.y)
		header.Position = UDim2.fromOffset(right.x, right.y)
		header.Size = UDim2.fromOffset(math.floor(right.w * 0.6), 40)
		local listTop = right.y + 46
		local confirmHeight = Theme.Sizes.TapComfortable
		list.Position = UDim2.fromOffset(right.x, listTop)
		list.Size = UDim2.fromOffset(right.w, right.y + right.h - listTop - confirmHeight - Theme.Sizes.Gap)
		confirm.button.Size = UDim2.fromOffset(right.w, confirmHeight)
		confirm.button.Position = UDim2.fromOffset(right.x, right.y + right.h - confirmHeight)
	end
	layout(ScreenManager.virtualSize(safeArea))

	local screen: ScreenManager.Screen = {
		onOpen = function(props: any?)
			local p = props :: Props
			title.Text = p.title
			readOnly = p.readOnly == true
			selected = nil
			setRows(p.rows)
			confirm.button.Visible = not readOnly
		end,
		onClose = function()
			toast.hide()
		end,
		onBack = function()
			callbacks.onBack()
			return true
		end,
		onResize = layout,
	}

	return {
		screen = screen,
		selectedId = function()
			return selected
		end,
		refresh = setRows,
		confirm = confirmSelected,
	}
end

return SkillList
