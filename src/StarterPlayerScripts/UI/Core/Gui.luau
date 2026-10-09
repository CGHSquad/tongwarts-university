--!strict
--[[
	Gui — small builders so component code stays readable: containers, labels, strokes, gradients,
	layouts. Every color and size comes from Theme.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Theme"))

local Gui = {}

function Gui.corner(parent: GuiObject, radius: number?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or Theme.Panel.Corner)
	corner.Parent = parent
	return corner
end

function Gui.padding(parent: GuiObject, all: number, horizontal: number?): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, all)
	padding.PaddingBottom = UDim.new(0, all)
	padding.PaddingLeft = UDim.new(0, horizontal or all)
	padding.PaddingRight = UDim.new(0, horizontal or all)
	padding.Parent = parent
	return padding
end

function Gui.stroke(parent: GuiObject, color: Color3, thickness: number, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency or 0
	stroke.Parent = parent
	return stroke
end

function Gui.gradient(parent: GuiObject, from: Color3, to: Color3, rotation: number?): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(from, to)
	gradient.Rotation = rotation or 0
	gradient.Parent = parent
	return gradient
end

function Gui.list(parent: GuiObject, direction: Enum.FillDirection, spacing: number): UIListLayout
	local list = Instance.new("UIListLayout")
	list.FillDirection = direction
	list.Padding = UDim.new(0, spacing)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = parent
	return list
end

function Gui.scale(parent: GuiObject, scale: number?): UIScale
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = scale or 1
	uiScale.Parent = parent
	return uiScale
end

function Gui.aspect(parent: GuiObject, ratio: number): UIAspectRatioConstraint
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = ratio
	aspect.Parent = parent
	return aspect
end

-- A see-through frame, only there for layout.
function Gui.frame(parent: Instance, name: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

export type LabelProps = {
	text: string?,
	size: number?, -- Theme.Sizes.TextBody by default
	font: Enum.Font?,
	color: Color3?,
	align: Enum.TextXAlignment?,
	wrap: boolean?,
	stroke: number?, -- a black outline, for lettering
}

function Gui.label(parent: Instance, name: string, props: LabelProps?): TextLabel
	local p: LabelProps = props or {}
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Font = p.font or Theme.Fonts.Body
	label.TextSize = p.size or Theme.Sizes.TextBody
	label.TextColor3 = p.color or Theme.Colors.TextLight
	label.TextXAlignment = p.align or Enum.TextXAlignment.Center
	label.TextWrapped = p.wrap == true
	label.TextTruncate = if p.wrap then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd
	label.Text = p.text or ""
	if p.stroke then
		label.TextStrokeColor3 = Theme.Colors.Ink
		label.TextStrokeTransparency = 0
		Gui.stroke(label, Theme.Colors.Ink, p.stroke)
	end
	label.Parent = parent
	return label
end

-- Fades every text/image/background in a tree; 1 = gone. For screens opening and closing.
function Gui.setTransparency(root: GuiObject, transparency: number)
	local function apply(object: Instance)
		local target = object :: any -- a union of classes can't be assigned through under the old solver
		if object:IsA("TextLabel") or object:IsA("TextButton") then
			target.TextTransparency = transparency
		end
		if object:IsA("ImageLabel") or object:IsA("ImageButton") then
			target.ImageTransparency = transparency
		end
		if object:IsA("GuiObject") and object.BackgroundTransparency < 1 then
			object.BackgroundTransparency = transparency
		end
		if object:IsA("UIStroke") then
			object.Transparency = transparency
		end
	end
	apply(root)
	for _, descendant in root:GetDescendants() do
		apply(descendant)
	end
end

return Gui
