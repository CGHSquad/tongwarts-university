--!strict
--[[
	Motion — the reduced-motion setting. Roblox's own "Reduce motion" switch
	(GuiService.ReducedMotionEnabled) decides it, and a ReducedMotion attribute on the LocalPlayer
	overrides it for debugging (set it from the command bar in Studio). Theme.Motion.reduced follows,
	so UI tweens shorten; the battle presentation reads Motion.scale() to zero every camera shake,
	sway, flash, slow-mo and FOV punch (cuts and moves stay, so nothing is missed).
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Theme"))

local Motion = {}

Motion.ATTRIBUTE = "ReducedMotion"

local bySetting = false
local started = false
local listeners: { (reduced: boolean) -> () } = {}

local function override(): boolean?
	local player = Players.LocalPlayer
	local value = if player then player:GetAttribute(Motion.ATTRIBUTE) else nil
	return if type(value) == "boolean" then value else nil
end

function Motion.isReduced(): boolean
	local forced = override()
	return if forced ~= nil then forced else bySetting
end

-- 1 normally, 0 with reduced motion: multiply every amplitude by it.
function Motion.scale(): number
	return if Motion.isReduced() then 0 else 1
end

function Motion.onChanged(callback: (reduced: boolean) -> ())
	table.insert(listeners, callback)
end

local function refresh()
	local reduced = Motion.isReduced()
	Theme.Motion.reduced = reduced
	for _, callback in listeners do
		callback(reduced)
	end
end

-- Reads the setting and follows changes. Safe where the setting doesn't exist (the tests' fake
-- Roblox): then only the attribute counts.
function Motion.start()
	if started then
		return
	end
	started = true
	local function readSetting()
		local ok, value = pcall(function()
			return GuiService.ReducedMotionEnabled
		end)
		bySetting = ok and value == true
	end
	readSetting()
	pcall(function()
		GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function()
			readSetting()
			refresh()
		end)
	end)
	local player = Players.LocalPlayer
	if player then
		pcall(function()
			player:GetAttributeChangedSignal(Motion.ATTRIBUTE):Connect(refresh)
		end)
	end
	refresh()
end

return Motion
