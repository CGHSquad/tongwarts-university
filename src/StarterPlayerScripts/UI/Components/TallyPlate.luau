--!strict
--[[
	TallyPlate — a results plate with a label and a number that counts up from 0 (handoff S6):
	an icon slot on the left, the label, the value on the right. `countTo` animates over
	Theme.Motion.CountUp seconds with a tick sound per step; `skip` lands on the final value.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Theme = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Theme"))
local Core = script.Parent.Parent:WaitForChild("Core")
local Audio = require(Core:WaitForChild("Audio"))
local Fallbacks = require(Core:WaitForChild("Fallbacks"))
local Gui = require(Core:WaitForChild("Gui"))

export type Props = {
	name: string,
	label: string,
	assetKey: string?, -- Results_TallyNormal / Gold / Green
	iconKey: string?,
	trim: Color3?,
	format: ((value: number) -> string)?,
	size: UDim2?,
	layoutOrder: number?,
}

export type TallyPlate = {
	frame: ImageLabel,
	value: TextLabel,
	setValue: (value: number) -> (),
	countTo: (value: number, seconds: number?, onDone: (() -> ())?) -> (),
	skip: () -> (),
	isCounting: () -> boolean,
	destroy: () -> (),
}

local TallyPlate = {}

function TallyPlate.new(parent: Instance, props: Props): TallyPlate
	local frame = Fallbacks.image(parent, props.name, props.assetKey or "", { fill = Theme.Colors.Obsidian, fillTransparency = 0.05, trim = props.trim or Theme.Colors.Cyan, trimThickness = 2 })
	if props.assetKey == nil or frame.Image == "" then
		Fallbacks.panel(frame, { fill = Theme.Colors.Obsidian, fillTransparency = 0.05, trim = props.trim or Theme.Colors.Cyan, trimThickness = 2 })
	end
	frame.Size = props.size or UDim2.new(1, 0, 0, Theme.Sizes.RowHeight)
	frame.LayoutOrder = props.layoutOrder or 0

	local icon = Fallbacks.image(frame, "Icon", props.iconKey or "", { fill = Theme.Colors.Navy, fillTransparency = 0, trim = Theme.Colors.Gold, trimThickness = 1, corner = 6 })
	if props.iconKey == nil or icon.Image == "" then
		Fallbacks.panel(icon, { fill = Theme.Colors.Navy, fillTransparency = 0, trim = Theme.Colors.Gold, trimThickness = 1, corner = 6 })
	end
	icon.Size = UDim2.fromOffset(36, 36)
	icon.Position = UDim2.new(0, 10, 0.5, -18)

	local label = Gui.label(frame, "Label", { text = props.label, size = Theme.Sizes.TextTitle, font = Theme.Fonts.Display, align = Enum.TextXAlignment.Left, stroke = 1 })
	label.Size = UDim2.new(0.5, -60, 1, 0)
	label.Position = UDim2.fromOffset(56, 0)

	local value = Gui.label(frame, "Value", { text = "", size = Theme.Sizes.TextTitle, font = Theme.Fonts.Display, color = Theme.Colors.Gold, align = Enum.TextXAlignment.Right, stroke = 1 })
	value.Size = UDim2.new(0.5, -16, 1, 0)
	value.Position = UDim2.new(0.5, 0, 0, 0)

	local format = props.format or function(n: number): string
		return tostring(n)
	end
	local shown = 0
	local target = 0
	local connection: RBXScriptConnection? = nil
	local finished: (() -> ())? = nil

	local function show(n: number)
		shown = n
		value.Text = format(n)
	end

	local function stop()
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end

	local function finish()
		stop()
		show(target)
		local callback = finished
		finished = nil
		if callback then
			callback()
		end
	end

	local function countTo(final: number, seconds: number?, onDone: (() -> ())?)
		stop()
		target = final
		finished = onDone
		local duration = Theme.motion(seconds or Theme.Motion.CountUp)
		if duration <= 0 or final == 0 then
			finish()
			return
		end
		local elapsed = 0
		local lastTick = 0
		show(0)
		connection = RunService.Heartbeat:Connect(function(dt: number)
			elapsed += dt
			local progress = math.clamp(elapsed / duration, 0, 1)
			local n = math.floor(final * progress)
			if n ~= shown then
				show(n)
				if elapsed - lastTick > 0.08 then
					lastTick = elapsed
					Audio.play("Tick")
				end
			end
			if progress >= 1 then
				finish()
			end
		end)
	end

	show(0)

	return {
		frame = frame,
		value = value,
		setValue = function(n: number)
			stop()
			target = n
			show(n)
		end,
		countTo = countTo,
		skip = function()
			if connection then
				finish()
			end
		end,
		isCounting = function()
			return connection ~= nil
		end,
		destroy = function()
			stop()
			frame:Destroy()
		end,
	}
end

return TallyPlate
