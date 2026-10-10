--!strict
--[[
	BattleView — the 3D side of a fight: the combatants on a stage, the battle camera, and the
	presentation of every beat (the battle-start swirl and sweep, each turn's shot, the actions,
	the result). It's redrawn from server snapshots and exists only on this client: a picture of the
	BattleSession, never the real thing.

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

	How it looks (C0 report, sections 3 and 4): the camera (Presentation/BattleCamera) sits low
	over the acting party member's shoulder, teammates included, cuts to an offset frontal shot of
	an acting enemy, whip-pans to whoever's next, punches its field of view on confirm, and sways a
	little while it holds. Every beat is a sequence on Presentation/Sequencer, which owns whatever
	the beat creates and reports when the stage is busy; its length comes from Pacing, the same
	numbers the server waits for, so a turn never opens over an unfinished beat. Clip, sound and
	effect ids are never written here: they come from the data modules (Summons.art and, from C2,
	the character and sound tables).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Abilities = require(Combat:WaitForChild("Abilities"))
local BattleTypes = require(Combat:WaitForChild("BattleTypes"))
local CombatConfig = require(Combat:WaitForChild("CombatConfig"))
local Pacing = require(Combat:WaitForChild("Pacing"))
local StatusEffects = require(Combat:WaitForChild("StatusEffects"))
local Summons = require(Combat:WaitForChild("Summons"))
local BattleTheme = require(script.Parent:WaitForChild("BattleTheme"))
local Presentation = script.Parent:WaitForChild("Presentation")
local BattleCamera = require(Presentation:WaitForChild("BattleCamera"))
local CameraSpec = require(Presentation:WaitForChild("CameraSpec"))
local Sequencer = require(Presentation:WaitForChild("Sequencer"))
local Shots = require(Presentation:WaitForChild("Shots"))
local Transition = require(Presentation:WaitForChild("Transition"))
local Motion = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Core"):WaitForChild("Motion"))
local Layout = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Core"):WaitForChild("Layout"))

type BattleState = BattleTypes.BattleState
type ParticipantState = BattleTypes.ParticipantState
type ActionRecord = BattleTypes.ActionRecord

-- The stage is its own little arena out past the north edge of the overworld's baseplate, so
-- nothing out exploring wanders through the fight. The party stands on the west side facing east,
-- the enemies on the east facing west; the HUD's columns (ring left, party cards right) suit the
-- over-the-shoulder shot that follows.
local STAGE_CENTER = Vector3.new(0, 0, -700)
local STAGE_FLOOR_SIZE = Vector3.new(100, 1, 80)
local BLOCK_SIZE = Vector3.new(5, 5, 5)
-- Slot 1 stands nearer the middle, slot 2 further out and to the side; the two on a side are
-- SLOT_GAP studs apart across: from the party's shoulder, both enemies' plates (190 design pixels
-- wide) then clear each other even on a phone, where a plate is a fifth of the screen.
local SLOT_GAP = 18
local SLOT_DEPTH = 9
local SLOT_DEPTH_STEP = 5
-- A party member's summon is only out while it uses one of its own abilities: it materializes, does
-- the move and dismisses in SUMMON_SECONDS, fading in and out over SUMMON_FADE_SECONDS of that.
local SUMMON_SECONDS = 1.2
local SUMMON_FADE_SECONDS = 0.2
-- Where it materializes, relative to its spot (which faces the enemies): behind the character, up
-- over its shoulder, and a step further from the camera, so the character stays in view in front.
local SUMMON_SOCKET = CFrame.new(-1.5, 4, 4)
-- A clip plays sped up when it's longer than its beat allows, so even a slow swing or fall is over
-- before the next turn opens: the allowance comes from Pacing (what the server waits), minus the
-- fade-ins and the slack; this is the most any clip gets.
local ATTACK_MAX_SECONDS = 1.6
local DEATH_MAX_SECONDS = 1.6
-- The battle start: the swirl covers the screen, the stage is set, the swirl clears onto the sweep.
local COVER_SECONDS = 0.45
local SWEEP_SECONDS = CameraSpec.Sweep.seconds
-- A beat's sequence ends this long before the server opens the next turn, so there's slack for
-- latency; the next turn's whip-pan takes over from wherever the camera is.
local RESOLVE_SLACK = 0.3
local HIT_DELAY = 0.12 -- after the blow lands: the recoil, the flinch, the shake
-- The party faces this way on the stage (toward the enemies): the party-wide shots are built on it.
local PARTY_FACING = Vector3.xAxis
-- A creature with no swing clip (none uploaded, or still downloading) lunges instead, after this
-- long, so the shot over its shoulder is readable before the blow lands.
local LUNGE_LEAD = 0.3
local RESULT_SECONDS = CameraSpec.Victory.seconds

-- A summon's animation tracks, loaded from its art once its model is in the DataModel. Any can be
-- missing (see Summons.SummonAnimations).
type Clips = {
	idle: AnimationTrack?, -- looping, or the attack held on its first frame when there's no idle
	idleFrozen: boolean,
	attack: AnimationTrack?,
	death: AnimationTrack?,
}

-- One combatant's spot on the stage. Its folder (named after the participant) holds what's on the
-- field there, named "Character" and "Summon", plus the Spot that carries its nameplate.
type Figure = {
	id: string,
	side: BattleTypes.Side,
	ownerUserId: number?,
	folder: Folder,
	home: CFrame, -- the spot, facing the other side
	spot: Part, -- invisible, at home
	summon: Model, -- the summon (for an enemy, its creature): its real model, or a colored block
	summonRoot: BasePart, -- the summon's anchored root; everything else hangs off it by its joints
	summonHome: CFrame, -- where that root stands: on the spot for an enemy, a party member's socket
	summonBlock: Part?, -- the colored block, when there's no real model
	height: number, -- how tall the summon stands
	art: Summons.SummonArt?, -- the real model's animations, when it has one
	clips: Clips?, -- loaded once the model has been on the stage
	character: Model?, -- party members: the player's character, always on the field
	characterRoot: BasePart?,
	characterHome: CFrame?, -- where the character's root stands
	highlight: Highlight,
	hpLabel: TextLabel,
	appearances: number, -- bumped each time the summon comes out, so only the latest one dismisses it
	knockedOut: boolean, -- so its fall only plays once, when it happens
	fall: "None" | "Pending" | "Cued", -- a knockout seen but not yet played: it waits for the blow that caused it
}

local BattleView = {}
BattleView.__index = BattleView

type ViewFields = {
	folder: Folder?,
	figures: { [string]: Figure },
	battle: BattleState?,
	lastActionSeen: number,
	turnSeen: number,
	resultShown: boolean,
	targetId: string?,
	targetFriendly: boolean,
	framing: Framing, -- what the HUD is showing on the player's own turn (setFraming)
	framingTargetId: string?,
	framingLocked: boolean, -- a move was confirmed: the HUD's framing no longer steers the camera this turn
	framingPending: boolean, -- asked for while a beat was playing: applied once the stage is free
	framingShown: Framing, -- what the camera last framed (a truck is from one enemy shot to another)
	enemyNameplates: boolean, -- off when the new HUD draws its own enemy plates (M0 report R19)
	partyNameplates: boolean, -- off for the new HUD too: its party cards carry the same
	localUserId: number?,
	playerGui: PlayerGui?,
	camera: BattleCamera.BattleCamera,
	sequencer: Sequencer.Sequencer,
	transition: Transition.Transition?,
}

-- What the HUD is showing while the player picks a move: the command ring, the skill list, or a
-- target (one enemy, one ally, or every enemy).
export type Framing = "Command" | "Menu" | "TargetEnemy" | "TargetAlly" | "TargetSquad"

export type Options = {
	enemyNameplates: boolean?, -- default true
	partyNameplates: boolean?, -- default true
	onBusyChanged: ((busy: boolean) -> ())?, -- the stage started or finished playing a beat
	playerGui: PlayerGui?, -- where the battle-start transition draws; found from the LocalPlayer otherwise
}

export type BattleView = typeof(setmetatable({} :: ViewFields, BattleView))

-- Slot 2 stands further out and nearer the camera so the two on a side don't overlap.
local function slotCFrame(side: string, slot: number): CFrame
	local direction = if side == "Party" then -1 else 1
	local position = STAGE_CENTER
		+ Vector3.new(direction * (SLOT_DEPTH + (slot - 1) * SLOT_DEPTH_STEP), BLOCK_SIZE.Y / 2, (slot - 1.5) * SLOT_GAP)
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
		if descendant:IsA("BaseScript") or descendant:IsA("ForceField") or descendant:IsA("LayerCollector") then
			-- No Animate or Health scripts (this copy only poses and lunges), no spawn shield, which
			-- would never wear off the copy, and no GUIs riding on the avatar (the overworld's
			-- "AFK" tag), which would float over the stage.
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

-- Plays the summon's attack clip, if it has one, within `maxSeconds` (sped up if it's longer).
-- Returns how long it takes and how far in the blow lands, in seconds, and a track to stop at
-- `maxSeconds` when the clip's length isn't known yet (it's still downloading, the first time): it
-- plays at its own pace until then, and never outlives the beat.
local function playAttackClip(figure: Figure, maxSeconds: number): (number?, number?, AnimationTrack?)
	local track = if figure.clips then figure.clips.attack else nil
	if track == nil then
		return nil, nil, nil
	end
	if track.Length <= 0 then
		track:Play(0.1)
		return nil, nil, track
	end
	local speed = math.max(1, track.Length / math.clamp(maxSeconds, 0.3, ATTACK_MAX_SECONDS))
	track:Play(0.1, 1, speed)
	local seconds = track.Length / speed
	local art = figure.art
	return seconds, seconds * (if art and art.attackImpact then art.attackImpact else 0.5), nil
end

-- Stops a clip that was still downloading when it started, so it never plays past its beat; a
-- death clip is frozen where it got to instead, since the figure stays down.
local function endUntimedClip(track: AnimationTrack, freeze: boolean)
	if not track.IsPlaying then
		return
	end
	if freeze then
		track:AdjustSpeed(0)
	else
		track:Stop(0.1)
	end
end

-- Plays the summon's death clip, if it has one, within `maxSeconds` (the time left in the beat,
-- at most DEATH_MAX_SECONDS), and holds its last frame. The connection that freezes it is owned by
-- `sequencer`, so leaving a fight drops it. Returns how long it takes (nil when that isn't known
-- yet) and, then, the track to freeze at `maxSeconds`.
local function playDeathClip(figure: Figure, sequencer: Sequencer.Sequencer, maxSeconds: number): (number?, AnimationTrack?)
	local clips = figure.clips
	local death = if clips then clips.death else nil
	if clips == nil or death == nil then
		return nil, nil
	end
	if clips.idle then
		clips.idle:Stop(0.2)
	end
	local allowed = math.clamp(maxSeconds, 0.3, DEATH_MAX_SECONDS)
	local speed = if death.Length > 0 then math.max(1, death.Length / allowed) else 1
	death:Play(0.1, 1, speed)
	local connection: RBXScriptConnection
	connection = death.Stopped:Connect(function()
		connection:Disconnect()
		sequencer:releaseConnection(connection)
		if figure.knockedOut then
			death:Play(0, 1, 0) -- frozen where it fell
			death.TimePosition = math.max(0, death.Length - 0.05)
		end
	end)
	sequencer:ownConnection(connection)
	if death.Length > 0 then
		return death.Length / speed, nil
	end
	return nil, death
end

--[[ Figures ]]

local function createFigure(participant: ParticipantState, parent: Instance, enemyNameplates: boolean, partyNameplates: boolean): Figure
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
	-- The new HUD draws its own enemy plates and party cards, so it turns these off.
	nameplate.Enabled = if participant.side == "Enemy" then enemyNameplates else partyNameplates
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
		id = participant.id,
		side = participant.side,
		ownerUserId = participant.ownerUserId,
		folder = folder,
		home = home,
		spot = spot,
		summon = summon,
		summonRoot = summonRoot,
		summonHome = summonRoot.CFrame,
		summonBlock = summonBlock,
		height = height,
		art = art,
		clips = nil,
		character = nil,
		characterRoot = nil,
		characterHome = nil,
		highlight = highlight,
		hpLabel = hpLabel,
		appearances = 0,
		knockedOut = participant.status == "KnockedOut", -- already down before this client was watching
		fall = "None",
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

-- How tall what stands in the spot is: a character is about five studs, a creature its height.
local function bodyHeight(figure: Figure): number
	return if figure.character then 5 else figure.height
end

-- Where a figure's body is, at its middle, facing the way its spot faces (an imported rig's root
-- may be turned any way and sit at its feet; the spot is what the stage laid out, and a creature's
-- middle is half its height above the floor). A party character's root is its hips, which serves.
local function standing(figure: Figure): CFrame
	local _, rest = body(figure)
	if figure.character then
		return figure.home.Rotation + rest.Position
	end
	local floor = figure.home.Position.Y - BLOCK_SIZE.Y / 2
	return figure.home.Rotation + Vector3.new(rest.Position.X, floor + figure.height / 2, rest.Position.Z)
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
-- then dismisses once that has played out. The character stays on the field throughout. `clipSeconds`
-- is the most its clip may take and `budget` the most the whole appearance may take, fade-out
-- included (both from the beat's Pacing budget). Returns how long after it starts coming out the
-- beat lands (for an attack, the blow), and a track to end at `clipSeconds` when its length wasn't
-- known yet.
type Beat = "cast" | "attack" | "death"
local function bringOutSummon(figure: Figure, beat: Beat, clipSeconds: number, budget: number, sequencer: Sequencer.Sequencer): (number, AnimationTrack?)
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
	local untimed: AnimationTrack? = nil
	if beat == "attack" then
		local seconds, impact, track = playAttackClip(figure, clipSeconds)
		untimed = track
		if seconds and impact then
			lands = math.max(SUMMON_FADE_SECONDS, impact)
			outFor = math.max(SUMMON_SECONDS, seconds + SUMMON_FADE_SECONDS)
		end
	elseif beat == "death" then
		local seconds, track = playDeathClip(figure, sequencer, clipSeconds)
		untimed = track
		if seconds then
			outFor = math.max(SUMMON_SECONDS, seconds + SUMMON_FADE_SECONDS)
		end
	end
	-- Never out longer than the beat allows: the fade-out ends inside the budget.
	outFor = math.max(SUMMON_FADE_SECONDS * 2, math.min(outFor, budget))

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
	return lands, untimed
end

-- A word or number that floats up off whoever stands in a spot and fades: damage, MISS, healing,
-- a status. It follows the body (which lunges and recoils), not the spot, and the sequencer owns
-- it: gone after a second, or at once if the fight is left.
local POPUP_SECONDS = 1.6 -- long enough to be read through an enemy beat's hold
local POPUP_RISE_SECONDS = 1.4
-- How far a popup drifts up as it fades. Kept small: in the close reaction shot every stud is
-- about a tenth of the screen, and a number that rose further passed under the status block
-- during the hold (the playtest), on a phone within half a second.
local POPUP_RISE_STUDS = 1
local POPUP_CREATURE_HEIGHT = 0.35 -- where on a creature's body a popup starts, from its feet
local AILMENT_POPUP_HEIGHT = -0.8 -- an ailment's name, just under the number (above it, it reached the status block on a phone)
BattleView.POPUP_RISE_STUDS = POPUP_RISE_STUDS -- (for the tests)
BattleView.AILMENT_POPUP_HEIGHT = AILMENT_POPUP_HEIGHT
local function showPopup(sequencer: Sequencer.Sequencer, figure: Figure, text: string, color: Color3, startHeight: number)
	local part, rest = body(figure)
	-- From a creature's chest, a third of the way up its body (an imported rig's root sits at its
	-- feet): its middle put the number under the phone's status block from over the party's shoulder.
	local lift = if figure.character then 0 else math.max(0, (figure.home.Position.Y - BLOCK_SIZE.Y / 2 + figure.height * POPUP_CREATURE_HEIGHT) - rest.Position.Y)
	local popup = Instance.new("BillboardGui")
	popup.Name = "Popup"
	popup.Adornee = part
	popup.Size = UDim2.fromOffset(160, 40)
	popup.StudsOffset = Vector3.new(0, startHeight + lift, 0)
	popup.AlwaysOnTop = true
	popup.LightInfluence = 0
	local label = newBillboardLabel(popup, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), BattleTheme.FontHeavy)
	label.Text = text
	label.TextColor3 = color
	popup.Parent = figure.spot

	local rise = TweenInfo.new(POPUP_RISE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(popup, rise, { StudsOffset = Vector3.new(0, startHeight + lift + POPUP_RISE_STUDS, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(POPUP_RISE_SECONDS * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, POPUP_RISE_SECONDS * 0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	sequencer:own(popup, POPUP_SECONDS)
end

-- Tells the world's other client scripts (ZoneClient's day cycle) that a fight is on, so they
-- hold still for it. Set once the wipe has covered the screen, cleared on leaving.
local function setInBattle(on: boolean)
	local player = Players.LocalPlayer
	if player then
		player:SetAttribute("InBattle", on)
	end
end

--[[ BattleView ]]

function BattleView.new(options: Options?): BattleView
	local sequencer = Sequencer.new(if options then options.onBusyChanged else nil)
	local localPlayer = Players.LocalPlayer
	local fields: ViewFields = {
		folder = nil,
		figures = {},
		battle = nil,
		lastActionSeen = 0,
		turnSeen = 0,
		resultShown = false,
		targetId = nil,
		targetFriendly = false,
		framing = "Command",
		framingTargetId = nil,
		framingLocked = false,
		framingPending = false,
		framingShown = "Command",
		enemyNameplates = if options and options.enemyNameplates ~= nil then options.enemyNameplates :: boolean else true,
		partyNameplates = if options and options.partyNameplates ~= nil then options.partyNameplates :: boolean else true,
		localUserId = if localPlayer then localPlayer.UserId else nil,
		playerGui = if options then options.playerGui else nil,
		camera = BattleCamera.new(),
		sequencer = sequencer,
		transition = nil,
	}
	return setmetatable(fields, BattleView)
end

-- Draws the latest battle state (nil = no battle running). Returns how long until the blow of a
-- newly shown action lands (0 when nothing is landing), so the HUD can show the outcome then.
function BattleView.render(self: BattleView, battle: BattleState?): number
	local previous = self.battle
	self.battle = battle
	if battle == nil then
		if previous ~= nil or self.folder ~= nil then
			self:_leave()
		end
		return 0
	end

	local fresh = previous == nil or previous.battleId ~= battle.battleId or self.folder == nil
	if fresh then
		self:_build(battle)
	end
	self:_refreshFigures()

	if battle.turnNumber ~= self.turnSeen and battle.currentActorId ~= nil then
		self.turnSeen = battle.turnNumber
		self.framing = "Command"
		self.framingTargetId = nil
		self.framingLocked = false
		self.framingPending = false
		self.framingShown = "Command"
		self.camera:setFocusBlur(false)
		self:_openTurn(battle)
	end
	local action = battle.lastAction
	local actionSeconds, impactIn = 0, 0
	if action ~= nil and action.sequence > self.lastActionSeen then
		self.lastActionSeen = action.sequence
		actionSeconds, impactIn = self:_playAction(battle, action)
	end
	for _, figure in self.figures do
		if figure.fall == "Pending" then
			-- Knocked out with no blow to wait for (joined late, or the action wasn't seen).
			self:_fall(figure, DEATH_MAX_SECONDS, self.sequencer:elapsed())
		end
	end
	if battle.phase == "reward" and not self.resultShown then
		self.resultShown = true
		-- The final blow and the result arrive in one snapshot: the result camera waits for the
		-- blow (and the fall) to play out, as a cue at the end of the action's sequence.
		if actionSeconds > 0 then
			self.sequencer:addCue(actionSeconds, function()
				self:_playResult(battle)
			end)
		else
			self:_playResult(battle)
		end
	end
	return impactIn
end

-- A knocked-out figure falls: an enemy's creature plays its death clip where it stands; a party
-- member's summon comes out to fall (if it has a death clip). `remaining` is the time left in the
-- beat for the fall, dismissal included; `at` is where in the sequence the fall starts, so a clip
-- whose length isn't known can be frozen when the beat ends.
-- `cues` is the list of the beat about to be played, when the fall belongs to one that hasn't
-- started yet (its freeze cue then goes there rather than onto the live sequence).
function BattleView._fall(self: BattleView, figure: Figure, remaining: number, at: number, cues: { Sequencer.Cue }?)
	if figure.fall == "None" then
		return
	end
	figure.fall = "None"
	-- The knocked-out look: faded, and a block goes grey. (A party member's summon fades itself
	-- in and out when it comes out to fall; this is what stays on the field.)
	if figure.summonBlock then
		figure.summonBlock.Color = BattleTheme.KnockedOut
	end
	fadeModel(figure.character or figure.summon, 0.35, 0)
	local sequencer = self.sequencer
	local budget = math.max(0.3, remaining)
	local untimed: AnimationTrack? = nil
	if figure.character == nil then
		local _, track = playDeathClip(figure, sequencer, budget)
		untimed = track
	elseif figure.clips and figure.clips.death then
		local _, track = bringOutSummon(figure, "death", budget - SUMMON_FADE_SECONDS * 2, budget, sequencer)
		untimed = track
	end
	if untimed then
		local track = untimed
		local function freeze()
			endUntimedClip(track, true)
		end
		if cues then
			table.insert(cues, { at = at + budget - SUMMON_FADE_SECONDS, run = freeze })
		else
			sequencer:addCue(at + budget - SUMMON_FADE_SECONDS, freeze)
		end
	end
end

-- Who acts next, from the turn queue and who's still standing (nil when the fight is over), the
-- way BattleSession walks it: during the opening bonus turn (round 0) the rest of the side that
-- struck first, in queue order, then round 1 from the top of the queue; otherwise the next in the
-- queue, wrapping. The camera can head there before the server opens the turn.
function BattleView.nextActorId(battle: BattleState): string?
	if battle.phase == "reward" then
		return nil
	end
	local queue = battle.turnQueue
	local current = battle.currentActorId
	local index = if current then table.find(queue, current) else nil
	if index == nil or #queue == 0 then
		return nil
	end
	local standing: { [string]: boolean } = {}
	local side: { [string]: BattleTypes.Side } = {}
	for _, participant in battle.participants do
		standing[participant.id] = participant.status == "Active"
		side[participant.id] = participant.side
	end
	if battle.round == 0 and battle.opening ~= nil then
		for later = index + 1, #queue do
			local candidate = queue[later]
			if standing[candidate] and side[candidate] == battle.opening then
				return candidate
			end
		end
		for _, candidate in queue do
			if standing[candidate] then
				return candidate
			end
		end
		return nil
	end
	for step = 1, #queue do
		local candidate = queue[(index + step - 1) % #queue + 1]
		if standing[candidate] then
			return candidate
		end
	end
	return nil
end
local nextActorId = BattleView.nextActorId

-- The server refused the move (or the turn moved on): back to the turn's own shot.
function BattleView.refocus(self: BattleView)
	local battle = self.battle
	self.framingLocked = false
	if battle and battle.currentActorId then
		self:_openTurn(battle)
	end
end

-- Runs the presentation: call every frame with the time since the last one.
function BattleView.update(self: BattleView, dt: number)
	self.camera:setMotionScale(Motion.scale())
	self.sequencer:update(dt)
	if self.framingPending and not self.sequencer:isBusy() then
		-- The HUD changed what the player looks at while a beat was still playing: frame it now.
		self.framingPending = false
		self:setFraming(self.framing, self.framingTargetId)
	end
	self.camera:update(dt)
end

-- The player confirmed a move: the field of view punches at once, before the server answers, and
-- if the move brings their summon out the camera already backs off to the summon shot, so the
-- summon never materializes between the lens and the character.
function BattleView.confirm(self: BattleView, abilityId: string?, targetId: string?)
	local battle = self.battle
	if battle == nil then
		return
	end
	self.camera:punch(CameraSpec.Kicks.confirmPunch)
	self.framingLocked = true
	self.framingPending = false
	self.camera:setFocusBlur(false)
	local actorId = battle.currentActorId
	local figure = if actorId then self.figures[actorId] else nil
	local ability = if abilityId then Abilities[abilityId] else nil
	if figure == nil or abilityId == nil or ability == nil then
		return
	end
	if ability.kind == "Attack" then
		-- Back from the target shot to the hero's shoulder at once, so the swing that follows (the
		-- character's own, or its summon's from the summon shot below) is seen from the hero's side.
		local home = self:_shotFor(actorId)
		if not self.camera:isHeadingTo(home) then
			self.camera:moveTo(home, CameraSpec.Transition.maxSweepSeconds)
		end
	end
	for _, participant in battle.participants do
		if participant.id == actorId and Pacing.isSummoned(participant.side, participant.abilities, abilityId) then
			if ability.kind == "Attack" then
				self.camera:moveTo(Shots.summon(standing(figure), self:_focus("Enemy")), CameraSpec.Transition.maxSweepSeconds)
			else
				-- A heal or buff opens on its own shot (the beat picks up from there: see _playAction).
				local recipientId = if ability.targets == "Self" then figure.id else targetId
				self.camera:moveTo(self:_castOpening(figure, ability.targets == "AllAllies", recipientId), CameraSpec.Transition.maxSweepSeconds)
			end
		end
	end
end

-- The shot a heal or buff opens on: a frontal medium shot of the caster's character, or for the
-- whole party the high-angle overhead. On the caster itself it opens on the recipient's shot (the
-- invocation and the effect share one frame, so there's no jump cut between two near-identical
-- shots).
function BattleView._castOpening(self: BattleView, caster: Figure, partyWide: boolean, recipientId: string?): Shots.Pose
	if partyWide then
		return Shots.partyOverhead(self:_focus("Party"), PARTY_FACING)
	elseif recipientId == caster.id then
		return Shots.allyChestUp(standing(caster))
	end
	return Shots.casterFrontal(standing(caster), bodyHeight(caster))
end

-- The HUD changed what the player is looking at on their own turn (the ring, the skill list, a
-- target): the camera frames it (CAMERA_SPEC sections 3 and 4). Only while the stage is idle and
-- no move has been confirmed; a new turn resets it.
function BattleView.setFraming(self: BattleView, framing: Framing, targetId: string?)
	local previous = self.framingShown
	self.framing = framing
	self.framingTargetId = targetId
	local battle = self.battle
	if battle == nil or battle.phase ~= "input" or self.framingLocked then
		return
	elseif self.sequencer:isBusy() then
		self.framingPending = true
		return
	end
	local actorId = battle.currentActorId
	local actor = if actorId then self.figures[actorId] else nil
	if actor == nil or actor.side ~= "Party" or actor.ownerUserId == nil or actor.ownerUserId ~= self.localUserId then
		return
	end
	local camera = self.camera
	local transition = CameraSpec.Transition
	local idle = self:_shotFor(actorId)
	self.framingShown = framing
	if framing == "Menu" then
		camera:moveTo(Shots.menuPush(idle), transition.maxSweepSeconds)
		camera:setFocusBlur(true, standing(actor).Position + Vector3.new(0, CameraSpec.Idle.focusUp, 0))
		return
	end
	camera:setFocusBlur(false)
	local target = if targetId then self.figures[targetId] else nil
	if framing == "TargetEnemy" and target then
		local others: { string } = {}
		for _, participant in battle.participants do
			if participant.side == "Enemy" and participant.id ~= target.id and participant.status == "Active" then
				table.insert(others, participant.id)
			end
		end
		local othersAt = if #others > 0 then self:_focusOf(others, standing(target).Position) else nil
		local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize
		local compact = viewport ~= nil and Layout.deviceClass(viewport) == "Phone"
		local shot = Shots.targetEnemy(standing(target), bodyHeight(target), standing(actor).Position, othersAt, compact)
		-- A truck between enemies stays a sweep, whatever it turns.
		local trucking = previous == "TargetEnemy"
		camera:moveTo(shot, if trucking then CameraSpec.TargetSingle.truckSeconds else transition.maxSweepSeconds, trucking)
		return
	elseif framing == "TargetAlly" and target then
		camera:moveTo(Shots.allyChestUp(standing(target)), transition.maxSweepSeconds)
		return
	elseif framing == "TargetSquad" then
		camera:moveTo(Shots.targetSquad(standing(actor), self:_focus("Enemy")), transition.maxSweepSeconds)
		return
	end
	if not camera:isHeadingTo(idle) then
		camera:moveTo(idle, transition.whipSeconds)
	end
end

-- Whether a beat is still playing on the stage (the HUD holds the ring until it isn't).
function BattleView.isBusy(self: BattleView): boolean
	return self.sequencer:isBusy()
end

-- How many things the presentation is holding (for the tests: none after a fight).
function BattleView.ownedCount(self: BattleView): number
	local transition = self.transition
	return self.sequencer:ownedCount() + (if transition and transition:isShowing() then 1 else 0)
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
	self.sequencer:cancel()
	local folder = Instance.new("Folder")
	folder.Name = "BattleStage"
	local floor = stagePart("Floor", STAGE_FLOOR_SIZE)
	floor.CFrame = CFrame.new(STAGE_CENTER - Vector3.new(0, STAGE_FLOOR_SIZE.Y / 2, 0))
	floor.Material = Enum.Material.Grass
	floor.Color = Color3.fromRGB(92, 115, 77)
	floor.Parent = folder
	for _, participant in battle.participants do
		self.figures[participant.id] = createFigure(participant, folder, self.enemyNameplates, self.partyNameplates)
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
				playDeathClip(figure, self.sequencer, DEATH_MAX_SECONDS)
				fadeModel(figure.summon, 0.35, 0)
			else
				startIdle(figure)
			end
		end
	end
	-- Don't replay an action that happened before this client started watching.
	self.lastActionSeen = if battle.lastAction then battle.lastAction.sequence else 0
	self.turnSeen = 0
	self.resultShown = false

	self.camera:activate()
	if battle.phase == "setup" then
		self:_playStart()
	else
		-- Joining a fight already under way: straight to its current shot.
		self.camera:cut(self:_shotFor(battle.currentActorId))
		setInBattle(true)
	end
end

-- Back to the overworld: nothing of the fight stays behind.
function BattleView._leave(self: BattleView)
	setInBattle(false)
	self.sequencer:cancel()
	local transition = self.transition
	if transition then
		transition:destroy()
	end
	self:_clear()
	self.camera:deactivate()
	self.turnSeen = 0
	self.resultShown = false
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

		if participant.status == "KnockedOut" then
			figure.hpLabel.Text = "Knocked out"
			if not figure.knockedOut then
				-- Its knocked-out look (the fade, a block's grey) comes with its fall, when the blow
				-- lands (_playAction), or at once if nothing is coming.
				figure.knockedOut = true
				figure.fall = "Pending"
			end
		elseif participant.status == "Left" then
			figure.hpLabel.Text = "Left the battle"
			fadeModel(figure.character or figure.summon, 0.75, 0)
		else
			figure.hpLabel.Text = `HP {participant.hp}/{participant.maxHp}`
			if figure.summonBlock then
				figure.summonBlock.Color = BattleTheme.colorFor(participant.side, participant.slot)
			end
			if not figure.knockedOut then
				fadeModel(figure.character or figure.summon, 0, 0)
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

--[[ Camera shots ]]

-- The middle of the standing figures on a side (their bodies' centers), to aim at.
function BattleView._focus(self: BattleView, side: BattleTypes.Side): Vector3
	local points = {}
	local battle = self.battle
	for _, figure in self.figures do
		if figure.side == side then
			local standing = true
			if battle then
				for _, participant in battle.participants do
					if participant.id == figure.id then
						standing = participant.status == "Active"
					end
				end
			end
			if standing then
				local _, rest = body(figure)
				table.insert(points, rest.Position + Vector3.new(0, bodyHeight(figure) * 0.3, 0))
			end
		end
	end
	local direction = if side == "Party" then -1 else 1
	return Shots.focusOf(points, STAGE_CENTER + Vector3.new(direction * SLOT_DEPTH, 3, 0))
end

-- The middle of these figures' bodies, or `fallback` when none of them is on the stage.
function BattleView._focusOf(self: BattleView, ids: { string }, fallback: Vector3): Vector3
	local points = {}
	for _, id in ids do
		local figure = self.figures[id]
		if figure then
			local _, rest = body(figure)
			table.insert(points, rest.Position + Vector3.new(0, bodyHeight(figure) * 0.3, 0))
		end
	end
	return Shots.focusOf(points, fallback)
end

-- The shot for whoever's turn it is: over a party member's shoulder (a teammate's from a little
-- further back), an offset frontal on an enemy; the wide shot when there is no one.
function BattleView._shotFor(self: BattleView, actorId: string?): Shots.Pose
	local figure = if actorId then self.figures[actorId] else nil
	if figure == nil then
		return Shots.wide(STAGE_CENTER)
	end
	local rest = standing(figure)
	if figure.side == "Party" then
		local mine = figure.ownerUserId ~= nil and figure.ownerUserId == self.localUserId
		return Shots.overShoulder(rest, self:_focus("Enemy"), if mine then 1 else CameraSpec.Idle.teammatePull)
	end
	return Shots.enemyFrontal(rest, bodyHeight(figure))
end

-- A turn opened: whip-pan to a party member about to act; a short ease over to an enemy's wind-up
-- shot (its beat ends with the camera already heading to whoever's next, so this is usually a
-- no-op then).
function BattleView._openTurn(self: BattleView, battle: BattleState)
	local actorId = battle.currentActorId
	local shot = self:_shotFor(actorId)
	if self.camera:isHeadingTo(shot) then
		return
	end
	local figure = if actorId then self.figures[actorId] else nil
	local enemy = figure ~= nil and figure.side == "Enemy"
	self.camera:moveTo(shot, if enemy then CameraSpec.Transition.enemyTurnSeconds else CameraSpec.Transition.whipSeconds)
end

--[[ Beats ]]

-- The battle start: the swirl covers the screen, then clears onto the sweep across both sides,
-- which ends behind the party just as the initiative reveal gives way to the first turn.
function BattleView._playStart(self: BattleView)
	local transition = self.transition
	if transition == nil then
		local playerGui = self.playerGui
		if playerGui == nil then
			local localPlayer = Players.LocalPlayer
			local found = if localPlayer then localPlayer:FindFirstChild("PlayerGui") else nil
			playerGui = if found and found:IsA("PlayerGui") then found else nil
		end
		if playerGui then
			transition = Transition.new(playerGui)
			self.transition = transition
		end
	end
	local scale = Motion.scale()
	local sweep = function(t: number): Shots.Pose
		return Shots.sweep(STAGE_CENTER, Vector3.xAxis, t / SWEEP_SECONDS)
	end
	-- The camera keeps the player's view (activate) until the wipe has covered the screen; the
	-- stage is only seen once the wipe clears onto the sweep.
	if transition then
		transition:coverScreen(COVER_SECONDS, scale)
	end
	self.sequencer:play(COVER_SECONDS + SWEEP_SECONDS, {
		{
			at = COVER_SECONDS,
			run = function()
				setInBattle(true) -- under the cover: the world's light changes unseen
				self.camera:follow(sweep, SWEEP_SECONDS)
				if transition then
					transition:uncoverScreen(COVER_SECONDS, Motion.scale())
				end
			end,
		},
	})
end

-- Plays what an action did: a party member's summon comes out if it's one of the summon's own
-- abilities (swinging its attack clip, if it has one; only a character or a block lunges at its
-- target), hits make the target recoil as the blow lands (a player's character flinches too), and
-- every target gets a popup (damage, CRIT, MISS, an ailment, healing, GUARD, or the status gained).
-- The camera: it holds over a party member's shoulder (pulling back for its summon, framing a heal
-- or buff's caster and recipient) and shakes as a blow lands; for an enemy's attack it cuts over
-- the targeted hero's shoulder, then to the hero as the blow lands, holds, and comes back.
-- Returns how long the beat plays (the sequence's length), so what follows can wait for it, and
-- how long until its outcome shows (the blow landing; the cast taking effect).
function BattleView._playAction(self: BattleView, battle: BattleState, action: ActionRecord): (number, number)
	local actor = self.figures[action.actorId]
	local ability = Abilities[action.abilityId]
	if actor == nil or ability == nil then
		return 0, 0
	end

	-- Attack and Guard are the character's own moves. Anything in the summon's list brings the
	-- summon out to perform it, while the character holds its ground.
	local attacking = ability.kind == "Attack"
	local summoned = false
	for _, participant in battle.participants do
		if participant.id == action.actorId and Pacing.isSummoned(participant.side, participant.abilities, ability.id) then
			summoned = true
		end
	end
	local cues: { Sequencer.Cue } = {}
	-- The previous beat's sequence is about to be replaced: a fall it still had cued lands now, so
	-- a knocked-out figure never stays standing because the next snapshot came in early.
	for _, figure in self.figures do
		if figure.fall == "Cued" then
			self:_fall(figure, DEATH_MAX_SECONDS, 0, cues)
		end
	end

	-- The beat's budget: what the server waits before the next turn, less slack for latency. Clips
	-- are compressed to fit inside it; an enemy's beat also holds on the outcome and eases back.
	local enemyActor = actor.side == "Enemy"
	local seconds = Pacing.resolveSeconds(ability, action.results, summoned, actor.side)
	local duration = math.max(0, seconds - RESOLVE_SLACK)
	local holdAndReturn = if enemyActor then CombatConfig.EnemyHoldSeconds + CombatConfig.EnemyReturnSeconds else 0
	local clipSeconds = duration - holdAndReturn - HIT_DELAY - 0.2 - (if summoned then SUMMON_FADE_SECONDS * 2 else 0)

	local performer, performerHome = body(actor)
	local lead = 0 -- how long the move waits: for its performer to materialize, then its swing
	local untimed: AnimationTrack? = nil
	local swings = false -- a real model playing a timed swing clip (otherwise it lunges)
	if summoned then
		lead, untimed = bringOutSummon(actor, if attacking then "attack" else "cast", clipSeconds, duration, self.sequencer)
		performer, performerHome = actor.summonRoot, actor.summonHome
		swings = attacking and actor.summonBlock == nil and actor.clips ~= nil and actor.clips.attack ~= nil
		if untimed then
			lead = math.max(lead, LUNGE_LEAD) -- a swing whose timing isn't known yet still gets a readable lead
		end
	elseif attacking and actor.character == nil then
		-- An enemy's creature swings its attack clip, if it has one (a clip still downloading plays
		-- too, with a readable lead); without one it lunges after that lead instead.
		local _, impact, track = playAttackClip(actor, clipSeconds)
		untimed = track
		if impact then
			lead = impact
			swings = true
		else
			lead = LUNGE_LEAD
			swings = track ~= nil
		end
	end
	if untimed then
		-- The clip's length wasn't known yet (still downloading): it plays as is and stops at the
		-- budget, so it can't outlive the beat.
		local track = untimed
		table.insert(cues, {
			at = math.max(0.1, clipSeconds),
			run = function()
				endUntimedClip(track, false)
			end,
		})
	end

	local camera = self.camera
	local sequencer = self.sequencer
	local firstHit: Figure? = nil
	local firstTarget: Figure? = nil
	local anyCritical = false
	local knockedSomeone = false
	-- When the action's outcome shows: an attack as its blow lands, anything else once its
	-- performer has materialized (a summon) and gestured.
	local outcomeAt = if attacking then lead + HIT_DELAY else lead + (if summoned then 0.3 else 0.1)
	local helping = ability.kind ~= "Guard" and (ability.targets == "Self" or ability.targets == "Ally" or ability.targets == "AllAllies")
	if actor.side == "Party" and not attacking and helping then
		-- A heal or buff: its invocation shot is seen (CameraSpec.Cast.initiationSeconds, once the
		-- camera has swept there) before the effect lands and the camera cuts to the recipient.
		local opening = if ability.targets == "AllAllies" then 0 else CameraSpec.Cast.initiationSeconds -- (a party-wide cast has no caster shot)
		outcomeAt = math.max(outcomeAt, opening + CameraSpec.Transition.maxSweepSeconds + CameraSpec.Cast.effectSlackSeconds)
	end
	for index, result in action.results do
		local target = self.figures[result.targetId]
		if target == nil then
			continue
		end

		if result.knockedOut then
			knockedSomeone = true
		end
		if result.knockedOut and target.fall == "Pending" then
			-- It falls as the blow lands, not before, within what's left of the beat: through an
			-- enemy's hold (the hold is there to show it), done before the camera returns.
			target.fall = "Cued"
			local fallen = target
			local fallAt = lead + HIT_DELAY
			local returnSeconds = if enemyActor then CombatConfig.EnemyReturnSeconds else 0
			table.insert(cues, {
				at = fallAt,
				run = function()
					self:_fall(fallen, duration - returnSeconds - fallAt, fallAt)
				end,
			})
		end
		if ability.kind == "Attack" and target ~= actor then
			firstTarget = firstTarget or target
		end

		if ability.kind == "Attack" and target ~= actor then
			local toward = (target.home.Position - actor.home.Position).Unit
			-- A character, a block, or a model with no swing clip lunges at its target.
			if index == 1 and not swings then
				nudge(performer, performerHome, toward * 4, 0.15, lead)
			end
			if result.hit then
				local struck, struckHome = body(target)
				nudge(struck, struckHome, toward * 1.5, 0.1, lead + HIT_DELAY)
				local character, characterRoot = target.character, target.characterRoot
				if character and characterRoot then
					flinch(character, characterRoot, lead + HIT_DELAY)
				end
				firstHit = firstHit or target
				anyCritical = anyCritical or result.critical
			end
		end

		-- The outcome shows when it happens: the number as the blow lands, a cast's effect once the
		-- summon has materialized and gestured.
		local popups: { () -> () } = {}
		if ability.kind == "Attack" then
			if not result.hit then
				table.insert(popups, function()
					showPopup(sequencer, target, "MISS", BattleTheme.SubtleText, 0)
				end)
			else
				local strong = result.critical or result.knockedOut
				local text = if result.critical then `CRIT -{result.damage}` else `-{result.damage}`
				local color = if strong then BattleTheme.Danger else BattleTheme.Text
				table.insert(popups, function()
					showPopup(sequencer, target, text, color, 0)
				end)
				local inflicted = result.inflicted
				if inflicted then
					local def = StatusEffects[inflicted]
					local name = `{if def then def.name else inflicted}!`
					table.insert(popups, function()
						showPopup(sequencer, target, name, BattleTheme.Danger, AILMENT_POPUP_HEIGHT)
					end)
				end
			end
		elseif ability.kind == "Heal" then
			local healed = result.healed
			table.insert(popups, function()
				showPopup(sequencer, target, `+{healed}`, BattleTheme.HealthBar, 0)
			end)
		elseif ability.kind == "Guard" then
			table.insert(popups, function()
				showPopup(sequencer, target, "GUARD", BattleTheme.ManaBar, 0)
			end)
		else
			local applied = result.applied
			local def = if applied then StatusEffects[applied] else nil
			local name = if def then def.name else ability.name
			table.insert(popups, function()
				showPopup(sequencer, target, name, BattleTheme.Accent, 0)
			end)
		end
		for _, show in popups do
			table.insert(cues, { at = outcomeAt, run = show })
		end
	end

	-- The camera for the beat.
	local transition = CameraSpec.Transition
	local nextId = nextActorId(battle)
	-- Back to whoever's next (a cut or a short sweep, CameraSpec.Transition.returnStyle), at `at`
	-- in the beat; not when this blow decided the fight, when the result camera takes over.
	local function returnAt(at: number)
		if nextId == nil then
			return
		end
		table.insert(cues, {
			at = math.min(at, math.max(0, duration - 0.05)),
			run = function()
				local shot = self:_shotFor(nextId)
				local style = transition.returnStyle
				if style == "cut" then
					camera:cut(shot)
				else
					camera:moveTo(shot, transition.returnSeconds, style == "sweep")
				end
			end,
		})
	end
	if actor.side == "Party" then
		if not attacking and helping then
			-- A heal or buff (CAMERA_SPEC section 5). On one ally (or itself): the caster's frontal
			-- medium shot for the invocation, then a cut to the recipient chest-up as it lands, the
			-- camera lifting with the effect (reduced motion: the chest-up shot, still). On the
			-- whole party: the high-angle overhead, held through the effect, then back.
			local recipients: { Figure } = {}
			for _, result in action.results do
				local recipient = self.figures[result.targetId]
				if recipient then
					table.insert(recipients, recipient)
				end
			end
			local partyWide = ability.targets == "AllAllies" or #recipients > 1
			local first = recipients[1]
			local opening = self:_castOpening(actor, partyWide, if first then first.id else nil)
			if not camera:isHeadingTo(opening) then
				camera:moveTo(opening, transition.maxSweepSeconds)
			end
			if partyWide then
				returnAt(outcomeAt + CameraSpec.Party.holdSeconds)
			else
				local recipient = recipients[1] or actor
				local root = standing(recipient)
				local cast = CameraSpec.Cast
				table.insert(cues, {
					at = outcomeAt - 0.1,
					run = function()
						if Motion.scale() <= 0 then
							camera:cut(Shots.allyChestUp(root))
						else
							camera:follow(function(t: number): Shots.Pose
								return Shots.allyLift(root, t / cast.liftSeconds)
							end, cast.liftSeconds)
						end
					end,
				})
			end
		elseif summoned then
			-- (Already on its way there if this player confirmed the move: see confirm.)
			local shot = Shots.summon(standing(actor), self:_focus("Enemy"))
			if not camera:isHeadingTo(shot) then
				camera:moveTo(shot, transition.maxSweepSeconds)
			end
		elseif attacking then
			-- The character's own swing, from over its shoulder (a teammate's, or this player's
			-- when the confirm's move hasn't happened: joining mid-turn).
			local shot = self:_shotFor(actor.id)
			if not camera:isHeadingTo(shot) then
				camera:moveTo(shot, transition.maxSweepSeconds)
			end
		end
	else
		-- An enemy's beat (CAMERA_SPEC section 6): hard cuts (never two springs in flight at once),
		-- a hold on the outcome, then one move back to whoever's next. The camera starts on the
		-- enemy's wind-up shot (_openTurn). A single-target attack cuts over the targeted hero's
		-- shoulder, looking out at the incoming swing, then to the hero's reaction as the blow
		-- lands (a miss too: the MISS shows there); an attack on the whole party cuts to a wide
		-- lineup of the party as the blows land. A heal or buff holds the enemy's own shot.
		local landsAt = lead + HIT_DELAY
		local struckCount = 0
		for _, result in action.results do
			local target = self.figures[result.targetId]
			if target and target ~= actor then
				struckCount += 1
			end
		end
		if attacking and firstTarget and struckCount > 1 then
			local lineup = Shots.partyLineup(self:_focus("Party"), PARTY_FACING)
			table.insert(cues, {
				at = math.max(0, landsAt - CameraSpec.EnemyIncoming.cutLeadSeconds),
				run = function()
					camera:cut(lineup)
				end,
			})
		elseif attacking and firstTarget then
			local struck = firstTarget
			local struckRest = standing(struck)
			local reaction = Shots.reaction(struckRest, bodyHeight(struck))
			if landsAt >= CameraSpec.EnemyIncoming.minLeadSeconds then
				camera:cut(Shots.incoming(struckRest, standing(actor).Position))
				table.insert(cues, {
					at = landsAt - CameraSpec.EnemyIncoming.cutLeadSeconds,
					run = function()
						camera:cut(reaction)
					end,
				})
			else
				-- No swing worth a shot of its own: straight to the reaction, one cut.
				camera:cut(reaction)
			end
		end
		-- A knockout holds longer, through the fall (the server's wait has the Knockout extra for
		-- exactly that).
		local hold = CombatConfig.EnemyHoldSeconds
		if knockedSomeone then
			hold += CombatConfig.ResolveExtraSeconds.Knockout
		end
		returnAt(landsAt + hold)
	end
	if firstHit then
		table.insert(cues, {
			at = lead + HIT_DELAY,
			run = function()
				local kicks = CameraSpec.Kicks
				local shake = if anyCritical then kicks.criticalShake else kicks.shake
				camera:shake(shake.amplitude, shake.seconds)
				if anyCritical then
					camera:punch(kicks.criticalPunch)
				end
			end,
		})
	end

	sequencer:play(duration, cues)
	return duration, outcomeAt
end

-- The fight is decided: a slow orbit of the party for a win, a tilt down to the floor for a loss.
-- The results screen opens over it. (Runs after the final blow's beat: see render.)
function BattleView._playResult(self: BattleView, battle: BattleState)
	local center = self:_focus("Party")
	local facing = PARTY_FACING
	local track = if battle.winner == "Party"
		then function(t: number): Shots.Pose
			return Shots.victory(center, facing, t / RESULT_SECONDS)
		end
		else function(t: number): Shots.Pose
			return Shots.defeat(center, facing, t / RESULT_SECONDS)
		end
	self.camera:follow(track, RESULT_SECONDS)
end

return BattleView
