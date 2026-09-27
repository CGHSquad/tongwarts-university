--!strict
--[[
	EnemyAI — MVP enemy action selection (GDD Step 6): a weighted-choice table per enemy type, read
	from that summon's `brain` in Summons. Full AI trees are explicitly a post-MVP investment.

	It only chooses. BattleSession still validates the choice exactly like a player's action.
	Taunts are the one hard rule: while an opponent is taunting, attacks have to go to it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Abilities = require(ReplicatedStorage.Combat.Abilities)
local Summons = require(ReplicatedStorage.Combat.Summons)
local BattleSession = require(script.Parent.BattleSession)

type Participant = BattleSession.Participant

-- For a summon with no brain: any ability that would help, any target.
local DEFAULT_BRAIN: Summons.EnemyBrain = {
	abilityWeights = {},
	targetWeights = { LowestHP = 1, Random = 1 },
}

local EnemyAI = {}

-- Picks one value with probability proportional to its weight. Weights are whole numbers;
-- zero or negative means "never". Returns nil when nothing has any weight.
local function pickWeighted<T>(rng: Random, options: { { value: T, weight: number } }): T?
	local total = 0
	for _, option in options do
		total += math.max(0, math.floor(option.weight))
	end
	if total <= 0 then
		return nil
	end

	local roll = rng:NextInteger(1, total)
	for _, option in options do
		roll -= math.max(0, math.floor(option.weight))
		if roll <= 0 then
			return option.value
		end
	end
	return nil
end

local function hasStatus(participant: Participant, statusId: string): boolean
	for _, status in participant.statuses do
		if status.id == statusId then
			return true
		end
	end
	return false
end

-- Would this ability do anything right now? No healing the unhurt, no re-casting a buff that's up.
local function isUseful(
	ability: Abilities.Ability,
	actor: Participant,
	allies: { Participant },
	opponents: { Participant }
): boolean
	if ability.kind == "Attack" then
		return #opponents > 0
	elseif ability.kind == "Heal" then
		for _, ally in allies do
			if ally.hp < ally.maxHp then
				return true
			end
		end
		return false
	end
	local targets: { Participant } = if ability.targets == "AllAllies" then allies else { actor }
	for _, target in targets do
		if not hasStatus(target, ability.status) then
			return true
		end
	end
	return false
end

local function mostHurt(participants: { Participant }): Participant
	local best = participants[1]
	for _, participant in participants do
		if participant.hp / participant.maxHp < best.hp / best.maxHp then
			best = participant
		end
	end
	return best
end

-- Chooses an ability and a target for `actor`. `allies` includes the actor itself.
-- Returns nil if it has nothing useful it can afford.
function EnemyAI.chooseAction(
	actor: Participant,
	allies: { Participant },
	opponents: { Participant },
	rng: Random
): (string?, string?)
	local summon = Summons[actor.summonId]
	local brain = if summon ~= nil and summon.brain ~= nil then summon.brain else DEFAULT_BRAIN

	-- 1. An ability it can afford that would do something, by weight. If every candidate has
	--    weight 0, fall back to the first one rather than skipping the turn.
	local options: { { value: string, weight: number } } = {}
	for _, abilityId in actor.abilities do
		local ability = Abilities[abilityId]
		if ability ~= nil and actor.mana >= ability.manaCost and isUseful(ability, actor, allies, opponents) then
			table.insert(options, { value = abilityId, weight = brain.abilityWeights[abilityId] or 0 })
		end
	end
	if #options == 0 then
		return nil, nil
	end
	local abilityId = pickWeighted(rng, options) or options[1].value
	local ability = Abilities[abilityId]

	-- 2. Its target. Abilities with no pick just name the actor.
	if ability.targets == "Self" or ability.targets == "AllAllies" then
		return abilityId, actor.id
	elseif ability.targets == "Ally" then
		return abilityId, mostHurt(allies).id
	end

	-- Attacks: taunting opponents first, then the brain's targeting rule.
	local pool: { Participant } = {}
	for _, opponent in opponents do
		if BattleSession.drawsAttacks(opponent) then
			table.insert(pool, opponent)
		end
	end
	if #pool == 0 then
		pool = opponents
	end

	local rule = pickWeighted(rng, {
		{ value = "LowestHP", weight = brain.targetWeights.LowestHP },
		{ value = "Random", weight = brain.targetWeights.Random },
	})
	local target = pool[1]
	if rule == "LowestHP" then
		for _, candidate in pool do
			if candidate.hp < target.hp then
				target = candidate
			end
		end
	else
		target = pool[rng:NextInteger(1, #pool)]
	end
	return abilityId, target.id
end

return EnemyAI
