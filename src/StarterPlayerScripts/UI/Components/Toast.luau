--!strict
--[[
	Toast — a short message at the top center ("Not enough Mana", why the server refused a request)
	that slides in and fades after a few seconds (handoff section 8). One Toast per screen; `show`
	replaces whatever is up.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Theme = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Theme"))
local Core = script.Parent.Parent:WaitForChild("Core")
local Fallbacks = require(Core:WaitForChild("Fallbacks"))
local Gui = require(Core:WaitForChild("Gui"))

export type Props = {
	name: string?,
	seconds: number?,
	color: Color3?, -- text color; danger red by default
}

export type Toast = {
	frame: ImageLabel,
	show: (text: string, seconds: number?) -> (),
	hide: () -> (),
	destroy: () -> (),
}

local Toast = {}

function Toast.new(parent: Instance, props: Props?): Toast
	local p: Props = props or {}
	local frame = Fallbacks.image(parent, p.name or "Toast", "", { fill = Theme.Colors.Obsidian, fillTransparency = 0.05, trim = Theme.Colors.Gold, trimThickness = 1 })
	Fallbacks.panel(frame, { fill = Theme.Colors.Obsidian, fillTransparency = 0.05, trim = Theme.Colors.Gold, trimThickness = 1 })
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0.17, 0)
	frame.Size = UDim2.fromOffset(360, 44)
	frame.Visible = false
	frame.ZIndex = 50

	local label = Gui.label(frame, "Label", { size = Theme.Sizes.TextBody, font = Theme.Fonts.Bold, color = p.color or Theme.Colors.Crimson })
	Gui.padding(label, 0, 12)

	local count = 0
	local function hide()
		frame.Visible = false
	end

	local function show(text: string, seconds: number?)
		count += 1
		local mine = count
		label.Text = text
		label.TextTransparency = 0
		frame.Visible = true
		frame.Position = UDim2.new(0.5, 0, 0.17, -12)
		TweenService:Create(frame, TweenInfo.new(Theme.motion(Theme.Motion.Fade), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0.17, 0) }):Play()
		task.delay(seconds or p.seconds or 3, function()
			if count == mine then
				hide()
			end
		end)
	end

	return {
		frame = frame,
		show = show,
		hide = hide,
		destroy = function()
			frame:Destroy()
		end,
	}
end

return Toast
