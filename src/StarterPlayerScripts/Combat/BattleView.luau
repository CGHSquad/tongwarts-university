--!strict
--[[
	BattleView — the 3D side of the prototype: the combatants on a little stage, an outline on
	whoever is acting and on your chosen target, a small hit effect, and a fixed battle camera.

	Who you see (GDD Step 6, "The player character on the field"):
		party    each player's own character, which never leaves its spot. It makes its own moves
		         itself: Attack and Guard (and Items, later). For one of its summon's own abilities
		         (Strike, Gale Clap, Sap Mend, ...) the summon, a colored block, materializes behind
		         the character, up over its shoulder, performs the move and dismisses again,
		         Stand/Persona-style: for that beat the two are on the field together.
		enemies  just their creature, a block: they have no character/summon split.
	The character is a copy of that player's avatar, or a blocky stand-in when this client can't see
	their avatar. Stats, HP and Mana all still belong to the summon; this is only how a turn looks.

	Everything here exists only on this client and is redrawn from server snapshots: it's a picture
	of the BattleSession, not the real thing. Replacing the blocks with real summon models later
	won't touch any combat code.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Abilities = require(Combat:WaitForChild("Abilities"))
local BattleTypes = require(Combat:WaitForChild("BattleTypes"))
local StatusEffects = require(Combat:WaitForChild("StatusEffects"))
local BattleTheme = require(script.Parent:WaitForChild("BattleTheme"))

type BattleState = BattleTypes.BattleState
type ParticipantState = BattleTypes.ParticipantState

-- The stage is its own little arena out past the north edge of the overworld's baseplate, so
-- nothing out exploring wanders through the fight. The camera looks across it, away from the
-- overworld, with the party on the left and the enemies on the right, matching the HUD panels.
local STAGE_CENTER = Vector3.new(0, 0, -700)
local STAGE_FLOOR_SIZE = Vector3.new(80, 1, 60)
local BLOCK_SIZE = Vector3.new(5, 5, 5)
local CAMERA_POSITION = STAGE_CENTER + Vector3.new(0, 20, 40)
local CAMERA_FOCUS = STAGE_CENTER + Vector3.new(0, 3, 0)
-- A party member's summon is only out while it uses one of its own abilities: it materializes, does
-- the move and dismisses in SUMMON_SECONDS, fading in and out over SUMMON_FADE_SECONDS of that.
local SUMMON_SECONDS = 1.2
local SUMMON_FADE_SECONDS = 0.2
-- Where it materializes, relative to its spot (which faces the enemies): behind the character, up
-- over its shoulder, and a step further from the camera, so the character stays in view in front.
local SUMMON_SOCKET = CFrame.new(-1.5, 4, 4)

-- One combatant's spot on the stage. Its folder (named after the participant) holds what's on the
-- field there, named "Character" and "Summon", plus the Spot that carries its nameplate and popups.
type Figure = {
	folder: Folder,
	home: CFrame, -- the spot, facing the other side
	spot: Part, -- invisible, at home
	summon: Part, -- the summon's block (for an enemy, its creature)
	summonHome: CFrame, -- where the block stands: home for an enemy, a party member's socket
	character: Model?, -- party members: the player's character, always on the field
	characterRoot: BasePart?,
	characterHome: CFrame?, -- where the character's root stands
	highlight: Highlight,
	hpLabel: TextLabel,
	appearances: number, -- bumped each time the summon comes out, so only the latest one dismisses it
}

local BattleView = {}
BattleView.__index = BattleView

type ViewFields = {
	folder: Folder?,
	figures: { [string]: Figure },
	battle: BattleState?,
	lastActionSeen: number,
	targetId: string?,
	targetFriendly: boolean,
	cameraActive: boolean,
}

export type BattleView = typeof(setmetatable({} :: ViewFields, BattleView))

-- Slot 2 stands further out and nearer the camera so the two on a side don't overlap.
local function slotCFrame(side: string, slot: number): CFrame
	local direction = if side == "Party" then -1 else 1
	local position = STAGE_CENTER + Vector3.new(direction * (9 + (slot - 1) * 5), BLOCK_SIZE.Y / 2, (slot - 1.5) * 10)
	return CFrame.lookAt(position, position - Vector3.new(direction, 0, 0)) -- face the other side
end

local function newBillboardLabel(parent: Instance, size: UDim2, position: UDim2, font: Enum.Font): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextScaled = true
	label.TextColor3 = BattleTheme.Text
	label.TextStrokeTransparency = 0.2
	label.Parent = parent
	return label
end

local function stagePart(name: string, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Material = Enum.Material.SmoothPlastic
	return part
end

--[[ The player's character ]]

-- A copy of a player's avatar to stand on the stage, or nil if this client can't see it (it hasn't
-- loaded, or it's too far away to have streamed in) or it's dead (in pieces until it respawns).
local function copyAvatar(userId: number?): Model?
	local player = if userId then Players:GetPlayerByUserId(userId) else nil
	local character = if player then player.Character else nil
	if character == nil or character:FindFirstChild("HumanoidRootPart") == nil then
		return nil
	end
	local living = character:FindFirstChildOfClass("Humanoid")
	if living and living.Health <= 0 then
		return nil
	end
	local archivable = character.Archivable
	character.Archivable = true
	local copy = character:Clone()
	character.Archivable = archivable
	if copy == nil then
		return nil
	end

	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("ForceField") then
			-- No Animate or Health scripts (this copy only poses and lunges), and no spawn shield,
			-- which would never wear off the copy.
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = false -- held by its joints to the root, which is anchored below
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
	local humanoid = copy:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- the stage has its own nameplate
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	return copy
end

type Limb = { name: string, size: Vector3, offset: Vector3, color: Color3 }

-- A blocky figure standing in for a player's character, in its slot's color.
local function buildStandIn(color: Color3): Model
	local model = Instance.new("Model")
	local root = stagePart("HumanoidRootPart", Vector3.new(2, 2, 1))
	root.Transparency = 1
	root.CFrame = CFrame.new()
	root.Parent = model
	-- Built around the origin and welded to the root, so moving the root moves the whole figure.
	local limbs: { Limb } = {
		{ name = "Torso", size = Vector3.new(2, 2, 1), offset = Vector3.new(0, 0, 0), color = color },
		{ name = "Head", size = Vector3.new(1.2, 1.2, 1.2), offset = Vector3.new(0, 1.6, 0), color = BattleTheme.Skin },
		{ name = "Left Arm", size = Vector3.new(1, 2, 1), offset = Vector3.new(-1.5, 0, 0), color = color },
		{ name = "Right Arm", size = Vector3.new(1, 2, 1), offset = Vector3.new(1.5, 0, 0), color = color },
		{ name = "Left Leg", size = Vector3.new(1, 2, 1), offset = Vector3.new(-0.5, -2, 0), color = BattleTheme.Legs },
		{ name = "Right Leg", size = Vector3.new(1, 2, 1), offset = Vector3.new(0.5, -2, 0), color = BattleTheme.Legs },
	}
	for _, limb in limbs do
		local part = stagePart(limb.name, limb.size)
		part.Anchored = false
		part.CFrame = CFrame.new(limb.offset)
		part.Color = limb.color
		part.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end
	model.PrimaryPart = root
	return model
end

-- How high a character's root stands off the floor.
local function rootHeight(model: Model, root: BasePart): number
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return 3 -- R6 avatars and the stand-in: 2-stud legs under a 2-stud torso
end

--[[ Figures ]]

local function createFigure(participant: ParticipantState, parent: Instance): Figure
	local home = slotCFrame(participant.side, participant.slot)
	local folder = Instance.new("Folder")
	folder.Name = participant.id

	local spot = stagePart("Spot", Vector3.new(1, 1, 1))
	spot.CFrame = home
	spot.Transparency = 1
	spot.Parent = folder

	local nameplate = Instance.new("BillboardGui")
	nameplate.Name = "Nameplate"
	nameplate.Adornee = spot
	nameplate.Size = UDim2.fromOffset(180, 44)
	nameplate.StudsOffset = Vector3.new(0, BLOCK_SIZE.Y / 2 + 1.8, 0)
	nameplate.AlwaysOnTop = true
	nameplate.LightInfluence = 0
	nameplate.Parent = spot
	local nameLabel = newBillboardLabel(nameplate, UDim2.fromScale(1, 0.55), UDim2.fromScale(0, 0), BattleTheme.FontBold)
	nameLabel.Text = participant.name
	local hpLabel = newBillboardLabel(nameplate, UDim2.fromScale(1, 0.45), UDim2.fromScale(0, 0.55), BattleTheme.Font)

	local summon = stagePart("Summon", BLOCK_SIZE)
	summon.CFrame = home
	summon.Color = BattleTheme.colorFor(participant.side, participant.slot)

	local highlight = Instance.new("Highlight")
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.OutlineTransparency = 0
	highlight.Enabled = false
	highlight.Parent = folder

	local figure: Figure = {
		folder = folder,
		home = home,
		spot = spot,
		summon = summon,
		summonHome = home,
		character = nil,
		characterRoot = nil,
		characterHome = nil,
		highlight = highlight,
		hpLabel = hpLabel,
		appearances = 0,
	}

	-- A player's party member is their character on the field. Its summon stays off the field until
	-- it's used, then appears at its socket behind the character (see bringOutSummon).
	local shown: Instance = summon
	if participant.side == "Party" then
		local character = copyAvatar(participant.ownerUserId) or buildStandIn(summon.Color)
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
		character.Name = "Character"
		local floor = home.Position - Vector3.new(0, BLOCK_SIZE.Y / 2, 0)
		local characterHome = home.Rotation + floor + Vector3.new(0, rootHeight(character, root), 0)
		-- Move every part into place (as Model:PivotTo would): until it's on the stage, its joints
		-- won't carry the rest along with the root. After that, moving the anchored root is enough.
		local shift = characterHome * root.CFrame:Inverse()
		for _, descendant in character:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CFrame = shift * descendant.CFrame
			end
		end
		root.Anchored = true
		figure.character = character
		figure.characterRoot = root
		figure.characterHome = characterHome
		figure.summonHome = home * SUMMON_SOCKET
		summon.CFrame = figure.summonHome
		shown = character
	end

	shown.Parent = folder
	highlight.Adornee = shown
	folder.Parent = parent
	return figure
end

-- What stands in a figure's spot and takes its hits, and where it stands: a party member's
-- character (moved by its root), or an enemy's creature.
local function body(figure: Figure): (BasePart, CFrame)
	local root, characterHome = figure.characterRoot, figure.characterHome
	if root and characterHome then
		return root, characterHome
	end
	return figure.summon, figure.home
end

-- Moves a part a little way from where it stands and straight back: a lunge or a recoil.
local function nudge(part: BasePart, rest: CFrame, offset: Vector3, seconds: number, delaySeconds: number)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true, delaySeconds)
	part.CFrame = rest
	TweenService:Create(part, info, { CFrame = rest + offset }):Play()
end

local function fadeSummon(summon: BasePart, transparency: number)
	TweenService:Create(summon, TweenInfo.new(SUMMON_FADE_SECONDS), { Transparency = transparency }):Play()
end

-- A party member's summon materializes at its socket behind the character to use one of its own
-- abilities, and dismisses once that has played out. The character stays on the field throughout.
local function bringOutSummon(figure: Figure)
	figure.appearances += 1
	local appearance = figure.appearances
	local summon = figure.summon
	summon.CFrame = figure.summonHome
	summon.Transparency = 1
	summon.Parent = figure.folder
	fadeSummon(summon, 0)
	task.delay(SUMMON_SECONDS - SUMMON_FADE_SECONDS, function()
		if figure.appearances == appearance then
			fadeSummon(summon, 1)
		end
	end)
	task.delay(SUMMON_SECONDS, function()
		if figure.appearances == appearance then
			summon.Parent = nil
		end
	end)
end

-- A word or number that floats up off a spot and fades: damage, MISS, healing, a status.
local function showPopup(figure: Figure, text: string, color: Color3, startHeight: number)
	local popup = Instance.new("BillboardGui")
	popup.Name = "Popup"
	popup.Adornee = figure.spot
	popup.Size = UDim2.fromOffset(160, 40)
	popup.StudsOffset = Vector3.new(0, startHeight, 0)
	popup.AlwaysOnTop = true
	popup.LightInfluence = 0
	local label = newBillboardLabel(popup, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), BattleTheme.FontHeavy)
	label.Text = text
	label.TextColor3 = color
	popup.Parent = figure.spot

	local rise = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(popup, rise, { StudsOffset = Vector3.new(0, startHeight + 3.5, 0) }):Play()
	TweenService:Create(label, rise, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(popup, 1)
end

--[[ BattleView ]]

function BattleView.new(): BattleView
	local fields: ViewFields = {
		folder = nil,
		figures = {},
		battle = nil,
		lastActionSeen = 0,
		targetId = nil,
		targetFriendly = false,
		cameraActive = false,
	}
	return setmetatable(fields, BattleView)
end

-- Draws the latest battle state (nil = no battle running).
function BattleView.render(self: BattleView, battle: BattleState?)
	local previous = self.battle
	self.battle = battle
	if battle == nil then
		self:_clear()
		self:_setBattleCamera(false)
		return
	end

	if previous == nil or previous.battleId ~= battle.battleId or self.folder == nil then
		self:_build(battle)
	end
	self:_setBattleCamera(true)
	self:_refreshFigures()

	local action = battle.lastAction
	if action ~= nil and action.sequence > self.lastActionSeen then
		self.lastActionSeen = action.sequence
		self:_playAction(battle, action)
	end
end

-- Outlines the summon you've picked in the HUD: red for an enemy, green for a party member
-- you're healing. nil clears it.
function BattleView.setTarget(self: BattleView, targetId: string?, friendly: boolean)
	if self.targetId == targetId and self.targetFriendly == friendly then
		return
	end
	self.targetId = targetId
	self.targetFriendly = friendly
	self:_refreshFigures()
end

function BattleView._build(self: BattleView, battle: BattleState)
	self:_clear()
	local folder = Instance.new("Folder")
	folder.Name = "BattleStage"
	local floor = stagePart("Floor", STAGE_FLOOR_SIZE)
	floor.CFrame = CFrame.new(STAGE_CENTER - Vector3.new(0, STAGE_FLOOR_SIZE.Y / 2, 0))
	floor.Material = Enum.Material.Grass
	floor.Color = Color3.fromRGB(92, 115, 77)
	floor.Parent = folder
	for _, participant in battle.participants do
		self.figures[participant.id] = createFigure(participant, folder)
	end
	folder.Parent = Workspace
	self.folder = folder
	-- Don't replay an action that happened before this client started watching.
	self.lastActionSeen = if battle.lastAction then battle.lastAction.sequence else 0
end

function BattleView._clear(self: BattleView)
	for _, figure in self.figures do
		figure.appearances += 1 -- any pending dismissal is moot now
		figure.summon:Destroy()
		if figure.character then
			figure.character:Destroy()
		end
	end
	table.clear(self.figures)
	if self.folder then
		self.folder:Destroy()
		self.folder = nil
	end
end

function BattleView._refreshFigures(self: BattleView)
	local battle = self.battle
	if battle == nil then
		return
	end

	for _, participant in battle.participants do
		local figure = self.figures[participant.id]
		if figure == nil then
			continue
		end

		local fade = 0
		if participant.status == "KnockedOut" then
			figure.summon.Color = BattleTheme.KnockedOut
			fade = 0.35
			figure.hpLabel.Text = "Knocked out"
		elseif participant.status == "Left" then
			figure.summon.Color = BattleTheme.colorFor(participant.side, participant.slot)
			fade = 0.75
			figure.hpLabel.Text = "Left the battle"
		else
			figure.summon.Color = BattleTheme.colorFor(participant.side, participant.slot)
			figure.hpLabel.Text = `HP {participant.hp}/{participant.maxHp}`
		end
		local character = figure.character
		if character == nil then
			figure.summon.Transparency = fade
		else
			-- A party member's summon fades itself in and out (bringOutSummon); this fades the
			-- character. LocalTransparencyModifier keeps parts that are meant to be invisible (the
			-- root) invisible.
			for _, descendant in character:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.LocalTransparencyModifier = fade
				elseif descendant:IsA("Decal") then
					descendant.LocalTransparencyModifier = fade
				end
			end
		end

		local acting = battle.phase == "input" and battle.currentActorId == participant.id
		if acting then
			figure.highlight.OutlineColor = BattleTheme.Accent
			figure.highlight.FillTransparency = 1
			figure.highlight.Enabled = true
		elseif self.targetId == participant.id then
			local color = if self.targetFriendly then BattleTheme.HealthBar else BattleTheme.Danger
			figure.highlight.OutlineColor = color
			figure.highlight.FillColor = color
			figure.highlight.FillTransparency = 0.6
			figure.highlight.Enabled = true
		else
			figure.highlight.Enabled = false
		end
	end
end

-- Plays what an action did: a party member's summon comes out if it's one of the summon's own
-- abilities, whoever performs the move lunges at its target and hits make the target recoil, then
-- every target gets a popup (damage, CRIT, MISS, an ailment, Mana a guard won back, healing, GUARD,
-- or the status gained).
function BattleView._playAction(self: BattleView, battle: BattleState, action: BattleTypes.ActionRecord)
	local actor = self.figures[action.actorId]
	local ability = Abilities[action.abilityId]
	if actor == nil or ability == nil then
		return
	end

	-- Attack and Guard are the character's own moves. Anything in the summon's list brings the
	-- summon out to perform it, while the character holds its ground.
	local performer, performerHome = body(actor)
	local lead = 0 -- how long the move waits for its performer to materialize
	for _, participant in battle.participants do
		if participant.id == action.actorId and participant.side == "Party" then
			if table.find(participant.abilities, ability.id) ~= nil then
				bringOutSummon(actor)
				performer, performerHome, lead = actor.summon, actor.summonHome, SUMMON_FADE_SECONDS
			end
		end
	end

	for index, result in action.results do
		local target = self.figures[result.targetId]
		if target == nil then
			continue
		end

		if ability.kind == "Attack" and target ~= actor then
			local toward = (target.home.Position - actor.home.Position).Unit
			if index == 1 then
				nudge(performer, performerHome, toward * 4, 0.15, lead)
			end
			if result.hit then
				local struck, struckHome = body(target)
				nudge(struck, struckHome, toward * 1.5, 0.1, lead + 0.12)
			end
		end

		if ability.kind == "Attack" then
			if not result.hit then
				showPopup(target, "MISS", BattleTheme.SubtleText, 0)
			else
				local strong = result.critical or result.knockedOut
				showPopup(
					target,
					if result.critical then `CRIT -{result.damage}` else `-{result.damage}`,
					if strong then BattleTheme.Danger else BattleTheme.Text,
					0
				)
				local inflicted = result.inflicted
				if inflicted then
					local def = StatusEffects[inflicted]
					showPopup(target, `{if def then def.name else inflicted}!`, BattleTheme.Danger, 1.5)
				end
			end
		elseif ability.kind == "Heal" then
			showPopup(target, `+{result.healed}`, BattleTheme.HealthBar, 0)
		elseif ability.kind == "Guard" then
			showPopup(target, "GUARD", BattleTheme.ManaBar, 0)
		else
			local applied = result.applied
			local def = if applied then StatusEffects[applied] else nil
			showPopup(target, if def then def.name else ability.name, BattleTheme.Accent, 0)
		end
	end
end

function BattleView._setBattleCamera(self: BattleView, active: boolean)
	if self.cameraActive == active then
		return
	end
	self.cameraActive = active

	local camera = Workspace.CurrentCamera
	if active then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(CAMERA_POSITION, CAMERA_FOCUS)
	else
		camera.CameraType = Enum.CameraType.Custom
	end
end

return BattleView
