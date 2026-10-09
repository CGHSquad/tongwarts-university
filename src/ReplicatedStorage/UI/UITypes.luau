--!strict
--[[
	UITypes — the view-models the UI renders (docs/ui/UI_HANDOFF.md section 6, reconciled by
	section 16 and docs/ui/M0_REPORT.md).

	These are shapes the client builds from BattleTypes snapshots (and, until the server has them,
	from MockData). The server's types stay the single source of truth: nothing here is sent over
	the network, and the UI never computes an outcome from them. Names are deliberately different
	from BattleTypes' (HudParticipant, not Participant) so the two can't be confused.
]]

export type Id = string

export type Resource = { current: number, max: number }

-- MVP affinity tiers are Weak / Neutral / Resist (GDD Step 6). Null is typed for later; nothing
-- emits it yet. Unknown is for an enemy whose weakness the player hasn't learned.
export type AffinityState = "Weak" | "Neutral" | "Resist" | "Null" | "Unknown"

export type AffinityEntry = { elementId: Id, iconKey: string, state: AffinityState }

export type HudParticipant = {
	id: Id,
	side: "Party" | "Enemy",
	slot: number,
	name: string,
	summonId: string,
	ownerUserId: number?, -- nil for an enemy
	ownerName: string?,
	isLocal: boolean, -- controlled by this client (a solo player controls every party member)
	hp: Resource,
	mana: Resource,
	statuses: { { id: string, name: string, kind: "Ailment" | "Buff", turnsLeft: number } },
	knockedOut: boolean, -- HP 0, out of the fight. Not Persona's Down (R7).
	left: boolean,
	isDown: boolean, -- Persona-style Down. Always false while Flags.DownSystem is off.
	knownWeaknesses: { Id }, -- empty until the type chart exists (R8)
	initiative: { roll: number, bonus: number, total: number }?,
	abilityIds: { Id }, -- the summon's own abilities, in kit order: the Spell list
}

export type AbilityRow = {
	id: Id,
	name: string,
	description: string,
	iconKey: string,
	elementId: Id?, -- the ability's damageType, when it has one
	cost: { mana: number, pips: number? },
	canAfford: boolean, -- a comparison of snapshot numbers; the server still decides
	hitsKnownWeakness: boolean, -- always false while Flags.ShowAffinities is off
	needsTarget: "None" | "Enemy" | "Ally" | "AllAllies",
	locked: boolean, -- Skill menu only
}

export type CommandId = "Attack" | "Spell" | "Item" | "Guard" | "Pass"

export type CommandView = { id: CommandId, enabled: boolean }

export type HudPhase = "Setup" | "Input" | "Resolve" | "Reward"

export type HudBattle = {
	battleId: number,
	rosterKey: string, -- battleId plus every participant id; per-participant widgets rebuild when it changes
	phase: HudPhase,
	round: number, -- 0 during the opening bonus turn
	turnNumber: number,
	turnQueue: { Id },
	activeId: Id?,
	participants: { HudParticipant }, -- in turnQueue order is not guaranteed; use byId
	byId: { [Id]: HudParticipant },
	localActorId: Id?, -- the participant this client must act for right now, if any
	opening: ("Party" | "Enemy")?,
	startedBy: string?,
	winner: ("Party" | "Enemy")?,
	turnDeadline: number?, -- server clock
	overworldReturnAt: number?, -- server clock
	lastActionSequence: number,
	lastLogLine: string?, -- the server's latest log line, shown while an action resolves
	recentLog: { string }, -- the last few log lines, oldest first: the recent-actions feed
	allEnemiesDown: boolean, -- always false while Flags.DownSystem is off
}

export type PartyMemberView = {
	userId: number,
	name: string,
	level: number?,
	isLeader: boolean,
	hp: Resource,
	mana: Resource,
	summonName: string,
	roleTag: string?,
}

-- S6 runs on mock rewards until the server has a reward payload (R10, Q3).
export type RewardItem = { id: Id, name: string, iconKey: string, count: number }
export type RewardMember = { userId: number, name: string, level: number, expGained: number, leveledUp: boolean, newLevel: number }
export type RewardView = {
	exp: number,
	currency: number,
	items: { RewardItem },
	members: { RewardMember },
}

export type StatEntry = { id: "Strength" | "Magic" | "Endurance" | "Agility" | "Luck", value: number, max: number }

return {}
