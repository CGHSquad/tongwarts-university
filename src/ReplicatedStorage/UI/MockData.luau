--!strict
--[[
	MockData — sample battles and rewards for the preview harness and the layout tests (handoff
	section 11, M0 report R12 amendment).

	Snapshots here have exactly the shape the server sends (BattleTypes), so screens are built against
	the real contract and switch to live data without changes. Party sizes: one member, two members
	owned by one solo player, two members owned by two players, and four members (MaxPartySize is
	2 today; the four-member layout is covered before the size is raised). Every number and name is
	sample data (handoff rule 11).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BattleTypes = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("BattleTypes"))
local UITypes = require(script.Parent:WaitForChild("UITypes"))

type ParticipantState = BattleTypes.ParticipantState
type BattleState = BattleTypes.BattleState
type Snapshot = BattleTypes.Snapshot

export type PartySize = "One" | "TwoSolo" | "Two" | "Four"
export type Scenario =
	"Setup" -- the initiative reveal
	| "MyTurn" -- the local player's turn, with one ability it can't afford
	| "AllyTurn" -- another player's turn
	| "EnemyTurn"
	| "Hit" -- resolving: a plain hit
	| "Crit" -- resolving: a critical hit that knocks an enemy out
	| "Miss"
	| "Heal"
	| "KnockedOut" -- a party member is down (HP 0), it's my turn with the other one
	| "Victory"
	| "Defeat"

-- The local player in every mock is user -1 (the tests' convention for bots).
local LOCAL_USER = -1

type MemberSpec = { summonId: string, name: string, userId: number, userName: string, abilities: { string } }

local MEMBERS: { [PartySize]: { MemberSpec } } = {
	One = {
		{ summonId = "TungTungSahur", name = "Tung Tung Sahur", userId = LOCAL_USER, userName = "Kai", abilities = { "Strike", "GaleClap" } },
	},
	TwoSolo = {
		{ summonId = "TungTungSahur", name = "Tung Tung Sahur A", userId = LOCAL_USER, userName = "Kai", abilities = { "Strike", "GaleClap" } },
		{ summonId = "TungTungGroveKeeper", name = "Tung Tung Grove-Keeper", userId = LOCAL_USER, userName = "Kai", abilities = { "Strike", "Tailwind", "SapMend" } },
	},
	Two = {
		{ summonId = "TungTungSahur", name = "Tung Tung Sahur", userId = LOCAL_USER, userName = "Kai", abilities = { "Strike", "GaleClap" } },
		{ summonId = "TungTungElder", name = "Tung Tung Elder", userId = -2, userName = "Ember", abilities = { "Strike", "KnockOnWood", "Windbreak" } },
	},
	Four = {
		{ summonId = "TungTungSahur", name = "Tung Tung Sahur", userId = LOCAL_USER, userName = "Kai", abilities = { "Strike", "GaleClap" } },
		{ summonId = "TungTungElder", name = "Tung Tung Elder", userId = -2, userName = "Ember", abilities = { "Strike", "KnockOnWood", "Windbreak" } },
		{ summonId = "TungTungSapling", name = "Tung Tung Sapling", userId = -3, userName = "Fern", abilities = { "Strike", "SplinterSlam" } },
		{ summonId = "TungTungGroveKeeper", name = "A very long summon name here", userId = -4, userName = "Nyx", abilities = { "Strike", "Tailwind", "SapMend" } },
	},
}

local ENEMIES: { { summonId: string, name: string } } = {
	{ summonId = "WildSapling", name = "Wild Sapling A" },
	{ summonId = "WildSapling", name = "Wild Sapling B" },
}

local function participant(id: string, side: BattleTypes.Side, slot: number, name: string, summonId: string, abilities: { string }, userId: number?, userName: string?): ParticipantState
	return {
		id = id,
		side = side,
		slot = slot,
		name = name,
		summonId = summonId,
		ownerUserId = userId,
		ownerName = userName,
		hp = 100,
		maxHp = 100,
		mana = 20,
		maxMana = 20,
		status = "Active",
		statuses = {},
		abilities = abilities,
		initiative = nil,
	}
end

local function buildParticipants(size: PartySize): { ParticipantState }
	local list = {}
	for slot, spec in MEMBERS[size] do
		table.insert(list, participant(`P{slot}`, "Party", slot, spec.name, spec.summonId, spec.abilities, spec.userId, spec.userName))
	end
	for slot, enemy in ENEMIES do
		local p = participant(`E{slot}`, "Enemy", slot, enemy.name, enemy.summonId, { "Strike", "GaleClap" })
		p.hp, p.maxHp, p.mana, p.maxMana = 90, 90, 18, 18
		table.insert(list, p)
	end
	return list
end

-- Party first, interleaved with enemies, like a real roll could land.
local function queueFor(participants: { ParticipantState }): { string }
	local party, enemies = {}, {}
	for _, p in participants do
		table.insert(if p.side == "Party" then party else enemies, p.id)
	end
	local queue = {}
	for index = 1, math.max(#party, #enemies) do
		if party[index] then
			table.insert(queue, party[index])
		end
		if enemies[index] then
			table.insert(queue, enemies[index])
		end
	end
	return queue
end

local function overworld(participants: { ParticipantState }): BattleTypes.OverworldState
	local players, seen = {}, {}
	for _, p in participants do
		local userId = p.ownerUserId
		if userId and not seen[userId] then
			seen[userId] = true
			table.insert(players, { userId = userId, name = p.ownerName or "Player" })
		end
	end
	return { players = players, maxPartySize = 2 }
end

local PARTY_SIZES: { PartySize } = { "One", "TwoSolo", "Two", "Four" }
local SCENARIOS: { Scenario } = { "Setup", "MyTurn", "AllyTurn", "EnemyTurn", "Hit", "Crit", "Miss", "Heal", "KnockedOut", "Victory", "Defeat" }

local MockData = {}

MockData.LOCAL_USER = LOCAL_USER
MockData.partySizes = PARTY_SIZES
MockData.scenarios = SCENARIOS

-- A snapshot for one party size in one scenario. `now` is the server clock for deadlines.
function MockData.snapshot(size: PartySize, scenario: Scenario, now: number?): Snapshot
	local clock = now or 1000
	local participants = buildParticipants(size)
	local byId: { [string]: ParticipantState } = {}
	for _, p in participants do
		byId[p.id] = p
	end
	local queue = queueFor(participants)
	local battle: BattleState = {
		battleId = 7,
		phase = "input",
		round = 1,
		turnNumber = 3,
		currentActorId = "P1",
		turnQueue = queue,
		opening = "Party",
		participants = participants,
		winner = nil,
		lastAction = nil,
		log = { "Wild Sapling B used Strike on Tung Tung Sahur for 15 damage." },
		turnDeadline = clock + 30,
		overworldReturnAt = nil,
		startedBy = "Kai",
	}

	-- Some wear and tear so bars aren't all full.
	byId.P1.hp = 82
	byId.P1.mana = 14
	byId.E1.hp = 53
	if byId.P2 then
		byId.P2.hp = 76
		byId.P2.statuses = { { id = "Guarded", turnsLeft = 2 } }
	end
	if byId.P3 then
		byId.P3.hp = 91
		byId.P3.mana = 15
	end
	if byId.P4 then
		byId.P4.hp = 68
		byId.P4.mana = 22
		byId.P4.maxMana = 25
		byId.P4.statuses = { { id = "Dazed", turnsLeft = 1 }, { id = "Tailwind", turnsLeft = 3 } }
	end

	if scenario == "Setup" then
		battle.phase = "setup"
		battle.round = 0
		battle.turnNumber = 0
		battle.currentActorId = nil
		battle.turnDeadline = nil
		for index, id in queue do
			local roll = 20 - index * 2
			byId[id].initiative = { roll = roll, bonus = 5, total = roll + 5 }
		end
	elseif scenario == "MyTurn" then
		byId.P1.mana = 5 -- Gale Clap (8) is unaffordable, Strike (2) isn't
	elseif scenario == "AllyTurn" then
		battle.currentActorId = if byId.P2 then "P2" else "P1"
		if size == "One" or size == "TwoSolo" then
			battle.currentActorId = "P1" -- a solo player has no ally; the state still exists for the cycle
		end
	elseif scenario == "EnemyTurn" then
		battle.currentActorId = "E1"
		battle.turnDeadline = nil
	elseif scenario == "Hit" or scenario == "Crit" or scenario == "Miss" or scenario == "Heal" then
		battle.phase = "resolve"
		battle.turnDeadline = nil
		if scenario == "Heal" and byId.P2 then
			battle.currentActorId = "P2"
			byId.P2.mana = 10
			battle.lastAction = {
				sequence = 12,
				actorId = "P2",
				abilityId = "SapMend",
				results = { { targetId = "P1", hit = true, critical = false, damage = 0, healed = 18, knockedOut = false, inflicted = nil, applied = nil, cleansed = true } },
			}
			battle.log = { "Tung Tung Grove-Keeper used Sap Mend on Tung Tung Sahur: healed 18." }
		else
			local crit = scenario == "Crit"
			local hit = scenario ~= "Miss"
			if crit then
				byId.E1.hp = 0
				byId.E1.status = "KnockedOut"
			elseif hit then
				byId.E1.statuses = { { id = "Dazed", turnsLeft = 2 } } -- the daze the log line reports
			end
			battle.lastAction = {
				sequence = 12,
				actorId = "P1",
				abilityId = "GaleClap",
				results = { { targetId = "E1", hit = hit, critical = crit, damage = if not hit then 0 elseif crit then 53 else 18, healed = 0, knockedOut = crit, inflicted = if hit and not crit then "Dazed" else nil, applied = nil, cleansed = false } },
			}
			battle.log = { if not hit then "Tung Tung Sahur used Gale Clap on Wild Sapling A, but missed." elseif crit then "Tung Tung Sahur used Gale Clap on Wild Sapling A: critical hit, 53 damage! Wild Sapling A is knocked out!" else "Tung Tung Sahur used Gale Clap on Wild Sapling A for 18 damage. Wild Sapling A is dazed!" }
		end
	elseif scenario == "KnockedOut" then
		local down = byId.P2 or byId.P1
		down.hp = 0
		down.status = "KnockedOut"
		down.statuses = {}
		if byId.P2 == nil then
			battle.currentActorId = "E1" -- the only member is down: the enemy acts
		end
	elseif scenario == "Victory" or scenario == "Defeat" then
		battle.phase = "reward"
		battle.turnDeadline = nil
		battle.currentActorId = nil
		battle.overworldReturnAt = clock + 8
		if scenario == "Victory" then
			battle.winner = "Party"
			for _, enemy in { byId.E1, byId.E2 } do
				enemy.hp = 0
				enemy.status = "KnockedOut"
			end
			battle.log = { "Wild Sapling B is knocked out! Victory!" }
		else
			battle.winner = "Enemy"
			for _, p in participants do
				if p.side == "Party" then
					p.hp = 0
					p.status = "KnockedOut"
				end
			end
			battle.log = { "Defeat... the party has fallen." }
		end
	end

	return { overworld = overworld(participants), battle = battle }
end

-- Every (size, scenario) pair, in the order the harness cycles them.
export type State = { name: string, size: PartySize, scenario: Scenario }
function MockData.states(): { State }
	local list: { State } = {}
	for _, size in PARTY_SIZES do
		for _, scenario in SCENARIOS do
			local state: State = { name = `{size} / {scenario}`, size = size :: PartySize, scenario = scenario :: Scenario }
			table.insert(list, state)
		end
	end
	return list
end

-- S6 rewards (R10, Q3): mock until the server has a reward payload.
function MockData.reward(size: PartySize): UITypes.RewardView
	local members = {}
	for index, spec in MEMBERS[size] do
		table.insert(members, {
			userId = spec.userId,
			name = spec.userName,
			level = 10,
			expGained = 420 - (index - 1) * 80,
			leveledUp = index <= 2,
			newLevel = 11,
		})
	end
	return {
		exp = 1240,
		currency = 860,
		items = {
			{ id = "PotionRed", name = "Red Potion", iconKey = "Item_PotionRed", count = 2 },
			{ id = "Herb", name = "Green Herb", iconKey = "Item_Herb", count = 1 },
			{ id = "RuneShard", name = "Rune Shard", iconKey = "Item_RuneShard", count = 1 },
		},
		members = members,
	}
end

-- Affinity rows (R8, Q4): empty for real; a sample set for the harness only.
local NO_AFFINITIES: { UITypes.AffinityEntry } = {}
local AFFINITIES_SAMPLE: { UITypes.AffinityEntry } = {
	{ elementId = "Strike", iconKey = "Icon_Physical", state = "Neutral" },
	{ elementId = "Wind", iconKey = "Icon_Wind", state = "Resist" },
	{ elementId = "Fire", iconKey = "Icon_Fire", state = "Weak" },
	{ elementId = "Ice", iconKey = "Icon_Ice", state = "Unknown" },
}

local STATS: { UITypes.StatEntry } = {
	{ id = "Strength", value = 12, max = 70 },
	{ id = "Magic", value = 10, max = 70 },
	{ id = "Endurance", value = 12, max = 70 },
	{ id = "Agility", value = 10, max = 70 },
	{ id = "Luck", value = 10, max = 70 },
}
MockData.affinities = NO_AFFINITIES
MockData.affinitiesSample = AFFINITIES_SAMPLE
MockData.stats = STATS

return MockData
