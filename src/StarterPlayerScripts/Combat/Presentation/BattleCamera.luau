--!strict
--[[
	BattleCamera — the one camera the battle presentation drives: it takes over the player's
	camera (Scriptable) for the fight and gives it back after.

	It moves between Shots.Poses on critically damped springs (snappy, never floaty, stable at any
	frame rate: the spring's closed-form step, so the tests' 5 Hz heartbeat and a phone's 30 fps
	land in the same places), cuts when told to, or follows a track (a function of time: the
	start-of-battle sweep, the victory orbit). No sweep is longer than CameraSpec's
	Transition.maxSweepSeconds; what holds is the shot itself, never the move. Each pose carries its
	Dutch tilt, sprung along with it. On top of the pose: a subtle idle sway, a decaying shake, a
	field-of-view punch and a whip-pan roll, each scaled by the reduced-motion setting (scale 0
	removes them entirely, and turns every sweep into a cut; the tilt and the tracks stay).

	Depth of field: Lighting's own effect would blur whatever a close shot doesn't focus on, so it's
	switched off for the fight and restored after. The camera brings its own, focused on the shot,
	for the sub-menu push (setFocusBlur), and leaves it off on low graphics quality.
]]

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local CameraSpec = require(script.Parent:WaitForChild("CameraSpec"))
local Shots = require(script.Parent:WaitForChild("Shots"))

type Pose = Shots.Pose
export type Track = (t: number) -> Pose -- t in seconds since the track started

local BattleCamera = {}
BattleCamera.__index = BattleCamera

