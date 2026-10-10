--!strict
--[[
	Sfx — plays a battle sound (CombatSounds) once. The sequencer owns the Sound, so it's cleaned
	up after it has played or when a fight is left. An empty id plays nothing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local CombatSounds = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("CombatSounds"))
local Sequencer = require(script.Parent:WaitForChild("Sequencer"))

local Sfx = {}

Sfx.LIFETIME = 3 -- seconds a played sound is kept before it's cleaned up

-- Plays sound `key`. Returns the Sound (the tests look for it), or nil when there's nothing to play.
function Sfx.play(sequencer: Sequencer.Sequencer, key: string): Sound?
	local def = (CombatSounds :: any)[key] :: CombatSounds.Sound?
	if def == nil or def.id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = "Sfx_" .. key
	sound.SoundId = def.id
	sound.Volume = def.volume
	sound.PlaybackSpeed = def.speed
	sound.Parent = SoundService
	pcall(function()
		sound:Play()
	end)
	sequencer:own(sound, Sfx.LIFETIME)
	return sound
end

return Sfx
