--!strict
--[[
	CharacterRig — a player character on the battle stage, as an animated fighter (C2): its
	weapon in its hand, its stance (the breathing combat idle, the guard stance while Bracing, or
	knocked out), and the one-shot clips its beats play (the dash in and back, the swing, a flinch,
	an evade, a blocked hit). Clips and timing come from CharacterMoves; the weapon from Weapons
	and the Studio-only ReplicatedStorage.CombatAssets.Weapons folder.

	A clip plays from its published id, or in Studio from its KeyframeSequence registered for a
	temporary id; with neither (the headless tests, an R6 avatar, a live server before publishing)
	`play` returns nil and the beat uses its procedural fallback. The knocked-out state needs no
	clip: the character crumples and lies on the floor, dimmed, on any avatar.

	The stance is also written as a `Stance` attribute on the character model ("Idle", "Guard",
	"Downed"), for the tests and for Studio checks.
]]

local KeyframeSequenceProvider = nil :: KeyframeSequenceProvider?
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local CharacterMoves = require(Combat:WaitForChild("CharacterMoves"))
local Weapons = require(Combat:WaitForChild("Weapons"))

type Clip = CharacterMoves.Clip

export type Stance = "Idle" | "Guard" | "Downed"

local CharacterRig = {}
CharacterRig.__index = CharacterRig

CharacterRig.DOWNED_SECONDS = 0.5 -- the crumple to the floor
CharacterRig.DOWNED_DIM = 0.35 -- how faded a knocked-out character is
CharacterRig.DOWNED_ROOT_HEIGHT = 0.6 -- its hips above the floor, lying on its back

type Fields = {
	character: Model,
	root: BasePart,
	home: CFrame, -- where its root stands at its formation spot
	floorY: number,
	weapon: Weapons.Weapon,
	moveset: CharacterMoves.Moveset,
	animator: Animator?, -- nil: no clips (R6, the stand-in)
	tracks: { [string]: AnimationTrack },
	loop: AnimationTrack?, -- the stance's looping clip
	stance: Stance,
	weaponModel: Model?,
	trails: { Trail },
	playing: { [AnimationTrack]: number }, -- one-shot tracks and the speed each was asked for
	timeScale: number,
}

export type CharacterRig = typeof(setmetatable({} :: Fields, CharacterRig))

-- Clip ids registered this session, by clip key ("" = tried and unavailable).
local registered: { [string]: string } = {}

-- The animation id to play a clip from: its published id, or (in Studio) a temporary id for its
-- KeyframeSequence in CombatAssets.Animations; nil when there's neither.
function CharacterRig.clipId(clip: Clip): string?
	if clip.id ~= "" then
		return clip.id
	end
	local known = registered[clip.key]
	if known ~= nil then
		return if known ~= "" then known else nil
	end
	registered[clip.key] = ""
	local studio = false
	pcall(function()
		studio = RunService:IsStudio()
	end)
	if not studio then
		return nil
	end
	local assets = ReplicatedStorage:FindFirstChild("CombatAssets")
	local folder = if assets then assets:FindFirstChild("Animations") else nil
	local sequence = if folder then folder:FindFirstChild(clip.key) else nil
	if sequence == nil or not sequence:IsA("KeyframeSequence") then
		return nil
	end
	local ok, id = pcall(function()
		local provider = KeyframeSequenceProvider or game:GetService("KeyframeSequenceProvider")
		KeyframeSequenceProvider = provider
		return provider:RegisterKeyframeSequence(sequence)
	end)
	if ok and type(id) == "string" and id ~= "" then
		registered[clip.key] = id
		return id
	end
	return nil
end

-- The weapon a player's character fights with: their DebugWeapon attribute in Studio, else the
-- default.
function CharacterRig.weaponFor(player: Player?): Weapons.Weapon
	local id: string? = nil
	if player then
		local ok, value = pcall(function()
			return player:GetAttribute(Weapons.ATTRIBUTE)
		end)
		if ok and type(value) == "string" then
			local studio = false
			pcall(function()
				studio = RunService:IsStudio()
			end)
			if studio then
				id = value
			end
		end
	end
	return Weapons.get(id)
end

local function findAnimator(character: Model): Animator?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return nil
	end
	local existing = humanoid:FindFirstChildOfClass("Animator")
	if existing then
		return existing
	end
	local animator = Instance.new("Animator")
	animator.Parent = humanoid
	return animator
end

function CharacterRig.new(character: Model, root: BasePart, home: CFrame, floorY: number, weapon: Weapons.Weapon): CharacterRig
	local fields: Fields = {
		character = character,
		root = root,
		home = home,
		floorY = floorY,
		weapon = weapon,
		moveset = CharacterMoves.moveset(weapon.moveset),
		animator = findAnimator(character),
		tracks = {},
		loop = nil,
		stance = "Idle",
		weaponModel = nil,
		trails = {},
		playing = {},
		timeScale = 1,
	}
	local self = setmetatable(fields, CharacterRig)
	character:SetAttribute("Stance", "Idle")
	character:SetAttribute("Weapon", weapon.id)
	self:_attachWeapon()
	return self
