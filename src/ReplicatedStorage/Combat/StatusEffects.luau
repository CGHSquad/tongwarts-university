--!strict
--[[
	StatusEffects — what each status does, as data (GDD Step 5: status effects are data that the
	BattleSession ticks each turn). Abilities apply them for a number of turns (see Abilities).

	A status counts down at the start of each of its summon's own turns and ends at 0, so
	"2 turns" lasts until the start of that summon's second turn from now. Applying a status the
	summon already has refreshes it rather than stacking.
]]

local CombatConfig = require(script.Parent:WaitForChild("CombatConfig"))

export type StatusKind =
	"Ailment" -- harmful: Luck resists it, and cleansing removes it
	| "Buff"

export type StatusDef = {
	id: string,
	name: string,
	kind: StatusKind,
	description: string,
	skipTurnChance: number?, -- chance to lose each turn it's active for
	damageTakenMultiplier: number?, -- incoming damage is multiplied by this
	agilityBonus: number?, -- extra Agility for accuracy and evasion (never re-sorts turn order)
	drawsAttacks: boolean?, -- enemies must target this summon
	blocksCriticals: boolean?, -- attacks against this summon can't be critical hits
	ailmentChanceMultiplier: number?, -- ailments' chance to land on this summon is multiplied by this
	manaWhenAttacked: number?, -- Mana it gains, once, the first time it's attacked while this lasts
}

local StatusEffects: { [string]: StatusDef } = {
	-- The only ailment so far: a stand-in until the MVP's real ailments (GDD Step 6) are designed.
	Dazed = {
		id = "Dazed",
		name = "Dazed",
		kind = "Ailment",
		description = "may lose its turn",
		skipTurnChance = 0.5,
	},

	Taunting = {
		id = "Taunting",
		name = "Taunting",
		kind = "Buff",
		description = "enemies must target it",
		drawsAttacks = true,
	},

	Guarded = {
		id = "Guarded",
		name = "Guarded",
		kind = "Buff",
		description = "takes less damage",
		damageTakenMultiplier = 0.6,
	},

	Tailwind = {
		id = "Tailwind",
		name = "Tailwind",
		kind = "Buff",
		description = "more accurate and harder to hit",
		agilityBonus = 4,
	},

	-- From the universal Guard action. Separate from Windbreak's Guarded, so both can be up at
	-- once. Its numbers live in CombatConfig with the rest of Guard's.
	Bracing = {
		id = "Bracing",
		name = "Bracing",
		kind = "Buff",
		description = "guarding: less damage, no critical hits, resists ailments",
		damageTakenMultiplier = 1 - CombatConfig.GuardDamageReduction,
		blocksCriticals = true,
		ailmentChanceMultiplier = CombatConfig.GuardAilmentChanceMultiplier,
		manaWhenAttacked = CombatConfig.GuardManaBonus,
	},
}

return StatusEffects
