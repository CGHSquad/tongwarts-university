--!strict
--[[
	Weapons — what a player character fights with (GDD: Strike, Slash and Pierce weapon
	categories; C0 report section 10, C9). In C2 a weapon is presentation only: which moveset the
	character's Attack plays (CharacterMoves), which model it holds (by name in the Studio-only
	ReplicatedStorage.CombatAssets.Weapons folder) and which way its blows shake the camera. The
	stats are recorded for C9, which brings weapons into the rules; nothing reads them yet.

	Which weapon a player uses: the Club, unless a `DebugWeapon` attribute on their Player names
	another (Studio playtests only; C9 adds real loadouts).
]]

export type Category = "Strike" | "Slash" | "Pierce"
-- Which way a blow's camera trauma runs: an overhead swing shakes vertically, a hook sideways.
export type Trauma = "Vertical" | "Lateral"

export type Weapon = {
	id: string,
	name: string,
	category: Category,
	atk: number, -- C9: the weapon's attack (displayed ×10)
	hit: number, -- C9: base hit chance
	moveset: string, -- a key of CharacterMoves
	model: string?, -- a model in ReplicatedStorage.CombatAssets.Weapons, held in the right hand; nil = bare hands
	trauma: Trauma,
	reach: number, -- studs between the target's body and where the character stops to swing
	sounds: { swing: string, hit: string }, -- CombatSounds keys
	hitEffect: string, -- a CombatFx key
}

local Weapons = {}

-- The starter weapon. Its model is a placeholder: the asset packs have no club or bat, so it
-- holds the 80+ pack's Iron Warhammer for now.
Weapons.Club = {
	id = "Club",
	name = "Club",
	category = "Strike",
	atk = 4,
	hit = 0.9,
	moveset = "Hammer",
	model = "Club",
	trauma = "Vertical",
	reach = 2.2,
	sounds = { swing = "swing", hit = "hit" },
	hitEffect = "HitClub",
} :: Weapon

-- Bare fists: a Strike weapon with the Club's numbers for now.
Weapons.Fists = {
	id = "Fists",
	name = "Fists",
	category = "Strike",
	atk = 4,
	hit = 0.9,
	moveset = "Fists",
	model = nil,
	trauma = "Lateral",
	reach = 1.3,
	sounds = { swing = "swing", hit = "hit" },
	hitEffect = "HitFists",
} :: Weapon

Weapons.DEFAULT = "Club"
Weapons.ATTRIBUTE = "DebugWeapon" -- on a Player, Studio only

local byId: { [string]: Weapon } = {
	Club = Weapons.Club,
	Fists = Weapons.Fists,
}

-- The weapon with this id, or the default for anything unknown.
function Weapons.get(id: string?): Weapon
	return (if id then byId[id] else nil) or byId[Weapons.DEFAULT]
end

function Weapons.ids(): { string }
	local list = {}
	for id in byId do
		table.insert(list, id)
	end
	table.sort(list)
	return list
end

return Weapons
