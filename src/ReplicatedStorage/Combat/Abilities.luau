--!strict
--[[
	Abilities — combat abilities as data (GDD Step 5), so new ones can be added here without
	touching the combat loop. Every summon has the basic Strike plus its own abilities (Summons).

	A few moves aren't in any summon's list because they're universal:
		universal = "Everyone"  every summon can use it: Guard
		universal = "Party"     every player's party member can: Attack, their character's own swing
	On the field, a player's character performs the universal moves itself; the summon only flashes
	in for the abilities in its own list (GDD Step 6, "The player character on the field"). Stats,
	HP and Mana still all belong to the summon, so Attack scales with the summon's Strength.

	kind
		"Attack"  hits one enemy. Rolls to hit (Agility vs Agility), then deals
		          power + scalingStat * statRatio, cut by the target's Endurance. Luck can make it a
		          critical hit, and `ailment` can afflict the target (Luck vs Luck).
		"Heal"    restores power + scalingStat * statRatio Health to one ally. `cleanse` also removes
		          ailments.
		"Status"  applies a status (StatusEffects) for `turns` turns.
		"Guard"   the universal defensive action (GDD Step 6): free, no target, and it braces (the
		          Bracing status) until the summon's own next turn.

	targets: what the player picks
		"Enemy"      an enemy that's still standing
		"Ally"       a party member that's still standing, itself included
		"Self"       itself (no pick)
		"AllAllies"  every party member still standing (no pick)

	The formulas and their numbers live in CombatConfig.
]]

export type StatName = "Strength" | "Magic" | "Endurance" | "Agility" | "Luck"
export type Targeting = "Enemy" | "Ally" | "Self" | "AllAllies"
export type Universal = "Everyone" | "Party" -- who has it without it being in their summon's list

export type AilmentChance = {
	status: string, -- an Ailment from StatusEffects
	chance: number, -- base chance on a hit, before Luck
	turns: number,
}

export type AttackAbility = {
	kind: "Attack",
	id: string,
	name: string,
	description: string,
	targets: Targeting,
	manaCost: number,
	universal: Universal?,
	damageType: "Strike" | "Wind", -- melee type or element; the MVP weakness axis will key off this
	power: number,
	scalingStat: StatName,
	statRatio: number,
	critBonus: number?, -- added to the critical hit chance
	ailment: AilmentChance?,
}

export type HealAbility = {
	kind: "Heal",
	id: string,
	name: string,
	description: string,
	targets: Targeting,
	manaCost: number,
	universal: Universal?,
	power: number,
	scalingStat: StatName,
	statRatio: number,
	cleanse: boolean?,
}

export type StatusAbility = {
	kind: "Status",
	id: string,
	name: string,
	description: string,
	targets: Targeting,
	manaCost: number,
	universal: Universal?,
	status: string, -- a StatusEffects entry
	turns: number,
}

export type GuardAbility = {
	kind: "Guard",
	id: string,
	name: string,
	description: string,
	targets: Targeting,
	manaCost: number,
	universal: Universal?,
	status: string,
	turns: number,
}

export type Ability = AttackAbility | HealAbility | StatusAbility | GuardAbility

local Abilities: { [string]: Ability } = {
	-- A player character's own basic attack (GDD Step 6, "The player character on the field"): free,
	-- and it scales with the summon's Strength until weapons exist to change it. Weaker than a
	-- summon's Strike, so it's for when you'd rather not spend Mana.
	Attack = {
		kind = "Attack",
		id = "Attack",
		name = "Attack",
		description = "Your character's own swing. Free, but weaker than a summon's Strike; scales with Strength.",
		targets = "Enemy",
		manaCost = 0,
		universal = "Party",
		damageType = "Strike",
		power = 4,
		scalingStat = "Strength",
		statRatio = 1,
	},

	-- Every summon's basic attack. Tung Tung School's melee type is Strike: cheap and reliable.
	Strike = {
		kind = "Attack",
		id = "Strike",
		name = "Strike",
		description = "A blunt-force bonk. Cheap and reliable; scales with Strength.",
		targets = "Enemy",
		manaCost = 2,
		damageType = "Strike",
		power = 8,
		scalingStat = "Strength",
		statRatio = 1,
	},

	-- Base: the school's Wind skill. The clap's gust hits harder and can leave the target dazed.
	GaleClap = {
		kind = "Attack",
		id = "GaleClap",
		name = "Gale Clap",
		description = "Claps its wooden hands into a cutting gust. Scales with Magic; can daze.",
		targets = "Enemy",
		manaCost = 8,
		damageType = "Wind",
		power = 10,
		scalingStat = "Magic",
		statRatio = 1.5,
		ailment = { status = "Dazed", chance = 0.2, turns = 2 },
	},

	-- Elder (tank): pull the enemies' attacks onto itself, then weather them.
	KnockOnWood = {
		kind = "Status",
		id = "KnockOnWood",
		name = "Knock on Wood",
		description = "Raps its trunk so loudly that every enemy has to target it.",
		targets = "Self",
		manaCost = 4,
		status = "Taunting",
		turns = 3,
	},

	Windbreak = {
		kind = "Status",
		id = "Windbreak",
		name = "Windbreak",
		description = "Wraps itself in a wall of wind to take less damage.",
		targets = "Self",
		manaCost = 5,
		status = "Guarded",
		turns = 3,
	},

	-- Sapling (damage): one big, expensive hit.
	SplinterSlam = {
		kind = "Attack",
		id = "SplinterSlam",
		name = "Splinter Slam",
		description = "A reckless full-body slam. Huge damage and a better critical chance.",
		targets = "Enemy",
		manaCost = 10,
		damageType = "Strike",
		power = 12,
		scalingStat = "Strength",
		statRatio = 1.3,
		critBonus = 0.1,
	},

	-- Grove-Keeper (support): buff the whole party, mend whoever needs it.
	Tailwind = {
		kind = "Status",
		id = "Tailwind",
		name = "Tailwind",
		description = "A helpful breeze: the whole party gets more accurate and harder to hit.",
		targets = "AllAllies",
		manaCost = 8,
		status = "Tailwind",
		turns = 3,
	},

	SapMend = {
		kind = "Heal",
		id = "SapMend",
		name = "Sap Mend",
		description = "Mends an ally with healing sap and clears their ailments. Scales with Magic.",
		targets = "Ally",
		manaCost = 6,
		power = 10,
		scalingStat = "Magic",
		statRatio = 1,
		cleanse = true,
	},

	-- Every summon can Guard instead of using an ability. Its numbers are in CombatConfig.
	Guard = {
		kind = "Guard",
		id = "Guard",
		name = "Guard",
		description = "Braces until its next turn: less damage, no critical hits, resists ailments, "
			.. "and some Mana back if it gets attacked.",
		targets = "Self",
		manaCost = 0,
		universal = "Everyone",
		status = "Bracing",
		turns = 1,
	},
}

return Abilities
