--!strict
--[[
	OverworldNotice — the small panel you see while exploring (M0 report R25, a stub until the
	overworld HUD is designed): the grounds' name and how fights start for a few seconds on arriving,
	who's in your party, and "a fight is on without you" while one is. Same behavior as the old
	BattleUI's overworld panel, so nothing regresses at parity.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UI = ReplicatedStorage:WaitForChild("UI")
local Strings = require(UI:WaitForChild("Strings"))
local Theme = require(UI:WaitForChild("Theme"))
local Combat = ReplicatedStorage:WaitForChild("Combat")
local BattleTypes = require(Combat:WaitForChild("BattleTypes"))

local Root = script.Parent.Parent.Parent
local Gui = require(Root:WaitForChild("Core"):WaitForChild("Gui"))
local SlicedPanel = require(Root:WaitForChild("Components"):WaitForChild("SlicedPanel"))

export type OverworldNotice = {
	frame: Frame,
	update: (overworld: BattleTypes.OverworldState, fightOn: boolean, localUserId: number) -> (),
	destroy: () -> (),
}

local OverworldNotice = {}

function OverworldNotice.new(parent: Instance): OverworldNotice
	local frame = Gui.frame(parent, "Overworld")
	local panel = SlicedPanel.new(frame, { name = "Panel", padding = Theme.Sizes.Margin })
	local title = Gui.label(panel.content, "Title", { text = Strings.OverworldTitle, size = Theme.Sizes.TextTitle, font = Theme.Fonts.Display, align = Enum.TextXAlignment.Left, stroke = 1 })
	title.Size = UDim2.new(1, 0, 0, 28)
	local howTo = Gui.label(panel.content, "HowTo", { text = Strings.OverworldHowTo, size = Theme.Sizes.TextLabel + 1, align = Enum.TextXAlignment.Left, wrap = true })
	howTo.Size = UDim2.new(1, 0, 0, 40)
	howTo.Position = UDim2.fromOffset(0, 30)
	local party = Gui.label(panel.content, "Party", { size = Theme.Sizes.TextLabel + 1, font = Theme.Fonts.Bold, color = Theme.Colors.TextDim, align = Enum.TextXAlignment.Left, wrap = true })
	party.Size = UDim2.new(1, 0, 0, 20)
	party.Position = UDim2.fromOffset(0, 72)
	local status = Gui.label(panel.content, "Status", { text = Strings.FightWithoutYou, size = Theme.Sizes.TextLabel + 1, font = Theme.Fonts.Bold, color = Theme.Colors.Gold, align = Enum.TextXAlignment.Left, wrap = true })
	status.Size = UDim2.new(1, 0, 0, 20)
	status.Position = UDim2.fromOffset(0, 94)
	status.Visible = false

	return {
		frame = frame,
		update = function(overworld: BattleTypes.OverworldState, fightOn: boolean, localUserId: number)
			local names = {}
			for _, player in overworld.players do
				table.insert(names, if player.userId == localUserId then Strings.format.you(player.name) else player.name)
			end
			party.Text = if #overworld.players <= 1 then Strings.PlayingSolo else Strings.format.party(names, overworld.maxPartySize)
			status.Visible = fightOn
		end,
		destroy = function()
			frame:Destroy()
		end,
	}
end

return OverworldNotice
