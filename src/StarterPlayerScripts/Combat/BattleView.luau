--!strict
--[[
	BattleView — the 3D side of the prototype: the combatants on a little stage, an outline on
	whoever is acting and on your chosen target, a small hit effect, and a fixed battle camera.

	Who you see (GDD Step 6, "The player character on the field"):
		party    each player's own character, which never leaves its spot. It makes its own moves
		         itself: Attack and Guard (and Items, later). For one of its summon's own abilities
		         (Strike, Gale Clap, Sap Mend, ...) the summon materializes behind the character, up
		         over its shoulder, performs the move and dismisses again, Stand/Persona-style: for
		         that beat the two are on the field together. It comes out once more to fall when
		         it's knocked out, if it has a death clip.
		enemies  just their creature: they have no character/summon split.
	The character is a copy of that player's avatar, or a blocky stand-in when this client can't see
	their avatar. A summon is its real 3D model and animations when Summons gives it `art` (idle while
	it's out, its attack clip timed to the blow landing, death when it's knocked out), or a colored
	block when it doesn't. Stats, HP and Mana all still belong to the summon; this is only how a
	turn looks.

	Everything here exists only on this client and is redrawn from server snapshots: it's a picture
	of the BattleSession, not the real thing.
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
local Summons = require(Combat:WaitForChild("Summons"))
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
-- A summon's attack clip plays sped up when it's longer than this, so even a slow swing is over
-- before the next turn opens (CombatConfig.ResolvePauseSeconds after the action).
local ATTACK_MAX_SECONDS = 1.6

-- A summon's animation tracks, loaded from its art once its model is in the DataModel. Any can be
-- missing (see Summons.SummonAnimations).
type Clips = {
	idle: AnimationTrack?, -- looping, or the attack held on its first frame when there's no idle
	idleFrozen: boolean,
	attack: AnimationTrack?,
	death: AnimationTrack?,
}

-- One combatant's spot on the stage. Its folder (named after the participant) holds what's on the
-- field there, named "Character" and "Summon", plus the Spot that carries its nameplate and popups.
type Figure = {
	folder: Folder,
	home: CFrame, -- the spot, facing the other side
	spot: Part, -- invisible, at home
	summon: Model, -- the summon (for an enemy, its creature): its real model, or a colored block
	summonRoot: BasePart, -- the summon's anchored root; everything else hangs off it by its joints
	summonHome: CFrame, -- where that root stands: on the spot for an enemy, a party member's socket
	summonBlock: Part?, -- the colored block, when there's no real model
	art: Summons.SummonArt?, -- the real model's animations, when it has one
	clips: Clips?, -- loaded once the model has been on the stage
	character: Model?, -- party members: the player's character, always on the field
	characterRoot: BasePart?,
	characterHome: CFrame?, -- where the character's root stands
	highlight: Highlight,
	hpLabel: TextLabel,
	appearances: number, -- bumped each time the summon comes out, so only the latest one dismisses it
	knockedOut: boolean, -- so its fall only plays once, when it happens
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
	enemyNameplates: boolean, -- off when the new HUD draws its own enemy plates (M0 report R19)
}

export type Options = {
	enemyNameplates: boolean?, -- default true
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

-- Moves every part of a model so `part` ends up at `target`, as Model:PivotTo would. Until a model
-- is on the stage its joints won't carry the rest along with one part; after that, moving its
-- anchored root is enough.
local function moveModel(model: Model, part: BasePart, target: CFrame)
	local shift = target * part.CFrame:Inverse()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CFrame = shift * descendant.CFrame
		end
	end
end

-- Fades a whole figure in or out (1 = gone). LocalTransparencyModifier keeps parts that are meant
-- to be invisible, like a rig's root, invisible.
local function fadeModel(model: Model, fade: number, seconds: number)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			if seconds > 0 then
				TweenService:Create(descendant, TweenInfo.new(seconds), { LocalTransparencyModifier = fade }):Play()
			elseif descendant:IsA("BasePart") then
				descendant.LocalTransparencyModifier = fade
			elseif descendant:IsA("Decal") then
				descendant.LocalTransparencyModifier = fade
			end
		end
	end
end

--[[ The summon ]]

-- The tallest part of a model. For an imported rig that's its skinned body mesh, whose center and
-- height stand for the whole figure (its weapon and invisible root don't).
local function tallestPart(model: Model): BasePart?
	local tallest: BasePart? = nil
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and (tallest == nil or descendant.Size.Y > tallest.Size.Y) then
			tallest = descendant
		end
	end
	return tallest
end

local warnedMissing: { [string]: boolean } = {}

-- A copy of a summon's real model, scaled to its art's height, plus its body (see tallestPart) and
-- root; nil when it has no art, or its model isn't in ReplicatedStorage.SummonModels.
local function copySummonModel(art: Summons.SummonArt?): (Model?, BasePart?, BasePart?)
	if art == nil then
		return nil, nil, nil
	end
	local models = ReplicatedStorage:FindFirstChild("SummonModels")
	local original = if models then models:FindFirstChild(art.model) else nil
	if original == nil or not original:IsA("Model") then
		if not warnedMissing[art.model] then
			warnedMissing[art.model] = true
			warn(`BattleView: no model "{art.model}" in ReplicatedStorage.SummonModels, so it's a block for now`)
		end
		return nil, nil, nil
	end
	local copy = original:Clone()
	local body = tallestPart(copy)
	if body == nil then
		copy:Destroy()
		return nil, nil, nil
	end
	copy:ScaleTo(copy:GetScale() * art.height / body.Size.Y)
	local root = copy.PrimaryPart or body
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = descendant == root -- the rest follow it by their joints
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
	return copy, body, root
end

-- A colored block standing in for a summon that has no model yet.
local function buildSummonBlock(color: Color3): (Model, Part)
	local model = Instance.new("Model")
	local block = stagePart("Block", BLOCK_SIZE)
	block.Color = color
	block.Parent = model
	model.PrimaryPart = block
	return model, block
end

local function loadTrack(animator: Animator, id: string, looped: boolean, priority: Enum.AnimationPriority): AnimationTrack
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local track = animator:LoadAnimation(animation)
	track.Looped = looped
	track.Priority = priority
	return track
end

-- Loads the summon's clips, once. Its model has to be in the DataModel for that.
local function loadClips(figure: Figure)
	local art = figure.art
	if figure.clips ~= nil or art == nil then
		return
	end
	local controller = figure.summon:FindFirstChildOfClass("AnimationController")
	local animator = if controller then controller:FindFirstChildOfClass("Animator") else nil
	if animator == nil then
		return
	end
	local animations = art.animations
	local clips: Clips = { idle = nil, idleFrozen = false, attack = nil, death = nil }
	if animations.idle then
		clips.idle = loadTrack(animator, animations.idle, true, Enum.AnimationPriority.Idle)
	elseif animations.attack then
		-- No idle yet: stand in the attack's first frame rather than the model's T-pose.
		clips.idle = loadTrack(animator, animations.attack, false, Enum.AnimationPriority.Idle)
		clips.idleFrozen = true
	end
	if animations.attack then
		clips.attack = loadTrack(animator, animations.attack, false, Enum.AnimationPriority.Action)
	end
	if animations.death then
		clips.death = loadTrack(animator, animations.death, false, Enum.AnimationPriority.Action2)
	end
	figure.clips = clips
end

local function startIdle(figure: Figure)
	local clips = figure.clips
	local idle = if clips then clips.idle else nil
	if clips and idle and not idle.IsPlaying then
		idle:Play(0, 1, if clips.idleFrozen then 0 else 1)
	end
end

local function stopClips(figure: Figure)
	local clips = figure.clips
	if clips then
		for _, track in { clips.idle, clips.attack, clips.death } :: { AnimationTrack? } do
			if track then
				track:Stop(0)
			end
		end
	end
end

-- Plays the summon's attack clip, if it has one. Returns how long it takes and how far in the blow
-- lands, in seconds; nil while its length isn't known (the clip is still downloading, the first
-- time), and then it plays at its own pace.
local function playAttackClip(figure: Figure): (number?, number?)
	local track = if figure.clips then figure.clips.attack else nil
	if track == nil then
		return nil, nil
	end
	if track.Length <= 0 then
		track:Play(0.1)
		return nil, nil
	end
	local speed = math.max(1, track.Length / ATTACK_MAX_SECONDS)
	track:Play(0.1, 1, speed)
	local seconds = track.Length / speed
	local art = figure.art
	return seconds, seconds * (if art and art.attackImpact then art.attackImpact else 0.5)
end

-- Plays the summon's death clip, if it has one, and holds its last frame. Returns how long it takes
-- (nil when that isn't known).
local function playDeathClip(figure: Figure): number?
	local clips = figure.clips
	local death = if clips then clips.death else nil
	if clips == nil or death == nil then
		return nil
	end
	if clips.idle then
		clips.idle:Stop(0.2)
	end
	death:Play(0.1)
	local connection: RBXScriptConnection
	connection = death.Stopped:Connect(function()
		connection:Disconnect()
		if figure.knockedOut then
			death:Play(0, 1, 0) -- frozen where it fell
			death.TimePosition = math.max(0, death.Length - 0.05)
		end
	end)
	return if death.Length > 0 then death.Length else nil
end

--[[ Figures ]]

local function createFigure(participant: ParticipantState, parent: Instance, enemyNameplates: boolean): Figure
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
	nameplate.Enabled = enemyNameplates or participant.side ~= "Enemy" -- the new HUD draws its own enemy plates
	nameplate.Parent = spot
	local nameLabel = newBillboardLabel(nameplate, UDim2.fromScale(1, 0.55), UDim2.fromScale(0, 0), BattleTheme.FontBold)
	nameLabel.Text = participant.name
	local hpLabel = newBillboardLabel(nameplate, UDim2.fromScale(1, 0.45), UDim2.fromScale(0, 0.55), BattleTheme.Font)

	-- The summon: its real model if it has one, otherwise a block in its slot's color.
	local color = BattleTheme.colorFor(participant.side, participant.slot)
	local def = Summons[participant.summonId]
	local art = if def then def.art else nil
	local summon, summonBody, summonRoot = copySummonModel(art)
	local summonBlock: Part? = nil
	if summon == nil or summonBody == nil or summonRoot == nil then
		local block
		summon, block = buildSummonBlock(color)
		summonBody, summonRoot, summonBlock, art = block, block, block, nil
	end
	assert(summon and summonBody and summonRoot)
	summon.Name = "Summon"
	local height = summonBody.Size.Y
	-- Lowered by however far its clips lift it (Summons.SummonArt.groundOffset), so it looks right
	-- once they play.
	local lowered = Vector3.new(0, if art and art.groundOffset then art.groundOffset * height else 0, 0)
	if participant.side == "Party" then
		-- Out at its socket behind the character, centered where a block's center would be.
		moveModel(summon, summonBody, home * SUMMON_SOCKET - lowered)
	else
		-- Standing on the floor in its spot.
		local floor = home.Position - Vector3.new(0, BLOCK_SIZE.Y / 2, 0)
		moveModel(summon, summonBody, home.Rotation + floor + Vector3.new(0, height / 2, 0) - lowered)
		nameplate.StudsOffset = Vector3.new(0, height - BLOCK_SIZE.Y / 2 + 1.8, 0)
	end
	summonRoot.Anchored = true

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
		summonRoot = summonRoot,
		summonHome = summonRoot.CFrame,
		summonBlock = summonBlock,
		art = art,
		clips = nil,
		character = nil,
		characterRoot = nil,
		characterHome = nil,
		highlight = highlight,
		hpLabel = hpLabel,
		appearances = 0,
		knockedOut = participant.status == "KnockedOut", -- already down before this client was watching
	}

	-- A player's party member is their character on the field. Its summon stays off the field until
	-- it's used, then appears at its socket behind the character (see bringOutSummon).
	local shown: Instance = summon
	if participant.side == "Party" then
		local character = copyAvatar(participant.ownerUserId) or buildStandIn(color)
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
		character.Name = "Character"
		local floor = home.Position - Vector3.new(0, BLOCK_SIZE.Y / 2, 0)
		local characterHome = home.Rotation + floor + Vector3.new(0, rootHeight(character, root), 0)
		moveModel(character, root, characterHome)
		root.Anchored = true
		figure.character = character
		figure.characterRoot = root
		figure.characterHome = characterHome
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
	return figure.summonRoot, figure.summonHome
end

-- Moves a part a little way from where it stands and straight back: a lunge or a recoil.
local function nudge(part: BasePart, rest: CFrame, offset: Vector3, seconds: number, delaySeconds: number)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true, delaySeconds)
	part.CFrame = rest
	TweenService:Create(part, info, { CFrame = rest + offset }):Play()
end

-- How far a hit rocks a player's character back, at its waist and at its neck.
local FLINCH_WAIST = math.rad(16)
local FLINCH_NECK = math.rad(14)
local FLINCH_SECONDS = 0.12 -- each way
local restPose: { [Instance]: CFrame } = setmetatable({} :: any, { __mode = "k" })

-- A player's character flinching from a hit: it rocks back at the waist and the neck, away from the
-- blow, and springs back. It's done through the avatar's own joints, so it works on any avatar with
-- no uploaded animation: current avatars' AnimationConstraints (Waist, Neck; posed through their
-- Transform) or older rigs' Motor6Ds (R15's Waist and Neck, R6's RootJoint and Neck; posed through
-- C0). The blocky stand-in has no joints; it just recoils.
local function flinch(character: Model, root: BasePart, delaySeconds: number)
	local info = TweenInfo.new(FLINCH_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true, delaySeconds)
	local right = root.CFrame.RightVector -- tilting around it leans the character back
	for _, joint in character:GetDescendants() do
		local angle = if joint.Name == "Waist" or joint.Name == "RootJoint"
			then FLINCH_WAIST
			elseif joint.Name == "Neck" then FLINCH_NECK
			else nil
		if angle == nil then
			continue
		end
		if joint:IsA("AnimationConstraint") then
			local attachment = joint.Attachment0
			if attachment then
				local rest = restPose[joint] or joint.Transform
				restPose[joint] = rest -- so a flinch that lands mid-flinch still springs back to rest
				local axis = attachment.WorldCFrame:VectorToObjectSpace(right)
				joint.Transform = rest
				TweenService:Create(joint, info, { Transform = rest * CFrame.fromAxisAngle(axis, angle) }):Play()
			end
		elseif joint:IsA("Motor6D") then
			local part0 = joint.Part0
			if part0 then
				local rest = restPose[joint] or joint.C0
				restPose[joint] = rest
				local axis = (part0.CFrame * rest):VectorToObjectSpace(right)
				joint.C0 = rest
				TweenService:Create(joint, info, { C0 = rest * CFrame.fromAxisAngle(axis, angle) }):Play()
			end
		end
	end
