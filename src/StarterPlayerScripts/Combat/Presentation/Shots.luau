--!strict
--[[
	Shots — where the battle camera stands for each beat, as pure CFrame math (no Instances, so
	the headless tests can check the same numbers). A Pose is a position, a point to look at, a
	field of view and a Dutch roll; BattleCamera moves between poses. Every number comes from
	CameraSpec. Stage directions: a party member's spot faces the enemies, an enemy's spot faces
	the party, so every shot is built from a spot's own vectors and works on either side.

	The shots (CAMERA_SPEC.md, sections 3 to 6, as the C0 report mapped them to C1):
		overShoulder   idle command framing: behind the acting party member's shoulder, hero in the
		               left third, enemies around the middle
		menuPush       the same, pushed a little forward with a tighter tilt (the skill list is open)
		targetEnemy    picking one enemy: tight and low, looking up at it from the hero's side
		targetSquad    picking all enemies: pulled back and up from the hero
		allyChestUp    picking (or healing) one ally: chest-up frontal
		partyOverhead  a party-wide buff or heal: high-angle three-quarters overhead
		casterFrontal  a buff or heal's invocation: frontal medium shot of the caster
		incoming       an enemy's attack: over the targeted hero's shoulder, looking out at it
		partyLineup    an enemy's attack on the whole party: wide rear-diagonal lineup
		enemyFrontal   an acting enemy's wind-up: offset frontal, low
		reaction       whoever a blow lands on, front-low
		summon         the summon beat, well back so character and summon both fit
		sweep          the battle-start dolly; victory orbits, defeat tilts; wide is the fallback
]]

local CameraSpec = require(script.Parent:WaitForChild("CameraSpec"))

local Shots = {}

export type Pose = {
	position: Vector3,
	lookAt: Vector3,
	fov: number,
	roll: number, -- degrees of Dutch tilt
}

local function pose(position: Vector3, lookAt: Vector3, fov: number, roll: number): Pose
	return { position = position, lookAt = lookAt, fov = fov, roll = roll }
end

local function smooth(t: number): number
	local x = math.clamp(t, 0, 1)
	return x * x * (3 - 2 * x)
end

-- The horizontal direction from `from` toward `to`, or `fallback` when they coincide.
local function flatAxis(from: Vector3, to: Vector3, fallback: Vector3): Vector3
	local toward = to - from
	local flat = Vector3.new(toward.X, 0, toward.Z)
	return if flat.Magnitude > 1e-3 then flat.Unit else fallback
end

local function rightOf(axis: Vector3): Vector3
	return axis:Cross(Vector3.yAxis)
end

-- The middle of a few points (the enemies, the party), to aim at.
function Shots.focusOf(points: { Vector3 }, fallback: Vector3): Vector3
	if #points == 0 then
		return fallback
	end
	local sum = Vector3.zero
	for _, point in points do
		sum += point
	end
	return sum / #points
end

-- Idle command framing: behind a party member's right shoulder (`root` is where its character
-- stands), looking between its head and `focus` (the enemies). Built on the line from the hero to
-- the focus, not on its facing, so both party slots frame alike. `pullBack` > 1 stands further
-- off (a teammate's turn, an enemy's shoulder); `aimRight` (default Idle.aimRight) moves the aim
-- right so the hero sits in the left third; `fov`/`roll` default to the idle values.
function Shots.overShoulder(root: CFrame, focus: Vector3, pullBack: number?, aimRight: number?, fov: number?, roll: number?): Pose
	local pull = pullBack or 1
	local idle = CameraSpec.Idle
	local axis = flatAxis(root.Position, focus, root.LookVector)
	local right = rightOf(axis)
	local position = root.Position - axis * (idle.back * pull) + Vector3.new(0, idle.up * pull, 0) + right * (idle.side * pull)
	local head = root.Position + Vector3.new(0, idle.focusUp, 0)
	local bias = if aimRight ~= nil then aimRight else idle.aimRight
	return pose(position, head:Lerp(focus, idle.focusBlend) + right * bias + Vector3.new(0, idle.aimUp, 0), fov or idle.fov, roll or idle.roll)
