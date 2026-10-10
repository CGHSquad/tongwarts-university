--!strict
--[[
	CameraSpec — every number the battle camera uses, in one place, so the shots are tuned here
	and nowhere else. The values follow the owner's Atlus-style camera spec
	(docs/combat-overhaul/CAMERA_SPEC.md, section 7's state matrix) with the owner's playtest
	feedback on top: the moves BETWEEN shots are hard cuts or short ease-out sweeps (at most
	`Transition.maxSweepSeconds`), never floats, but a shot HOLDS as long as the outcome needs
	(CombatConfig's EnemyHoldSeconds). Distances are studs, angles degrees; `roll` is the Dutch tilt
	(negative leans the frame to match the HUD's diagonals). The spec gives some distances in metres:
	a stud is 0.28 m, so 1 m is about 3.6 studs.

	What's here is the C1 alignment pass: idle and command framing, the sub-menu micro-push with
	depth of field, target-select framing, buff/heal framing, and enemy single-target and all-party
	framing. Hit-stop, the impact FOV punch values, directional trauma and staggered AoE hits are
	C2's; the summon cut-in masking C3's; the boss low-angle wind-up C8's.
]]

local CameraSpec = {
	-- Moves between shots.
	Transition = {
		maxSweepSeconds = 0.25, -- no sweep is longer than this (an ease-out, critically damped, done when the time is up)
		whipSeconds = 0.22, -- the party's own turn changes and target trucks
		enemyTurnSeconds = 0.25, -- over to an acting enemy's wind-up shot
		-- Any move that would turn the camera more than this is a cut instead of a sweep (from the
		-- hero's reaction, facing the party, back behind the party is 120-160 degrees: in 0.25 s
		-- that's a smear, not a pan).
		cutAboveDegrees = 90,
		-- How the camera comes back after an enemy's beat: "auto" (the rule above), "sweep" (always
		-- returnSeconds) or "cut" (always).
		returnStyle = "auto",
		returnSeconds = 0.25,
		-- With reduced motion every sweep is a cut, and the tracks (the start dolly, the result
		-- orbit) hold their final frame; the Dutch tilt and the framing stay.
		reducedMotionCuts = true,
	},

	-- Idle turn: over the active party member's shoulder, two-thirds composition (the hero in the
	-- left third, the enemies around the middle), built on the line from the hero to the enemies.
	Idle = {
		fov = 52,
		roll = -4,
		back = 9.5,
		up = 3.2,
		side = 5,
		focusUp = 2, -- above the hip root: the head
		focusBlend = 0.65, -- toward the enemies' middle
		aimRight = 2.5, -- so the hero sits left of centre from either slot
		-- The aim lifted this much, so the scene sits a little low: on a phone the status block
		-- covers the top 45% and the damage number on an enemy was under it.
		aimUp = 2,
		teammatePull = 1.3, -- a teammate's turn, from a little further back
		-- The idle drift: studs, cycles per second, how much of it is vertical, and how long it
		-- takes to ease back in after a track.
		sway = { amount = 0.12, rate = 0.9, vertical = 0.6, blendSeconds = 0.3 },
	},

	-- The skill list is open: a micro-push forward, a tighter tilt, the background softened.
	Menu = {
		fov = 50,
		roll = -6,
		dolly = 1.4, -- studs forward along the shot's axis (the spec's 0.3-0.5 m is 1.1-1.8 studs)
		-- Focused on the acting hero's head; the enemies and the arena beyond soften.
		depthOfField = { farIntensity = 0.55, nearIntensity = 0, inFocusRadius = 4 },
	},

	-- Picking one enemy: tight, low, looking up at its torso from the hero's side; switching
	-- targets trucks across.
	TargetSingle = {
		fov = 42,
		roll = -2,
		-- Sized to the enemy, so a 5-stud sapling and a 13-stud Elder frame alike: it takes `fill`
		-- of the frame's height with its head `headAt` down from the top, its plate above the head
		-- inside the HUD's box. (Live, a sapling filling the frame had its plate over its face.)
		fill = 0.4,
		headAt = 0.48,
		-- On a phone the HUD's box for the plates starts about halfway down (lower still inside a
		-- real phone's safe area), and it's only two plates wide: the enemy stands low, its head
		-- below the row of plates, its feet at the bottom (the mana plate is hidden while a target
		-- is picked), off centre so the other plates fit beside its own.
		compact = { fill = 0.29, headAt = 0.7, offCenter = 0.14 },
		-- The picked enemy sits this far off the middle (a fraction of the frame's width), away
		-- from the other enemies, so their plates (pinned to the HUD box's edge on their side) fit
		-- beside its own on a phone. `aspect` is the frame's width over height it assumes.
		offCenter = 0.14,
		aspect = 1.9,
		-- Never closer to the hero than this (a 13-stud Elder would otherwise put the camera
		-- behind the hero, who'd come into the frame): a tall enemy is then shown head and chest.
		heroClearance = 6,
		side = 3, -- studs to the side, for a three-quarter view
		heightAbove = 0.25, -- camera height: this fraction of the enemy's height above the floor
		truckSeconds = 0.2,
	},

	-- Picking all enemies: pulled back and up from the hero to frame the whole squad.
	TargetSquad = {
		fov = 62,
		roll = 0,
		back = 9,
		up = 7,
		focusUp = 2,
	},

	-- Picking one ally (a heal): chest-up frontal.
	TargetAlly = {
		-- (Live, 7 studs off put the character's head and torso across the whole screen, under
		-- the mana plate: from 9 it's a medium shot, head in the upper middle.)
		fov = 45,
		roll = 0,
		front = 9,
		side = 2,
		up = 1.2,
		focusUp = 1.8, -- (aimed at the shoulders, so the head clears the status line above)
	},

	-- A turn lost to a daze (C2 follow-up): the dazed figure's own shot (a party member chest-up,
	-- an enemy frontal), aimed so its head and the stars over it sit this far down the screen,
	-- below the HUD's status block on a phone (which reaches about half way down).
	Daze = { headAt = 0.64 },

	-- Buffs and heals, when they fire (section 5).
	Cast = {
		initiationSeconds = 0.25, -- the caster's frontal medium shot
		effectSlackSeconds = 0.1, -- after that shot and the sweep to it, before the effect lands
		casterFov = 45,
		caster = { front = 5, frontPerHeight = 0.5, side = 1.5, upPerHeight = 0.1 },
		recipientFov = 45,
		recipientRoll = 0,
		lift = 1.8, -- the pedestal lift following the effect upward (the spec's 0.5-1.0 m is 1.8-3.6 studs)
		liftLook = 0.5, -- the aim rises this share of it (the camera tilts down onto the recipient; at 1 the body dropped to the frame's bottom)
		breatheOut = 5, -- field of view opening during the lift
		liftSeconds = 0.6,
	},

	-- Party-wide buffs and heals: a high-angle three-quarters overhead of the party, held still.
	Party = {
		fov = 62,
		roll = 0,
		pitchDown = 30,
		distance = 17,
		focusUp = 1,
		-- After the effect lands, before the camera comes back. A party-wide effect lands a sweep and
		-- Cast.effectSlackSeconds into the beat (there's no caster shot first), and the shot is cut
		-- to on confirm, about 0.15 s before the beat: about 1.1 s in all, under the spec's 1.2 s.
		holdSeconds = 0.6,
	},

	-- An acting enemy's wind-up: a low offset frontal shot, looking up (the boss's extreme low
	-- angle is C8's).
	EnemyWindup = {
		fov = 48,
		roll = 3, -- the spec's wind-ups avoid a level horizon; leaning the other way from the party's shots marks the enemy's side
		front = 5,
		frontPerHeight = 0.7,
		side = 3,
		sidePerHeight = 0.3,
		heightAbove = 0.15,
		focusUp = 0.1,
		offset = 1.5, -- the aim past the enemy, so it sits right of centre
	},

	-- An enemy's single-target attack: over the targeted hero's shoulder, looking out at it.
	EnemyIncoming = {
		fov = 45,
		roll = 0,
		pull = 1.1,
		minLeadSeconds = 0.25, -- a swing shorter than this gets no shot of its own (straight to the reaction)
		cutLeadSeconds = 0.05, -- the cut to the reaction comes this long before the blow lands
	},

	-- An enemy's attack on the whole party: a wide rear-diagonal lineup of the party, held
	-- through the blast.
	EnemyAoE = {
		fov = 62,
		roll = 0,
		back = 13,
		side = 6,
		up = 6,
		focusAhead = 3,
	},

	-- Whoever a blow lands on: front-low (C2 refines the impact framing itself).
	Reaction = {
		fov = 50,
		roll = 0,
		front = 6,
		frontPerHeight = 0.7,
		side = 2,
		upPerHeight = 0.25,
		-- Aimed above the body's middle, so the body (and the number on it) sits in the lower half
		-- of the frame, clear of the turn bar and status block for the whole hold.
		focusUpPerHeight = 0.35,
	},

	-- The summon beat: well back and out, so character and summon are both in frame.
	Summon = {
		fov = 52,
		roll = -3,
		back = 15,
		up = 7.5,
		side = 7,
		focusUp = 4.5,
		focusBlend = 0.3,
		pairBack = 1, -- the aim sits this far behind the character, between it and the summon
	},

	-- The battle-start dolly across the stage (from behind the enemies' side to the party's).
	Sweep = { seconds = 1.9, fovFrom = 62, fovTo = 56, start = 24, travel = 48, front = 30, frontDrift = 2, up = 7, upDrift = 2, focusUp = 3 },
	-- The result: an orbit of the party for a win, a tilt down to the floor for a loss.
	Victory = { seconds = 2.5, fov = 54, fovDrift = 4, radius = 17, height = 6.5, startAngle = -35, arc = 60, focusUp = 3 },
	Defeat = { fov = 56, fovDrift = -8, front = 12, up = 4, focusUp = 3, tiltDown = 4 },
	Wide = { fov = 60, back = 40, up = 20, focusUp = 3 },

	-- Kicks on top of the shot (all zero with reduced motion). Degrees, studs, seconds.
	Kicks = {
		confirmPunch = 8, -- field of view, on confirming a move
		punchSettleSeconds = 0.25,
		whipRoll = 2, -- how far a whip-pan rolls the frame at its peak
		whipBelowSeconds = 0.3, -- a move quicker than this is a whip-pan (it rolls)...
		whipMinStuds = 2, -- ...when it travels at least this far
		fovRange = { 20, 120 }, -- the field of view never leaves this, kicks included
		rollSettleSeconds = 0.3,
		shakeFrequency = 47,
	},

	-- The impact of a blow (CAMERA_SPEC section 4B/4C, C2). Frames are 60 fps frames.
	Impact = {
		frameSeconds = 1 / 60,
		hitStopFrames = 4, -- on contact the swing holds and the target reacts only after (spec: 2-6)
		criticalHitStopFrames = 6,
		fovPunch = -5, -- the field of view snaps this much narrower on the contact frame...
		fovPunchSettleSeconds = 0.18, -- ...and eases back over this (spec: 0.15-0.2)
		trauma = { amplitude = 0.3, seconds = 0.25 }, -- the shake, along the blow's direction
		criticalTrauma = { amplitude = 0.45, seconds = 0.35 },
		-- Several targets register one after another, this many frames apart (spec: 3-5), each
		-- with its own small shudder and pulse.
		staggerFrames = 4,
		tick = { fovPunch = -2, amplitude = 0.15, seconds = 0.15 },
		-- A critical: a white flash and a brief slow-mo after the hit-stop.
		flash = { seconds = 0.09, startTransparency = 0.35 },
		slowMo = { seconds = 0.3, scale = 0.25 },
	},

	-- Depth of field is left off on low graphics quality levels (1-3 of 10).
	DepthOfFieldMinQuality = 4,
}

return CameraSpec
