--!strict
--[[
	CombatConfig — every combat formula's numbers, in one place.

	These are placeholders: the GDD's Step 11 Q6 ("exact HP/Mana/pip formulas") is still open, so
	change numbers here freely while playtesting. Pips are deliberately absent (Phase 1 avoids the
	pip system). What each status does is in StatusEffects; ability numbers are in Abilities.
]]

local CombatConfig = {
	-- Who fights. Walking into an overworld enemy pulls you and everyone else in the server into
	-- the fight, up to MaxPartySize players. Party summons are dealt to them in that order (whoever
	-- touched the enemy first), so with two players each controls one, and a solo player controls
	-- both. Overworld enemies fight as EnemySummons unless they say otherwise (EnemySpawns). Any ids
	-- from Summons work here.
	MaxPartySize = 2,
	PartySummons = { "TungTungSahur", "TungTungSahur" },
	EnemySummons = { "WildSapling", "WildSapling" },

	-- Pacing, in seconds.
	InitiativeRevealSeconds = 3, -- time to read the initiative rolls (and who struck first) before the first turn
	EnemyThinkSeconds = 1.25, -- small delay so enemy turns are readable
	ResolvePauseSeconds = 1.5, -- after an action, before the next turn opens
	TurnTimeoutSeconds = 30, -- a player who doesn't act in time skips the turn (AFK/disconnect rule)
	ResultScreenSeconds = 8, -- victory/defeat screen before everyone's back in the overworld

	-- Initiative (GDD Step 6): rolled once per battle.
	-- total = random 1..InitiativeDieSides + floor(Agility / AgilityPerInitiativeBonus)
	InitiativeDieSides = 20,
	AgilityPerInitiativeBonus = 2,

	-- Stats -> resources. Endurance is the biggest part of max Health; Magic sets max Mana.
	BaseHP = 40,
	HPPerEndurance = 5,
	BaseMana = 10,
	ManaPerMagic = 1,
	ManaRegenPerTurn = 3, -- restored at the start of each of that summon's turns

	-- Attack damage = (ability power + scaling stat * ratio)
	--   * a random factor within +/- DamageVariance
	--   * CriticalMultiplier on a critical hit
	--   * (1 - the target's damage reduction from Endurance)
	--   * status effects like Guarded
	-- (at least 1). Heals skip the randomness: power + scaling stat * ratio.
	DamageVariance = 0.1,

	-- Endurance: each point cuts incoming damage, physical and magical alike, by this share, up
	-- to MaxDamageReduction. Endurance 10 blocks 20%.
	DamageReductionPerEndurance = 0.02,
	MaxDamageReduction = 0.6,
	-- Statuses like Windbreak's Guarded and Guard's Bracing cut damage further, multiplying with
	-- Endurance rather than adding to it. Whatever stacks, the total never blocks more than this.
	MaxTotalDamageReduction = 0.75,

	-- Accuracy vs evasion, both from Agility: every attack rolls to hit.
	-- hit chance = BaseHitChance + (attacker Agility - target Agility) * HitChancePerAgility,
	-- kept between MinHitChance and MaxHitChance.
	BaseHitChance = 0.9,
	HitChancePerAgility = 0.02,
	MinHitChance = 0.5,
	MaxHitChance = 0.98,

	-- Critical hits, from the attacker's Luck:
	-- crit chance = BaseCritChance + Luck * CritChancePerLuck + the ability's critBonus.
	BaseCritChance = 0.02,
	CritChancePerLuck = 0.01,
	CriticalMultiplier = 1.5,

	-- Status ailments, Luck vs Luck: when an attack with an ailment hits,
	-- chance = the ability's base chance + (attacker Luck - target Luck) * AilmentChancePerLuck,
	-- kept between 0 and MaxAilmentChance.
	AilmentChancePerLuck = 0.02,
	MaxAilmentChance = 0.9,

	-- Guard (GDD Step 6, "Guard — a universal defensive action"): any summon can spend its turn
	-- guarding instead of using an ability. Free, no target; it braces until its own next turn.
	-- It's purely defensive: it never gives Mana back.
	-- While bracing it:
	GuardDamageReduction = 0.3, -- takes this much less damage, multiplied with Endurance's cut:
	-- a maxed-Endurance tank (60%) guarding blocks 1 - 0.4 * 0.7 = 72% in total
	GuardAilmentChanceMultiplier = 0.5, -- ailments are this much as likely to land on it
	-- (critical hits against a guarding summon are always blocked)

	-- Overworld encounters (GDD "Combat philosophy"): walking into an enemy starts a fight, and where
	-- the enemy was, compared with the way the player was facing, decides how the fight opens:
	--   in front (within EncounterFrontAngle of straight ahead): the party struck first, so everyone
	--     in the party takes a bonus turn before round 1
	--   behind (within EncounterBackAngle of straight behind): it caught the player from behind, so
	--     every enemy takes a bonus turn before round 1
	--   anywhere else, from the side: a neutral start
	-- A bonus turn goes in initiative order, and then the fight runs as usual from round 1.
	EncounterFrontAngle = 60, -- degrees either side of straight ahead
	EncounterBackAngle = 60, -- degrees either side of straight behind
	EncounterContactDistance = 4, -- studs between the player and the enemy, center to center, that count as touching
	EncounterCooldownSeconds = 4, -- after a fight, the party gets this long to walk away before another can start
	EnemyRespawnSeconds = 20, -- a beaten overworld enemy comes back after this long
	EnemyPatrolSpeed = 8, -- studs per second (players walk at 16)
	EnemyPatrolPauseSeconds = 1, -- a patrolling enemy stops this long at each point of its route
	EnemyIdleTurnSeconds = 4, -- an idle enemy turns to look another way this often

	-- How many combat log lines clients receive.
	LogLinesShown = 6,
}

return CombatConfig