end

-- The skill list is open: the idle shot pushed a little forward along its axis, tilted more.
function Shots.menuPush(idle: Pose): Pose
	local menu = CameraSpec.Menu
	local forward = (idle.lookAt - idle.position)
	local axis = if forward.Magnitude > 1e-3 then forward.Unit else Vector3.zAxis
	return pose(idle.position + axis * menu.dolly, idle.lookAt, menu.fov, menu.roll)
end

-- Picking one enemy: from the hero's side, close and low, looking up at it. `center` is the
-- enemy's middle (facing the party), `height` how tall it stands, `fromHero` where the hero is,
-- `others` the middle of the other enemies (it's framed a little off-centre, away from them),
-- `compact` for a phone's screen.
function Shots.targetEnemy(center: CFrame, height: number, fromHero: Vector3, others: Vector3?, compact: boolean?): Pose
	local t = CameraSpec.TargetSingle
	local fill = if compact then t.compact.fill else t.fill
	local headAt = if compact then t.compact.headAt else t.headAt
	local offCenter = if compact then t.compact.offCenter else t.offCenter
	local axis = flatAxis(center.Position, fromHero, center.LookVector) -- toward the hero
	local right = rightOf(axis)
	local floor = center.Position.Y - height / 2
	-- The frame's height at the enemy, so it fills `fill` of it; the distance that gives.
	local frameHeight = height / fill
	local distance = frameHeight / (2 * math.tan(math.rad(t.fov / 2)))
	local toHero = Vector3.new(fromHero.X - center.Position.X, 0, fromHero.Z - center.Position.Z).Magnitude
	if distance > toHero - t.heroClearance then
		-- A tall enemy: stand short of the hero (it would come into the frame) and show the enemy
		-- head and chest, the head still where it would be.
		distance = math.max(4, toHero - t.heroClearance)
		frameHeight = distance * 2 * math.tan(math.rad(t.fov / 2))
	end
	local position = Vector3.new(center.Position.X, floor + height * t.heightAbove, center.Position.Z) + axis * distance + right * t.side
	-- Aim above its head, so the head sits `headAt` down the frame.
	local lookAt = Vector3.new(center.Position.X, floor + height + frameHeight * (headAt - 0.5), center.Position.Z)
	if others then
		-- The camera looks back along -axis, so its right is -right; aim toward the others' side,
		-- which puts the picked enemy on the far side of the frame from them.
		local cameraRight = -right
		local side = if (others - center.Position):Dot(cameraRight) >= 0 then 1 else -1
		lookAt += cameraRight * (side * offCenter * frameHeight * t.aspect)
	end
	return pose(position, lookAt, t.fov, t.roll)
end

-- Picking all enemies: pulled back and up from the hero, framing the squad's middle.
function Shots.targetSquad(heroRoot: CFrame, squadCenter: Vector3): Pose
	local t = CameraSpec.TargetSquad
	local axis = flatAxis(heroRoot.Position, squadCenter, heroRoot.LookVector)
	local position = heroRoot.Position - axis * t.back + Vector3.new(0, t.up, 0)
	return pose(position, squadCenter + Vector3.new(0, t.focusUp, 0), t.fov, t.roll)
end

-- `shot`, re-aimed up or down (from where it stands, toward `point`) so `point` sits `fraction` of
-- the way down the screen: e.g. a dazed head and its stars below the HUD's status block
-- (CameraSpec.Daze). Exact for a pinhole with a vertical field of view (the shot's roll aside):
-- the camera pitches so the point is the right angle below its axis.
function Shots.withPointAt(shot: Pose, point: Vector3, fraction: number): Pose
	local offset = point - shot.position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local distance = flat.Magnitude
	if distance < 1e-3 then
		return shot
	end
	local below = math.atan2(-offset.Y, distance) -- the point's angle below the horizon
	local off = math.atan((2 * fraction - 1) * math.tan(math.rad(shot.fov / 2))) -- below the axis
	local pitch = below - off -- the axis's angle below the horizon
	local lookAt = shot.position + flat.Unit * distance - Vector3.new(0, distance * math.tan(pitch), 0)
	return pose(shot.position, lookAt, shot.fov, shot.roll)
end

-- Picking, or healing, one ally: a chest-up frontal shot (`root` is its hip root, facing the enemies).

function Shots.allyChestUp(root: CFrame): Pose
	local a = CameraSpec.TargetAlly
	local position = root.Position + root.LookVector * a.front + root.RightVector * a.side + Vector3.new(0, a.up, 0)
	return pose(position, root.Position + Vector3.new(0, a.focusUp, 0), a.fov, a.roll)
end

-- A buff or heal on one ally, as it lands: the chest-up shot lifted (the pedestal) with the field
-- of view breathing out, t from 0 to 1.
function Shots.allyLift(root: CFrame, t: number): Pose
	local shot = Shots.allyChestUp(root)
	local cast = CameraSpec.Cast
	local s = smooth(t)
	shot.position += Vector3.new(0, cast.lift * s, 0)
	shot.lookAt += Vector3.new(0, cast.lift * cast.liftLook * s, 0)
	shot.fov = cast.recipientFov + cast.breatheOut * s
	shot.roll = cast.recipientRoll
	return shot
end

-- A party-wide buff or heal: a high-angle three-quarters overhead of the party's middle, from the
-- front-right, pitched down.
function Shots.partyOverhead(center: Vector3, facing: Vector3): Pose
	local p = CameraSpec.Party
	local forward = facing.Unit
	local right = rightOf(forward)
	local pitch = math.rad(p.pitchDown)
	local quarter = (forward + right).Unit
	local position = center + quarter * (p.distance * math.cos(pitch)) + Vector3.new(0, p.distance * math.sin(pitch), 0)
	return pose(position, center + Vector3.new(0, p.focusUp, 0), p.fov, p.roll)
end

-- A buff or heal's invocation: a frontal medium shot of the caster (`root` its body, `height`
-- how tall).
function Shots.casterFrontal(root: CFrame, height: number): Pose
	local cast = CameraSpec.Cast
	local c = cast.caster
	local up = Vector3.new(0, height * c.upPerHeight, 0)
	local position = root.Position + root.LookVector * (c.front + height * c.frontPerHeight) + root.RightVector * c.side + up
	return pose(position, root.Position + up, cast.casterFov, 0)
end

-- An enemy's single-target attack: over the targeted hero's shoulder, looking out at the enemy.
function Shots.incoming(heroRoot: CFrame, enemyCenter: Vector3): Pose
	local e = CameraSpec.EnemyIncoming
	return Shots.overShoulder(heroRoot, enemyCenter, e.pull, 0, e.fov, e.roll)
end

-- An enemy's attack on the whole party: a wide rear-diagonal lineup of the party (`center` their
-- middle, `facing` toward the enemies).
function Shots.partyLineup(center: Vector3, facing: Vector3): Pose
	local l = CameraSpec.EnemyAoE
	local forward = facing.Unit
	local right = rightOf(forward)
	local position = center - forward * l.back + right * l.side + Vector3.new(0, l.up, 0)
	return pose(position, center + forward * l.focusAhead, l.fov, l.roll)