end

-- Puts the weapon's model in the character's right hand: a copy of its template from
-- CombatAssets.Weapons, held by a Motor6D at the grip the pack's rig used (the template's
-- `GripC0`/`GripC1` attributes). Its glow emitters stay off; its trails light up during a swing.
function CharacterRig._attachWeapon(self: CharacterRig)
	local name = self.weapon.model
	if name == nil then
		return
	end
	local assets = ReplicatedStorage:FindFirstChild("CombatAssets")
	local folder = if assets then assets:FindFirstChild("Weapons") else nil
	local template = if folder then folder:FindFirstChild(name) else nil
	if template == nil or not template:IsA("Model") then
		return
	end
	local hand = self.character:FindFirstChild("RightHand") or self.character:FindFirstChild("Right Arm")
	if hand == nil or not hand:IsA("BasePart") then
		return
	end
	local model = template:Clone()
	local grip = model:FindFirstChild("Main", true)
	if grip == nil or not grip:IsA("BasePart") then
		model:Destroy()
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
		elseif d:IsA("ParticleEmitter") then
			d.Enabled = false
		elseif d:IsA("Trail") then
			d.Enabled = false
			table.insert(self.trails, d)
		elseif d:IsA("Motor6D") or d:IsA("Weld") then
			d:Destroy() -- the pack rig's own hand joint; ours is made below
		end
	end
	local c0 = template:GetAttribute("GripC0")
	local c1 = template:GetAttribute("GripC1")
	local joint = Instance.new("Motor6D")
	joint.Name = "WeaponGrip"
	joint.Part0 = hand
	joint.Part1 = grip
	joint.C0 = if typeof(c0) == "CFrame" then c0 else CFrame.new()
	joint.C1 = if typeof(c1) == "CFrame" then c1 else CFrame.new()
	if hand.Name == "Right Arm" then
		joint.C0 = CFrame.new(0, -1, 0) * joint.C0 -- an R6 arm: the hand is its bottom end
	end
	joint.Parent = grip
	model.Name = "Weapon"
	model.Parent = self.character
	self.weaponModel = model
end

-- The trails on the weapon, on for a swing and off after.
function CharacterRig.setTrails(self: CharacterRig, on: boolean)
	for _, trail in self.trails do
		trail.Enabled = on
	end
end

function CharacterRig._load(self: CharacterRig, clip: Clip): AnimationTrack?
	local animator = self.animator
	if animator == nil then
		return nil
	end
	local cached = self.tracks[clip.key]
	if cached then
		return cached
	end
	local id = CharacterRig.clipId(clip)
	if id == nil then
		return nil
	end
	local ok, loaded = pcall(function(): AnimationTrack?
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		return animator:LoadAnimation(animation)
	end)
	local track: AnimationTrack? = if ok then loaded else nil
	if track == nil then
		return nil
	end
	track.Looped = clip.looped
	track.Priority = if clip.looped then Enum.AnimationPriority.Idle else Enum.AnimationPriority.Action
	self.tracks[clip.key] = track
	return track
end

-- Whether this character can play clips at all (an R15 avatar with clips available).
function CharacterRig.hasClips(self: CharacterRig): boolean
	return self.animator ~= nil and self:_load(self.moveset.idle) ~= nil
end

-- Plays a one-shot clip at `speed` (so a clip's timing can be fitted to a beat). Returns the
-- track, or nil when the clip isn't available (the caller's fallback runs instead).
function CharacterRig.play(self: CharacterRig, clip: Clip, speed: number?, fade: number?): AnimationTrack?
	if self.stance == "Downed" then
		return nil
	end
	local track = self:_load(clip)
	if track == nil then
		return nil
	end
	local rate = speed or 1
	track:Play(fade or 0.1, 1, rate * self.timeScale)
	self.playing[track] = rate
	local connection: RBXScriptConnection
	connection = track.Stopped:Connect(function()
		connection:Disconnect()
		self.playing[track] = nil
	end)
	return track
end

-- Stops a one-shot clip (fading out over `fade`).
function CharacterRig.stop(self: CharacterRig, track: AnimationTrack?, fade: number?)
	if track then
		track:Stop(fade or 0.15)
		self.playing[track] = nil
	end
end

