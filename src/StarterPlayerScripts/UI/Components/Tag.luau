--!strict
--[[
	Tag — the small angular labels: WEAK / RESIST / NULL / DOWN / FRONT (handoff section 8). Each
	kind has its color and its art key; the word is always live text, with a shape and color so it
	never relies on color alone (handoff section 10).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UI = ReplicatedStorage:WaitForChild("UI")
local Strings = require(UI:WaitForChild("Strings"))
local Theme = require(UI:WaitForChild("Theme"))
local Core = script.Parent.Parent:WaitForChild("Core")
local Fallbacks = require(Core:WaitForChild("Fallbacks"))
local Gui = require(Core:WaitForChild("Gui"))

export type Kind = "Weak" | "Resist" | "Null" | "Down" | "Front" | "KnockedOut" | "Left"

export type Props = {
	name: string,
	kind: Kind,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	layoutOrder: number?,
}

export type Tag = {
	frame: ImageLabel,
	label: TextLabel,
	setKind: (kind: Kind) -> (),
	destroy: () -> (),
}

local KINDS: { [string]: { text: string, color: Color3, key: string? } } = {
	Weak = { text = Strings.Weak, color = Theme.Colors.Crimson, key = "Tag_Weak" },
	Resist = { text = Strings.Resist, color = Theme.Colors.ManaBlue, key = "Tag_Resist" },
	Null = { text = Strings.Null, color = Theme.Colors.Disabled, key = "Tag_Null" },
	Down = { text = Strings.Down, color = Theme.Colors.Crimson, key = "Tag_Down" },
	Front = { text = Strings.Front, color = Theme.Colors.Cyan, key = nil },
	KnockedOut = { text = Strings.KnockedOut, color = Theme.Colors.Disabled, key = nil },
	Left = { text = Strings.Left, color = Theme.Colors.Disabled, key = nil },
}

local Tag = {}

function Tag.new(parent: Instance, props: Props): Tag
	local look = KINDS[props.kind]
	local frame = Fallbacks.image(parent, props.name, look.key or "", { fill = look.color, fillTransparency = 0, trim = Theme.Colors.Ink, trimThickness = 1, corner = 3 })
	if frame.Image == "" then
		Fallbacks.panel(frame, { fill = look.color, fillTransparency = 0, trim = Theme.Colors.Ink, trimThickness = 1, corner = 3 })
	end
	frame.Size = props.size or UDim2.fromOffset(64, 24)
	frame.Position = props.position or UDim2.fromScale(0, 0)
	frame.AnchorPoint = props.anchor or Vector2.zero
	frame.LayoutOrder = props.layoutOrder or 0
	frame.Rotation = -4 -- the angular lean from the mockups; art replaces it

	local label = Gui.label(frame, "Label", { text = look.text, size = Theme.Sizes.TextLabel + 1, font = Theme.Fonts.Display, stroke = 1 })

	local function setKind(kind: Kind)
		local next = KINDS[kind]
		label.Text = next.text
		if next.key == nil or not Fallbacks.skin(frame, next.key) then
			frame.Image = ""
			frame.BackgroundTransparency = 0
			frame.BackgroundColor3 = next.color
		end
	end

	return {
		frame = frame,
		label = label,
		setKind = setKind,
		destroy = function()
			frame:Destroy()
		end,
	}
end

return Tag