end

-- An acting enemy's wind-up: an offset frontal shot, low, aimed a little past it so it sits
-- right of centre. `root` is its body's middle (facing the party), `height` how tall it stands:
-- the shot backs off with its size, so a 13-stud Elder fits like a 5-stud Sapling.
function Shots.enemyFrontal(root: CFrame, height: number): Pose
	local e = CameraSpec.EnemyWindup
	local floor = root.Position.Y - height / 2
	local position = Vector3.new(root.Position.X, floor + height * e.heightAbove, root.Position.Z)
		+ root.LookVector * (e.front + height * e.frontPerHeight)
		+ root.RightVector * (e.side + height * e.sidePerHeight)
	local lookAt = root.Position + Vector3.new(0, height * e.focusUp, 0) + root.RightVector * e.offset
	return pose(position, lookAt, e.fov, e.roll)
end

-- Front-low on whoever a blow lands on: `root` is its body (a character's hip root, a creature's
-- middle), `height` how tall it is.
function Shots.reaction(root: CFrame, height: number): Pose
	local r = CameraSpec.Reaction
	local position = root.Position + root.LookVector * (r.front + height * r.frontPerHeight) + root.RightVector * r.side + Vector3.new(0, height * r.upPerHeight, 0)
	return pose(position, root.Position + Vector3.new(0, height * r.focusUpPerHeight, 0), r.fov, r.roll)
