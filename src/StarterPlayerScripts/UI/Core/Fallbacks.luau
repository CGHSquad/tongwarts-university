--!strict
--[[
	Fallbacks — art if there is art, a drawn look if there isn't (handoff 5.2). Every component
	goes through here, so screens work with zero images and art drops in later without code changes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UI = ReplicatedStorage:WaitForChild("UI")
local Assets = require(UI:WaitForChild("Assets"))
local Theme = require(UI:WaitForChild("Theme"))
local Gui = require(script.Parent:WaitForChild("Gui"))

local Fallbacks = {}

function Fallbacks.has(key: string): boolean
	return Assets.image(key) ~= nil
end

-- Puts the art for `key` on an image object, with its slice settings. Returns false when there is
-- no art, so the caller draws its fallback instead.
function Fallbacks.skin(object: ImageLabel | ImageButton, key: string): boolean
	local target = object :: any -- a union of classes can't be assigned through under the old solver
	local id = if key == "" then nil else Assets.image(key) -- "" means "no art for this one"
	if id == nil then
		target.Image = ""
		return false
	end
	target.Image = id
	target.BackgroundTransparency = 1
	local entry = Assets.entry(key)
	if entry and entry.slice then
		target.ScaleType = Enum.ScaleType.Slice
		target.SliceCenter = entry.slice
		target.SliceScale = entry.sliceScale or 1
	else
		target.ScaleType = Enum.ScaleType.Fit
	end
	return true
end

export type PanelLook = {
	fill: Color3?,
	fillTransparency: number?,
	trim: Color3?,
	trimThickness: number?,
	corner: number?,
	gradientTo: Color3?, -- a vertical gradient from fill to this
}

-- The drawn panel look: a dark fill, a trim stroke, a soft gradient.
function Fallbacks.panel(object: GuiObject, look: PanelLook?)
	local l: PanelLook = look or {}
	object.BackgroundColor3 = l.fill or Theme.Panel.Fill
	object.BackgroundTransparency = l.fillTransparency or Theme.Panel.FillTransparency
	object.BorderSizePixel = 0
	Gui.corner(object, l.corner)
	local thickness = l.trimThickness or Theme.Panel.TrimThickness
	if thickness > 0 then
		Gui.stroke(object, l.trim or Theme.Panel.Trim, thickness)
	end
	if l.gradientTo then
		Gui.gradient(object, l.fill or Theme.Panel.Fill, l.gradientTo, 90)
	end
end

-- An image object that shows the art for `key`, or the drawn look when there is none.
function Fallbacks.image(parent: Instance, name: string, key: string, look: PanelLook?): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = name
	image.BorderSizePixel = 0
	image.BackgroundTransparency = 1
	if not Fallbacks.skin(image, key) then
		Fallbacks.panel(image, look)
	end
	image.Parent = parent
	return image
end

return Fallbacks