end

-- A party member's summon materializes at its socket behind the character, idling, for one beat:
--   "cast"    one of its own abilities that isn't an attack (a heal, a buff)
--   "attack"  one of its own attacks: its attack clip plays as it materializes
--   "death"   it's been knocked out: its death clip plays
-- then dismisses once that has played out. The character stays on the field throughout. Returns
-- how long after it starts coming out the beat lands (for an attack, the blow).
type Beat = "cast" | "attack" | "death"
local function bringOutSummon(figure: Figure, beat: Beat): number
	figure.appearances += 1
	local appearance = figure.appearances
	local summon = figure.summon
	figure.summonRoot.CFrame = figure.summonHome
	fadeModel(summon, 1, 0)
	summon.Parent = figure.folder
	fadeModel(summon, 0, SUMMON_FADE_SECONDS)
	loadClips(figure)
	stopClips(figure)
	startIdle(figure)

	local lands = SUMMON_FADE_SECONDS
	local outFor = SUMMON_SECONDS -- a clip whose length is known keeps it out until that's over
	if beat == "attack" then
		local seconds, impact = playAttackClip(figure)
		if seconds and impact then
			lands = math.max(SUMMON_FADE_SECONDS, impact)
			outFor = math.max(SUMMON_SECONDS, seconds + SUMMON_FADE_SECONDS)
		end
	elseif beat == "death" then
		local seconds = playDeathClip(figure)
		if seconds then
			outFor = math.max(SUMMON_SECONDS, seconds + SUMMON_FADE_SECONDS)
		end
	end

	task.delay(outFor - SUMMON_FADE_SECONDS, function()
		if figure.appearances == appearance then
			fadeModel(summon, 1, SUMMON_FADE_SECONDS)
		end
	end)
	task.delay(outFor, function()
		if figure.appearances == appearance then
			summon.Parent = nil
			stopClips(figure)
		end
	end)
	return lands
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

