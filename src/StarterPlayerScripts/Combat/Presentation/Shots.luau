--!strict
--[[
	Shots — where the battle camera stands for each beat, as pure CFrame math (no Instances, so
	the headless tests can check the same numbers). A Pose is a position, a point to look at and a
	field of view; BattleCamera moves between poses. Stage directions: a party member's spot faces
	the enemies, an enemy's spot faces the party, so every shot is built from a spot's own vectors
	and works on either side.

	The shots (C0 report, section 3):
		overShoulder   low, behind the acting party member's right shoulder: it sits lower-left,
		               the enemies centre-right, clear of the HUD's columns
		summon         the same, pulled back and out so the summon materializing behind the
		               character fits in frame
		enemyFrontal   an offset frontal shot of the acting enemy, from the party's side
		reaction       front-low on whoever a blow lands on
		sweep          the battle-start dolly from behind the enemies across to behind the party
		victory        a slow orbit around the party; defeat tilts down to the floor
		wide           the old fixed shot across the stage, the fallback when there is no actor
]]

local Shots = {}

export type Pose = {
	position: Vector3,
	lookAt: Vector3,
	fov: number,
}

Shots.FOV = 60
-- Over the shoulder: measured against the HUD's columns on a phone (844x390) and a 16:9 desktop,
-- the acting character's head lands around a quarter of the way across, the enemies between 0.4
-- and 0.6, their plates clear of each other and (just) of the party cards' column.
Shots.OTS = { back = 8.5, up = 3, side = 2.8, focusUp = 2, focusBlend = 0.65, aimRight = 2.5 }
Shots.ENEMY = { front = 5, side = 3, up = 0.15, focusUp = 0.1, offset = 1.5, fov = 58 }
Shots.WIDE = { back = 40, up = 20, focusUp = 3 }

local function pose(position: Vector3, lookAt: Vector3, fov: number): Pose
	return { position = position, lookAt = lookAt, fov = fov }
end

local function smooth(t: number): number
	local x = math.clamp(t, 0, 1)
	return x * x * (3 - 2 * x)
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

-- Behind a party member's right shoulder (`root` is where its character stands, facing the
-- enemies), looking between its head and `focus` (the enemies). `pullBack` > 1 stands further
-- off: a teammate's turn, or the summon beat.
function Shots.overShoulder(root: CFrame, focus: Vector3, pullBack: number?): Pose
	local pull = pullBack or 1
	local ots = Shots.OTS
	local position = root.Position - root.LookVector * (ots.back * pull) + Vector3.new(0, ots.up * pull, 0) + root.RightVector * (ots.side * pull)
	local head = root.Position + Vector3.new(0, ots.focusUp, 0)
	-- Aimed a little to the right of the line to the enemies, so the character sits left of
	-- centre from either party slot (the slot nearer the enemies would otherwise be centred).
	return pose(position, head:Lerp(focus, ots.focusBlend) + root.RightVector * ots.aimRight, Shots.FOV)
end

-- The summon beat: well back, up and out to the character's right, clear of the socket where the
-- summon materializes (behind the character, up over its left shoulder), so character and summon
-- are both in frame with the enemies beyond.
-- (A Tung Tung summon with its bat spans up to about 13 studs mid-swing: measured on a phone at
-- back 11 / up 6 its head touched the top edge and its feet were cut, hence the extra distance.)
Shots.SUMMON = { back = 15, up = 7.5, side = 7, focusUp = 4.5, focusBlend = 0.3 }
function Shots.summon(root: CFrame, focus: Vector3): Pose
	local s = Shots.SUMMON
	local position = root.Position - root.LookVector * s.back + Vector3.new(0, s.up, 0) + root.RightVector * s.side
	local pair = root.Position + Vector3.new(0, s.focusUp, 0) - root.LookVector * 1
	return pose(position, pair:Lerp(focus, s.focusBlend), Shots.FOV)
end

-- An offset frontal shot of an enemy: in front of it (on the party's side), off to one side, a
-- little above its middle and aimed a little past it so it sits right of centre. `root` is its
-- body's centre (where an enemy's creature stands), `height` how tall it is: the shot backs off
-- with its size, so a 13-stud Elder fits the frame like a 5-stud Sapling.
function Shots.enemyFrontal(root: CFrame, height: number): Pose
	local e = Shots.ENEMY
	local position = root.Position + root.LookVector * (e.front + height * 0.7) + root.RightVector * (e.side + height * 0.3) + Vector3.new(0, height * e.up, 0)
	local lookAt = root.Position + Vector3.new(0, height * e.focusUp, 0) + root.RightVector * e.offset
	return pose(position, lookAt, e.fov)
end

-- Front-low on whoever a blow lands on: `root` is its body (a character's hip root, a creature's
-- centre), `height` how tall it is.
function Shots.reaction(root: CFrame, height: number): Pose
	local position = root.Position + root.LookVector * (5 + height * 0.6) + root.RightVector * 2 + Vector3.new(0, height * 0.25, 0)
	return pose(position, root.Position + Vector3.new(0, height * 0.15, 0), 56)
end

-- The old fixed shot across the stage: party on the left, enemies on the right.
function Shots.wide(center: Vector3): Pose
	local w = Shots.WIDE
	return pose(center + Vector3.new(0, w.up, w.back), center + Vector3.new(0, w.focusUp, 0), Shots.FOV)
end

-- The battle-start sweep: a dolly from behind the enemies' side across the front of the stage to
-- the party's side, t from 0 to 1. `enemyDirection` points from the stage centre toward the enemies.
function Shots.sweep(center: Vector3, enemyDirection: Vector3, t: number): Pose
	local s = smooth(t)
	local side = enemyDirection.Unit
	local front = Vector3.new(-side.Z, 0, side.X) -- across the stage, in front of both sides
	local position = center + side * (24 - 48 * s) + front * (30 - 2 * s) + Vector3.new(0, 7 - 2 * s, 0)
	return pose(position, center + Vector3.new(0, 3, 0), 62 - 4 * s)
end

-- Victory: a slow orbit around the party's `center`, t from 0 to 1; `facing` is the way the party
-- faces (toward where the enemies stood).
function Shots.victory(center: Vector3, facing: Vector3, t: number): Pose
	local s = smooth(t)
	local angle = math.rad(-35 + 60 * s)
	local forward = facing.Unit
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local radius = 17
	local direction = forward * math.cos(angle) + right * math.sin(angle)
	local position = center + direction * radius + Vector3.new(0, 6.5, 0)
	return pose(position, center + Vector3.new(0, 3, 0), 54 + 4 * s)
end

-- Defeat: the camera stays in front of the fallen party and tilts down to the floor.
function Shots.defeat(center: Vector3, facing: Vector3, t: number): Pose
	local s = smooth(t)
	local position = center + facing.Unit * 12 + Vector3.new(0, 4, 0)
	local lookAt = center + Vector3.new(0, 3 - 4 * s, 0)
	return pose(position, lookAt, 56 - 8 * s)
end

return Shots
