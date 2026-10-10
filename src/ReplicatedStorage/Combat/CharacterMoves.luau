--!strict
--[[
	CharacterMoves — the player character's animation clips, by moveset and beat (C2). The clips
	come from the purchased R15 packs (CREDITS.md; inventory in docs/combat-overhaul/C2_REPORT.md):
	each entry names its source (pack › rig › clip) and its timing, read from the clip's markers:
	`hit` is the contact frame (its `Hit` marker) and `reset` when the move is done (`Reset`).

	A clip plays from its published `id` once there is one (published under the PhantomVerse group).
	Until then, in Studio only, the client registers the clip's KeyframeSequence, kept in the
	Studio-only ReplicatedStorage.CombatAssets.Animations folder under the clip's `key`, for a
	temporary id. With neither (the headless tests; a live server before publishing) the beat falls
	back to the procedural moves. Every clip is R15; an R6 avatar always uses the fallbacks.
]]

export type Clip = {
	key: string, -- its KeyframeSequence's name in CombatAssets.Animations, and its name for publishing
	source: string, -- pack › rig › clip
	id: string, -- the published animation id ("" until it's published)
	length: number, -- seconds at normal speed
	hit: number?, -- seconds to the contact frame
	reset: number?, -- seconds to the end of the move (the rest is recovery to idle)
	looped: boolean,
}

export type Moveset = {
	idle: Clip, -- the breathing combat idle (looped)
	attack: Clip, -- Attack
	critical: Clip, -- Attack, when it's a critical hit
	guard: Clip, -- the Guard stance (looped while Bracing)
	guardHit: Clip, -- taking a blow while guarding
}

export type Shared = {
	approach: Clip, -- dashing in to the target
	retreat: Clip, -- dashing back to the formation spot
	evadeLeft: Clip, -- sidestepping a blow that misses
	evadeRight: Clip,
	flinch: Clip, -- taking a blow
}

local P80 = "80+ Weapon Models & Animations"
local P150 = "150+ Weapon Animations & Models"

local function clip(key: string, pack: string, rig: string, name: string, length: number, looped: boolean, hit: number?, reset: number?): Clip
	return {
		key = key,
		source = `{pack} › {rig} › {name}`,
		id = "",
		length = length,
		hit = hit,
		reset = reset,
		looped = looped,
	}
end

local CharacterMoves = {}

-- Moves every moveset shares (the 80+ Fist set's dashes, the 150+ Dual Axes flinch).
CharacterMoves.Shared = {
	approach = clip("Shared.Approach", P80, "Fist Animations", "Forward Dash", 0.68, false),
	retreat = clip("Shared.Retreat", P80, "Fist Animations", "Backward Dash", 0.58, false),
	evadeLeft = clip("Shared.EvadeLeft", P80, "Fist Animations", "Dash Left", 0.73, false),
	evadeRight = clip("Shared.EvadeRight", P80, "Fist Animations", "Dash Right", 0.73, false),
	flinch = clip("Shared.Flinch", P150, "Dual Axes Animations", "Flinch", 0.47, false),
} :: Shared

-- The Club (and any Strike hammer or bat): the 80+ Hammer set.
CharacterMoves.Hammer = {
	idle = clip("Hammer.Idle", P80, "Hammer Animations", "Idle", 4.0, true),
	attack = clip("Hammer.Attack", P80, "Hammer Animations", "Hit 1", 2.08, false, 0.58, 0.7),
	critical = clip("Hammer.Critical", P80, "Hammer Animations", "Sword Heavy", 1.0, false, 0.55, 0.9),
	guard = clip("Hammer.Guard", P80, "Hammer Animations", "Block", 4.0, true),
	guardHit = clip("Hammer.GuardHit", P80, "Hammer Animations", "Block Hit One", 0.58, false),
} :: Moveset

-- Bare fists: the 80+ Fist set.
CharacterMoves.Fists = {
	idle = clip("Fists.Idle", P80, "Fist Animations", "Idle", 2.0, true),
	attack = clip("Fists.Attack", P80, "Fist Animations", "M1 - 1", 1.6, false, 0.43, 0.62),
	critical = clip("Fists.Critical", P80, "Fist Animations", "M1 - 5", 1.5, false, 0.4, 0.52),
	guard = clip("Fists.Guard", P80, "Fist Animations", "Block", 2.0, true),
	guardHit = clip("Fists.GuardHit", P80, "Fist Animations", "Block Hit - 1", 0.5, false),
} :: Moveset

local movesets: { [string]: Moveset } = {
	Hammer = CharacterMoves.Hammer,
	Fists = CharacterMoves.Fists,
}

function CharacterMoves.moveset(name: string): Moveset
	return movesets[name] or CharacterMoves.Hammer
end

-- Every clip, each once, sorted by key: what the Studio registration and the publish list cover.
function CharacterMoves.all(): { Clip }
	local list: { Clip } = {}
	local seen: { [string]: boolean } = {}
	local function add(c: Clip)
		if not seen[c.key] then
			seen[c.key] = true
			table.insert(list, c)
		end
	end
	for _, c in CharacterMoves.Shared :: any do
		add(c)
	end
	for _, set in movesets do
		for _, c in set :: any do
			add(c)
		end
	end
	table.sort(list, function(a, b)
		return a.key < b.key
	end)
	return list
end

return CharacterMoves
