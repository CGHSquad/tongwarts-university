--!strict
--[[
	ListRow — one row of a skill or item list (handoff S7, S3): a medallion on the left, the name,
	a cost or quantity capsule on the right, and a description that shows when the row is selected.
	States: Normal, Selected (wider glow, expanded), Dimmed (can't afford: visible, tappable only to
	say why), Locked (padlock, Skill menu only). A WEAK tag slot sits on the left edge; it only
	shows when told to.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Theme = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Theme"))
local Core = script.Parent.Parent:WaitForChild("Core")
local Audio = require(Core:WaitForChild("Audio"))
local Fallbacks = require(Core:WaitForChild("Fallbacks"))
local Gui = require(Core:WaitForChild("Gui"))
local Capsule = require(script.Parent:WaitForChild("Capsule"))
local IconMedallion = require(script.Parent:WaitForChild("IconMedallion"))
local Tag = require(script.Parent:WaitForChild("Tag"))

export type State = "Normal" | "Selected" | "Dimmed" | "Locked"

export type Props = {
	name: string,
	title: string,
	description: string?,
	capsule: string?, -- cost or quantity text; nil for no capsule
	iconKey: string?,
	glyph: string?,
	state: State?,
	weak: boolean?, -- show the WEAK tag
	onTap: (() -> ())?,
	layoutOrder: number?,
	width: UDim?,
}

export type ListRow = {
	button: ImageButton,
	setState: (state: State) -> (),
	setWeak: (weak: boolean) -> (),
	setCapsule: (text: string?) -> (),
	getState: () -> State,
	destroy: () -> (),
}

local ROW_KEYS: { [string]: string } = {
	Normal = "SkillList_RowNormal",
	Selected = "SkillList_RowSelected",
	Dimmed = "SkillList_RowDimmed",
	Locked = "SkillList_RowLocked",
}

local ListRow = {}

function ListRow.new(parent: Instance, props: Props): ListRow
	local rowHeight = Theme.Sizes.RowHeight
	local button = Instance.new("ImageButton")
	button.Name = props.name
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundTransparency = 1
	button.Size = UDim2.new(props.width or UDim.new(1, 0), UDim.new(0, rowHeight))
	button.LayoutOrder = props.layoutOrder or 0
	button.ClipsDescendants = true
	local hasArt = Fallbacks.skin(button, ROW_KEYS.Normal)
	if not hasArt then
		Fallbacks.panel(button, { fill = Theme.Colors.Obsidian, fillTransparency = 0.05, trim = Theme.Colors.Gold, trimThickness = 1 })
	end
	local stroke = button:FindFirstChildOfClass("UIStroke")

	local medallion = IconMedallion.new(button, { name = "Icon", iconKey = props.iconKey, glyph = props.glyph, size = 40, position = UDim2.new(0, 10, 0, 8) })

	local title = Gui.label(button, "Title", { text = props.title, size = Theme.Sizes.TextBody, font = Theme.Fonts.Bold, align = Enum.TextXAlignment.Left })
	title.Size = UDim2.new(1, -170, 0, rowHeight)
	title.Position = UDim2.fromOffset(60, 0)

	local description = Gui.label(button, "Description", { text = props.description or "", size = Theme.Sizes.TextLabel + 1, color = Theme.Colors.TextDim, align = Enum.TextXAlignment.Left, wrap = true })
	description.Size = UDim2.new(1, -70, 0, 24)
	description.Position = UDim2.fromOffset(60, rowHeight - 4)
	description.Visible = false

	local capsule: Capsule.Capsule? = nil
	if props.capsule then
		capsule = Capsule.new(button, { name = "Cost", text = props.capsule :: string, assetKey = "Capsule_Cost", dimmedKey = "Capsule_CostDimmed", position = UDim2.new(1, -10, 0, rowHeight / 2), anchor = Vector2.new(1, 0.5) })
	end

	local weakTag = Tag.new(button, { name = "WeakTag", kind = "Weak", position = UDim2.new(0, -6, 0.5, 0), anchor = Vector2.new(0, 0.5), size = UDim2.fromOffset(56, 22) })
	weakTag.frame.Visible = props.weak == true

	local lock = Gui.label(button, "Lock", { text = "🔒", size = Theme.Sizes.TextBody })
	lock.Size = UDim2.fromOffset(32, 32)
	lock.Position = UDim2.new(0, 14, 0.5, -16)
	lock.Visible = false

	local state: State = props.state or "Normal"
	local function setState(newState: State)
		state = newState
		local selected = state == "Selected"
		if hasArt then
			Fallbacks.skin(button, ROW_KEYS[state])
		else
			button.BackgroundColor3 = if selected then Theme.Colors.Navy else Theme.Colors.Obsidian
			button.BackgroundTransparency = if state == "Locked" then 0.4 elseif state == "Dimmed" then 0.35 else 0.05
			if stroke then
				stroke.Color = if selected then Theme.Colors.Cyan elseif state == "Dimmed" or state == "Locked" then Theme.Colors.Disabled else Theme.Colors.Gold
				stroke.Thickness = if selected then 2 else 1
			end
		end
		title.TextColor3 = if state == "Dimmed" or state == "Locked" then Theme.Colors.TextDim else Theme.Colors.TextLight
		medallion.setSelected(selected)
		medallion.frame.Visible = state ~= "Locked"
		lock.Visible = state == "Locked"
		if capsule then
			capsule.setDimmed(state == "Dimmed" or state == "Locked")
		end
		local expanded = selected and (props.description or "") ~= ""
		description.Visible = expanded
		local height = if expanded then rowHeight + 24 else rowHeight
		TweenService:Create(button, TweenInfo.new(Theme.motion(Theme.Motion.Fade)), { Size = UDim2.new(button.Size.X, UDim.new(0, height)) }):Play()
	end
	setState(state)

	local connection = button.Activated:Connect(function()
		if state == "Locked" then
			return
		end
		Audio.play("Tap")
		if props.onTap then
			props.onTap()
		end
	end)
	button.Parent = parent

	return {
		button = button,
		setState = setState,
		setWeak = function(weak: boolean)
			weakTag.frame.Visible = weak
		end,
		setCapsule = function(text: string?)
			if capsule then
				capsule.frame.Visible = text ~= nil
				capsule.setText(text or "")
			end
		end,
		getState = function()
			return state
		end,
		destroy = function()
			connection:Disconnect()
			button:Destroy()
		end,
	}
end

return ListRow
