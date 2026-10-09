--!strict
--[[
	BattleDirector — runs the fights: starting one when a player walks into an overworld enemy
	(startEncounter), and the real-time loop around its BattleSession (turn timers, enemy turns,
	pacing, players leaving). One per server, one battle at a time.

	It doesn't call Roblox APIs itself: BattleServer hands it the clock, the scheduler, the RNG and
	the functions that reach clients and the overworld. That keeps this file about game flow, and
	lets it run outside Studio.

	Party rule: everyone in the server is one party. Whoever touches an enemy pulls the others into
	the fight too, up to CombatConfig.MaxPartySize players; anyone past that sits this one out.
	How the fight opens (who struck first) comes from the overworld: see Overworld and Encounter.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Abilities = require(ReplicatedStorage.Combat.Abilities)
local BattleTypes = require(ReplicatedStorage.Combat.BattleTypes)
local CombatConfig = require(ReplicatedStorage.Combat.CombatConfig)
local Pacing = require(ReplicatedStorage.Combat.Pacing)
local BattleSession = require(script.Parent.BattleSession)
local EnemyAI = require(script.Parent.EnemyAI)

export type Dependencies = {
	now: () -> number, -- server clock that clients share: workspace:GetServerTimeNow()
	delay: (seconds: number, callback: () -> ()) -> (), -- task.delay
	rng: Random,
	broadcast: (snapshot: BattleTypes.Snapshot) -> (), -- send the latest state to every client
	notify: (userId: number, message: string) -> (), -- tell one player why a request was refused
	-- The fight is over and cleared, and everyone's back in the overworld. The winner is nil if the
	-- fight was reset after an error.
	battleEnded: (winner: BattleTypes.Side?) -> (),
}

-- A fight about to start, from the overworld.
export type Encounter = {
	enemies: { string }, -- the enemy side's summons (Summons ids)
	opening: BattleTypes.Side?, -- the side that struck first and takes a bonus turn, if either did
}

type Member = {
	userId: number,
	name: string,
}

local BattleDirector = {}
BattleDirector.__index = BattleDirector

type DirectorFields = {
	deps: Dependencies,
	members: { Member }, -- everyone in the server, in join order
	session: BattleSession.BattleSession?,
	battleCount: number,
	startedBy: string?, -- the player who walked into the enemy
	turnDeadline: number?,
	overworldReturnAt: number?,
}

export type BattleDirector = typeof(setmetatable({} :: DirectorFields, BattleDirector))

function BattleDirector.new(deps: Dependencies): BattleDirector
	local fields: DirectorFields = {
		deps = deps,
		members = {},
		session = nil,
		battleCount = 0,
		startedBy = nil,
		turnDeadline = nil,
		overworldReturnAt = nil,
	}
	return setmetatable(fields, BattleDirector)
end

--[[ Called by BattleServer. Each one broadcasts the new state when something changed. ]]

function BattleDirector.playerJoined(self: BattleDirector, userId: number, name: string)
	if self:_findMember(userId) then
		return
	end
	table.insert(self.members, { userId = userId, name = name })
	self:_broadcast()
end

function BattleDirector.playerLeft(self: BattleDirector, userId: number)
	for index, member in self.members do
		if member.userId == userId then
			table.remove(self.members, index)
			break
		end
	end

	local session = self.session
	if session then
		self:_protect(function()
			local wasTheirTurn = session:removePlayer(userId)
			if session.phase == "reward" then
				self:_showResults()
			elseif wasTheirTurn then
				self:_beginNextTurn() -- move on now instead of waiting out their timer (GDD Step 6)
			end
		end)
	end
	self:_broadcast()
end

-- `userId` walked into an overworld enemy: start the fight. The party is that player, then
-- everyone else in the server in join order, up to MaxPartySize. Returns the party's user ids, or
-- nil if no fight started (one is already running, or that player isn't in the server).
function BattleDirector.startEncounter(self: BattleDirector, userId: number, encounter: Encounter): { number }?
	local starter = self:_findMember(userId)
	if starter == nil or self.session ~= nil then
		return nil
	end
	local party: { Member } = { starter }
	for _, member in self.members do
		if member ~= starter and #party < CombatConfig.MaxPartySize then
			table.insert(party, member)
		end
	end

	local started = false
	self:_protect(function()
		self:_startBattle(party, encounter)
		started = true
	end)
	self:_broadcast()
	if not started then
		return nil
	end
	local userIds = {}
	for _, member in party do
		table.insert(userIds, member.userId)
	end
	return userIds
end

function BattleDirector.submitAction(self: BattleDirector, userId: number, abilityId: string, targetId: string)
	local session = self.session
	if session == nil then
		self.deps.notify(userId, "There's no battle running.")
		return
	end

	local changed = true
	self:_protect(function()
		local accepted, _, message = session:submitAction(userId, abilityId, targetId)
		if accepted then
			self:_afterTurn(session.lastAction)
		else
			changed = false
			self.deps.notify(userId, message or "You can't do that right now.")
		end
	end)
	if changed then
		self:_broadcast()
	end
end

function BattleDirector.getSnapshot(self: BattleDirector): BattleTypes.Snapshot
	local players: { BattleTypes.OverworldPlayer } = {}
	for _, member in self.members do
		table.insert(players, { userId = member.userId, name = member.name })
	end

	local battle: BattleTypes.BattleState? = nil
	if self.session then
		local state = self.session:getState()
		state.turnDeadline = self.turnDeadline
		state.overworldReturnAt = self.overworldReturnAt
		state.startedBy = self.startedBy
		battle = state
	end

	return {
		overworld = {
			players = players,
			maxPartySize = CombatConfig.MaxPartySize,
		},
		battle = battle,
	}
end

--[[ Starting a fight ]]

function BattleDirector._startBattle(self: BattleDirector, party: { Member }, encounter: Encounter)
	-- Party summons are dealt round-robin: one each for two players, both for a solo player.
	local roster: { BattleSession.RosterEntry } = {}
	for slot, summonId in CombatConfig.PartySummons do
		local owner = party[(slot - 1) % #party + 1]
		local entry: BattleSession.RosterEntry = {
			side = "Party",
			summonId = summonId,
			ownerUserId = owner.userId,
			ownerName = owner.name,
		}
		table.insert(roster, entry)
	end
	for _, summonId in encounter.enemies do
		local entry: BattleSession.RosterEntry = { side = "Enemy", summonId = summonId }
		table.insert(roster, entry)
	end

	self.battleCount += 1
	local session = BattleSession.new(self.battleCount, roster, self.deps.rng)
	self.session = session
	self.startedBy = party[1].name
	self.turnDeadline = nil
	self.overworldReturnAt = nil

	session:rollInitiative(encounter.opening)
	self:_after(CombatConfig.InitiativeRevealSeconds, function()
		self:_beginNextTurn()
	end)
end

--[[ Battle loop ]]

function BattleDirector._beginNextTurn(self: BattleDirector)
	local session = self.session :: BattleSession.BattleSession
	self.turnDeadline = nil
	local actor = session:beginNextTurn()

	if session.phase ~= "input" then
		self:_afterTurn(nil) -- an ailment cost it the turn
	elseif actor.ownerUserId == nil and not session:canAffordAnyAbility(actor) then
		-- Only enemies get here: players can always Guard, which is free. The AI doesn't guard.
		session:passTurn("NoMana")
		self:_afterTurn(nil)
	elseif actor.ownerUserId == nil then
		self:_after(CombatConfig.EnemyThinkSeconds, function()
			self:_takeEnemyTurn()
		end)
	else
		-- A player's turn. If they don't act in time (AFK or disconnected), the turn passes
		-- (GDD Step 6, "Disconnects" and "AFK players").
		self.turnDeadline = self.deps.now() + CombatConfig.TurnTimeoutSeconds
		self:_after(CombatConfig.TurnTimeoutSeconds, function()
			session:passTurn("Timeout")
			self:_afterTurn(nil)
		end)
	end
end

function BattleDirector._takeEnemyTurn(self: BattleDirector)
	local session = self.session :: BattleSession.BattleSession
	local actor = session:getCurrentActor() :: BattleSession.Participant
	local abilityId, targetId = EnemyAI.chooseAction(
		actor,
		session:getActiveAllies(actor),
		session:getActiveOpponents(actor),
		self.deps.rng
	)

	local acted = false
	if abilityId ~= nil and targetId ~= nil then
		acted = session:performEnemyAction(abilityId, targetId)
	end
	if not acted then
		session:passTurn("NoValidAction")
	end
	self:_afterTurn(if acted then session.lastAction else nil)
end

-- The current turn is over (acted, passed, or its player left): pause long enough for everyone's
-- stage to play `action` out (Pacing; nil when nothing happened), then open the next turn, or
-- show the result if the battle just ended.
function BattleDirector._afterTurn(self: BattleDirector, action: BattleTypes.ActionRecord?)
	local session = self.session :: BattleSession.BattleSession
	self.turnDeadline = nil
	if session.phase == "reward" then
		self:_showResults()
	else
		self:_after(BattleDirector.resolveSeconds(session, action), function()
			self:_beginNextTurn()
		end)
	end
end

-- How long the stage gets for `action` before the next turn (Pacing, from what it did).
function BattleDirector.resolveSeconds(session: BattleSession.BattleSession, action: BattleTypes.ActionRecord?): number
	if action == nil then
		return Pacing.resolveSeconds(nil, nil, false)
	end
	local actor = session.byId[action.actorId]
	local ability = Abilities[action.abilityId]
	local summoned = actor ~= nil and Pacing.isSummoned(actor.side, actor.abilities, action.abilityId)
	return Pacing.resolveSeconds(ability, action.results, summoned, if actor then actor.side else nil)
end

function BattleDirector._showResults(self: BattleDirector)
	if self.overworldReturnAt ~= nil then
		return
	end
	self.turnDeadline = nil
	self.overworldReturnAt = self.deps.now() + CombatConfig.ResultScreenSeconds
	self:_after(CombatConfig.ResultScreenSeconds, function()
		self:_endBattle()
	end)
end

-- The fight is over (or was reset): clear it, and hand everyone back to the overworld.
function BattleDirector._endBattle(self: BattleDirector)
	local session = self.session
	self.session = nil
	self.startedBy = nil
	self.turnDeadline = nil
	self.overworldReturnAt = nil
	if session then
		self.deps.battleEnded(session.winner)
	end
end

--[[ Helpers ]]

-- Runs `callback` later, but only if the battle is still on the same turn and phase by then. If
-- it has moved on (the player acted, someone left, the battle ended), the callback is dropped,
-- so a stale timer can never act on the wrong turn.
function BattleDirector._after(self: BattleDirector, seconds: number, callback: () -> ())
	local session = self.session
	if session == nil then
		return
	end
	local turnNumber, phase = session.turnNumber, session.phase
	self.deps.delay(seconds, function()
		if self.session ~= session or session.turnNumber ~= turnNumber or session.phase ~= phase then
			return
		end
		self:_protect(callback)
		self:_broadcast()
	end)
end

-- Last line of defense for "nobody has to step in": if a bug throws mid-battle, end the fight
-- instead of leaving everyone stuck on a frozen turn. The error still shows in the output.
function BattleDirector._protect(self: BattleDirector, callback: () -> ())
	local failure: string? = nil
	xpcall(callback, function(err)
		failure = debug.traceback(tostring(err), 2)
	end)
	if failure == nil then
		return
	end
	warn(`[BattleDirector] Battle error, returning everyone to the overworld:\n{failure}`)
	self:_endBattle()
	for _, member in self.members do
		self.deps.notify(member.userId, "Something went wrong, so the battle was reset.")
	end
end

function BattleDirector._findMember(self: BattleDirector, userId: number): Member?
	for _, member in self.members do
		if member.userId == userId then
			return member
		end
	end
	return nil
end

function BattleDirector._broadcast(self: BattleDirector)
	self.deps.broadcast(self:getSnapshot())
end

return BattleDirector
