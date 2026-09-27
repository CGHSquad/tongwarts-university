--!strict
--[[
	BattleTheme — colors and fonts for the combat prototype's UI and placeholder blocks, kept in
	one place for whoever owns UI/art (GDD Step 4).
]]

local BattleTheme = {
	-- One color per summon slot; the block in the world and its UI swatch share it.
	PartyColors = { Color3.fromRGB(70, 150, 255), Color3.fromRGB(90, 210, 130) },
	EnemyColors = { Color3.fromRGB(235, 85, 75), Color3.fromRGB(245, 165, 60) },
	KnockedOut = Color3.fromRGB(95, 95, 100),
	-- The blocky stand-in for a player's character (when their avatar can't be shown): shirt in
	-- the slot's color, plus these.
	Skin = Color3.fromRGB(245, 205, 160),
	Legs = Color3.fromRGB(55, 60, 80),

	Panel = Color3.fromRGB(22, 24, 32),
	PanelTransparency = 0.12,
	Text = Color3.fromRGB(240, 240, 245),
	SubtleText = Color3.fromRGB(165, 170, 185),
	Accent = Color3.fromRGB(255, 205, 70), -- whose turn it is
	Danger = Color3.fromRGB(255, 95, 85), -- your target, refusals, defeat

	HealthBar = Color3.fromRGB(95, 205, 110),
	ManaBar = Color3.fromRGB(80, 140, 255),
	BarBackground = Color3.fromRGB(48, 50, 60),

	Button = Color3.fromRGB(58, 62, 80),
	ButtonText = Color3.fromRGB(240, 240, 245),
	ButtonSelected = Color3.fromRGB(255, 205, 70),
	ButtonSelectedText = Color3.fromRGB(30, 30, 30),
	ButtonDisabled = Color3.fromRGB(38, 40, 48),
	ButtonDisabledText = Color3.fromRGB(110, 112, 125),
	AttackButton = Color3.fromRGB(230, 80, 70),

	Font = Enum.Font.BuilderSans,
	FontBold = Enum.Font.BuilderSansBold,
	FontHeavy = Enum.Font.BuilderSansExtraBold,
}

function BattleTheme.colorFor(side: string, slot: number): Color3
	local palette = if side == "Party" then BattleTheme.PartyColors else BattleTheme.EnemyColors
	return palette[(slot - 1) % #palette + 1]
end

return BattleTheme
