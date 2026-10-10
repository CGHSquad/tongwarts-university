--!strict
--[[
	Transition — the battle-start wipe: shutter stripes in the school's colours sweep in from both
	sides and close over the screen, the stage is set up under the cover, then they sweep out again
	to reveal the camera sweep. Roblox can't capture the live frame, so a true Persona "shatter"
	isn't possible; this is the stylised wipe instead. With reduced motion it's a plain fade.

	One ScreenGui of its own in PlayerGui (above every screen, survives respawns), built when a
	cover starts and destroyed once uncovered, so nothing lingers after a fight.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Theme"))

local Transition = {}
Transition.__index = Transition

Transition.NAME = "BattleTransition"
Transition.STRIPES = 10
Transition.STAGGER = 0.02 -- seconds between one stripe starting and the next

type Fields = {
	playerGui: PlayerGui,
	gui: ScreenGui?,
	stripes: Frame?,
	cover: Frame?,
	serial: number,
}

export type Transition = typeof(setmetatable({} :: Fields, Transition))

function Transition.new(playerGui: PlayerGui): Transition
	local fields: Fields = { playerGui = playerGui, gui = nil, stripes = nil, cover = nil, serial = 0 }
	return setmetatable(fields, Transition)
end

local function screenGui(name: string): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 200
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	return gui
end

-- Where stripe `index` rests off-screen: odd stripes come from the left, even from the right.
local function offscreen(index: number): UDim2
	local row = (index - 1) / Transition.STRIPES
	return UDim2.fromScale(if index % 2 == 1 then -1 else 1, row)
end

local function onscreen(index: number): UDim2
	return UDim2.fromScale(0, (index - 1) / Transition.STRIPES)
end

-- Fills the screen over `seconds`. `motionScale` 0 fades instead of sweeping.
function Transition.coverScreen(self: Transition, seconds: number, motionScale: number)
	self:destroy()
	self.serial += 1
	local gui = screenGui(Transition.NAME)
	self.gui = gui

	local cover = Instance.new("Frame")
	cover.Name = "Cover"
	cover.Size = UDim2.fromScale(1, 1)
	cover.BackgroundColor3 = Theme.Colors.Obsidian
	cover.BackgroundTransparency = 1
	cover.BorderSizePixel = 0
	cover.ZIndex = 2
	cover.Parent = gui
	self.cover = cover

	if motionScale > 0 then
		local stripes = Instance.new("Frame")
		stripes.Name = "Stripes"
		stripes.Size = UDim2.fromScale(1, 1)
		stripes.BackgroundTransparency = 1
		stripes.ZIndex = 1
		stripes.Parent = gui
		local sweep = math.max(0.05, seconds - Transition.STAGGER * Transition.STRIPES)
		for index = 1, Transition.STRIPES do
			local stripe = Instance.new("Frame")
			stripe.Name = `Stripe{index}`
			stripe.Position = offscreen(index)
			stripe.Size = UDim2.fromScale(1, 1 / Transition.STRIPES + 0.002) -- a hair of overlap, no seams
			stripe.BackgroundColor3 = if index % 2 == 0 then Theme.SchoolAccent else Theme.Colors.Gold
			stripe.BorderSizePixel = 0
			stripe.Parent = stripes
			local info = TweenInfo.new(sweep, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, Transition.STAGGER * (index - 1))
			TweenService:Create(stripe, info, { Position = onscreen(index) }):Play()
		end
		self.stripes = stripes
		-- The dark cover arrives as the last stripe closes, so the stage can be set under it.
		TweenService:Create(cover, TweenInfo.new(seconds * 0.3, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, seconds * 0.7), { BackgroundTransparency = 0 }):Play()
	else
		TweenService:Create(cover, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { BackgroundTransparency = 0 }):Play()
	end
	gui.Parent = self.playerGui
end

-- Clears the screen over `seconds`, then removes itself.
function Transition.uncoverScreen(self: Transition, seconds: number, motionScale: number)
	local gui, cover, stripes = self.gui, self.cover, self.stripes
	if gui == nil or cover == nil then
		return
	end
	self.serial += 1
	local serial = self.serial
	TweenService:Create(cover, TweenInfo.new(seconds * 0.4, Enum.EasingStyle.Linear), { BackgroundTransparency = 1 }):Play()
	if stripes and motionScale > 0 then
		local sweep = math.max(0.05, seconds - Transition.STAGGER * Transition.STRIPES)
		for index = 1, Transition.STRIPES do
			local stripe = stripes:FindFirstChild(`Stripe{index}`)
			if stripe and stripe:IsA("Frame") then
				-- Out the way it came, starting from the far end of the shutter.
				local info = TweenInfo.new(sweep, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, Transition.STAGGER * (Transition.STRIPES - index))
				TweenService:Create(stripe, info, { Position = offscreen(index) }):Play()
			end
		end
	elseif stripes then
		stripes.Visible = false
	end
	task.delay(seconds + 0.05, function()
		if self.serial == serial then
			self:destroy()
		end
	end)
end

function Transition.isShowing(self: Transition): boolean
	return self.gui ~= nil
end

function Transition.destroy(self: Transition)
	local gui = self.gui
	self.gui, self.cover, self.stripes = nil, nil, nil
	if gui then
		gui:Destroy()
	end
end

return Transition
