--!strict
--[[
	Summons — BrainRot summon definitions (data only).

	Summons carry the combat stats (GDD "Core stats & Mana/Energy", finalized): the player is who
	you are, the summon is what you fight with. Max Health and Mana come from the stats using the
	formulas in CombatConfig.

	The four launch Tung Tung Sahur variants (GDD "Tung Tung Sahur — summon variants") share a
	balanced baseline and each leans into one role. Every one keeps the basic Strike.
]]

export type Stats = {
	Strength: number, -- physical (Strike) damage
	Magic: number, -- elemental (Wind) damage, healing, and max Mana
	Endurance: number, -- cuts incoming damage (physical and magical); the biggest part of max Health
	Agility: number, -- initiative bonus, plus accuracy and evasion
	Luck: number, -- critical hits, and inflicting and resisting ailments
}

-- How an enemy picks its move (GDD Step 6, "Enemy action selection"): weighted choices, no AI
-- trees. Weights are whole numbers and don't need to add up to 100.
export type EnemyBrain = {
	abilityWeights: { [string]: number }, -- only abilities it can use right now are considered
	targetWeights: {
		LowestHP: number, -- go for the most-hurt target
		Random: number, -- hit anyone
	},
}

export type SummonDef = {
	id: string,
	name: string,
	role: string,
	stats: Stats,
	abilities: { string }, -- ids from Abilities
	brain: EnemyBrain?, -- used when this summon fights on the enemy side
}

local Summons: { [string]: SummonDef } = {
	-- Base: even stats, no glaring weakness. What every new player gets first.
	TungTungSahur = {
		id = "TungTungSahur",
		name = "Tung Tung Sahur",
		role = "Balanced",
		stats = { Strength = 12, Magic = 10, Endurance = 12, Agility = 10, Luck = 10 },
		abilities = { "Strike", "GaleClap" },
	},

	-- Elder (tank): the toughest, but slow and easy to hit. Steady rather than lucky.
	TungTungElder = {
		id = "TungTungElder",
		name = "Tung Tung Elder",
		role = "Tank",
		stats = { Strength = 11, Magic = 8, Endurance = 17, Agility = 6, Luck = 7 },
		abilities = { "Strike", "KnockOnWood", "Windbreak" },
	},

	-- Sapling (damage): hits hardest and crits often, but fragile with a small Mana pool.
	TungTungSapling = {
		id = "TungTungSapling",
		name = "Tung Tung Sapling",
		role = "Damage",
		stats = { Strength = 15, Magic = 6, Endurance = 7, Agility = 13, Luck = 13 },
		abilities = { "Strike", "SplinterSlam" },
	},

	-- Grove-Keeper (support): strong Magic for buffs and heals, weak Strike. Lucky enough to
	-- shrug off ailments while it keeps the party clear of them.
	TungTungGroveKeeper = {
		id = "TungTungGroveKeeper",
		name = "Tung Tung Grove-Keeper",
		role = "Support",
		stats = { Strength = 7, Magic = 16, Endurance = 10, Agility = 11, Luck = 12 },
		abilities = { "Strike", "Tailwind", "SapMend" },
	},

	-- Placeholder enemy: a feral Sapling. Hits hard and is a little quicker than a Tung Tung, but
	-- goes down sooner.
	WildSapling = {
		id = "WildSapling",
		name = "Wild Sapling",
		role = "Enemy",
		stats = { Strength = 15, Magic = 8, Endurance = 10, Agility = 12, Luck = 10 },
		abilities = { "Strike", "GaleClap" },
		brain = {
			abilityWeights = { Strike = 70, GaleClap = 30 },
			targetWeights = { LowestHP = 60, Random = 40 },
		},
	},
}

return Summons
