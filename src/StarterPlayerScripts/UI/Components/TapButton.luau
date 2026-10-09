--!strict
--[[
	TapButton — the one button everything uses (handoff section 8): normal / pressed / disabled, a
	48 px minimum in both directions, press scale 0.95, a sound hook, and an optional key hint for
	keyboard players. Art through Fallbacks; a drawn plate otherwise.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UI = ReplicatedStorage:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Core = script.Parent.Parent:WaitForChild("Core")
local Audio = require(Core:WaitForChild("Audio"))
local Fallbacks = require(Core:WaitForChild("Fallbacks"))
local Gui = require(Core:WaitForChild("Gui"))
local Input = require(Core:WaitForChild("Input"))

export type Props = {
	name: string,
	text: string,
	onTap: (() -> ())?,
	size: UDim2?, -- design pixels; bumped up to TapMin if smaller
	position: UDim2?,
	anchor: Vector2?,
	layoutOrder: number?,
	color: Color3?, -- fallback fill
	textColor: Color3?,
	textSize: number?,
	font: Enum.Font?,
	assetKey: string?, -- normal-state art
	pressedKey: string?,
	disabledKey: string?,
	keyHint: string?, -- a command name from Input.keyFor, shown as "[1]" when hints are on
	sound: string?, -- Audio event, default "Tap"
}

export type TapButton = {
	button: ImageButton,
	label: TextLabel,
	setEnabled: (enabled: boolean) -> (),
	setText: (text: string) -> (),
	setSelected: (selected: boolean) -> (),
	isEnabled: () -> boolean,
	destroy: () -> (),
}

local TapButton = {}

-- Offsets below the minimum tap size are bumped up; Scale-sized buttons get a UISizeConstraint.
local function atLeastTapMin(size: UDim2): UDim2
	local min = Theme.Sizes.TapMin
	local x = if size.X.Scale == 0 then math.max(size.X.Offset, min) else size.X.Offset
	local y = if size.Y.Scale == 0 then math.max(size.Y.Offset, min) else size.Y.Offset
	return UDim2.new(size.X.Scale, x, size.Y.Scale, y)
end

function TapButton.new(parent: Instance, props: Props): TapButton
	local button = Instance.new("ImageButton")
	button.Name = props.name
	button.Image = ""
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Size = atLeastTapMin(props.size or UDim2.fromOffset(160, Theme.Sizes.TapComfortable))
	button.Position = props.position or UDim2.fromScale(0, 0)
	button.AnchorPoint = props.anchor or Vector2.zero
	button.LayoutOrder = props.layoutOrder or 0
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(Theme.Sizes.TapMin, Theme.Sizes.TapMin)
	constraint.Parent = button

	local fill = props.color or Theme.SchoolAccent
	local hasArt = props.assetKey ~= nil and Fallbacks.skin(button, props.assetKey :: string)
	if not hasArt then
		Fallbacks.panel(button, { fill = fill, fillTransparency = 0, trim = Theme.Panel.Trim, gradientTo = Theme.Colors.Obsidian })
	end

	local label = Gui.label(button, "Label", {
		text = props.text,
		size = props.textSize or Theme.Sizes.TextBody,
		font = props.font or Theme.Fonts.Bold,
		color = props.textColor or Theme.Colors.TextLight,
	})
	label.Size = UDim2.new(1, -16, 1, 0)
	label.Position = UDim2.fromOffset(8, 0)

	local hint: TextLabel? = nil
	if props.keyHint then
		hint = Gui.label(button, "KeyHint", { size = Theme.Sizes.TextLabel, font = Theme.Fonts.Bold, color = Theme.Colors.TextDim })
		local h = hint :: TextLabel
		h.Size = UDim2.new(1, -8, 0, Theme.Sizes.TextLabel + 2)
		h.Position = UDim2.new(0, 4, 1, -(Theme.Sizes.TextLabel + 4))
		h.TextXAlignment = Enum.TextXAlignment.Right
		h.Text = Input.keyHint(props.keyHint :: string) or ""
		h.Visible = h.Text ~= ""
	end
	local stopInput = Input.onChanged(function()
		if hint then
			hint.Text = Input.keyHint(props.keyHint :: string) or ""
			hint.Visible = hint.Text ~= ""
		end
	end)

	local scale = Gui.scale(button)
	local enabled = true
	local selected = false

	local function restyle()
		if hasArt then
			local key = if not enabled then props.disabledKey elseif selected then props.pressedKey else props.assetKey
			if key then
				Fallbacks.skin(button, key)
			end
		else
			button.BackgroundColor3 = if not enabled then Theme.Colors.Disabled elseif selected then Theme.Colors.Gold else fill
		end
		label.TextColor3 = if not enabled then Theme.Colors.TextDim elseif selected then Theme.Colors.Obsidian else (props.textColor or Theme.Colors.TextLight)
		button.Interactable = enabled
	end
	restyle()

	local function press(down: boolean)
		if not enabled then
			return
		end
		local target = if down then 0.95 else 1
		TweenService:Create(scale, TweenInfo.new(Theme.motion(0.08)), { Scale = target }):Play()
	end

	local connections = {
		button.MouseButton1Down:Connect(function()
			press(true)
		end),
		button.MouseButton1Up:Connect(function()
			press(false)
		end),
		button.MouseLeave:Connect(function()
			press(false)
		end),
		button.Activated:Connect(function()
			if not enabled then
				return
			end
			Audio.play(props.sound or "Tap")
			if props.onTap then
				props.onTap()
			end
		end),
	}

	button.Parent = parent

	return {
		button = button,
		label = label,
		setEnabled = function(value: boolean)
			enabled = value
			restyle()
		end,
		setText = function(text: string)
			label.Text = text
		end,
		setSelected = function(value: boolean)
			selected = value
			restyle()
		end,
		isEnabled = function()
			return enabled
		end,
		destroy = function()
			stopInput()
			for _, connection in connections do
				connection:Disconnect()
			end
			button:Destroy()
		end,
	}
end

return TapButton
