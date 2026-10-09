--!strict
--[[
	Audio — named UI sound events (handoff Core/Audio). Nothing plays until Assets.Sounds has ids;
	until then every call is a no-op, so screens can wire their sounds now.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Assets = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Assets"))

local Audio = {}

local sounds: { [string]: Sound } = {}

function Audio.play(name: string)
	local id = Assets.Sounds[name]
	if id == nil or id == "" then
		return
	end
	local existing: Sound? = sounds[name]
	local sound: Sound
	if existing then
		sound = existing
	else
		sound = Instance.new("Sound")
		sound.Name = `UI_{name}`
		sound.SoundId = id
		sound.Parent = SoundService
		sounds[name] = sound
	end
	pcall(function()
		sound:Play()
	end)
end

return Audio
