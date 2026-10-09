--!strict
--[[
	SafeZoneDebug — translucent red rectangles over the three keep-out regions and a green outline
	around the safe area, so a layout that strays into a corner is obvious in the Device Emulator
	(handoff section 11). Drawn in Scale units from Layout's fractions, so it needs no resize logic.
]]

local Core = script.Parent.Parent:WaitForChild("Core")
local Layout = require(Core:WaitForChild("Layout"))

export type SafeZoneDebug = {
	frame: Frame,
	setVisible: (visible: boolean) -> (),
	toggle: () -> boolean,
	destroy: () -> (),
}

local SafeZoneDebug = {}

local function box(parent: Instance, name: string, position: UDim2, size: UDim2, color: Color3, transparency: number)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	frame.ZIndex = 1000
	frame.Parent = parent
	return frame
end

function SafeZoneDebug.attach(safeArea: Frame): SafeZoneDebug
	local root = Instance.new("Frame")
	root.Name = "SafeZoneDebug"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Visible = false
	root.ZIndex = 1000
	root.Parent = safeArea

	local k = Layout.KEEP_OUT
	local red = Color3.fromRGB(255, 40, 40)
	box(root, "TopLeft", UDim2.fromScale(0, 0), UDim2.fromScale(k.topLeft.w, k.topLeft.h), red, 0.6)
	box(root, "BottomLeft", UDim2.fromScale(0, 1 - k.bottomLeft.h), UDim2.fromScale(k.bottomLeft.w, k.bottomLeft.h), red, 0.6)
	box(root, "BottomRight", UDim2.fromScale(1 - k.bottomRight.w, 1 - k.bottomRight.h), UDim2.fromScale(k.bottomRight.w, k.bottomRight.h), red, 0.6)

	local m = Layout.SAFE_MARGIN
	local outline = box(root, "SafeArea", UDim2.fromScale(m.x, m.y), UDim2.fromScale(1 - 2 * m.x, 1 - 2 * m.y), Color3.new(0, 1, 0), 1)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 255, 90)
	stroke.Thickness = 2
	stroke.Parent = outline

	return {
		frame = root,
		setVisible = function(visible: boolean)
			root.Visible = visible
		end,
		toggle = function()
			root.Visible = not root.Visible
			return root.Visible
		end,
		destroy = function()
			root:Destroy()
		end,
	}
end

return SafeZoneDebug
