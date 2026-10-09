--!strict
-- Opens the UI preview harness on start when Flags.UIHarness is on (Studio only; off in the repo).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Flags = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Flags"))

if Flags.UIHarness then
	local Harness = require(script.Parent:WaitForChild("Harness"))
	Harness.open(Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui)
end
