--!strict
--[[
	Encounter — how an overworld fight opens (GDD "Combat philosophy"): striking an enemy first
	gives your party the advantage, and getting hit from behind hands the enemies a free turn.

	When a player touches an enemy, look at where the enemy is compared with the way the player is
	facing:

		Front   it's ahead of them: they walked into it, so the party takes a bonus turn
		Back    it's behind them: it caught them from behind, so the enemies take a bonus turn
		Side    anywhere else: a neutral start

	The angles are in CombatConfig. Only the flat (X/Z) directions count, so standing on a slope or
	jumping doesn't change the answer. Pure math, no Instances.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BattleTypes = require(ReplicatedStorage.Combat.BattleTypes)
local CombatConfig = require(ReplicatedStorage.Combat.CombatConfig)

export type Contact = "Front" | "Back" | "Side"

local Encounter = {}

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

-- Where the enemy at `enemyPosition` is, from the point of view of a player at `playerCFrame`.
function Encounter.classify(playerCFrame: CFrame, enemyPosition: Vector3): Contact
	local toEnemy = flat(enemyPosition - playerCFrame.Position)
	local facing = flat(playerCFrame.LookVector)
	if toEnemy.Magnitude < 1e-3 or facing.Magnitude < 1e-3 then
		return "Side" -- right on top of each other, or looking straight up or down: call it even
	end

	local cosine = math.clamp(toEnemy.Unit:Dot(facing.Unit), -1, 1)
	local angle = math.deg(math.acos(cosine)) -- 0 = straight ahead, 180 = straight behind
	if angle <= CombatConfig.EncounterFrontAngle then
		return "Front"
	elseif angle >= 180 - CombatConfig.EncounterBackAngle then
		return "Back"
	end
	return "Side"
end

-- The side that takes the bonus opening turn after this kind of contact, or nil for an even start.
function Encounter.openingFor(contact: Contact): BattleTypes.Side?
	if contact == "Front" then
		return "Party"
	elseif contact == "Back" then
		return "Enemy"
	end
	return nil
end

return Encounter
