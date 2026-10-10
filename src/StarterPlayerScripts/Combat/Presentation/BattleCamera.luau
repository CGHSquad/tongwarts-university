--!strict
--[[
	BattleCamera — the one camera the battle presentation drives: it takes over the player's
	camera (Scriptable) for the fight and gives it back after.

	It moves between Shots.Poses on critically damped springs (snappy, never floaty, stable at any
	frame rate: the spring's closed-form step, so the tests' 5 Hz heartbeat and a phone's 30 fps
	land in the same places), cuts when told to, or follows a track (a function of time: the
	start-of-battle sweep, the victory orbit). On top of the pose: a subtle idle sway, a decaying
	shake, a field-of-view punch and a whip-pan roll, each scaled by the reduced-motion setting
	(scale 0 removes them entirely; cuts and moves stay).

	Lighting's DepthOfField would blur whatever a close shot doesn't focus on, so it's switched off
	for the fight and restored after.
]]

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Shots = require(script.Parent:WaitForChild("Shots"))

type Pose = Shots.Pose
export type Track = (t: number) -> Pose -- t in seconds since the track started

local BattleCamera = {}
BattleCamera.__index = BattleCamera

BattleCamera.WHIP_SECONDS = 0.22
BattleCamera.MOVE_SECONDS = 0.35
BattleCamera.SWAY = { amount = 0.12, rate = 0.9 } -- studs, cycles per second (roughly)
BattleCamera.WHIP_ROLL = math.rad(2) -- how far a whip-pan rolls the frame at its peak
BattleCamera.ROLL_OMEGA = 4 / 0.3
BattleCamera.SWAY_BLEND_SECONDS = 0.3 -- the sway eases back in after a track

type Fields = {
	active: boolean,
	position: Vector3,
	velocity: Vector3,
	-- The look direction as angles, sprung separately: yaw always turns the short way round and
	-- pitch stays near the horizon, so a move from facing one side to facing the other never
	-- swings the view through the floor (as interpolating a look-at point would).
	yaw: number,
	yawVelocity: number,
	pitch: number,
	pitchVelocity: number,
	targetYaw: number, -- unwrapped next to the current yaw
	targetPitch: number,
	fov: number,
	fovVelocity: number,
	fovKick: number,
	fovKickVelocity: number,
	roll: number,
	rollVelocity: number,
	omega: number, -- the springs' stiffness: 4 / seconds to settle
	target: Pose,
	track: Track?,
	trackTime: number,
	trackLength: number,
	shakeAmplitude: number,
	shakeLeft: number,
	shakeLength: number,
	shakeSeed: number,
	swayWeight: number, -- eases back in after a track, so the sway never jumps
	motionScale: number,
	time: number,
	dof: DepthOfFieldEffect?,
	dofWasEnabled: boolean,
	cameraType: Enum.CameraType?, -- the player's, restored afterwards
	fovBefore: number,
}

export type BattleCamera = typeof(setmetatable({} :: Fields, BattleCamera))

