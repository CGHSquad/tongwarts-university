--!strict
--[[
	EnemyOverlay — the plate over each enemy (handoff S1): name, HP bar, its status effects as
	small tags under the bar, crimson target brackets while the player is picking a target (gold on
	the chosen one), and the WEAK marker and DOWN tag that stay hidden until their flags and data
	exist. One BillboardGui per enemy, a fixed pixel
	size (scaled with the HUD's root scale), anchored to the spot BattleView keeps for that
	participant; BattleView's own enemy plates are switched off for the new HUD (M0 report R19).
	The plate is a button, so tapping the enemy picks it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UI = ReplicatedStorage:WaitForChild("UI")
local Flags = require(UI:WaitForChild("Flags"))
local Strings = require(UI:WaitForChild("Strings"))
local Theme = require(UI:WaitForChild("Theme"))
local UITypes = require(UI:WaitForChild("UITypes"))

local Root = script.Parent.Parent.Parent
local Fallbacks = require(Root:WaitForChild("Core"):WaitForChild("Fallbacks"))
local Gui = require(Root:WaitForChild("Core"):WaitForChild("Gui"))
local Components = Root:WaitForChild("Components")
local Capsule = require(Components:WaitForChild("Capsule"))
local StatBar = require(Components:WaitForChild("StatBar"))
local Tag = require(Components:WaitForChild("Tag"))

type HudBattle = UITypes.HudBattle
type HudParticipant = UITypes.HudParticipant

export type EnemyOverlay = {
	folder: Folder,
	update: (battle: HudBattle, targetId: string?, pickable: { [string]: boolean }) -> (),
	tick: () -> (), -- every frame: re-stacks the plates whenever the battle camera has moved
	setScale: (scale: number) -> (),
	hide: () -> (),
	onPick: (callback: (id: string) -> ()) -> (),
	destroy: () -> (),
}

type Plate = {
	gui: BillboardGui,
	root: Frame,
	scale: UIScale,
	baseOffset: number, -- studs above the spot, from BattleView's own plate
	button: ImageButton,
	stroke: UIStroke?,
	title: TextLabel,
	hp: StatBar.StatBar,
	statuses: Frame,
	statusKey: string, -- what the status tags were built for
	left: Frame,
	right: Frame,
	weak: Tag.Tag,
	down: Tag.Tag,
}

local EnemyOverlay = {}

EnemyOverlay.PLATE_WIDTH = 190
EnemyOverlay.PLATE_HEIGHT = 60

-- The stage part this participant's plate hangs over, and how high above it, from BattleView.
local function spotFor(id: string): (BasePart?, Vector3)
	local stage = Workspace:FindFirstChild("BattleStage")
	local figure = if stage then stage:FindFirstChild(id) else nil
	local spot = if figure then figure:FindFirstChild("Spot") else nil
	if spot and spot:IsA("BasePart") then
		local nameplate = spot:FindFirstChild("Nameplate")
		local offset = if nameplate and nameplate:IsA("BillboardGui") then nameplate.StudsOffset else Vector3.new(0, 4.5, 0)
		return spot, offset
	end
	return nil, Vector3.zero
end

function EnemyOverlay.new(playerGui: PlayerGui, name: string?): EnemyOverlay
	local folderName = name or "CombatHUDEnemies"
	local folder = Instance.new("Folder")
	folder.Name = folderName
	folder.Parent = playerGui
	local plates: { [string]: Plate } = {}
	local api: EnemyOverlay
	local builtFor: string? = nil
	local pick: ((id: string) -> ())? = nil
	local connections: { RBXScriptConnection } = {}
	local scale = 1
	local width, height = EnemyOverlay.PLATE_WIDTH, EnemyOverlay.PLATE_HEIGHT

	local function clear()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		for _, plate in plates do
			plate.gui:Destroy()
		end
		table.clear(plates)
	end

	local function applyScale(plate: Plate)
		plate.gui.Size = UDim2.fromOffset(math.round(width * scale), math.round(height * scale))
		plate.scale.Scale = scale
	end

	-- A respawn (a reset mid-fight, the respawn after a loss) clears PlayerGui of everything but the
	-- ScreenGuis that opt out, and the plates go with their folder: start over with a new one.
	local function ensureFolder()
		if folder.Parent ~= nil then
			return
		end
		clear()
		folder = Instance.new("Folder")
		folder.Name = folderName
		folder.Parent = playerGui
		builtFor = nil
		api.folder = folder
	end

	local function build(battle: HudBattle)
		clear()
		for _, p in battle.participants do
			if p.side ~= "Enemy" then
				continue
			end
			local gui = Instance.new("BillboardGui")
			gui.Name = `Enemy_{p.id}`
			gui.AlwaysOnTop = true -- over the scene, like the handoff asks (Studio's MCP screen capture never shows AlwaysOnTop billboards; that's the capture, not the game)
			gui.LightInfluence = 0
			gui.Active = true
			gui.ResetOnSpawn = false
			gui.Enabled = false

			-- Everything sits in a root frame of the design size; a UIScale scales it with the HUD.
			local root = Gui.frame(gui, "Root")
			root.AnchorPoint = Vector2.new(0.5, 0)
			root.Position = UDim2.new(0.5, 0, 0, 0)
			root.Size = UDim2.fromOffset(width, height)
			local uiScale = Gui.scale(root)

			local button = Instance.new("ImageButton")
			button.Name = "Plate"
			button.Image = ""
			button.AutoButtonColor = false
			button.BorderSizePixel = 0
			button.Interactable = false
			button.AnchorPoint = Vector2.new(0.5, 0)
			button.Position = UDim2.new(0.5, 0, 0, 0)
			button.Size = UDim2.new(1, -24, 0, 42)
			if not Fallbacks.skin(button, "Enemy_NamePlate") then
				Fallbacks.panel(button, { fill = Theme.Colors.Obsidian, fillTransparency = 0.1, trim = Theme.Colors.Crimson, trimThickness = 1, corner = 4 })
			end
			button.Parent = root
			local title = Gui.label(button, "Title", { text = p.name, size = Theme.Sizes.TextLabel + 1, font = Theme.Fonts.Bold, stroke = 1 })
			title.Size = UDim2.new(1, -8, 0, 18)
			title.Position = UDim2.fromOffset(4, 2)
			local hp = StatBar.new(button, { name = "Hp", color = Theme.Colors.Crimson, trackKey = "Enemy_HpTrack", fillKey = "Enemy_HpFill", height = 14, size = UDim2.new(1, -12, 0, 14), position = UDim2.fromOffset(6, 24), textFormat = Strings.format.hp })

			-- Status effects, as small tags in the strip under the plate.
			local statuses = Gui.frame(root, "Statuses")
			statuses.Position = UDim2.fromOffset(0, 44)
			statuses.Size = UDim2.new(1, 0, 0, 16)
			Gui.list(statuses, Enum.FillDirection.Horizontal, 4).HorizontalAlignment = Enum.HorizontalAlignment.Center

			-- Target brackets either side of the plate (handoff: "crimson target brackets").
			local function bracket(bracketName: string, anchorX: number): Frame
				local b = Instance.new("Frame")
				b.Name = bracketName
				b.AnchorPoint = Vector2.new(anchorX, 0)
				b.Position = UDim2.new(anchorX, 0, 0, 0)
				b.Size = UDim2.fromOffset(6, 42)
				b.BackgroundColor3 = Theme.Colors.Crimson
				b.BorderSizePixel = 0
				b.Visible = false
				b.Parent = root
				return b
			end
			local left, right = bracket("BracketLeft", 0), bracket("BracketRight", 1)

			local weak = Tag.new(root, { name = "Weak", kind = "Weak", position = UDim2.new(1, 0, 1, 0), anchor = Vector2.new(1, 1), size = UDim2.fromOffset(52, 18) })
			weak.frame.Visible = false
			local down = Tag.new(root, { name = "Down", kind = "Down", position = UDim2.new(0.5, 0, 1, 0), anchor = Vector2.new(0.5, 1), size = UDim2.fromOffset(60, 18) })
			down.frame.Visible = false

			local id = p.id
			table.insert(connections, button.Activated:Connect(function()
				if pick and button.Interactable then
					pick(id)
				end
			end))
			gui.Parent = folder
			local plate: Plate = { gui = gui, root = root, scale = uiScale, baseOffset = 0, button = button, stroke = button:FindFirstChildOfClass("UIStroke"), title = title, hp = hp, statuses = statuses, statusKey = "", left = left, right = right, weak = weak, down = down }
			applyScale(plate)
			plates[id] = plate
		end
		builtFor = battle.rosterKey
	end

	-- Two plates of a fixed pixel size can land on top of each other when the battle camera puts
	-- their enemies close together on screen. Plates whose enemies overlap on screen stack instead:
	-- the later one in screen order moves up a row. Re-run whenever the camera moves (tick). Needs
	-- the camera's projection, which the tests' fake Roblox doesn't have; then they stay put.
	local lastCameraCFrame: CFrame? = nil
	local function stagger()
		local camera = Workspace.CurrentCamera
		if camera == nil then
			return
		end
		lastCameraCFrame = camera.CFrame
		local entries: { { plate: Plate, x: number, pixelsPerStud: number } } = {}
		for _, plate in plates do
			local spot: Instance? = plate.gui.Adornee
			if not plate.gui.Enabled or spot == nil or not spot:IsA("BasePart") then
				continue
			end
			local ok, x, pixelsPerStud = pcall(function()
				local base = spot.CFrame.Position + Vector3.new(0, plate.baseOffset, 0)
				local point = camera:WorldToViewportPoint(base)
				local up = camera:WorldToViewportPoint(base + Vector3.new(0, 1, 0))
				return point.X, math.max(point.Y - up.Y, 0.001)
			end)
			if ok then
				table.insert(entries, { plate = plate, x = x, pixelsPerStud = pixelsPerStud })
			end
		end
		table.sort(entries, function(a, b)
			return a.x < b.x
		end)
		local placed: { { x: number, row: number } } = {}
		local plateWidth = width * scale
		for _, entry in entries do
			local row = 0
			local function clashes(r: number): boolean
				for _, other in placed do
					if other.row == r and math.abs(other.x - entry.x) < plateWidth + 8 then
						return true
					end
				end
				return false
			end
			while clashes(row) do
				row += 1
			end
			table.insert(placed, { x = entry.x, row = row })
			local rowStuds = (height * scale + 6) / entry.pixelsPerStud
			entry.plate.gui.StudsOffset = Vector3.new(0, entry.plate.baseOffset + row * rowStuds, 0)
		end
	end

	local function update(battle: HudBattle, targetId: string?, pickable: { [string]: boolean })
		ensureFolder()
		if builtFor ~= battle.rosterKey then
			build(battle)
		end
		for id, plate in plates do
			local p = battle.byId[id]
			if p == nil then
				continue
			end
			local spot, offset = spotFor(id)
			if spot then
				plate.gui.Adornee = spot
				plate.gui.StudsOffset = offset
				plate.baseOffset = offset.Y
			end
			plate.gui.Enabled = spot ~= nil and not p.left -- no spot (the harness): the plate just stays off
			plate.hp.set(p.hp.current, p.hp.max, true)
			local statusKey = ""
			for _, status in p.statuses do
				statusKey ..= `{status.id}:{status.turnsLeft};`
			end
			if statusKey ~= plate.statusKey then
				plate.statusKey = statusKey
				for _, child in plate.statuses:GetChildren() do
					if child:IsA("GuiObject") then
						child:Destroy()
					end
				end
				for index, status in p.statuses do
					Capsule.new(plate.statuses, {
						name = status.id,
						text = Strings.format.statusTurns(status.name, status.turnsLeft),
						color = if status.kind == "Ailment" then Theme.Colors.Crimson else Theme.Colors.Cyan,
						size = UDim2.fromOffset(76, 16),
						layoutOrder = index,
					})
				end
			end
			local targeted = targetId == id
			local canPick = pickable[id] == true
			plate.button.Interactable = canPick
			plate.left.Visible = canPick
			plate.right.Visible = canPick
			local bracketColor = if targeted then Theme.Colors.Gold else Theme.Colors.Crimson
			plate.left.BackgroundColor3 = bracketColor
			plate.right.BackgroundColor3 = bracketColor
			local acting = battle.activeId == id and battle.phase ~= "Reward"
			if plate.stroke then
				plate.stroke.Color = if targeted then Theme.Colors.Gold elseif acting then Theme.Colors.Cyan else Theme.Colors.Crimson
				plate.stroke.Thickness = if targeted or acting then 3 else 1
			end
			plate.button.BackgroundTransparency = if p.knockedOut then 0.6 else 0.1
			plate.title.TextTransparency = if p.knockedOut then 0.4 else 0
			plate.weak.frame.Visible = Flags.ShowAffinities and #p.knownWeaknesses > 0
			plate.down.frame.Visible = Flags.DownSystem and p.isDown
		end
		stagger()
	end

	local function tick()
		local camera = Workspace.CurrentCamera
		if camera == nil or next(plates) == nil then
			return
		end
		if camera.CFrame ~= lastCameraCFrame then
			stagger()
		end
	end

	api = {
		folder = folder,
		update = update,
		tick = tick,
		setScale = function(newScale: number)
			scale = newScale
			for _, plate in plates do
				applyScale(plate)
			end
		end,
		hide = function()
			for _, plate in plates do
				plate.gui.Enabled = false
			end
		end,
		onPick = function(callback)
			pick = callback
		end,
		destroy = function()
			clear()
			folder:Destroy()
		end,
	}
	return api
end

return EnemyOverlay
