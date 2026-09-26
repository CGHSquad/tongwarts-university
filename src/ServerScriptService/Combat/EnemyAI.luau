--!strict
--[[
	EnemyAI — MVP enemy action selection (GDD Step 6): a weighted-choice table per enemy type, read
	from that summon's `brain` in Summons. Full AI trees are explicitly a post-MVP investment.

	It only chooses. BattleSession still validates the choice exactly like a player's action.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Abilities = require(ReplicatedStorage.Combat.Abilities)
local Summons = require(ReplicatedStorage.Combat.Summons)
local BattleSession = require(script.Parent.BattleSession)

type Participant = BattleSession.Participant

-- For a summon with no brain: any affordable ability, any target.
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

-- Chooses an ability and a target for `actor` from the opponents still standing.
-- Returns nil if it has nothing it can do (no affordable ability or no one to hit).
function EnemyAI.chooseAction(actor: Participant, opponents: { Participant }, rng: Random): (string?, string?)
	if #opponents == 0 then
		return nil, nil
	end
	local summon = Summons[actor.summonId]
	local brain = if summon ~= nil and summon.brain ~= nil then summon.brain else DEFAULT_BRAIN

	-- 1. An ability it can afford right now, by weight. If every affordable ability has weight 0,
	--    fall back to the first affordable one rather than skipping the turn.
	local abilityOptions: { { value: string, weight: number } } = {}
	for _, abilityId in actor.abilities do
		local ability = Abilities[abilityId]
		if ability ~= nil and actor.mana >= ability.manaCost then
			table.insert(abilityOptions, { value = abilityId, weight = brain.abilityWeights[abilityId] or 0 })
		end
	end
	if #abilityOptions == 0 then
		return nil, nil
	end
	local abilityId = pickWeighted(rng, abilityOptions) or abilityOptions[1].value

	-- 2. A targeting rule by weight, then the target it points at.
	local rule = pickWeighted(rng, {
		{ value = "LowestHP", weight = brain.targetWeights.LowestHP },
		{ value = "Random", weight = brain.targetWeights.Random },
	})
	local target = opponents[1]
	if rule == "LowestHP" then
		for _, opponent in opponents do
			if opponent.hp < target.hp then
				target = opponent
			end
		end
	else
		target = opponents[rng:NextInteger(1, #opponents)]
	end

	return abilityId, target.id
end

return EnemyAI
