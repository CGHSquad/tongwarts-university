--!strict
--[[
	CombatSounds — the battle's sound effects, by key (C2). Placeholders from Roblox's free audio
	library (all "Courtesy of Pro Sound Effects", the ProSoundEffects uploads Roblox licenses for
	experiences); swap any id here. An empty id plays nothing.
]]

export type Sound = {
	id: string,
	volume: number,
	speed: number, -- playback speed (pitch)
}

local function sound(id: string, volume: number, speed: number): Sound
	return { id = id, volume = volume, speed = speed }
end

local CombatSounds = {
	swing = sound("rbxassetid://9120972321", 0.6, 1.1), -- Wood Whoosh Slicing Air Quick Swings 4
	hit = sound("rbxassetid://9117969687", 0.8, 1), -- Punch Kit Beefy Hit 2
	crit = sound("rbxassetid://9117970193", 1, 0.85), -- Punch Kit Beefy Hit 7, pitched down
	miss = sound("rbxassetid://9126229255", 0.6, 1.2), -- Whoosh By Fast Airy Swooshing Whipping Thuds 2
	guard = sound("rbxassetid://9119072660", 0.7, 1), -- Shield Clang As Hit Metal Sword Hubcap 1
}

return CombatSounds
