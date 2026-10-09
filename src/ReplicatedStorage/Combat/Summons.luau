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

-- Uploaded animation clips for a summon's model, as rbxassetid URLs, keyed by the beat they play.
-- Any can be missing: without an idle it holds the first frame of its attack (or its bind pose),
-- and without an attack or death it just holds its pose for that beat.
export type SummonAnimations = {
	idle: string?, -- loops whenever the model is out
	attack: string?, -- plays over the idle when it performs one of its attacks
	death: string?, -- plays once when it's knocked out, then holds its last frame
	walk: string?, -- uploaded, but not used yet: summons don't walk on the battle stage
}

-- A summon's real 3D model, for the battle stage (BattleView). Without it, the summon shows as a
-- colored block.
export type SummonArt = {
	-- The Model's name in ReplicatedStorage.SummonModels, which Rojo builds from
	-- src/ReplicatedStorage/SummonModels/<model>.rbxm (a model saved from Studio: a skinned rig
	-- with an AnimationController, facing -Z).
	model: string,
	height: number, -- how tall it stands on the battle stage, in studs; the model is scaled to fit
	animations: SummonAnimations,
	attackImpact: number?, -- how far into the attack clip the blow lands, 0 to 1 (default 0.5)
	-- How far its clips lift the whole model off the ground, as a share of its height: some of the
	-- uploaded clips carry a stray offset on the hips. The model stands this much lower to make up
	-- for it. Remove it once the clips are re-exported without the offset.
	groundOffset: number?,
}

export type SummonDef = {
	id: string,
	name: string,
	role: string,
	stats: Stats,
	abilities: { string }, -- ids from Abilities
	brain: EnemyBrain?, -- used when this summon fights on the enemy side
	art: SummonArt?, -- its 3D model and animations; nil shows a colored block
}

