--!strict
--[[
	CommandRing — the ribbons on the left: Attack, Spell, Guard (Item and Pass behind flags), each a
	big tap target in its fixed color (handoff S1). They burst in with a stagger when it's the
	local player's turn and hide otherwise. Keyboard players see [1]..[5].
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UI = ReplicatedStorage:WaitForChild("UI")
local Bindings = require(UI:WaitForChild("Bindings"))
local Theme = require(UI:WaitForChild("Theme"))
local UITypes = require(UI:WaitForChild("UITypes"))

local Root = script.Parent.Parent.Parent
local Gui = require(Root:WaitForChild("Core"):WaitForChild("Gui"))
local TapButton = require(Root:WaitForChild("Components"):WaitForChild("TapButton"))

export type CommandRing = {
	frame: Frame,
	show: (commands: { UITypes.CommandView }) -> (),
	hide: () -> (),
	layout: (width: number, height: number) -> (),
	destroy: () -> (),
}

type Ribbon = { button: TapButton.TapButton, id: UITypes.CommandId }

local RIBBON_HEIGHT = 56
local RIBBON_GAP = 8

local COLORS: { [string]: Color3 } = {
	Attack = Theme.Colors.CommandAttack,
	Spell = Theme.Colors.CommandSpell,
	Item = Theme.Colors.CommandItem,
	Guard = Theme.Colors.CommandGuard,
	Pass = Theme.Colors.CommandPass,
}
local ART: { [string]: string } = {
	Attack = "Combat_CommandBlue",
	Spell = "Combat_CommandPurple",
	Item = "Combat_CommandGreen",
	Guard = "Combat_CommandAmber",
	Pass = "Combat_CommandSilver",
}

local CommandRing = {}

function CommandRing.new(parent: Instance, onCommand: (id: UITypes.CommandId) -> ()): CommandRing
	local frame = Gui.frame(parent, "Ring")
	frame.Visible = false
	local ribbons: { Ribbon } = {}
	local width = 160
	local shownKey = ""

	local function clear()
		for _, ribbon in ribbons do
			ribbon.button.destroy()
		end
		table.clear(ribbons)
	end

	local function place()
		for index, ribbon in ribbons do
			ribbon.button.button.Position = UDim2.fromOffset(0, (index - 1) * (RIBBON_HEIGHT + RIBBON_GAP))
			ribbon.button.button.Size = UDim2.fromOffset(width, RIBBON_HEIGHT)
		end
	end

	local function build(commands: { UITypes.CommandView })
		clear()
		for index, command in commands do
			local id: UITypes.CommandId = command.id
			local button = TapButton.new(frame, {
				name = id,
				text = Bindings.commandLabel(id),
				color = COLORS[id],
				assetKey = ART[id],
				keyHint = id,
				textSize = Theme.Sizes.TextBody + 2,
				font = Theme.Fonts.Display,
				layoutOrder = index,
				onTap = function()
					onCommand(id)
				end,
			})
			button.setEnabled(command.enabled)
			table.insert(ribbons, { button = button, id = id })
		end
		place()
	end

	local function show(commands: { UITypes.CommandView })
		local key = ""
		for _, command in commands do
			key ..= `{command.id}:{command.enabled};`
		end
		if key ~= shownKey or #ribbons == 0 then
			shownKey = key
			build(commands)
		end
		if frame.Visible then
			return
		end
		frame.Visible = true
		-- Burst in: each ribbon slides from the left, a beat after the one above it.
		for index, ribbon in ribbons do
			local object = ribbon.button.button
			local y = (index - 1) * (RIBBON_HEIGHT + RIBBON_GAP)
			local rest = UDim2.fromOffset(0, y)
			object.Position = UDim2.fromOffset(-40, y)
			local info = TweenInfo.new(Theme.motion(Theme.Motion.RibbonBurst), Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, Theme.motion(Theme.Motion.RibbonStagger) * (index - 1))
			TweenService:Create(object, info, { Position = rest }):Play()
		end
	end

	return {
		frame = frame,
		show = show,
		hide = function()
			frame.Visible = false
		end,
		layout = function(w: number, _h: number)
			width = math.max(w, Theme.Sizes.TapMin)
			place()
		end,
		destroy = function()
			clear()
			frame:Destroy()
		end,
	}
end

return CommandRing
