--!strict
--[[
	BattleSession — the rules and state of one fight. Server-only (GDD Steps 5 and 6).

	Pure Luau: no Instances, RemoteEvents or task scheduling. BattleDirector owns time and
	networking; this module owns the rules, so every combat rule lives in one place. It sits in
	ServerScriptService, which never replicates, so clients can't even read it.

	A fight, as BattleDirector drives it:
		session:rollInitiative()           -- once per battle; builds turnQueue          "setup"
		session:beginNextTurn()            -- the next active participant's turn opens   "input"
		session:submitAction(userId, ...)  -- a player's request: validated, resolved    "resolve"
		session:performEnemyAction(...)    -- same validation and resolution for the AI  "resolve"
		session:passTurn(reason)           -- AFK timeout, or nothing affordable         "resolve"
		...back to beginNextTurn, until one side has no one left standing              "reward"
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Abilities = require(ReplicatedStorage.Combat.Abilities)
local BattleTypes = require(ReplicatedStorage.Combat.BattleTypes)
local CombatConfig = require(ReplicatedStorage.Combat.CombatConfig)
local Summons = require(ReplicatedStorage.Combat.Summons)

type Side = BattleTypes.Side
type Phase = BattleTypes.Phase

-- One entry per summon joining the battle.
export type RosterEntry = {
	side: Side,
	summonId: string,
	ownerUserId: number?, -- the player controlling it; nil means the server's AI
	ownerName: string?,
}

-- A summon in this battle (the GDD's participant entry; its characterRef is summonId).
export type Participant = {
	id: string,
	side: Side,
	slot: number,
	name: string,
	summonId: string,
	ownerUserId: number?,
	ownerName: string?,
	stats: Summons.Stats,
	abilities: { string },
	hp: number,
	maxHp: number,
	mana: number,
	maxMana: number,
	status: BattleTypes.ParticipantStatus,
	initiative: BattleTypes.InitiativeRoll?,
}

export type ActionError = "NotInputPhase" | "NotYourTurn" | "UnknownAbility" | "NotEnoughMana" | "InvalidTarget"
export type PassReason = "Timeout" | "NoMana" | "NoValidAction"

local MAX_LOG_LINES = 50

local BattleSession = {}
BattleSession.__index = BattleSession

type SessionFields = {
	id: number,
	rng: Random,
	phase: Phase,
	round: number,
	turnNumber: number, -- increases every time a turn opens; identifies "this turn" for timers
	participants: { Participant }, -- roster order
	byId: { [string]: Participant },
	turnQueue: { string }, -- participant ids in initiative order
	turnIndex: number, -- position of the current actor in turnQueue
	currentActorId: string?,
	winner: Side?,
	lastAction: BattleTypes.ActionRecord?,
	actionCount: number,
	log: { string },
}

export type BattleSession = typeof(setmetatable({} :: SessionFields, BattleSession))

-- Placeholder formulas (GDD Step 11, Q6). The numbers live in CombatConfig.
function BattleSession.maxHpFor(stats: Summons.Stats): number
	return CombatConfig.BaseHP + stats.Vitality * CombatConfig.HPPerVitality
end

function BattleSession.maxManaFor(stats: Summons.Stats): number
	return CombatConfig.BaseMana + stats.Magic * CombatConfig.ManaPerMagic
end

function BattleSession.initiativeBonusFor(agility: number): number
	return math.floor(agility / CombatConfig.AgilityPerInitiativeBonus)
end

local function statValue(stats: Summons.Stats, stat: Abilities.StatName): number
	if stat == "Strength" then
		return stats.Strength
	elseif stat == "Magic" then
		return stats.Magic
	elseif stat == "Vitality" then
		return stats.Vitality
	end
	return stats.Agility
end

-- Turn order: highest initiative total first. Exact ties go to the party side (GDD Step 6), then
-- to the lower slot, so the same rolls always produce the same order.
local function goesFirst(a: Participant, b: Participant): boolean
	local aTotal = (a.initiative :: BattleTypes.InitiativeRoll).total
	local bTotal = (b.initiative :: BattleTypes.InitiativeRoll).total
	if aTotal ~= bTotal then
		return aTotal > bTotal
	end
	if a.side ~= b.side then
		return a.side == "Party"
	end
	return a.slot < b.slot
end

function BattleSession.new(id: number, roster: { RosterEntry }, rng: Random): BattleSession
	local fields: SessionFields = {
		id = id,
		rng = rng,
		phase = "setup",
		round = 0,
		turnNumber = 0,
		participants = {},
		byId = {},
		turnQueue = {},
		turnIndex = 0,
		currentActorId = nil,
		winner = nil,
		lastAction = nil,
		actionCount = 0,
		log = {},
	}
	local self = setmetatable(fields, BattleSession)

	local slotsTaken: { [string]: number } = {}
	for _, entry in roster do
		local summon = Summons[entry.summonId]
		assert(summon ~= nil, `Unknown summon "{entry.summonId}"`)

		local slot = (slotsTaken[entry.side] or 0) + 1
		slotsTaken[entry.side] = slot
		local maxHp = BattleSession.maxHpFor(summon.stats)
		local maxMana = BattleSession.maxManaFor(summon.stats)
		local participant: Participant = {
			id = (if entry.side == "Party" then "P" else "E") .. slot,
			side = entry.side,
			slot = slot,
			name = `{summon.name} {string.char(64 + slot)}`, -- "Tung Tung Sahur A", "... B"
			summonId = summon.id,
			ownerUserId = entry.ownerUserId,
			ownerName = entry.ownerName,
			stats = table.clone(summon.stats),
			abilities = table.clone(summon.abilities),
			hp = maxHp,
			maxHp = maxHp,
			mana = maxMana,
			maxMana = maxMana,
			status = "Active",
			initiative = nil,
		}
		table.insert(self.participants, participant)
		self.byId[participant.id] = participant
	end

	return self
end

-- GDD Step 6: each participant rolls once at the start of the battle, a random roll plus an
-- Agility bonus, and the turn queue sorts by that total rather than by raw Agility. Agility
-- raises the odds of acting early without guaranteeing it. The order then stays fixed for the
-- whole battle.
function BattleSession.rollInitiative(self: BattleSession)
	assert(self.phase == "setup" and #self.turnQueue == 0, "Initiative is rolled once, before the first turn")

	for _, participant in self.participants do
		local roll = self.rng:NextInteger(1, CombatConfig.InitiativeDieSides)
		local bonus = BattleSession.initiativeBonusFor(participant.stats.Agility)
		participant.initiative = { roll = roll, bonus = bonus, total = roll + bonus }
	end

	local order = table.clone(self.participants)
	table.sort(order, goesFirst)
	for _, participant in order do
		table.insert(self.turnQueue, participant.id)
		local initiative = participant.initiative :: BattleTypes.InitiativeRoll
		self:_log(
			`{participant.name} rolls initiative: {initiative.roll} + {initiative.bonus} Agility = {initiative.total}`
		)
	end
end

-- Opens the next turn: walks forward through turnQueue (wrapping into a new round), skipping
-- anyone knocked out or gone, restores a little Mana to the new actor, and waits for its action.
function BattleSession.beginNextTurn(self: BattleSession): Participant
	assert(self.phase == "setup" or self.phase == "resolve", `Can't begin a turn during "{self.phase}"`)
	assert(#self.turnQueue > 0, "Roll initiative before the first turn")

	for _ = 1, #self.turnQueue do
		self.turnIndex = self.turnIndex % #self.turnQueue + 1
		if self.turnIndex == 1 then
			self.round += 1
		end

		local actor = self.byId[self.turnQueue[self.turnIndex]]
		if actor.status == "Active" then
			self.turnNumber += 1
			self.currentActorId = actor.id
			self.phase = "input"
			actor.mana = math.min(actor.maxMana, actor.mana + CombatConfig.ManaRegenPerTurn)
			return actor
		end
	end

	error("No one is left to act, but the battle has no winner")
end

-- The participant whose turn it is (or who just acted, during "resolve").
function BattleSession.getCurrentActor(self: BattleSession): Participant?
	local id = self.currentActorId
	return if id then self.byId[id] else nil
end

function BattleSession.canAffordAnyAbility(self: BattleSession, participant: Participant): boolean
	for _, abilityId in participant.abilities do
		local ability = Abilities[abilityId]
		if ability ~= nil and participant.mana >= ability.manaCost then
			return true
		end
	end
	return false
end

function BattleSession.getActiveOpponents(self: BattleSession, participant: Participant): { Participant }
	local opponents = {}
	for _, other in self.participants do
		if other.side ~= participant.side and other.status == "Active" then
			table.insert(opponents, other)
		end
	end
	return opponents
end

-- A player's request to act, straight from the SubmitAction RemoteEvent. Every rule is checked
-- here on the server: is it this player's turn, is the ability theirs and affordable, is the
-- target legal. Returns true once the action has resolved, or false with an error code and a
-- message to show that player. The client's copy of the state is only ever for display.
function BattleSession.submitAction(
	self: BattleSession,
	userId: number,
	abilityId: string,
	targetId: string
): (boolean, ActionError?, string?)
	local actor = self:getCurrentActor()
	if self.phase ~= "input" or actor == nil then
		local message = if self.phase == "setup"
			then "The battle is about to start."
			elseif self.phase == "reward" then "The battle is over."
			else "Hold on, the last action is still resolving."
		return false, "NotInputPhase", message
	end
	if actor.ownerUserId ~= userId then
		local whose = if actor.ownerName then `{actor.ownerName}'s` else "the enemy's"
		return false, "NotYourTurn", `It's not your turn, it's {whose}.`
	end
	return self:_resolveAction(actor, abilityId, targetId)
end

-- The AI's version of submitAction: the same checks and the same resolution, no favors.
function BattleSession.performEnemyAction(
	self: BattleSession,
	abilityId: string,
	targetId: string
): (boolean, ActionError?, string?)
	local actor = self:getCurrentActor()
	if self.phase ~= "input" or actor == nil or actor.ownerUserId ~= nil then
		error("performEnemyAction called outside an AI-controlled turn")
	end
	return self:_resolveAction(actor, abilityId, targetId)
end

-- Ends the current turn without an action.
function BattleSession.passTurn(self: BattleSession, reason: PassReason)
	local actor = self:getCurrentActor()
	if self.phase ~= "input" or actor == nil then
		error("passTurn called with no open turn")
	end

	self.phase = "resolve"
	if reason == "Timeout" then
		self:_log(`{actor.name} ran out of time and skips the turn.`)
	elseif reason == "NoMana" then
		self:_log(`{actor.name} is out of Mana and skips the turn.`)
	else
		self:_log(`{actor.name} hesitates and skips the turn.`)
	end
end

-- A player left the server mid-battle (GDD Step 6, "Players leaving combat"): their summons drop
-- out of the turn order. Returns true if one of them was mid-turn, so the caller can move on
-- right away instead of waiting out the turn timer.
function BattleSession.removePlayer(self: BattleSession, userId: number): boolean
	local wasTheirTurn = false
	for _, participant in self.participants do
		if participant.ownerUserId == userId and participant.status == "Active" then
			participant.status = "Left"
			self:_log(`{participant.name} leaves the battle.`)
			if self.phase == "input" and participant.id == self.currentActorId then
				wasTheirTurn = true
			end
		end
	end

	if wasTheirTurn then
		self.phase = "resolve"
	end
	self:_checkForWinner()
	return wasTheirTurn
end

-- Everything clients need to draw the battle. Copies, so nothing outside can mutate the session.
function BattleSession.getState(self: BattleSession): BattleTypes.BattleState
	local participants: { BattleTypes.ParticipantState } = {}
	for _, participant in self.participants do
		table.insert(participants, {
			id = participant.id,
			side = participant.side,
			slot = participant.slot,
			name = participant.name,
			summonId = participant.summonId,
			ownerUserId = participant.ownerUserId,
			ownerName = participant.ownerName,
			hp = participant.hp,
			maxHp = participant.maxHp,
			mana = participant.mana,
			maxMana = participant.maxMana,
			status = participant.status,
			abilities = table.clone(participant.abilities),
			initiative = if participant.initiative then table.clone(participant.initiative) else nil,
		})
	end

	local firstLogLine = math.max(1, #self.log - CombatConfig.LogLinesShown + 1)
	return {
		battleId = self.id,
		phase = self.phase,
		round = self.round,
		turnNumber = self.turnNumber,
		currentActorId = self.currentActorId,
		turnQueue = table.clone(self.turnQueue),
		participants = participants,
		winner = self.winner,
		lastAction = if self.lastAction then table.clone(self.lastAction) else nil,
		log = table.move(self.log, firstLogLine, #self.log, 1, {}),
		turnDeadline = nil,
		lobbyReturnAt = nil,
	}
end

function BattleSession._resolveAction(
	self: BattleSession,
	actor: Participant,
	abilityId: string,
	targetId: string
): (boolean, ActionError?, string?)
	local ability = Abilities[abilityId]
	if ability == nil or table.find(actor.abilities, abilityId) == nil then
		return false, "UnknownAbility", `{actor.name} doesn't know that ability.`
	end
	if actor.mana < ability.manaCost then
		return false,
			"NotEnoughMana",
			`Not enough Mana for {ability.name}: it costs {ability.manaCost} and {actor.name} has {actor.mana}.`
	end
	local target = self.byId[targetId]
	if target == nil or target.side == actor.side or target.status ~= "Active" then
		return false, "InvalidTarget", "Pick an enemy that's still standing."
	end

	-- GDD Step 6, "Action priority": pre-action triggers, the action, post-action triggers, then
	-- death checks. There are no status effects yet, so only the action and death checks run.
	self.phase = "resolve"
	actor.mana -= ability.manaCost
	local damage = self:_rollDamage(actor, ability)
	target.hp = math.max(0, target.hp - damage)

	local knockedOut = target.hp == 0
	self.actionCount += 1
	self.lastAction = {
		sequence = self.actionCount,
		actorId = actor.id,
		targetId = target.id,
		abilityId = ability.id,
		damage = damage,
		knockedOut = knockedOut,
	}
	self:_log(`{actor.name} used {ability.name} on {target.name} for {damage} damage.`)

	if knockedOut then
		target.status = "KnockedOut"
		self:_log(`{target.name} is knocked out!`)
	end
	self:_checkForWinner()
	return true, nil, nil
end

function BattleSession._rollDamage(self: BattleSession, actor: Participant, ability: Abilities.Ability): number
	local base = ability.power + statValue(actor.stats, ability.scalingStat) * ability.statRatio
	local variance = CombatConfig.DamageVariance
	return math.max(1, math.round(base * self.rng:NextNumber(1 - variance, 1 + variance)))
end

function BattleSession._hasActive(self: BattleSession, side: Side): boolean
	for _, participant in self.participants do
		if participant.side == side and participant.status == "Active" then
			return true
		end
	end
	return false
end

function BattleSession._checkForWinner(self: BattleSession)
	if self.winner ~= nil then
		return
	end
	if not self:_hasActive("Enemy") then
		self:_finish("Party")
	elseif not self:_hasActive("Party") then
		self:_finish("Enemy")
	end
end

function BattleSession._finish(self: BattleSession, winner: Side)
	self.winner = winner
	self.phase = "reward"
	self.currentActorId = nil
	self:_log(if winner == "Party" then "Victory! The party wins the battle." else "Defeat... the party has fallen.")
end

function BattleSession._log(self: BattleSession, line: string)
	table.insert(self.log, line)
	if #self.log > MAX_LOG_LINES then
		table.remove(self.log, 1)
	end
end

return BattleSession
