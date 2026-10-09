--!strict
--[[
	ViewportPortrait — one 3D model in a ViewportFrame with a WorldModel, slowly rotating (handoff
	section 8; S2 and S3, which are Milestone 4). This is the stub: the frame, the WorldModel and a
	placeholder label. `setModel` parents a model and frames it; the camera orbit and the summon
	rig reuse from BattleView come with M4. Only one portrait should be alive at a time on mobile.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UI = ReplicatedStorage:WaitForChild("UI")
local Strings = require(UI:WaitForChild("Strings"))
local Theme = require(UI:WaitForChild("Theme"))
local Core = script.Parent.Parent:WaitForChild("Core")
local Fallbacks = require(Core:WaitForChild("Fallbacks"))
local Gui = require(Core:WaitForChild("Gui"))

export type Props = {
	name: string,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
}

export type ViewportPortrait = {
	frame: ViewportFrame,
	world: WorldModel,
	setModel: (model: Model?) -> (),
	destroy: () -> (),
}

local ViewportPortrait = {}

function ViewportPortrait.new(parent: Instance, props: Props): ViewportPortrait
	local frame = Instance.new("ViewportFrame")
	frame.Name = props.name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = props.size or UDim2.fromOffset(240, 240)
	frame.Position = props.position or UDim2.fromScale(0, 0)
	frame.AnchorPoint = props.anchor or Vector2.zero
	Fallbacks.panel(frame, { fill = Theme.Colors.Obsidian, fillTransparency = 0.3, trim = Theme.Colors.Gold, trimThickness = 1 })

	local world = Instance.new("WorldModel")
	world.Name = "World"
	world.Parent = frame

	local placeholder = Gui.label(frame, "Placeholder", { text = Strings.ComingSoon, size = Theme.Sizes.TextLabel, color = Theme.Colors.TextDim })

	local current: Model? = nil
	local function setModel(model: Model?)
		if current then
			current:Destroy()
		end
		current = model
		placeholder.Visible = model == nil
		if model then
			model.Parent = world
		end
	end

	frame.Parent = parent

	return {
		frame = frame,
		world = world,
		setModel = setModel,
		destroy = function()
			frame:Destroy()
		end,
	}
end

return ViewportPortrait
