--!strict
--[[
	StatBar — a track and a fill that tweens to the new value, with an optional trailing "damage"
	bar that follows a beat later (handoff S1 animation), and the numbers written on top.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Theme = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Theme"))
local Core = script.Parent.Parent:WaitForChild("Core")
local Fallbacks = require(Core:WaitForChild("Fallbacks"))
local Gui = require(Core:WaitForChild("Gui"))

export type Props = {
	name: string,
	color: Color3,
	trackKey: string?,
	fillKey: string?,
	height: number?,
	trail: boolean?, -- the delayed damage trail
	showText: boolean?,
	textFormat: ((current: number, max: number) -> string)?,
	layoutOrder: number?,
	size: UDim2?,
	position: UDim2?,
}

export type StatBar = {
	frame: ImageLabel,
	fill: ImageLabel,
	text: TextLabel?,
	set: (current: number, max: number, animate: boolean?) -> (),
	destroy: () -> (),
}

local StatBar = {}

local function fraction(current: number, max: number): number
	return if max <= 0 then 0 else math.clamp(current / max, 0, 1)
end

function StatBar.new(parent: Instance, props: Props): StatBar
	local height = props.height or Theme.Sizes.BarHeight
	local track = Fallbacks.image(parent, props.name, props.trackKey or "", {
		fill = Theme.Colors.Obsidian,
		fillTransparency = 0.2,
		trim = Theme.Colors.Gold,
		trimThickness = 1,
		corner = 3,
	})
	if props.trackKey == nil then
		Fallbacks.panel(track, { fill = Theme.Colors.Obsidian, fillTransparency = 0.2, trim = Theme.Colors.Gold, trimThickness = 1, corner = 3 })
	end
	track.Size = props.size or UDim2.new(1, 0, 0, height)
	track.Position = props.position or UDim2.fromScale(0, 0)
	track.LayoutOrder = props.layoutOrder or 0
	track.ClipsDescendants = true

	local trail: ImageLabel? = nil
	if props.trail then
		local t = Fallbacks.image(track, "Trail", "", { fill = Theme.Colors.Crimson, fillTransparency = 0.2, trimThickness = 0, corner = 3 })
		Fallbacks.panel(t, { fill = Theme.Colors.Crimson, fillTransparency = 0.2, trimThickness = 0, corner = 3 })
		t.Size = UDim2.fromScale(1, 1)
		t.ZIndex = 1
		trail = t
	end

	local fill = Fallbacks.image(track, "Fill", props.fillKey or "", { fill = props.color, fillTransparency = 0, trimThickness = 0, corner = 3 })
	if props.fillKey == nil then
		Fallbacks.panel(fill, { fill = props.color, fillTransparency = 0, trimThickness = 0, corner = 3 })
	else
		fill.ImageColor3 = Theme.Colors.White
	end
	fill.Size = UDim2.fromScale(1, 1)
	fill.ZIndex = 2

	local text: TextLabel? = nil
	if props.showText ~= false then
		text = Gui.label(track, "Value", { size = math.max(Theme.Sizes.TextLabel, height - 2), font = Theme.Fonts.Bold, stroke = 1 })
		local t = text :: TextLabel
		t.ZIndex = 3
	end
	local format = props.textFormat

	local function set(current: number, max: number, animate: boolean?)
		local target = UDim2.fromScale(fraction(current, max), 1)
		if animate then
			TweenService:Create(fill, TweenInfo.new(Theme.motion(Theme.Motion.Tween), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = target }):Play()
			if trail then
				TweenService:Create(trail, TweenInfo.new(Theme.motion(Theme.Motion.Tween), Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, Theme.motion(Theme.Motion.BarTrailDelay)), { Size = target }):Play()
			end
		else
			fill.Size = target
			if trail then
				trail.Size = target
			end
		end
		if text then
			text.Text = if format then format(current, max) else `{current} / {max}`
		end
	end
	set(0, 1)

	return {
		frame = track,
		fill = fill,
		text = text,
		set = set,
		destroy = function()
			track:Destroy()
		end,
	}
end

return StatBar
