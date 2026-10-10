--!strict
--[[
	CombatFx — the battle's particle effects, by key (C2). Each names a template in the Studio-only
	ReplicatedStorage.CombatAssets.Vfx folder (copied from the purchased 50+ Combat VFX Pack, see
	CREDITS.md; which pack effect each is, in docs/combat-overhaul/C2_REPORT.md) and caps how many
	particles one trigger may emit: `cap` on desktop, `mobileCap` on a touch-only device. A template
	that emits more is scaled down, every emitter together. With no template (the headless tests,
	a place without the folder) nothing is drawn.
]]

export type Effect = {
	template: string,
	cap: number,
	mobileCap: number,
	lifetime: number, -- seconds before the copy is cleaned up
}

local function effect(template: string, cap: number, mobileCap: number, lifetime: number): Effect
	return { template = template, cap = cap, mobileCap = mobileCap, lifetime = lifetime }
end

local CombatFx = {
	HitClub = effect("HitClub", 64, 32, 1.2), -- pack #11: heavy white impact, debris and dust
	HitFists = effect("HitFists", 29, 20, 1), -- pack #27: white star hit spark
	HitCritical = effect("HitCritical", 120, 60, 1.5), -- pack #39: red-white fiery impact, red streaks
	HitOnHero = effect("HitOnHero", 29, 20, 1), -- pack #13: white star flash
	GuardBlock = effect("GuardBlock", 90, 45, 1.2), -- pack #29: blue shield dome
	Whiff = effect("Whiff", 40, 20, 0.8), -- pack #47: thin white swoosh
	DashDust = effect("DashDust", 30, 15, 1.2), -- pack #6: smoke puff
	EvadeDust = effect("EvadeDust", 40, 20, 1.2), -- pack #10: dust puff
	KnockoutDust = effect("KnockoutDust", 50, 25, 1.5), -- pack #16: dust and smoke burst
	ParryFlash = effect("ParryFlash", 55, 28, 1), -- pack #30: white ring burst (no parry rule yet)
	DazeStars = effect("DazeStars", 29, 20, 1), -- pack #9: white star sparks, over a dazed head
}

return CombatFx
