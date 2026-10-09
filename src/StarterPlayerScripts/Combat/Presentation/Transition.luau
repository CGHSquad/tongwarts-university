--!strict
--[[
	Transition — the battle-start wipe: wedges in the school's colours swirl in from the centre and
	fill the screen, the stage is set up under the cover, then they spin away to reveal the camera
	sweep. Roblox can't capture the live frame, so a true Persona "shatter" isn't possible; this is
	the stylised swirl instead. With reduced motion it's a plain fade.

	One ScreenGui of its own in PlayerGui (above every screen, survives respawns), built when a
	cover starts and destroyed once uncovered, so nothing lingers after a fight.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Theme"))

local Transition = {}
Transition.__index = Transition

Transition.NAME = "BattleTransition"
Transition.WEDGES = 8

type Fields = {
	playerGui: PlayerGui,
	gui: ScreenGui?,
	wedges: Frame?,
	cover: Frame?,
	serial: number,
}

export type Transition = typeof(setmetatable({} :: Fields, Transition))

function Transition.new(playerGui: PlayerGui): Transition
	local fields: Fields = { playerGui = playerGui, gui = nil, wedges = nil, cover = nil, serial = 0 }
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

-- Fills the screen over `seconds`. `motionScale` 0 fades instead of swirling.
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
		local wedges = Instance.new("Frame")
		wedges.Name = "Wedges"
		wedges.AnchorPoint = Vector2.new(0.5, 0.5)
		wedges.Position = UDim2.fromScale(0.5, 0.5)
		wedges.Size = UDim2.fromScale(1, 1)
		wedges.BackgroundTransparency = 1
		wedges.ZIndex = 1
		wedges.Parent = gui
		local scale = Instance.new("UIScale")
		scale.Scale = 0
		scale.Parent = wedges
		for index = 1, Transition.WEDGES do
			local wedge = Instance.new("Frame")
			wedge.Name = `Wedge{index}`
			wedge.AnchorPoint = Vector2.new(0, 0.5)
			wedge.Position = UDim2.fromScale(0.5, 0.5)
			wedge.Size = UDim2.fromScale(0.9, 0.14)
			wedge.Rotation = (index - 1) * (360 / Transition.WEDGES)
			wedge.BackgroundColor3 = if index % 2 == 0 then Theme.SchoolAccent else Theme.Colors.Gold
			wedge.BorderSizePixel = 0
			wedge.Parent = wedges
		end
		self.wedges = wedges
		TweenService:Create(scale, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 2.2 }):Play()
		TweenService:Create(wedges, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Rotation = 120 }):Play()
		TweenService:Create(cover, TweenInfo.new(seconds * 0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, seconds * 0.5), { BackgroundTransparency = 0 }):Play()
	else
		TweenService:Create(cover, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { BackgroundTransparency = 0 }):Play()
	end
	gui.Parent = self.playerGui
end

-- Clears the screen over `seconds`, then removes itself.
function Transition.uncoverScreen(self: Transition, seconds: number, motionScale: number)
	local gui, cover, wedges = self.gui, self.cover, self.wedges
	if gui == nil or cover == nil then
		return
	end
	self.serial += 1
	local serial = self.serial
	TweenService:Create(cover, TweenInfo.new(seconds * 0.6, Enum.EasingStyle.Linear), { BackgroundTransparency = 1 }):Play()
	if wedges and motionScale > 0 then
		local scale = wedges:FindFirstChildOfClass("UIScale")
		if scale then
			TweenService:Create(scale, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, seconds * 0.2), { Scale = 0 }):Play()
		end
		TweenService:Create(wedges, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = 240 }):Play()
	elseif wedges then
		wedges.Visible = false
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
	self.gui, self.cover, self.wedges = nil, nil, nil
	if gui then
		gui:Destroy()
	end
end

return Transition
