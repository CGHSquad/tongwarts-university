--!strict
--[[
	Theme — every color, font, size and motion value the UI uses, in one place (handoff 5.3).

	The palette is the mockups' (navy, obsidian, gold, purple, cyan); the launch school's own color
	(TungWarts: forest green, gold, white) comes in through SchoolAccent, which only replaces the
	highlight and trim token so crimson stays enemy-only (Q5). Swap `Theme.setSchool` per school.

	Sizes are in design pixels at Layout.DESIGN (a phone screen); the root UIScale scales them up
	on bigger screens, never down, so 18 px body text and 48 px tap targets are the floor everywhere.
]]

local Theme = {}

Theme.Colors = {
	Obsidian = Color3.fromRGB(11, 13, 26), -- #0B0D1A
	Navy = Color3.fromRGB(18, 26, 58), -- #121A3A
	Gold = Color3.fromRGB(242, 193, 78), -- #F2C14E
	Purple = Color3.fromRGB(123, 63, 228), -- #7B3FE4
	Cyan = Color3.fromRGB(54, 214, 245), -- #36D6F5
	Crimson = Color3.fromRGB(216, 40, 60), -- #D8283C: enemy / weak only
	HpGreen = Color3.fromRGB(86, 214, 110),
	ManaBlue = Color3.fromRGB(70, 150, 255),
	TextLight = Color3.fromRGB(245, 243, 236),
	TextDim = Color3.fromRGB(168, 172, 190),
	-- Text that sits straight over the 3D scene (the status line's detail): near-white, always with
	-- an Ink stroke (Sizes.StrokeOverScene), so it reads over a bright sky as well as dark ground.
	TextOverScene = Color3.fromRGB(236, 238, 246),
	Disabled = Color3.fromRGB(70, 72, 88),
	Ink = Color3.fromRGB(0, 0, 0), -- outlines and lettering strokes
	White = Color3.fromRGB(255, 255, 255),
	-- Command ribbons (handoff S1): one fixed color each
	CommandAttack = Color3.fromRGB(70, 120, 180), -- steel blue
	CommandSpell = Color3.fromRGB(123, 63, 228), -- purple
	CommandItem = Color3.fromRGB(44, 160, 90), -- green
	CommandGuard = Color3.fromRGB(230, 160, 40), -- amber
	CommandPass = Color3.fromRGB(190, 195, 205), -- silver
}

-- Panels: the fallback look when no art is loaded (handoff 5.2).
Theme.Panel = {
	Fill = Theme.Colors.Obsidian,
	FillTransparency = 0.08,
	Trim = Theme.Colors.Gold,
	TrimThickness = 2,
	Corner = 6,
}

export type School = { id: string, name: string, accent: Color3, trim: Color3, text: Color3 }

Theme.Schools = {
	TungWarts = {
		id = "TungWarts",
		name = "TungWarts University",
		accent = Color3.fromRGB(46, 125, 79), -- forest green
		trim = Theme.Colors.Gold,
		text = Theme.Colors.White,
	} :: School,
}

-- The token the school replaces: highlights (active turn, selected row) and trim.
Theme.SchoolAccent = Theme.Schools.TungWarts.accent
Theme.School = Theme.Schools.TungWarts

function Theme.setSchool(school: School)
	Theme.School = school
	Theme.SchoolAccent = school.accent
end

Theme.Fonts = {
	Display = Enum.Font.BuilderSansExtraBold, -- lettering: bold + black UIStroke approximates the mockups
	Bold = Enum.Font.BuilderSansBold,
	Body = Enum.Font.BuilderSans,
}

-- Design pixels (see the header).
Theme.Sizes = {
	TapMin = 48,
	TapComfortable = 56,
	TextBody = 18,
	TextLabel = 14, -- captions only, never for anything that must be read in a hurry
	TextTitle = 24,
	TextDisplay = 40,
	StrokeDisplay = 3,
	StrokeOverScene = 2, -- the Ink outline on text over the scene (TextOverScene)
	BarHeight = 14,
	RowHeight = 56,
	Gap = 8,
	Margin = 12,
}

-- Seconds. Motion.scale is 1, or Motion.reducedScale when the reduced-motion setting is on.
Theme.Motion = {
	Fade = 0.15,
	Tween = 0.25,
	RibbonBurst = 0.2,
	RibbonStagger = 0.04,
	StampPop = 0.25,
	StampHold = 0.8,
	BarTrailDelay = 0.3,
	CountUp = 1.0,
	reducedScale = 0.4,
	reduced = false,
}

function Theme.motion(seconds: number): number
	return if Theme.Motion.reduced then seconds * Theme.Motion.reducedScale else seconds
end

return Theme
