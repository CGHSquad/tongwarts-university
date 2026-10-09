--!strict
--[[
	Bindings — turns the server's snapshot (BattleTypes) into the view-models the screens render
	(UITypes), and answers the "what can I pick" questions the HUD needs: which commands, which
	ability rows, which targets are legal for an ability.

	Nothing here decides an outcome. `canAfford` compares two numbers the server sent; `canTarget`
	mirrors the server's targeting rule so the picker only offers sensible choices (M0 report R22);
	the server re-checks every request. Pure data, so the Lune tests require it too.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Combat = ReplicatedStorage:WaitForChild("Combat")
local Abilities = require(Combat:WaitForChild("Abilities"))
local BattleTypes = require(Combat:WaitForChild("BattleTypes"))
local StatusEffects = require(Combat:WaitForChild("StatusEffects"))
local Flags = require(script.Parent:WaitForChild("Flags"))
local Strings = require(script.Parent:WaitForChild("Strings"))
local UITypes = require(script.Parent:WaitForChild("UITypes"))

type ParticipantState = BattleTypes.ParticipantState
type BattleState = BattleTypes.BattleState
type HudParticipant = UITypes.HudParticipant
type HudBattle = UITypes.HudBattle
type AbilityRow = UITypes.AbilityRow
type CommandView = UITypes.CommandView

local Bindings = {}

-- The character's own moves (universal abilities), in ring order.
Bindings.CHARACTER_MOVES = { "Attack", "Guard" }

local PHASES: { [string]: UITypes.HudPhase } = { setup = "Setup", input = "Input", resolve = "Resolve", reward = "Reward" }

function Bindings.participant(p: ParticipantState, localUserId: number): HudParticipant
	local statuses = {}
	for _, status in p.statuses do
		local def = StatusEffects[status.id]
		local kind: "Ailment" | "Buff" = if def and def.kind == "Ailment" then "Ailment" else "Buff"
		table.insert(statuses, {
			id = status.id,
			name = if def then def.name else status.id,
			kind = kind,
			turnsLeft = status.turnsLeft,
		})
	end
	return {
		id = p.id,
		side = p.side,
		slot = p.slot,
		name = p.name,
		summonId = p.summonId,
		ownerUserId = p.ownerUserId,
		ownerName = p.ownerName,
		isLocal = p.ownerUserId == localUserId,
		hp = { current = p.hp, max = p.maxHp },
		mana = { current = p.mana, max = p.maxMana },
		statuses = statuses,
		knockedOut = p.status == "KnockedOut",
		left = p.status == "Left",
		isDown = false, -- no server source (Flags.DownSystem)
		knownWeaknesses = {}, -- no affinity data yet (Flags.ShowAffinities)
		initiative = p.initiative,
		abilityIds = p.abilities,
	}
end

function Bindings.battle(battle: BattleState, localUserId: number): HudBattle
	local participants = {}
	local byId: { [string]: HudParticipant } = {}
	local ids = {}
	for _, p in battle.participants do
		local hud = Bindings.participant(p, localUserId)
		table.insert(participants, hud)
		byId[hud.id] = hud
		table.insert(ids, hud.id)
	end
	local actor = if battle.currentActorId then byId[battle.currentActorId] else nil
	local localActorId = if battle.phase == "input" and actor and actor.isLocal then actor.id else nil
	return {
		battleId = battle.battleId,
		rosterKey = `{battle.battleId}:{table.concat(ids, ",")}`,
		phase = PHASES[battle.phase] or "Input",
		round = battle.round,
		turnNumber = battle.turnNumber,
		turnQueue = battle.turnQueue,
		activeId = battle.currentActorId,
		participants = participants,
		byId = byId,
		localActorId = localActorId,
		opening = battle.opening,
		startedBy = battle.startedBy,
		winner = battle.winner,
		turnDeadline = battle.turnDeadline,
		overworldReturnAt = battle.overworldReturnAt,
		lastActionSequence = if battle.lastAction then battle.lastAction.sequence else 0,
		lastLogLine = battle.log[#battle.log],
		allEnemiesDown = false,
	}
end

-- Whether this player has a summon in the battle.
function Bindings.isInBattle(battle: BattleState, localUserId: number): boolean
	for _, p in battle.participants do
		if p.ownerUserId == localUserId then
			return true
		end
	end
	return false
end

-- The icon (by Assets key) and the fallback glyph for an ability.
function Bindings.iconFor(ability: Abilities.Ability): (string, string)
	if ability.kind == "Attack" then
		return if ability.damageType == "Wind" then "Icon_Wind" else "Icon_Physical", if ability.damageType == "Wind" then "W" else "S"
	elseif ability.kind == "Heal" then
		return "Icon_Heal", "+"
	elseif ability.kind == "Guard" then
		return "Icon_Guard", "G"
	end
	return "Icon_Light", "B"
end

local function needsTarget(ability: Abilities.Ability): "None" | "Enemy" | "Ally" | "AllAllies"
	if ability.targets == "Enemy" then
		return "Enemy"
	elseif ability.targets == "Ally" then
		return "Ally"
	elseif ability.targets == "AllAllies" then
		return "AllAllies"
	end
	return "None"
end

function Bindings.abilityRow(abilityId: string, mana: number): AbilityRow?
	local ability = Abilities[abilityId]
	if ability == nil then
		return nil
	end
	local iconKey, _ = Bindings.iconFor(ability)
	return {
		id = ability.id,
		name = ability.name,
		description = ability.description,
		iconKey = iconKey,
		elementId = if ability.kind == "Attack" then (ability.damageType :: string) else nil,
		cost = { mana = ability.manaCost, pips = nil },
		canAfford = mana >= ability.manaCost,
		hitsKnownWeakness = false,
		needsTarget = needsTarget(ability),
		locked = false,
	}
end

-- The summon's own abilities (the Spell list), in kit order.
function Bindings.abilityRows(actor: HudParticipant, abilityIds: { string }): { AbilityRow }
	local rows = {}
	for _, id in abilityIds do
		local row = Bindings.abilityRow(id, actor.mana.current)
		if row then
			table.insert(rows, row)
		end
	end
	return rows
end

-- The command ring: Attack, Spell, Guard, plus Item and Pass behind their flags (R6).
function Bindings.commands(abilityIds: { string }): { CommandView }
	local commands: { CommandView } = {
		{ id = "Attack", enabled = true },
		{ id = "Spell", enabled = #abilityIds > 0 },
	}
	if Flags.ShowItem then
		table.insert(commands, { id = "Item", enabled = false })
	end
	table.insert(commands, { id = "Guard", enabled = true })
	if Flags.ShowPass then
		table.insert(commands, { id = "Pass", enabled = false })
	end
	return commands
end

function Bindings.commandLabel(id: UITypes.CommandId): string
	if id == "Attack" then
		return Strings.Attack
	elseif id == "Spell" then
		return Strings.Spell
	elseif id == "Item" then
		return Strings.Item
	elseif id == "Guard" then
		return Strings.Guard
	end
	return Strings.Pass
end

-- Whether `target` is a legal pick for `abilityId` by `actor`. Mirrors the server's rule; the
-- server still checks for itself.
function Bindings.canTarget(abilityId: string, actor: HudParticipant, target: HudParticipant): boolean
	local ability = Abilities[abilityId]
	if ability == nil or target.knockedOut or target.left then
		return false
	elseif ability.targets == "Enemy" then
		return target.side ~= actor.side
	elseif ability.targets == "Ally" then
		return target.side == actor.side
	end
	return false -- Self and AllAllies need no pick
end

-- The legal targets for an ability, and the one to preselect: the first enemy, or the most hurt
-- party member for a heal.
function Bindings.targetsFor(abilityId: string, actor: HudParticipant, battle: HudBattle): ({ HudParticipant }, HudParticipant?)
	local legal = {}
	local best: HudParticipant? = nil
	local ability = Abilities[abilityId]
	for _, p in battle.participants do
		if Bindings.canTarget(abilityId, actor, p) then
			table.insert(legal, p)
			if best == nil then
				best = p
			elseif ability and ability.targets == "Ally" then
				local share = p.hp.current / math.max(p.hp.max, 1)
				local bestShare = (best :: HudParticipant).hp.current / math.max((best :: HudParticipant).hp.max, 1)
				if share < bestShare then
					best = p
				end
			end
		end
	end
	return legal, best
end

-- What the server will be sent as the target for an ability that needs no pick.
function Bindings.selfTarget(actor: HudParticipant): string
	return actor.id
end

return Bindings
