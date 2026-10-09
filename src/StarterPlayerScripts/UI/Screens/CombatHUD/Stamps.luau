--!strict
--[[
	Stamps — ONE MORE! and ALL-OUT ATTACK (handoff S1). Behind Flags.DownSystem, which is off:
	there is no server source for either (M0 report R7). Built so the harness can show them on mock
	data; the HUD never calls `show` while the flag is off.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UI = ReplicatedStorage:WaitForChild("UI")
local Flags = require(UI:WaitForChild("Flags"))
local Strings = require(UI:WaitForChild("Strings"))
local Theme = require(UI:WaitForChild("Theme"))

local Root = script.Parent.Parent.Parent
local Core = Root:WaitForChild("Core")
local Fallbacks = require(Core:WaitForChild("Fallbacks"))
local Gui = require(Core:WaitForChild("Gui"))

export type Kind = "OneMore" | "AllOut"

export type Stamps = {
	frame: Frame,
	show: (kind: Kind, force: boolean?) -> (), -- force: the harness, which has no flag to flip
	hide: () -> (),
	destroy: () -> (),
}

local Stamps = {}

function Stamps.new(parent: Instance): Stamps
	local frame = Gui.frame(parent, "Stamps")
	frame.Visible = false

	local oneMore = Fallbacks.image(frame, "OneMore", "Combat_OneMoreLettering", { fill = Theme.Colors.Gold, fillTransparency = 0, trim = Theme.Colors.Ink, trimThickness = 3, corner = 8 })
	oneMore.AnchorPoint = Vector2.new(0.5, 0.5)
	oneMore.Position = UDim2.fromScale(0.5, 0.4)
	oneMore.Size = UDim2.fromOffset(260, 80)
	oneMore.Rotation = -8
	oneMore.Visible = false
	local oneMoreText = Gui.label(oneMore, "Label", { text = Strings.OneMore, size = Theme.Sizes.TextDisplay, font = Theme.Fonts.Display, stroke = Theme.Sizes.StrokeDisplay })
	oneMoreText.Visible = oneMore.Image == ""

	local allOut = Fallbacks.image(frame, "AllOut", "Combat_AllOutRibbon", { fill = Theme.Colors.Gold, fillTransparency = 0, trim = Theme.Colors.Ink, trimThickness = 3, corner = 8 })
	allOut.AnchorPoint = Vector2.new(0.5, 0.5)
	allOut.Position = UDim2.fromScale(0.5, 0.7)
	allOut.Size = UDim2.fromOffset(320, 64)
	allOut.Visible = false
	Gui.label(allOut, "Label", { text = Strings.AllOutAttack, size = Theme.Sizes.TextTitle, font = Theme.Fonts.Display, stroke = 2 })

	local shows = 0

	local function show(kind: Kind, force: boolean?)
		if not Flags.DownSystem and not force then
			return
		end
		shows += 1
		local mine = shows
		frame.Visible = true
		local stamp = if kind == "OneMore" then oneMore else allOut
		stamp.Visible = true
		local scale = stamp:FindFirstChildOfClass("UIScale") or Gui.scale(stamp)
		scale.Scale = 0.6
		TweenService:Create(scale, TweenInfo.new(Theme.motion(Theme.Motion.StampPop), Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		if kind == "OneMore" then
			task.delay(Theme.motion(Theme.Motion.StampPop + Theme.Motion.StampHold), function()
				if shows == mine then
					stamp.Visible = false
					frame.Visible = allOut.Visible
				end
			end)
		end
	end

	return {
		frame = frame,
		show = show,
		hide = function()
			oneMore.Visible = false
			allOut.Visible = false
			frame.Visible = false
		end,
		destroy = function()
			frame:Destroy()
		end,
	}
end

return Stamps