local Summons: { [string]: SummonDef } = {
	-- Base: even stats, no glaring weakness. What every new player gets first.
	TungTungSahur = {
		id = "TungTungSahur",
		name = "Tung Tung Sahur",
		role = "Balanced",
		stats = { Strength = 12, Magic = 10, Endurance = 12, Agility = 10, Luck = 10 },
		abilities = { "Strike", "GaleClap" },
		art = {
			model = "TungTungSahur",
			height = 7.5,
			animations = {
				idle = "rbxassetid://92471837974906",
				attack = "rbxassetid://107148770446911",
				death = "rbxassetid://134488455223099",
				walk = "rbxassetid://113311650213737",
			},
			groundOffset = 0.41, -- measured in Studio: its idle lifts it about 3 studs at 7.5 tall
		},
	},

	-- Elder (tank): the toughest, but slow and easy to hit. Steady rather than lucky.
	TungTungElder = {
		id = "TungTungElder",
		name = "Tung Tung Elder",
		role = "Tank",
		stats = { Strength = 11, Magic = 8, Endurance = 17, Agility = 6, Luck = 7 },
		abilities = { "Strike", "KnockOnWood", "Windbreak" },
		-- Its idle, death and walk clips aren't uploaded yet.
		art = {
			model = "TungTungElder",
			height = 9,
			animations = {
				attack = "rbxassetid://82527202850156",
			},
		},
	},

	-- Sapling (damage): hits hardest and crits often, but fragile with a small Mana pool.
	TungTungSapling = {
		id = "TungTungSapling",
		name = "Tung Tung Sapling",
		role = "Damage",
		stats = { Strength = 15, Magic = 6, Endurance = 7, Agility = 13, Luck = 13 },
		abilities = { "Strike", "SplinterSlam" },
		art = {
			model = "TungTungSapling",
			height = 6.5,
			animations = {
				idle = "rbxassetid://80139522491826",
				attack = "rbxassetid://90374935899361",
				death = "rbxassetid://127292475281760",
				walk = "rbxassetid://80507091562272",
			},
			groundOffset = 0.42, -- measured in Studio: its idle lifts it about 2.7 studs at 6.5 tall
		},
	},

	-- Grove-Keeper (support): strong Magic for buffs and heals, weak Strike. Lucky enough to
	-- shrug off ailments while it keeps the party clear of them.
	TungTungGroveKeeper = {
		id = "TungTungGroveKeeper",
		name = "Tung Tung Grove-Keeper",
		role = "Support",
		stats = { Strength = 7, Magic = 16, Endurance = 10, Agility = 11, Luck = 12 },
		abilities = { "Strike", "Tailwind", "SapMend" },
		-- No clips uploaded yet (its attack exists in Studio's animation saves; idle and death don't).
		art = {
			model = "TungTungGroveKeeper",
			height = 8.5,
			animations = {},
		},
	},

	-- Placeholder enemy: a feral Sapling. Hits hard and is a little quicker than a Tung Tung, but
	-- goes down sooner. No art yet, so it's a colored block on the battle stage.
	-- Wild versions of the Tung Tungs: they spar in the university gym. Same models and clips as the
	-- tamed ones, a little weaker, fighting on the enemy side.
	WildTungTungSahur = {
		id = "WildTungTungSahur",
		name = "Wild Tung Tung Sahur",
		role = "Enemy",
		stats = { Strength = 11, Magic = 9, Endurance = 11, Agility = 10, Luck = 9 },
		abilities = { "Strike", "GaleClap" },
		brain = {
			abilityWeights = { Strike = 65, GaleClap = 35 },
			targetWeights = { LowestHP = 55, Random = 45 },
		},
		art = {
			model = "TungTungSahur",
			height = 7.5,
			animations = {
				idle = "rbxassetid://92471837974906",
				attack = "rbxassetid://107148770446911",
				death = "rbxassetid://134488455223099",
				walk = "rbxassetid://113311650213737",
			},
			groundOffset = 0.41,
		},
	},

	WildGroveKeeper = {
		id = "WildGroveKeeper",
		name = "Wild Grove-Keeper",
		role = "Enemy",
		stats = { Strength = 7, Magic = 14, Endurance = 10, Agility = 10, Luck = 11 },
		abilities = { "Strike", "Tailwind", "SapMend" },
		brain = {
			abilityWeights = { Strike = 50, Tailwind = 20, SapMend = 30 },
			targetWeights = { LowestHP = 60, Random = 40 },
		},
		-- Its own clips aren't uploaded yet, so it borrows the Tung Tung Sahur's (same mixamo skeleton,
		-- so they fit). Swap in its own ids once they're published.
		art = {
			model = "TungTungGroveKeeper",
			height = 10,
			animations = {
				idle = "rbxassetid://92471837974906", -- Sahur idle
				walk = "rbxassetid://113311650213737", -- Sahur walk
				death = "rbxassetid://134488455223099", -- Sahur death
			},
			groundOffset = 0.1, -- measured in Studio with the borrowed Sahur idle
		},
	},

	WildElder = {
		id = "WildElder",
		name = "Wild Elder",
		role = "Enemy",
		stats = { Strength = 11, Magic = 7, Endurance = 16, Agility = 5, Luck = 7 },
		abilities = { "Strike", "KnockOnWood", "Windbreak" },
		brain = {
			abilityWeights = { Strike = 45, KnockOnWood = 35, Windbreak = 20 },
			targetWeights = { LowestHP = 50, Random = 50 },
		},
		-- Borrows the Sahur's idle/walk/death until the Elder's own are uploaded (same skeleton).
		art = {
			model = "TungTungElder",
			height = 13,
			animations = {
				idle = "rbxassetid://92471837974906", -- Sahur idle
				walk = "rbxassetid://113311650213737", -- Sahur walk
				death = "rbxassetid://134488455223099", -- Sahur death
				attack = "rbxassetid://82527202850156",
			},
			groundOffset = 0.135, -- measured in Studio with the borrowed Sahur idle
		},
	},

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
		-- A young Tung Tung Sapling: same model and clips, a size smaller.
		art = {
			model = "TungTungSapling",
			height = 5,
			animations = {
				idle = "rbxassetid://80139522491826",
				attack = "rbxassetid://90374935899361",
				death = "rbxassetid://127292475281760",
				walk = "rbxassetid://80507091562272",
			},
			groundOffset = 0.42,
		},
	},
}

return Summons
