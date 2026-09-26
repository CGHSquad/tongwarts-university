--!strict
--[[
	Summons — BrainRot summon definitions (data only).

	Summons carry the combat stats (GDD "Core stats & Mana/Energy"): the player is who you are, the
	summon is what you fight with. Only the stats this prototype uses are listed; Intelligence and
	Luck join when an ability needs them. Max HP and Mana are derived from the stats using the
	formulas in CombatConfig. Phase 1 caps the roster at two summon types.
]]

export type Stats = {
	Strength: number, -- Strike damage
	Magic: number, -- Wind damage and max Mana
	Vitality: number, -- max HP
	Agility: number, -- initiative bonus
}

-- How an enemy picks its move (GDD Step 6, "Enemy action selection"): weighted choices, no AI
-- trees. Weights are whole numbers and don't need to add up to 100.
export type EnemyBrain = {
	abilityWeights: { [string]: number }, -- only abilities it can currently afford are considered
	targetWeights: {
		LowestHP: number, -- go for the most-hurt party summon
		Random: number, -- hit anyone
	},
}

export type SummonDef = {
	id: string,
	name: string,
	stats: Stats,
	abilities: { string }, -- ids from Abilities
	brain: EnemyBrain?, -- used when this summon fights on the enemy side
}

local Summons: { [string]: SummonDef } = {
	-- The launch starter: even stats, no glaring weakness.
	TungTungSahur = {
		id = "TungTungSahur",
		name = "Tung Tung Sahur",
		stats = { Strength = 12, Magic = 10, Vitality = 12, Agility = 10 },
		abilities = { "Strike", "GaleClap" },
	},

	-- Placeholder enemy: a feral Sapling (the glass-cannon variant). Hits harder than a Tung Tung
	-- and is fast enough to often win initiative, but goes down quicker: focus fire and well-timed
	-- Gale Claps win the fight.
	WildSapling = {
		id = "WildSapling",
		name = "Wild Sapling",
		stats = { Strength = 17, Magic = 8, Vitality = 10, Agility = 14 },
		abilities = { "Strike", "GaleClap" },
		brain = {
			abilityWeights = { Strike = 70, GaleClap = 30 },
			targetWeights = { LowestHP = 60, Random = 40 },
		},
	},
}

return Summons
