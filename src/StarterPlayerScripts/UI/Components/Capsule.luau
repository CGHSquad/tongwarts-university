--!strict
--[[
	Capsule — the small pill that carries a cost ("8 Mana") or a quantity ("x3") (handoff S3, S7).
	Dimmed when the player can't afford it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Theme"))
local Core = script.Parent.Parent:WaitForChild("Core")
local Fallbacks = require(Core:WaitForChild("Fallbacks"))
local Gui = require(Core:WaitForChild("Gui"))

export type Props = {
	name: string,
	text: string,
	color: Color3?,
	assetKey: string?,
	dimmedKey: string?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	layoutOrder: number?,
}

export type Capsule = {
	frame: ImageLabel,
	label: TextLabel,
	setText: (text: string) -> (),
	setDimmed: (dimmed: boolean) -> (),
	destroy: () -> (),
}

local Capsule = {}

function Capsule.new(parent: Instance, props: Props): Capsule
	local color = props.color or Theme.Colors.Purple
	local frame = Fallbacks.image(parent, props.name, props.assetKey or "", { fill = color, fillTransparency = 0, trimThickness = 1, trim = Theme.Colors.Gold, corner = 12 })
	local hasArt = frame.Image ~= ""
	if not hasArt then
		Fallbacks.panel(frame, { fill = color, fillTransparency = 0, trimThickness = 1, trim = Theme.Colors.Gold, corner = 12 })
	end
	frame.Size = props.size or UDim2.fromOffset(88, 28)
	frame.Position = props.position or UDim2.fromScale(0, 0)
	frame.AnchorPoint = props.anchor or Vector2.zero
	frame.LayoutOrder = props.layoutOrder or 0

	local label = Gui.label(frame, "Label", { text = props.text, size = Theme.Sizes.TextLabel + 2, font = Theme.Fonts.Bold })
	Gui.padding(label, 0, 8)

	return {
		frame = frame,
		label = label,
		setText = function(text: string)
			label.Text = text
		end,
		setDimmed = function(dimmed: boolean)
			if hasArt then
				Fallbacks.skin(frame, if dimmed and props.dimmedKey then props.dimmedKey :: string else props.assetKey :: string)
			else
				frame.BackgroundColor3 = if dimmed then Theme.Colors.Disabled else color
			end
			label.TextColor3 = if dimmed then Theme.Colors.TextDim else Theme.Colors.TextLight
		end,
		destroy = function()
			frame:Destroy()
		end,
	}
end

return Capsule
