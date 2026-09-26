--!strict
--[[
	CombatConfig — every tuning number for the Phase 1 combat prototype, in one place.

	These are placeholders: the GDD's Step 11 Q6 ("exact HP/Mana/pip formulas") is still open, so
	change numbers here freely while playtesting. Pips are deliberately absent (Phase 1 avoids the
	pip system).
]]

local CombatConfig = {
	-- Who fights. Party summons are dealt to the party in join order, so with two players each
	-- controls one, and a solo player controls both.
	MaxPartySize = 2,
	PartySummons = { "TungTungSahur", "TungTungSahur" },
	EnemySummons = { "WildSapling", "WildSapling" },

	-- Pacing, in seconds.
	LobbyCountdownSeconds = 3, -- after everyone is ready, before the battle starts
	InitiativeRevealSeconds = 3, -- time to read the initiative rolls before the first turn
	EnemyThinkSeconds = 1.25, -- small delay so enemy turns are readable
	ResolvePauseSeconds = 1.5, -- after an action, before the next turn opens
	TurnTimeoutSeconds = 30, -- a player who doesn't act in time skips the turn (AFK/disconnect rule)
	ResultScreenSeconds = 8, -- victory/defeat screen before returning to the lobby

	-- Initiative (GDD Step 6): rolled once per battle.
	-- total = random 1..InitiativeDieSides + floor(Agility / AgilityPerInitiativeBonus)
	InitiativeDieSides = 20,
	AgilityPerInitiativeBonus = 2,

	-- Stats -> resources. Max HP comes from Vitality, max Mana from Magic.
	BaseHP = 40,
	HPPerVitality = 5,
	BaseMana = 10,
	ManaPerMagic = 1,
	ManaRegenPerTurn = 3, -- restored at the start of each of that summon's turns

	-- Damage = (ability power + scaling stat * ratio), then randomly scaled by +/- DamageVariance.
	DamageVariance = 0.1,

	-- How many combat log lines clients receive.
	LogLinesShown = 6,
}

return CombatConfig
