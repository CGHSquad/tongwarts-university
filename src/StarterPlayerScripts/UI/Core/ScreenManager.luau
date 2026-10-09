--!strict
--[[
	ScreenManager — owns the UI's ScreenGuis and which screens are open (handoff 5.4).

	Each registered screen gets its own ScreenGui, created once and kept (so instance names are
	stable for the tests), with the safe-zone settings every screen needs: ScreenInsets so Roblox's
	top bar and device notches are excluded, a SafeArea frame that everything is placed in, and a
	root UIScale that follows Layout.scaleFor as the screen resizes. Screens stack: `open` pushes,
	`back` (Esc / BACK / gamepad B) pops. Combat's own sub-states (ring, list, targets) live inside
	the combat screen, not here.
]]

local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Assets"))
local Layout = require(script.Parent:WaitForChild("Layout"))

-- DisplayOrders sit under the zone fades (55 / 60), the abyss flash (50) and the portal toast (40)
-- that other client scripts own, so those always cover the UI (M0 report R20).
export type Screen = {
	onOpen: ((props: any?) -> ())?,
	onClose: (() -> ())?,
	onBack: (() -> boolean)?, -- true if the screen handled Back itself
	onResize: ((virtualSize: Vector2) -> ())?, -- the SafeArea's size in design pixels changed
}

export type Factory = (manager: ScreenManager, gui: ScreenGui, safeArea: Frame) -> Screen

type Entry = {
	name: string,
	gui: ScreenGui,
	safeArea: Frame,
	scale: UIScale,
	screen: Screen,
	displayOrder: number,
}

type Fields = {
	playerGui: PlayerGui,
	entries: { [string]: Entry },
	stack: { string },
}

local ScreenManager = {}
ScreenManager.__index = ScreenManager

export type ScreenManager = typeof(setmetatable({} :: Fields, ScreenManager))

ScreenManager.DISPLAY_ORDER = {
	Combat = 10,
	SkillList = 12,
	Results = 14,
	Menus = 20,
	Toast = 28,
	Harness = 30,
}

-- The size the UI has to work with: the ScreenGui's own size (post-inset) when the engine has
-- computed it, else the camera's viewport (the tests' fake Roblox has no layout engine).
function ScreenManager.measure(gui: ScreenGui): Vector2
	local ok, size = pcall(function()
		return gui.AbsoluteSize
	end)
	if ok and size.X > 0 and size.Y > 0 then
		return size
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else Layout.DESIGN
end

-- The SafeArea's size in design pixels: the screen divided by the root scale. Screens place their
-- regions in this space (Layout.regions(virtualSize)) and the UIScale renders it at screen size.
function ScreenManager.virtualSize(safeArea: Frame): Vector2
	return Vector2.new(safeArea.Size.X.Offset, safeArea.Size.Y.Offset)
end

-- A ScreenGui with the safe-zone setup, its SafeArea frame and root UIScale. The SafeArea is sized
-- to the screen in design pixels (screen / scale) and scaled back up by the UIScale, so everything
-- inside it works in design pixels at every screen size. `onResize` gets the new virtual size.
function ScreenManager.newScreenGui(name: string, displayOrder: number, onResize: ((Vector2) -> ())?): (ScreenGui, Frame, UIScale)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.DisplayOrder = displayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.FullscreenExtension
	gui.Enabled = false

	local safeArea = Instance.new("Frame")
	safeArea.Name = "SafeArea"
	safeArea.BackgroundTransparency = 1
	safeArea.BorderSizePixel = 0
	safeArea.Parent = gui

	local scale = Instance.new("UIScale")
	scale.Name = "RootScale"
	scale.Parent = safeArea

	local function fit()
		local size = ScreenManager.measure(gui)
		local s = Layout.scaleFor(size)
		scale.Scale = s
		safeArea.Size = UDim2.fromOffset(math.round(size.X / s), math.round(size.Y / s))
		if onResize then
			onResize(ScreenManager.virtualSize(safeArea))
		end
	end
	fit()
	pcall(function()
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	end)
	return gui, safeArea, scale
end

function ScreenManager.new(playerGui: PlayerGui): ScreenManager
	local fields: Fields = { playerGui = playerGui, entries = {}, stack = {} }
	return setmetatable(fields, ScreenManager)
end

-- Creates the screen's ScreenGui now (hidden) and builds the screen into it.
function ScreenManager.register(self: ScreenManager, name: string, displayOrder: number, factory: Factory)
	assert(self.entries[name] == nil, `screen "{name}" is already registered`)
	local screen: Screen? = nil
	local gui, safeArea, scale = ScreenManager.newScreenGui(name, displayOrder, function(virtualSize)
		if screen and screen.onResize then
			screen.onResize(virtualSize)
		end
	end)
	gui.Parent = self.playerGui
	screen = factory(self, gui, safeArea)
	self.entries[name] = { name = name, gui = gui, safeArea = safeArea, scale = scale, screen = screen :: Screen, displayOrder = displayOrder }
end

function ScreenManager.entry(self: ScreenManager, name: string): Entry?
	return self.entries[name]
end

function ScreenManager.isOpen(self: ScreenManager, name: string): boolean
	return table.find(self.stack, name) ~= nil
end

function ScreenManager.current(self: ScreenManager): string?
	return self.stack[#self.stack]
end

-- Preloads the screen's art (if any), shows it, and puts it on top of the stack.
function ScreenManager.open(self: ScreenManager, name: string, props: any?)
	local entry = self.entries[name]
	assert(entry ~= nil, `screen "{name}" isn't registered`)
	local content = Assets.contentFor(name)
	if #content > 0 then
		pcall(function()
			ContentProvider:PreloadAsync(content)
		end)
	end
	local index = table.find(self.stack, name)
	if index then
		table.remove(self.stack, index)
	end
	table.insert(self.stack, name)
	entry.gui.Enabled = true
	if entry.screen.onOpen then
		entry.screen.onOpen(props)
	end
end

function ScreenManager.close(self: ScreenManager, name: string)
	local entry = self.entries[name]
	if entry == nil then
		return
	end
	local index = table.find(self.stack, name)
	if index then
		table.remove(self.stack, index)
	end
	if entry.gui.Enabled then
		entry.gui.Enabled = false
		if entry.screen.onClose then
			entry.screen.onClose()
		end
	end
	pcall(function()
		GuiService.SelectedObject = nil
	end)
end

-- Back: the top screen gets first say; if it doesn't handle it, it closes.
function ScreenManager.back(self: ScreenManager): boolean
	local name = self:current()
	if name == nil then
		return false
	end
	local entry = self.entries[name]
	if entry.screen.onBack and entry.screen.onBack() then
		return true
	end
	self:close(name)
	return true
end

function ScreenManager.closeAll(self: ScreenManager)
	for index = #self.stack, 1, -1 do
		self:close(self.stack[index])
	end
end

return ScreenManager
