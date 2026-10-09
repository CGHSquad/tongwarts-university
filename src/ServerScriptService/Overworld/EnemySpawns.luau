--!strict
--[[
	EnemySpawns — the enemies out in the overworld, as data. Each one is a group: walk into it
	and you fight its `enemies` (Overworld starts the battle).

		behavior "Patrol"  walks `path` point to point, looping back to the first, and faces the
		                   way it's walking
		         "Idle"    stands on the first point of `path` and turns to look around now and then

	A point's Y is the height of the ground it stands on: 0 on the overworld baseplate. The overworld
	spawn point is at the middle (0, 0), so keep enemies a good distance from it. The university
	gym's wild Tung Tungs stand on its sparring stage up on the mountain. How fast they move and how often
	they turn is in CombatConfig.
]]

export type Behavior = "Patrol" | "Idle"

export type EnemySpawn = {
	id: string,
	name: string, -- shown over its head
	behavior: Behavior,
	path: { Vector3 },
	enemies: { string }?, -- who you fight (Summons ids); nil means CombatConfig.EnemySummons
	look: string?, -- whose 3D model it wears out in the world (a Summons id with art); nil = Tung Tung Sapling
	height: number?, -- how tall that model stands, in studs (default 4.2, kid-sized)
	reach: number?, -- how close (across the ground) counts as touching it; default CombatConfig.EncounterContactDistance
	facing: Vector3?, -- Idle only: stand still facing this direction instead of looking around
}

