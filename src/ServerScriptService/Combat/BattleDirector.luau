--!strict
--[[
	BattleDirector — runs the arena: the ready-up lobby, and the real-time loop around a
	BattleSession (turn timers, enemy turns, pacing, players leaving). One per server, one battle at
	a time.

	It doesn't call Roblox APIs itself: BattleServer hands it the clock, the scheduler, the RNG and
	the functions that reach clients. That keeps this file about game flow, and lets it run
	outside Studio.

	Lobby rule: players press Ready, and after a short countdown the battle starts once everyone in
	the server is ready, or once a full party (CombatConfig.MaxPartySize) is. Anyone else watches
	and can join the next battle.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BattleTypes = require(ReplicatedStorage.Combat.BattleTypes)
local CombatConfig = require(ReplicatedStorage.Combat.CombatConfig)
local BattleSession = require(script.Parent.BattleSession)
local EnemyAI = require(script.Parent.EnemyAI)

export type Dependencies = {
	now: () -> number, -- server clock that clients share: workspace:GetServerTimeNow()
	delay: (seconds: number, callback: () -> ()) -> (), -- task.delay
	rng: Random,
	broadcast: (snapshot: BattleTypes.Snapshot) -> (), -- send the latest state to every client
	notify: (userId: number, message: string) -> (), -- tell one player why a request was refused
}

type Member = {
	userId: number,
	name: string,
	ready: boolean,
}

local BattleDirector = {}
BattleDirector.__index = BattleDirector

type DirectorFields = {
	deps: Dependencies,
	members: { Member }, -- everyone in the server, in join order
	session: BattleSession.BattleSession?,
	battleCount: number,
	countdownEndsAt: number?,
	countdownId: number, -- bumped to cancel a pending countdown
	turnDeadline: number?,
	lobbyReturnAt: number?,
}

export type BattleDirector = typeof(setmetatable({} :: DirectorFields, BattleDirector))

function BattleDirector.new(deps: Dependencies): BattleDirector
	local fields: DirectorFields = {
		deps = deps,
		members = {},
		session = nil,
		battleCount = 0,
		countdownEndsAt = nil,
		countdownId = 0,
		turnDeadline = nil,
		lobbyReturnAt = nil,
	}
	return setmetatable(fields, BattleDirector)
end

--[[ Called by BattleServer. Each one broadcasts the new state when something changed. ]]

function BattleDirector.playerJoined(self: BattleDirector, userId: number, name: string)
	if self:_findMember(userId) then
		return
	end
	table.insert(self.members, { userId = userId, name = name, ready = false })
	self:_refreshCountdown()
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
	self:_refreshCountdown()
	self:_broadcast()
end

function BattleDirector.setReady(self: BattleDirector, userId: number, ready: boolean)
	local member = self:_findMember(userId)
	if member == nil then
		return
	end
	if self.session then
		self.deps.notify(userId, "A battle is already running. Ready up when it ends.")
		return
	end
	if member.ready == ready then
		return -- nothing changed, so nothing to broadcast
	end
	member.ready = ready
	self:_refreshCountdown()
	self:_broadcast()
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
			self:_afterTurn()
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
	local members: { BattleTypes.LobbyMember } = {}
	for _, member in self.members do
		table.insert(members, { userId = member.userId, name = member.name, ready = member.ready })
	end

	local battle: BattleTypes.BattleState? = nil
	if self.session then
		local state = self.session:getState()
		state.turnDeadline = self.turnDeadline
		state.lobbyReturnAt = self.lobbyReturnAt
		battle = state
	end

	return {
		lobby = {
			members = members,
			maxPartySize = CombatConfig.MaxPartySize,
			countdownEndsAt = self.countdownEndsAt,
		},
		battle = battle,
	}
end

--[[ Lobby ]]

-- Starts, keeps or cancels the pre-battle countdown to match who is ready right now.
function BattleDirector._refreshCountdown(self: BattleDirector)
	local readyCount = 0
	for _, member in self.members do
		if member.ready then
			readyCount += 1
		end
	end
	local canStart = self.session == nil
		and readyCount > 0
		and (readyCount == #self.members or readyCount >= CombatConfig.MaxPartySize)

	if not canStart then
		if self.countdownEndsAt ~= nil then
			self.countdownEndsAt = nil
			self.countdownId += 1 -- the pending start sees a different id and does nothing
		end
		return
	end
	if self.countdownEndsAt ~= nil then
		return -- already counting down
	end

	self.countdownId += 1
	local countdownId = self.countdownId
	self.countdownEndsAt = self.deps.now() + CombatConfig.LobbyCountdownSeconds
	self.deps.delay(CombatConfig.LobbyCountdownSeconds, function()
		if self.countdownId ~= countdownId or self.session ~= nil then
			return
		end
		self:_protect(function()
			self:_startBattle()
		end)
		self:_broadcast()
	end)
end

function BattleDirector._startBattle(self: BattleDirector)
	self.countdownEndsAt = nil

	-- The first ready players (in join order) form the party. Everyone's Ready resets for next time.
	local party: { Member } = {}
	for _, member in self.members do
		if member.ready and #party < CombatConfig.MaxPartySize then
			table.insert(party, member)
		end
		member.ready = false
	end
	assert(#party > 0, "The countdown finished with no one ready")

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
	for _, summonId in CombatConfig.EnemySummons do
		local entry: BattleSession.RosterEntry = { side = "Enemy", summonId = summonId }
		table.insert(roster, entry)
	end

	self.battleCount += 1
	local session = BattleSession.new(self.battleCount, roster, self.deps.rng)
	self.session = session
	self.turnDeadline = nil
	self.lobbyReturnAt = nil

	session:rollInitiative()
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
		self:_afterTurn() -- an ailment cost it the turn
	elseif not session:canAffordAnyAbility(actor) then
		session:passTurn("NoMana")
		self:_afterTurn()
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
			self:_afterTurn()
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
	self:_afterTurn()
end

-- The current turn is over (acted, passed, or its player left): pause so everyone can see what
-- happened, then open the next turn, or show the result if the battle just ended.
function BattleDirector._afterTurn(self: BattleDirector)
	local session = self.session :: BattleSession.BattleSession
	self.turnDeadline = nil
	if session.phase == "reward" then
		self:_showResults()
	else
		self:_after(CombatConfig.ResolvePauseSeconds, function()
			self:_beginNextTurn()
		end)
	end
end

function BattleDirector._showResults(self: BattleDirector)
	if self.lobbyReturnAt ~= nil then
		return
	end
	self.turnDeadline = nil
	self.lobbyReturnAt = self.deps.now() + CombatConfig.ResultScreenSeconds
	self:_after(CombatConfig.ResultScreenSeconds, function()
		self:_returnToLobby()
	end)
end

function BattleDirector._returnToLobby(self: BattleDirector)
	self.session = nil
	self.turnDeadline = nil
	self.lobbyReturnAt = nil
	for _, member in self.members do
		member.ready = false
	end
	self:_refreshCountdown()
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

-- Last line of defense for "nobody has to step in": if a bug throws mid-battle, reset to the
-- lobby instead of leaving everyone stuck on a frozen turn. The error still shows in the output.
function BattleDirector._protect(self: BattleDirector, callback: () -> ())
	local failure: string? = nil
	xpcall(callback, function(err)
		failure = debug.traceback(tostring(err), 2)
	end)
	if failure == nil then
		return
	end
	warn(`[BattleDirector] Battle error, returning everyone to the lobby:\n{failure}`)
	self:_returnToLobby()
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