BattleCamera.WHIP_SECONDS = CameraSpec.Transition.whipSeconds
BattleCamera.MOVE_SECONDS = CameraSpec.Transition.maxSweepSeconds
BattleCamera.SWAY = CameraSpec.Idle.sway -- studs, cycles per second (roughly)
BattleCamera.WHIP_ROLL = math.rad(CameraSpec.Kicks.whipRoll) -- how far a whip-pan rolls the frame at its peak
BattleCamera.ROLL_OMEGA = 8 / CameraSpec.Kicks.rollSettleSeconds -- (as SETTLE below: done when the time is up)
BattleCamera.SWAY_BLEND_SECONDS = CameraSpec.Idle.sway.blendSeconds -- the sway eases back in after a track
BattleCamera.FOCUS_EFFECT_NAME = "BattleCameraFocus"
-- A sweep's spring stiffness is SETTLE / its seconds: a critically damped spring is 99.7% of the
-- way there at omega * t = 8, so a 0.25 s sweep is done in 0.25 s rather than creeping on after it
-- (at 6.6 the live trace still showed 0.1-0.4 studs settling over another 0.1 s).
BattleCamera.SETTLE = 8
-- The C1 field-of-view kick's spring (confirming a move): softer than SETTLE, it rings out past
-- Kicks.punchSettleSeconds.
BattleCamera.PUNCH_OMEGA = 4 / CameraSpec.Kicks.punchSettleSeconds

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
	tilt: number, -- the pose's Dutch tilt, radians, sprung
	tiltVelocity: number,
	targetTilt: number,
	roll: number, -- the transient whip-pan roll, radians
	rollVelocity: number,
	omega: number, -- the springs' stiffness: SETTLE / seconds to settle
	target: Pose,
	track: Track?,
	trackTime: number,
	trackLength: number,
	shakeAmplitude: number,
	shakeLeft: number,
	shakeLength: number,
	shakeSeed: number,
	shakeDirection: Vector3?, -- the blow's direction in the world (nil: an all-round shake)
	kickOmega: number, -- the field-of-view kick's spring: SETTLE / its settle time
	swayWeight: number, -- eases back in after a track, so the sway never jumps
	motionScale: number,
	time: number,
	dof: DepthOfFieldEffect?, -- Lighting's own, held off for the fight
	dofWasEnabled: boolean,
	focus: DepthOfFieldEffect?, -- the camera's own, for the sub-menu push
	focusOn: boolean,
	focusPoint: Vector3?, -- what it keeps sharp (the acting hero's head); the shot's aim when nil
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
	return math.clamp(seconds, 0.05, CameraSpec.Transition.maxSweepSeconds)
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

-- Whether the player's graphics quality is high enough for depth of field: a saved level under
-- CameraSpec.DepthOfFieldMinQuality says no. Automatic says no on a touch-only device (a phone or
-- tablet, where Automatic runs low) and yes elsewhere; no settings at all (the tests' fake Roblox)
-- says yes.
function BattleCamera.depthOfFieldAllowed(): boolean
	local ok, level = pcall(function()
		local settings = UserSettings():GetService("UserGameSettings")
		return settings.SavedQualityLevel.Value
	end)
	if ok and type(level) == "number" then
		if level > 0 then
			return level >= CameraSpec.DepthOfFieldMinQuality
		end
		local touchOnly = false
		pcall(function()
			local input = game:GetService("UserInputService")
			touchOnly = input.TouchEnabled and not input.KeyboardEnabled
		end)
		return not touchOnly
	end
	return true
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
		tilt = 0,
		tiltVelocity = 0,
		targetTilt = 0,
		roll = 0,
		rollVelocity = 0,
		omega = BattleCamera.SETTLE / BattleCamera.MOVE_SECONDS,
		target = start,
		track = nil,
		trackTime = 0,
		trackLength = 0,
		shakeAmplitude = 0,
		shakeLeft = 0,
		shakeLength = 1,
		shakeSeed = 0,
		shakeDirection = nil,
		kickOmega = BattleCamera.PUNCH_OMEGA,
		swayWeight = 1,
		motionScale = 1,
		time = 0,
		dof = nil,
		dofWasEnabled = false,
		focus = nil,
		focusOn = false,
		focusPoint = nil,
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
		local pose: Pose = { position = held.Position, lookAt = held.Position + held.LookVector * 10, fov = camera.FieldOfView, roll = 0 }
		self:_snapTo(pose)
		camera.CameraType = Enum.CameraType.Scriptable
	end
	self:_holdLightingDof()
	self.focusOn = false
	self:_ensureFocus()
	self:_apply()
end

-- The camera's own depth of field effect, made when missing: the zone's lighting preset may be
-- swapped under the fight (ZoneClient), sweeping Lighting's effects away with it.
function BattleCamera._ensureFocus(self: BattleCamera): DepthOfFieldEffect?
	if not self.active then
		return nil
	end
	local existing = self.focus
	if existing ~= nil and existing.Parent ~= nil then
		return existing -- (still in Lighting: nothing else moves it, and a swap destroys it)
	end
	local focus = Instance.new("DepthOfFieldEffect")
	focus.Name = BattleCamera.FOCUS_EFFECT_NAME
	local blur = CameraSpec.Menu.depthOfField
	focus.FarIntensity = blur.farIntensity
	focus.NearIntensity = blur.nearIntensity
	focus.InFocusRadius = blur.inFocusRadius
	focus.FocusDistance = 10
	focus.Enabled = self.focusOn and BattleCamera.depthOfFieldAllowed()
	focus.Parent = Lighting
	self.focus = focus
	return focus
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
	local focus = self.focus
	if focus then
		focus:Destroy()
		self.focus = nil
	end
	self.focusOn = false
end

-- 0 with reduced motion: no sway, shake, punch or roll, and every sweep is a cut.
function BattleCamera.setMotionScale(self: BattleCamera, scale: number)
	self.motionScale = math.clamp(scale, 0, 1)
end

-- Softens everything but `point` (the acting hero, while the skill list is open). Stays off on low
-- graphics quality.
function BattleCamera.setFocusBlur(self: BattleCamera, on: boolean, point: Vector3?)
	self.focusOn = on
	self.focusPoint = point
	local focus = self:_ensureFocus()
	if focus then
		focus.Enabled = on and BattleCamera.depthOfFieldAllowed()
	end
end

function BattleCamera.isFocusBlurred(self: BattleCamera): boolean
	local focus = self.focus
	return focus ~= nil and focus.Enabled
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
	self.targetTilt = math.rad(target.roll)
	self.tilt, self.tiltVelocity = self.targetTilt, 0
end

-- Jumps straight to a pose.
function BattleCamera.cut(self: BattleCamera, target: Pose)
	self.track = nil
	self:_snapTo(target)
	self:_apply()
end

-- Sweeps to a pose, an ease-out settling in about `seconds` (never more than the spec's longest
-- sweep). A whip (`seconds` under 0.3) also rolls the camera a touch on the way, like a fast pan.
-- A move that would turn the camera more than CameraSpec's cutAboveDegrees is a cut, and so is
-- every move with reduced motion; `noCut` keeps it a sweep whatever the turn.
function BattleCamera.moveTo(self: BattleCamera, target: Pose, seconds: number?, noCut: boolean?)
	local transition = CameraSpec.Transition
	if self.motionScale <= 0 and transition.reducedMotionCuts then
		self:cut(target)
		return
	end
	if not noCut and self:turnDegreesTo(target) > transition.cutAboveDegrees then
		self:cut(target)
		return
	end
	self.track = nil
	local settle = clampSeconds(seconds or BattleCamera.MOVE_SECONDS)
	self.omega = BattleCamera.SETTLE / settle
	local kicks = CameraSpec.Kicks
	if settle < kicks.whipBelowSeconds and (target.position - self.position).Magnitude > kicks.whipMinStuds then
		-- A kick whose critically damped response peaks at WHIP_ROLL (peak = v / (omega * e)).
		local toward = (target.position - self.position)
		local side = toward:Dot(self:_right())
		local kick = BattleCamera.WHIP_ROLL * BattleCamera.ROLL_OMEGA * math.exp(1)
		-- (Set, not added: two moves issued in one frame, a confirm's and a turn's, roll once.)
		self.rollVelocity = (if side >= 0 then -1 else 1) * kick * self.motionScale
	end
	self.target = target
	local yaw, pitch = anglesOf(target)
	self.targetYaw = unwrap(yaw, self.yaw)
	self.targetPitch = pitch
	self.targetTilt = math.rad(target.roll)
end

-- Follows `track` for `seconds` (cutting to it), then holds where it ended. With reduced motion it
-- cuts straight to where the track ends.
function BattleCamera.follow(self: BattleCamera, track: Track, seconds: number)
	if self.motionScale <= 0 and CameraSpec.Transition.reducedMotionCuts then
		self:cut(track(seconds))
		return
	end
	self.track = track
	self.trackTime = 0
	self.trackLength = math.max(0.01, seconds)
	self:cut(track(0))
	self.track = track
end

-- A quick field-of-view kick that springs back: confirming a move (wider), the contact frame of a
-- blow (narrower, CameraSpec.Impact). With `settleSeconds` it snaps there and settles back in that
-- time; without, it eases back on the C1 kick's softer spring.
function BattleCamera.punch(self: BattleCamera, degrees: number, settleSeconds: number?)
	self.fovKick += degrees * self.motionScale
	if settleSeconds then
		-- An impact: snaps and settles back in exactly that time.
		self.fovKickVelocity = 0
		self.kickOmega = BattleCamera.SETTLE / math.max(0.05, settleSeconds)
	else
		-- The C1 kicks (confirming a move): their softer spring, as before.
		self.kickOmega = BattleCamera.PUNCH_OMEGA
	end
end

-- A decaying shake of up to `amplitude` studs over `seconds`. With `direction` (the blow's, in the
-- world) it runs along that line on screen, mostly: directional trauma, vertical for an overhead
-- swing, sideways for a hook, back along an incoming blow.
function BattleCamera.shake(self: BattleCamera, amplitude: number, seconds: number, direction: Vector3?)
	local amount = amplitude * self.motionScale
	if amount <= 0 then
		return
	end
	self.shakeAmplitude = math.max(self.shakeAmplitude * (self.shakeLeft / math.max(self.shakeLength, 0.01)), amount)
	self.shakeLength = math.max(0.05, seconds)
	self.shakeLeft = self.shakeLength
	self.shakeSeed += 1
	self.shakeDirection = if direction and direction.Magnitude > 1e-3 then direction.Unit else nil
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
	if math.abs(self.target.fov - pose.fov) > 0.5 or math.abs(self.target.roll - pose.roll) > 0.5 then
		return false
	end
	local yaw, pitch = anglesOf(pose)
	return directionOf(yaw, pitch):Dot(directionOf(self.targetYaw, self.targetPitch)) > math.cos(math.rad(2))
end

-- How far (degrees) the camera would turn to face the way `pose` looks, from where it's heading.
function BattleCamera.turnDegreesTo(self: BattleCamera, pose: Pose): number
	local yaw, pitch = anglesOf(pose)
	local dot = directionOf(yaw, pitch):Dot(directionOf(self.targetYaw, self.targetPitch))
	return math.deg(math.acos(math.clamp(dot, -1, 1)))
end

function BattleCamera.isSettled(self: BattleCamera): boolean
	return self.track == nil
		and (self.position - self.target.position).Magnitude < 0.05
		and math.abs(self.yaw - self.targetYaw) < 0.002
		and math.abs(self.pitch - self.targetPitch) < 0.002
end

-- Lighting's own depth of field (not the camera's) is held off for the fight. The zone's lighting
-- preset may be swapped under the fight (ZoneClient), replacing the effect: keep the new one off too.
function BattleCamera._holdLightingDof(self: BattleCamera)
	local dof = self.dof
	if dof ~= nil and dof.Parent ~= nil then
		return
	end
	for _, child in Lighting:GetChildren() do
		if child:IsA("DepthOfFieldEffect") and child ~= self.focus and child ~= dof then
			self.dof = child
			self.dofWasEnabled = child.Enabled
			child.Enabled = false
			return
		end
	end
end

function BattleCamera.update(self: BattleCamera, dt: number)
	if not self.active then
		return
	end
	dt = math.clamp(dt, 0, 0.25)
	self.time += dt
	self:_holdLightingDof()
	if self.focusOn then
		self:_ensureFocus()
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
		self.tilt, self.tiltVelocity = springNumber(self.tilt, self.tiltVelocity, self.targetTilt, self.omega, dt)
		self.swayWeight = math.min(1, self.swayWeight + dt / BattleCamera.SWAY_BLEND_SECONDS)
	end
	self.fovKick, self.fovKickVelocity = springNumber(self.fovKick, self.fovKickVelocity, 0, self.kickOmega, dt)
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
		offset += (right * math.sin(t) + Vector3.yAxis * (sway.vertical * math.sin(t * 1.37 + 1))) * (sway.amount * scale * self.swayWeight)
	end
	if self.shakeLeft > 0 and scale > 0 then
		local progress = 1 - self.shakeLeft / self.shakeLength
		local strength = self.shakeAmplitude * (1 - progress) * (1 - progress)
		local phase = self.time * CameraSpec.Kicks.shakeFrequency + self.shakeSeed
		local direction = self.shakeDirection
		local along, across = right, Vector3.yAxis
		if direction then
			-- The blow's direction as the camera sees it (its part along the view doesn't shake).
			local up = Vector3.yAxis
			local onScreen = right * direction:Dot(right) + up * direction:Dot(up)
			if onScreen.Magnitude > 0.2 then
				along = onScreen.Unit
				across = along:Cross(directionOf(self.yaw, self.pitch)).Unit
			end
			offset += (along * math.sin(phase) + across * (0.25 * math.cos(phase * 1.3))) * strength
		else
			offset += (along * math.sin(phase) + across * math.cos(phase * 1.3)) * strength
		end
	end
	local position = self.position + offset
	local cframe = CFrame.lookAt(position, position + directionOf(self.yaw, self.pitch))
	local roll = self.tilt + self.roll
	if roll ~= 0 then
		cframe *= CFrame.Angles(0, 0, roll)
	end
	camera.CFrame = cframe
	local range = CameraSpec.Kicks.fovRange
	camera.FieldOfView = math.clamp(self.fov + self.fovKick, range[1], range[2])
	local focus = self.focus
	if focus and focus.Enabled then
		focus.FocusDistance = ((self.focusPoint or self.target.lookAt) - position).Magnitude
	end
end

return BattleCamera
