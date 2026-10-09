--!strict
--[[
	IconMedallion — a round disc with a gold ring and an icon in the middle (handoff section 8),
	with a selected state (cyan ring and glow). Icons come from Assets by key; with no art the
	medallion shows a short glyph (the first letter of the element) instead.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Theme"))
local Core = script.Parent.Parent:WaitForChild("Core")
local Fallbacks = require(Core:WaitForChild("Fallbacks"))
local Gui = require(Core:WaitForChild("Gui"))

export type Props = {
	name: string,
	iconKey: string?,
	glyph: string?, -- fallback text when there is no icon art
	size: number?, -- diameter in design pixels
	position: UDim2?,
	anchor: Vector2?,
	layoutOrder: number?,
	selected: boolean?,
}

export type IconMedallion = {
	frame: ImageLabel,
	setSelected: (selected: boolean) -> (),
	setIcon: (iconKey: string?, glyph: string?) -> (),
	destroy: () -> (),
}

local IconMedallion = {}

function IconMedallion.new(parent: Instance, props: Props): IconMedallion
	local size = props.size or 44
	local frame = Fallbacks.image(parent, props.name, "Icon_MedallionEmpty", { fill = Theme.Colors.Navy, fillTransparency = 0, trim = Theme.Colors.Gold, trimThickness = 2, corner = size })
	frame.Size = UDim2.fromOffset(size, size)
	frame.Position = props.position or UDim2.fromScale(0, 0)
	frame.AnchorPoint = props.anchor or Vector2.zero
	frame.LayoutOrder = props.layoutOrder or 0
	Gui.aspect(frame, 1)

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Image = ""
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.62, 0.62)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = frame

	local glyph = Gui.label(frame, "Glyph", { size = math.floor(size * 0.42), font = Theme.Fonts.Display, stroke = 1 })

	local function setIcon(iconKey: string?, text: string?)
		local hasArt = iconKey ~= nil and Fallbacks.skin(icon, iconKey :: string)
		icon.Visible = hasArt
		glyph.Visible = not hasArt
		glyph.Text = text or ""
	end
	setIcon(props.iconKey, props.glyph)

	local stroke = frame:FindFirstChildOfClass("UIStroke")
	local function setSelected(selected: boolean)
		local key = if selected then "Icon_MedallionSelected" else "Icon_MedallionEmpty"
		if not Fallbacks.skin(frame, key) then
			frame.Image = ""
			frame.BackgroundTransparency = 0
			if stroke then
				stroke.Color = if selected then Theme.Colors.Cyan else Theme.Colors.Gold
				stroke.Thickness = if selected then 3 else 2
			end
		end
	end
	setSelected(props.selected == true)

	return {
		frame = frame,
		setSelected = setSelected,
		setIcon = setIcon,
		destroy = function()
			frame:Destroy()
		end,
	}
end

return IconMedallion
