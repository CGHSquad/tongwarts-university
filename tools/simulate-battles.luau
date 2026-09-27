--[[
	simulate-battles — plays thousands of battles with the real combat rules (BattleSession and
	EnemyAI, loaded straight from src/) to compare party compositions and see what each role does.

	Run from the repo root (Lune comes with `rokit install`):
		lune run tools/simulate-battles              -- 2000 battles per party and play style
		lune run tools/simulate-battles 10000 7      -- battles per party, random seed

	Two play styles for the party:
		careless   picks any affordable ability and any legal target, like mashing buttons
		sensible   heals anyone under half Health, keeps its buffs up (only taunts while healthy),
		           otherwise hits the weakest enemy with its hardest-hitting attack
	Enemies use the game's own EnemyAI either way.

	The combat modules are plain Luau, so nothing Roblox runs here: a tiny stand-in for `game` and
	`script` maps src/ the way default.project.json does.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

-- Party compositions to compare (ids from Summons.luau). The enemies come from CombatConfig.
local PARTIES = {
	{ "TungTungSahur", "TungTungSahur" },
	{ "TungTungElder", "TungTungSapling" },
	{ "TungTungSapling", "TungTungGroveKeeper" },
	{ "TungTungElder", "TungTungGroveKeeper" },
	{ "TungTungSahur", "TungTungGroveKeeper" },
	{ "TungTungSapling", "TungTungSapling" },
}

local BATTLES = tonumber(process.args[1]) or 2000
local SEED = tonumber(process.args[2]) or 1

--[[ Loading the game's modules outside Roblox ]]

local SERVICE_FOLDERS = {
	ReplicatedStorage = "src/ReplicatedStorage",
	ServerScriptService = "src/ServerScriptService",
}

if not fs.isDir(SERVICE_FOLDERS.ReplicatedStorage) then
	error("Run this from the repo root: lune run tools/simulate-battles")
end

-- A stand-in Instance for each folder and module in src/, named the way Rojo names them, so
-- `script.Parent.X` and `ReplicatedStorage.Combat.X` work. Built up front because Lune's file
-- reads can't happen inside a metamethod.
local function buildNode(path: string, name: string, parent: any): any
	local node: any = { Name = name, Parent = parent, _path = path }
	if fs.isDir(path) then
		for _, entry in fs.readDir(path) do
			local childName = string.gsub(string.gsub(entry, "%.luau$", ""), "%.server$", "")
			childName = string.gsub(childName, "%.client$", "")
			node[childName] = buildNode(`{path}/{entry}`, childName, node)
		end
	else
		node._source = fs.readFile(path)
	end
	return node
end

local services = {}
for serviceName, folder in SERVICE_FOLDERS do
	services[serviceName] = buildNode(folder, serviceName, nil)
end

local fakeGame = {
	GetService = function(_, serviceName: string)
		return assert(services[serviceName], `The simulator doesn't provide {serviceName}`)
	end,
}

local loaded = {}
local function requireModule(node: any): any
	assert(type(node) == "table" and node._source, "require expects a module")
	if loaded[node._path] == nil then
		local chunk = luau.load(node._source, {
			debugName = node._path,
			environment = { game = fakeGame, script = node, require = requireModule },
		})
		loaded[node._path] = chunk()
	end
	return loaded[node._path]
end

local ReplicatedStorage = fakeGame:GetService("ReplicatedStorage")
local ServerScriptService = fakeGame:GetService("ServerScriptService")
local Abilities = requireModule(ReplicatedStorage.Combat.Abilities)
local CombatConfig = requireModule(ReplicatedStorage.Combat.CombatConfig)
local StatusEffects = requireModule(ReplicatedStorage.Combat.StatusEffects)
local Summons = requireModule(ReplicatedStorage.Combat.Summons)
local BattleSession = requireModule(ServerScriptService.Combat.BattleSession)
local EnemyAI = requireModule(ServerScriptService.Combat.EnemyAI)

-- Roblox's Random, backed by Lune's seeded math.random.
math.randomseed(SEED)
local rng = {
	NextInteger = function(_, min: number, max: number): number
		return math.random(min, max)
	end,
	NextNumber = function(_, min: number?, max: number?): number
		local roll = math.random()
		if min == nil or max == nil then
			return roll
		end
		return min + (max - min) * roll
	end,
}

--[[ Party play styles ]]

local function hasStatus(participant, statusId: string): boolean
	for _, status in participant.statuses do
		if status.id == statusId then
			return true
		end
	end
	return false
end

local function healthShare(participant): number
	return participant.hp / participant.maxHp
end

local function lowest(participants, measure)
	local best = participants[1]
	for _, participant in participants do
		if measure(participant) < measure(best) then
			best = participant
		end
	end
	return best
end

local function legalTargets(session, actor, ability)
	if ability.targets == "Enemy" then
		return session:getActiveOpponents(actor)
	elseif ability.targets == "Ally" then
		return session:getActiveAllies(actor)
	end
	return { actor } -- no pick needed
end

local function affordable(actor)
	local list = {}
	for _, abilityId in actor.abilities do
		local ability = Abilities[abilityId]
		if actor.mana >= ability.manaCost then
			table.insert(list, ability)
		end
	end
	return list
end

local function careless(session, actor): (string, string)
	local options = affordable(actor)
	local ability = options[math.random(#options)]
	local targets = legalTargets(session, actor, ability)
	return ability.id, targets[math.random(#targets)].id
end

local function sensible(session, actor): (string, string)
	local allies = session:getActiveAllies(actor)
	local options = affordable(actor)

	-- 1. Patch up anyone under half Health.
	for _, ability in options do
		if ability.kind == "Heal" then
			local hurt = lowest(allies, healthShare)
			if healthShare(hurt) < 0.5 then
				return ability.id, hurt.id
			end
		end
	end

	-- 2. Keep buffs up, but only taunt while healthy enough to take the hits.
	for _, ability in options do
		if ability.kind == "Status" then
			local targets = if ability.targets == "AllAllies" then allies else { actor }
			local missing = false
			for _, target in targets do
				missing = missing or not hasStatus(target, ability.status)
			end
			local safe = not StatusEffects[ability.status].drawsAttacks or healthShare(actor) >= 0.4
			if missing and safe then
				return ability.id, actor.id
			end
		end
	end

	-- 3. Otherwise, the hardest-hitting attack on the weakest enemy.
	local best, bestDamage = nil, -1
	for _, ability in options do
		if ability.kind == "Attack" then
			local damage = ability.power + actor.stats[ability.scalingStat] * ability.statRatio
			if damage > bestDamage then
				best, bestDamage = ability, damage
			end
		end
	end
	if best == nil then
		return careless(session, actor)
	end
	local target = lowest(session:getActiveOpponents(actor), function(enemy)
		return enemy.hp
	end)
	return best.id, target.id
end

--[[ Running battles ]]

local function newMemberStats()
	return { dealt = 0, taken = 0, healed = 0, targeted = 0, knockedOut = 0 }
end

local function newTally()
	return {
		battles = 0,
		wins = 0,
		rounds = 0,
		members = {}, -- [party slot] = stats for that summon
		enemyAttacks = 0,
		dice = {
			partyAttacks = 0,
			partyHits = 0,
			partyCrits = 0,
			enemyAttacks = 0,
			enemyHits = 0,
			ailmentsOnParty = 0,
			ailmentsOnEnemies = 0,
			turnsLostByParty = 0,
			turnsLostByEnemies = 0,
		},
	}
end

local function record(session, tally, action)
	local actor = session.byId[action.actorId]
	local ability = Abilities[action.abilityId]
	for _, result in action.results do
		local target = session.byId[result.targetId]
		if ability.kind == "Attack" then
			local fromParty = actor.side == "Party"
			local dice = tally.dice
			if fromParty then
				dice.partyAttacks += 1
				dice.partyHits += if result.hit then 1 else 0
				dice.partyCrits += if result.critical then 1 else 0
				tally.members[actor.slot].dealt += result.damage
			else
				dice.enemyAttacks += 1
				dice.enemyHits += if result.hit then 1 else 0
				tally.enemyAttacks += 1
				tally.members[target.slot].targeted += 1
				tally.members[target.slot].taken += result.damage
			end
			if result.inflicted and fromParty then
				dice.ailmentsOnEnemies += 1
			elseif result.inflicted then
				dice.ailmentsOnParty += 1
			end
		elseif ability.kind == "Heal" and actor.side == "Party" then
			tally.members[actor.slot].healed += result.healed
		end
	end
end

local function playBattle(party, style, tally)
	local roster = {}
	for index, summonId in party do
		table.insert(roster, { side = "Party", summonId = summonId, ownerUserId = index, ownerName = `Player{index}` })
		tally.members[index] = tally.members[index] or newMemberStats()
	end
	for _, summonId in CombatConfig.EnemySummons do
		table.insert(roster, { side = "Enemy", summonId = summonId })
	end

	local session = BattleSession.new(1, roster, rng)
	session:rollInitiative()
	local lastSequence = 0
	local turns = 0
	while session.phase ~= "reward" do
		turns += 1
		assert(turns < 1000, "a battle didn't end")
		local actor = session:beginNextTurn()
		if session.phase ~= "input" then
			-- An ailment cost it the turn.
			if actor.side == "Party" then
				tally.dice.turnsLostByParty += 1
			else
				tally.dice.turnsLostByEnemies += 1
			end
		elseif not session:canAffordAnyAbility(actor) then
			session:passTurn("NoMana")
		elseif actor.ownerUserId == nil then
			local abilityId, targetId = EnemyAI.chooseAction(
				actor,
				session:getActiveAllies(actor),
				session:getActiveOpponents(actor),
				rng
			)
			if abilityId and targetId then
				assert(session:performEnemyAction(abilityId, targetId))
			else
				session:passTurn("NoValidAction")
			end
		else
			local abilityId, targetId = style(session, actor)
			local ok, _, message = session:submitAction(actor.ownerUserId, abilityId, targetId)
			assert(ok, message)
		end

		local action = session.lastAction
		if action and action.sequence ~= lastSequence then
			lastSequence = action.sequence
			record(session, tally, action)
		end
	end

	tally.battles += 1
	tally.rounds += session.round
	if session.winner == "Party" then
		tally.wins += 1
	end
	for _, participant in session.participants do
		if participant.side == "Party" and participant.status == "KnockedOut" then
			tally.members[participant.slot].knockedOut += 1
		end
	end
end

--[[ Report ]]

local function shortName(summonId: string): string
	return (string.gsub(Summons[summonId].name, "^Tung Tung ", ""))
end

local function partyName(party): string
	local names = {}
	for _, summonId in party do
		table.insert(names, shortName(summonId))
	end
	return table.concat(names, " + ")
end

local function percent(part: number, whole: number): string
	return string.format("%3.0f%%", 100 * part / math.max(1, whole))
end

local enemyNames = {}
for _, summonId in CombatConfig.EnemySummons do
	table.insert(enemyNames, Summons[summonId].name)
end
print(`{BATTLES} battles per party and play style, seed {SEED}. Enemies: {table.concat(enemyNames, " + ")}.\n`)

local results = {}
for _, party in PARTIES do
	local entry = { party = party, careless = newTally(), sensible = newTally() }
	for _ = 1, BATTLES do
		playBattle(party, careless, entry.careless)
		playBattle(party, sensible, entry.sensible)
	end
	table.insert(results, entry)
end

print("Win rate                              careless   sensible   rounds (sensible)")
for _, entry in results do
	print(
		string.format(
			"  %-34s %8s   %8s   %6.1f",
			partyName(entry.party),
			percent(entry.careless.wins, entry.careless.battles),
			percent(entry.sensible.wins, entry.sensible.battles),
			entry.sensible.rounds / entry.sensible.battles
		)
	)
end

print("\nWho does what (sensible play, average per battle)")
print("  Party                              Member         Dealt   Taken   Healed   Enemy attacks at it   KO'd")
for _, entry in results do
	local tally = entry.sensible
	for slot, summonId in entry.party do
		local member = tally.members[slot]
		print(
			string.format(
				"  %-34s %-13s %6.1f  %6.1f   %6.1f   %19s   %4s",
				if slot == 1 then partyName(entry.party) else "",
				shortName(summonId),
				member.dealt / tally.battles,
				member.taken / tally.battles,
				member.healed / tally.battles,
				percent(member.targeted, tally.enemyAttacks),
				percent(member.knockedOut, tally.battles)
			)
		)
	end
end

print("\nDice (sensible play; ailments and lost turns are per battle)")
print("  Party                              Party hits  Party crits  Enemy hits  Dazed: party / enemies  Turns lost: party / enemies")
for _, entry in results do
	local dice = entry.sensible.dice
	local battles = entry.sensible.battles
	print(
		string.format(
			"  %-34s %10s  %11s  %10s  %13.2f / %-7.2f  %18.2f / %.2f",
			partyName(entry.party),
			percent(dice.partyHits, dice.partyAttacks),
			percent(dice.partyCrits, dice.partyHits),
			percent(dice.enemyHits, dice.enemyAttacks),
			dice.ailmentsOnParty / battles,
			dice.ailmentsOnEnemies / battles,
			dice.turnsLostByParty / battles,
			dice.turnsLostByEnemies / battles
		)
	)
end