-- One step of a critically damped spring from (x, v) toward `target`, exact for any dt. Works on
-- numbers and on Vector3s alike (it's linear).
local function springNumber(x: number, v: number, target: number, omega: number, dt: number): (number, number)
	local d = x - target
	local b = v + omega * d
	local e = math.exp(-omega * dt)
	local nx, nv = target + (d + b * dt) * e, (b - omega * (d + b * dt)) * e
	if math.abs(nx - target) < 1e-4 and math.abs(nv) < 1e-3 then
		return target, 0 -- settled
	end
	return nx, nv
end

local function springVector(x: Vector3, v: Vector3, target: Vector3, omega: number, dt: number): (Vector3, Vector3)
	local d = x - target
	local b = v + d * omega
	local e = math.exp(-omega * dt)
	local nx, nv = target + (d + b * dt) * e, (b - (d + b * dt) * omega) * e
	if (nx - target).Magnitude < 1e-3 and nv.Magnitude < 1e-2 then
		return target, Vector3.zero -- settled: no residual creep
	end
	return nx, nv
end

local function clampSeconds(seconds: number): number
	return math.max(0.05, seconds)
end

-- A look direction from yaw (0 faces -Z, positive turns toward -X) and pitch (positive looks up).
local function directionOf(yaw: number, pitch: number): Vector3
	local flat = math.cos(pitch)
	return Vector3.new(-math.sin(yaw) * flat, math.sin(pitch), -math.cos(yaw) * flat)
end

-- The yaw and pitch of a pose's look direction.
local function anglesOf(pose: Pose): (number, number)
	local look = pose.lookAt - pose.position
	if look.Magnitude < 1e-3 then
		return 0, 0
	end
	local direction = look.Unit
	return math.atan2(-direction.X, -direction.Z), math.asin(math.clamp(direction.Y, -1, 1))
end

-- `target` moved next to `current` on the circle, so the spring turns the short way round.
local function unwrap(target: number, current: number): number
	return current + (target - current + math.pi) % (2 * math.pi) - math.pi
end

function BattleCamera.new(): BattleCamera
	local start = Shots.wide(Vector3.zero)
	local fields: Fields = {
		active = false,
		position = start.position,
		velocity = Vector3.zero,
		yaw = 0,
		yawVelocity = 0,
		pitch = 0,
		pitchVelocity = 0,
		targetYaw = 0,
		targetPitch = 0,
		fov = start.fov,
		fovVelocity = 0,
		fovKick = 0,
		fovKickVelocity = 0,
		roll = 0,
		rollVelocity = 0,
		omega = 4 / BattleCamera.MOVE_SECONDS,
		target = start,
		track = nil,
		trackTime = 0,
		trackLength = 0,
		shakeAmplitude = 0,
		shakeLeft = 0,
		shakeLength = 1,
		shakeSeed = 0,
		swayWeight = 1,
		motionScale = 1,
		time = 0,
		dof = nil,
		dofWasEnabled = false,
		cameraType = nil,
		fovBefore = 70,
	}
	return setmetatable(fields, BattleCamera)
end

-- Takes the camera over, holding the view the player had (so nothing jumps until a shot is set).
function BattleCamera.activate(self: BattleCamera)
	if self.active then
		return
	end
	self.active = true
	local camera = Workspace.CurrentCamera
	if camera then
		self.cameraType = camera.CameraType
		self.fovBefore = camera.FieldOfView
		local held = camera.CFrame
		local pose: Pose = { position = held.Position, lookAt = held.Position + held.LookVector * 10, fov = camera.FieldOfView }
		self:_snapTo(pose)
		camera.CameraType = Enum.CameraType.Scriptable
	end
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if dof then
		self.dof = dof
		self.dofWasEnabled = dof.Enabled
		dof.Enabled = false
	end
	self:_apply()
end

-- Gives the camera back to the player, and the depth of field to Lighting.
function BattleCamera.deactivate(self: BattleCamera)
	if not self.active then
		return
	end
	self.active = false
	self.track = nil
	self.shakeLeft = 0
	self.fovKick, self.fovKickVelocity = 0, 0
	self.roll, self.rollVelocity = 0, 0
	local camera = Workspace.CurrentCamera
	if camera then
		local before = self.cameraType
		camera.CameraType = if before and before ~= Enum.CameraType.Scriptable then before else Enum.CameraType.Custom
		camera.FieldOfView = self.fovBefore
	end
	local dof = self.dof
	if dof then
		dof.Enabled = self.dofWasEnabled
		self.dof = nil
	end
end

-- 0 with reduced motion: no sway, shake, punch or roll.
function BattleCamera.setMotionScale(self: BattleCamera, scale: number)
	self.motionScale = math.clamp(scale, 0, 1)
end

-- Puts the springs at a pose, at rest.
function BattleCamera._snapTo(self: BattleCamera, target: Pose)
	self.target = target
	self.position, self.velocity = target.position, Vector3.zero
	local yaw, pitch = anglesOf(target)
	self.yaw, self.yawVelocity = yaw, 0
	self.pitch, self.pitchVelocity = pitch, 0
	self.targetYaw, self.targetPitch = yaw, pitch
	self.fov, self.fovVelocity = target.fov, 0
end

-- Jumps straight to a pose.
function BattleCamera.cut(self: BattleCamera, target: Pose)
	self.track = nil
	self:_snapTo(target)
	self:_apply()
end

-- Springs to a pose, settling in about `seconds`. A whip (`seconds` under 0.3) also rolls the
-- camera a touch on the way, like a fast pan.
function BattleCamera.moveTo(self: BattleCamera, target: Pose, seconds: number?)
	self.track = nil
	local settle = clampSeconds(seconds or BattleCamera.MOVE_SECONDS)
	self.omega = 4 / settle
	if settle < 0.3 and (target.position - self.position).Magnitude > 2 then
		-- A kick whose critically damped response peaks at WHIP_ROLL (peak = v / (omega * e)).
		local toward = (target.position - self.position)
		local side = toward:Dot(self:_right())
		local kick = BattleCamera.WHIP_ROLL * BattleCamera.ROLL_OMEGA * math.exp(1)
		self.rollVelocity += (if side >= 0 then -1 else 1) * kick * self.motionScale
	end
	self.target = target
	local yaw, pitch = anglesOf(target)
	self.targetYaw = unwrap(yaw, self.yaw)
	self.targetPitch = pitch
end

-- Follows `track` for `seconds` (cutting to it), then holds where it ended.
function BattleCamera.follow(self: BattleCamera, track: Track, seconds: number)
	self.track = track
	self.trackTime = 0
	self.trackLength = math.max(0.01, seconds)
	self:cut(track(0))
	self.track = track
end

-- A quick field-of-view kick that springs back: confirming a move, a critical hit.
function BattleCamera.punch(self: BattleCamera, degrees: number)
	self.fovKick += degrees * self.motionScale
end

-- A decaying shake of up to `amplitude` studs over `seconds`.
function BattleCamera.shake(self: BattleCamera, amplitude: number, seconds: number)
	local amount = amplitude * self.motionScale
	if amount <= 0 then
		return
	end
	self.shakeAmplitude = math.max(self.shakeAmplitude * (self.shakeLeft / math.max(self.shakeLength, 0.01)), amount)
	self.shakeLength = clampSeconds(seconds)
	self.shakeLeft = self.shakeLength
	self.shakeSeed += 1
end

-- Where the camera is heading (the pose, before sway and shake).
function BattleCamera.getTarget(self: BattleCamera): Pose
	return self.target
end

-- Whether the camera is already heading to (or holding) this pose, so a second move there would
-- only add a kick.
function BattleCamera.isHeadingTo(self: BattleCamera, pose: Pose): boolean
	if self.track ~= nil or (self.target.position - pose.position).Magnitude >= 0.5 then
		return false
	end
	local yaw, pitch = anglesOf(pose)
	return directionOf(yaw, pitch):Dot(directionOf(self.targetYaw, self.targetPitch)) > math.cos(math.rad(2))
end

function BattleCamera.isSettled(self: BattleCamera): boolean
	return self.track == nil
		and (self.position - self.target.position).Magnitude < 0.05
		and math.abs(self.yaw - self.targetYaw) < 0.002
		and math.abs(self.pitch - self.targetPitch) < 0.002
end

function BattleCamera.update(self: BattleCamera, dt: number)
	if not self.active then
		return
	end
	dt = math.clamp(dt, 0, 0.25)
	self.time += dt
	-- The zone's lighting preset may be swapped under the fight (ZoneClient), replacing the depth
	-- of field effect: keep the new one off too.
	local dof = self.dof
	if dof == nil or dof.Parent == nil then
		local found = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
		if found and found ~= dof then
			self.dof = found
			self.dofWasEnabled = found.Enabled
			found.Enabled = false
		end
	end

	local track = self.track
	if track then
		self.trackTime += dt
		local t = math.min(self.trackTime, self.trackLength)
		local target = track(t)
		self:_snapTo(target)
		if self.trackTime >= self.trackLength then
			self.track = nil
		end
		self.swayWeight = 0
	else
		local target = self.target
		self.position, self.velocity = springVector(self.position, self.velocity, target.position, self.omega, dt)
		self.yaw, self.yawVelocity = springNumber(self.yaw, self.yawVelocity, self.targetYaw, self.omega, dt)
		self.pitch, self.pitchVelocity = springNumber(self.pitch, self.pitchVelocity, self.targetPitch, self.omega, dt)
		self.fov, self.fovVelocity = springNumber(self.fov, self.fovVelocity, target.fov, self.omega, dt)
		self.swayWeight = math.min(1, self.swayWeight + dt / BattleCamera.SWAY_BLEND_SECONDS)
	end
	self.fovKick, self.fovKickVelocity = springNumber(self.fovKick, self.fovKickVelocity, 0, 4 / 0.25, dt)
	self.roll, self.rollVelocity = springNumber(self.roll, self.rollVelocity, 0, BattleCamera.ROLL_OMEGA, dt)
	if self.shakeLeft > 0 then
		self.shakeLeft = math.max(0, self.shakeLeft - dt)
	end
	self:_apply()
end

function BattleCamera._right(self: BattleCamera): Vector3
	return Vector3.new(math.cos(self.yaw), 0, -math.sin(self.yaw))
end

-- Writes the pose, with sway and shake on top, to the real camera.
function BattleCamera._apply(self: BattleCamera)
	local camera = Workspace.CurrentCamera
	if camera == nil or not self.active then
		return
	end
	local scale = self.motionScale
	local right = self:_right()
	local offset = Vector3.zero
	if scale > 0 and self.track == nil and self.swayWeight > 0 then
		local sway = BattleCamera.SWAY
		local t = self.time * sway.rate
		offset += (right * math.sin(t) + Vector3.yAxis * (0.6 * math.sin(t * 1.37 + 1))) * (sway.amount * scale * self.swayWeight)
	end
	if self.shakeLeft > 0 and scale > 0 then
		local progress = 1 - self.shakeLeft / self.shakeLength
		local strength = self.shakeAmplitude * (1 - progress) * (1 - progress)
		local phase = self.time * 47 + self.shakeSeed
		offset += (right * math.sin(phase) + Vector3.yAxis * math.cos(phase * 1.3)) * strength
	end
	local position = self.position + offset
	local cframe = CFrame.lookAt(position, position + directionOf(self.yaw, self.pitch))
	if self.roll ~= 0 then
		cframe *= CFrame.Angles(0, 0, self.roll)
	end
	camera.CFrame = cframe
	camera.FieldOfView = math.clamp(self.fov + self.fovKick, 20, 120)
end

return BattleCamera
