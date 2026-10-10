# C2 — Strike attack and impact feel

Status: built on branch `combat-c2-strike`, waiting for the owner's approval. This report starts
with the inventory of the four purchased asset packs (asked for before building), then the plan,
the live results, the animations to publish and the quality loop.

## 1. The asset packs: where they live and the licence rules

Four R15 packs from BuiltByBit, all by **WokeSSS** (https://builtbybit.com/creators/wokesss.753925/):

| Pack | Listing | File | What's in it |
| --- | --- | --- | --- |
| 150+ Weapon Animations & Models | https://builtbybit.com/resources/150-weapon-animations-models.119528/ | `.rbxm`, 4.6 MB | 8 weapon rigs, 158 clips, 13 weapon models |
| 80+ Weapon Models & Animations | https://builtbybit.com/resources/80-weapon-models-animations.117662/ | `.rbxm`, 2.2 MB | 5 weapon rigs, 82 clips, 6 weapon models |
| 125+ Animations & Weapons Pack | https://builtbybit.com/resources/125-animations-weapons-pack.126261/ | `.rbxl` (a place), 2.9 MB | 8 weapon rigs, 128 clips, 8 weapon models |
| 50+ Combat VFX Pack | https://builtbybit.com/resources/50-combat-vfx-pack.118478/ | `.rbxm`, 150 KB | 49 particle effects (1,415 emitters, 11 beams) |

**Licence**: "Standard EULA: use on any projects you own with attribution". Not open source, and
this repository is public, so:

- No pack file and nothing exported from one (places, models, meshes, textures, animation data) is
  ever committed or copied into the repo folder. `.gitignore` now refuses pack names and any
  `AssetPacks/`, `PackExports/` or `*AssetPack*/` folder, plus every `.rbxl`/`.rbxlx`; every
  commit's file list is checked before it's made.
- The packs live only in the Team Create place, imported raw into **`ServerStorage/AssetPacks`**
  (Rojo doesn't manage ServerStorage). The 125+ place file was read with Lune into a model file in a
  scratch folder outside the repo; nothing was uploaded or published.
- What the game needs at runtime goes in **`ReplicatedStorage/CombatAssets`**, a Studio-only folder
  that Rojo creates empty and never wipes (`"$ignoreUnknownInstances": true` in
  `default.project.json`). The headless tests build the place without it, so every use falls back
  cleanly when it's empty.
- Only asset ids (once published under PhantomVerse) and our own code and data go in the repo.
  Attribution is in `CREDITS.md`.

How the import was done (for the next pack): Studio's MCP can't open local files, and
`InsertService:LoadLocalAsset` is not allowed to it, but `game:GetObjects("rbxasset://…")` reads
from Studio's own `content` folder. Each pack was copied there temporarily, loaded, parented into
`ServerStorage/AssetPacks` one child at a time, and the copies deleted.

## 2. Inventory

### Animations: 368 KeyframeSequences, all publishable

Every clip is a `KeyframeSequence` in a rig's `AnimSaves` (none is an uploaded id), on a standard
R15 skeleton (HumanoidRootPart → LowerTorso → … 15 joints), so each can be published from the
Animation Editor under PhantomVerse. Most carry `KeyframeMarker`s: `Swing`, `Hit` (the contact
frame) and `Reset` (when the move is done), sometimes `WindUpStart`/`WindUpEnd`, and footstep
markers on locomotion. The `Hit` marker is what times the impact, hit-stop and damage number.

Per weapon rig (counts by type; "heavy / skill" = heavy, M2, air slam, up-tilt, dash attack, jump
or air attack, all usable as skill animations):

| Pack | Rig (weapon) | Clips | Attacks / combo | Heavy / skill | Parry | Block | Block-hit | Hit reaction | Idle | Walk | Run | Landing | Dash | Weapon model(s) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 80+ | Dagger | 22 | 5 | 5 | — | 1 | 3 | — | 1 | 1 | 1 | 1 | 4 | Voidrune Edge (2 emitters, 6 trails) |
| 80+ | Sword | 13 | 5 | — | — | 1 | 2 | — | 1 | 1 | 1 | 1 | 1 | Night's Edge (2 emitters, 7 trails) |
| 80+ | Hammer | 17 | 5 | 5 | — | 1 | 2 | — | 1 | 1 | 1 | — | 1 | Iron Warhammer (31 emitters, 4 trails) |
| 80+ | Spear | 14 | 5 | 4 | — | 1 | 1 | — | 1 | 1 | 1 | — | — | Azure Reaver (2 emitters, 6 trails) |
| 80+ | Fist | 16 | 5 | — | — | 1 | 3 | — | 1 | 1 | 1 | — | 4 | none (bare hands) |
| 150+ | Dual Axes | 23 | 5 | 5 | 4 | 1 | — | 1 | 1 | 1 | 1 | — | 4 | Stone Axes (2 emitters) |
| 150+ | Great Sword | 20 | 4 | 6 | 6 | 1 | — | — | 1 | 1 | 1 | — | — | Abyssal Covenant (3 emitters, 6 trails) |
| 150+ | Trident | 23 | 5 | 5 | 4 | 1 | 2 | — | 1 | 1 | 1 | — | 3 | Neptune's Trident (16 emitters) |
| 150+ | Dual Great Shield | 24 | 5 | 5 | 4 | 1 | — | 1 | 1 | 1 | 1 | 1 | 4 | Iron GreatShield (2 emitters, 4 trails) |
| 150+ | Gauntlets | 18 | 5 | 5 | 5 | 1 | — | — | 1 | 1 | — | — | — | Voidfang Gauntlets (4 emitters, 4 trails) |
| 150+ | Requiem | 18 | 5 | 3 | 5 | 1 | — | — | 1 | 1 | 1 | — | 1 | Obsidian Requiem (2 emitters, 7 trails) |
| 150+ | Oathkeeper | 12 | 5 | — | — | 1 | 2 | — | 1 | — | 1 | 1 | 1 | Oath Keeper (3 emitters, 6 trails) |
| 150+ | Lance | 20 | 5 | 5 | 5 | 1 | 1 | — | 1 | 1 | 1 | — | — | Abyssfang Lance (2 emitters, 6 trails) |
| 125+ | Blade | 16 | 5 | 3 | 3 | 1 | — | — | 1 | 1 | 1 | — | 1 | NSoD |
| 125+ | Glaive | 10 | 5 | 5 | — | — | — | — | — | — | — | — | — | Azure Reaver |
| 125+ | Grimoire | 14 | 5 | 5 | 1 | 1 | 2 | — | — | — | — | — | — | Revenant Grimoire |
| 125+ | Light Axe | 17 | 5 | 3 | 3 | 1 | — | — | 1 | 1 | 1 | 1 | 1 | Iron Boarding Axe (2 emitters) |
| 125+ | Medium Axe | 15 | 6 | 2 | 3 | 1 | — | — | 1 | — | — | 1 | 1 | Stone Axes |
| 125+ | Pickaxe | 17 | 5 | 5 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | — | — | Starter Pickaxe |
| 125+ | Rapier | 23 | 5 | 5 | 3 | 1 | 1 | — | 1 | 1 | 1 | 1 | 4 | Iron Rapier (2 emitters) |
| 125+ | Shield | 16 | 5 | — | — | 1 | 3 | — | 1 | 1 | 1 | — | 4 | Graveward Bulwark |

("Parry" includes parried, clash and guard-break clips; the counts are by clip name, so a few are
approximate.) Duplicates across packs: the 125+ Blade set is the 150+ Requiem set; Glaive is the
80+ Spear set; Shield is the Fist set; Oathkeeper is the 80+ Sword set; Medium Axe and Dual Axes
share clips.

**Not in any pack**: a death or knocked-out clip, and a dodge (the side dashes serve as the evade).
Hit reactions are thin: one `Flinch` (Dual Axes, 0.47 s; Dual Great Shield's is 0.18 s) and a long
`Dazed` stun loop (Pickaxe, 4.8 s). Every clip is R15: an R6 avatar keeps today's procedural moves.

### Weapon models

21 weapon models (some duplicated across packs), each held by one `Motor6D` from `RightHand` to the
model's `Main` part (gauntlets: one per hand). No clip animates the weapon joint (the Hammer
clips carry a stray `staff` pose that matches nothing), so a model welded to a character's hand
follows its swings. There is **no club or bat**: the Iron Warhammer is the Club's placeholder.
Several models carry glow emitters and trails (the Iron Warhammer has 31 emitters): the runtime copy
keeps them off except the trails during a swing.

### VFX: 49 effects, all named "SYXASSETS"

Each effect is a 2×2×2 invisible part with emitters (and attachments) using a common emit convention
(attributes `EmitCount`, `EmitDelay`, `EmitDuration`, `TimeScale_Start/End/Duration`). They're
unnamed, so they were sorted by eye (grid captures in Studio Play, continuous and burst). "Burst" is
the particles one trigger emits (sum of `EmitCount`):

| # | Looks like | Burst | Use |
| --- | --- | --- | --- |
| 4, 11 | Heavy white impact, debris and dust | 32, 64 | **Club hit** (#11) |
| 8 | Big white impact with a shock ring and debris | 302 | heavy hit (cap) |
| 39 | Red-white fiery impact, red slash streaks, sparks | 290 | **Critical hit** (capped to 120) |
| 31, 38 | Huge orange-white explosions | 532, 584 | too heavy for mobile; a boss or skill later, trimmed |
| 9, 13, 27 | White star hit sparks | 29 each | **Fists hit** (#27), enemy hits on heroes (#13) |
| 48 | White star flash with a ground disc | 190 | block-break later (cap) |
| 29 | Blue shield dome | 300 | **Guard: blocked hit** (capped to 90) |
| 30 | White ring burst with streaks | 55 | **Parry flash** (no parry rule yet) |
| 47, 23, 40 | Thin white swoosh lines | 63, 24, 147 | **Miss / whiff** (#47) |
| 6 | Smoke puff | 96 | **Dash dust** (capped to 30) |
| 10, 14 | Dust puffs | 123, 180 | **Evade dust** (#10, capped to 40) |
| 16 | Dust and smoke burst | 126 | **Knockout dust** (capped to 50) |
| 2, 20 | Dust with embers, faint dark puff | 244, 42 | landing / dark hits later |
| 21, 24, 25, 41, 43, 44 | White crescent slashes | 24–44 | **C4 Slash** (#24 normal, #43 large) |
| 46 | White X cross slash | 62 | **C4 Slash critical** |
| 22, 37 | Red crescents / slash ring | 31, 67 | crits, enemy slashes |
| 32, 33, 42, 45 | Green / yellow slash lines and arcs | 31–63 | element-coloured slashes later |
| 23 | Thin straight white line | 24 | **C4 Pierce** thrust |
| 1, 3, 5, 12, 15, 17, 18, 26, 49 | Small coloured bursts and orbs (purple, blue, red, green, pink) | 1–92 | magic / status later (not Wind) |
| 7, 19, 28, 34, 36 | Fire bursts, rings, glows, a fire streak | 45–530 | fire later |
| 35 | Grey swirl ring | 91 | not used (reads as wind; Wind skills get their own) |

**Mobile**: one hit's effect is capped by data (`CombatFx`): the picks above stay under 120
particles per trigger on desktop and half that on touch devices (scaling every emitter's count
down together), and duration emitters' rates are scaled the same way.

### Picks for the weapons

| Weapon | Set | Clips used | Model |
| --- | --- | --- | --- |
| **Club** (Strike) | 80+ **Hammer** | Idle; Hit 1 (attack, `Hit` at 0.58 s); Sword Heavy (critical, `Hit` at 0.55 s); Block (Guard stance); Block Hit One (blocked hit) | Iron Warhammer (placeholder: no club or bat in the packs) |
| **Fists** (Strike) | 80+ **Fist** | Idle; M1 - 1 (attack, `Hit` at 0.43 s); M1 - 5 (critical); Block; Block Hit - 1 | none |
| Shared by both | 80+ Fist, 150+ Dual Axes | Forward Dash (approach), Backward Dash (return), Dash Left / Dash Right (evade), Flinch (hit reaction) | — |
| **Sword** (Slash), for C4 | 150+ **Requiem** (+ 150+ Oathkeeper's Block Hit 1/2) | M1_1…M1_5, M2 (heavy), Dash Attack, Air Attack, Parry, Parried, Blocking | Obsidian Requiem |
| **Spear** (Pierce), for C4 | 150+ **Trident** | M1 1…5, Spear Heavy, Sentinel Air Slam / Up Tilt, dash attack, parrying, parried, blocking, blocked hit, three dashes | Azure Reaver (a spear; Neptune's Trident has 16 emitters) |

The Hammer set reads better than the Gauntlets for a club (overhead and side swings with weight);
the Gauntlets set stays a candidate for a later gauntlet weapon.

**What gets authored**: no clip. The knocked-out state is done in code (the character crumples and
lies on the floor, dimmed: see section 3), which works for every avatar, R6 included; the evade
uses the packs' side dashes. Breathing idle, guard stance, blocked hit, flinch and the dashes all
come from the packs.

## 3. Plan

Presentation and server pacing numbers only; no rule changes (BattleSession untouched).

- **Data** (`ReplicatedStorage/Combat/`): `Weapons` (Club and Fists, both Strike, the Club's
  stats `atk 4`, `hit 0.90`, data only until C9), `CharacterMoves` (each moveset's clips by beat:
  pack, rig, clip, published id, length and the `Hit`/`Reset` marker times), `CombatFx` (effect keys
  → template and particle caps), `CombatSounds` (swing, hit, crit, miss, guard keys → ids).
  `DebugWeapon` (a Player attribute, Studio only) picks the weapon.
- **Clip ids**: a clip's published id once there is one; until then, in Studio only, the client
  registers the clip's KeyframeSequence from `CombatAssets/Animations` with
  `KeyframeSequenceProvider` (a temporary id; verified to work from an ordinary LocalScript in
  Studio Play). With neither (the tests, a live server before publishing), the beat falls back to
  today's procedural moves.
- **The attack beat** (a character's own Attack): approach dash to just short of the target's mesh
  → swing (its `Hit` marker is the contact frame) → hit-stop 4 frames (6 on a critical) → recover →
  dash back to the formation coordinate. On contact: damage number, flinch, effect and sound, FOV
  punch −5° easing back over 0.18 s, trauma along the swing (vertical for the club's overhead,
  lateral for a fist hook). A critical adds a white flash and a brief slow-mo. A miss: the target
  sidesteps (the evade), a whoosh and a whiff line, MISS sliding off.
- **Staggered AoE**: several targets register 4 frames apart, each with its own number, flinch and
  shudder.
- **Character states**: breathing combat idle, guard stance while Guarded (blocked hits play the
  block-hit clip and the shield effect), flinch on a hit, evade on a miss, and the knocked-out
  state: crumple and lie on the floor, dimmed, so a fallen teammate no longer stands in shots.
- **Damage numbers**: a scale pop on appearing, heavier outline; criticals bigger and red with a
  small shake; MISS grey and sliding sideways; a guarded hit blue.
- **Reduced motion**: no hit-stop, shake, slow-mo or flash (the beat simply plays at speed).
- **Server pacing**: a character's Attack adds the dash (`Dash`, replacing `Lunge` for it), every
  hit adds the hit-stop, a critical the slow-mo (C0 report section 4's numbers, re-measured).

## 4. Results: live Studio measurements

Measured in Studio Play on the real server (NorthLookout, two Tung Tung Sahurs against two Wild
Saplings, 60 fps, a Heartbeat trace of the stage character, its clips, the camera's FOV, popups and
effects). Times are from the action reaching the client unless noted.

| Beat | What the trace shows |
|---|---|
| Club attack: dash in | 13.9 studs in 0.35 s (Forward Dash at 1.94×), stopping 4.1 studs from the target's middle |
| Club attack: swing and contact | Hit 1 at 1.38×; contact 0.75 s in, the number on the freeze frame |
| Club attack: hit-stop | swing frozen at 0.604 s into the clip for about 5 frames (0.083 s) |
| Club attack: FOV punch | 52° → 47.9° on the contact frame, back by about 0.15 s |
| Club attack: return | Backward Dash at 1.45×, back on the exact formation spot; next turn opens 2.5 s in |
| Fists attack: dash in | 26.1 studs in 0.35 s from the far slot (Forward Dash at 1.94×) |
| Fists attack: swing and contact | M1 - 1 at 1.02×; contact 0.77 s after the dash starts; `HitFists` and the number on that frame |
| Fists attack: hit-stop | frozen at 0.44 s into the clip for 4 frames (0.067 s) |
| Fists attack: FOV punch and return | 52° → 47.9° → 52° in 0.15 s; retreat 0.32 s after contact, home 0.41 s later (1.50 s dash to home) |
| Enemy hit on a hero | Flinch clip (0.47 s), `HitOnHero`, FOV 50° → 45.8°, a 1.3-stud recoil |
| Critical (Club) | contact 0.78 s; 6-frame hit-stop (0.78–0.89 s); white flash at 0.35 opacity, clear in 0.08 s; slow-mo 0.25× for 0.30 s; FOV 52° → 47.8°, back in 0.13 s; `CRIT -21` popup and `HitCritical` |
| Guard | Guard stance with the Block loop and the GUARD popup |
| Knocked out | Downed stance with `KnockoutDust`: the character lies dimmed, out of its teammate's shots |

The first critical measured was a crafted beat: the real snapshot replayed through a standalone
`BattleView` in Studio Play, since crits are a 2% roll. A second fight, played on autopilot
through the game's own action remote (P1 guarding every turn, P2 attacking, reduced motion on
from the seventh turn), then produced every other beat from real server rolls:

| Beat | What the event log shows |
|---|---|
| A party miss | `MISS` (Miss style) with `EvadeDust` and `Whiff` on the contact frame; the dash still goes in and back |
| A hero's evade | `EVADE` (Evade style) with `EvadeDust` and `Whiff`, twice in a row on the guarding P1 |
| An enemy's critical on a hero | the flash, `HitCritical` and `CRIT -24` (Critical style) on one frame, FOV 45.8° |
| A guarded hit | `GuardBlock` and the number in the Guarded style (blue) |
| Reduced motion | after it switched on, the enemy hits that followed had no field-of-view punch; numbers and effects were unchanged. No party hit landed with it on, so the missing freeze is covered by the headless test only |
| Knocked out, Club | the Downed stance, `KnockoutDust`, the club out of the hand and lying flat on the floor beside the body (its lowest point 0.02 studs above the floor) |
| Phone (iPhone 14 emulator, touch only) | the lower particle caps apply; P1's turn shot holds the club over its shoulder; the downed teammate lies low at the frame's right edge, not standing in it |

Screenshots: `C2_idle_club` and `C2_idle_fists` (the stances), `C2_guard_stance` (P1 blocking
behind the warhammer during P2's turn), `C2_downed_teammate` and
`C2_downed_weapon_drop_staged_cam` (the downed character and its dropped club, from a camera
pointed at it on purpose, since in play it's out of shot), `C2_phone_turn`. Impact frames last
4 to 6 frames, and a Studio capture takes 10 to 20 seconds, so their numbers come from the
per-frame traces above rather than screenshots. The console showed only `Hello world!`.

Particle counts are capped per effect in `CombatFx` (desktop and touch-only caps). The biggest
critical burst is 120 on desktop and 60 on a phone, down from the pack's 260+.

## 5. Animations to publish under PhantomVerse

Nothing was authored: the knocked-out state is procedural (kneel, lie down, dim, drop the
weapon) and the evade reuses the side dashes. Every clip below is a KeyframeSequence in
`ReplicatedStorage.CombatAssets.Animations`, named by its key. Publish each one under the
PhantomVerse group, then put its id in the clip's `id` field in `CharacterMoves.luau`.

| Weapon | Key (the KeyframeSequence's name) | Pack › rig › clip |
|---|---|---|
| Club (Hammer set) | `Hammer.Idle` | 80+ › Hammer Animations › Idle |
| Club (Hammer set) | `Hammer.Attack` | 80+ › Hammer Animations › Hit 1 |
| Club (Hammer set) | `Hammer.Critical` | 80+ › Hammer Animations › Sword Heavy |
| Club (Hammer set) | `Hammer.Guard` | 80+ › Hammer Animations › Block |
| Club (Hammer set) | `Hammer.GuardHit` | 80+ › Hammer Animations › Block Hit One |
| Fists | `Fists.Idle` | 80+ › Fist Animations › Idle |
| Fists | `Fists.Attack` | 80+ › Fist Animations › M1 - 1 |
| Fists | `Fists.Critical` | 80+ › Fist Animations › M1 - 5 |
| Fists | `Fists.Guard` | 80+ › Fist Animations › Block |
| Fists | `Fists.GuardHit` | 80+ › Fist Animations › Block Hit - 1 |
| Shared | `Shared.Approach` | 80+ › Fist Animations › Forward Dash |
| Shared | `Shared.Retreat` | 80+ › Fist Animations › Backward Dash |
| Shared | `Shared.EvadeLeft` | 80+ › Fist Animations › Dash Left |
| Shared | `Shared.EvadeRight` | 80+ › Fist Animations › Dash Right |
| Shared | `Shared.Flinch` | 150+ › Dual Axes Animations › Flinch |

After publishing, test one clip in a live server, not just Studio Play. Studio plays clips the
group owns (and the temporary registered ids) in situations where a live server won't.

## 6. Quality loop

**Critic round 1** (fresh context, the whole diff). No serious defects. Outcomes:

| Finding | Outcome |
|---|---|
| On several targets, the impact (hit-stop, punch, flash) fired on the first slot even when that target was missed | Fixed: it lands on the first critical hit, else the first hit; every other hit pulses on its own frame. Tested |
| A summon's attack used the character's weapon effect, sound and trauma | Fixed: only the character's own blows use its weapon. Tested |
| The struck target recoiled through the hit-stop | Fixed: its recoil and flinch start once the freeze lets go |
| The touch-only particle cap ignored emitters switched on for a duration | Fixed: those count their rate times duration |
| A local copy of `CombatAssets` under `src/` would not be ignored | Fixed: `.gitignore` covers `src/ReplicatedStorage/CombatAssets/` |
| No test drove the clip path | Fixed: a test publishes ids for every clip and checks the idle loop, the frozen swing, flinch, guard and the downed stop |
| A summon's dismissal ran in real time and cut its frozen swing short | Fixed: it waits out the beat's held time |
| A blow along the camera's view loses its direction | Logged in CAMERA_POLISH (camera polish is parked) |
| Cues at the same time ran in no fixed order | Fixed: same-time cues run in the order given |
| `punch()` changed the C1 confirm kick's spring; three `Kicks` values went unused | Fixed: the confirm kick keeps its C1 spring; the unused values are gone |

The live retest found the dropped club sunk 0.65 studs into the floor; it now rests on it
(fixed and tested).

**Playtester round 1** (fresh context, two fights through the real HUD, Club). The dash, contact
timing, hit-stop, FOV punch, popups, guard stance, enemy holds and the knocked-out state all read
well. Outcomes for its findings:

| Finding | Outcome |
|---|---|
| At contact the attacker's body hid its target: the dash ended on the camera's line, 9 px apart on screen | Fixed: the character strikes from the target's side as the camera sees it. In the test the two are 6.2° apart from the camera, up from 0.2°. Live, the attacker blocks 1 of 6 sight lines to its target at contact |
| A guarding hero knocked out by a guarded hit showed a plain hit | Fixed: guarding is read from the snapshot the blow came in on (a knockout clears Bracing). Tested |
| An enemy knockout had no dust | Fixed: every knockout raises `KnockoutDust`. Tested |
| A turn lost to daze has no beat on screen, only the log line | Not C2 (status beats); left for the owner to place |
| The status line under the round banner is faint over a bright sky | Not C2 (HUD styling); left for the owner to place |
| An enemy attacker is on screen only about 0.5 s, and an enemy never moves toward its target | Logged in CAMERA_POLISH (camera polish is parked; enemy approach moves come with later milestones) |
| The results screen got about 4.8 s on a loss | Not changed by C2 (the server's reward window and the final beat's hold are C1/M3 timing); left for the owner |

**Critic round 2** (fresh context, the fixes above). Nothing serious. Outcomes:

| Finding | Outcome |
|---|---|
| After the side strike, the recoil, the hit effect, the shake and a miss's sidestep still followed the old line between the formation spots; a sidestep could step into the attacker | Fixed: they follow the blow's real line, and a sidestep goes across it. Live, a missed target stayed at least 4.1 studs from its attacker over five misses |
| A hero knocked out by the blow snapped back upright for a moment (the deferred recoil reset its root) | Fixed: a blow that knocks out skips the recoil and flinch; the fall owns the body. Live, the root never rose back to standing height |
| No test put a critical on a later target than a plain hit | Fixed: tested (the freeze and flash land on the critical's frame) |
| CLAUDE.md said the attacker "never" hides the reaction | Fixed: "rarely" |
| The strike side is a near-tie for one slot pairing; either side reads | Left as is: both sides keep the target in view |
| A late joiner would see dust on creatures already down | Left as is: nobody can join a fight in progress |

The recoil skip and the sidestep direction aren't tested headlessly: the fake Roblox lands tweens
at their end, so their paths can't be sampled there.

