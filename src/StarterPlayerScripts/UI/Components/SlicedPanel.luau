--!strict
--[[
	SlicedPanel — a panel drawn from a 9-slice image when its art exists, or the themed fallback
	look when it doesn't (handoff section 8). Content goes in `content`, which is padded.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Theme"))
local Core = script.Parent.Parent:WaitForChild("Core")
local Fallbacks = require(Core:WaitForChild("Fallbacks"))
local Gui = require(Core:WaitForChild("Gui"))

export type Props = {
	name: string,
	assetKey: string?,
	look: Fallbacks.PanelLook?,
	padding: number?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	layoutOrder: number?,
}

export type SlicedPanel = {
	frame: ImageLabel,
	content: Frame,
	setLook: (look: Fallbacks.PanelLook) -> (),
	destroy: () -> (),
}

local SlicedPanel = {}

function SlicedPanel.new(parent: Instance, props: Props): SlicedPanel
	local frame = Fallbacks.image(parent, props.name, props.assetKey or "", props.look)
	if props.assetKey == nil then
		Fallbacks.panel(frame, props.look)
	end
	frame.Size = props.size or UDim2.fromScale(1, 1)
	frame.Position = props.position or UDim2.fromScale(0, 0)
	frame.AnchorPoint = props.anchor or Vector2.zero
	frame.LayoutOrder = props.layoutOrder or 0

	local content = Gui.frame(frame, "Content")
	content.Size = UDim2.fromScale(1, 1)
	Gui.padding(content, props.padding or Theme.Sizes.Margin)

	local function setLook(look: Fallbacks.PanelLook)
		if frame.Image ~= "" then
			return -- art decides the look
		end
		frame.BackgroundColor3 = look.fill or Theme.Panel.Fill
		local stroke = frame:FindFirstChildOfClass("UIStroke")
		if stroke and look.trim then
			stroke.Color = look.trim
		end
	end

	return {
		frame = frame,
		content = content,
		setLook = setLook,
		destroy = function()
			frame:Destroy()
		end,
	}
end

return SlicedPanel