function BattleView.new(options: Options?): BattleView
	local fields: ViewFields = {
		folder = nil,
		figures = {},
		battle = nil,
		lastActionSeen = 0,
		targetId = nil,
		targetFriendly = false,
		cameraActive = false,
		enemyNameplates = if options and options.enemyNameplates ~= nil then options.enemyNameplates :: boolean else true,
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
		self.figures[participant.id] = createFigure(participant, folder, self.enemyNameplates)
	end
	folder.Parent = Workspace
	self.folder = folder
	-- Animations only load once a model is in the DataModel. An enemy's creature is on the field
	-- from the start; a party member's summon comes out for a moment so its clips start downloading
	-- now, rather than the first time it's used.
	for _, figure in self.figures do
		if figure.art then
			local away = figure.summon.Parent == nil
			figure.summon.Parent = figure.folder
			loadClips(figure)
			if away then
				figure.summon.Parent = nil
			elseif figure.knockedOut then
				playDeathClip(figure)
			else
				startIdle(figure)
			end
		end
	end
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
		local tint = BattleTheme.colorFor(participant.side, participant.slot)
		if participant.status == "KnockedOut" then
			tint = BattleTheme.KnockedOut
			fade = 0.35
			figure.hpLabel.Text = "Knocked out"
			if not figure.knockedOut then
				figure.knockedOut = true
				if figure.character == nil then
					playDeathClip(figure)
				elseif figure.clips and figure.clips.death then
					bringOutSummon(figure, "death") -- it comes out to fall
				end
			end
		elseif participant.status == "Left" then
			fade = 0.75
			figure.hpLabel.Text = "Left the battle"
		else
			figure.hpLabel.Text = `HP {participant.hp}/{participant.maxHp}`
		end
		-- Only a block takes its slot's color; a real model keeps its own look.
		if figure.summonBlock then
			figure.summonBlock.Color = tint
		end
		-- A party member's summon fades itself in and out (bringOutSummon); this fades what stays
		-- on the field: a party member's character, or an enemy's creature.
		fadeModel(figure.character or figure.summon, fade, 0)

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
-- abilities (swinging its attack clip, if it has one; only a character or a block lunges at its
-- target), hits make the target recoil as the blow lands (a player's character flinches too), and
-- every target gets a popup (damage, CRIT, MISS, an ailment, healing, GUARD, or the status gained).
function BattleView._playAction(self: BattleView, battle: BattleState, action: BattleTypes.ActionRecord)
	local actor = self.figures[action.actorId]
	local ability = Abilities[action.abilityId]
	if actor == nil or ability == nil then
		return
	end

	-- Attack and Guard are the character's own moves. Anything in the summon's list brings the
	-- summon out to perform it, while the character holds its ground.
	local attacking = ability.kind == "Attack"
	local performer, performerHome = body(actor)
	local lead = 0 -- how long the move waits: for its performer to materialize, then its swing
	local summoned = false
	for _, participant in battle.participants do
		if participant.id == action.actorId and participant.side == "Party" then
			if table.find(participant.abilities, ability.id) ~= nil then
				summoned = true
				lead = bringOutSummon(actor, if attacking then "attack" else "cast")
				performer, performerHome = actor.summonRoot, actor.summonHome
			end
		end
	end
	if attacking and not summoned and actor.character == nil then
		-- An enemy's creature swings its attack clip, if it has one.
		local _, impact = playAttackClip(actor)
		lead = impact or 0
	end

	for index, result in action.results do
		local target = self.figures[result.targetId]
		if target == nil then
			continue
		end

		if ability.kind == "Attack" and target ~= actor then
			local toward = (target.home.Position - actor.home.Position).Unit
			-- A character or a block lunges at its target; a summon's real model has its swing.
			local swings = (summoned or actor.character == nil) and actor.summonBlock == nil
			if index == 1 and not swings then
				nudge(performer, performerHome, toward * 4, 0.15, lead)
			end
			if result.hit then
				local struck, struckHome = body(target)
				nudge(struck, struckHome, toward * 1.5, 0.1, lead + 0.12)
				local character, characterRoot = target.character, target.characterRoot
				if character and characterRoot then
					flinch(character, characterRoot, lead + 0.12)
				end
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
