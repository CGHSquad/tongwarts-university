--!strict
--[[
	Abilities — combat abilities as data (GDD Step 5), so new ones can be added here without
	touching the combat loop. Every ability targets one enemy that is still standing.

	damage = (power + the summon's scalingStat * statRatio), +/- CombatConfig.DamageVariance
]]

export type StatName = "Strength" | "Magic" | "Vitality" | "Agility"

export type Ability = {
	id: string,
	name: string,
	description: string,
	damageType: "Strike" | "Wind", -- melee type or element; the MVP weakness axis will key off this
	manaCost: number,
	power: number,
	scalingStat: StatName,
	statRatio: number,
}

local Abilities: { [string]: Ability } = {
	-- Tung Tung School's melee type is Strike: blunt force, cheap, reliable.
	Strike = {
		id = "Strike",
		name = "Strike",
		description = "A blunt-force bonk. Cheap and reliable; scales with Strength.",
		damageType = "Strike",
		manaCost = 2,
		power = 8,
		scalingStat = "Strength",
		statRatio = 1,
	},

	-- Tung Tung School's element is Wind: a harder hit that costs a real chunk of Mana.
	GaleClap = {
		id = "GaleClap",
		name = "Gale Clap",
		description = "Claps its wooden hands into a cutting gust. Hits harder; scales with Magic.",
		damageType = "Wind",
		manaCost = 8,
		power = 10,
		scalingStat = "Magic",
		statRatio = 1.5,
	},
}

return Abilities
