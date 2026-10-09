--[[
	Headless end-to-end tests. Builds the place with Rojo, then plays it in Lune on a fake Roblox
	(Sim.luau): a server plus a client per test player, all running the real scripts from src/.
	Bots walk into enemies and click the real battle UI, and every update each client receives is
	checked against the rules: whose turn it is, what the HUD offers, who's on the stage, and so on.

	Run from the repo root, after `rokit install`:
		lune run tests/run                 -- everything
		lune run tests/run quick           -- the same, with fewer seeded battles at the end
		lune run tests/run quick Guard     -- only the tests whose names contain "Guard"
		lune run tests/run MyPlace.rbxlx   -- test a place you've already built

	It can't tell you how anything looks: there's no rendering or physics, tweens jump straight to
	where they end, and players' avatars are simple stand-ins. Check those in Studio. When you
	change how the game behaves on purpose, change the tests that pin that behavior down with it.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local Sim = require("./Sim")

local QUICK = false
local ONLY = nil -- run just the tests whose names contain this
local PLACE = nil
for _, arg in process.args do
	if arg == "quick" then
		QUICK = true
	elseif string.find(arg, "%.rbxlx?$") then
		PLACE = arg
	else
		ONLY = arg
	end
end

local function quit(message)
	print(message)
	process.exit(1)
end

if PLACE == nil then
	if not fs.isFile("default.project.json") then
		quit("Run this from the repo root: lune run tests/run")
	end
	PLACE = "tests/place.rbxlx" -- gitignored
	local ok, build = pcall(process.exec, "rojo", { "build", "default.project.json", "--output", PLACE })
	if not ok or not build.ok then
		local details = if ok then build.stderr else string.match(tostring(build), "^[^\n]*") -- no traceback
		if details ~= "" then
			print(details)
		end
		quit("Couldn't build the place with Rojo. Is it installed? Run `rokit install` in the repo root.")
	end
end

local STATE_UPDATE = "ReplicatedStorage.Remotes.Battle.StateUpdate"
local NOTICE = "ReplicatedStorage.Remotes.Battle.Notice"
local SUBMIT = "ReplicatedStorage.Remotes.Battle.SubmitAction"

--[[ Tiny test runner ]]

local passed, failed = 0, 0
local failures = {}

local function test(name, fn)
	if ONLY and string.find(name, ONLY, 1, true) == nil then
		return
	end
	local ok, err = xpcall(fn, function(message)
		return debug.traceback(tostring(message), 2)
	end)
	if ok then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		table.insert(failures, { name = name, err = err })
		print("  FAIL " .. name .. "\n" .. tostring(err))
	end
end

local function expect(condition, message)
	if not condition then
		error(message or "expectation failed", 2)
	end
end

local function expectNear(actual, expected, message)
	if math.abs(actual - expected) > 1e-9 then
		error(`{message or "values differ"}: expected {expected}, got {actual}`, 2)
	end
end

local function expectEqual(actual, expected, message)
	if actual ~= expected then
		error(`{message or "values differ"}: expected {tostring(expected)}, got {tostring(actual)}`, 2)
	end
end

--[[ Server-side observer: checks every snapshot the server sends ]]

local function participantById(battle, id)
	for _, participant in battle.participants do
		if participant.id == id then
			return participant
		end
	end
	return nil
end

local Observer = {}
Observer.__index = Observer

function Observer.attach(sim)
	local self = setmetatable({
		sim = sim,
		violations = {},
		notices = {}, -- [userId] = { messages }
		snapshots = 0,
		last = nil,
		battlesStarted = 0,
		battlesFinished = 0,
		results = {}, -- { winner, rounds, turns, duration, timeouts }
		currentBattleId = nil,
		battleStartTime = nil,
		seenActions = {},
		turnStartMana = {},
		prevHp = {},
		prevMana = {},
		prevTurn = nil,
		guardWaiting = {}, -- [id] = true from a Guard until something attacks it or its next turn comes
		bonusTurnTotals = {}, -- initiative totals of who acted in this battle's bonus turn, in order
		openings = { Party = 0, Enemy = 0, None = 0 }, -- how each battle opened
		timeouts = 0,
		passes = 0,
		firstActors = {},
	}, Observer)

	local server = sim.server
	self.Summons = server.require(server.dm:GetService("ReplicatedStorage").Combat.Summons)
	self.Abilities = server.require(server.dm:GetService("ReplicatedStorage").Combat.Abilities)
	self.Config = server.require(server.dm:GetService("ReplicatedStorage").Combat.CombatConfig)
	self.StatusEffects = server.require(server.dm:GetService("ReplicatedStorage").Combat.StatusEffects)
	self.Pacing = server.require(server.dm:GetService("ReplicatedStorage").Combat.Pacing)
	self.pacingChecks = 0

	table.insert(sim.hooks.serverSend, function(fullName, userId, payload)
		if fullName == NOTICE then
			self.notices[userId] = self.notices[userId] or {}
			table.insert(self.notices[userId], payload[1])
		end
	end)
	table.insert(sim.hooks.serverBroadcast, function(fullName, payload)
		if fullName == STATE_UPDATE then
			self:check(payload[1])
		end
	end)
	return self
end

function Observer:fail(message)
	table.insert(self.violations, `t={string.format("%.2f", self.sim.now)}: {message}`)
end

function Observer:check(snapshot)
	self.snapshots += 1
	self.last = snapshot
	local seen = {}
	for _, player in snapshot.overworld.players do
		if seen[player.userId] then
			self:fail("duplicate player in the overworld list")
		end
		seen[player.userId] = true
	end

	local battle = snapshot.battle
	if battle == nil then
		if self.currentBattleId ~= nil then
			self.currentBattleId = nil
		end
		return
	end

	if battle.battleId ~= self.currentBattleId then
		self.currentBattleId = battle.battleId
		self.battlesStarted += 1
		self.battleStartTime = self.sim.now
		self.prevHp = {}
		self.prevMana = {}
		self.guardWaiting = {}
		self.bonusTurnTotals = {}
		local opening = battle.opening or "None"
		self.openings[opening] += 1
		if battle.opening ~= nil and battle.opening ~= "Party" and battle.opening ~= "Enemy" then
			self:fail("unknown opening " .. tostring(battle.opening))
		end
		if battle.startedBy == nil then
			self:fail("battle has no startedBy")
		end
		self.turnStartMana = {}
		self.seenActions = {}
		self.recorded = false
		self.lastTurnSeen = 0
	end

	-- Health may only go up through a heal in this snapshot's (new) action.
	local healedNow = {}
	local newAction = battle.lastAction
	if newAction and not self.seenActions[newAction.sequence] then
		for _, result in newAction.results do
			healedNow[result.targetId] = (healedNow[result.targetId] or 0) + result.healed
		end
	end

	local byId = {}
	for _, p in battle.participants do
		byId[p.id] = p
		if p.hp < 0 or p.hp > p.maxHp or math.floor(p.hp) ~= p.hp then
			self:fail(`{p.id} hp out of range: {p.hp}/{p.maxHp}`)
		end
		if p.mana < 0 or p.mana > p.maxMana then
			self:fail(`{p.id} mana out of range: {p.mana}/{p.maxMana}`)
		end
		if p.status == "KnockedOut" and p.hp ~= 0 then
			self:fail(`{p.id} knocked out with {p.hp} hp`)
		end
		if p.status == "Active" and p.hp <= 0 then
			self:fail(`{p.id} active at 0 hp`)
		end
		local previous = self.prevHp[p.id]
		if previous and p.hp - previous > (healedNow[p.id] or 0) then
			self:fail(`{p.id} hp went up by more than it was healed ({previous} -> {p.hp})`)
		end
		if p.status ~= "Active" and #p.statuses > 0 then
			self:fail(`{p.id} is {p.status} but still has statuses`)
		end
		self.prevHp[p.id] = p.hp

		local summon = self.Summons[p.summonId]
		local init = p.initiative
		if init == nil then
			self:fail(`{p.id} has no initiative`)
		else
			local expectedBonus = math.floor(summon.stats.Agility / self.Config.AgilityPerInitiativeBonus)
			if init.roll < 1 or init.roll > self.Config.InitiativeDieSides or math.floor(init.roll) ~= init.roll then
				self:fail(`{p.id} initiative roll {init.roll} outside 1..{self.Config.InitiativeDieSides}`)
			end
			if init.bonus ~= expectedBonus or init.total ~= init.roll + init.bonus then
				self:fail(`{p.id} initiative math wrong: {init.roll} + {init.bonus} = {init.total}`)
			end
		end
	end

	-- Turn queue: a permutation of the participants, sorted by total, party first on ties, then slot.
	if #battle.turnQueue ~= #battle.participants then
		self:fail("turn queue size mismatch")
	end
	for index, id in battle.turnQueue do
		if byId[id] == nil then
			self:fail("unknown id in turn queue: " .. tostring(id))
		elseif index > 1 then
			local a, b = byId[battle.turnQueue[index - 1]], byId[id]
			if a and a.initiative and b.initiative then
				local ta, tb = a.initiative.total, b.initiative.total
				local ordered = ta > tb
					or (ta == tb and a.side == "Party" and b.side == "Enemy")
					or (ta == tb and a.side == b.side and a.slot < b.slot)
				if not ordered then
					self:fail(`turn queue order: {a.id}({ta}) before {b.id}({tb})`)
				end
			end
		end
	end

	if battle.turnNumber < self.lastTurnSeen then
		self:fail("turn number went backwards")
	end

	-- Pacing: after a turn resolves, the next one opens exactly Pacing.resolveSeconds later, for
	-- what that turn did (its new action, or nothing when it passed or was lost). A snapshot that
	-- only repeats the resolve (someone left) doesn't restart the clock.
	if battle.phase == "resolve" then
		local resolveAction = battle.lastAction
		local fresh = resolveAction ~= nil and not self.seenActions[resolveAction.sequence]
		if self.resolveTurn ~= battle.turnNumber then
			self.resolveTurn = battle.turnNumber
			self.resolveAt = self.sim.now
			local expected = self.Pacing.resolveSeconds(nil, nil, false)
			if fresh and resolveAction then
				local attacker = byId[resolveAction.actorId]
				local ability = self.Abilities[resolveAction.abilityId]
				local summoned = attacker ~= nil and self.Pacing.isSummoned(attacker.side, attacker.abilities, resolveAction.abilityId)
				expected = self.Pacing.resolveSeconds(ability, resolveAction.results, summoned, if attacker then attacker.side else nil)
			end
			self.resolveExpected = expected
		end
	elseif battle.phase == "input" and self.resolveAt ~= nil then
		local gap = self.sim.now - self.resolveAt
		if math.abs(gap - self.resolveExpected) > 1e-6 then
			self:fail(`turn {battle.turnNumber} opened {string.format("%.3f", gap)}s after the last resolve; Pacing says {string.format("%.3f", self.resolveExpected)}s`)
		end
		self.pacingChecks += 1
		self.resolveAt = nil
		self.resolveTurn = nil
	elseif battle.phase ~= "input" then
		self.resolveAt = nil
		self.resolveTurn = nil
	end
	if battle.turnNumber > self.lastTurnSeen and battle.currentActorId then
		self.guardWaiting[battle.currentActorId] = nil -- its Guard ended as its turn began
	end
	self.lastTurnSeen = battle.turnNumber

	local actor = if battle.currentActorId then byId[battle.currentActorId] else nil
	if battle.phase == "input" then
		if actor == nil or actor.status ~= "Active" then
			self:fail("input phase without an active actor")
		else
			if actor.ownerUserId ~= nil and battle.turnDeadline == nil then
				self:fail("player turn without a deadline")
			end
			if actor.ownerUserId == nil and battle.turnDeadline ~= nil then
				self:fail("enemy turn with a deadline")
			end
			self.turnStartMana[battle.turnNumber] = self.turnStartMana[battle.turnNumber] or actor.mana
			if battle.turnNumber == 1 then
				self.firstActors[battle.battleId] = actor
				-- A bonus turn comes first (round 0) for the side that struck first; else round 1.
				if battle.opening then
					if battle.round ~= 0 or actor.side ~= battle.opening then
						self:fail(`first turn went to {actor.id} in round {battle.round}, but {battle.opening} struck first`)
					end
				elseif battle.round ~= 1 then
					self:fail(`an even start should begin in round 1, not {battle.round}`)
				end
			end
			if battle.round == 0 and battle.opening == nil then
				self:fail("a bonus turn without an opening")
			end
		end
	elseif battle.turnDeadline ~= nil then
		self:fail(`deadline set during {battle.phase}`)
	end

	-- Every resolved action: happened on its own turn, by the current actor, on a legal target,
	-- cost the right Mana, and did damage in range.
	local action = battle.lastAction
	if action and not self.seenActions[action.sequence] then
		self.seenActions[action.sequence] = battle.turnNumber
		for sequence, turn in self.seenActions do
			if sequence ~= action.sequence and turn == battle.turnNumber then
				self:fail(`two actions in turn {battle.turnNumber}`)
			end
		end
		local attacker = byId[action.actorId]
		local ability = self.Abilities[action.abilityId]
		if attacker and battle.round == 0 then
			-- The bonus turn: only the side that struck first, each summon once, in initiative order.
			if attacker.side ~= battle.opening then
				self:fail(`{attacker.id} acted in the bonus turn, but {tostring(battle.opening)} struck first`)
			end
			local total = attacker.initiative and attacker.initiative.total or 0
			local previous = self.bonusTurnTotals[#self.bonusTurnTotals]
			if previous and total > previous then
				self:fail("bonus turn out of initiative order")
			end
			table.insert(self.bonusTurnTotals, total)
			self.bonusTurnActors = self.bonusTurnActors or {}
			if self.bonusTurnActors[`{battle.battleId}/{attacker.id}`] then
				self:fail(`{attacker.id} acted twice in the bonus turn`)
			end
			self.bonusTurnActors[`{battle.battleId}/{attacker.id}`] = true
		end
		if attacker == nil or ability == nil or #action.results == 0 then
			self:fail("action references unknown ids or has no results")
		else
			if battle.phase ~= "reward" and battle.currentActorId ~= action.actorId then
				self:fail("action by someone other than the current actor")
			end
			local startMana = self.turnStartMana[battle.turnNumber]
			if startMana and attacker.mana ~= startMana - ability.manaCost then
				self:fail(`mana accounting: {startMana} - {ability.manaCost} ~= {attacker.mana}`)
			end
			for _, result in action.results do
				local target = byId[result.targetId]
				if target == nil then
					self:fail("result for an unknown target")
					continue
				end
				local sameSide = target.side == attacker.side
				if (ability.targets == "Enemy") == sameSide then
					self:fail(`{ability.id} ({ability.targets}) affected {target.id} on the wrong side`)
				end
				if ability.targets == "Self" and target.id ~= attacker.id then
					self:fail(`{ability.id} should only affect its user`)
				end

				if ability.kind == "Attack" then
					self.attacks = (self.attacks or 0) + 1
					-- Being attacked never changes the target's Mana, guarding or not: Guard is purely
					-- defensive (GDD Step 6, "Guard's Mana bonus removed entirely").
					if self.guardWaiting[target.id] then
						self.guardsAttacked = (self.guardsAttacked or 0) + 1
					end
					self.guardWaiting[target.id] = nil
					local before = self.prevMana[target.id]
					if before and self.prevTurn == battle.turnNumber and target.mana ~= before then
						self:fail(`attacking {target.id} changed its Mana: {before} -> {target.mana}`)
					end
					if not result.hit then
						self.misses = (self.misses or 0) + 1
						if result.damage ~= 0 or result.knockedOut or result.inflicted then
							self:fail("a miss did something")
						end
					else
						if result.critical then
							self.crits = (self.crits or 0) + 1
						end
						if result.inflicted then
							self.inflicted = (self.inflicted or 0) + 1
						end
						-- Exact damage range: base * variance * crit * (1 - Endurance share) * Guarded.
						local summon = self.Summons[attacker.summonId]
						local base = ability.power + summon.stats[ability.scalingStat] * ability.statRatio
						local targetSummon = self.Summons[target.summonId]
						local reduction = math.clamp(
							targetSummon.stats.Endurance * self.Config.DamageReductionPerEndurance,
							0,
							self.Config.MaxDamageReduction
						)
						local guard = 1
						local bracing = false
						for _, status in target.statuses do
							guard *= self.StatusEffects[status.id].damageTakenMultiplier or 1
							bracing = bracing or self.StatusEffects[status.id].blocksCriticals == true
						end
						if result.critical and bracing then
							self:fail(`critical hit on {target.id} while it was guarding`)
						end
						-- Statuses clear on a knockout, so then allow anything from every damage-cutting
						-- status at once (Guarded * Bracing) to none.
						local strongest = 1
						for _, def in self.StatusEffects do
							strongest *= def.damageTakenMultiplier or 1
						end
						local crit = if result.critical then self.Config.CriticalMultiplier else 1
						local function taken(multiplier)
							-- Endurance, then statuses, multiplied; the total cut is capped.
							return math.max((1 - reduction) * multiplier, 1 - self.Config.MaxTotalDamageReduction)
						end
						local lowGuard = if result.knockedOut then strongest else guard
						local highGuard = if result.knockedOut then 1 else guard
						local low = math.max(1, math.round(base * (1 - self.Config.DamageVariance) * crit * taken(lowGuard)))
						local high = math.max(1, math.round(base * (1 + self.Config.DamageVariance) * crit * taken(highGuard)))
						if result.damage < low or result.damage > high then
							self:fail(`{ability.id} damage {result.damage} outside {low}..{high} on {target.id}`)
						end
						if result.knockedOut ~= (target.hp == 0) then
							self:fail("knockedOut flag mismatch")
						end
						if result.inflicted then
							local def = self.StatusEffects[result.inflicted]
							local has = false
							for _, status in target.statuses do
								has = has or status.id == result.inflicted
							end
							if def == nil or def.kind ~= "Ailment" or not has then
								self:fail(`inflicted {result.inflicted} didn't stick to {target.id}`)
							end
						end
					end
				elseif ability.kind == "Heal" then
					self.heals = (self.heals or 0) + 1
					if result.healed < 0 or result.damage ~= 0 then
						self:fail("bad heal result")
					end
				else
					if ability.kind == "Guard" then
						self.guards = (self.guards or 0) + 1
						self.guardWaiting[target.id] = true
						if ability.manaCost ~= 0 or target.id ~= attacker.id then
							self:fail("Guard should be free and affect only its user")
						end
					else
						self.buffs = (self.buffs or 0) + 1
					end
					local has = false
					for _, status in target.statuses do
						has = has or status.id == ability.status
					end
					if result.applied ~= ability.status or not has then
						self:fail(`{ability.id} didn't apply {ability.status} to {target.id}`)
					end
				end
			end
		end
	end

	for _, line in battle.log do
		if string.find(line, "ran out of time", 1, true) then
			self.sawTimeout = true
		end
		if string.find(line, "loses its turn", 1, true) then
			self.sawLostTurn = true
		end
	end

	if battle.phase == "reward" then
		if battle.winner == nil then
			self:fail("reward without a winner")
		end
		if battle.currentActorId ~= nil then
			self:fail("reward phase still has an actor")
		end
		if battle.overworldReturnAt == nil then
			self:fail("reward phase without overworldReturnAt")
		end
		local standing = { Party = false, Enemy = false }
		for _, p in battle.participants do
			if p.status == "Active" then
				standing[p.side] = true
			end
		end
		if battle.winner == "Party" and standing.Enemy then
			self:fail("party won with enemies standing")
		elseif battle.winner == "Enemy" and standing.Party then
			self:fail("enemies won with party members standing")
		end
		if not self.recorded then
			self.recorded = true
			self.battlesFinished += 1
			table.insert(self.results, {
				winner = battle.winner,
				rounds = battle.round,
				turns = battle.turnNumber,
				duration = self.sim.now - self.battleStartTime,
			})
		end
	elseif battle.winner ~= nil then
		self:fail("winner set before the reward phase")
	end

	if #battle.log > self.Config.LogLinesShown then
		self:fail("log longer than LogLinesShown")
	end

	for _, p in battle.participants do
		self.prevMana[p.id] = p.mana
	end
	self.prevTurn = battle.turnNumber
end

--[[ Client-side checker: after each render, the UI must match the state it was given ]]

-- On a player's turn, the action panel must offer exactly what's legal: every ability button is
-- clickable only if affordable, one affordable ability is selected, and the target buttons are
-- exactly the legal targets for that ability (none at all for Self / AllAllies abilities).
-- The HUD's offer on the player's turn, against the rules: exactly one chooser (the ring, the
-- skill list or the target panel) unless the request is on its way; the character's own moves
-- always on; the summon's kit as rows, dimmed when it can't afford one; and a pick offered for
-- exactly the summons the server would accept.
local function checkChooser(observer, client, battle, actor)
	local safeArea = client.playerGui.CombatHUD.SafeArea
	local theme = client.env.require(client.env.dm:GetService("ReplicatedStorage").UI.Theme)
	local strings = client.env.require(client.env.dm:GetService("ReplicatedStorage").UI.Strings)
	local ring, target, list = safeArea.Ring, safeArea.TargetPanel, client.playerGui.SkillList
	local open = (if ring.Visible then 1 else 0) + (if target.Visible then 1 else 0) + (if list.Enabled then 1 else 0)
	if open == 0 then
		-- Nothing on offer is fine only while the request is away, or while the stage is still
		-- playing the last beat (the ring waits for it, at most CombatHUD.RING_WAIT_CAP).
		if safeArea.Status.Detail.Text ~= strings.Sending and client.playerGui:GetAttribute("StageBusy") ~= true then
			observer:fail(`{client.name}: nothing to choose on their turn`)
		end
		return
	elseif open > 1 then
		observer:fail(`{client.name}: two choosers at once`)
		return
	end
	if ring.Visible then
		for _, name in { "Attack", "Guard" } do
			if not Sim.isClickable(ring:FindFirstChild(name)) then
				observer:fail(`{client.name}: no {name} ribbon on their turn`)
			end
		end
		if Sim.isClickable(ring.Spell) ~= (#actor.abilities > 0) then
			observer:fail(`{client.name}: Spell offered={Sim.isClickable(ring.Spell)} with {#actor.abilities} abilities`)
		end
		if ring:FindFirstChild("Item") ~= nil or ring:FindFirstChild("Pass") ~= nil then
			observer:fail(`{client.name}: Item and Pass are behind their flags`)
		end
	elseif list.Enabled then
		local names = {}
		for _, row in list.SafeArea.List.Rows:GetChildren() do
			if row:IsA("GuiButton") then
				table.insert(names, row.Name)
				local ability = observer.Abilities[row.Name]
				local affordable = ability ~= nil and actor.mana >= ability.manaCost
				local dimmed = row.Title.TextColor3 == theme.Colors.TextDim
				if dimmed == affordable then
					observer:fail(`{client.name}: row {row.Name} dimmed={dimmed} affordable={affordable}`)
				end
			end
		end
		table.sort(names)
		local kit = table.clone(actor.abilities)
		table.sort(kit)
		if table.concat(names, ",") ~= table.concat(kit, ",") then
			observer:fail(`{client.name}: the list has {table.concat(names, ",")}, not the summon's abilities`)
		end
	else
		local plates = client.playerGui:FindFirstChild("CombatHUDEnemies")
		local offered, anyEnemy, anyAlly = {}, false, false
		for _, p in battle.participants do
			if p.side == "Enemy" then
				local plate = plates and plates:FindFirstChild("Enemy_" .. p.id)
				offered[p.id] = plate ~= nil and Sim.isClickable(plate.Root.Plate)
				anyEnemy = anyEnemy or offered[p.id]
			else
				local card = safeArea.Party:FindFirstChild("Card_" .. p.id)
				offered[p.id] = card ~= nil and Sim.isClickable(card)
				anyAlly = anyAlly or offered[p.id]
			end
		end
		if anyEnemy == anyAlly then
			observer:fail(`{client.name}: a pick is among the enemies or among the party, never both or neither`)
		end
		for _, p in battle.participants do
			local legal = p.status == "Active" and ((anyEnemy and p.side ~= actor.side) or (anyAlly and p.side == actor.side))
			if offered[p.id] ~= legal then
				observer:fail(`{client.name}: target {p.id} offered={offered[p.id]} legal={legal}`)
			end
		end
		local picks = 0
		for _, p in battle.participants do
			if p.side == "Enemy" then
				local plate = plates and plates:FindFirstChild("Enemy_" .. p.id)
				if plate and plate.Root.BracketLeft.Visible and plate.Root.BracketLeft.BackgroundColor3 == theme.Colors.Gold then
					picks += 1
				end
			else
				local card = safeArea.Party:FindFirstChild("Card_" .. p.id)
				local stroke = card and card:FindFirstChildOfClass("UIStroke")
				if stroke and stroke.Color == theme.Colors.HpGreen then
					picks += 1
				end
			end
		end
		if picks ~= 1 then
			observer:fail(`{client.name}: {picks} summons marked as the pick`)
		end
		if not Sim.isClickable(target.Confirm) then
			observer:fail(`{client.name}: Confirm not clickable with a pick made`)
		end
	end
end

local function isInBattle(battle, userId)
	for _, p in battle.participants do
		if p.ownerUserId == userId then
			return true
		end
	end
	return false
end

-- Who's on the field (GDD Step 6, "The player character on the field", Stand/Persona-style): a
-- party member's spot always shows its player's character, plus its summon while that's out for one
-- of its own abilities, at its socket behind the character; an enemy's spot shows its creature.
local SUMMON_SECONDS = 1.2 -- BattleView's
local SUMMON_FADE_SECONDS = 0.2

-- A summon on the stage is a Model: its real model (Summons art) or a colored block. Its body is
-- its tallest part (the block, or a rig's skinned mesh), which BattleView places; its root is the
-- anchored part the rest hangs off, which lunges.
local function summonBody(summon)
	local tallest = nil
	for _, part in summon:GetDescendants() do
		if part:IsA("BasePart") and (tallest == nil or part.Size.Y > tallest.Size.Y) then
			tallest = part
		end
	end
	return tallest
end

local function summonRoot(summon)
	return summon.PrimaryPart or summonBody(summon)
end

-- Where a summon that's out stands, measured from its spot (which faces the enemies): behind the
-- character and up over its shoulder, clear of it. That's where it shows once its clips play: a
-- model whose clips lift it (Summons art.groundOffset) is placed that much lower.
local function socketOffset(spot, summonDef)
	local body = summonBody(spot.Summon)
	local art = summonDef.art
	local lift = if art and art.groundOffset and spot.Summon:FindFirstChild("Block") == nil then art.groundOffset * body.Size.Y else 0
	local offset = body.CFrame.Position - spot.Spot.CFrame.Position -- (Lune can't read Part.Position)
	return offset:Dot(-spot.Spot.CFrame.LookVector), offset.Y + lift
end

local function checkStage(observer, client, battle, stage)
	local now = observer.sim.now
	client.summonUntil = client.summonUntil or {}
	local action = battle.lastAction
	local key = if action then `{battle.battleId}:{action.sequence}` else nil
	local fresh = key ~= nil and key ~= client.lastStageAction
	client.lastStageAction = key
	for _, p in battle.participants do
		local spot = stage:FindFirstChild(p.id)
		local character = if spot then spot:FindFirstChild("Character") else nil
		local summon = if spot then spot:FindFirstChild("Summon") else nil
		if spot == nil then
			observer:fail(`{client.name}: no spot for {p.id} on the stage`)
		elseif p.side == "Enemy" then
			if character ~= nil or summon == nil then
				observer:fail(`{client.name}: {p.id} should only ever show its creature`)
			end
		elseif character == nil then
			observer:fail(`{client.name}: {p.id}'s character left the field`)
		else
			local expectSummon = nil -- nil: it may be on its way out
			client.seenDown = client.seenDown or {}
			local downKey = `{battle.battleId}:{p.id}`
			if p.status == "KnockedOut" and not client.seenDown[downKey] then
				-- Knocked out just now: its summon may come out to fall (with a death clip), once the
				-- blow that felled it has landed (up to about a second after the snapshot).
				client.seenDown[downKey] = true
				client.summonUntil[p.id] = math.max(client.summonUntil[p.id] or 0, now + SUMMON_SECONDS + 1)
			elseif fresh and action.actorId == p.id then
				expectSummon = table.find(p.abilities, action.abilityId) ~= nil
				if expectSummon then
					client.summonUntil[p.id] = now + SUMMON_SECONDS
				end
			elseif now >= (client.summonUntil[p.id] or 0) + 0.1 then
				expectSummon = false
			end
			if expectSummon == true and summon == nil then
				observer:fail(`{client.name}: {p.id}'s summon should appear for its own {action.abilityId}`)
			elseif expectSummon == false and summon ~= nil then
				observer:fail(`{client.name}: {p.id}'s summon should only be out for its own abilities`)
			end
			if summon ~= nil then
				local behind, up = socketOffset(spot, observer.Summons[p.summonId])
				if behind < 3 or up < 3 then
					observer:fail(`{client.name}: {p.id}'s summon should be behind and above its character ({behind}, {up})`)
				end
			end
		end
	end
end

-- Whether this client's HUD is showing a fight.
local function hudInBattle(client)
	local gui = client.playerGui:FindFirstChild("CombatHUD")
	if gui == nil then
		return false
	end
	local safeArea = gui.SafeArea
	local results, list = client.playerGui:FindFirstChild("Results"), client.playerGui:FindFirstChild("SkillList")
	return safeArea.Party.Visible or safeArea.TurnBar.Visible or safeArea.Reveal.Visible or (results ~= nil and results.Enabled) or (list ~= nil and list.Enabled)
end

local function attachClientChecker(sim, observer, client)
	local dm = client.env.dm
	local Strings = client.env.require(dm:GetService("ReplicatedStorage").UI.Strings)
	local Controls = client.env.require(dm:GetService("StarterPlayer").StarterPlayerScripts.UI.Core.Controls)
	local signal = sim:clientSignal(STATE_UPDATE, client.userId)
	signal:Connect(function(snapshot)
		client.lastSnapshot = snapshot
		local gui = client.playerGui:FindFirstChild("CombatHUD")
		if gui == nil then
			observer:fail(client.name .. ": no CombatHUD")
			return
		end
		local safeArea = gui.SafeArea
		local results = client.playerGui.Results
		local battle = snapshot.battle
		local inBattle = battle ~= nil and isInBattle(battle, client.userId)
		-- Touch controls are off exactly while in a fight (R21).
		if Controls.isEnabled() == inBattle then
			observer:fail(`{client.name}: touch controls enabled={Controls.isEnabled()} but inBattle={inBattle}`)
		end
		local workspace = client.env.dm:GetService("Workspace")
		local stage = workspace:FindFirstChild("BattleStage")
		local camera = workspace.CurrentCamera
		if not inBattle then
			-- Out of a fight: no battle widgets, and the overworld notice says whether a fight is on.
			if hudInBattle(client) then
				observer:fail(client.name .. ": battle widgets up outside a fight they're in")
			end
			if stage ~= nil then
				observer:fail(client.name .. ": battle stage shown outside a battle they're in")
			end
			if camera.CameraType.Name == "Scriptable" then
				observer:fail(client.name .. ": battle camera left on in the overworld")
			end
			local status = safeArea.Overworld.Panel.Content.Status
			if battle ~= nil and not safeArea.Overworld.Visible then
				observer:fail(client.name .. ": a fight is on, but the overworld notice isn't up to say so")
			end
			if status.Visible ~= (battle ~= nil) then
				observer:fail(client.name .. ": overworld doesn't say whether a fight is on")
			end
			return
		end

		if stage == nil or #stage:GetChildren() ~= #battle.participants + 1 then -- a spot each, and a floor
			observer:fail(client.name .. ": stage spots missing")
		else
			checkStage(observer, client, battle, stage)
		end
		if camera.CameraType.Name ~= "Scriptable" then
			observer:fail(client.name .. ": battle camera not set")
		end
		-- The server waits Pacing seconds; the stage's beat is shorter than that by design, so no
		-- turn ever opens while the stage is still busy.
		if battle.phase == "input" and client.playerGui:GetAttribute("StageBusy") == true then
			observer:fail(`{client.name}: turn {battle.turnNumber} opened while the stage was still busy`)
		end
		local actor = if battle.currentActorId then participantById(battle, battle.currentActorId) else nil
		local myTurn = battle.phase == "input" and actor ~= nil and actor.ownerUserId == client.userId
		local title = safeArea.Status.Title.Text
		if myTurn ~= (string.find(title, Strings.YourTurn, 1, true) ~= nil) then
			observer:fail(`{client.name}: status "{title}" but myTurn={myTurn}`)
		end
		-- While initiative is revealed the headline says how the fight opened; a bonus turn says so too.
		if battle.phase == "setup" then
			local expected = if battle.opening == "Party"
				then "struck first"
				elseif battle.opening == "Enemy" then "Ambushed"
				else "Encounter"
			local headline = safeArea.Reveal.Panel.Content.Title.Text
			if not safeArea.Reveal.Visible or not string.find(headline, expected, 1, true) then
				observer:fail(`{client.name}: setup reveal "{headline}" (visible={safeArea.Reveal.Visible}) for opening {tostring(battle.opening)}`)
			end
		elseif battle.phase ~= "reward" and battle.round == 0 and not string.find(title, Strings.BonusTurn, 1, true) then
			observer:fail(`{client.name}: bonus turn status says "{title}"`)
		end
		if myTurn then
			checkChooser(observer, client, battle, actor)
		elseif safeArea.Ring.Visible or safeArea.TargetPanel.Visible or client.playerGui.SkillList.Enabled then
			observer:fail(client.name .. ": choices offered off their turn")
		end
		-- Party cards track HP, knockouts and status effects; enemy plates track HP and sit over
		-- their enemy, with BattleView's own plate off (R19).
		local plates = client.playerGui:FindFirstChild("CombatHUDEnemies")
		for _, p in battle.participants do
			if p.side == "Party" then
				local card = safeArea.Party:FindFirstChild("Card_" .. p.id)
				if card == nil then
					observer:fail(`{client.name}: no card for {p.id}`)
				else
					if card.Content.Hp.Value.Text ~= Strings.format.hp(p.hp, p.maxHp) then
						observer:fail(`{client.name}: {p.id}'s card HP is stale`)
					end
					if card.Content.StatusTag.Visible ~= (p.status ~= "Active") then
						observer:fail(`{client.name}: {p.id}'s KO tag is wrong`)
					end
					local owner = if p.ownerUserId == client.userId then Strings.format.you(p.ownerName or "") else (p.ownerName or "")
					if card.Content.Owner.Text ~= owner then
						observer:fail(`{client.name}: {p.id}'s card says "{card.Content.Owner.Text}", not whose summon it is`)
					end
					for _, status in p.statuses do
						local def = observer.StatusEffects[status.id]
						if not string.find(card.Content.Statuses.Text, if def then def.name else status.id, 1, true) then
							observer:fail(`{client.name}: {status.id} missing from {p.id}'s card`)
						end
					end
				end
			else
				local plate = if plates then plates:FindFirstChild("Enemy_" .. p.id) else nil
				local spot = if stage and stage:FindFirstChild(p.id) then stage[p.id]:FindFirstChild("Spot") else nil
				if plate == nil then
					observer:fail(`{client.name}: no plate for {p.id}`)
				elseif plate.Root.Plate.Hp.Value.Text ~= Strings.format.hp(p.hp, p.maxHp) then
					observer:fail(`{client.name}: {p.id}'s plate HP is stale`)
				elseif spot == nil or plate.Adornee ~= spot or not plate.Enabled then
					observer:fail(`{client.name}: {p.id}'s plate isn't over its enemy`)
				elseif spot.Nameplate.Enabled then
					observer:fail(`{client.name}: BattleView's plate for {p.id} is still on (R19)`)
				else
					local tags = 0
					for _, tag in plate.Root.Statuses:GetChildren() do
						if tag:IsA("ImageLabel") then
							tags += 1
							local known = false
							for _, status in p.statuses do
								local def = observer.StatusEffects[status.id]
								known = known or tag.Label.Text == Strings.format.statusTurns(if def then def.name else status.id, status.turnsLeft)
							end
							if not known then
								observer:fail(`{client.name}: {p.id}'s plate shows a status it doesn't have ({tag.Label.Text})`)
							end
						end
					end
					if tags ~= #p.statuses then
						observer:fail(`{client.name}: {p.id}'s plate shows {tags} status tags for {#p.statuses} statuses`)
					end
				end
			end
		end
		-- The recent-actions feed shows the last log lines while the fight is on.
		local feedOn = (battle.phase == "input" or battle.phase == "resolve") and #battle.log > 0
		if safeArea.Log.Visible ~= feedOn then
			observer:fail(`{client.name}: the recent-actions feed visible={safeArea.Log.Visible}`)
		elseif feedOn then
			local last = battle.log[#battle.log]
			if string.sub(safeArea.Log.Lines.Text, -#last) ~= last then
				observer:fail(`{client.name}: the feed doesn't end with the latest log line`)
			end
		end
		-- The results screen opens once the fight is decided, after the stage has played the final
		-- blow (it waits while the stage is busy, at most CombatHUD.RESULTS_WAIT_CAP).
		if results.Enabled and battle.phase ~= "reward" then
			observer:fail(client.name .. ": the results screen is up before the fight is decided")
		elseif battle.phase == "reward" and not results.Enabled and client.playerGui:GetAttribute("StageBusy") ~= true then
			observer:fail(client.name .. ": the results screen isn't up although the stage is idle")
		end
	end)
end

--[[ Bots: play through the real UI, clicking only what a player could click ]]

local Bot = {}
Bot.__index = Bot

function Bot.new(sim, client, options, observer)
	local self = setmetatable({
		sim = sim,
		client = client,
		observer = observer,
		options = options,
		busy = false,
		turnsTaken = 0,
	}, Bot)
	client.env.heartbeat:Connect(function()
		self:step()
	end)
	return self
end

function Bot:later(seconds, fn)
	self.busy = true
	self.sim:delay(seconds, function()
		self.busy = false
		fn()
	end, "bot " .. self.client.name)
end

local function clickableChildren(container)
	local list = {}
	for _, child in container:GetChildren() do
		if child:IsA("GuiButton") and Sim.isClickable(child) then
			table.insert(list, child)
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

function Bot:step()
	if self.busy then
		return
	end
	local sim, client, options = self.sim, self.client, self.options
	if client.playerGui:FindFirstChild("CombatHUD") == nil then
		return
	end
	-- (The overworld notice only shows for a moment on arriving, so "exploring" is "not in a fight".)
	if not hudInBattle(client) then
		-- Exploring: walk into the nearest enemy, from the front, back or side ("random" mixes them).
		if options.engage then
			self:later(options.engageDelay or 0.8, function()
				if hudInBattle(client) then
					return
				end
				local root = sim:rootPart(client.userId)
				local nearest, bestDistance = nil, math.huge
				for _, enemy in sim:overworldEnemies() do
					local distance = if root then (enemy.CFrame.Position - root.CFrame.Position).Magnitude else 0
					if distance < bestDistance then
						nearest, bestDistance = enemy, distance
					end
				end
				if nearest then
					local how = options.engage
					if how == "random" then
						how = ({ "front", "back", "side" })[math.random(3)]
					end
					sim:touchEnemy(client.userId, nearest, how)
				end
			end)
		end
		return
	end
	if options.afkInBattle then
		return
	end
	local ring = sim:gui(client, "Ring")
	if ring and ring.Visible and Sim.isClickable(ring.Attack) then
		local think = options.thinkMin + math.random() * (options.thinkMax - options.thinkMin)
		self:later(think, function()
			self:takeTurn()
		end)
	end
end

-- The HP a plate or card shows, for picking the most hurt target.
local function shownHp(valueLabel)
	return tonumber(string.match(valueLabel.Text, "(%d+) / %d+")) or math.huge
end

function Bot:takeTurn()
	local sim, client = self.sim, self.client
	local safeArea = client.playerGui.CombatHUD.SafeArea
	local ring, target, list = safeArea.Ring, safeArea.TargetPanel, client.playerGui.SkillList
	if not ring.Visible then
		return
	end
	local battle = client.lastSnapshot and client.lastSnapshot.battle
	local actor = battle and battle.currentActorId and participantById(battle, battle.currentActorId)
	if actor == nil then
		return
	end

	-- 1. Pick a move: "greedy" takes the priciest ability it can afford, "guard" alternates Guard
	-- with that, "attack" sticks to the character's swing, otherwise any move.
	local affordable = {}
	for _, abilityId in actor.abilities do
		local ability = self.observer.Abilities[abilityId]
		if ability and actor.mana >= ability.manaCost then
			table.insert(affordable, abilityId)
		end
	end
	local policy = self.options.policy
	local choice = "Attack"
	local guardNow = false
	if policy == "guard" then
		self.guardedLast = not self.guardedLast
		guardNow = self.guardedLast
	end
	if guardNow then
		choice = "Guard"
	elseif policy == "attack" then
		choice = "Attack"
	elseif policy == "greedy" or policy == "guard" then
		local best = nil
		for _, abilityId in affordable do
			if best == nil or self.observer.Abilities[abilityId].manaCost > self.observer.Abilities[best].manaCost then
				best = abilityId
			end
		end
		choice = best or "Attack"
	else
		local moves = { "Attack", "Guard" }
		for _, abilityId in affordable do
			table.insert(moves, abilityId)
		end
		choice = moves[math.random(#moves)]
	end

	-- 2. Make it through the HUD.
	if choice == "Guard" then
		sim:click(client, ring.Guard) -- no target: straight to the server
		self.turnsTaken += 1
		return
	elseif choice == "Attack" then
		sim:click(client, ring.Attack)
	else
		sim:click(client, ring.Spell)
		local row = list.SafeArea.List.Rows:FindFirstChild(choice)
		assert(row, "no row for " .. choice)
		sim:click(client, row) -- selects it, or confirms it when it was already the selection
		if list.Enabled then
			sim:click(client, row)
		end
	end
	checkChooser(self.observer, client, battle, actor)

	-- 3. Pick a target if the move needs one: "greedy" goes for the lowest Health.
	if target.Visible then
		local candidates = {}
		local plates = client.playerGui:FindFirstChild("CombatHUDEnemies")
		for _, p in battle.participants do
			if p.side == "Enemy" then
				local plate = plates and plates:FindFirstChild("Enemy_" .. p.id)
				if plate and Sim.isClickable(plate.Root.Plate) then
					table.insert(candidates, { button = plate.Root.Plate, hp = shownHp(plate.Root.Plate.Hp.Value) })
				end
			else
				local card = safeArea.Party:FindFirstChild("Card_" .. p.id)
				if card and Sim.isClickable(card) then
					table.insert(candidates, { button = card, hp = shownHp(card.Content.Hp.Value) })
				end
			end
		end
		local pick = candidates[math.random(math.max(1, #candidates))]
		if policy == "greedy" or policy == "guard" then
			for _, candidate in candidates do
				if candidate.hp < pick.hp then
					pick = candidate
				end
			end
		end
		if pick then
			sim:click(client, pick.button) -- a tap picks it (or confirms it, when it already was the pick)
		end
		if target.Visible and Sim.isClickable(target.Confirm) then
			sim:click(client, target.Confirm)
		end
	end
	self.turnsTaken += 1
end

--[[ Scenario helpers ]]

local function newWorld(seed, options)
	local sim = Sim.new(PLACE, { seed = seed, verbose = options and options.verbose })
	sim:startServer()
	local observer = Observer.attach(sim)
	return sim, observer
end

-- The client's LocalPlayer, as its scripts see it.
local function localPlayer(client)
	return client.env.getService("Players").LocalPlayer
end

local function join(sim, observer, userId, name, botOptions)
	local client = sim:connectClient(userId, name)
	assert(sim:runUntil(function()
		return client.started == true
	end, 5), name .. " never started")
	-- Out onto the grass, as ZoneClient marks it in the game.
	localPlayer(client):SetAttribute("Zone", "Overworld")
	assert(sim:runUntil(function()
		local overworld = sim:gui(client, "Overworld")
		return (overworld ~= nil and overworld.Visible) or hudInBattle(client)
	end, 5), name .. " never showed its first state")
	attachClientChecker(sim, observer, client)
	local bot = if botOptions then Bot.new(sim, client, botOptions, observer) else nil
	return client, bot
end

local function assertClean(sim, observer, allowNotices)
	if #sim.errors > 0 then
		error("runtime errors:\n" .. sim.errors[1].label .. ": " .. sim.errors[1].message)
	end
	if #sim.warnings > 0 then
		error("warnings:\n" .. sim.warnings[1].message)
	end
	if #observer.violations > 0 then
		error(`{#observer.violations} invariant violations, first: {observer.violations[1]}`)
	end
	if not allowNotices then
		for userId, messages in observer.notices do
			error(`unexpected notice to {userId}: {messages[1]}`)
		end
	end
end

local function backInOverworld(observer)
	return observer.last ~= nil and observer.last.battle == nil
end

-- Walks into enemies from any direction, and plays its turns at a human pace.
local HUMAN = { engage = "random", thinkMin = 0.4, thinkMax = 4, engageDelay = 1 }

--[[ Tests ]]

print("\nBattleSession rules (unit)")

function sim_rng()
	return {
		NextInteger = function(_, min, max)
			return math.random(min, max)
		end,
		NextNumber = function(_, min, max)
			local roll = math.random()
			return if min then min + (max - min) * roll else roll
		end,
	}
end

local function sessionFixture(rolls, party)
	local sim = Sim.new(PLACE, { seed = 7 })
	local server = sim.server
	local sss = server.dm:GetService("ServerScriptService")
	local BattleSession = server.require(sss.Combat.BattleSession)
	-- A scripted RNG. Initiative rolls come from `rolls` (in roster order). Chance rolls
	-- (NextNumber()) come from rng.chances while any are queued, else 0.5, which means: attacks
	-- hit, no critical hits, no ailments, no lost turns. Damage variance is always exactly 1.
	local rng = {
		index = 0,
		chances = {},
		NextInteger = function(self, min, max)
			self.index += 1
			local value = rolls[self.index]
			assert(value, "ran out of scripted rolls")
			assert(value >= min and value <= max)
			return value
		end,
		NextNumber = function(self, min, max)
			if min then
				return (min + max) / 2
			end
			if #self.chances > 0 then
				return table.remove(self.chances, 1)
			end
			return 0.5
		end,
	}
	party = party or { "TungTungSahur", "TungTungSahur" }
	local roster = {
		{ side = "Party", summonId = party[1], ownerUserId = 1, ownerName = "Ann" },
		{ side = "Party", summonId = party[2], ownerUserId = 2, ownerName = "Bo" },
		{ side = "Enemy", summonId = "WildSapling" },
		{ side = "Enemy", summonId = "WildSapling" },
	}
	return BattleSession.new(1, roster, rng), BattleSession, rng, server
end

test("initiative is roll + Agility bonus, sorted by total (not by raw Agility)", function()
	-- Tung Tung bonus 5 (Agility 10), Wild Sapling bonus 6 (Agility 12).
	-- P1 rolls 20 -> 25, P2 rolls 1 -> 6, E1 rolls 10 -> 16, E2 rolls 2 -> 8
	local session = sessionFixture({ 20, 1, 10, 2 })
	session:rollInitiative()
	expectEqual(table.concat(session.turnQueue, ","), "P1,E1,E2,P2", "turn order")
	local p1 = session.byId.P1
	expectEqual(p1.initiative.roll, 20)
	expectEqual(p1.initiative.bonus, 5)
	expectEqual(p1.initiative.total, 25)
end)

test("exact initiative ties go to the party side, then the lower slot", function()
	-- Totals: P1 12+5=17, P2 12+5=17, E1 11+6=17, E2 11+6=17 -> all tied
	local session = sessionFixture({ 12, 12, 11, 11 })
	session:rollInitiative()
	expectEqual(table.concat(session.turnQueue, ","), "P1,P2,E1,E2", "tie order")
end)

test("turn order is fixed for the battle and skips knocked-out summons", function()
	local session = sessionFixture({ 20, 1, 10, 2 }) -- P1, E1, E2, P2
	session:rollInitiative()
	expectEqual(session:beginNextTurn().id, "P1")
	expectEqual(session.round, 1)
	session.byId.E1.status = "KnockedOut"
	session.byId.E1.hp = 0
	session:passTurn("Timeout")
	expectEqual(session:beginNextTurn().id, "E2", "E1 skipped")
	session:passTurn("Timeout")
	expectEqual(session:beginNextTurn().id, "P2")
	session:passTurn("Timeout")
	expectEqual(session:beginNextTurn().id, "P1", "wraps to a new round")
	expectEqual(session.round, 2)
end)

test("server validation: turn ownership, ability, Mana, target", function()
	local session = sessionFixture({ 20, 1, 10, 2 })
	session:rollInitiative()
	local ok, code = session:submitAction(1, "Strike", "E1")
	expect(not ok and code == "NotInputPhase", "no action before the first turn opens")
	session:beginNextTurn() -- P1 (owned by user 1)

	ok, code = session:submitAction(2, "Strike", "E1")
	expect(not ok and code == "NotYourTurn", "user 2 can't act on user 1's turn: " .. tostring(code))
	ok, code = session:submitAction(1, "Fireball", "E1")
	expect(not ok and code == "UnknownAbility", "unknown ability")
	ok, code = session:submitAction(1, "Strike", "P2")
	expect(not ok and code == "InvalidTarget", "can't hit an ally")
	ok, code = session:submitAction(1, "Strike", "P1")
	expect(not ok and code == "InvalidTarget", "can't hit yourself")
	ok, code = session:submitAction(1, "Strike", "E9")
	expect(not ok and code == "InvalidTarget", "unknown target")
	session.byId.E2.status = "KnockedOut"
	session.byId.E2.hp = 0
	ok, code = session:submitAction(1, "Strike", "E2")
	expect(not ok and code == "InvalidTarget", "can't hit a knocked-out enemy")
	session.byId.P1.mana = 7
	ok, code = session:submitAction(1, "GaleClap", "E1")
	expect(not ok and code == "NotEnoughMana", "Gale Clap needs 8 Mana")
	expectEqual(session.phase, "input", "rejections don't use up the turn")
	expectEqual(session.byId.E1.hp, session.byId.E1.maxHp, "rejections do no damage")

	ok = session:submitAction(1, "Strike", "E1")
	expect(ok, "a legal Strike resolves")
	expectEqual(session.byId.P1.mana, 5, "Strike costs 2 Mana")
	-- Strike: (8 power + Strength 12) = 20, minus the target's Endurance 10 share (20%) = 16
	expectEqual(session.byId.E1.hp, session.byId.E1.maxHp - 16, "damage")
	ok, code = session:submitAction(1, "Strike", "E1")
	expect(not ok and code == "NotInputPhase", "no second action in the same turn")
end)

test("Mana regenerates at the start of each of your turns, capped at max", function()
	local session = sessionFixture({ 20, 1, 10, 2 }) -- P1, E1, E2, P2
	session:rollInitiative()
	local p1 = session:beginNextTurn()
	expectEqual(p1.mana, 20, "full at the start")
	assert(session:submitAction(1, "GaleClap", "E1"))
	expectEqual(p1.mana, 12, "Gale Clap costs 8")
	for _ = 1, 3 do
		session:beginNextTurn()
		session:passTurn("Timeout")
	end
	session:beginNextTurn()
	expectEqual(p1.mana, 15, "+3 at the start of the next turn")
end)

test("knockouts end the battle, and a leaving player's summon drops out", function()
	local session = sessionFixture({ 20, 1, 10, 2 }) -- P1, E1, E2, P2
	session:rollInitiative()
	session:beginNextTurn() -- P1
	session.byId.E1.hp = 1
	assert(session:submitAction(1, "Strike", "E1"))
	expectEqual(session.byId.E1.status, "KnockedOut")
	expectEqual(session.phase, "resolve", "one enemy left, battle goes on")
	session:beginNextTurn() -- E1 is out, so E2
	expectEqual(session:getCurrentActor().id, "E2")
	session:passTurn("NoValidAction")
	session:beginNextTurn() -- P2 (user 2)
	expect(session:removePlayer(2), "leaving on your own turn reports it")
	expectEqual(session.byId.P2.status, "Left")
	expectEqual(session.phase, "resolve", "their turn is voided")
	session:beginNextTurn()
	expectEqual(session:getCurrentActor().id, "P1", "P2 is skipped from now on")
	session.byId.E2.hp = 3
	assert(session:submitAction(1, "Strike", "E2"))
	expectEqual(session.phase, "reward")
	expectEqual(session.winner, "Party")
	expect(session:getCurrentActor() == nil, "no actor after the battle")
end)

test("if every party member leaves, the enemies win", function()
	local session = sessionFixture({ 20, 1, 10, 2 })
	session:rollInitiative()
	session:removePlayer(1)
	session:removePlayer(2)
	expectEqual(session.phase, "reward")
	expectEqual(session.winner, "Enemy")
end)

print("\nStat model and abilities (unit)")

test("Endurance cuts damage (physical and magical) and makes up most of max Health", function()
	local session, BattleSession = sessionFixture({ 20, 1, 10, 2 })
	expectNear(BattleSession.damageReductionFor(10), 0.2)
	expectNear(BattleSession.damageReductionFor(40), 0.6, "capped")
	expectEqual(BattleSession.maxHpFor({ Strength = 1, Magic = 1, Endurance = 17, Agility = 1, Luck = 1 }), 125)
	session:rollInitiative()
	session:beginNextTurn() -- P1
	assert(session:submitAction(1, "GaleClap", "E1"))
	-- Gale Clap is magical: (10 + Magic 10 * 1.5) = 25, minus 20% = 20
	expectEqual(session.byId.E1.maxHp - session.byId.E1.hp, 20, "Endurance cuts magical damage too")
end)

test("attacks roll to hit, Agility against Agility, and can miss", function()
	local session, BattleSession, rng = sessionFixture({ 20, 1, 10, 2 })
	expectNear(BattleSession.hitChanceFor(10, 12), 0.86)
	expectNear(BattleSession.hitChanceFor(30, 5), 0.98, "capped")
	expectNear(BattleSession.hitChanceFor(5, 30), 0.5, "floored")
	session:rollInitiative()
	session:beginNextTurn() -- P1
	rng.chances = { 0.99 } -- above any hit chance: a miss
	assert(session:submitAction(1, "Strike", "E1"))
	local result = session.lastAction.results[1]
	expect(not result.hit and result.damage == 0, "the attack missed")
	expectEqual(session.byId.E1.hp, session.byId.E1.maxHp, "a miss does no damage")
	expectEqual(session.byId.P1.mana, 18, "a miss still costs Mana")
	expect(string.find(session.log[#session.log], "missed", 1, true), "the log says so")
end)

test("Luck drives critical hits", function()
	local session, BattleSession, rng = sessionFixture({ 20, 1, 10, 2 })
	expectNear(BattleSession.critChanceFor(10, 0), 0.12)
	expectNear(BattleSession.critChanceFor(13, 0.1), 0.25, "Splinter Slam's bonus")
	session:rollInitiative()
	session:beginNextTurn() -- P1
	rng.chances = { 0, 0 } -- hit, then critical
	assert(session:submitAction(1, "Strike", "E1"))
	expect(session.lastAction.results[1].critical, "critical")
	-- 20 * 1.5 = 30, minus 20% = 24
	expectEqual(session.byId.E1.maxHp - session.byId.E1.hp, 24, "critical damage")
end)

test("ailments: Luck against Luck to inflict, and a dazed summon may lose its turn", function()
	local session, BattleSession, rng = sessionFixture({ 20, 1, 10, 2 }) -- P1, E1, E2, P2
	expectNear(BattleSession.ailmentChanceFor(0.2, 10, 10), 0.2)
	expectNear(BattleSession.ailmentChanceFor(0.2, 13, 7), 0.32, "more Luck, better odds")
	expectNear(BattleSession.ailmentChanceFor(0.2, 0, 100), 0, "floored")
	expectNear(BattleSession.ailmentChanceFor(0.9, 100, 0), 0.9, "capped")

	session:rollInitiative()
	session:beginNextTurn() -- P1
	rng.chances = { 0, 0.99, 0 } -- hit, no critical, ailment lands
	assert(session:submitAction(1, "GaleClap", "E1"))
	expectEqual(session.lastAction.results[1].inflicted, "Dazed")
	expectEqual(session.byId.E1.statuses[1].turnsLeft, 2)

	rng.chances = { 0 } -- E1's turn: the daze takes it
	local actor = session:beginNextTurn()
	expectEqual(actor.id, "E1")
	expectEqual(session.phase, "resolve", "lost its turn")
	expect(string.find(session.log[#session.log], "is dazed and loses its turn", 1, true), "logged")
	expectEqual(session.byId.E1.statuses[1].turnsLeft, 1, "counted down")

	session:beginNextTurn() -- E2
	session:passTurn("NoValidAction")
	session:beginNextTurn() -- P2
	session:passTurn("Timeout")
	session:beginNextTurn() -- P1
	session:passTurn("Timeout")
	rng.chances = { 0.99 } -- E1 shakes it off this time
	session:beginNextTurn()
	expectEqual(session.phase, "input", "acts normally")
	expectEqual(#session.byId.E1.statuses, 0, "the daze wore off")
end)

test("Sap Mend heals a party member and clears ailments, but never an enemy", function()
	local session = sessionFixture({ 20, 1, 10, 2 }, { "TungTungGroveKeeper", "TungTungElder" })
	session:rollInitiative()
	session:beginNextTurn() -- P1 (Grove-Keeper)
	local elder = session.byId.P2
	elder.hp = 50
	table.insert(elder.statuses, { id = "Dazed", turnsLeft = 2 })
	local ok, code = session:submitAction(1, "SapMend", "E1")
	expect(not ok and code == "InvalidTarget", "can't heal an enemy")
	ok, code = session:submitAction(1, "Strike", "P2")
	expect(not ok and code == "InvalidTarget", "can't attack an ally")
	assert(session:submitAction(1, "SapMend", "P2"))
	-- 10 power + Magic 16 = 26
	expectEqual(elder.hp, 76, "healed")
	expectEqual(#elder.statuses, 0, "ailment cleared")
	expect(session.lastAction.results[1].cleansed, "reported")
end)

test("Taunt pulls enemy attacks, Windbreak cuts damage, Tailwind helps without re-sorting turns", function()
	local session, BattleSession, rng, server =
		sessionFixture({ 20, 15, 1, 2 }, { "TungTungElder", "TungTungGroveKeeper" }) -- P1 23, P2 20, E2 8, E1 7
	local EnemyAI = server.require(server.dm:GetService("ServerScriptService").Combat.EnemyAI)
	session:rollInitiative()
	local queueBefore = table.concat(session.turnQueue, ",")

	session:beginNextTurn() -- P1 (Elder)
	assert(session:submitAction(1, "KnockOnWood", "whatever")) -- no pick needed; the target is ignored
	local elder = session.byId.P1
	expect(BattleSession.drawsAttacks(elder), "taunting")
	local realRng = sim_rng()
	for _ = 1, 200 do
		local enemy = session.byId.E1
		local _, targetId =
			EnemyAI.chooseAction(enemy, session:getActiveAllies(enemy), session:getActiveOpponents(enemy), realRng)
		expectEqual(targetId, "P1", "enemies must attack the taunter")
	end

	session:beginNextTurn() -- P2 (Grove-Keeper)
	assert(session:submitAction(2, "Tailwind", "P2"))
	expectEqual(BattleSession.effectiveAgility(elder), 10, "Elder 6 + 4")
	expectEqual(BattleSession.effectiveAgility(session.byId.P2), 15, "Grove-Keeper 11 + 4")
	expectEqual(table.concat(session.turnQueue, ","), queueBefore, "turn order never re-sorts mid-battle")

	session:beginNextTurn() -- E2
	session:passTurn("NoValidAction")
	session:beginNextTurn() -- E1
	session:passTurn("NoValidAction")
	session:beginNextTurn() -- P1 again
	assert(session:submitAction(1, "Windbreak", "P1"))
	session:beginNextTurn() -- P2
	session:passTurn("Timeout")
	session:beginNextTurn() -- E2 hits the guarded, taunting Elder
	local before = elder.hp
	assert(session:performEnemyAction("Strike", "P1"))
	-- (8 + Strength 15) = 23, minus Endurance 17 (34%), times Guarded 0.6 = 9.1 -> 9
	expectEqual(before - elder.hp, 9, "Endurance and Guarded both cut the hit")
end)

test("statuses count down at the start of their summon's own turns", function()
	local session = sessionFixture({ 20, 1, 10, 2 }, { "TungTungElder", "TungTungSahur" }) -- P1, E1, E2, P2
	session:rollInitiative()
	session:beginNextTurn() -- P1
	assert(session:submitAction(1, "KnockOnWood", "P1"))
	local elder = session.byId.P1
	local seen = {}
	for _ = 1, 12 do
		local actor = session:beginNextTurn()
		if actor.id == "P1" then
			table.insert(seen, if #elder.statuses > 0 then elder.statuses[1].turnsLeft else 0)
		end
		if session.phase == "input" then
			session:passTurn("Timeout")
		end
	end
	expectEqual(table.concat(seen, ","), "2,1,0", "3 turns: lasts until the start of its third turn")
end)

print("\nGuard (unit)")

test("every summon can Guard: free, no target, even with no Mana", function()
	local session, BattleSession, _, server = sessionFixture({ 20, 1, 10, 2 }) -- P1, E1, E2, P2
	local Summons = server.require(server.dm:GetService("ReplicatedStorage").Combat.Summons)
	for summonId, summon in Summons do
		expect(table.find(summon.abilities, "Guard") == nil, `{summonId} doesn't list Guard itself`)
		expect(BattleSession.canUse({ abilities = summon.abilities }, "Guard"), `{summonId} can Guard anyway`)
	end
	session:rollInitiative()
	session:beginNextTurn() -- P1
	local p1 = session.byId.P1
	p1.mana = 0
	assert(session:submitAction(1, "Guard", "E1")) -- no pick needed; the target is ignored
	expectEqual(p1.mana, 0, "free")
	expectEqual(#p1.statuses, 1)
	expectEqual(p1.statuses[1].id, "Bracing")
	expectEqual(p1.statuses[1].turnsLeft, 1)
	local result = session.lastAction.results[1]
	expect(result.targetId == "P1" and result.applied == "Bracing", "it braces itself")
	expect(string.find(session.log[#session.log], "guards", 1, true), "logged")
	session:beginNextTurn() -- E1: the rules let enemies Guard too (the AI just doesn't choose it)
	assert(session:performEnemyAction("Guard", "E1"))
end)

test("Bracing multiplies with Endurance: a maxed-Endurance tank guarding blocks 72%, never 80%+", function()
	local session, BattleSession = sessionFixture({ 20, 1, 10, 2 }, { "TungTungElder", "TungTungSahur" }) -- P1, E1, E2, P2
	local elder = session.byId.P1
	local function reductionWith(endurance, statusIds)
		elder.stats.Endurance = endurance
		elder.statuses = {}
		for _, id in statusIds do
			table.insert(elder.statuses, { id = id, turnsLeft = 1 })
		end
		return BattleSession.damageReductionAgainst(elder)
	end
	expectNear(reductionWith(30, {}), 0.6, "Endurance alone caps at 60%")
	expectNear(reductionWith(30, { "Bracing" }), 0.72, "maxed Endurance + Guard: 1 - 0.4 * 0.7")
	expectNear(reductionWith(17, { "Bracing" }), 1 - 0.66 * 0.7, "the Elder guarding")
	expectNear(reductionWith(17, { "Guarded", "Bracing" }), 1 - 0.66 * 0.6 * 0.7, "Windbreak and Guard stack as separate statuses")
	expectNear(reductionWith(30, { "Guarded", "Bracing" }), 0.75, "never more than MaxTotalDamageReduction")
	elder.stats.Endurance = 17
	elder.statuses = {}

	session:rollInitiative()
	session:beginNextTurn() -- P1 (Elder)
	assert(session:submitAction(1, "Windbreak", "P1"))
	session:beginNextTurn() -- E1
	session:passTurn("NoValidAction")
	session:beginNextTurn() -- E2
	session:passTurn("NoValidAction")
	session:beginNextTurn() -- P2
	session:passTurn("Timeout")
	session:beginNextTurn() -- P1 guards on top of Windbreak
	assert(session:submitAction(1, "Guard", "P1"))
	expectEqual(#elder.statuses, 2, "Guarded and Bracing side by side")
	session:beginNextTurn() -- E1
	local before = elder.hp
	assert(session:performEnemyAction("Strike", "P1"))
	-- (8 + Strength 15) = 23, * 0.66 (Endurance 17) * 0.6 (Guarded) * 0.7 (Bracing) = 6.4 -> 6
	expectEqual(before - elder.hp, 6, "Endurance, Windbreak and Guard all multiply")
end)

test("no critical hits against a guarding summon", function()
	local session, BattleSession, rng = sessionFixture({ 20, 1, 10, 2 }) -- P1, E1, E2, P2
	session:rollInitiative()
	session:beginNextTurn() -- P1 guards
	assert(session:submitAction(1, "Guard", "P1"))
	expect(BattleSession.blocksCriticals(session.byId.P1), "guarding blocks critical hits")
	session:beginNextTurn() -- E1
	rng.chances = { 0, 0 } -- hit, then a critical roll that would crit anyone else
	assert(session:performEnemyAction("Strike", "P1"))
	local result = session.lastAction.results[1]
	expect(result.hit and not result.critical, "no critical hit")
	-- 23 * (1 - 0.24) * 0.7 = 12.2 -> 12
	expectEqual(result.damage, 12, "cut by Endurance and Bracing")
	session:beginNextTurn() -- E2, against P2, who isn't guarding: the same rolls crit
	rng.chances = { 0, 0 }
	assert(session:performEnemyAction("Strike", "P2"))
	expect(session.lastAction.results[1].critical, "an unguarded summon can still be crit")
end)

test("guarding halves the chance of an ailment landing", function()
	local session, BattleSession, rng = sessionFixture({ 20, 1, 10, 2 }) -- P1, E1, E2, P2
	session:rollInitiative()
	session:beginNextTurn() -- P1 guards
	assert(session:submitAction(1, "Guard", "P1"))
	expectNear(BattleSession.ailmentChanceMultiplier(session.byId.P1), 0.5)
	expectNear(BattleSession.ailmentChanceMultiplier(session.byId.P2), 1)
	session:beginNextTurn() -- E1: Gale Clap dazes 20% of the time (Luck 10 vs 10), 10% while guarding
	rng.chances = { 0, 0.99, 0.15 } -- hit, no critical, ailment roll
	assert(session:performEnemyAction("GaleClap", "P1"))
	expectEqual(session.lastAction.results[1].inflicted, nil, "0.15 misses the halved 10%")
	session:beginNextTurn() -- E2: the same roll on P2, who isn't guarding
	rng.chances = { 0, 0.99, 0.15 }
	assert(session:performEnemyAction("GaleClap", "P2"))
	expectEqual(session.lastAction.results[1].inflicted, "Dazed", "0.15 lands inside the full 20%")
end)

test("Guard never gives Mana: attacked while guarding, hit or miss, it gets nothing back", function()
	local session, _, rng = sessionFixture({ 20, 1, 10, 2 }) -- P1, E1, E2, P2
	session:rollInitiative()
	local p1, p2 = session.byId.P1, session.byId.P2
	session:beginNextTurn() -- P1 guards with Mana to spare
	p1.mana = 5
	assert(session:submitAction(1, "Guard", "P1"))
	expectEqual(p1.mana, 5, "free, and no Mana for guarding either")
	session:beginNextTurn() -- E1 attacks it and misses
	rng.chances = { 0.99 }
	assert(session:performEnemyAction("Strike", "P1"))
	local result = session.lastAction.results[1]
	expect(not result.hit, "missed")
	expectEqual((result :: any).manaGained, nil, "results don't carry Mana anymore")
	expectEqual(p1.mana, 5, "a miss pays nothing")
	session:beginNextTurn() -- E2 attacks it and hits
	rng.chances = { 0, 0.99 }
	assert(session:performEnemyAction("Strike", "P1"))
	expect(session.lastAction.results[1].hit, "hit")
	expectEqual(p1.mana, 5, "a hit pays nothing")
	for _, line in session.log do
		expect(not string.find(line, "Mana.", 1, true) or string.find(line, "out of Mana", 1, true), `no Mana payout logged: {line}`)
	end

	session:beginNextTurn() -- P2 guards, and nothing attacks it before its next turn
	p2.mana = 5
	assert(session:submitAction(2, "Guard", "P2"))
	session:beginNextTurn() -- P1: its Guard ended as its turn began
	expectEqual(#p1.statuses, 0, "Bracing lasts until its own next turn")
	expectEqual(p1.mana, 8, "5 + 3 regen, the only Mana it got")
	session:passTurn("Timeout")
	session:beginNextTurn() -- E1
	session:passTurn("NoValidAction")
	session:beginNextTurn() -- E2
	session:passTurn("NoValidAction")
	session:beginNextTurn() -- P2
	expectEqual(p2.mana, 8, "5 + 3 regen either way")
	expectEqual(#p2.statuses, 0, "and its Guard is over")
end)

test("Guard lasts until its summon's next turn, through every turn in between", function()
	local session, BattleSession = sessionFixture({ 20, 1, 10, 2 }) -- P1, E1, E2, P2
	session:rollInitiative()
	session:beginNextTurn() -- P1
	assert(session:submitAction(1, "Guard", "P1"))
	local p1 = session.byId.P1
	for _, expected in { "E1", "E2", "P2" } do
		local actor = session:beginNextTurn()
		expectEqual(actor.id, expected)
		expect(BattleSession.blocksCriticals(p1), `still bracing during {expected}'s turn`)
		session:passTurn("Timeout")
	end
	expectEqual(session:beginNextTurn().id, "P1")
	expect(not BattleSession.blocksCriticals(p1), "over once its own turn comes around")
end)

test("guarding on empty Mana, even into a knockout, leaves it empty", function()
	local session = sessionFixture({ 20, 1, 10, 2 }) -- P1, E1, E2, P2
	session:rollInitiative()
	local p1, p2 = session.byId.P1, session.byId.P2
	session:beginNextTurn() -- P1 guards on empty
	p1.mana = 0
	assert(session:submitAction(1, "Guard", "P1"))
	session:beginNextTurn() -- E1
	assert(session:performEnemyAction("Strike", "P1"))
	expectEqual(p1.mana, 0, "attacked while guarding: still empty")
	session:beginNextTurn() -- E2
	session:passTurn("NoValidAction")
	session:beginNextTurn() -- P2 guards on 1 Health
	p2.hp, p2.mana = 1, 0
	assert(session:submitAction(2, "Guard", "P2"))
	session:beginNextTurn() -- P1
	session:passTurn("Timeout")
	session:beginNextTurn() -- E1 knocks it out anyway
	assert(session:performEnemyAction("Strike", "P2"))
	expect(session.lastAction.results[1].knockedOut, "knocked out")
	expectEqual(p2.mana, 0)
end)

test("a player who can't afford any ability still gets the turn (Guard is free); enemies pass", function()
	local sim = Sim.new(PLACE, { seed = 7 })
	local server = sim.server
	local BattleDirector = server.require(server.dm:GetService("ServerScriptService").Combat.BattleDirector)
	local config = server.require(server.dm:GetService("ReplicatedStorage").Combat.CombatConfig)
	config.ManaRegenPerTurn = 0 -- so a summon on 0 Mana stays there
	local clock, pending, queued = 0, {}, 0
	local director = BattleDirector.new({
		now = function()
			return clock
		end,
		delay = function(seconds, callback)
			queued += 1
			table.insert(pending, { at = clock + seconds, order = queued, fn = callback })
		end,
		rng = sim_rng(),
		broadcast = function() end,
		notify = function() end,
		battleEnded = function() end,
	})
	local function runNext()
		table.sort(pending, function(a, b)
			return a.at < b.at or (a.at == b.at and a.order < b.order)
		end)
		local item = table.remove(pending, 1)
		assert(item, "nothing scheduled")
		clock = item.at
		item.fn()
	end

	director:playerJoined(1, "Solo")
	assert(director:startEncounter(1, { enemies = { "WildSapling", "WildSapling" } }), "the fight starts")
	local session = director.session
	assert(session, "a battle is running")
	for _, p in session.participants do
		p.mana = 0 -- can't afford anything but Guard (Strike costs 2)
	end

	local playerTurns, enemyPasses = 0, 0
	for _ = 1, 40 do
		runNext()
		local actor = session:getCurrentActor()
		if session.phase == "input" and actor and actor.side == "Party" then
			playerTurns += 1
			expect(director.turnDeadline ~= nil, "the player's turn waits for them")
			director:submitAction(1, "Guard", actor.id)
			expectEqual(session.lastAction.abilityId, "Guard")
		end
		if string.find(session.log[#session.log], "is out of Mana and skips the turn", 1, true) then
			expect(actor ~= nil and actor.side == "Enemy", "only enemies are passed for Mana")
			enemyPasses += 1
		end
		if playerTurns >= 2 and enemyPasses >= 2 then
			break
		end
	end
	expect(playerTurns >= 2, "players got their turns")
	expect(enemyPasses >= 2, "enemies with no Mana passed")
end)

test("arriving on the grass shows the overworld panel for a few seconds", function()
	local sim, observer = newWorld(4400)
	local client = join(sim, observer, -1, "Ann", nil) -- join arrives her on the grass
	local panel = sim:gui(client, "Overworld")
	expect(panel.Visible, "it pops up on arriving")
	sim:run(7)
	expect(not panel.Visible, "and goes away after a few seconds, with no fight on")
	localPlayer(client):SetAttribute("Zone", "Lobby")
	sim:run(0.5)
	expect(not panel.Visible, "not in the lobby")
	localPlayer(client):SetAttribute("Zone", "Overworld")
	sim:run(0.5)
	expect(panel.Visible, "back out on the grass, it shows again")
	assertClean(sim, observer)
end)

test("Guard through the UI: its own button, no target, and it braces", function()
	local sim, observer = newWorld(4200) -- two Tung Tung Sahurs, the default lineup
	join(sim, observer, -1, "Guardian", { engage = "random", thinkMin = 0.3, thinkMax = 1.5, engageDelay = 0.5, policy = "guard" })
	join(sim, observer, -2, "Striker", { engage = "random", thinkMin = 0.3, thinkMax = 1.5, engageDelay = 0.5, policy = "greedy" })
	-- Keep fighting until a Guard has been attacked (one fight may not). The observer fails the run
	-- if that attack changed the guard's Mana.
	expect(sim:runUntil(function()
		return observer.battlesFinished >= 1 and (observer.guardsAttacked or 0) > 0 and backInOverworld(observer)
	end, 3600), "no Guard was ever attacked")
	assertClean(sim, observer)
	expect((observer.guards or 0) >= 2, "the Guardian guarded through the UI")
end)

test("with no Mana at all, the character's Attack and Guard still work", function()
	local sim, observer = newWorld(4300)
	local config = sim.server.require(sim.server.dm:GetService("ReplicatedStorage").Combat.CombatConfig)
	config.BaseMana, config.ManaPerMagic, config.ManaRegenPerTurn = 0, 0, 0 -- nobody can afford anything
	join(sim, observer, -1, "Broke", { engage = "random", thinkMin = 0.3, thinkMax = 1, engageDelay = 0.5, policy = "random" })
	expect(sim:runUntil(function()
		return (observer.guards or 0) >= 4
	end, 900), "the player never got to Guard")
	assertClean(sim, observer)
end)

print("\nTwo players, through the UI")

test("two players fight a full battle start to finish, then a rematch", function()
	local sim, observer = newWorld(101)
	local a = join(sim, observer, -1, "Player1", HUMAN)
	local b = join(sim, observer, -2, "Player2", HUMAN)
	expect(sim:runUntil(function()
		return observer.battlesStarted >= 1
	end, 30), "battle never started")

	-- Each player controls exactly one party summon.
	local owners = {}
	for _, p in observer.last.battle.participants do
		if p.side == "Party" then
			table.insert(owners, p.ownerUserId)
		end
	end
	table.sort(owners)
	expectEqual(table.concat(owners, ","), "-2,-1", "one summon each")

	expect(sim:runUntil(function()
		return observer.battlesFinished >= 1 and backInOverworld(observer)
	end, 900), "battle never finished")
	expect(not observer.sawTimeout, "no one should have timed out")

	-- Both back in the overworld, free to walk, and then they run into another enemy.
	sim:run(0.2)
	for _, client in { a, b } do
		expect(not hudInBattle(client), client.name .. " is back exploring")
		expect(not sim:rootPart(client.userId).Anchored, client.name .. " can walk again")
	end
	expect(sim:runUntil(function()
		return observer.battlesFinished >= 2 and backInOverworld(observer)
	end, 900), "rematch never finished")
	assertClean(sim, observer)
	local r = observer.results[1]
	print(`       battle 1: {r.winner} won in {r.rounds} rounds, {r.turns} turns, {math.floor(r.duration)}s`)
end)

test("solo player controls both party summons", function()
	local sim, observer = newWorld(202)
	join(sim, observer, -1, "Solo", HUMAN)
	expect(sim:runUntil(function()
		return observer.battlesFinished >= 1 and backInOverworld(observer)
	end, 900), "solo battle never finished")
	for _, p in observer.results do
		expect(p.winner ~= nil)
	end
	assertClean(sim, observer)
end)

test("an AFK player's turns time out and the battle still finishes", function()
	local sim, observer = newWorld(303)
	join(sim, observer, -1, "Active", HUMAN)
	join(sim, observer, -2, "AFK", { afkInBattle = true })
	expect(sim:runUntil(function()
		return observer.battlesFinished >= 1 and backInOverworld(observer)
	end, 1800), "battle with an AFK player never finished")
	expect(observer.sawTimeout, "the AFK player's turn should have timed out")
	assertClean(sim, observer)
end)

print("\nDisconnects")

local function runToPhase(sim, observer, predicate, label)
	expect(sim:runUntil(function()
		local battle = observer.last and observer.last.battle
		return battle ~= nil and predicate(battle)
	end, 300), "never reached: " .. label)
end

local function currentActor(battle)
	return if battle.currentActorId then participantById(battle, battle.currentActorId) else nil
end

test("leaving on your own turn moves the battle on immediately", function()
	local sim, observer = newWorld(404)
	join(sim, observer, -1, "Stays", HUMAN)
	join(sim, observer, -2, "Leaves", { afkInBattle = true })
	runToPhase(sim, observer, function(battle)
		local actor = currentActor(battle)
		return battle.phase == "input" and actor ~= nil and actor.ownerUserId == -2
	end, "Leaves' turn")
	local turnBefore = observer.last.battle.turnNumber
	local leftAt = sim.now
	sim:disconnectClient(-2)
	expect(sim:runUntil(function()
		local battle = observer.last.battle
		return battle ~= nil and (battle.turnNumber > turnBefore or battle.phase == "reward")
	end, 30), "battle stalled after the player left")
	expect(sim.now - leftAt < 3, `next turn should open right away (took {sim.now - leftAt}s)`)
	local leaver = nil
	for _, p in observer.last.battle.participants do
		if p.ownerUserId == -2 then
			leaver = p
		end
	end
	expectEqual(leaver.status, "Left", "their summon drops out")
	expect(sim:runUntil(function()
		return observer.battlesFinished >= 1 and backInOverworld(observer)
	end, 900), "battle never finished after a player left")
	expectEqual(#observer.last.overworld.players, 1, "only the remaining player is left")
	assertClean(sim, observer)
end)

test("leaving during an enemy turn, the initiative reveal, or the result screen", function()
	for _, case in { "enemy", "setup", "reward" } do
		local sim, observer = newWorld(500 + #case)
		join(sim, observer, -1, "Stays", HUMAN)
		join(sim, observer, -2, "Leaves", HUMAN)
		if case == "enemy" then
			runToPhase(sim, observer, function(battle)
				local actor = currentActor(battle)
				return battle.phase == "input" and actor ~= nil and actor.ownerUserId == nil
			end, "an enemy turn")
		elseif case == "setup" then
			runToPhase(sim, observer, function(battle)
				return battle.phase == "setup"
			end, "setup")
		else
			runToPhase(sim, observer, function(battle)
				return battle.phase == "reward"
			end, "reward")
		end
		sim:disconnectClient(-2)
		expect(sim:runUntil(function()
			return observer.battlesFinished >= 1 and backInOverworld(observer)
		end, 900), "battle never finished (" .. case .. ")")
		assertClean(sim, observer)
	end
end)

test("everyone leaves mid-battle: the fight ends, and a newcomer can start another", function()
	local sim, observer = newWorld(606)
	join(sim, observer, -1, "One", HUMAN)
	join(sim, observer, -2, "Two", HUMAN)
	runToPhase(sim, observer, function(battle)
		return battle.phase == "input" and battle.turnNumber >= 3
	end, "turn 3")
	sim:disconnectClient(-1)
	sim:disconnectClient(-2)
	sim:run(30)
	expect(backInOverworld(observer), "the fight should be over")
	expectEqual(#observer.last.overworld.players, 0)
	-- A new player can start a fresh battle afterwards.
	join(sim, observer, -3, "Newcomer", HUMAN)
	expect(sim:runUntil(function()
		return observer.battlesFinished >= 2 and backInOverworld(observer)
	end, 900), "newcomer's battle never finished")
	assertClean(sim, observer)
end)

print("\nCheating clients (remote calls a real client UI wouldn't make)")

test("out-of-turn, malformed and illegal requests are all refused", function()
	local sim, observer = newWorld(707)
	join(sim, observer, -1, "Honest", { engage = "side", engageDelay = 1, afkInBattle = true })
	join(sim, observer, -2, "Cheater", { afkInBattle = true })

	local function snapshotKey()
		local battle = observer.last.battle
		local parts = { battle.phase, tostring(battle.turnNumber) }
		for _, p in battle.participants do
			table.insert(parts, `{p.id}:{p.hp}:{p.mana}:{p.status}`)
		end
		return table.concat(parts, "|")
	end
	local function noticeCount(userId)
		return #(observer.notices[userId] or {})
	end

	-- 1) Act on someone else's turn.
	runToPhase(sim, observer, function(battle)
		local actor = currentActor(battle)
		return battle.phase == "input" and actor ~= nil and actor.ownerUserId ~= -2
	end, "a turn that isn't the cheater's")
	local before, notices = snapshotKey(), noticeCount(-2)
	sim:sendToServer(SUBMIT, -2, "Strike", "E1")
	sim:run(0.2)
	expectEqual(snapshotKey(), before, "out-of-turn request changed the state")
	expectEqual(noticeCount(-2), notices + 1, "cheater should get a refusal notice")
	expect(string.find(observer.notices[-2][#observer.notices[-2]], "not your turn", 1, true), "notice text")

	-- 2) On their own turn: malformed payloads are dropped silently, illegal ones are refused.
	runToPhase(sim, observer, function(battle)
		local actor = currentActor(battle)
		return battle.phase == "input" and actor ~= nil and actor.ownerUserId == -2
	end, "the cheater's turn")
	local battle = observer.last.battle
	local actor = currentActor(battle)
	local ally = nil
	for _, p in battle.participants do
		if p.side == "Party" and p.id ~= actor.id then
			ally = p
		end
	end
	before, notices = snapshotKey(), noticeCount(-2)
	sim:sendToServer(SUBMIT, -2, 42, "E1")
	sim:sendToServer(SUBMIT, -2, "Strike", { "E1" })
	sim:sendToServer(SUBMIT, -2, nil, nil)
	sim:sendToServer(SUBMIT, -2)
	sim:run(0.2)
	expectEqual(snapshotKey(), before, "malformed requests changed the state")
	expectEqual(noticeCount(-2), notices, "malformed requests are dropped without a reply")

	for _, request in {
		{ "Fireball", "E1" },
		{ "Strike", ally.id },
		{ "Strike", actor.id },
		{ "Strike", "E99" },
		{ "Strike", "" },
		{ string.rep("x", 100000), "E1" },
	} do
		sim:sendToServer(SUBMIT, -2, request[1], request[2])
	end
	sim:run(0.2)
	expectEqual(snapshotKey(), before, "illegal requests changed the state")
	expectEqual(noticeCount(-2), notices + 6, "each illegal request gets a refusal")

	-- 3) Two actions fired back to back: only the first one counts.
	sim:sendToServer(SUBMIT, -2, "Strike", "E1")
	sim:sendToServer(SUBMIT, -2, "Strike", "E2")
	sim:run(0.2)
	local after = observer.last.battle
	expectEqual(after.lastAction.results[1].targetId, "E1", "first request resolved")
	expectEqual(participantById(after, "E2").hp, participantById(after, "E2").maxHp, "second request did nothing")
	expectEqual(noticeCount(-2), notices + 7, "second request refused")

	-- 4) Spending Mana it doesn't have.
	local function cheaterTurn()
		runToPhase(sim, observer, function(b)
			local a = currentActor(b)
			return b.phase == "input" and a ~= nil and a.ownerUserId == -2
		end, "the cheater's next turn")
		return currentActor(observer.last.battle)
	end
	-- Keep casting Gale Clap until its Mana runs low. Turns lost to Dazed still regenerate Mana,
	-- and the fight may end (its partner is AFK), so this can take a few turns or even battles.
	local sawManaRefusal = false
	for _ = 1, 30 do
		local me = cheaterTurn()
		local target = nil
		for _, p in observer.last.battle.participants do
			if p.side == "Enemy" and p.status == "Active" then
				target = p.id
			end
		end
		if target == nil then
			break
		end
		if me.mana < 8 then
			local count = noticeCount(-2)
			local key = snapshotKey()
			sim:sendToServer(SUBMIT, -2, "GaleClap", target)
			sim:run(0.2)
			expectEqual(snapshotKey(), key, "unaffordable Gale Clap changed the state")
			expectEqual(noticeCount(-2), count + 1, "unaffordable Gale Clap refused")
			expect(string.find(observer.notices[-2][#observer.notices[-2]], "Mana", 1, true), "notice mentions Mana")
			sawManaRefusal = true
			break
		end
		sim:sendToServer(SUBMIT, -2, "GaleClap", target)
		sim:run(0.2)
	end
	expect(sawManaRefusal, "never got to test the Mana check")

	assertClean(sim, observer, true)
end)

print("\nOverworld encounters")

local roblox = require("@lune/roblox")

-- A BattleDirector on a hand-cranked clock, for checking how fights start and end.
local function directorFixture()
	local sim = Sim.new(PLACE, { seed = 7 })
	local server = sim.server
	local BattleDirector = server.require(server.dm:GetService("ServerScriptService").Combat.BattleDirector)
	local clock, pending, queued = 0, {}, 0
	local ended = {}
	local director = BattleDirector.new({
		now = function()
			return clock
		end,
		delay = function(seconds, callback)
			queued += 1
			table.insert(pending, { at = clock + seconds, order = queued, fn = callback })
		end,
		rng = sim_rng(),
		broadcast = function() end,
		notify = function() end,
		battleEnded = function(winner)
			table.insert(ended, winner or "reset")
		end,
	})
	local function runNext()
		table.sort(pending, function(a, b)
			return a.at < b.at or (a.at == b.at and a.order < b.order)
		end)
		local item = table.remove(pending, 1)
		assert(item, "nothing scheduled")
		clock = item.at
		item.fn()
	end
	return director, runNext, ended
end

test("the way you're facing when you touch an enemy decides who gets the bonus turn", function()
	local sim = Sim.new(PLACE, { seed = 1 })
	local Encounter = sim.server.require(sim.server.dm:GetService("ServerScriptService").Overworld.Encounter)
	local V3 = roblox.Vector3
	-- The player stands at the origin facing -Z, and the enemy is 3 studs away, `degrees` round
	-- from straight ahead.
	local player = Sim.lookAt(V3.new(0, 3, 0), V3.new(0, 3, -1))
	expect(player.LookVector.Z < -0.99, "the test's own CFrame faces -Z")
	local function contactAt(degrees, height)
		local radians = math.rad(degrees)
		return Encounter.classify(player, V3.new(3 * math.sin(radians), height or 3, -3 * math.cos(radians)))
	end
	expectEqual(contactAt(0), "Front")
	expectEqual(contactAt(59), "Front")
	expectEqual(contactAt(-59), "Front")
	expectEqual(contactAt(61), "Side")
	expectEqual(contactAt(90), "Side")
	expectEqual(contactAt(-119), "Side")
	expectEqual(contactAt(121), "Back")
	expectEqual(contactAt(-150), "Back")
	expectEqual(contactAt(180), "Back")
	expectEqual(contactAt(0, 8), "Front", "height doesn't count")
	expectEqual(Encounter.classify(player, V3.new(0, 9, 0)), "Side", "straight overhead: call it even")
	expectEqual(Encounter.openingFor("Front"), "Party")
	expectEqual(Encounter.openingFor("Back"), "Enemy")
	expectEqual(Encounter.openingFor("Side"), nil)
end)

test("striking first: that side takes a bonus turn in initiative order, then round 1 as usual", function()
	-- P1 rolls 20 (25), P2 1 (6), E1 10 (16), E2 2 (8): the queue is P1, E1, E2, P2.
	local function turnsWith(opening, count)
		local session = sessionFixture({ 20, 1, 10, 2 })
		session:rollInitiative(opening)
		local order = {}
		for _ = 1, count do
			local actor = session:beginNextTurn()
			table.insert(order, `{actor.id}@{session.round}`)
			session:passTurn("Timeout")
		end
		return table.concat(order, " "), session
	end
	local order, session = turnsWith("Party", 6)
	expectEqual(order, "P1@0 P2@0 P1@1 E1@1 E2@1 P2@1", "the party's bonus turn")
	expectEqual(session:getState().opening, "Party")
	expect(string.find(session.log[5], "party struck first", 1, true), "logged after the rolls")
	order = turnsWith("Enemy", 6)
	expectEqual(order, "E1@0 E2@0 P1@1 E1@1 E2@1 P2@1", "the enemies' bonus turn")
	order, session = turnsWith(nil, 6)
	expectEqual(order, "P1@1 E1@1 E2@1 P2@1 P1@2 E1@2", "an even start is the plain initiative order")
	expectEqual(session:getState().opening, nil)

	-- Someone on the side with the bonus turn who's already gone is skipped.
	local gone = sessionFixture({ 20, 1, 10, 2 })
	gone:rollInitiative("Party")
	gone:removePlayer(1) -- P1's player leaves during the initiative reveal
	local actor = gone:beginNextTurn()
	expect(actor.id == "P2" and gone.round == 0, "P2 still gets its bonus turn")
	gone:passTurn("Timeout")
	expectEqual(gone:beginNextTurn().id, "E1", "then round 1")
end)

test("a fight pulls in whoever touched the enemy, then everyone else, up to the party size", function()
	local director, runNext, ended = directorFixture()
	director:playerJoined(1, "Ann")
	director:playerJoined(2, "Bo")
	director:playerJoined(3, "Cy")
	local party = director:startEncounter(3, { enemies = { "WildSapling" }, opening = "Enemy" })
	expectEqual(table.concat(party or {}, ","), "3,1", "the one who touched it first, then join order")
	local battle = director:getSnapshot().battle
	expectEqual(battle.startedBy, "Cy")
	expectEqual(battle.opening, "Enemy")
	local owners, enemies = {}, 0
	for _, p in battle.participants do
		if p.side == "Party" then
			table.insert(owners, p.ownerUserId)
		else
			enemies += 1
		end
	end
	expectEqual(table.concat(owners, ","), "3,1", "summons dealt to the party in that order")
	expectEqual(enemies, 1, "the enemy side is the encounter's")
	expectEqual(director:startEncounter(2, { enemies = { "WildSapling" } }), nil, "one fight at a time")

	-- Everyone in the party leaves: the enemies win, and after the result screen the director
	-- reports it and clears the fight.
	director:playerLeft(3)
	director:playerLeft(1)
	for _ = 1, 10 do
		if #ended > 0 then
			break
		end
		runNext()
	end
	expectEqual(table.concat(ended, ","), "Enemy", "battleEnded reported once, with the winner")
	expectEqual(director:getSnapshot().battle, nil)
	expectEqual(director:startEncounter(99, { enemies = { "WildSapling" } }), nil, "only players in the server")
	expect(director:startEncounter(2, { enemies = { "WildSapling" } }) ~= nil, "the next fight can start")
end)

-- Starts a fight by walking `userId`'s character into `enemyId` the way `how` says.
local function touch(sim, observer, userId, enemyId, how)
	local enemy = sim:overworldEnemies()[enemyId]
	assert(enemy, enemyId .. " isn't out there")
	assert(sim:touchEnemy(userId, enemy, how), "couldn't move")
	expect(sim:runUntil(function()
		return observer.last ~= nil and observer.last.battle ~= nil
	end, 2), "touching " .. enemyId .. " didn't start a fight")
	return observer.last.battle
end

test("walking into an enemy face-on: the party struck first and takes a bonus turn", function()
	local sim, observer = newWorld(811)
	local client = join(sim, observer, -1, "Ann", { thinkMin = 0.3, thinkMax = 1, policy = "greedy" })
	sim:run(1)
	local enemy = sim:overworldEnemies().NorthLookout
	local standing = enemy.CFrame
	local battle = touch(sim, observer, -1, "NorthLookout", "front")
	expectEqual(battle.opening, "Party")
	expectEqual(battle.startedBy, "Ann")

	-- Frozen where they stood, and the enemy holds still, until it's over.
	local root, humanoid = sim:rootPart(-1), sim:humanoid(-1)
	expect(root.Anchored and humanoid.WalkSpeed == 0 and humanoid.JumpHeight == 0, "frozen during the fight")
	expect(not sim:touchEnemy(-1, sim:overworldEnemies().EastPatrol, "front"), "can't walk around mid-fight")
	runToPhase(sim, observer, function(b)
		return b.round >= 1 or b.phase == "reward"
	end, "round 1")
	expect(#observer.bonusTurnTotals >= 1, "the party acted in the bonus turn")
	expect(enemy.CFrame == standing, "the enemy it's fighting stays put")
	expect(hudInBattle(client), "the player sees the fight")
	assertClean(sim, observer)
end)

test("an enemy walking into your back: the enemies struck first and take the bonus turn", function()
	local sim, observer = newWorld(812)
	join(sim, observer, -1, "Ann", { thinkMin = 0.3, thinkMax = 1, policy = "greedy" })
	sim:run(1)
	local battle = touch(sim, observer, -1, "EastPatrol", "back")
	expectEqual(battle.opening, "Enemy")
	runToPhase(sim, observer, function(b)
		return b.phase == "input" and b.turnNumber == 1
	end, "the first turn")
	local first = currentActor(observer.last.battle)
	expect(first.side == "Enemy" and observer.last.battle.round == 0, "an enemy opens the bonus turn")
	runToPhase(sim, observer, function(b)
		return b.round >= 1 or b.phase == "reward"
	end, "round 1")
	assertClean(sim, observer)
end)

test("touching an enemy side-on: an even start", function()
	local sim, observer = newWorld(813)
	join(sim, observer, -1, "Ann", { thinkMin = 0.3, thinkMax = 1, policy = "greedy" })
	sim:run(1)
	-- A lookout stands still; a patrol would keep walking between placing Ann and the server's
	-- next check, and could end up behind her.
	local battle = touch(sim, observer, -1, "SouthLookout", "side")
	expectEqual(battle.opening, nil)
	runToPhase(sim, observer, function(b)
		return b.phase == "input" and b.turnNumber == 1
	end, "the first turn")
	expectEqual(observer.last.battle.round, 1, "no bonus turn")
	assertClean(sim, observer)
end)

test("after a win the enemy is gone until it respawns; everyone gets a moment to walk away", function()
	local sim, observer = newWorld(814)
	local summons = sim.server.require(sim.server.dm:GetService("ReplicatedStorage").Combat.Summons)
	local config = sim.server.require(sim.server.dm:GetService("ReplicatedStorage").Combat.CombatConfig)
	summons.WildSapling.stats = { Strength = 1, Magic = 1, Endurance = 0, Agility = 1, Luck = 0 } -- a pushover
	join(sim, observer, -1, "Ann", { thinkMin = 0.3, thinkMax = 1, policy = "greedy" })
	sim:run(1)
	touch(sim, observer, -1, "SouthLookout", "side")
	expect(sim:runUntil(function()
		return observer.battlesFinished >= 1 and backInOverworld(observer)
	end, 600), "the fight never finished")
	expectEqual(observer.results[1].winner, "Party")
	local endedAt = sim.now

	expect(sim:overworldEnemies().SouthLookout == nil, "a beaten enemy vanishes")
	local root, humanoid = sim:rootPart(-1), sim:humanoid(-1)
	expect(not root.Anchored and humanoid.WalkSpeed == 16 and humanoid.JumpHeight > 7, "free to move again")

	-- Walking straight into another enemy during the cooldown does nothing...
	sim:touchEnemy(-1, sim:overworldEnemies().NorthLookout, "front")
	sim:run(config.EncounterCooldownSeconds - 1)
	expectEqual(observer.battlesStarted, 1, "no new fight during the cooldown")
	-- ...and once it's over, the touch counts.
	expect(sim:runUntil(function()
		return observer.battlesStarted >= 2
	end, 3), "the next fight should start after the cooldown")
	expect(sim.now - endedAt >= config.EncounterCooldownSeconds, "not before the cooldown ended")

	-- The beaten enemy comes back where it started.
	sim:run(config.EnemyRespawnSeconds)
	local back = sim:overworldEnemies().SouthLookout
	expect(back ~= nil, "it respawns")
	local position = back.CFrame.Position
	expect(math.abs(position.X - -30) < 0.01 and math.abs(position.Z - 90) < 0.01, "at its spot")
	assertClean(sim, observer)
end)

test("a party that wins and stays put isn't pulled into a new fight when the enemy respawns", function()
	-- The fight leaves the party standing where it touched the enemy: right on its spot. The enemy
	-- comes back there, so it has to wait until they've walked off, or a win would start the next
	-- fight by itself (seen live on the campus gym's sparring stage).
	local sim, observer = newWorld(816)
	local summons = sim.server.require(sim.server.dm:GetService("ReplicatedStorage").Combat.Summons)
	local config = sim.server.require(sim.server.dm:GetService("ReplicatedStorage").Combat.CombatConfig)
	summons.WildSapling.stats = { Strength = 1, Magic = 1, Endurance = 0, Agility = 1, Luck = 0 } -- a pushover
	local client = join(sim, observer, -1, "Ann", { thinkMin = 0.3, thinkMax = 1, policy = "greedy" })
	sim:run(1)
	expect(client.coreGui.Backpack == false, "the backpack hotbar (Roblox's own 1-9 keys) is off")

	-- Up on the campus, 1-on-1 with the gym's sparring sapling (ground y = 403.5 there).
	touch(sim, observer, -1, "GymWildSapling", "front")
	expect(sim:runUntil(function()
		return observer.battlesFinished >= 1 and backInOverworld(observer)
	end, 600), "the fight never finished")
	expectEqual(observer.results[1].winner, "Party")
	expect(sim:overworldEnemies().GymWildSapling == nil, "the beaten sapling is gone")
	local root = sim:rootPart(-1)
	local stood = root.CFrame.Position
	expect(not root.Anchored, "Ann is free to move")

	-- Ann doesn't move (chatting, or away from the keyboard). Long after the cooldown and the respawn
	-- time have passed, nothing has happened to her...
	sim:run(config.EncounterCooldownSeconds + config.EnemyRespawnSeconds + 5)
	expectEqual(observer.battlesStarted, 1, "no second fight while she stands on its spot")
	expect(sim:overworldEnemies().GymWildSapling == nil, "the sapling waits to come back")
	expect((root.CFrame.Position - stood).Magnitude < 0.01, "and she hasn't been moved")

	-- ...she walks off its spot, and it comes back where it stood...
	root.CFrame = root.CFrame + roblox.Vector3.new(12, 0, 0)
	expect(sim:runUntil(function()
		return sim:overworldEnemies().GymWildSapling ~= nil
	end, 2), "it respawns once she's clear")
	local back = sim:overworldEnemies().GymWildSapling
	local position = back.CFrame.Position
	expect(math.abs(position.X - 4182) < 0.01 and math.abs(position.Z - -56) < 0.01, "at its spot")
	sim:run(1)
	expectEqual(observer.battlesStarted, 1, "and still no fight")

	-- ...and walking back into it is a fight again, as ever.
	touch(sim, observer, -1, "GymWildSapling", "front")
	expectEqual(observer.battlesStarted, 2)
	assertClean(sim, observer)
end)

test("after a loss the party respawns at the spawn point, and the enemy stays", function()
	local sim, observer = newWorld(815)
	local summons = sim.server.require(sim.server.dm:GetService("ReplicatedStorage").Combat.Summons)
	summons.WildSapling.stats = { Strength = 400, Magic = 1, Endurance = 30, Agility = 30, Luck = 0 } -- hopeless
	join(sim, observer, -1, "Ann", { thinkMin = 0.3, thinkMax = 1, policy = "greedy" })
	sim:run(1)
	local spawnsBefore = sim.characterSpawns
	touch(sim, observer, -1, "NorthLookout", "front")
	expect(sim:runUntil(function()
		return observer.battlesFinished >= 1 and backInOverworld(observer)
	end, 600), "the fight never finished")
	expectEqual(observer.results[1].winner, "Enemy")
	sim:run(0.5)
	expectEqual(sim.characterSpawns, spawnsBefore + 1, "respawned")
	local root = sim:rootPart(-1)
	expect(root.CFrame.Position.Magnitude < 5 and not root.Anchored, "back at the spawn point, free to move")
	expect(sim:overworldEnemies().NorthLookout ~= nil, "the enemy that won is still there")
	assertClean(sim, observer)
end)

test("one fight at a time: a third player sits it out, then can start the next", function()
	local sim, observer = newWorld(816)
	join(sim, observer, -1, "Ann", { thinkMin = 0.3, thinkMax = 1, policy = "greedy" })
	join(sim, observer, -2, "Bo", { thinkMin = 0.3, thinkMax = 1, policy = "greedy" })
	local cy = join(sim, observer, -3, "Cy", nil)
	sim:run(1)
	local battle = touch(sim, observer, -2, "WestPatrol", "front")
	expect(not isInBattle(battle, -3), "the party is full without Cy")
	expect(isInBattle(battle, -1) and isInBattle(battle, -2), "Bo pulled Ann in")
	sim:run(1)
	expect(sim:gui(cy, "Overworld").Visible and not hudInBattle(cy), "Cy keeps exploring")
	expect(sim:gui(cy, "Overworld", "Panel", "Content", "Status").Visible, "and is told a fight is on")
	expect(not sim:rootPart(-3).Anchored, "Cy isn't frozen")

	-- Cy walking into an enemy mid-fight doesn't start another one...
	sim:touchEnemy(-3, sim:overworldEnemies().NorthLookout, "front")
	sim:run(2)
	expectEqual(observer.battlesStarted, 1)
	-- ...but once this one's over, Cy (still touching it) starts the next, and pulls in Ann.
	expect(sim:runUntil(function()
		return observer.battlesStarted >= 2
	end, 900), "Cy's fight never started")
	local next = observer.last.battle
	expectEqual(next.startedBy, "Cy")
	expect(isInBattle(next, -3) and isInBattle(next, -1) and not isInBattle(next, -2), "Cy, then Ann (first to join)")
	assertClean(sim, observer)
end)

test("patrolling enemies walk their paths; idle ones stand still and look around", function()
	local sim, observer = newWorld(817)
	local config = sim.server.require(sim.server.dm:GetService("ReplicatedStorage").Combat.CombatConfig)
	local enemies = sim:overworldEnemies()
	local east, north = enemies.EastPatrol, enemies.NorthLookout
	local eastStart, northStart = east.CFrame, north.CFrame
	local sawCorner, stayedOnPath = false, true
	for _ = 1, 100 do
		sim:run(0.2)
		local p = east.CFrame.Position
		stayedOnPath = stayedOnPath and p.X >= 39.9 and p.X <= 90.1 and p.Z >= -30.1 and p.Z <= 30.1
			and (math.abs(p.X - 40) < 0.1 or math.abs(p.X - 90) < 0.1 or math.abs(p.Z + 30) < 0.1 or math.abs(p.Z - 30) < 0.1)
		sawCorner = sawCorner or (math.abs(p.X - 90) < 0.1 and math.abs(p.Z + 30) < 0.1)
		-- It faces where it's going (or, pausing at a corner, the next one).
		expect(math.abs(east.CFrame.LookVector.Y) < 1e-6, "patrols look level")
	end
	expect(east.CFrame.Position ~= eastStart.Position, "the patrol moved")
	expect(stayedOnPath, "it stays on the edges of its route")
	expect(sawCorner, "it reached the next corner of its route")
	expect(north.CFrame.Position == northStart.Position, "the idle one stays put")
	expect(north.CFrame.LookVector:Dot(northStart.LookVector) < 0.99, "and has turned to look another way")
	expect(config.EnemyIdleTurnSeconds < 20)
	assertClean(sim, observer)
end)

print("\nThe player character on the field")

test("Attack: every player's character has it, free, weaker than Strike; enemies don't", function()
	local session, BattleSession, _, server = sessionFixture({ 20, 1, 10, 2 }, { "TungTungGroveKeeper", "TungTungElder" }) -- P1, E1, E2, P2
	local combat = server.dm:GetService("ReplicatedStorage").Combat
	local Summons = server.require(combat.Summons)
	local Abilities = server.require(combat.Abilities)
	for summonId, summon in Summons do
		expect(table.find(summon.abilities, "Attack") == nil, `{summonId} doesn't list Attack itself`)
		expect(BattleSession.canUse({ side = "Party", abilities = summon.abilities }, "Attack"), `{summonId} in a party can Attack`)
		expect(not BattleSession.canUse({ side = "Enemy", abilities = summon.abilities }, "Attack"), `{summonId} as an enemy can't`)
	end
	local attack, strike = Abilities.Attack, Abilities.Strike
	expect(attack.manaCost == 0 and attack.kind == "Attack" and attack.scalingStat == "Strength", "free, Strength-scaled")
	expect(attack.power < strike.power and attack.statRatio <= strike.statRatio, "always weaker than Strike")

	session:rollInitiative()
	session:beginNextTurn() -- P1, the Grove-Keeper (Strength 7)
	local p1 = session.byId.P1
	p1.mana = 0
	assert(session:submitAction(1, "Attack", "E1"))
	expectEqual(p1.mana, 0, "free")
	-- (4 + Strength 7) = 11, minus the Wild Sapling's Endurance 10 (20%) = 8.8 -> 9
	expectEqual(session.byId.E1.maxHp - session.byId.E1.hp, 9, "the Strike formula with Attack's numbers")
	expect(string.find(session.log[#session.log], "used Attack on", 1, true), "logged")
	session:beginNextTurn() -- E1
	local ok, code = session:performEnemyAction("Attack", "P1")
	expect(not ok and code == "UnknownAbility", "enemies have no character to Attack with")
end)

-- Plays Ann's turns by hand through the UI, one move per turn from `moves`, and reports for each
-- who was on the field for it ("character", or "character+summon") and what lunged ("character",
-- "summon", or "-" for nothing), checking along the way that the character never left.
local function playMoves(sim, observer, client, moves)
	local stage = function()
		return client.env.dm:GetService("Workspace"):FindFirstChild("BattleStage")
	end
	local seen = {}
	for _, move in moves do
		runToPhase(sim, observer, function(b)
			local actor = currentActor(b)
			return b.phase == "input" and actor ~= nil and actor.ownerUserId == client.userId
		end, "Ann's turn")
		local actor = currentActor(observer.last.battle)
		local safeArea = client.playerGui.CombatHUD.SafeArea
		local ring, target, list = safeArea.Ring, safeArea.TargetPanel, client.playerGui.SkillList
		expect(sim:runUntil(function()
			return ring.Visible
		end, 2), "the ring never showed") -- the client hears about the turn a moment later
		local spot = stage()[actor.id]
		local character = spot:FindFirstChild("Character")
		expect(character and not spot:FindFirstChild("Summon"), "just the character between moves")
		local root = character.HumanoidRootPart
		local lastSeen = client.lastSnapshot.battle.lastAction
		local sequenceBefore = if lastSeen then lastSeen.sequence else 0
		local tweensBefore = #sim.tweenLog
		if move == "Attack" or move == "Guard" then
			expect(Sim.isClickable(ring[move]), move .. " should be on offer")
			sim:click(client, ring[move])
		else
			sim:click(client, ring.Spell)
			local row = list.SafeArea.List.Rows:FindFirstChild(move)
			expect(row and Sim.isClickable(row), move .. " should be on offer")
			sim:click(client, row)
			if list.Enabled then
				sim:click(client, row) -- the second tap confirms it
			end
		end
		if target.Visible then
			sim:click(client, target.Confirm) -- the preselected target
		end
		expect(sim:runUntil(function()
			local last = client.lastSnapshot.battle and client.lastSnapshot.battle.lastAction
			return last ~= nil and last.sequence > sequenceBefore
		end, 2), move .. " never reached Ann's screen")
		local played = client.lastSnapshot.battle.lastAction
		expect(played.actorId == actor.id and played.abilityId == move, `played {played.abilityId}, not {move}`)

		-- Ann's screen has just played it.
		local summon = spot:FindFirstChild("Summon")
		expect(spot:FindFirstChild("Character") == character, "the character stays on the field")
		local lunged = "-"
		for index = tweensBefore + 1, #sim.tweenLog do
			local tween = sim.tweenLog[index]
			if tween.goals.CFrame ~= nil and rawequal(tween.instance, root) then
				lunged = if lunged == "-" then "character" else lunged .. "+character"
			elseif tween.goals.CFrame ~= nil and summon ~= nil and rawequal(tween.instance, summonRoot(summon)) then
				lunged = if lunged == "-" then "summon" else lunged .. "+summon"
			end
		end
		if summon ~= nil then
			local summonPart = summonBody(summon)
			expect(summonPart.LocalTransparencyModifier == 1, "the summon starts out see-through and materializes")
			sim:run(SUMMON_FADE_SECONDS + 0.05)
			expect(spot:FindFirstChild("Summon") == summon and summonPart.LocalTransparencyModifier == 0, "then it's all there")
			expect(spot:FindFirstChild("Character") == character, "together with the character")
			local behind, up = socketOffset(spot, observer.Summons[actor.summonId])
			expect(behind >= 3 and up >= 3, `behind the character and over its shoulder ({behind}, {up})`)
		end
		sim:run(SUMMON_SECONDS)
		expect(spot:FindFirstChild("Summon") == nil, "a summon is gone once its move has played out")
		expect(spot:FindFirstChild("Character") == character, "and the character is still there")
		table.insert(seen, `{move}:{if summon then "character+summon" else "character"}:{lunged}`)
	end
	return table.concat(seen, " ")
end

test("on the field: your character does Attack and Guard and never leaves; your summon appears behind it for its own abilities", function()
	local sim, observer = newWorld(851)
	local client = join(sim, observer, -1, "Ann", nil)
	sim:run(1)
	touch(sim, observer, -1, "SouthLookout", "side")
	sim:run(0.5)
	local stage = client.env.dm:GetService("Workspace").BattleStage
	for _, p in observer.last.battle.participants do
		local spot = stage[p.id]
		if p.side == "Party" then
			local character = spot:FindFirstChild("Character")
			expect(character and character:FindFirstChild("Torso"), "a copy of the player's own character")
			expect(character:FindFirstChild("Animate") == nil, "without its scripts")
			local offset = character.Torso.CFrame.Position - spot.Spot.CFrame.Position
			expect(offset.Magnitude < 4, "all of it moved onto the stage, not just its root")
			expect(spot:FindFirstChild("Summon") == nil, "its summon waits off the field")
		else
			expect(spot:FindFirstChild("Summon") and not spot:FindFirstChild("Character"), "enemies are just their creature")
		end
	end
	expect(client.env.characters[-1].Archivable == false, "the real character is left as it was")

	local result = playMoves(sim, observer, client, { "Attack", "Strike", "Guard", "GaleClap" })
	expectEqual(
		result,
		-- The character lunges for its own Attack; the summon's model swings its clip instead.
		"Attack:character:character Strike:character+summon:- Guard:character:- GaleClap:character+summon:-"
	)
	assertClean(sim, observer)
end)

-- Summons' art (Summons.luau): the ids of every clip a summon has, by beat.
local function clipIds(sim, summonId)
	local Summons = sim.server.require(sim.server.dm:GetService("ReplicatedStorage").Combat.Summons)
	return Summons[summonId].art.animations
end

local function playedClip(sim, client, id)
	for _, entry in sim.animationLog do
		if entry.env == client.env.name and entry.id == id and entry.event == "Play" then
			return true
		end
	end
	return false
end

test("summons with art are their real model and animations; the rest are blocks", function()
	local sim, observer = newWorld(853)
	local config = sim.server.require(sim.server.dm:GetService("ReplicatedStorage").Combat.CombatConfig)
	config.PartySummons = { "TungTungSahur", "TungTungSahur" }
	config.EnemySummons = { "TungTungSapling", "WildSapling" } -- a creature with art, and one without:
	local client = join(sim, observer, -1, "Ann", { thinkMin = 0.3, thinkMax = 1, policy = "greedy" })
	-- every summon has art now, so take the Wild Sapling's away on Ann's screen to see the fallback
	client.env.require(client.env.dm:GetService("ReplicatedStorage").Combat.Summons).WildSapling.art = nil
	sim:run(1)
	touch(sim, observer, -1, "SouthLookout", "side")
	sim:run(0.5)

	local stage = client.env.dm:GetService("Workspace").BattleStage
	local sahur, sapling = clipIds(sim, "TungTungSahur"), clipIds(sim, "TungTungSapling")
	for _, p in observer.last.battle.participants do
		local spot = stage[p.id]
		if p.side == "Party" then
			expect(spot:FindFirstChild("Summon") == nil, "a party summon waits off the field")
		elseif p.summonId == "WildSapling" then
			local creature = spot.Summon
			expect(creature:FindFirstChild("Block") and creature:FindFirstChildOfClass("AnimationController") == nil, "no art: a block")
		else
			local creature = spot.Summon
			expect(creature:FindFirstChild("Block") == nil, "its real model, not a block")
			expect(creature:FindFirstChildOfClass("AnimationController"), "an animated rig")
			local body = summonBody(creature)
			local bottom = body.CFrame.Position.Y - body.Size.Y / 2
			local Summons = sim.server.require(sim.server.dm:GetService("ReplicatedStorage").Combat.Summons)
			local sunk = (Summons[p.summonId].art.groundOffset or 0) * body.Size.Y -- its clips lift it back up
			expect(math.abs(bottom + sunk) < 0.01, `standing on the stage floor once its clips play ({bottom})`)
			expect(summonRoot(creature).Anchored, "held in place by its root")
			expect(client.env.modelScales[Sim.unwrap(creature)] ~= nil, "scaled to its art's height")
		end
	end
	expect(playedClip(sim, client, sapling.idle), "the creature idles from the start")

	-- A party summon comes out for its own attack: idle, then its swing.
	expect(sim:runUntil(function()
		return playedClip(sim, client, sahur.attack)
	end, 120), "no Tung Tung Sahur ever swung its attack clip")
	expect(playedClip(sim, client, sahur.idle), "it idles while it's out")

	-- Someone falls by the end: the creature (on the floor) or a party member's summon (it comes
	-- out to fall).
	expect(sim:runUntil(function()
		return observer.battlesFinished >= 1 and backInOverworld(observer)
	end, 3600), "the battle never finished")
	expect(playedClip(sim, client, sapling.death) or playedClip(sim, client, sahur.death), "a death clip played")

	-- Hit, a player's character flinches: its joints rock back and spring back.
	local flinched = {}
	for _, tween in sim.tweenLog do
		if tween.goals.C0 ~= nil and tween.instance.ClassName == "Motor6D" then
			flinched[tween.instance.Name] = true
			expect(tween.info.Reverses, "and springs back")
		end
	end
	expect(flinched.RootJoint and flinched.Neck, "the character flinched at the waist and the neck")
	assertClean(sim, observer)
end)

test("a summon whose model isn't in the place is a block, with one warning", function()
	local sim, observer = newWorld(854)
	local client = join(sim, observer, -1, "Ann", nil)
	client.env.dm:GetService("ReplicatedStorage").SummonModels.TungTungSahur:Destroy()
	sim:run(1)
	touch(sim, observer, -1, "SouthLookout", "side")
	local result = playMoves(sim, observer, client, { "Strike" })
	expectEqual(result, "Strike:character+summon:summon")
	local stage = client.env.dm:GetService("Workspace").BattleStage
	for _, p in observer.last.battle.participants do
		if p.side == "Party" and p.ownerUserId == -1 then
			local spot = stage[p.id]
			expect(spot:FindFirstChild("Summon") == nil, "back off the field")
		end
	end
	expectEqual(#sim.warnings, 1, "warned once, not per figure")
	expect(string.find(sim.warnings[1].message, "TungTungSahur", 1, true), "naming the missing model")
	table.clear(sim.warnings)
	assertClean(sim, observer)
end)

test("a player whose character this client can't see gets a stand-in figure", function()
	local sim, observer = newWorld(852)
	local ann = join(sim, observer, -1, "Ann", nil)
	local bo = join(sim, observer, -2, "Bo", { thinkMin = 0.3, thinkMax = 1, policy = "greedy" })
	sim:run(1)
	-- Say Bo is far away and hasn't streamed in on Ann's client.
	ann.env.characters[-2]:Destroy()
	ann.env.characters[-2] = nil
	local battle = touch(sim, observer, -1, "SouthLookout", "side")
	sim:run(0.5)
	local annStage = ann.env.dm:GetService("Workspace").BattleStage
	local boStage = bo.env.dm:GetService("Workspace").BattleStage
	for _, p in battle.participants do
		if p.ownerUserId == -2 then
			local standIn = annStage[p.id].Character
			expect(standIn:FindFirstChild("Left Arm"), "Ann sees a stand-in for Bo")
			local offset = standIn["Left Arm"].CFrame.Position - annStage[p.id].Spot.CFrame.Position
			expect(offset.Magnitude < 4, "standing in Bo's spot")
			expect(boStage[p.id].Character:FindFirstChild("Left Arm") == nil, "Bo sees his own character")
		end
	end
	assertClean(sim, observer)
end)

test("a dead avatar gets a stand-in; a copied one leaves its spawn shield behind", function()
	local sim, observer = newWorld(853)
	local ann = join(sim, observer, -1, "Ann", nil)
	join(sim, observer, -2, "Bo", { thinkMin = 0.3, thinkMax = 1, policy = "greedy" })
	sim:run(1)
	-- Bo has just reset: his character is dead, in pieces until he respawns.
	ann.env.characters[-2]:FindFirstChildOfClass("Humanoid").Health = 0
	-- Ann has only just spawned: her character still has the SpawnLocation's ForceField.
	roblox.Instance.new("ForceField").Parent = ann.env.characters[-1]
	local battle = touch(sim, observer, -1, "SouthLookout", "side")
	sim:run(0.5)
	local annStage = ann.env.dm:GetService("Workspace").BattleStage
	local checked = 0
	for _, p in battle.participants do
		if p.ownerUserId == -2 then
			expect(annStage[p.id].Character:FindFirstChild("Left Arm"), "Ann sees a stand-in for dead Bo")
			checked += 1
		elseif p.ownerUserId == -1 then
			local copy = annStage[p.id].Character
			expect(copy:FindFirstChild("Left Arm") == nil, "Ann's own avatar is copied")
			expect(copy:FindFirstChildOfClass("ForceField") == nil, "without the spawn shield")
			expect(ann.env.characters[-1]:FindFirstChildOfClass("ForceField"), "which her real character keeps")
			checked += 1
		end
	end
	expect(checked == 2, `checked {checked} party members`)
	assertClean(sim, observer)
end)

print("\nUI foundation (M1): the modules, the harness and the safe zones")

-- The UI modules, required on a client the way its own scripts require them.
local function uiModules(client)
	local dm = client.env.dm
	local data = dm:GetService("ReplicatedStorage").UI
	local code = dm:GetService("StarterPlayer").StarterPlayerScripts.UI
	local req = client.env.require
	return {
		Theme = req(data.Theme),
		Strings = req(data.Strings),
		Flags = req(data.Flags),
		Assets = req(data.Assets),
		MockData = req(data.MockData),
		Layout = req(code.Core.Layout),
		ScreenManager = req(code.Core.ScreenManager),
		Input = req(code.Core.Input),
		Harness = req(code.Preview.Harness),
	}
end

local PHONE = roblox.Vector2.new(844, 390)
local SMALL_PHONE = roblox.Vector2.new(667, 375) -- a small phone in landscape, below the design size
local SMALL_PC = roblox.Vector2.new(1024, 576) -- a small PC window
local TABLET = roblox.Vector2.new(1024, 768)
local DESKTOP = roblox.Vector2.new(1920, 1080)

-- A client at a given screen size, joined and on the grass.
local function joinAt(sim, observer, userId, name, viewportSize)
	local client = sim:connectClient(userId, name, { viewportSize = viewportSize })
	assert(sim:runUntil(function()
		return client.started == true
	end, 5), name .. " never started")
	localPlayer(client):SetAttribute("Zone", "Overworld")
	sim:run(0.5)
	attachClientChecker(sim, observer, client)
	return client
end

test("Layout: scale, keep-outs and regions at phone, tablet and desktop sizes", function()
	local sim, observer = newWorld(6000)
	local client = joinAt(sim, observer, -1, "Ann", PHONE)
	local Layout = uiModules(client).Layout

	expectNear(Layout.scaleFor(PHONE), 1, "the design phone renders at scale 1")
	expectNear(Layout.scaleFor(roblox.Vector2.new(1280, 720)), 1280 / 844, "a 720p window scales up")
	expectNear(Layout.scaleFor(DESKTOP), Layout.MAX_SCALE, "1080p hits the cap")
	expectNear(Layout.scaleFor(roblox.Vector2.new(667, 375)), 1, "a smaller phone never scales down")
	expectEqual(Layout.deviceClass(PHONE), "Phone")
	expectEqual(Layout.deviceClass(TABLET), "Tablet")
	expectEqual(Layout.deviceClass(DESKTOP), "Desktop")

	for _, size in { PHONE, TABLET, DESKTOP } do
		local keepOut = Layout.keepOut(size)
		expectNear(keepOut.bottomLeft.y, size.Y * 0.75, "the bottom keep-outs are the bottom 25%")
		expectNear(keepOut.bottomRight.x + keepOut.bottomRight.w, size.X, "the bottom-right keep-out reaches the edge")
		expectNear(keepOut.topLeft.x, 0, "the top-left keep-out sits in the corner")
		for name, region in Layout.regions(size) do
			expect(Layout.hitsKeepOut(region, keepOut) == nil, `region {name} clears the keep-outs at {size.X}x{size.Y}`)
			expect(Layout.contains(Layout.screen(size), region), `region {name} stays on screen at {size.X}x{size.Y}`)
		end
	end

	-- resolve() is what the layout tests use in place of AbsolutePosition / AbsoluteSize.
	local parent = Layout.rect(100, 50, 400, 200)
	local rect = Layout.resolve(roblox.UDim2.new(1, -10, 0, 20), roblox.UDim2.new(0.5, 0, 0, 40), roblox.Vector2.new(1, 0), parent)
	expectNear(rect.x, 100 + 400 - 10 - 200, "anchored to the right edge")
	expectNear(rect.y, 70)
	expectNear(rect.w, 200)
	expectNear(rect.h, 40)
	assertClean(sim, observer)
end)

test("Theme, Strings, Flags and Assets: Mana not MP, every flag off, every image empty", function()
	local sim, observer = newWorld(6001)
	local client = joinAt(sim, observer, -1, "Ann", PHONE)
	local ui = uiModules(client)
	expectEqual(ui.Strings.Mana, "Mana")
	expectEqual(ui.Strings.format.manaCost(8), "8 Mana")
	expectEqual(ui.Strings.format.manaCost(0), "Free")
	expectEqual(ui.Strings.format.returningIn(5), "Returning in 5...")
	for _, flag in { "DownSystem", "ShowAffinities", "ShowItem", "ShowPass", "ShowRoles", "ShowSummonLevels", "UIHarness" } do
		expect(ui.Flags[flag] == false, `Flags.{flag} is off`)
	end
	expect(ui.Theme.Sizes.TapMin >= 48 and ui.Theme.Sizes.TextBody >= 18, "the mobile minimums")
	expect(ui.Theme.SchoolAccent == ui.Theme.Schools.TungWarts.accent, "TungWarts skins the launch UI")
	local count = 0
	for key, entry in ui.Assets.Images do
		count += 1
		expect(entry.id == nil and ui.Assets.image(key) == nil, `{key} has no art yet`)
		expect(string.sub(entry.file, 1, 3) == "UI_", `{key}'s file name follows UI_<Screen>_<Part>`)
	end
	expect(count > 60, "every sheet's parts are keyed")
	for screen in ui.Assets.Screens do
		expectEqual(#ui.Assets.contentFor(screen), 0, `nothing to preload for {screen} without art`)
	end
	assertClean(sim, observer)
end)

test("MockData: every state is a valid snapshot with 1, 2 (solo or two players) or 4 party members", function()
	local sim, observer = newWorld(6002)
	local client = joinAt(sim, observer, -1, "Ann", PHONE)
	local MockData = uiModules(client).MockData
	local expectedMembers = { One = 1, TwoSolo = 2, Two = 2, Four = 4 }
	local states = MockData.states()
	expectEqual(#states, 4 * 11, "four party sizes by eleven scenarios")
	for _, state in states do
		local snapshot = MockData.snapshot(state.size, state.scenario, 1000)
		local battle = snapshot.battle
		expect(battle ~= nil, state.name .. ": has a battle")
		local party, owners, ids = 0, {}, {}
		for _, p in battle.participants do
			expect(ids[p.id] == nil, state.name .. ": ids are unique")
			ids[p.id] = p
			if p.side == "Party" then
				party += 1
				owners[p.ownerUserId] = true
				expect(p.ownerUserId ~= nil, state.name .. ": party members have owners")
			else
				expect(p.ownerUserId == nil, state.name .. ": enemies have none")
			end
			expect(p.hp <= p.maxHp and p.mana <= p.maxMana, state.name .. ": numbers stay in range")
			expect((p.hp == 0) == (p.status == "KnockedOut"), state.name .. ": HP 0 means knocked out, and only then")
		end
		expectEqual(party, expectedMembers[state.size], state.name .. ": party size")
		expect(owners[MockData.LOCAL_USER], state.name .. ": the local player is in the party")
		if state.size == "TwoSolo" then
			expectEqual(battle.participants[2].ownerUserId, MockData.LOCAL_USER, "solo: both members are the local player's")
		end
		expectEqual(#battle.turnQueue, #battle.participants, state.name .. ": everyone is in the turn queue")
		for _, id in battle.turnQueue do
			expect(ids[id] ~= nil, state.name .. ": the queue names real participants")
		end
		if battle.phase == "input" then
			expect(battle.currentActorId ~= nil and ids[battle.currentActorId] ~= nil, state.name .. ": input has an actor")
		elseif battle.phase == "reward" then
			expect(battle.winner ~= nil and battle.overworldReturnAt ~= nil, state.name .. ": reward has a winner and a return time")
		elseif battle.phase == "setup" then
			for _, p in battle.participants do
				expect(p.initiative ~= nil, state.name .. ": setup shows every initiative roll")
			end
		end
		local action = battle.lastAction
		if action then
			expect(ids[action.actorId] ~= nil, state.name .. ": the last action's actor exists")
			for _, result in action.results do
				expect(ids[result.targetId] ~= nil, state.name .. ": its targets exist")
			end
		end
		expectEqual(#MockData.reward(state.size).members, expectedMembers[state.size], state.name .. ": rewards list the party")
	end
	expectEqual(#MockData.affinities, 0, "no real affinity data (R8)")
	assertClean(sim, observer)
end)

test("ScreenManager: a blank screen opens, stacks and closes; the SafeArea follows the screen size", function()
	local sim, observer = newWorld(6003)
	local client = joinAt(sim, observer, -1, "Ann", PHONE)
	local ui = uiModules(client)
	local playerGui = localPlayer(client):WaitForChild("PlayerGui")
	local manager = ui.ScreenManager.new(playerGui)
	local opened, closed = 0, 0
	manager:register("Blank", 10, function(_, gui, safeArea)
		expect(gui.ScreenInsets == roblox.Enum.ScreenInsets.CoreUISafeInsets, "Roblox's own UI is kept clear")
		expect(safeArea.Name == "SafeArea" and safeArea:FindFirstChild("RootScale") ~= nil, "a SafeArea with a root scale")
		return {
			onOpen = function()
				opened += 1
			end,
			onClose = function()
				closed += 1
			end,
		}
	end)
	manager:register("Over", 12, function()
		return {}
	end)
	local blank = client.playerGui:FindFirstChild("Blank")
	expect(blank ~= nil and blank.Enabled == false, "registered screens exist, hidden")
	expectEqual(blank.SafeArea.Size.X.Offset, 844, "the SafeArea is the screen in design pixels")
	expectEqual(blank.SafeArea.Size.Y.Offset, 390)
	expectNear(blank.SafeArea.RootScale.Scale, 1)

	manager:open("Blank")
	expect(blank.Enabled and manager:current() == "Blank" and opened == 1, "open shows it")
	manager:open("Over")
	expectEqual(manager:current(), "Over", "the newest screen is on top")
	expect(manager:back(), "Back closes the top screen")
	expectEqual(manager:current(), "Blank")
	manager:close("Blank")
	expect(not blank.Enabled and manager:current() == nil and closed == 1, "close hides it and empties the stack")

	-- A big screen: scaled up, never down.
	local big = joinAt(sim, observer, -2, "Bo", DESKTOP)
	local bigManager = uiModules(big).ScreenManager.new(localPlayer(big):WaitForChild("PlayerGui"))
	bigManager:register("Blank", 10, function()
		return {}
	end)
	local bigBlank = big.playerGui:FindFirstChild("Blank")
	expect(math.abs(bigBlank.SafeArea.RootScale.Scale - 1.6) < 1e-5, "1080p renders at the scale cap") -- UIScale.Scale is a float32
	expectEqual(bigBlank.SafeArea.Size.X.Offset, 1200, "and its SafeArea is 1920 / 1.6 wide")
	expectEqual(bigBlank.SafeArea.Size.Y.Offset, 675)
	assertClean(sim, observer)
end)

-- Walks a built screen: every button's design size, and whether any image has art.
local function inspect(root)
	local buttons, images = {}, 0
	for _, object in root:GetDescendants() do
		if object:IsA("GuiButton") then
			table.insert(buttons, object)
		elseif object:IsA("ImageLabel") or object:IsA("ImageButton") then
			if object.Image ~= "" then
				images += 1
			end
		end
	end
	return buttons, images
end

test("the harness renders every component with no art, cycles every mock state, and keeps tap targets at 48 px", function()
	local sim, observer = newWorld(6004)
	local client = joinAt(sim, observer, -1, "Ann", PHONE)
	local ui = uiModules(client)
	local playerGui = localPlayer(client):WaitForChild("PlayerGui")
	local handle = ui.Harness.open(playerGui)
	local gui = client.playerGui:FindFirstChild("UIHarness")
	expect(gui ~= nil and gui.Enabled, "the harness is up")
	expect(client.playerGui.CombatHUD.Enabled == false, "the combat HUD steps aside")

	local buttons, images = inspect(gui)
	expect(#buttons >= 8, "buttons, list rows and the controls are all there")
	expectEqual(images, 0, "no image has art: every component is on its fallback look")
	for _, button in buttons do
		local size = button.Size
		local wide = size.X.Scale > 0 or size.X.Offset >= 48
		local tall = size.Y.Scale > 0 or size.Y.Offset >= 48
		expect(wide and tall, `{button:GetFullName()} is at least 48 px (got {size.X.Offset}x{size.Y.Offset})`)
	end
	local tiny = gui.SafeArea.Gallery.Buttons.Tiny -- asked for at 20 px
	expect(tiny.Size.X.Offset >= 48 and tiny.Size.Y.Offset >= 48 and tiny:FindFirstChildOfClass("UISizeConstraint") ~= nil, "to the minimum, with a size constraint")

	local states = ui.MockData.states()
	local seen = {}
	for _ = 1, #states do
		seen[handle.stateName()] = true
		handle.next()
		sim:run(0.1)
	end
	local distinct = 0
	for _ in seen do
		distinct += 1
	end
	expectEqual(distinct, #states, "every mock state was shown")
	expect(gui.SafeArea.Gallery.Misc.Tally.Value.Text ~= "", "the tally counted")
	expect(handle.toggleSafeZones(), "the safe-zone overlay toggles on")
	expect(gui.SafeArea.SafeZoneDebug.Visible, "and is drawn")
	handle.close()
	expect(client.playerGui:FindFirstChild("UIHarness") == nil, "closing removes it")
	expect(client.playerGui.CombatHUD.Enabled, "and gives the combat HUD back")
	sim:run(0.5)
	assertClean(sim, observer)
end)

test("party stacks of 1 and 4 members stay out of the safe zones at phone size", function()
	local sim, observer = newWorld(6005)
	local client = joinAt(sim, observer, -1, "Ann", PHONE)
	local ui = uiModules(client)
	local Layout = ui.Layout
	local handle = ui.Harness.open(localPlayer(client):WaitForChild("PlayerGui"))
	local gui = client.playerGui.UIHarness
	local safeArea = gui.SafeArea
	local virtual = roblox.Vector2.new(safeArea.Size.X.Offset, safeArea.Size.Y.Offset)
	expectEqual(virtual.X, 844)
	local screen = Layout.screen(virtual)
	local keepOut = Layout.keepOut(virtual)
	local safe = Layout.safeArea(virtual)

	local function rectOf(object, parentRect)
		return Layout.resolve(object.Position, object.Size, object.AnchorPoint, parentRect)
	end

	local states = ui.MockData.states()
	local checked = 0
	for index, state in states do
		if state.scenario ~= "MyTurn" then
			continue
		end
		handle.setState(index)
		local stack = safeArea.PartyStack
		local stackRect = rectOf(stack, screen)
		expect(Layout.hitsKeepOut(stackRect, keepOut) == nil, `{state.name}: the party column clears the corners`)
		local cards = {}
		for _, child in stack:GetChildren() do
			if string.sub(child.Name, 1, 5) == "Card_" then
				table.insert(cards, child)
			end
		end
		local expected = { One = 1, TwoSolo = 2, Two = 2, Four = 4 }
		expectEqual(#cards, expected[state.size], `{state.name}: one card per member`)
		for _, card in cards do
			local rect = rectOf(card, stackRect)
			expect(Layout.hitsKeepOut(rect, keepOut) == nil, `{state.name}: {card.Name} clears the corners ({rect.x}, {rect.y}, {rect.w}, {rect.h})`)
			expect(Layout.contains(safe, rect), `{state.name}: {card.Name} is inside the safe area`)
			expect(rect.h >= 44, `{state.name}: {card.Name} keeps a readable height`)
			expect(card.Content.Hp.Value.Text ~= "" and card.Content.Mana.Value.Text ~= "", `{state.name}: {card.Name} shows HP and Mana`)
		end
		local topBar = rectOf(safeArea.TopBar, screen)
		expect(Layout.hitsKeepOut(topBar, keepOut) == nil, `{state.name}: the top bar clears the corners`)
		checked += 1
	end
	expectEqual(checked, 4, "one, two solo, two and four members")
	handle.close()
	assertClean(sim, observer)
end)

test("BattleView keeps its enemy nameplates by default, and drops them for the new HUD (R19)", function()
	local sim, observer = newWorld(6006)
	local client = joinAt(sim, observer, -1, "Ann", PHONE)
	local ui = uiModules(client)
	local BattleView = client.env.require(client.env.dm:GetService("StarterPlayer").StarterPlayerScripts.Combat.BattleView)
	local battle = ui.MockData.snapshot("Two", "MyTurn", 1000).battle
	local workspace = client.env.dm:GetService("Workspace")

	local plain = BattleView.new()
	plain:render(battle)
	local stage = workspace:FindFirstChild("BattleStage")
	expect(stage.E1.Spot.Nameplate.Enabled and stage.P1.Spot.Nameplate.Enabled, "by default every spot has its plate")
	plain:render(nil)

	local hud = BattleView.new({ enemyNameplates = false })
	hud:render(battle)
	stage = workspace:FindFirstChild("BattleStage")
	expect(not stage.E1.Spot.Nameplate.Enabled and not stage.E2.Spot.Nameplate.Enabled, "the new HUD draws enemy plates itself")
	expect(stage.P1.Spot.Nameplate.Enabled, "party plates are untouched")
	hud:render(nil)
	assertClean(sim, observer)
end)

print("\nUI Milestone 2 (M2): the skill list and the combat HUD")

local function m2Modules(client)
	local dm = client.env.dm
	local modules = uiModules(client)
	modules.Bindings = client.env.require(dm:GetService("ReplicatedStorage").UI.Bindings)
	modules.Controls = client.env.require(dm:GetService("StarterPlayer").StarterPlayerScripts.UI.Core.Controls)
	return modules
end

-- Every visible GuiObject under `root` with where it lands on screen (Layout.resolve, since the
-- fake Roblox has no layout engine); hidden subtrees are skipped.
local function visibleRects(Layout, root, rootRect)
	local list = {}
	local function walk(object, parentRect)
		for _, child in object:GetChildren() do
			if child:IsA("GuiObject") and child.Visible then
				local rect = Layout.resolve(child.Position, child.Size, child.AnchorPoint, parentRect)
				table.insert(list, { object = child, rect = rect })
				walk(child, rect)
			end
		end
	end
	walk(root, rootRect)
	return list
end

-- Nothing visible in a HUD ScreenGui touches a keep-out, and every button is a 48 px tap target.
local function checkSafeZones(Layout, gui, label)
	local safeArea = gui.SafeArea
	local virtual = roblox.Vector2.new(safeArea.Size.X.Offset, safeArea.Size.Y.Offset)
	local keepOut, screen = Layout.keepOut(virtual), Layout.screen(virtual)
	local seen = 0
	for _, entry in visibleRects(Layout, safeArea, screen) do
		local object, rect = entry.object, entry.rect
		if object.Name == "Dim" or object.Name == "TapToSkip" then
			continue -- the scene tint behind the list and the results' tap catcher cover the whole screen on purpose
		end
		seen += 1
		expect(Layout.hitsKeepOut(rect, keepOut) == nil, `{label}: {object:GetFullName()} clears the corners ({rect.x}, {rect.y}, {rect.w}, {rect.h})`)
		if object:IsA("GuiButton") then
			expect(rect.w >= 48 and rect.h >= 48, `{label}: {object:GetFullName()} is at least 48 px ({rect.w}x{rect.h})`)
		end
	end
	return seen
end

local function mockStateIndex(ui, size, scenario)
	for index, state in ui.MockData.states() do
		if state.size == size and state.scenario == scenario then
			return index
		end
	end
	error(`no mock state {size} / {scenario}`)
end

test("M2: Bindings turn a snapshot into the HUD's view-model and mirror the server's legality rules (R22)", function()
	local sim, observer = newWorld(6100)
	local client = joinAt(sim, observer, -1, "Ann", PHONE)
	local ui = m2Modules(client)
	local B = ui.Bindings
	local snapshot = ui.MockData.snapshot("Four", "MyTurn", 1000)
	local hud = B.battle(snapshot.battle, -1)
	expectEqual(hud.phase, "Input")
	expectEqual(hud.localActorId, "P1")
	expectEqual(#hud.participants, 6)
	expect(hud.byId.P1.isLocal and not hud.byId.P2.isLocal and not hud.byId.E1.isLocal, "only my summon is local")
	expectEqual(hud.byId.P4.statuses[1].name, "Dazed")
	expectEqual(hud.byId.P4.statuses[1].kind, "Ailment")
	expectEqual(hud.byId.P4.statuses[2].kind, "Buff")
	expect(B.isInBattle(snapshot.battle, -1) and not B.isInBattle(snapshot.battle, -9), "who's in the fight")

	local rows = B.abilityRows(hud.byId.P1, hud.byId.P1.abilityIds)
	expectEqual(#rows, 2)
	expectEqual(rows[1].id, "Strike")
	expect(rows[1].canAfford, "Strike (2 Mana) with 5 Mana")
	expect(not rows[2].canAfford, "Gale Clap (8 Mana) isn't affordable")
	expectEqual(rows[2].needsTarget, "Enemy")
	expectEqual(rows[2].elementId, "Wind")
	local ids = {}
	for _, command in B.commands(hud.byId.P1.abilityIds) do
		table.insert(ids, command.id)
	end
	expectEqual(table.concat(ids, ","), "Attack,Spell,Guard", "Item and Pass stay behind their flags")

	local legal, best = B.targetsFor("Attack", hud.byId.P1, hud)
	expectEqual(#legal, 2)
	expectEqual(best.id, "E1", "the first enemy is preselected")
	legal, best = B.targetsFor("SapMend", hud.byId.P4, hud)
	expectEqual(#legal, 4, "a heal offers every standing party member")
	expectEqual(best.id, "P4", "the most hurt one first")
	legal = B.targetsFor("Guard", hud.byId.P1, hud)
	expectEqual(#legal, 0, "Guard needs no pick")
	expectEqual(B.abilityRow("Tailwind", 20).needsTarget, "AllAllies")
	expectEqual(B.abilityRow("KnockOnWood", 20).needsTarget, "None")

	local ko = B.battle(ui.MockData.snapshot("Two", "Crit", 1000).battle, -1)
	legal = B.targetsFor("Attack", ko.byId.P1, ko)
	expectEqual(#legal, 1, "a knocked-out enemy can't be targeted")
	expectEqual(legal[1].id, "E2")
	expect(ko.byId.E1.knockedOut and not ko.byId.E1.isDown, "KnockedOut is never Down (R7)")
	local enemyTurn = B.battle(ui.MockData.snapshot("Two", "EnemyTurn", 1000).battle, -1)
	expect(enemyTurn.localActorId == nil, "no local actor on the enemy's turn")
	assertClean(sim, observer)
end)

-- Every mock state through the harness's HUD mode at one screen size: what shows when, the
-- cards and plates, the feed, the safe zones and the tap sizes.
local function checkHudStatesAt(label, viewport)
	local sim, observer = newWorld(6101)
	local client = joinAt(sim, observer, -1, "Ann", viewport)
	local ui = m2Modules(client)
	local Layout, Strings = ui.Layout, ui.Strings
	local handle = ui.Harness.open(localPlayer(client):WaitForChild("PlayerGui"))
	handle.setHudMode(true)
	local gui = client.playerGui:FindFirstChild("HarnessCombatHUD")
	expect(gui ~= nil and gui.Enabled, `{label}: the harness opened the HUD on mock data`)
	local safeArea = gui.SafeArea
	expectEqual(safeArea.Size.X.Offset, math.round(viewport.X / Layout.scaleFor(viewport)), `{label}: the SafeArea is the screen in design pixels`)
	local expectedCards = { One = 1, TwoSolo = 2, Two = 2, Four = 4 }

	for index, state in ui.MockData.states() do
		local name = `{label} {state.name}`
		handle.setState(index)
		sim:run(0.05)
		local battle = ui.MockData.snapshot(state.size, state.scenario).battle
		local actor = if battle.currentActorId then participantById(battle, battle.currentActorId) else nil
		local myTurn = battle.phase == "input" and actor ~= nil and actor.ownerUserId == -1
		expectEqual(safeArea.Ring.Visible, myTurn, `{name}: the ring shows only on my turn`)
		expectEqual(safeArea.Reveal.Visible, battle.phase == "setup", `{name}: the initiative reveal`)
		expectEqual(safeArea.TurnBar.Visible, battle.phase ~= "setup" and battle.phase ~= "reward", `{name}: the turn bar`)
		local resultsGui = client.playerGui.HarnessResults
		expectEqual(resultsGui.Enabled, battle.phase == "reward", `{name}: the results screen`)
		if battle.phase == "reward" then
			expectEqual(resultsGui.SafeArea.Title.Text.Text, if battle.winner == "Party" then Strings.Victory else Strings.Defeat, name)
			expect(resultsGui.SafeArea.Returning.Text ~= "", `{name}: the return countdown`)
			checkSafeZones(Layout, resultsGui, name)
		end
		if battle.phase == "setup" then
			expect(string.find(safeArea.Reveal.Panel.Content.Rolls.Text, "+ 5 =", 1, true) ~= nil, `{name}: the rolls are listed`)
		end
		if myTurn then
			for _, ribbon in { "Attack", "Spell", "Guard" } do
				expect(Sim.isClickable(safeArea.Ring[ribbon]), `{name}: the {ribbon} ribbon`)
			end
			expect(safeArea.Ring:FindFirstChild("Item") == nil and safeArea.Ring:FindFirstChild("Pass") == nil, `{name}: Item and Pass stay behind their flags`)
			expect(string.find(safeArea.Status.Title.Text, Strings.YourTurn, 1, true) ~= nil, `{name}: says it's my turn`)
			expect(string.find(safeArea.Status.Detail.Text, "s left", 1, true) ~= nil, `{name}: with the time left`)
			expect(safeArea.ManaPlate.Visible and safeArea.ManaPlate.Plate.Content.Mana.Value.Text ~= "", `{name}: the hero Mana plate`)
		else
			expect(not safeArea.ManaPlate.Visible, `{name}: no Mana plate off my turn`)
			expect(not safeArea.TargetPanel.Visible, `{name}: no target panel off my turn`)
		end
		-- The recent-actions feed: the last log lines while the fight is on, out of the way otherwise.
		local feedOn = (battle.phase == "input" or battle.phase == "resolve") and #battle.log > 0
		expectEqual(safeArea.Log.Visible, feedOn, `{name}: the recent-actions feed`)
		if feedOn then
			local text = safeArea.Log.Lines.Text
			local last = battle.log[#battle.log]
			expect(string.sub(text, -#last) == last, `{name}: the feed ends with the latest log line`)
			local _, lineBreaks = string.gsub(text, "\n", "")
			expect(lineBreaks < 3, `{name}: at most three lines in the feed`)
		end
		local cards = 0
		for _, child in safeArea.Party:GetChildren() do
			if string.sub(child.Name, 1, 5) == "Card_" then
				cards += 1
				local id = string.sub(child.Name, 6)
				local p = participantById(battle, id)
				expectEqual(child.Content.Hp.Value.Text, Strings.format.hp(p.hp, p.maxHp), `{name}: {child.Name} HP`)
				expectEqual(child.Content.StatusTag.Visible, p.status ~= "Active", `{name}: {child.Name} KO tag`)
				expectEqual(child.Content.Owner.Text, if p.ownerUserId == -1 then Strings.format.you(p.ownerName) else p.ownerName, `{name}: {child.Name} says whose summon it is`)
			end
		end
		expectEqual(cards, expectedCards[state.size], `{name}: one card per member`)
		-- Each enemy's statuses as tags on its plate (the plates themselves need a stage to show).
		local plates = client.playerGui.HarnessCombatHUDEnemies
		for _, p in battle.participants do
			if p.side == "Enemy" then
				local plate = plates:FindFirstChild("Enemy_" .. p.id)
				expect(plate ~= nil, `{name}: a plate for {p.id}`)
				local tags = {}
				for _, tag in plate.Root.Statuses:GetChildren() do
					if tag:IsA("ImageLabel") then
						table.insert(tags, tag.Label.Text)
					end
				end
				expectEqual(#tags, #p.statuses, `{name}: one tag per status on {p.id}`)
				for _, status in p.statuses do
					local def = observer.StatusEffects[status.id]
					expect(table.find(tags, Strings.format.statusTurns(def.name, status.turnsLeft)) ~= nil, `{name}: {status.id} tagged on {p.id}`)
				end
			end
		end
		local tokens = 0
		for _, child in safeArea.TurnBar.Plate.Content.Tokens:GetChildren() do
			if child:IsA("ImageLabel") then
				tokens += 1
				expectEqual(child.Now.Visible, battle.currentActorId == child.Name and battle.phase ~= "reward", `{name}: NOW on {child.Name}`)
			end
		end
		expectEqual(tokens, #battle.turnQueue, `{name}: one token per participant`)
		expect(not safeArea.Stamps.Visible, `{name}: no stamps with the Down system off`)
		checkSafeZones(Layout, gui, name)
		local _, images = inspect(safeArea)
		expectEqual(images, 0, `{name}: no art, every piece on its fallback`)
	end

	-- The list and the target panel at this size: clear of the corners, names with room.
	handle.setState(mockStateIndex(ui, "One", "MyTurn"))
	sim:click(client, safeArea.Ring.Spell)
	local listGui = client.playerGui.HarnessSkillList
	expect(listGui.Enabled, `{label}: Spell opens the list`)
	checkSafeZones(Layout, listGui, `{label} list`)
	local titleWidth = listGui.SafeArea.List.Size.X.Offset - 8 - 170
	expect(titleWidth >= 120, `{label}: the ability names have room ({titleWidth} px)`)
	sim:click(client, listGui.SafeArea.Back)
	sim:click(client, safeArea.Ring.Attack)
	expect(safeArea.TargetPanel.Visible, `{label}: Attack asks for a target`)
	checkSafeZones(Layout, gui, `{label} target`)
	sim:click(client, safeArea.TargetPanel.Back)

	-- Hovering or holding a ribbon shows what the move does, where the status detail was.
	local config = client.env.require(client.env.dm:GetService("ReplicatedStorage").Combat.CombatConfig)
	local guardLine = Strings.format.guard(math.round(config.GuardDamageReduction * 100), math.round((1 - config.GuardAilmentChanceMultiplier) * 100))
	local detail = safeArea.Status.Detail
	client.env.instanceSignal(safeArea.Ring.Guard, "MouseEnter"):Fire()
	expectEqual(detail.Text, guardLine, `{label}: hovering Guard explains it`)
	client.env.instanceSignal(safeArea.Ring.Guard, "MouseLeave"):Fire()
	expect(string.find(detail.Text, "s left", 1, true) ~= nil, `{label}: the timer is back once the pointer leaves`)
	client.env.instanceSignal(safeArea.Ring.Guard, "MouseButton1Down"):Fire()
	expectEqual(detail.Text, guardLine, `{label}: holding Guard explains it`)
	client.env.instanceSignal(safeArea.Ring.Guard, "MouseButton1Up"):Fire()
	expect(string.find(detail.Text, "s left", 1, true) ~= nil, `{label}: and the timer is back on release`)
	client.env.instanceSignal(safeArea.Ring.Attack, "MouseEnter"):Fire()
	expectEqual(detail.Text, observer.Abilities.Attack.description, `{label}: hovering Attack explains it too`)
	client.env.instanceSignal(safeArea.Ring.Attack, "MouseLeave"):Fire()

	handle.showStamp("OneMore")
	expect(safeArea.Stamps.Visible and safeArea.Stamps.OneMore.Visible, `{label}: the harness can force ONE MORE!`)
	handle.setHudMode(false)
	expect(client.playerGui:FindFirstChild("HarnessCombatHUD") == nil, `{label}: leaving HUD mode removes it`)
	expect(client.playerGui.UIHarness.SafeArea.Gallery.Visible, `{label}: and brings the gallery back`)
	handle.close()
	sim:run(0.5)
	assertClean(sim, observer)
end

test("M2: the combat HUD renders every mock state from the harness at phone, small-phone and small-PC sizes, clear of the safe zones", function()
	checkHudStatesAt("phone", PHONE)
	checkHudStatesAt("small phone", SMALL_PHONE)
	checkHudStatesAt("small PC", SMALL_PC)
end)

test("M2: the Spell list (S7): the summon's kit with Mana costs, dimmed rows that say why, Back, then a target", function()
	local sim, observer = newWorld(6102)
	local client = joinAt(sim, observer, -1, "Ann", PHONE)
	local ui = m2Modules(client)
	local Layout, Strings, Theme = ui.Layout, ui.Strings, ui.Theme
	local handle = ui.Harness.open(localPlayer(client):WaitForChild("PlayerGui"))
	handle.setHudMode(true)
	handle.setState(mockStateIndex(ui, "One", "MyTurn")) -- 5 Mana: Strike (2) yes, Gale Clap (8) no
	local safeArea = client.playerGui.HarnessCombatHUD.SafeArea
	local listGui = client.playerGui.HarnessSkillList
	expect(not listGui.Enabled, "the list is closed to start")

	sim:click(client, safeArea.Ring.Spell)
	expect(listGui.Enabled and not safeArea.Ring.Visible and safeArea.Dim.Visible, "Spell opens the list over a dimmed scene")
	expect(safeArea.TurnBar.Visible and safeArea.ManaPlate.Visible, "the turn bar and Mana plate persist")
	expectEqual(listGui.SafeArea.Header.Plate.Content.Title.Text, Strings.Spell)
	local rows = listGui.SafeArea.List.Rows
	local strike, gale = rows:FindFirstChild("Strike"), rows:FindFirstChild("GaleClap")
	expect(strike ~= nil and gale ~= nil and rows:FindFirstChild("Attack") == nil, "one row per ability in the summon's kit")
	expect(strike.Cost ~= nil and gale.Cost ~= nil, "each with its Mana cost")
	expect(strike.Title.TextColor3 == Theme.Colors.TextLight and gale.Title.TextColor3 == Theme.Colors.TextDim, "Gale Clap is dimmed")
	expect(strike.Description.Visible and not gale.Description.Visible, "the selected row shows its description")
	expect(Sim.isClickable(listGui.SafeArea.Confirm), "Confirm is on for the preselected Strike")
	sim:click(client, gale)
	local toast = listGui.SafeArea.Toast
	expect(toast.Visible and toast.Label.Text == Strings.NotEnoughMana, "tapping a dimmed row says why")
	expect(listGui.Enabled and not safeArea.TargetPanel.Visible, "and nothing else happens")
	expect(checkSafeZones(Layout, listGui, "list") > 4, "the list, Confirm and Back clear the corners")
	local titleWidth = listGui.SafeArea.List.Size.X.Offset - 8 - 170 -- the row's title: the list width less the medallion and the capsule
	expect(titleWidth >= 150, `the ability names have room ({titleWidth} px)`)
	local virtual = roblox.Vector2.new(listGui.SafeArea.Size.X.Offset, listGui.SafeArea.Size.Y.Offset)
	local bottomClear = virtual.Y * (1 - Layout.KEEP_OUT.bottomRight.h)
	local confirm = listGui.SafeArea.Confirm
	expect(confirm.Position.Y.Offset + confirm.Size.Y.Offset <= bottomClear, "the list ends above the bottom corners")

	sim:click(client, listGui.SafeArea.Back)
	expect(not listGui.Enabled and safeArea.Ring.Visible and not safeArea.Dim.Visible, "Back returns to the ring")

	sim:click(client, safeArea.Ring.Spell)
	sim:click(client, rows.Strike) -- preselected, so the tap confirms it
	expect(not listGui.Enabled and safeArea.TargetPanel.Visible and not safeArea.Ring.Visible, "choosing Strike moves on to the target")
	expectEqual(safeArea.TargetPanel.Caption.Text, Strings.PickEnemy)
	expect(string.find(safeArea.Status.Detail.Text, Strings.PickEnemy, 1, true) == 1, "the status says to pick an enemy")
	sim:click(client, safeArea.TargetPanel.Back)
	expect(safeArea.Ring.Visible and not safeArea.TargetPanel.Visible, "Back from the target returns to the ring")
	sim:click(client, safeArea.Ring.Spell)
	sim:click(client, rows.Strike)
	sim:click(client, safeArea.TargetPanel.Confirm)
	local ability, target = handle.lastAction()
	expectEqual(ability, "Strike")
	expectEqual(target, "E1", "the first enemy is preselected")
	expectEqual(safeArea.Status.Detail.Text, Strings.Sending)
	expect(not safeArea.Ring.Visible and not safeArea.TargetPanel.Visible, "locked until the server moves on")
	handle.close()
	assertClean(sim, observer)
end)

test("M2: keyboard: 1 is Attack, 2 is Spell, Enter confirms, Backspace goes back, and hints show for keyboard players", function()
	local sim, observer = newWorld(6103)
	local client = joinAt(sim, observer, -1, "Ann", DESKTOP)
	local ui = m2Modules(client)
	local handle = ui.Harness.open(localPlayer(client):WaitForChild("PlayerGui"))
	handle.setHudMode(true)
	handle.setState(mockStateIndex(ui, "One", "MyTurn"))
	local safeArea = client.playerGui.HarnessCombatHUD.SafeArea
	local listGui = client.playerGui.HarnessSkillList
	local input = client.env.getService("UserInputService")
	local function press(key)
		input.InputBegan:Fire({ KeyCode = roblox.Enum.KeyCode[key], UserInputType = roblox.Enum.UserInputType.Keyboard }, false)
	end
	expect(not safeArea.Ring.Attack.KeyHint.Visible, "no hints for a mouse player")
	ui.Input.override("Keyboard")
	expectEqual(safeArea.Ring.Attack.KeyHint.Text, "[1]")
	expectEqual(safeArea.Ring.Spell.KeyHint.Text, "[2]")
	expectEqual(safeArea.Ring.Guard.KeyHint.Text, "[4]")
	expect(safeArea.Ring.Attack.KeyHint.Visible, "hints show for keyboard players")

	press("One")
	expect(safeArea.TargetPanel.Visible, "1 is Attack")
	press("Backspace")
	expect(safeArea.Ring.Visible and not safeArea.TargetPanel.Visible, "Backspace goes back")
	press("Two")
	expect(listGui.Enabled, "2 is Spell")
	press("Return")
	expect(not listGui.Enabled and safeArea.TargetPanel.Visible, "Enter confirms the selected row")
	press("Return")
	local ability, target = handle.lastAction()
	expectEqual(ability, "Strike")
	expectEqual(target, "E1")
	ui.Input.override("Mouse")
	handle.close()
	assertClean(sim, observer)
end)

-- A client at a phone size, joined and on the grass (the HUD is the only UI now).
local function joinHud(sim, observer, userId, name, viewportSize)
	return joinAt(sim, observer, userId, name, viewportSize)
end

local function lastSequence(client)
	local battle = client.lastSnapshot and client.lastSnapshot.battle
	return if battle and battle.lastAction then battle.lastAction.sequence else 0
end

-- Waits for the ring on this client's turn.
local function hudTurn(sim, client)
	local safeArea = client.playerGui.CombatHUD.SafeArea
	expect(sim:runUntil(function()
		return safeArea.Ring.Visible
	end, 90), "the ring never showed")
	return currentActor(client.lastSnapshot.battle), lastSequence(client)
end

local function waitPlayed(sim, client, sequenceBefore, move)
	expect(sim:runUntil(function()
		return lastSequence(client) > sequenceBefore
	end, 3), move .. " never played")
	return client.lastSnapshot.battle.lastAction
end

test("M2: a real fight on the new HUD: Attack, Spell and Guard through the ring, the enemy plates, and the controls off until it's over (R21)", function()
	local sim, observer = newWorld(6104)
	local client = joinHud(sim, observer, -1, "Ann", PHONE)
	local ui = m2Modules(client)
	local Controls, Strings, Theme = ui.Controls, ui.Strings, ui.Theme
	expect(Controls.isEnabled(), "controls on while exploring")
	sim:run(1)
	local battle = touch(sim, observer, -1, "NorthLookout", "front")
	expectEqual(battle.opening, "Party")
	expect(sim:runUntil(function()
		return client.lastSnapshot ~= nil and client.lastSnapshot.battle ~= nil
	end, 2), "the client never heard about the fight")
	local safeArea = client.playerGui.CombatHUD.SafeArea
	local enemies = client.playerGui.CombatHUDEnemies
	expect(not Controls.isEnabled(), "controls off in the fight")
	expectEqual(Controls.changes(), 1)
	expect(safeArea.Reveal.Visible and string.find(safeArea.Reveal.Panel.Content.Title.Text, "struck first", 1, true) ~= nil, "the reveal says who struck first")
	expect(enemies:FindFirstChild("Enemy_E1") ~= nil and enemies.Enemy_E1.Enabled, "a plate over the enemy")

	-- 1. Attack: the ring, then the preselected enemy, confirmed.
	local actor, before = hudTurn(sim, client)
	expect(string.find(safeArea.Status.Detail.Text, "s left", 1, true) ~= nil, "the turn timer")
	sim:click(client, safeArea.Ring.Attack)
	expect(safeArea.TargetPanel.Visible and not safeArea.Ring.Visible, "Attack asks for a target")
	expectEqual(safeArea.TargetPanel.Caption.Text, Strings.PickEnemy)
	local plate = enemies.Enemy_E1.Root
	expect(plate.BracketLeft.Visible and plate.BracketLeft.BackgroundColor3 == Theme.Colors.Gold and Sim.isClickable(plate.Plate), "gold brackets on the chosen enemy, which can be tapped")
	sim:click(client, safeArea.TargetPanel.Confirm)
	expectEqual(safeArea.Status.Detail.Text, Strings.Sending)
	local played = waitPlayed(sim, client, before, "Attack")
	expectEqual(played.abilityId, "Attack")
	expectEqual(played.actorId, actor.id)
	expectEqual(played.results[1].targetId, "E1")

	-- 2. Spell: the list, Strike (preselected, so the tap confirms), then the enemy tapped twice.
	actor, before = hudTurn(sim, client)
	sim:click(client, safeArea.Ring.Spell)
	local list = client.playerGui.SkillList
	expect(list.Enabled, "Spell opens the list")
	sim:click(client, list.SafeArea.List.Rows.Strike)
	expect(not list.Enabled and safeArea.TargetPanel.Visible, "Strike wants a target")
	local chosen, other = nil, nil
	for _, gui in enemies:GetChildren() do
		if Sim.isClickable(gui.Root.Plate) then
			if gui.Root.BracketLeft.BackgroundColor3 == Theme.Colors.Gold then
				chosen = gui
			else
				other = gui
			end
		end
	end
	expect(chosen ~= nil, "one enemy is preselected")
	local pick = other or chosen
	if other then
		sim:click(client, other.Root.Plate) -- a tap picks it
		expect(safeArea.TargetPanel.Visible and other.Root.BracketLeft.BackgroundColor3 == Theme.Colors.Gold, "the pick moved to the tapped enemy")
	end
	sim:click(client, pick.Root.Plate) -- a second tap confirms it
	played = waitPlayed(sim, client, before, "Strike")
	expectEqual(played.abilityId, "Strike")
	expectEqual(played.results[1].targetId, string.sub(pick.Name, 7))

	-- 3. Guard: straight away, no target.
	actor, before = hudTurn(sim, client)
	sim:click(client, safeArea.Ring.Guard)
	expect(not safeArea.TargetPanel.Visible and not safeArea.Ring.Visible, "Guard needs no target")
	played = waitPlayed(sim, client, before, "Guard")
	expectEqual(played.abilityId, "Guard")
	expectEqual(played.actorId, actor.id)
	expect(string.find(safeArea.Party["Card_" .. actor.id].Content.Statuses.Text, "Bracing", 1, true) ~= nil, "its card shows it's bracing")

	-- A reset mid-fight: the fresh character stays without controls, and the plates (which the
	-- respawn clears out of PlayerGui with everything but the HUD's ScreenGuis) come back.
	sim:spawnCharacter(-1)
	sim:run(0.5)
	expect(not Controls.isEnabled(), "still off after a respawn mid-fight")
	expect(client.playerGui:FindFirstChild("CombatHUD") ~= nil and client.playerGui:FindFirstChild("SkillList") ~= nil, "the HUD's ScreenGuis survive a respawn")
	expect(sim:runUntil(function()
		local folder = client.playerGui:FindFirstChild("CombatHUDEnemies")
		return folder ~= nil and folder:FindFirstChild("Enemy_E1") ~= nil and folder.Enemy_E1.Enabled
	end, 5), "the enemy plates are rebuilt after a respawn")

	-- Fight on with Attack until it's over.
	local rounds = 0
	while client.lastSnapshot.battle ~= nil and client.lastSnapshot.battle.phase ~= "reward" do
		rounds += 1
		expect(rounds < 600, "the fight never ended")
		if safeArea.Ring.Visible then
			sim:click(client, safeArea.Ring.Attack)
			sim:click(client, safeArea.TargetPanel.Confirm)
		end
		sim:run(0.5)
	end
	local resultsGui = client.playerGui.Results
	expect(sim:runUntil(function()
		return resultsGui.Enabled
	end, 5), "the results screen at the end, once the final blow has played")
	local won = client.lastSnapshot.battle.winner == "Party"
	expectEqual(resultsGui.SafeArea.Title.Text.Text, if won then Strings.Victory else Strings.Defeat)
	-- Back (keyboard or gamepad B) skips the count-up, even though there is no actor to act for now.
	if won then
		local expValue = resultsGui.SafeArea.Tallies.Exp.Value
		expect(resultsGui.SafeArea.SkipHint.Visible and expValue.Text ~= Strings.format.gained(ui.MockData.reward("TwoSolo").exp), "the tallies are counting")
		client.env.getService("UserInputService").InputBegan:Fire({ KeyCode = roblox.Enum.KeyCode.Backspace, UserInputType = roblox.Enum.UserInputType.Keyboard }, false)
		expect(not resultsGui.SafeArea.SkipHint.Visible and expValue.Text == Strings.format.gained(ui.MockData.reward("TwoSolo").exp), "Back skipped straight to the totals")
	end
	expect(string.find(resultsGui.SafeArea.Returning.Text, "Returning", 1, true) ~= nil, "with the return countdown")
	expect(not safeArea.Party.Visible and not safeArea.TurnBar.Visible, "the HUD's own widgets step aside for it")
	expect(not Controls.isEnabled(), "controls stay off on the result screen")
	expect(sim:runUntil(function()
		return client.lastSnapshot.battle == nil
	end, 30), "never came back to the overworld")
	expect(Controls.isEnabled(), "controls back on in the overworld")
	expectEqual(Controls.changes(), 2, "off once, on once")
	enemies = client.playerGui.CombatHUDEnemies -- a fresh folder since the respawn mid-fight
	expect(not safeArea.Party.Visible and not resultsGui.Enabled and not enemies.Enemy_E1.Enabled, "the HUD cleared")
	sim:run(1)
	assertClean(sim, observer)
end)


test("M2: a reset during my own turn brings the enemy plates and my pick straight back, before any new snapshot", function()
	local sim, observer = newWorld(6106)
	local client = joinHud(sim, observer, -1, "Ann", PHONE)
	local Theme = m2Modules(client).Theme
	sim:run(1)
	touch(sim, observer, -1, "NorthLookout", "front")
	local safeArea = client.playerGui.CombatHUD.SafeArea
	hudTurn(sim, client)
	sim:click(client, safeArea.Ring.Attack)
	expect(safeArea.TargetPanel.Visible, "picking a target")
	local enemies = client.playerGui.CombatHUDEnemies
	-- Move the pick off the default enemy when there is another one, so the pick itself is tested.
	local other = nil
	for _, gui in enemies:GetChildren() do
		if Sim.isClickable(gui.Root.Plate) and gui.Root.BracketLeft.BackgroundColor3 ~= Theme.Colors.Gold then
			other = gui
		end
	end
	if other then
		sim:click(client, other.Root.Plate)
	end
	local chosen = if other then other.Name else "Enemy_E1"
	local snapshotBefore = client.lastSnapshot
	local sequenceBefore = lastSequence(client)

	sim:spawnCharacter(-1) -- a reset: PlayerGui cleared, CharacterAdded fired, nothing from the server
	expect(client.lastSnapshot == snapshotBefore, "no new snapshot arrived")
	local folder = client.playerGui:FindFirstChild("CombatHUDEnemies")
	expect(folder ~= nil and folder ~= enemies, "a fresh plate folder, at once")
	for _, gui in folder:GetChildren() do
		expect(gui.Enabled and gui.Root.BracketLeft.Visible and Sim.isClickable(gui.Root.Plate), gui.Name .. " is back and pickable")
	end
	expect(folder[chosen].Root.BracketLeft.BackgroundColor3 == Theme.Colors.Gold, "the chosen enemy still has the gold brackets")
	expect(safeArea.TargetPanel.Visible and Sim.isClickable(safeArea.TargetPanel.Confirm), "the target panel is still up")

	sim:click(client, folder[chosen].Root.Plate) -- tapping the fresh plate of the pick confirms it
	local played = waitPlayed(sim, client, sequenceBefore, "Attack")
	expectEqual(played.abilityId, "Attack")
	expectEqual(played.results[1].targetId, string.sub(chosen, 7))
	sim:run(1)
	assertClean(sim, observer)
end)

print("\nUI Milestone 3 (M3): the results screen")

test("M3: the results screen (S6) on mock rewards: tallies count up in turn, items and LEVEL UP! follow, the countdown runs, a tap skips", function()
	local sim, observer = newWorld(6200)
	local client = joinAt(sim, observer, -1, "Ann", PHONE)
	local ui = m2Modules(client)
	local Layout, Strings, MockData = ui.Layout, ui.Strings, ui.MockData
	local handle = ui.Harness.open(localPlayer(client):WaitForChild("PlayerGui"))
	handle.setHudMode(true)
	local resultsGui = client.playerGui.HarnessResults
	expect(not resultsGui.Enabled, "closed until a fight is decided")

	handle.setState(mockStateIndex(ui, "Four", "Victory"))
	expect(resultsGui.Enabled, "open on the reward phase")
	local area = resultsGui.SafeArea
	expectEqual(area.Title.Text.Text, Strings.Victory)
	expect(area.Title.Text.Visible and not area.Title.Lettering.Visible, "live lettering while there is no art")
	local mock = MockData.reward("Four")
	local exp, gold = area.Tallies.Exp.Value, area.Tallies.Currency.Value
	expect(exp.Text ~= Strings.format.gained(mock.exp), "EXP starts counting from zero")
	expect(area.SkipHint.Visible, "the skip hint shows while counting")
	local slotsShown = 0
	for _, slot in area.Tallies.Items.Content.Slots:GetChildren() do
		if slot:IsA("ImageLabel") and slot.Visible then slotsShown += 1 end
	end
	expectEqual(slotsShown, 0, "items wait for the tallies")
	expectEqual(area.Returning.Text, Strings.format.returningIn(8), "the countdown from overworldReturnAt")

	sim:run(2.6) -- EXP then the currency, a second each
	expectEqual(exp.Text, Strings.format.gained(mock.exp), "EXP counted up")
	expectEqual(gold.Text, Strings.format.gained(mock.currency), "then the currency")
	slotsShown = 0
	for _, slot in area.Tallies.Items.Content.Slots:GetChildren() do
		if slot:IsA("ImageLabel") and slot.Visible then
			slotsShown += 1
			expectEqual(slot.Quantity.Label.Text, Strings.format.quantity(mock.items[slotsShown].count), slot.Name)
		end
	end
	expectEqual(slotsShown, #mock.items, "every item, with its count")
	local rowsShown, badges = 0, 0
	for _, row in area.Party.Rows:GetChildren() do
		if row:IsA("ImageLabel") and row.Visible then
			rowsShown += 1
			if row.Content.LevelUp.Visible then badges += 1 end
		end
	end
	expectEqual(rowsShown, 4, "one row per player")
	expectEqual(badges, 2, "LEVEL UP! where the mock says so")
	expectEqual(area.Party.Rows.Row1.Content.Gained.Text, Strings.format.gained(mock.members[1].expGained))
	expect(not area.SkipHint.Visible, "no more skipping once it's all shown")
	expectEqual(area.Returning.Text, Strings.format.returningIn(6), "the countdown runs on the server clock")
	checkSafeZones(Layout, resultsGui, "Four / Victory")

	-- A tap anywhere skips the count.
	handle.setState(mockStateIndex(ui, "One", "Victory"))
	expect(exp.Text ~= Strings.format.gained(mock.exp), "counting again")
	sim:click(client, area.TapToSkip)
	expectEqual(exp.Text, Strings.format.gained(MockData.reward("One").exp), "skipped straight to the total")
	expectEqual(gold.Text, Strings.format.gained(MockData.reward("One").currency))
	rowsShown = 0
	for _, row in area.Party.Rows:GetChildren() do
		if row:IsA("ImageLabel") and row.Visible then rowsShown += 1 end
	end
	expectEqual(rowsShown, 1, "one player, one row")

	-- DEFEAT: the same layout, live text, nothing gained.
	handle.setState(mockStateIndex(ui, "Two", "Defeat"))
	expectEqual(area.Title.Text.Text, Strings.Defeat)
	sim:run(0.3)
	expectEqual(exp.Text, Strings.format.gained(0))
	expectEqual(gold.Text, Strings.format.gained(0))
	slotsShown, badges, rowsShown = 0, 0, 0
	for _, slot in area.Tallies.Items.Content.Slots:GetChildren() do
		if slot:IsA("ImageLabel") and slot.Visible then slotsShown += 1 end
	end
	for _, row in area.Party.Rows:GetChildren() do
		if row:IsA("ImageLabel") and row.Visible then
			rowsShown += 1
			if row.Content.LevelUp.Visible then badges += 1 end
		end
	end
	expectEqual(slotsShown, 0, "no items on a loss")
	expectEqual(badges, 0, "no level-ups on a loss")
	expectEqual(rowsShown, 2, "both players listed")
	checkSafeZones(Layout, resultsGui, "Two / Defeat")

	handle.setState(mockStateIndex(ui, "Two", "MyTurn"))
	expect(not resultsGui.Enabled, "closed again once the fight is on")
	handle.close()
	assertClean(sim, observer)
end)

print("\nEvery summon variant, through the UI")

local function setLineup(sim, lineup)
	local config = sim.server.require(sim.server.dm:GetService("ReplicatedStorage").Combat.CombatConfig)
	config.PartySummons = lineup
end

test("each new party comp plays full battles through the UI (taunt, guard, party buff, heals)", function()
	local lineups = {
		{ "TungTungElder", "TungTungGroveKeeper" },
		{ "TungTungSapling", "TungTungGroveKeeper" },
		{ "TungTungElder", "TungTungSapling" },
		{ "TungTungSahur", "TungTungGroveKeeper" },
	}
	local totals = { heals = 0, buffs = 0, misses = 0, crits = 0, inflicted = 0, attacks = 0, guards = 0, guardsAttacked = 0 }
	local sawLostTurn = false
	for index, lineup in lineups do
		local sim, observer = newWorld(4000 + index)
		setLineup(sim, lineup)
		local random = { engage = "random", thinkMin = 0.3, thinkMax = 3, engageDelay = 0.5, policy = "random" }
		local greedy = { engage = "random", thinkMin = 0.3, thinkMax = 3, engageDelay = 0.5, policy = "greedy" }
		join(sim, observer, -1, "P1", random)
		join(sim, observer, -2, "P2", greedy)
		expect(sim:runUntil(function()
			return observer.battlesFinished >= 3 and backInOverworld(observer)
		end, 3600), `{table.concat(lineup, " + ")}: battles never finished`)
		assertClean(sim, observer)
		-- The summons really were these variants.
		for _, p in observer.results do
			expect(p.winner ~= nil)
		end
		for key in totals do
			totals[key] += observer[key] or 0
		end
		sawLostTurn = sawLostTurn or observer.sawLostTurn == true
	end

	-- Solo: one player runs both the tank and the healer.
	local sim, observer = newWorld(4100)
	setLineup(sim, { "TungTungElder", "TungTungGroveKeeper" })
	join(sim, observer, -1, "Solo", { engage = "random", thinkMin = 0.3, thinkMax = 2, engageDelay = 0.5, policy = "random" })
	expect(sim:runUntil(function()
		return observer.battlesFinished >= 2 and backInOverworld(observer)
	end, 3600), "solo tank + healer never finished")
	assertClean(sim, observer)

	print(
		`       UI-driven: {totals.attacks} attacks ({totals.misses} missed, {totals.crits} crits, {totals.inflicted} dazes), {totals.heals} heals, {totals.buffs} statuses applied`
	)
	print(
		`       Guard: used {totals.guards} times, attacked while guarding {totals.guardsAttacked} times (Mana unchanged every time)`
	)
	expect(totals.heals > 0 and totals.buffs > 0, "heals and buffs were used through the UI")
	expect(totals.guards > 0 and totals.guardsAttacked > 0, "Guard was used through the UI and attacked")
	expect(totals.misses > 0 and totals.crits > 0 and totals.inflicted > 0, "misses, crits and dazes all happened")
	expect(sawLostTurn, "some summon lost a turn to Dazed")
end)

print("\nMany battles (invariants + balance)")

test("hundreds of seeded two-player battles stay consistent", function()
	local seeds = if QUICK then 40 else 300
	local stats = {
		random = { wins = 0, total = 0, rounds = 0, duration = 0 },
		greedy = { wins = 0, total = 0, rounds = 0, duration = 0 },
	}
	local firstActorSides = { Party = 0, Enemy = 0 } -- in even starts
	local openings = { Party = 0, None = 0, Enemy = 0 }
	local ttsBeatsBothSaplings = 0
	for seed = 1, seeds do
		local policy = if seed % 2 == 0 then "greedy" else "random"
		local sim, observer = newWorld(10000 + seed)
		local options = { engage = "random", thinkMin = 0.3, thinkMax = 3, engageDelay = 0.5, policy = policy }
		join(sim, observer, -1, "P1", options)
		join(sim, observer, -2, "P2", options)
		expect(sim:runUntil(function()
			return observer.battlesFinished >= 1
		end, 900), `seed {seed}: battle never finished`)
		assertClean(sim, observer)
		local result = observer.results[1]
		local s = stats[policy]
		s.total += 1
		s.rounds += result.rounds
		s.duration += result.duration
		if result.winner == "Party" then
			s.wins += 1
		end
		local battleState = observer.last.battle
		local opening = battleState.opening or "None"
		openings[opening] += 1
		if opening == "None" then
			firstActorSides[observer.firstActors[1].side] += 1
		end
		-- How often does a Tung Tung (Agility 10) out-roll BOTH Saplings (Agility 12)?
		local bestTts, bestSapling = -1, -1
		for _, p in battleState.participants do
			if p.side == "Party" then
				bestTts = math.max(bestTts, p.initiative.total)
			else
				bestSapling = math.max(bestSapling, p.initiative.total)
			end
		end
		if bestTts >= bestSapling then
			ttsBeatsBothSaplings += 1
		end
	end
	for policy, s in stats do
		print(string.format("       %-6s bots: party won %d/%d (%.0f%%), avg %.1f rounds, avg %.0fs per battle",
			policy, s.wins, s.total, 100 * s.wins / math.max(1, s.total), s.rounds / math.max(1, s.total), s.duration / math.max(1, s.total)))
	end
	print(string.format("       openings: party struck first %d, even %d, enemies struck first %d", openings.Party, openings.None, openings.Enemy))
	print(string.format("       in even starts the party went first in %d/%d; a Tung Tung out-rolled both Saplings in %d/%d",
		firstActorSides.Party, openings.None, ttsBeatsBothSaplings, seeds))
	expect(openings.Party > 0 and openings.None > 0 and openings.Enemy > 0, "bots touched enemies every way")
	expect(firstActorSides.Party > 0 and firstActorSides.Enemy > 0, "initiative should vary between battles")
end)

print("\nCombat overhaul C1: camera and flow")

local function cameraOf(client)
	return client.env.dm:GetService("Workspace").CurrentCamera
end

local function stageOf(client)
	return client.env.dm:GetService("Workspace"):FindFirstChild("BattleStage")
end

local function myInputTurn(userId)
	return function(b)
		local actor = currentActor(b)
		return b.phase == "input" and actor ~= nil and actor.ownerUserId == userId
	end
end

local function enemyInputTurn(b)
	local actor = currentActor(b)
	return b.phase == "input" and actor ~= nil and actor.side == "Enemy"
end

-- A slow bot: it takes two to three seconds over each move, so the camera can be measured holding.
local SLOW = { thinkMin = 2, thinkMax = 3, policy = "attack" }

test("C1: the camera sweeps the stage under the start swirl, sits over the acting party member's shoulder, faces an acting enemy, and lets go afterwards", function()
	local sim, observer = newWorld(901)
	local client = join(sim, observer, -1, "Ann", SLOW)
	local camera = cameraOf(client)
	sim:run(1)
	expect(camera.CameraType.Name ~= "Scriptable", "the player's own camera in the overworld")
	touch(sim, observer, -1, "SouthLookout", "side")
	sim:run(0.25)
	expectEqual(camera.CameraType.Name, "Scriptable")
	local transition = client.playerGui:FindFirstChild("BattleTransition")
	expect(transition ~= nil and transition:FindFirstChild("Stripes") ~= nil, "the wipe covers the start")
	expect(client.playerGui:GetAttribute("StageBusy") == true, "the stage is busy for the start")
	local a = camera.CFrame.Position
	sim:run(1)
	local b = camera.CFrame.Position
	expect((a - b).Magnitude > 3, `the sweep moves the camera during the reveal ({(a - b).Magnitude})`)
	local stage = stageOf(client)
	local e1, e2 = stage.E1.Spot.CFrame.Position, stage.E2.Spot.CFrame.Position
	expect((e1 - e2).Magnitude >= 14, `the enemies stand far enough apart for their plates ({(e1 - e2).Magnitude})`)
	expect(not stage.P1.Spot.Nameplate.Enabled and not stage.E1.Spot.Nameplate.Enabled, "the new HUD turns every stage plate off")

	-- Ann's turn: over her character's shoulder, looking at the enemies.
	runToPhase(sim, observer, myInputTurn(-1), "Ann's turn")
	sim:run(0.8) -- the whip-pan settles; the bot is still thinking
	expect(client.playerGui:FindFirstChild("BattleTransition") == nil, "the swirl is gone")
	local battle = observer.last.battle
	local actor = currentActor(battle)
	local root = stage[actor.id].Character.HumanoidRootPart.CFrame
	local cam = camera.CFrame
	local behind = (cam.Position - root.Position):Dot(root.LookVector)
	expect(behind < -3 and behind > -12, `the camera stands behind the acting character ({behind})`)
	expect(cam.Position.Y > root.Position.Y, "and above its hips")
	local enemyAt = summonRoot(stage.E1.Summon).CFrame.Position
	expect(cam.LookVector:Dot((enemyAt - cam.Position).Unit) > 0.75, "looking toward the enemies")
	expect(math.abs(camera.FieldOfView - 60) < 2, `a 60 degree field of view ({camera.FieldOfView})`)
	-- A subtle sway while it holds.
	local held = camera.CFrame.Position
	sim:run(0.4)
	local drift = (camera.CFrame.Position - held).Magnitude
	expect(drift > 0.001 and drift < 0.6, `a subtle sway while holding ({drift})`)

	-- An enemy's turn: an offset frontal shot, from the party's side.
	runToPhase(sim, observer, enemyInputTurn, "an enemy's turn")
	sim:run(0.8)
	battle = observer.last.battle
	actor = currentActor(battle)
	local enemy = summonRoot(stage[actor.id].Summon).CFrame
	cam = camera.CFrame
	expect((cam.Position - enemy.Position):Dot(enemy.LookVector) > 3, "in front of the acting enemy, on the party's side")
	expect(cam.LookVector:Dot((enemy.Position - cam.Position).Unit) > 0.85, "looking at it")

	-- While a blow plays, the presentation holds its popups; afterwards it holds nothing.
	local before = lastSequence(client)
	expect(sim:runUntil(function()
		return lastSequence(client) > before
	end, 60), "no action played")
	sim:run(0.2)
	expect((client.playerGui:GetAttribute("StageOwned") or 0) > 0, "the presentation owns the beat's popups")

	-- Afterwards: the camera is the player's again and nothing of the fight is left.
	expect(sim:runUntil(function()
		return observer.battlesFinished >= 1 and backInOverworld(observer)
	end, 900), "the fight never ended")
	sim:run(0.5)
	expect(camera.CameraType.Name ~= "Scriptable", "the camera is given back")
	expect(stageOf(client) == nil, "no stage")
	expect(client.playerGui:FindFirstChild("BattleTransition") == nil, "no transition left")
	expectEqual(client.playerGui:GetAttribute("StageOwned"), 0, "the presentation holds nothing")
	expect(client.playerGui:GetAttribute("StageBusy") ~= true, "and isn't busy")
	expect(observer.pacingChecks > 5, "the observer checked the pacing of every turn")
	assertClean(sim, observer)
end)

test("C1: reduced motion: a plain fade instead of the swirl, no sway while holding; the camera still cuts and moves", function()
	local sim, observer = newWorld(902)
	local client = join(sim, observer, -1, "Ann", SLOW)
	localPlayer(client):SetAttribute("ReducedMotion", true)
	local Theme = client.env.require(client.env.dm:GetService("ReplicatedStorage").UI.Theme)
	expect(Theme.Motion.reduced == true, "Theme follows the setting")
	sim:run(1)
	touch(sim, observer, -1, "SouthLookout", "side")
	sim:run(0.1)
	local transition = client.playerGui:FindFirstChild("BattleTransition")
	expect(transition ~= nil and transition:FindFirstChild("Cover") ~= nil and transition:FindFirstChild("Stripes") == nil, "a fade, no wipe")
	runToPhase(sim, observer, myInputTurn(-1), "Ann's turn")
	sim:run(0.8)
	local camera = cameraOf(client)
	local stage = stageOf(client)
	local root = stage[currentActor(observer.last.battle).id].Character.HumanoidRootPart.CFrame
	expect((camera.CFrame.Position - root.Position):Dot(root.LookVector) < -3, "still over the shoulder")
	local held = camera.CFrame.Position
	sim:run(0.4)
	expect((camera.CFrame.Position - held).Magnitude < 1e-4, `no sway with reduced motion ({(camera.CFrame.Position - held).Magnitude})`)
	localPlayer(client):SetAttribute("ReducedMotion", nil)
	expect(Theme.Motion.reduced == false, "back to normal when the override is cleared")
	expect(sim:runUntil(function()
		return observer.battlesFinished >= 1 and backInOverworld(observer)
	end, 900), "the fight never ended")
	assertClean(sim, observer)
end)

test("C1: Pacing: the pause after an action grows with what the stage has to show; a passed turn waits only the base", function()
	local sim = Sim.new(PLACE, { seed = 7 })
	local rs = sim.server.dm:GetService("ReplicatedStorage")
	local Pacing = sim.server.require(rs.Combat.Pacing)
	local Abilities = sim.server.require(rs.Combat.Abilities)
	local Config = sim.server.require(rs.Combat.CombatConfig)
	local function result(hit, critical, knockedOut)
		return { targetId = "E1", hit = hit, critical = critical, damage = if hit then 5 else 0, healed = 0, knockedOut = knockedOut, cleansed = false }
	end
	local base = Pacing.resolveSeconds(nil, nil, false)
	expectEqual(base, Config.ResolvePauseSeconds, "a passed or lost turn")
	local attack = Pacing.resolveSeconds(Abilities.Attack, { result(true, false, false) }, false)
	expect(attack > base, "an attack takes longer than nothing")
	local strike = Pacing.resolveSeconds(Abilities.Strike, { result(true, false, false) }, true)
	expectNear(strike, attack + Config.ResolveExtraSeconds.Summon, "a summon's attack adds the summon beat")
	expect(Pacing.resolveSeconds(Abilities.Strike, { result(true, true, true) }, true) > strike, "a knockout on a critical holds longer")
	expect(Pacing.resolveSeconds(Abilities.Attack, { result(false, false, false) }, false) < attack, "a miss is quicker")
	expect(Pacing.resolveSeconds(Abilities.GaleClap, { result(true, false, false), result(true, false, false) }, true) > strike, "two targets take longer than one")
	expect(Pacing.resolveSeconds(Abilities.Guard, nil, false) >= Config.MinResolveSeconds, "never under the minimum")
	expect(Pacing.resolveSeconds(Abilities.SapMend, { result(true, false, false) }, true) > base, "a cast has its beat")
	expectNear(
		Pacing.resolveSeconds(Abilities.Strike, { result(true, false, false) }, false, "Enemy"),
		Pacing.resolveSeconds(Abilities.Strike, { result(true, false, false) }, false, "Party") + Config.EnemyHoldSeconds + Config.EnemyReturnSeconds,
		"an enemy's action holds on its outcome and eases back"
	)
	expect(Pacing.isSummoned("Party", { "Strike" }, "Strike"), "a party member's own ability brings its summon out")
	expect(not Pacing.isSummoned("Party", { "Strike" }, "Attack"), "its character's Attack doesn't")
	expect(not Pacing.isSummoned("Enemy", { "Strike" }, "Strike"), "enemies have no summon to bring out")
end)

test("C1: the ring waits for the stage to finish its beat, but never longer than RING_WAIT_CAP", function()
	local sim, observer = newWorld(903)
	local client = joinHud(sim, observer, -1, "Ann", PHONE)
	local ui = m2Modules(client)
	local CombatHUD = client.env.require(client.env.dm:GetService("StarterPlayer").StarterPlayerScripts.UI.Screens.CombatHUD)
	local hud = CombatHUD.new(client.playerGui, ui.MockData.LOCAL_USER, {
		onAction = function() end,
		onTargetChanged = function() end,
	}, { namePrefix = "Gate" })
	local snapshot = ui.MockData.snapshot("Two", "MyTurn", sim.now)
	local ring = client.playerGui.GateCombatHUD.SafeArea.Ring

	hud:setStageBusy(true)
	hud:render(snapshot)
	expect(not ring.Visible, "held while the stage is busy")
	sim:run(0.3)
	hud:tick(sim.now)
	expect(not ring.Visible, "still held before the cap")
	sim:run(0.4)
	hud:tick(sim.now)
	expect(ring.Visible, "shown once the cap has passed, busy or not")

	snapshot.battle.turnNumber += 1 -- the next turn: held again, then released the moment the stage is free
	hud:setStageBusy(true)
	hud:render(snapshot)
	expect(not ring.Visible, "held on the new turn")
	hud:setStageBusy(false)
	hud:tick(sim.now)
	expect(ring.Visible, "released on the next tick once the stage is done")

	snapshot.battle.turnNumber += 1 -- a stage that isn't busy never holds the ring
	hud:render(snapshot)
	expect(ring.Visible, "straight away when the stage is idle")
	hud:destroy()
	assertClean(sim, observer)
end)

-- Plays a fight at `size` and checks the enemy plates against the HUD's box under the battle
-- camera, and that a long attack clip is compressed to its beat.
local function checkPlatesAt(seed, size, label)
	local sim, observer = newWorld(seed)
	local client = joinHud(sim, observer, -1, "Ann", size)
	local ui = m2Modules(client)
	local Layout = ui.Layout
	local Summons = client.env.require(client.env.dm:GetService("ReplicatedStorage").Combat.Summons)
	local attackClip = Summons.WildSapling.art.animations.attack
	sim.clipLengths[attackClip] = 2.4 -- a slow swing: longer than any beat's budget
	local bot = Bot.new(sim, client, SLOW, observer)
	sim:run(1)
	touch(sim, observer, -1, "NorthLookout", "side") -- two Wild Saplings
	local camera = cameraOf(client)
	local plates = client.playerGui.CombatHUDEnemies

	-- The HUD's box for the plates, as CombatHUD lays it out: the GUI inset, then the regions in
	-- design pixels scaled up to the screen.
	local scale = Layout.scaleFor(size)
	local virtual = roblox.Vector2.new(math.round(size.X / scale), math.round(size.Y / scale))
	local regions = Layout.regions(virtual)
	local inset = client.env.getService("GuiService"):GetGuiInset()
	local gap = 8
	local statusBottom = regions.topCenter.y + (36 + 10) + 4 + 74
	local box = {
		left = inset.X + (regions.left.x + regions.left.w + gap) * scale,
		top = inset.Y + (statusBottom + gap) * scale,
		right = inset.X + (regions.right.x - gap) * scale,
		bottom = inset.Y + (regions.center.y + regions.center.h - 48 - gap) * scale,
	}
	local plateW, plateH = 190 * scale, 60 * scale
	local function checkPlates(shot)
		local rects = {}
		for _, gui in plates:GetChildren() do
			if gui:IsA("BillboardGui") and gui.Enabled and gui.Root.Visible then
				local spot = gui.Adornee
				local center = spot.CFrame.Position + gui.StudsOffsetWorldSpace
				local screen = Sim.worldToViewportPoint(camera.CFrame, camera.FieldOfView, size, center)
				local rect = Layout.rect(screen.X - plateW / 2, screen.Y - plateH / 2, plateW, plateH)
				-- (12 design px of slack: plates are placed again only once the camera has moved 0.3
				-- studs or turned a degree, which is about that much on screen.)
				local slack = 12 * scale
				expect(
					rect.x >= box.left - slack and rect.x + rect.w <= box.right + slack and rect.y >= box.top - slack and rect.y + rect.h <= box.bottom + slack,
					`{label}, {shot}: {gui.Name} inside the HUD's box ({math.round(rect.x)}, {math.round(rect.y)}; box {math.round(box.left)}-{math.round(box.right)} x {math.round(box.top)}-{math.round(box.bottom)})`
				)
				table.insert(rects, rect)
			end
		end
		expect(#rects >= 1, `{label}, {shot}: at least one plate in frame`)
		if #rects == 2 then
			expect(not Layout.intersects(rects[1], rects[2]), `{label}, {shot}: the two plates don't overlap ({math.round(rects[1].x)},{math.round(rects[1].y)} and {math.round(rects[2].x)},{math.round(rects[2].y)})`)
		end
		return #rects
	end

	runToPhase(sim, observer, myInputTurn(-1), "Ann's turn")
	sim:run(0.8)
	expectEqual(checkPlates("over the shoulder"), 2, `{label}: both enemies in frame from behind the party`)
	runToPhase(sim, observer, enemyInputTurn, "an enemy's turn")
	sim:run(0.8)
	checkPlates("enemy frontal")

	-- The sapling's 2.4 s swing is played faster than real time, so it fits the beat.
	expect(sim:runUntil(function()
		for _, entry in sim.animationLog do
			if entry.env == client.env.name and entry.id == attackClip and entry.event == "Play" and entry.speed > 1 then
				return true
			end
		end
		return false
	end, 240), `{label}: a compressed attack clip never played`)
	expect(bot.turnsTaken > 0, `{label}: the bot played`)
	assertClean(sim, observer)
end

test("C1: under the battle camera the enemy plates keep inside the HUD's box and clear of each other, and clips are compressed to the beat (phone and desktop)", function()
	checkPlatesAt(904, PHONE, "phone")
	checkPlatesAt(905, roblox.Vector2.new(1920, 1080), "desktop")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if passed + failed == 0 then
	quit(`No test names contain "{ONLY}".`)
elseif failed > 0 then
	process.exit(1)
end
