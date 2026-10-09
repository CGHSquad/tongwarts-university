--!strict
--[[
	Pacing — how long the server waits after an action before the next turn opens, so the stage
	has time to play it out (GDD Step 6: the server owns time, the client only renders).

	Both sides read it: BattleDirector waits this long, and BattleView treats it as the budget its
	presentation of the action may take (compressing clips to fit), so the next turn never opens
	while an animation is still going. Pure data and arithmetic, no Roblox APIs; the numbers live
	in CombatConfig (ResolvePauseSeconds is the base, ResolveExtraSeconds what each beat adds).
]]

local Abilities = require(script.Parent:WaitForChild("Abilities"))
local BattleTypes = require(script.Parent:WaitForChild("BattleTypes"))
local CombatConfig = require(script.Parent:WaitForChild("CombatConfig"))

local Pacing = {}

-- Whether a party member's own summon comes out to perform this ability (Stand/Persona-style),
-- rather than its character making a universal move (Attack, Guard).
function Pacing.isSummoned(side: BattleTypes.Side, abilities: { string }, abilityId: string): boolean
	return side == "Party" and table.find(abilities, abilityId) ~= nil
end

-- Seconds between an action resolving and the next turn opening. `ability` is nil when the turn
-- passed or was lost to an ailment: nothing to show but the log line. `side` is the actor's: an
-- enemy's action holds on its outcome and the camera eases back afterwards (CombatConfig's
-- EnemyHoldSeconds and EnemyReturnSeconds), which the wait covers.
function Pacing.resolveSeconds(
	ability: Abilities.Ability?,
	results: { BattleTypes.ActionResult }?,
	summoned: boolean,
	side: BattleTypes.Side?
): number
	local seconds = CombatConfig.ResolvePauseSeconds
	if ability == nil then
		return seconds
	end
	if side == "Enemy" then
		seconds += CombatConfig.EnemyHoldSeconds + CombatConfig.EnemyReturnSeconds
	end
	local extra = CombatConfig.ResolveExtraSeconds
	if ability.kind == "Attack" then
		seconds += extra.Lunge
		local hits, criticals, knockouts = 0, 0, 0
		local list: { BattleTypes.ActionResult } = results or {}
		for _, result in list do
			if result.hit then
				hits += 1
			end
			if result.critical then
				criticals += 1
			end
			if result.knockedOut then
				knockouts += 1
			end
		end
		if results and #results > 1 then
			seconds += extra.AllTarget
		end
		if results and hits == 0 then
			seconds += extra.Miss
		end
		if criticals > 0 then
			seconds += extra.Critical
		end
		if knockouts > 0 then
			seconds += extra.Knockout
		end
	elseif ability.kind == "Guard" then
		seconds += extra.Guard
	else
		seconds += extra.Cast
	end
	if summoned then
		seconds += extra.Summon
	end
	return math.max(CombatConfig.MinResolveSeconds, seconds)
end

return Pacing
