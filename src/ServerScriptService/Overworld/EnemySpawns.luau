--!strict
--[[
	EnemySpawns — the enemies out in the overworld, as data. Each one is a group: walk into it
	and you fight its `enemies` (Overworld starts the battle).

		behavior "Patrol"  walks `path` point to point, looping back to the first, and faces the
		                   way it's walking
		         "Idle"    stands on the first point of `path` and turns to look around now and then

	Points are on the baseplate, whose top is at Y = 0, so only X and Z matter. The spawn point is
	at the middle (0, 0), so keep enemies a good distance from it. How fast they move and how often
	they turn is in CombatConfig.
]]

export type Behavior = "Patrol" | "Idle"

export type EnemySpawn = {
	id: string,
	name: string, -- shown over its head
	behavior: Behavior,
	path: { Vector3 },
	enemies: { string }?, -- who you fight (Summons ids); nil means CombatConfig.EnemySummons
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
}

return EnemySpawns
