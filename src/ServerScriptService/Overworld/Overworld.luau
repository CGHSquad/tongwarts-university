--!strict
--[[
	Overworld — the world between fights (GDD "Combat philosophy"): enemies that patrol or stand
	around on the baseplate, and the touch that starts a battle. Server-only.

	Every frame it moves the enemies (EnemySpawns) and checks whether any player's character is
	touching one. When one is, Encounter works out how the fight opens from the way the player was
	facing, and `startBattle` (from BattleServer, which asks BattleDirector) starts it. While the
	fight runs, that enemy holds still, the party's characters are frozen where they stood, and no
	other fight can start. When it's over (endBattle):

		the party won   the enemy vanishes and comes back EnemyRespawnSeconds later
		the party lost  everyone in it respawns at the spawn point
		either way      the party gets EncounterCooldownSeconds to walk away before another fight

	An enemy is one anchored block with a face on its front, so players can see which way it's
	looking. It doesn't collide: walking into it is what touching means.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BattleTypes = require(ReplicatedStorage.Combat.BattleTypes)
local CombatConfig = require(ReplicatedStorage.Combat.CombatConfig)
local Encounter = require(script.Parent.Encounter)
local EnemySpawns = require(script.Parent.EnemySpawns)

type EnemySpawn = EnemySpawns.EnemySpawn

-- Starts a fight because `userId` touched `spawn`'s enemy. Returns the user ids of everyone
-- pulled into it, or nil if no fight started.
export type StartBattle = (userId: number, spawn: EnemySpawn, contact: Encounter.Contact) -> { number }?

local BODY_SIZE = Vector3.new(4, 6, 4)
local BODY_COLOR = Color3.fromRGB(196, 78, 64)
local RETRY_SECONDS = 1 -- after a touch that couldn't start a fight, before that player can try again

type Enemy = {
	spawn: EnemySpawn,
	body: Part,
	nextPoint: number, -- Patrol: the point of its path it's walking to
	waitLeft: number, -- Patrol: pause left at a point; Idle: time until it turns again
	respawnAt: number?, -- set while it's beaten and gone
}

type Fight = {
	enemy: Enemy,
	party: { number }, -- user ids
}

type SavedMovement = {
	walkSpeed: number,
	jumpHeight: number,
	jumpPower: number,
}

local Overworld = {}
Overworld.__index = Overworld

type OverworldFields = {
	startBattle: StartBattle,
	folder: Folder,
	enemies: { Enemy },
	clock: number, -- seconds of Heartbeat time since start()
	fight: Fight?,
	cooldownUntil: { [number]: number }, -- user id -> clock time until which they can't start a fight
	saved: { [number]: SavedMovement }, -- frozen players' movement, to give back afterwards
}

export type Overworld = typeof(setmetatable({} :: OverworldFields, Overworld))

--[[ Enemy bodies ]]

-- Standing on the baseplate at `point` (only its X and Z count).
local function standingAt(point: Vector3): Vector3
	return Vector3.new(point.X, BODY_SIZE.Y / 2, point.Z)
end

local function createBody(spawn: EnemySpawn): Part
	local body = Instance.new("Part")
	body.Name = spawn.id
	body.Size = BODY_SIZE
	body.Anchored = true
	body.CanCollide = false
	body.CanTouch = false
	body.Material = Enum.Material.SmoothPlastic
	body.Color = BODY_COLOR

	-- Two eyes on the front, the way it's looking.
	local face = Instance.new("SurfaceGui")
	face.Name = "Face"
	face.Face = Enum.NormalId.Front
	face.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	face.PixelsPerStud = 25
	face.Parent = body
	for _, x in { 0.3, 0.7 } do
		local eye = Instance.new("Frame")
		eye.AnchorPoint = Vector2.new(0.5, 0.5)
		eye.Position = UDim2.fromScale(x, 0.3)
		eye.Size = UDim2.fromScale(0.2, 0.14)
		eye.BackgroundColor3 = Color3.new(1, 1, 1)
		eye.BorderSizePixel = 0
		eye.Parent = face
		local pupil = Instance.new("Frame")
		pupil.AnchorPoint = Vector2.new(0.5, 0.5)
		pupil.Position = UDim2.fromScale(0.5, 0.5)
		pupil.Size = UDim2.fromScale(0.5, 0.5)
		pupil.BackgroundColor3 = Color3.new(0, 0, 0)
		pupil.BorderSizePixel = 0
		pupil.Parent = eye
	end

	local nameplate = Instance.new("BillboardGui")
	nameplate.Name = "Nameplate"
	nameplate.Size = UDim2.fromOffset(160, 30)
	nameplate.StudsOffset = Vector3.new(0, BODY_SIZE.Y / 2 + 1.5, 0)
	nameplate.MaxDistance = 150
	nameplate.LightInfluence = 0
	nameplate.Parent = body
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.BuilderSansBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = spawn.name
	label.Parent = nameplate

	return body
end

-- Back to the start of its path, facing along it (an idle enemy faces -Z).
local function placeAtStart(enemy: Enemy)
	local path = enemy.spawn.path
	local start = standingAt(path[1])
	if enemy.spawn.behavior == "Patrol" then
		enemy.body.CFrame = CFrame.lookAt(start, standingAt(path[2]))
		enemy.nextPoint = 2
		enemy.waitLeft = 0
	else
		enemy.body.CFrame = CFrame.new(start)
		enemy.nextPoint = 1
		enemy.waitLeft = CombatConfig.EnemyIdleTurnSeconds
	end
end

--[[ Players' characters ]]

local function characterParts(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	if character == nil then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil, character:FindFirstChildOfClass("Humanoid")
end

-- Close enough to count as touching: within EncounterContactDistance across the ground, and not
-- way above or below it.
local function touching(playerPosition: Vector3, enemyPosition: Vector3): boolean
	local offset = playerPosition - enemyPosition
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= CombatConfig.EncounterContactDistance
		and math.abs(offset.Y) <= BODY_SIZE.Y
end

--[[ Overworld ]]

function Overworld.new(startBattle: StartBattle): Overworld
	local folder = Instance.new("Folder")
	folder.Name = "OverworldEnemies"
	folder.Parent = Workspace

	local fields: OverworldFields = {
		startBattle = startBattle,
		folder = folder,
		enemies = {},
		clock = 0,
		fight = nil,
		cooldownUntil = {},
		saved = {},
	}
	local self = setmetatable(fields, Overworld)

	for _, spawn in EnemySpawns do
		assert(spawn.behavior == "Idle" or #spawn.path >= 2, `{spawn.id}: a patrol needs at least two points`)
		local enemy: Enemy = { spawn = spawn, body = createBody(spawn), nextPoint = 1, waitLeft = 0, respawnAt = nil }
		placeAtStart(enemy)
		enemy.body.Parent = folder
		table.insert(self.enemies, enemy)
	end
	return self
end

-- Starts moving the enemies and watching for touches.
function Overworld.start(self: Overworld)
	RunService.Heartbeat:Connect(function(dt: number)
		self:_step(dt)
	end)

	local function watch(player: Player)
		-- A party member who respawns mid-fight (say, by resetting) stays frozen.
		player.CharacterAdded:Connect(function()
			local fight = self.fight
			if fight and table.find(fight.party, player.UserId) then
				self:_freeze(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		self.cooldownUntil[player.UserId] = nil
		self.saved[player.UserId] = nil
	end)
end

-- The fight is over (BattleDirector's result; nil if it was reset after an error).
function Overworld.endBattle(self: Overworld, winner: BattleTypes.Side?)
	local fight = self.fight
	if fight == nil then
		return
	end
	self.fight = nil

	for _, userId in fight.party do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			self:_unfreeze(player)
			self.cooldownUntil[userId] = self.clock + CombatConfig.EncounterCooldownSeconds
			if winner == "Enemy" then
				task.spawn(function()
					player:LoadCharacterAsync() -- beaten: back to the spawn point
				end)
			end
		end
	end

	if winner == "Party" then
		fight.enemy.respawnAt = self.clock + CombatConfig.EnemyRespawnSeconds
		fight.enemy.body.Parent = nil
	end
end

function Overworld._step(self: Overworld, dt: number)
	self.clock += dt
	local fight = self.fight
	for _, enemy in self.enemies do
		local respawnAt = enemy.respawnAt
		if respawnAt then
			if self.clock >= respawnAt then
				enemy.respawnAt = nil
				placeAtStart(enemy)
				enemy.body.Parent = self.folder
			end
		elseif fight == nil or fight.enemy ~= enemy then -- the one being fought holds still
			self:_move(enemy, dt)
		end
	end
	if fight == nil then
		self:_checkTouches()
	end
end

function Overworld._move(self: Overworld, enemy: Enemy, dt: number)
	enemy.waitLeft -= dt
	if enemy.spawn.behavior == "Idle" then
		if enemy.waitLeft <= 0 then
			enemy.waitLeft += CombatConfig.EnemyIdleTurnSeconds
			enemy.body.CFrame *= CFrame.Angles(0, math.rad(90), 0) -- look another way
		end
		return
	end
	if enemy.waitLeft > 0 then
		return -- pausing at a point
	end

	local path = enemy.spawn.path
	local position = enemy.body.CFrame.Position
	local target = standingAt(path[enemy.nextPoint])
	local offset = target - position
	local step = CombatConfig.EnemyPatrolSpeed * dt
	if offset.Magnitude > step then
		local nextPosition = position + offset.Unit * step
		enemy.body.CFrame = CFrame.lookAt(nextPosition, target)
		return
	end

	-- Arrived: pause here, turned toward the next point.
	enemy.nextPoint = enemy.nextPoint % #path + 1
	enemy.waitLeft = CombatConfig.EnemyPatrolPauseSeconds
	local following = standingAt(path[enemy.nextPoint])
	enemy.body.CFrame = if (following - target).Magnitude > 1e-3
		then CFrame.lookAt(target, following)
		else CFrame.new(target) * enemy.body.CFrame.Rotation
end

function Overworld._checkTouches(self: Overworld)
	for _, player in Players:GetPlayers() do
		local root = characterParts(player)
		if root == nil or self.clock < (self.cooldownUntil[player.UserId] or 0) then
			continue
		end
		local position = root.CFrame.Position
		for _, enemy in self.enemies do
			local enemyPosition = enemy.body.CFrame.Position
			if enemy.respawnAt == nil and touching(position, enemyPosition) then
				local contact: Encounter.Contact = Encounter.classify(root.CFrame, enemyPosition)
				local party = self.startBattle(player.UserId, enemy.spawn, contact)
				if party then
					self:_beginFight(enemy, party)
					return
				end
				self.cooldownUntil[player.UserId] = self.clock + RETRY_SECONDS
				break
			end
		end
	end
end

function Overworld._beginFight(self: Overworld, enemy: Enemy, party: { number })
	self.fight = { enemy = enemy, party = table.clone(party) }
	for _, userId in party do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			self:_freeze(player)
		end
	end
end

-- Holds a character in place for the fight: anchored, and no walking or jumping.
function Overworld._freeze(self: Overworld, player: Player)
	local root, humanoid = characterParts(player)
	if root then
		root.Anchored = true
	end
	if humanoid then
		if self.saved[player.UserId] == nil then
			self.saved[player.UserId] = {
				walkSpeed = humanoid.WalkSpeed,
				jumpHeight = humanoid.JumpHeight,
				jumpPower = humanoid.JumpPower,
			}
		end
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
		humanoid.JumpPower = 0
	end
end

function Overworld._unfreeze(self: Overworld, player: Player)
	local saved = self.saved[player.UserId]
	self.saved[player.UserId] = nil
	local root, humanoid = characterParts(player)
	if root then
		root.Anchored = false
	end
	if humanoid and saved then
		humanoid.WalkSpeed = saved.walkSpeed
		humanoid.JumpHeight = saved.jumpHeight
		humanoid.JumpPower = saved.jumpPower
	end
end

return Overworld