end

-- The summon beat: well back, up and out to the character's right, clear of the socket where the
-- summon materializes (behind the character, up over its left shoulder), so character and summon
-- are both in frame with the enemies beyond.
function Shots.summon(root: CFrame, focus: Vector3): Pose
	local s = CameraSpec.Summon
	local position = root.Position - root.LookVector * s.back + Vector3.new(0, s.up, 0) + root.RightVector * s.side
	local pair = root.Position + Vector3.new(0, s.focusUp, 0) - root.LookVector * s.pairBack
	return pose(position, pair:Lerp(focus, s.focusBlend), s.fov, s.roll)
end

-- The fixed shot across the stage: the fallback when there is no one to frame.
function Shots.wide(center: Vector3): Pose
	local w = CameraSpec.Wide
	return pose(center + Vector3.new(0, w.up, w.back), center + Vector3.new(0, w.focusUp, 0), w.fov, 0)
end

-- The battle-start sweep: a dolly from behind the enemies' side across the front of the stage to
-- the party's side, t from 0 to 1. `enemyDirection` points from the stage centre toward the enemies.
function Shots.sweep(center: Vector3, enemyDirection: Vector3, t: number): Pose
	local s = smooth(t)
	local sweep = CameraSpec.Sweep
	local side = enemyDirection.Unit
	local front = Vector3.new(-side.Z, 0, side.X) -- across the stage, in front of both sides
	local position = center + side * (sweep.start - sweep.travel * s) + front * (sweep.front - sweep.frontDrift * s) + Vector3.new(0, sweep.up - sweep.upDrift * s, 0)
	return pose(position, center + Vector3.new(0, sweep.focusUp, 0), sweep.fovFrom + (sweep.fovTo - sweep.fovFrom) * s, 0)
end

-- Victory: a slow orbit around the party's `center`, t from 0 to 1; `facing` is the way the party
-- faces (toward where the enemies stood).
function Shots.victory(center: Vector3, facing: Vector3, t: number): Pose
	local s = smooth(t)
	local v = CameraSpec.Victory
	local angle = math.rad(v.startAngle + v.arc * s)
	local forward = facing.Unit
	local right = rightOf(forward)
	local direction = forward * math.cos(angle) + right * math.sin(angle)
	local position = center + direction * v.radius + Vector3.new(0, v.height, 0)
	return pose(position, center + Vector3.new(0, v.focusUp, 0), v.fov + v.fovDrift * s, 0)
end

-- Defeat: the camera stays in front of the fallen party and tilts down to the floor.
function Shots.defeat(center: Vector3, facing: Vector3, t: number): Pose
	local s = smooth(t)
	local d = CameraSpec.Defeat
	local position = center + facing.Unit * d.front + Vector3.new(0, d.up, 0)
	local lookAt = center + Vector3.new(0, d.focusUp - d.tiltDown * s, 0)
	return pose(position, lookAt, d.fov + d.fovDrift * s, 0)
end

return Shots