local EnemySpawns: { EnemySpawn } = {
	{
		id = "EastPatrol",
		name = "Wild Saplings",
		behavior = "Patrol",
		path = { Vector3.new(40, 0, -30), Vector3.new(90, 0, -30), Vector3.new(90, 0, 30), Vector3.new(40, 0, 30) },
	},
	{
		id = "WestPatrol",
		name = "Wild Saplings",
		behavior = "Patrol",
		path = { Vector3.new(-50, 0, -60), Vector3.new(-50, 0, 60) },
	},
	{
		id = "NorthLookout",
		name = "Wild Saplings",
		behavior = "Idle",
		path = { Vector3.new(0, 0, -80) },
	},
	{
		id = "SouthLookout",
		name = "Wild Saplings",
		behavior = "Idle",
		path = { Vector3.new(-30, 0, 90) },
	},
	-- University gym: one wild version of every Tung Tung waits on the sparring stage, each its own
	-- size. Walk into one to spar 1-on-1. (Ground here is the gym's sparring mat, y = 403.5.) They stand still
	-- facing the gym's doors (south, +Z) instead of looking around.
	{
		id = "GymWildSapling",
		name = "Wild Sapling",
		behavior = "Idle",
		path = { Vector3.new(4182.0, 403.5, -56.0) },
		enemies = { "WildSapling" },
		look = "TungTungSapling",
		height = 4.2,
		reach = 4,
		facing = Vector3.new(0, 0, 1),
	},
	{
		id = "GymWildSahur",
		name = "Wild Tung Tung Sahur",
		behavior = "Idle",
		path = { Vector3.new(4200.0, 403.5, -56.0) },
		enemies = { "WildTungTungSahur" },
		look = "WildTungTungSahur",
		height = 6.2,
		reach = 5,
		facing = Vector3.new(0, 0, 1),
	},
	{
		id = "GymWildGroveKeeper",
		name = "Wild Grove-Keeper",
		behavior = "Idle",
		path = { Vector3.new(4218.0, 403.5, -56.0) },
		enemies = { "WildGroveKeeper" },
		look = "WildGroveKeeper",
		height = 9,
		reach = 6.5,
		facing = Vector3.new(0, 0, 1),
	},
	{
		id = "GymWildElder",
		name = "Wild Elder",
		behavior = "Idle",
		path = { Vector3.new(4236.0, 403.5, -56.0) },
		enemies = { "WildElder" },
		look = "WildElder",
		height = 16,
		reach = 9,
		facing = Vector3.new(0, 0, 1),
	},

	-- Tralala Tralalero University gym (underwater): the same sparring partners on its round arena
	-- (arena floor y = 102.3), facing the gym doors.
	{
		id = "TralalaGymWildSapling",
		name = "Wild Sapling",
		behavior = "Idle",
		path = { Vector3.new(-3729.8, 102.3, 191.2) },
		enemies = { "WildSapling" },
		look = "TungTungSapling",
		height = 4.2,
		reach = 4,
		facing = Vector3.new(-0.932, 0, -0.362),
	},
	{
		id = "TralalaGymWildSahur",
		name = "Wild Tung Tung Sahur",
		behavior = "Idle",
		path = { Vector3.new(-3726.2, 102.3, 181.8) },
		enemies = { "WildTungTungSahur" },
		look = "WildTungTungSahur",
		height = 6.2,
		reach = 5,
		facing = Vector3.new(-0.932, 0, -0.362),
	},
	{
		id = "TralalaGymWildGroveKeeper",
		name = "Wild Grove-Keeper",
		behavior = "Idle",
		path = { Vector3.new(-3722.6, 102.3, 172.5) },
		enemies = { "WildGroveKeeper" },
		look = "WildGroveKeeper",
		height = 9,
		reach = 6.5,
		facing = Vector3.new(-0.932, 0, -0.362),
	},
	{
		id = "TralalaGymWildElder",
		name = "Wild Elder",
		behavior = "Idle",
		path = { Vector3.new(-3719.0, 102.3, 163.2) },
		enemies = { "WildElder" },
		look = "WildElder",
		height = 16,
		reach = 9,
		facing = Vector3.new(-0.932, 0, -0.362),
	},
	-- Cappuccino Assassino University arena gym (lava campus): the same sparring partners on the
	-- coffee-ring mat (mat top y = 502.2), facing the torii entrance.
	{
		id = "CappuccinoGymWildSapling",
		name = "Wild Sapling",
		behavior = "Idle",
		path = { Vector3.new(317.3, 502.2, 4493.7) },
		enemies = { "WildSapling" },
		look = "TungTungSapling",
		height = 4.2,
		reach = 4,
		facing = Vector3.new(-0.974, 0, 0.228),
	},
	{
		id = "CappuccinoGymWildSahur",
		name = "Wild Tung Tung Sahur",
		behavior = "Idle",
		path = { Vector3.new(315.0, 502.2, 4484.0) },
		enemies = { "WildTungTungSahur" },
		look = "WildTungTungSahur",
		height = 6.2,
		reach = 5,
		facing = Vector3.new(-0.974, 0, 0.228),
	},
	{
		id = "CappuccinoGymWildGroveKeeper",
		name = "Wild Grove-Keeper",
		behavior = "Idle",
		path = { Vector3.new(312.8, 502.2, 4474.2) },
		enemies = { "WildGroveKeeper" },
		look = "WildGroveKeeper",
		height = 9,
		reach = 6.5,
		facing = Vector3.new(-0.974, 0, 0.228),
	},
	{
		id = "CappuccinoGymWildElder",
		name = "Wild Elder",
		behavior = "Idle",
		path = { Vector3.new(310.3, 502.2, 4463.5) },
		enemies = { "WildElder" },
		look = "WildElder",
		height = 16,
		reach = 9,
		facing = Vector3.new(-0.974, 0, 0.228),
	},
	-- Cappuccino Ballerina Academy Grand Theatre gym (snowy mountainside): the same sparring partners on the
	-- stage (stage top y = 599.3), facing the theatre doors.
	{
		id = "BallerinaGymWildSapling",
		name = "Wild Sapling",
		behavior = "Idle",
		path = { Vector3.new(-4118.0, 599.3, 4479.8) },
		enemies = { "WildSapling" },
		look = "TungTungSapling",
		height = 4.2,
		reach = 4,
		facing = Vector3.new(-0.811, 0, 0.585),
	},
	{
		id = "BallerinaGymWildSahur",
		name = "Wild Tung Tung Sahur",
		behavior = "Idle",
		path = { Vector3.new(-4123.8, 599.3, 4471.7) },
		enemies = { "WildTungTungSahur" },
		look = "WildTungTungSahur",
		height = 6.2,
		reach = 5,
		facing = Vector3.new(-0.811, 0, 0.585),
	},
	{
		id = "BallerinaGymWildGroveKeeper",
		name = "Wild Grove-Keeper",
		behavior = "Idle",
		path = { Vector3.new(-4129.7, 599.3, 4463.6) },
		enemies = { "WildGroveKeeper" },
		look = "WildGroveKeeper",
		height = 9,
		reach = 6.5,
		facing = Vector3.new(-0.811, 0, 0.585),
	},
	{
		id = "BallerinaGymWildElder",
		name = "Wild Elder",
		behavior = "Idle",
		path = { Vector3.new(-4136.1, 599.3, 4454.7) },
		enemies = { "WildElder" },
		look = "WildElder",
		height = 16,
		reach = 9,
		facing = Vector3.new(-0.811, 0, 0.585),
	},
}

return EnemySpawns
