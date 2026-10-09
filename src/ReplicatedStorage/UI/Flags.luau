--!strict
--[[
	Flags — feature switches for UI that has no server support yet (handoff 5.1, section 16).
	Everything here is off by default; nothing behind a flag may invent a game rule.
]]

local Flags = {
	-- Persona-style Down / ONE MORE! / ALL-OUT ATTACK (Q2, R7). There is no server source for any
	-- of it; the UI is built on mock data only. KnockedOut is never mapped to DOWN.
	DownSystem = false,

	-- WEAK markers, affinity rows and WEAK tags (Q4, R8). No affinity data exists anywhere yet.
	ShowAffinities = false,

	-- Commands with no server support (R6).
	ShowItem = false,
	ShowPass = false,

	-- S5 role tags (handoff section 4 #5): only the party-leader marker at MVP.
	ShowRoles = false,

	-- Summon level / EXP / next-skill plates on S3 (R11).
	ShowSummonLevels = false,

	-- Opens the Studio preview harness (StarterPlayerScripts/UI/Preview) on start. Dev only.
	UIHarness = false,
}

return Flags
