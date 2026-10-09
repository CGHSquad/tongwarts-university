--!strict
--[[
	Strings — every piece of text the UI shows, so it can change in one place and be localized later
	(handoff rule 4). Constants for fixed labels; `Strings.format.*` for text built from numbers and
	names (R23). No module may bake text into a label.

	The resource is Mana, never MP (handoff rule 6).
]]

local Strings = {
	Mana = "Mana",
	ManaShort = "MP", -- only where there is truly no room; prefer Mana
	Health = "HP",
	Currency = "Gold", -- placeholder soft currency name (GDD Step 7: TBD)

	-- Commands (S1)
	Attack = "Attack",
	Spell = "Spell",
	Item = "Item",
	Guard = "Guard",
	Pass = "Pass",
	Free = "Free",
	Confirm = "Confirm",
	Back = "Back",
	Close = "Close",
	Now = "NOW",
	Waiting = "Waiting...",
	Sending = "Sending...",
	YourTurn = "YOUR TURN",
	EnemyTurn = "Enemy turn",
	ChooseMove = "Choose a move",
	PickEnemy = "Pick an enemy",
	PickAlly = "Pick a party member",
	TargetSelf = "Target: itself",
	TargetParty = "Target: the whole party",
	BonusTurn = "Bonus turn",
	NotEnoughMana = "Not enough Mana",
	NotYourTurn = "It's not your turn",

	-- Tags (S1, S3, S7)
	Weak = "WEAK",
	Resist = "RESIST",
	Null = "NULL",
	Down = "DOWN",
	Front = "FRONT",
	KnockedOut = "KO",
	Left = "LEFT",
	OneMore = "ONE MORE!",
	AllOutAttack = "ALL-OUT ATTACK",

	-- Results (S6)
	Victory = "VICTORY",
	Defeat = "DEFEAT",
	Result = "RESULT",
	Exp = "EXP",
	Items = "ITEM",
	Party = "PARTY",
	LevelUp = "LEVEL UP!",
	Continue = "Continue",

	-- Overworld notice
	OverworldTitle = "TungWarts Grounds",
	OverworldHowTo = "Walk into an enemy to start a fight. Face it when you touch it and your party gets a bonus turn. "
		.. "If one walks into your back, the enemies get it instead.",
	PlayingSolo = "Playing solo: you'll control your whole party.",
	FightWithoutYou = "A fight is on without you. You'll be in the next one.",

	-- Stubs (handoff section 12)
	ComingSoon = "Coming soon",

	-- Harness
	HarnessTitle = "UI harness",
	HarnessPrev = "Prev",
	HarnessNext = "Next",
	HarnessSafeZones = "Safe zones",
}

local format = {}

function format.hp(current: number, max: number): string
	return `{Strings.Health}  {current} / {max}`
end

function format.mana(current: number, max: number): string
	return `{Strings.Mana}  {current} / {max}`
end

function format.manaCost(cost: number): string
	return if cost > 0 then `{cost} {Strings.Mana}` else Strings.Free
end

function format.round(round: number): string
	return if round == 0 then Strings.BonusTurn else `Round {round}`
end

function format.secondsLeft(seconds: number): string
	return `{seconds}s left`
end

function format.returningIn(seconds: number): string
	return `Returning in {seconds}...`
end

function format.chooseFor(summonName: string): string
	return `Choose an attack for {summonName}`
end

function format.waitingFor(summonName: string): string
	return `Waiting for {summonName}`
end

function format.alliesTurn(playerName: string): string
	return `{playerName}'s turn`
end

function format.enemyChoosing(enemyName: string): string
	return `{enemyName} is choosing a move...`
end

function format.party(names: { string }, maxPartySize: number): string
	return `Party: {table.concat(names, ", ")}. Up to {maxPartySize} fight together.`
end

function format.you(name: string): string
	return `{name} (you)`
end

function format.quantity(count: number): string
	return `x{count}`
end

function format.gained(amount: number): string
	return `+{amount}`
end

function format.level(level: number): string
	return `Lv {level}`
end

function format.guard(damagePercent: number, ailmentPercent: number): string
	return `Until its next turn: {damagePercent}% less damage, no critical hits, ailments {ailmentPercent}% less likely.`
end

-- How the fight opened (the initiative reveal). `who` is the player who touched the enemy.
function format.opening(opening: string?, who: string): (string, string)
	if opening == "Party" then
		return "You struck first!",
			`{who} walked right into them: your party takes a bonus turn, then everyone goes in initiative order.`
	elseif opening == "Enemy" then
		return "Ambushed from behind!",
			`They caught {who} from behind: the enemies take a bonus turn, then everyone goes in initiative order.`
	end
	return "Encounter!",
		`{who} bumped into them from the side, an even start. Everyone rolls 1-20 plus an Agility bonus; highest goes first.`
end

function format.initiative(roll: number, bonus: number, total: number): string
	return `{roll} + {bonus} = {total}`
end

Strings.format = format

return Strings