-- The sequencer's time scale (a hit-stop's 0, a slow-mo's fraction, 1 after): one-shot clips
-- follow it, the stance's loop doesn't (it's breathing, not the blow).
function CharacterRig.setTimeScale(self: CharacterRig, scale: number)
	self.timeScale = scale
	for track, rate in self.playing do
		if track.IsPlaying then
			track:AdjustSpeed(rate * scale)
		end
	end
end

function CharacterRig.getStance(self: CharacterRig): Stance
	return self.stance
end

-- Changes stance. Idle and Guard loop their clip (when there is one); Downed crumples the
-- character to the floor and dims it (`instant` skips the fall, for a character already down).
function CharacterRig.setStance(self: CharacterRig, stance: Stance, instant: boolean?)
	if self.stance == stance then
		return
	end
	if self.stance == "Downed" then
		return -- nobody gets up in a fight (no revive yet)
	end
	self.stance = stance
	self.character:SetAttribute("Stance", stance)
	local previous = self.loop
	if stance == "Downed" then
		for track in self.playing do
			track:Stop(0.1)
		end
		table.clear(self.playing)
		if previous then
			previous:Stop(0.2)
			self.loop = nil
		end
		self:setTrails(false)
		self:_lieDown(instant == true)
		return
	end
	local clip = if stance == "Guard" then self.moveset.guard else self.moveset.idle
	local track = self:_load(clip)
	if track and track ~= previous then
		track:Play(0.25)
	end
	if previous and previous ~= track then
		previous:Stop(0.25)
	end
	self.loop = track
end

-- Starts the stance's loop if it isn't playing (after a beat, or once clips are available).
function CharacterRig.resumeStance(self: CharacterRig)
	if self.stance == "Downed" then
		return
	end
	local clip = if self.stance == "Guard" then self.moveset.guard else self.moveset.idle
	local track = self:_load(clip)
	if track and not track.IsPlaying then
		track:Play(0.25)
	end
	self.loop = track
end

-- Knocked out: the character drops to its knees, then falls back onto the floor, and dims. It's
-- the character's anchored root that moves (the joints carry the rest), so it works on any avatar.
function CharacterRig._lieDown(self: CharacterRig, instant: boolean)
	local root = self.root
	local standing = self.home
	local floorPoint = Vector3.new(standing.Position.X, self.floorY + CharacterRig.DOWNED_ROOT_HEIGHT, standing.Position.Z)
	-- On its back, head away from the enemies: turned a quarter around its right axis.
	local lying = (standing.Rotation + floorPoint) * CFrame.Angles(math.rad(90), 0, 0)
	local kneeling = standing * CFrame.new(0, -1.2, 0) * CFrame.Angles(math.rad(25), 0, 0)
	for _, d in self.character:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			(d :: any).LocalTransparencyModifier = CharacterRig.DOWNED_DIM
		end
	end
	if instant then
		root.CFrame = lying
		self:_dropWeapon()
		return
	end
	local first = CharacterRig.DOWNED_SECONDS * 0.4
	local second = CharacterRig.DOWNED_SECONDS - first
	local kneel = TweenService:Create(root, TweenInfo.new(first, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = kneeling })
	kneel:Play()
	task.delay(first, function()
		if self.root.Parent ~= nil then
			TweenService:Create(root, TweenInfo.new(second, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { CFrame = lying }):Play()
		end
	end)
	task.delay(first + second * 0.5, function()
		self:_dropWeapon()
	end)
end

-- The weapon falls out of a knocked-out character's hand and lies flat on the floor beside it
-- (held in the hand it would stand up out of the body).
function CharacterRig._dropWeapon(self: CharacterRig)
	local model = self.weaponModel
	if model == nil or model.Parent == nil then
		return
	end
	local main = model:FindFirstChild("Main", true)
	if main == nil or not main:IsA("BasePart") then
		return
	end
	local grip = model:FindFirstChild("WeaponGrip", true)
	if grip then
		grip:Destroy()
	end
	local size = main.Size
	-- Lay the part's longest axis flat, across the character's spot.
	local tilt = if size.Y >= size.X and size.Y >= size.Z then CFrame.Angles(0, 0, math.rad(90)) else CFrame.new()
	local beside = self.home.Position + self.home.RightVector * 1.8
	main.Anchored = true
	main.CFrame = CFrame.new(beside.X, self.floorY, beside.Z) * self.home.Rotation * tilt
	-- Then lift it until its lowest point (any part welded to it included) rests on the floor.
	local lowest = math.huge
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local cf, extent = part.CFrame, part.Size / 2
			local below = math.abs(cf.RightVector.Y) * extent.X + math.abs(cf.UpVector.Y) * extent.Y + math.abs(cf.LookVector.Y) * extent.Z
			lowest = math.min(lowest, cf.Position.Y - below)
		end
	end
	if lowest < math.huge then
		main.CFrame += Vector3.new(0, self.floorY - lowest + 0.02, 0)
	end
	self:setTrails(false)
end

function CharacterRig.destroy(self: CharacterRig)
	for _, track in self.tracks do
		track:Stop(0)
	end
	table.clear(self.tracks)
	table.clear(self.playing)
end

return CharacterRig
