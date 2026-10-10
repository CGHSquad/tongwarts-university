--!strict
--[[
	BattleSession — the rules and state of one fight. Server-only (GDD Steps 5 and 6).

	Pure Luau: no Instances, RemoteEvents or task scheduling. BattleDirector owns time and
	networking; this module owns the rules, so every combat rule lives in one place. It sits in
	ServerScriptService, which never replicates, so clients can't even read it.

	A fight, as BattleDirector drives it:
		session:rollInitiative(opening)    -- once per battle; builds turnQueue             "setup"
		session:beginNextTurn()            -- next summon's turn: Mana back, statuses tick   "input"
		                                   -- (straight to "resolve" if an ailment costs it the turn)
		session:submitAction(userId, ...)  -- a player's request: validated, resolved       "resolve"
		session:performEnemyAction(...)    -- same validation and resolution for the AI     "resolve"
		session:passTurn(reason)           -- AFK timeout, or nothing affordable            "resolve"
		...back to beginNextTurn, until one side has no one left standing                 "reward"

	Stats (GDD "Core stats", finalized): Strength and Magic scale damage, Endurance cuts incoming
	damage and makes up most of max Health, Agility gives the initiative bonus plus accuracy and
	evasion, and Luck drives critical hits and ailments. The numbers are all in CombatConfig.

	Besides its own abilities, every summon can Guard (GDD Step 6): free, no target, and it braces
	until its own next turn. See _guard and _attack. Every player's party member can also Attack,
	their character's own free swing ("The player character on the field"); see canUse.

	A fight can open with a bonus turn for one side, depending on how the overworld encounter
	began (GDD Step 6's initiativeBonus): everyone on that side acts once, in initiative order,
	before round 1. See rollInitiative.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Abilities = require(ReplicatedStorage.Combat.Abilities)
local BattleTypes = require(ReplicatedStorage.Combat.BattleTypes)
local CombatConfig = require(ReplicatedStorage.Combat.CombatConfig)
local StatusEffects = require(ReplicatedStorage.Combat.StatusEffects)
local Summons = require(ReplicatedStorage.Combat.Summons)

type Side = BattleTypes.Side
type Phase = BattleTypes.Phase
type ActionResult = BattleTypes.ActionResult

-- One entry per summon joining the battle.
export type RosterEntry = {
	side: Side,
	summonId: string,
	ownerUserId: number?, -- the player controlling it; nil means the server's AI
	ownerName: string?,
}

-- A status on a summon. Clients only ever see its id and turns left (getState).
export type ActiveStatus = {
	id: string,
	turnsLeft: number,
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
	statuses: { ActiveStatus },
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
	opening: Side?, -- the side that takes a bonus turn before round 1, if any
	openingQueue: { string }, -- that side's ids in initiative order: the bonus turn
	openingIndex: number, -- how far through openingQueue the bonus turn has got
	currentActorId: string?,
	winner: Side?,
	lastAction: BattleTypes.ActionRecord?,
	lostTurn: BattleTypes.LostTurn?, -- the current turn, when an ailment cost it
	actionCount: number,
	log: { string },
}

export type BattleSession = typeof(setmetatable({} :: SessionFields, BattleSession))

--[[ Formulas. Placeholders per GDD Step 11 Q6; the numbers live in CombatConfig. ]]

function BattleSession.maxHpFor(stats: Summons.Stats): number
	return CombatConfig.BaseHP + stats.Endurance * CombatConfig.HPPerEndurance
end

function BattleSession.maxManaFor(stats: Summons.Stats): number
	return CombatConfig.BaseMana + stats.Magic * CombatConfig.ManaPerMagic
end

function BattleSession.initiativeBonusFor(agility: number): number
	return math.floor(agility / CombatConfig.AgilityPerInitiativeBonus)
end

-- The share of incoming damage, physical or magical, that Endurance blocks.
function BattleSession.damageReductionFor(endurance: number): number
	return math.clamp(endurance * CombatConfig.DamageReductionPerEndurance, 0, CombatConfig.MaxDamageReduction)
end

-- Accuracy (attacker's Agility) against evasion (target's Agility).
function BattleSession.hitChanceFor(attackerAgility: number, targetAgility: number): number
	local chance = CombatConfig.BaseHitChance + (attackerAgility - targetAgility) * CombatConfig.HitChancePerAgility
	return math.clamp(chance, CombatConfig.MinHitChance, CombatConfig.MaxHitChance)
end

function BattleSession.critChanceFor(luck: number, abilityBonus: number): number
	return math.clamp(CombatConfig.BaseCritChance + luck * CombatConfig.CritChancePerLuck + abilityBonus, 0, 1)
end

-- Inflicting an ailment: the ability's base chance, pushed up or down by Luck against Luck.
function BattleSession.ailmentChanceFor(baseChance: number, attackerLuck: number, targetLuck: number): number
	local chance = baseChance + (attackerLuck - targetLuck) * CombatConfig.AilmentChancePerLuck
	return math.clamp(chance, 0, CombatConfig.MaxAilmentChance)
end

--[[ Status effects ]]

-- Agility for accuracy and evasion, buffs included. Turn order never uses this: it was rolled from
-- base Agility at the start, and a fight in progress is never re-sorted (GDD Step 6).
function BattleSession.effectiveAgility(participant: Participant): number
	local agility = participant.stats.Agility
	for _, status in participant.statuses do
		agility += StatusEffects[status.id].agilityBonus or 0
	end
	return agility
end

-- Whether enemies have to target this participant (a taunt is up).
function BattleSession.drawsAttacks(participant: Participant): boolean
	for _, status in participant.statuses do
		if StatusEffects[status.id].drawsAttacks then
			return true
		end
	end
	return false
end

-- The share of incoming damage this participant blocks. Endurance cuts it first, then each status
-- (Guarded, Bracing) cuts what's left, so they multiply instead of adding up: Endurance's 60% cap
-- and Bracing's 30% block 1 - 0.4 * 0.7 = 72%, not 90%. The total is capped as well.
function BattleSession.damageReductionAgainst(participant: Participant): number
	local taken = 1 - BattleSession.damageReductionFor(participant.stats.Endurance)
	for _, status in participant.statuses do
		taken *= StatusEffects[status.id].damageTakenMultiplier or 1
	end
	return math.min(1 - taken, CombatConfig.MaxTotalDamageReduction)
end

-- Whether attacks on this participant can't be critical hits (it's guarding).
function BattleSession.blocksCriticals(participant: Participant): boolean
	for _, status in participant.statuses do
		if StatusEffects[status.id].blocksCriticals then
			return true
		end
	end
	return false
end

-- Scales the chance of inflicting an ailment on this participant (below 1 while it's guarding).
function BattleSession.ailmentChanceMultiplier(participant: Participant): number
	local multiplier = 1
	for _, status in participant.statuses do
		multiplier *= StatusEffects[status.id].ailmentChanceMultiplier or 1
	end
	return multiplier
end

-- A status the summon already has is refreshed, not stacked.
local function applyStatus(participant: Participant, statusId: string, turns: number)
	local def = StatusEffects[statusId]
	assert(def ~= nil, `Unknown status "{statusId}"`)
	for _, status in participant.statuses do
		if status.id == statusId then
			status.turnsLeft = math.max(status.turnsLeft, turns)
			return
		end
	end
	table.insert(participant.statuses, { id = statusId, turnsLeft = turns })
end

local function removeAilments(participant: Participant): boolean
	local removed = false
	for index = #participant.statuses, 1, -1 do
		if StatusEffects[participant.statuses[index].id].kind == "Ailment" then
			table.remove(participant.statuses, index)
			removed = true
		end
	end
	return removed
end

--[[ Helpers ]]

local function statValue(stats: Summons.Stats, stat: Abilities.StatName): number
	if stat == "Strength" then
		return stats.Strength
	elseif stat == "Magic" then
		return stats.Magic
	elseif stat == "Endurance" then
		return stats.Endurance
	elseif stat == "Agility" then
		return stats.Agility
	end
	return stats.Luck
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

local function newResult(targetId: string): ActionResult
	return {
		targetId = targetId,
		hit = true,
		critical = false,
		damage = 0,
		healed = 0,
		knockedOut = false,
		inflicted = nil,
		applied = nil,
		cleansed = false,
	}
end

--[[ Lifecycle ]]

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
		opening = nil,
		openingQueue = {},
		openingIndex = 0,
		currentActorId = nil,
		winner = nil,
		lastAction = nil,
		lostTurn = nil,
		actionCount = 0,
		log = {},
	}
	local self = setmetatable(fields, BattleSession)

	-- Summons go by their type's name, with a letter only when a side has more than one of it.
	local copies: { [string]: number } = {}
	for _, entry in roster do
		local key = `{entry.side}/{entry.summonId}`
		copies[key] = (copies[key] or 0) + 1
	end

	local slotsTaken: { [string]: number } = {}
	local copiesNamed: { [string]: number } = {}
	for _, entry in roster do
		local summon = Summons[entry.summonId]
		assert(summon ~= nil, `Unknown summon "{entry.summonId}"`)

		local slot = (slotsTaken[entry.side] or 0) + 1
		slotsTaken[entry.side] = slot
		local key = `{entry.side}/{entry.summonId}`
		copiesNamed[key] = (copiesNamed[key] or 0) + 1
		local name = if copies[key] > 1 then `{summon.name} {string.char(64 + copiesNamed[key])}` else summon.name

		local maxHp = BattleSession.maxHpFor(summon.stats)
		local maxMana = BattleSession.maxManaFor(summon.stats)
		local participant: Participant = {
			id = (if entry.side == "Party" then "P" else "E") .. slot,
			side = entry.side,
			slot = slot,
			name = name,
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
			statuses = {},
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
--
-- `opening` is the side that struck first in the overworld (GDD "Combat philosophy"), if either
-- did. Everyone on it takes a bonus turn before round 1, in the order they just rolled. Then
-- round 1 starts from the top of the queue as usual.
function BattleSession.rollInitiative(self: BattleSession, opening: Side?)
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

	self.opening = opening
	if opening then
		for _, id in self.turnQueue do
			if self.byId[id].side == opening then
				table.insert(self.openingQueue, id)
			end
		end
		self:_log(`The {if opening == "Party" then "party" else "enemies"} struck first: a bonus turn before round 1!`)
	end
end

-- Opens the next turn: walks forward through turnQueue (wrapping into a new round), skipping
-- anyone knocked out or gone, and runs the start of that summon's turn. Usually the phase is then
-- "input", waiting for its action; if an ailment cost it the turn, it's already "resolve".
function BattleSession.beginNextTurn(self: BattleSession): Participant
	assert(self.phase == "setup" or self.phase == "resolve", `Can't begin a turn during "{self.phase}"`)
	assert(#self.turnQueue > 0, "Roll initiative before the first turn")
	self.lostTurn = nil

	-- The bonus turn, if the fight opened with one, comes before round 1 (the round is still 0).
	while self.openingIndex < #self.openingQueue do
		self.openingIndex += 1
		local actor = self.byId[self.openingQueue[self.openingIndex]]
		if actor.status == "Active" then
			self.turnNumber += 1
			self.currentActorId = actor.id
			self.phase = "input"
			self:_startTurn(actor)
			return actor
		end
	end

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
			self:_startTurn(actor)
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

-- Whether it can afford one of its own abilities. (Guard is free, so it can always do that.)
function BattleSession.canAffordAnyAbility(self: BattleSession, participant: Participant): boolean
	for _, abilityId in participant.abilities do
		local ability = Abilities[abilityId]
		if ability ~= nil and participant.mana >= ability.manaCost then
			return true
		end
	end
	return false
end

-- Whether this participant may use the ability: one of its own, or a universal one it qualifies
-- for (Guard for every summon, Attack for every player's party member; see Abilities).
function BattleSession.canUse(participant: Participant, abilityId: string): boolean
	local ability = Abilities[abilityId]
	if ability == nil then
		return false
	elseif ability.universal == "Everyone" or (ability.universal == "Party" and participant.side == "Party") then
		return true
	end
	return table.find(participant.abilities, abilityId) ~= nil
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

-- Everyone still standing on this participant's side, itself included.
function BattleSession.getActiveAllies(self: BattleSession, participant: Participant): { Participant }
	local allies = {}
	for _, other in self.participants do
		if other.side == participant.side and other.status == "Active" then
			table.insert(allies, other)
		end
	end
	return allies
end

-- A player's request to act, straight from the SubmitAction RemoteEvent. Every rule is checked
-- here on the server: is it this player's turn, is the ability theirs and affordable, is the
-- target legal for it. Returns true once the action has resolved, or false with an error code and
-- a message to show that player. The client's copy of the state is only ever for display.
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
			table.clear(participant.statuses)
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
		local statuses: { BattleTypes.StatusState } = {}
		for _, status in participant.statuses do
			table.insert(statuses, { id = status.id, turnsLeft = status.turnsLeft })
		end
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
			statuses = statuses,
			abilities = table.clone(participant.abilities),
			initiative = if participant.initiative then table.clone(participant.initiative) else nil,
		})
	end

	local lastAction: BattleTypes.ActionRecord? = nil
	if self.lastAction then
		local results = {}
		for _, result in self.lastAction.results do
			table.insert(results, table.clone(result))
		end
		lastAction = {
			sequence = self.lastAction.sequence,
			actorId = self.lastAction.actorId,
			abilityId = self.lastAction.abilityId,
			results = results,
		}
	end

	local firstLogLine = math.max(1, #self.log - CombatConfig.LogLinesShown + 1)
	return {
		battleId = self.id,
		phase = self.phase,
		round = self.round,
		turnNumber = self.turnNumber,
		currentActorId = self.currentActorId,
		turnQueue = table.clone(self.turnQueue),
		opening = self.opening,
		participants = participants,
		winner = self.winner,
		lastAction = lastAction,
		lostTurn = if self.lostTurn then table.clone(self.lostTurn) else nil,
		log = table.move(self.log, firstLogLine, #self.log, 1, {}),
		turnDeadline = nil,
		overworldReturnAt = nil,
		startedBy = nil,
	}
end

--[[ Turn internals ]]

-- The start of a turn (GDD Step 6's pre-action triggers): Mana trickles back, each status gets
-- its say, and then they all count down. An ailment can cost the whole turn.
function BattleSession._startTurn(self: BattleSession, actor: Participant)
	actor.mana = math.min(actor.maxMana, actor.mana + CombatConfig.ManaRegenPerTurn)

	local lostTurnTo: StatusEffects.StatusDef? = nil
	local lostTurnId: string? = nil
	for _, status in actor.statuses do
		local def = StatusEffects[status.id]
		if lostTurnTo == nil and def.skipTurnChance ~= nil and self:_roll(def.skipTurnChance) then
			lostTurnTo = def
			lostTurnId = status.id
		end
	end

	for index = #actor.statuses, 1, -1 do
		local status = actor.statuses[index]
		status.turnsLeft -= 1
		if status.turnsLeft <= 0 then
			table.remove(actor.statuses, index)
		end
	end

	if lostTurnTo and lostTurnId then
		self.phase = "resolve"
		self.lostTurn = { turnNumber = self.turnNumber, actorId = actor.id, statusId = lostTurnId }
		self:_log(`{actor.name} is {string.lower(lostTurnTo.name)} and loses its turn.`)
	end
end

-- Who an ability would affect, or nil if the requested target isn't legal for it. Abilities that
-- need no pick ("Self", "AllAllies") ignore targetId.
function BattleSession._targetsFor(
	self: BattleSession,
	actor: Participant,
	ability: Abilities.Ability,
	targetId: string
): { Participant }?
	if ability.targets == "Self" then
		return { actor }
	elseif ability.targets == "AllAllies" then
		return self:getActiveAllies(actor)
	end

	local target = self.byId[targetId]
	if target == nil or target.status ~= "Active" then
		return nil
	end
	local isAlly = target.side == actor.side
	if (ability.targets == "Ally") ~= isAlly then
		return nil
	end
	return { target }
end

function BattleSession._resolveAction(
	self: BattleSession,
	actor: Participant,
	abilityId: string,
	targetId: string
): (boolean, ActionError?, string?)
	local ability = Abilities[abilityId]
	if ability == nil or not BattleSession.canUse(actor, abilityId) then
		return false, "UnknownAbility", `{actor.name} doesn't know that ability.`
	end
	if actor.mana < ability.manaCost then
		return false,
			"NotEnoughMana",
			`Not enough Mana for {ability.name}: it costs {ability.manaCost} and {actor.name} has {actor.mana}.`
	end
	local targets = self:_targetsFor(actor, ability, targetId)
	if targets == nil then
		return false,
			"InvalidTarget",
			if ability.targets == "Ally"
				then "Pick a party member who's still standing."
				else "Pick an enemy that's still standing."
	end

	-- GDD Step 6, "Action priority": pre-action triggers (they ran at the start of the turn), the
	-- action, post-action triggers (none yet), then death checks.
	self.phase = "resolve"
	actor.mana -= ability.manaCost
	local results: { ActionResult } = {}
	if ability.kind == "Attack" then
		for _, target in targets do
			table.insert(results, self:_attack(actor, ability, target))
		end
	elseif ability.kind == "Heal" then
		for _, target in targets do
			table.insert(results, self:_heal(actor, ability, target))
		end
	elseif ability.kind == "Guard" then
		table.insert(results, self:_guard(actor, ability))
	else
		results = self:_grantStatus(actor, ability, targets)
	end

	self.actionCount += 1
	self.lastAction = {
		sequence = self.actionCount,
		actorId = actor.id,
		abilityId = ability.id,
		results = results,
	}
	self:_checkForWinner()
	return true, nil, nil
end

-- One attack on one target: roll to hit, roll for a critical hit, cut the damage by the target's
-- Endurance and statuses, then check for a knockout, and roll for the ailment if it's still up.
-- A guarding target can't be crit and resists the ailment.
function BattleSession._attack(
	self: BattleSession,
	actor: Participant,
	ability: Abilities.AttackAbility,
	target: Participant
): ActionResult
	local result = newResult(target.id)
	local hitChance =
		BattleSession.hitChanceFor(BattleSession.effectiveAgility(actor), BattleSession.effectiveAgility(target))
	if self:_roll(hitChance) then
		self:_hit(actor, ability, target, result)
	else
		result.hit = false
		self:_log(`{actor.name} used {ability.name} on {target.name}, but missed.`)
	end
	return result
end

-- The rest of an attack, once it connects.
function BattleSession._hit(
	self: BattleSession,
	actor: Participant,
	ability: Abilities.AttackAbility,
	target: Participant,
	result: ActionResult
)
	local variance = CombatConfig.DamageVariance
	local damage = (ability.power + statValue(actor.stats, ability.scalingStat) * ability.statRatio)
		* self.rng:NextNumber(1 - variance, 1 + variance)
	local critChance = if BattleSession.blocksCriticals(target)
		then 0
		else BattleSession.critChanceFor(actor.stats.Luck, ability.critBonus or 0)
	result.critical = self:_roll(critChance)
	if result.critical then
		damage *= CombatConfig.CriticalMultiplier
	end
	damage *= 1 - BattleSession.damageReductionAgainst(target)
	result.damage = math.max(1, math.round(damage))
	target.hp = math.max(0, target.hp - result.damage)
	self:_log(
		if result.critical
			then `{actor.name} used {ability.name} on {target.name}: critical hit, {result.damage} damage!`
			else `{actor.name} used {ability.name} on {target.name} for {result.damage} damage.`
	)

	local ailment = ability.ailment
	if target.hp == 0 then
		result.knockedOut = true
		target.status = "KnockedOut"
		table.clear(target.statuses)
		self:_log(`{target.name} is knocked out!`)
	elseif ailment then
		local chance = BattleSession.ailmentChanceFor(ailment.chance, actor.stats.Luck, target.stats.Luck)
			* BattleSession.ailmentChanceMultiplier(target)
		if self:_roll(chance) then
			applyStatus(target, ailment.status, ailment.turns)
			result.inflicted = ailment.status
			self:_log(`{target.name} is {string.lower(StatusEffects[ailment.status].name)}!`)
		end
	end
end

function BattleSession._heal(
	self: BattleSession,
	actor: Participant,
	ability: Abilities.HealAbility,
	target: Participant
): ActionResult
	local result = newResult(target.id)
	local amount = math.round(ability.power + statValue(actor.stats, ability.scalingStat) * ability.statRatio)
	result.healed = math.min(amount, target.maxHp - target.hp)
	target.hp += result.healed
	result.cleansed = ability.cleanse == true and removeAilments(target)
	self:_log(
		`{actor.name} used {ability.name} on {target.name}: +{result.healed} Health{if result.cleansed
			then ", ailments cleared"
			else ""}.`
	)
	return result
end

function BattleSession._grantStatus(
	self: BattleSession,
	actor: Participant,
	ability: Abilities.StatusAbility,
	targets: { Participant }
): { ActionResult }
	local results: { ActionResult } = {}
	for _, target in targets do
		applyStatus(target, ability.status, ability.turns)
		local result = newResult(target.id)
		result.applied = ability.status
		table.insert(results, result)
	end

	local def = StatusEffects[ability.status]
	local onWhom = if ability.targets == "AllAllies" then " on the whole party" else ""
	self:_log(`{actor.name} used {ability.name}: {def.name}{onWhom} for {ability.turns} turns ({def.description}).`)
	return results
end

-- Guard (GDD Step 6): spends the turn bracing (the Bracing status) until this summon's next turn.
function BattleSession._guard(self: BattleSession, actor: Participant, ability: Abilities.GuardAbility): ActionResult
	applyStatus(actor, ability.status, ability.turns)
	local result = newResult(actor.id)
	result.applied = ability.status
	self:_log(`{actor.name} guards, bracing until its next turn.`)
	return result
end

function BattleSession._roll(self: BattleSession, chance: number): boolean
	return self.rng:NextNumber() < chance
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
