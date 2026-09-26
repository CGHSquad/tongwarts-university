--!strict
--[[
	BattleTypes — the shape of the state the server sends to clients (the StateUpdate RemoteEvent).

	The server builds these snapshots and clients only render them: the UI never keeps its own copy
	of the truth (GDD Step 5, "UI systems"). This module only exports types.

	Times are server clock values (workspace:GetServerTimeNow()), which clients can compare against
	their own GetServerTimeNow() to show countdowns.
]]

export type Side = "Party" | "Enemy"

-- GDD Step 6 phases, plus "setup": the pause between the initiative roll and the first turn.
export type Phase = "setup" | "input" | "resolve" | "reward"

export type ParticipantStatus = "Active" | "KnockedOut" | "Left"

export type InitiativeRoll = {
	roll: number, -- the random part
	bonus: number, -- the Agility-scaled modifier
	total: number, -- roll + bonus; the turn order sorts by this
}

export type ParticipantState = {
	id: string, -- "P1", "P2" for the party, "E1", "E2" for enemies
	side: Side,
	slot: number, -- 1-based position within its side
	name: string,
	summonId: string,
	ownerUserId: number?, -- nil for enemies (the server's AI controls them)
	ownerName: string?,
	hp: number,
	maxHp: number,
	mana: number,
	maxMana: number,
	status: ParticipantStatus,
	abilities: { string },
	initiative: InitiativeRoll?,
}

export type ActionRecord = {
	sequence: number, -- increases with every resolved action in a battle
	actorId: string,
	targetId: string,
	abilityId: string,
	damage: number,
	knockedOut: boolean,
}

export type BattleState = {
	battleId: number,
	phase: Phase,
	round: number,
	turnNumber: number,
	currentActorId: string?,
	turnQueue: { string }, -- participant ids in initiative order, fixed for the whole battle
	participants: { ParticipantState },
	winner: Side?,
	lastAction: ActionRecord?,
	log: { string },
	turnDeadline: number?, -- when the current player's turn auto-passes
	lobbyReturnAt: number?, -- when the result screen closes
}

export type LobbyMember = {
	userId: number,
	name: string,
	ready: boolean,
}

export type LobbyState = {
	members: { LobbyMember },
	maxPartySize: number,
	countdownEndsAt: number?, -- set while the pre-battle countdown runs
}

export type Snapshot = {
	lobby: LobbyState,
	battle: BattleState?, -- nil when no battle is running
}

return {}
