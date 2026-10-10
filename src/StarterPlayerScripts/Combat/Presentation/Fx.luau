--!strict
--[[
	Fx — plays a battle particle effect (CombatFx) where something happens: a copy of its template
	from the Studio-only ReplicatedStorage.CombatAssets.Vfx folder, fired the way the VFX pack's
	effects expect (each emitter's `EmitCount` after its `EmitDelay`, or switched on for its
	`EmitDuration`), with the whole burst scaled down to the effect's particle cap (lower on a
	touch-only device). The sequencer owns the copy, so it's cleaned up after its lifetime or when a
	fight is left. No template, no effect: the headless tests and a place without the folder draw
	nothing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatFx = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("CombatFx"))
local Sequencer = require(script.Parent:WaitForChild("Sequencer"))

local Fx = {}

local touchOnly: boolean? = nil
local function isTouchOnly(): boolean
	local known = touchOnly
	if known ~= nil then
		return known
	end
	local result = false
	pcall(function()
		local input = game:GetService("UserInputService")
		result = input.TouchEnabled and not input.KeyboardEnabled
	end)
	touchOnly = result
	return result
end

local function templateFor(name: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("CombatAssets")
	local folder = if assets then assets:FindFirstChild("Vfx") else nil
	return if folder then folder:FindFirstChild(name) else nil
end

-- Whether an effect has a template here (the tests and Studio checks ask).
function Fx.available(key: string): boolean
	local def = (CombatFx :: any)[key]
	return def ~= nil and templateFor(def.template) ~= nil
end

local function number(value: any, default: number): number
	return if type(value) == "number" then value else default
end

-- Plays effect `key` at `at`. `parent` is where the copy goes (the stage folder; Workspace by
-- default). Returns the copy, or nil when there's nothing to play.
function Fx.play(sequencer: Sequencer.Sequencer, key: string, at: CFrame, parent: Instance?): Instance?
	local def = (CombatFx :: any)[key] :: CombatFx.Effect?
	if def == nil then
		return nil
	end
	local template = templateFor(def.template)
	if template == nil then
		return nil
	end
	local copy = template:Clone()
	local emitters: { ParticleEmitter } = {}
	local total = 0
	for _, d in copy:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			d.Enabled = false
			table.insert(emitters, d)
			-- A burst counts its EmitCount; an emitter switched on for a while, its rate times that.
			local duration = number(d:GetAttribute("EmitDuration"), 0)
			total += if duration > 0 then d.Rate * duration else math.max(0, number(d:GetAttribute("EmitCount"), 0))
		elseif d:IsA("Beam") then
			d.Enabled = false
		elseif d:IsA("Trail") then
			d.Enabled = false
		end
	end
	local cap = if isTouchOnly() then def.mobileCap else def.cap
	local ratio = if total > cap then cap / total else 1
	if copy:IsA("BasePart") then
		copy.Anchored = true
		copy.CanCollide = false
		copy.CanTouch = false
		copy.CanQuery = false
		copy.Transparency = 1
		copy.CFrame = at
	elseif copy:IsA("Model") then
		copy:PivotTo(at)
	end
	copy.Parent = parent or Workspace
	for _, emitter in emitters do
		local count = number(emitter:GetAttribute("EmitCount"), 0)
		local delay = math.max(0, number(emitter:GetAttribute("EmitDelay"), 0))
		local duration = number(emitter:GetAttribute("EmitDuration"), 0)
		local scaled = if count > 0 then math.max(1, math.floor(count * ratio + 0.5)) else 0
		local function fire()
			if copy.Parent == nil then
				return
			end
			if duration > 0 then
				emitter.Rate *= ratio
				emitter.Enabled = true
				task.delay(duration, function()
					emitter.Enabled = false
				end)
			elseif scaled > 0 then
				pcall(function()
					emitter:Emit(scaled)
				end)
			end
		end
		if delay > 0 then
			task.delay(delay, fire)
		else
			fire()
		end
	end
	sequencer:own(copy, def.lifetime)
	return copy
end

return Fx
