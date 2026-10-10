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

-- The screen area the plates may use, in viewport pixels: between the HUD's status line and its
-- recent-actions feed, and between the command ring's column and the party cards' column
-- (CombatHUD works it out from its layout). Plates that would land outside are pushed inside.
export type Bounds = { left: number, top: number, right: number, bottom: number }

export type EnemyOverlay = {
	folder: Folder,
	update: (battle: HudBattle, targetId: string?, pickable: { [string]: boolean }) -> (),
	tick: () -> (), -- every frame: re-places the plates once the battle camera has moved enough
	setScale: (scale: number) -> (),
	setBounds: (bounds: Bounds) -> (),
	hide: () -> (),
	onPick: (callback: (id: string) -> ()) -> (),
	destroy: () -> (),
}

type Plate = {
	gui: BillboardGui,
	root: Frame,
	scale: UIScale,
	baseOffset: number, -- studs above the spot, from BattleView's own plate
	row: number, -- stacked this many plates down last time (hysteresis)
	placedAt: Vector3?, -- the world-space offset last written
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
EnemyOverlay.STACK_GAP = 6 -- pixels between stacked plates
EnemyOverlay.BESIDE_STUDS = 1.5 -- a plate put beside its enemy clears its middle by this much (a head's half-width and some)
EnemyOverlay.HEAD_GAP_STUDS = 1.8 -- BattleView hangs the plate's anchor this far above the enemy's head
EnemyOverlay.STACK_SLACK = 12 -- pixels a stacked plate may hang past the box's bottom before it goes sideways instead (a phone's box is two plates tall less a few pixels)
-- The camera has to move this much before the plates are placed again (the idle sway stays under
-- it, so a held shot costs nothing per frame).
EnemyOverlay.REPLACE_DISTANCE = 0.3 -- studs
EnemyOverlay.REPLACE_ANGLE = math.cos(math.rad(1))
EnemyOverlay.REPLACE_FOV = 0.5 -- degrees of field of view (the confirm punch, a shot's own FOV) before the plates are placed again

-- Where a world point lands on the viewport (pixels; it may be outside it) and whether it's in
-- front of the camera. A plain function, so the per-frame pcall allocates nothing.
local function projectPoint(camera: Camera, point: Vector3): (number, number, boolean)
	local screen = camera:WorldToViewportPoint(point)
	return screen.X, screen.Y, screen.Z > 0
end

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
	local bounds: Bounds? = nil

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
	-- The box is also written on the folder (BoxLeft/Top/Right/Bottom, viewport pixels), for the
	-- tests and for debugging in Studio.
	local function writeBounds()
		local box = bounds
		if box then
			folder:SetAttribute("BoxLeft", box.left)
			folder:SetAttribute("BoxTop", box.top)
			folder:SetAttribute("BoxRight", box.right)
			folder:SetAttribute("BoxBottom", box.bottom)
		end
	end

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
		writeBounds()
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
			local plate: Plate = { gui = gui, root = root, scale = uiScale, baseOffset = 0, row = 0, placedAt = nil, button = button, stroke = button:FindFirstChildOfClass("UIStroke"), title = title, hp = hp, statuses = statuses, statusKey = "", left = left, right = right, weak = weak, down = down }
			applyScale(plate)
			plates[id] = plate
		end
		builtFor = battle.rosterKey
	end

	-- Placing the plates for the current camera: each hangs over its enemy's head, pushed inside the
	-- HUD's bounds, and plates that would overlap stack downward (the later one in screen order
	-- drops a row; a plate keeps its row while it's within a looser distance, so nothing flickers
	-- during a pan). The result is written as a world-space offset, only when it changed. Needs the
	-- camera's projection, which the tests' fake Roblox doesn't have; then the plates stay put.
	local lastCameraPosition: Vector3? = nil
	local lastCameraLook: Vector3? = nil
	local lastCameraUp: Vector3? = nil -- (the Dutch tilt and the whip roll turn the frame without moving it)
	local lastCameraFov = 0
	type Entry = { plate: Plate, x: number, y: number, anchorX: number, anchorY: number, pixelsPerStud: number }
	local function byX(a: Entry, b: Entry): boolean
		return a.x < b.x
	end
	local function place()
		local camera = Workspace.CurrentCamera
		if camera == nil then
			return
		end
		local cameraCFrame = camera.CFrame
		lastCameraPosition = cameraCFrame.Position
		lastCameraLook = cameraCFrame.LookVector
		lastCameraUp = cameraCFrame.UpVector
		lastCameraFov = camera.FieldOfView
		local plateWidth, plateHeight = width * scale, height * scale
		local entries: { Entry } = {}
		for _, plate in plates do
			local spot: Instance? = plate.gui.Adornee
			if not plate.gui.Enabled or spot == nil or not spot:IsA("BasePart") then
				continue
			end
			local base = spot.CFrame.Position + Vector3.new(0, plate.baseOffset, 0)
			local ok, x, y, inFront = pcall(projectPoint, camera, base)
			if not ok then
				return -- no projection here (the fake Roblox without a camera): leave every plate where it is
			end
			-- A plate whose anchor is behind the camera, or far outside the frame, hides; one just
			-- above or beside the frame (a tall enemy's head in a close shot) is pulled in below. A
			-- plate the player can tap (picking a target) stays however far out its enemy is: the
			-- target shot is tight on one enemy, and the others must still be there to switch to.
			local viewport = camera.ViewportSize
			local margin = viewport.Y * 0.5
			local pinned = plate.button.Interactable
			local placeable = inFront and (pinned or (x > -margin and x < viewport.X + margin and y > -margin and y < viewport.Y + margin))
			plate.root.Visible = placeable
			if not placeable then
				continue
			end
			local _, upY = projectPoint(camera, base + Vector3.new(0, 1, 0)) -- (the first call just worked, so this one does)
			local pixelsPerStud = math.max(y - upY, 0.001)
			table.insert(entries, { plate = plate, x = x, y = y, anchorX = x, anchorY = y, pixelsPerStud = pixelsPerStud })
		end
		table.sort(entries, byX)

		local rowStep = plateHeight + EnemyOverlay.STACK_GAP
		local box = bounds
		local minX, maxX = -math.huge, math.huge
		local minY, maxY = -math.huge, math.huge
		if box then
			minX, maxX = box.left + plateWidth / 2, math.max(box.left + plateWidth / 2, box.right - plateWidth / 2)
			minY, maxY = box.top + plateHeight / 2, math.max(box.top + plateHeight / 2, box.bottom - plateHeight / 2)
		end
		-- 1. Each plate inside the box, where it would hang on its own. One the box's top pushes
		-- down onto its own enemy's head (a close shot: the head is near the top of the box) goes
		-- beside the enemy instead, on whichever side fits, toward the screen's middle if both do.
		local middleX = (minX + maxX) / 2
		for _, entry in entries do
			local pushedDown = math.clamp(entry.y, minY, maxY) - entry.y
			entry.x = math.clamp(entry.x, minX, maxX)
			entry.y = math.clamp(entry.y, minY, maxY)
			local headTop = entry.anchorY + entry.pixelsPerStud * EnemyOverlay.HEAD_GAP_STUDS
			local overHead = entry.y + plateHeight / 2 > headTop
				and math.abs(entry.x - entry.anchorX) < plateWidth / 2 + entry.pixelsPerStud * EnemyOverlay.BESIDE_STUDS
			if pushedDown > 0 and overHead then
				local clear = plateWidth / 2 + entry.pixelsPerStud * EnemyOverlay.BESIDE_STUDS
				local leftX, rightX = entry.anchorX - clear, entry.anchorX + clear
				local leftFits = leftX >= minX and leftX <= maxX
				local rightFits = rightX >= minX and rightX <= maxX
				if leftFits and rightFits then
					entry.x = if entry.anchorX > middleX then leftX else rightX
				elseif leftFits then
					entry.x = leftX
				elseif rightFits then
					entry.x = rightX
				end
			end
		end
		-- 2. Plates that would sit on each other move apart: a row down when the box has room,
		-- else pushed apart sideways, both of them, within the box. A plate that was displaced
		-- last time only goes back once it's clear by a wider margin (hysteresis), so nothing
		-- flickers during a pan.
		local displaced: { [Plate]: boolean } = {}
		for _ = 1, 3 do
			local any = false
			for i = 1, #entries - 1 do
				for j = i + 1, #entries do
					local a, b = entries[i], entries[j]
					local loose = if a.plate.row > 0 or b.plate.row > 0 then 24 else EnemyOverlay.STACK_GAP
					local dx, dy = b.x - a.x, b.y - a.y
					-- (Rows are a row step apart: a stacked pair is separated, however loose the sideways test.)
					if math.abs(dx) >= plateWidth + loose or math.abs(dy) >= rowStep - 0.5 then
						continue
					end
					any = true
					displaced[b.plate] = true
					local lower = math.max(a.y, b.y) + rowStep
					if lower <= maxY + EnemyOverlay.STACK_SLACK then
						-- Room below: the one further right drops a row under the other.
						b.y = math.max(b.y, a.y + rowStep)
					else
						-- Side by side: push both apart, and if the box stops one, the other gives way.
						displaced[a.plate] = true
						local need = plateWidth + EnemyOverlay.STACK_GAP - math.abs(dx)
						local leftOne, rightOne = if dx >= 0 then a else b, if dx >= 0 then b else a
						leftOne.x -= need / 2
						rightOne.x += need / 2
						if leftOne.x < minX then
							rightOne.x += minX - leftOne.x
							leftOne.x = minX
						end
						if rightOne.x > maxX then
							leftOne.x -= rightOne.x - maxX
							rightOne.x = maxX
						end
						leftOne.x = math.clamp(leftOne.x, minX, maxX)
						rightOne.x = math.clamp(rightOne.x, minX, maxX)
					end
				end
			end
			if not any then
				break
			end
		end
		-- (Whatever the passes did, every plate ends inside the box, the stack's slack included.)
		for _, entry in entries do
			entry.x = math.clamp(entry.x, minX, maxX)
			entry.y = math.clamp(entry.y, minY, maxY + EnemyOverlay.STACK_SLACK)
		end
		-- 3. Back to the world: the point at the anchor's depth that the camera sees at the plate's
		-- pixel (a ray through the pixel, exact under perspective however far a pinned plate moved
		-- from its enemy), as an offset from the spot, written only when it changed.
		local cameraPosition = cameraCFrame.Position
		local right, up, look = cameraCFrame.RightVector, cameraCFrame.UpVector, cameraCFrame.LookVector
		local viewport = camera.ViewportSize
		local tanY = math.tan(math.rad(camera.FieldOfView) / 2)
		local tanX = tanY * viewport.X / math.max(viewport.Y, 1)
		for _, entry in entries do
			local plate = entry.plate
			plate.row = if displaced[plate] then 1 else 0
			local spot = plate.gui.Adornee :: BasePart
			local spotAt = spot.CFrame.Position
			local anchor = spotAt + Vector3.new(0, plate.baseOffset, 0)
			local depth = (anchor - cameraPosition):Dot(look)
			local nx = entry.x / viewport.X * 2 - 1
			local ny = 1 - entry.y / viewport.Y * 2
			local through = look + right * (nx * tanX) + up * (ny * tanY)
			-- (The engine applies StudsOffsetWorldSpace in the spot's own frame, not the world's: the
			-- enemies' spots are turned to face the party, so the world offset is turned with them.)
			local offset = spot.CFrame:VectorToObjectSpace(cameraPosition + through * depth - spotAt)
			local last = plate.placedAt
			if last == nil or (last - offset).Magnitude > 0.02 then
				plate.placedAt = offset
				plate.gui.StudsOffsetWorldSpace = offset
			end
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
				plate.baseOffset = offset.Y
				if plate.placedAt == nil then
					plate.gui.StudsOffset = Vector3.zero
					plate.gui.StudsOffsetWorldSpace = Vector3.new(0, offset.Y, 0) -- over its head until placed
				end
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
		place()
	end

	-- Every frame: place the plates again once the camera has moved or turned enough.
	local function tick()
		local camera = Workspace.CurrentCamera
		if camera == nil or next(plates) == nil then
			return
		end
		local cframe = camera.CFrame
		local lastPosition, lastLook, lastUp = lastCameraPosition, lastCameraLook, lastCameraUp
		if lastPosition == nil or lastLook == nil or lastUp == nil then
			place()
		elseif (cframe.Position - lastPosition).Magnitude > EnemyOverlay.REPLACE_DISTANCE
			or cframe.LookVector:Dot(lastLook) < EnemyOverlay.REPLACE_ANGLE
			or cframe.UpVector:Dot(lastUp) < EnemyOverlay.REPLACE_ANGLE
			or math.abs(camera.FieldOfView - lastCameraFov) > EnemyOverlay.REPLACE_FOV
		then
			place()
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
		setBounds = function(newBounds: Bounds)
			bounds = newBounds
			writeBounds()
			lastCameraPosition = nil -- place again on the next tick
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
