# C0 — Combat overhaul audit and plan (report only, no code)

Date: 2026-10-09. Branch `main` at 353ecea. Sources read: `CLAUDE.md`,
`docs/GDD.md` (every section the brief named), the combat code (`BattleSession`, `BattleDirector`,
`EnemyAI`, `BattleView`, `BattleClient`, `CombatConfig`, `Abilities`, `Summons`, `StatusEffects`,
`EnemySpawns`, `Overworld`, `Encounter`), the HUD under `src/StarterPlayerScripts/UI/`, the tests and
the simulator, and the design workbook. The workbook was read from the Excel export
(`Tungwart University.xlsx`: Legend & Rules, LevelCurve, PlayerGear, Base, Elder, Sapling,
Grove-Keeper), not from the live Google Sheet, which doesn't load reliably here. The export is the
sheet source from now on. Note: the only export on disk at the time of the corrections (14:19) is
byte-identical to the one first read; the Wind Ward wording below follows the owner's statement
that the fresh sheet describes a single break behavior, not the file's older rows.

Sections: 1 tools I actually have · 2 audit of stage, camera and animation code · 3 camera
proposal · 4 presentation sequencer and server pacing · 5 animation, sound and VFX inventory ·
6 HUD pieces to re-check · 7 critic and playtester loop · 8 C6 kit mechanics map and flags ·
9 C7 affinity profiles (need your approval) · 10 data shapes C5–C9 · 11 sheet vs GDD vs code
disagreements · 12 simulator baseline · 13 decisions I need from you before C1 and C5.

---

## 1. Tools I actually have

| Tool | Status | What it gives us |
| --- | --- | --- |
| Roblox Studio MCP | Connected to **"Midnight Mushroom!"** (placeId 124999635119033), Edit mode. Tools: `execute_luau` (Edit/Client/Server VMs), `start_stop_play`, `screen_capture`, `get_console_output`, `user_mouse_input` / `user_keyboard_input`, `search_asset` / `insert_asset`, `inspect_instance`, `search_game_tree`, `script_read/grep`, a Studio-side `subagent` (explore / screen_capture / unit_test), and skills (`rbx-device-simulator-lua`, `rbx-debug`, `rbx-perf-profiling`). | Live playtests, captures, device emulation, asset search. Known limits (from earlier sessions): captures never show `AlwaysOnTop` BillboardGuis; `execute_luau` runs in its own VM (can't monkey-patch live modules); each call costs 5–20 s so both party moves must go in one input batch; `VirtualInputManager` is not permitted; HttpService is off in the experience. |
| Place ownership | `game.CreatorType = Group`, group **6222756 "PhantomVerse"**. Group inventory is searchable (models found: SAHUR, Sahur Bat, Sahur Death, several T-Pose rigs). `search_asset` has no Animation type filter, so I can't list the group's uploaded clips from here. | Animations must be published under this group. |
| Animation upload | **I cannot publish animations from the MCP.** Studio only publishes KeyframeSequences through the Animation Editor's dialog (or `Plugin:SaveSelectedToRoblox`, which `execute_luau` has no plugin context for). What I *can* do: build a `KeyframeSequence` programmatically on the in-place rigs and call `KeyframeSequenceProvider:RegisterKeyframeSequence` for a **temporary id that works in Studio Play** (good enough for every critic/playtester round), and drop the same sequence into the rig's `AnimSaves`. **Agreed flow (confirmed by you):** per milestone I park the clips in `AnimSaves` and hand you their names; you publish them from the Animation Editor directly under the PhantomVerse group (owner = group), with no per-animation permission steps, and paste the ids back; I put the ids in the data modules. Each handoff will remind you to **test one published clip in a live server**, not only in Studio Play, because `RegisterKeyframeSequence` ids only exist in Studio. |
| Rigs in the place | Workspace has the four authoring rigs `SAHUR`, `SAPLING`, `ELDER`, `GM` (Grove-Keeper), each a skinned mesh with `AnimationController` and an `AnimSaves` ObjectValue. **Every AnimSaves is empty**, so the Grove-Keeper attack that `CLAUDE.md` says "exists in Studio's animation saves" is no longer in the place. Whoever uploaded it may still have its asset id; otherwise it gets re-authored. `ReplicatedStorage.SummonModels` holds the four `.rbxm` rigs (Sahur 34 bones, Sapling 28, Elder 52, GK 52), none with Animation objects. Place scripts match the repo byte-for-byte modulo CRLF (BattleView, BattleSession, Summons checked), so Rojo has synced recently. |
| Blender MCP | Connected: **Blender 5.2.2 LTS**, addon 1.8, `execute_blender_code` (full bpy), `look`, `get_scene_info`, FBX import and export both available. Asset libraries and 3D generators are all off. The open scene is an unrelated R15 avatar cage armature (51 bones, `Root/HumanoidRootNode/LowerTorso/...`), useful as an R15 animation rig. | I can script clips (keyframe bones, export FBX). The only Tung Tung source FBX in the repo is the **Sahur** (`art-source/Summons/TungTungSahur/T-Pose.fbx` + 4 clips). Elder, Sapling and Grove-Keeper FBX are not in the repo, so Blender clips for those need the team's FBX, or I author them in Studio directly (see §5). |
| Free audio | `search_asset` on the Creator Store with `priceFilter=free` works (e.g. five free "swing" clips found under 3 s). | Sound keys can be filled with real ids during C2 and inserted/previewed in Studio. |
| Lune / luau-lsp / Rojo | `lune 0.10.5`, `luau-lsp`, `rojo` all on PATH via `~/.rokit/bin`. `lune run tools/simulate-battles 600 1` ran clean (baseline in §12). | Tests, typecheck and simulator run locally. |
| Google Sheets MCP | Available, but I used the attached Excel export as instructed. | — |

## 2. Audit: stage, camera and animation code today

**Stage** (`BattleView.luau`): a bare 80×60 grass slab at `(0, 0, -700)`, party on −X, enemies on +X,
slots 9 and 14 studs from center and 10 studs apart in Z. Confirmed in Studio: **zero parts and zero
terrain voxels within 100 studs of the stage center** (the camera can clip nothing but the floor,
and there is also nothing to look at: the backdrop is sky and the horizon). Lighting has Sky,
SunRays, Atmosphere, Bloom and **DepthOfField**; DoF will blur whatever a close over-the-shoulder
shot doesn't focus on, so the battle camera must set/clear it.

**Camera**: one fixed `Scriptable` CFrame at `(0, 20, 40)` looking at `(0, 3, 0)`, set once per
battle (`_setBattleCamera`), restored to `Custom` after. No FOV changes, no motion. Tests only check
`CameraType` is Scriptable in a fight and Custom outside (`tests/run.luau:756,774`), so a moving
camera breaks no test.

**Animation**: summons have idle/attack/death/walk clip ids in `Summons.art.animations`
(Sahur and Sapling complete; Elder attack only; Grove-Keeper none, the wilds borrow Sahur's idle,
walk and death). `BattleView.playAttackClip` speeds a clip up so it fits `ATTACK_MAX_SECONDS = 1.6`
and times the hit to `attackImpact` (default 0.5). The player's character has **no clips at all**:
a 4-stud `nudge` tween lunge, a `flinch` that rotates Waist/Neck joints by code, and a copied avatar
with its Animate script stripped (so it stands in bind pose). Enemies' creatures swing their clip
and recoil by tween. Popups are BillboardGuis on the Spot with `Debris`. Everything is tween-and-
`task.delay` based with no central owner, so cancellation on leave/respawn is per-figure
(`appearances` counter) and there is no notion of "the sequence is finished".

**Pacing** (`CombatConfig` / `BattleDirector`): `InitiativeRevealSeconds 3`, `EnemyThinkSeconds 1.25`,
`ResolvePauseSeconds 1.5` (one fixed pause after every action), `TurnTimeoutSeconds 30`,
`ResultScreenSeconds 8`. The client plays the action when the snapshot carrying `lastAction`
arrives, so animation time is bounded by 1.5 s minus latency. The HUD opens the ring the moment the
next "input" snapshot arrives, regardless of what the stage is still doing.

**Where the Atlus feel is currently lost**: static camera, no character animation, no hit-stop,
one popup style, fixed 1.5 s cadence, no battle-start transition, and a results screen that opens
over the same wide shot.

**Reduced motion**: `Theme.Motion.reduced` exists and `Theme.motion()` scales UI durations, but
nothing sets it. There is no settings surface. Proposal: a tiny client `Motion` module reads
`UserGameSettings.ReducedMotion` (pcall; Lune lacks it) plus a `ReducedMotion` attribute on the
LocalPlayer as a debug override, and both `Theme.Motion.reduced` and the sequencer's shake / sway /
flash / slow-mo / FOV-punch amplitudes read from it (cuts and dashes stay, amplitudes go to 0).

**Tests/Sim**: `Sim.luau` fakes `Heartbeat`, `TweenService` (tweens jump to their end), `Debris`,
`task.delay`, `AnimationTrack` (logs Play/Stop, `Length` stays 0) and `Camera.ViewportSize`; it does
**not** fake `RenderStepped`/`BindToRenderStep`, `Lighting` post-effects behave as plain instances,
and there is no `SoundService`. The sequencer must therefore drive on `Heartbeat`, and I will extend
the Sim with a `SoundService`/`Sound` play log and a camera-shot log so tests can assert "no
tween/VFX left after resolve" and "camera shot per phase".

## 3. Camera proposal (multiplayer)

Every client owns its own camera; the shot is a pure function of (phase, actor, local player,
lastAction), so two players see different but consistent framings and nothing is replicated.

| Beat | Shot | Notes |
| --- | --- | --- |
| Battle start | Full-screen **swirl/iris wipe** in school colours (Roblox can't capture the live frame, so a true Persona "shatter of the screenshot" isn't possible; a stylised shard overlay is), then a **sweep**: dolly from behind the enemies, across the stage, to behind the party, ~1.8 s, while the initiative reveal is on screen. Settles into the first actor's shot. | Needs `InitiativeRevealSeconds` 3 → 3.5. |
| My turn (input) | **Low over-the-shoulder** behind my acting character's right shoulder: `root + right 2.4, up 2.2, back 6.5`, looking at a point between the character's head and the enemy centroid, FOV 60. The character sits in the lower-left third, enemies centre-right, above the HUD's bottom plate and left of the party column. | Matches the HUD: ring on the left over/near "me", enemy plates in the middle, party cards over empty background on the right. |
| Teammate's turn | Same OTS shot behind the **teammate's** character (Persona goes behind whoever acts), pulled back ~30% and 1 stud higher so my own character stays in frame when geometry allows. The status line already says "X's turn". | Alternative considered: a wide spectator shot. Rejected: it reads as "not my game"; OTS keeps you in the fight. |
| Enemy turn (think) | **Offset frontal** on the acting enemy: camera on the party side, low (y ≈ 2.5), 40° off its facing, enemy at the right third, its likely target (taunter or lowest HP; purely for framing, taken from the snapshot) soft in the left foreground. | Holds for `EnemyThinkSeconds`. For C8 bosses the camera **holds here through the whole wind-up turn**, slow push-in, no cut. |
| Confirm (mine) | **FOV punch** 60 → 68 → 56 over 0.18 s and the ring collapses, played **optimistically on confirm** before the server answers (snap back if the server refuses). | The "input feels instant" rule. |
| Attack travel | Camera tracks the dash from behind (lead 0.6 stud), no cut. | |
| Impact | Camera **shake** (±0.25 stud, 0.25 s, decays), **hit-stop** 70 ms (clip speed 0, tween paused), crit: 120 ms + brief slow-mo 0.35 s at 0.35 speed + white flash. | All amplitudes × motion scale. |
| Resolve | **Whip-pan** (0.22 s, ease-in-out, slight roll) back to the next actor's shot. | |
| Enemy's hit on us | Cut to over-the-enemy's-shoulder toward the target for the swing, then the target's reaction shot (flinch/guard/evade) from the front-low. | |
| Summon cut-in (C3) | Cut to a tight low shot on the character; summon materialises behind/above; flash; cut to the ability's travel shot. | |
| KO | Brief hold on the fallen figure (0.6 s) before the whip-pan. | |
| Victory | Slow dolly-orbit around the party with summons out in idle, FOV 50 → 55, 2.5 s, then the S6 results open over it (they already take over the screen; the camera keeps drifting underneath). | Defeat: slow tilt down to the floor. |
| Idle sway | Perlin drift ±0.12 stud / ±0.35° at ~0.2 Hz on any held shot. | Off under reduced motion. |

Guards: camera y never below 1.5 above the floor, a raycast from focus to camera that pulls the
camera in if anything (future stage dressing) sits between, and `DepthOfField` disabled for the
fight and restored after. Transitions use a critically damped spring (not `Quad` tweens) so they
are snappy and never floaty, with cuts (no interpolation) for shots more than ~25 studs apart.

**Stage spacing fix**: enemy slots move from 10 studs apart to ~14 (Z) with slot 2 one stud back,
and the stage floor grows to 100×70. From the OTS shot both enemy plates then clear each other at
phone scale; `EnemyOverlay.stagger` stays as the fallback and gets re-run per frame while the camera
moves (today it only runs on snapshot updates).

## 4. Presentation sequencer and server pacing

**Sequencer** (`StarterPlayerScripts/Combat/Presentation/Sequencer.luau`, client only): turns each
snapshot transition into a timeline of cues on `Heartbeat`: `cut`, `shot` (spring to a camera pose),
`clip` (play a track with a target duration; speeds up if the clip is longer), `move` (dash/return
on a spring), `hitStop`, `slowMo`, `shake`, `flash`, `popup`, `sound`, `vfx`, `wait`. A sequence
owns every instance and connection it creates (a maid) and the view calls `sequencer:cancel()` on
battle end, leave, respawn and new battle, which is what makes "no orphaned tweens/VFX after
resolve/death/leave/respawn" testable: a test asserts the sequencer's owned set is empty and the
camera is back to `Custom`. Each later milestone registers **beat sets** by ability kind /
`damageType` / weapon type (`Presentation/Beats/Strike.luau`, `Summon.luau`, `Slash.luau`,
`Pierce.luau`, `Charged.luau`), all data-looked-up (clip ids from `Summons.art`, character clip
ids from a new `ReplicatedStorage/Combat/CharacterAnimations.luau`, sound keys from
`ReplicatedStorage/Combat/Sounds.luau`), nothing hardcoded in `BattleView`.

**Ready gate**: the HUD only shows the ring when `sequencer.busy == false`, with a hard cap of 0.6 s
past the server's turn start so a slow client can never block input (the turn timer is server-side
anyway). The sequencer exposes a `Busy` attribute on `PlayerScripts` so the playtester can log it.

**Server pacing**: `ResolvePauseSeconds` stops being one number. A pure-data module
`ReplicatedStorage/Combat/Pacing.luau` gives `Pacing.resolveSeconds(action, results)` and both sides
use it: `BattleDirector._afterTurn` waits that long; the client treats it as its budget and
compresses clips to fit. Starting values (to be measured by the playtester, not guessed):

| Component | Seconds | Why |
| --- | --- | --- |
| Base after any action (whip-pan + settle + latency pad) | 0.9 | was the whole 1.5 |
| Melee dash (approach 0.35, swing 0.45, recoil 0.3, return 0.45) | +1.55 | C2 |
| Hit-stop / crit slow-mo | +0.08 / +0.4 | C2 |
| Miss | −0.25 | nothing to sell |
| Summon cut-in | +0.9 | C3 |
| All-target ability | +0.3 | second impact |
| Knockout | +0.8 | hold on the fall |
| Boss charge release | +1.2 | C8 |
| Buff / heal / status | +0.6 | cast + glow |

A club Attack therefore pauses ~2.5 s (today 1.5), a Guard ~1.5, a summon Strike ~3.4, a KO on a
crit ~3.9. `EnemyThinkSeconds` 1.25 stays (it is now the enemy shot's hold). `InitiativeRevealSeconds`
3 → 3.5. `ResultScreenSeconds` 8 unchanged (2.5 s pose, 5.5 s results). None of this touches a rule;
BattleSession is unchanged. The headless suite's virtual clock will run the longer pauses, so the
8-minute suite grows (estimate +30%); if that hurts, the Sim can run with a `Pacing` override.

## 5. Animation, sound and VFX inventory, with how each gets made

Authoring legend: **Studio-KFS** = I build a `KeyframeSequence` by code on the in-place rig
(bone poses), register a temporary id for tests, park it in `AnimSaves`, you publish under the
group. **Blender** = I keyframe in Blender via bpy and export FBX; you import and publish.
**Roblox default** = a Roblox-owned public animation id (free to use, no upload), as a placeholder.
**Human pass** = quality-critical, recommend an animator touches it before launch.

**C1 (camera and flow)**: no new clips. VFX: swirl/iris wipe overlay (UI, school colours), initiative
sting. Sounds: `battle_start`, `whip_pan`, `initiative_reveal`, `turn_open`.

**C2 (Strike attack and impact feel)**:

| Asset | Who | Make it with | Notes |
| --- | --- | --- | --- |
| Combat idle (breathing) | player character (R15, any avatar) | Blender on the R15 armature already open (scripted sway + breath) | small, loopable, safe to script |
| Club swing | player character | **Roblox default `ToolSlash` as placeholder**, then **human pass** | the one clip that sells C2; a scripted swing will read stiff |
| Flinch | player character | keep the current joint-rotation code, tuned (fast in, spring out) | no upload needed; works on every avatar |
| Guard stance | player character | Blender, scripted pose (arms raised, weight back) | |
| Evade (sidestep) | player character | Blender, scripted (one hop back, lean) | |
| Dash / return | player character | code (spring move), no clip | |
| Enemy flinch | summons / creatures | Studio bone recoil by code (Hips/Spine `Transform` kick) | none of the rigs has a hit clip |
| Elder idle, Elder death | TungTungElder | **Studio-KFS** (no FBX in repo); idle = breathing sway, death = topple | currently borrows Sahur's; missing per `Summons.luau` |

VFX: impact burst (one-shot ParticleEmitter, 8–12 sparks), dust puffs at dash start and stop, crit
white flash (ColorCorrection + full-screen frame, 90 ms), slow-mo (track `AdjustSpeed` + sequencer
clock), damage numbers (scale pop, outline; crit bigger/red with a small shake; MISS grey italic
slide-off; GUARDED blue; EVADE white streak), guard arc (semi-transparent cone in front of the
character), evade afterimage (faded clone, 0.25 s). Sounds (keys, filled from the free store):
`swing_club`, `hit_blunt`, `hit_crit`, `miss_whoosh`, `guard_raise`, `guard_block`, `evade_step`,
`ko_fall`, `damage_pop`.

**C3 (summons and polish)**:

| Asset | Who | Make it with |
| --- | --- | --- |
| Grove-Keeper attack | TungTungGroveKeeper | **ask for the already-uploaded id**; else Studio-KFS |
| Grove-Keeper idle, death | TungTungGroveKeeper | Studio-KFS |
| Elder idle, death | TungTungElder | (from C2) |
| Cast pose (heal/buff) | all four summons | Studio-KFS, one short raise-arms clip each (or reuse attack first half) |
| Victory pose | all four summons | Studio-KFS (Sahur could be Blender from the repo FBX) |
| Materialise | all | VFX only: burst ring + motes + flash, refactored out of `SummonFX.client.luau` into a shared `VFX` module |

VFX: summon burst, wind slash projectile (Tor/Gator/Clap Gust), heal motes, buff/debuff arrows
(up gold / down crimson), status-applied badge. Sounds: `summon_burst`, `summon_dismiss`,
`cast_wind`, `heal_chime`, `buff_up`, `debuff_down`, `victory_sting`, `defeat_sting`.

**C4 (Sword and Spear)**: sword slash (Roblox default `ToolSlash` placeholder → human pass), spear
thrust (Roblox default `ToolLunge` placeholder → human pass), slash arc VFX, pierce line VFX,
`swing_sword`, `hit_slash`, `swing_spear`, `hit_pierce`. Still missing for all: anything after a KO
(the character just fades); listed as a later nicety.

**C7**: WEAK / RESIST / NULL hit stamps (UI), `weak_sting`, `resist_dull`, `null_clink`. **C8**: boss
charge = idle held at 0.6 speed + rising glow (PointLight + aura emitter) + warning vignette; release
= attack clip at 0.85 speed + heavy shake + `release_boom`; `charge_hum`, `warning_sting`.

**Still missing after C3 (will list again in the C3 PR)**: human-quality club swing; any clip for the
blocky stand-in character (it only lunges); Grove-Keeper walk (overworld); hit/KO clips for
summons (recoil stays procedural).

## 6. HUD pieces to re-check under a moving camera

- **Enemy plates** (`EnemyOverlay`): BillboardGuis on the Spots. `stagger()` projects through the
  camera but runs only on snapshot updates; under a moving camera it must run every frame the
  camera moves (cheap: two `WorldToViewportPoint` per plate). Plates must stay inside the safe area
  when the OTS shot puts an enemy near the screen edge: clamp or hide while off-screen.
- **Target brackets and the WEAK/DOWN tags** ride on the plates; same check.
- **Popups** (`BattleView.showPopup`): adorned to the Spot, but characters now dash away from
  their spot; adorn to the body root instead, and keep them readable with the camera low (they
  rise into the status-line region on a phone: check).
- **BattleView's own party nameplates** are still on (only enemy nameplates were turned off for
  the new HUD, R19); under a low camera they float over the heads in frame. Turn them off; the
  party cards carry the information.
- **Command ring** (left column) will overlap the acting character's body in the OTS shot. That is
  the Persona composition, but the ring's ribbons must stay legible against a moving avatar:
  check contrast, consider the existing `Dim` behind the ring only.
- **Status line / turn-order bar** (top) vs. enemy heads in the enemy-turn shot; **Mana plate**
  (bottom centre) vs. the character's feet; **log feed** (bottom of centre) vs. the enemy plates
  when they stack upward.
- **Results screen** over the victory camera (it dims the scene itself: fine) and the **skill
  list** dim while the idle sway runs underneath.
- **Harness/tests**: the layout tests are pure math at phone, small-phone and small-PC sizes and
  stay valid (screen-space); the plates need a Studio check with the Device Emulator
  (`rbx-device-simulator-lua`) at 844×390 and 1920×1080, with touch controls visible, per shot:
  input, confirm, impact, enemy turn, boss wind-up, victory.

## 7. How I will run the critic and playtester subagents

- **Critic**: one `Agent` (general-purpose) per round with a fresh context. Its prompt contains only
  the milestone spec, the rubric, `git diff main...<branch>` and the `lune run tests/run` and
  `tools/typecheck` output. It is told it may read files but edit nothing, and must return
  findings ranked high / medium / low with file:line and a one-line repro.
- **Playtester**: one `Agent` (general-purpose) with the Studio MCP tools and the driving recipe
  from earlier sessions (click paths, batched `user_mouse_input` for both party moves, results
  recorder, `AlwaysOnTop` capture trick, `GymWildSapling` for a 3-round win). Before it starts I
  push the branch into the place (Rojo plugin connected, or `execute_luau` source push, reverting
  any debug flags afterwards) and start Play. Its recorder: a client-side script injected through
  `execute_luau` that stamps `os.clock()` on every `StateUpdate` phase change, samples
  `Animator:GetPlayingAnimationTracks()` on the stage models and the sequencer's `Busy` attribute
  every Heartbeat, and counts console errors/warnings; it writes CSV into a `StringValue` the agent
  reads back, and captures at the listed beats (turn start, confirm, impact, resolve, enemy turn,
  boss wind-up and release, victory). It reports: turn-to-turn latency, any "input" phase that
  arrived while `Busy`, errors/warnings, and the screenshots.
- Loop: fix → re-run both, at most 3 rounds, stop when no high finding remains. The PR table lists
  every finding with fixed / declined + reason. If a subagent can't reach the Studio MCP (tool
  inheritance) I run the playtest myself with the same script and say so.

## 8. C6 — the kits mapped to mechanics, with flags

Mechanics the GDD table needs (each a data field, none of them exist yet except taunt-as-status and
agility bonus): **(T)** taunt with exemptions (all-target and Charged ignore it); **(P)** passives
(permanent statuses applied at battle start, hidden from the turn countdown); **(B)** buff/debuff
roots as statuses: `damageDealtMultiplier`, `damageTakenMultiplier`, `hitBonus`/`evadeBonus`
(points), `agilityBonus`, 3 turns, refresh-not-stack; **(HP%)** Health costs; **(HPS)** damage
scaled by caster HP share; **(CRL)** crit bonus vs low-HP targets; **(STK)** stacking status with a
cap; **(EVT)** evasion vs a damage type; **(PC)** party-composition bonus; **(BRK)** affinity break
(C7); **(OH)** on-hit reactions (heal when hit, daze the attacker); **(AC)** ailment-chance
multipliers dealt; **(MM)** max-Mana multiplier.

| Archetype | Ability (Lv) | Mechanics | Flags |
| --- | --- | --- | --- |
| Base | Cur (1) | Heal 15+M, 4 MP | — |
| Base | Tor (1) | Wind 12+M, 4 MP | shared with GK: one ability id |
| Base | Brace (5) | B: self `damageTaken ×0.85` 3t, 5 MP | **Cost 5 breaks the table's own "buffs cost 8" rule**; needs its own status id (not Guarja) and it multiplies with Guarja/Windbreak/Guard under the 75% cap |
| Base | Strike One (10) | Strike 12+S, 4 MP | — |
| Base | Wind Ward (15) | BRK: target's Wind Resist/Null → Neutral 3t, 6 MP | built in C7; in C6 **listed but disabled** with a "needs affinities" row note (my choice unless you prefer it left out) |
| Base | Dizzying Gale (20) | P + AC: user's Daze chance ×1.5 | ambiguous whether ×1.5 applies before or after the Luck adjustment and the 90% cap. Proposal: multiply the base chance, then Luck, then cap |
| Base | Clap Gust (25) | Wind all, 6+0.6M, Daze 45% 2t, 8 MP | 45%×1.5 = 67.5% with Dizzying Gale, fine under the cap |
| Elder | Groundshake Taunt (1) | T: 1 turn, 4 MP | "1 turn" = until Elder's next turn (statuses tick at the owner's turn start): one enemy action each in between, which is what you want |
| Elder | Windbreak (5) | B: `damageTaken ×0.6` 2t + OH: attacker Dazed 25% 1t, 6 MP | today's Windbreak is 3t/5 MP; Daze-on-hit is new. Does Luck vs Luck apply to the 25%? Proposal: yes, same ailment formula |
| Elder | Band Aid (9) | not in battle | listed on the summon as menu-only, filtered out of the battle list |
| Elder | Blind Strike (13) | Strike 10+S + B: target Fokanda 3t, 6 MP | **Foka interpretation**: Fokanda lowers the target's hit AND its evasion (so attacks on it land +10 points); confirm |
| Elder | Hardwood Sap (17) | P: `damageTaken ×0.9` | — |
| Elder | All-Defense (21) | P: Guarja applied at battle start, 3 turns | — |
| Elder | Heartwood Stand (25) | T 2t + `damageTaken ×0.5` + OH heal 5% max HP per hit landed, 12 MP | with Hardwood Sap, Windbreak, Guarja and Guard it hits the 75% cap at once; the cap makes Windbreak + Heartwood redundant. Not a bug, worth knowing |
| Sapling | Vital Strike (1) | Strike (12+S)×(0.5+0.7×HP%), HP% 8% | **"8% HP" of max or current?** Only Timber Fall says "current" and "can't KO". Proposal: max HP, and every HP cost leaves at least 1 HP; confirm |
| Sapling | Stick Driver (5) | Strike 12+S, Daze 30% 2t, HP% 10% | same question |
| Sapling | Wake-Up Call (9) | B: self Rileja (`dealt ×1.25`) + Zippja (+4 Agi) 3t, 8 MP | Zippja = today's Tailwind `agilityBonus 4`, reused |
| Sapling | Strike Evade (13) | P + EVT: incoming Strike hit −15 points | **clamp order**: before or after the 50–98% clamp? Proposal: subtract, then clamp |
| Sapling | Dead Wood (17) | Strike 12+Luck, CRL +40% vs targets <30% HP, 6 MP | Fortune: scales Luck |
| Sapling | Grudge (21) | P + STK: +2 Strength per damage instance taken (own HP costs count), 5 stacks | a miss gives nothing; +10 Str at Lv 25 is +42% Strength and Sapling can feed it with its own costs: strong on paper, the HP drain is the check. Watch it in the sim |
| Sapling | Timber Fall (25) | Strike all 8+0.9S + B: Guarnda all 3t, cost 25% of current HP, can't KO | strongest-looking row: AoE + party-wide Defence down + Grudge stack for the price of HP |
| GK | Tor (1) | as Base | — |
| GK | Guarja (5) | B: ally `damageTaken ×0.8` 3t, 8 MP | — |
| GK | Gator (9) | Wind all 8+0.8M, 6 MP | — |
| GK | Sap Mend (13) | Heal 10+0.8M + cure one ailment at 40%+Luck×2%, 5 MP | today's Sap Mend always cleanses; becomes a roll |
| GK | Mana Font (17) | P + MM: max Mana ×1.1 at battle start | — |
| GK | Rilenda (21) | B: enemy `dealt ×0.8` 3t, 8 MP | — |
| GK | Grove Bond (25) | P + PC: Tung Tung allies' damage ×(1.05 + 0.05 per other Tung Tung archetype in the party, max 1.15) | **Sheet says "Attack and Magic +5%" (a stat buff, which would also boost heals); GDD says "deal more damage".** I follow the GDD. With `MaxPartySize = 2` the bonus caps at +10% in practice |

Thin at Level 1 (on paper): Elder has only Groundshake Taunt (no damaging summon skill until Blind
Strike at 13), Sapling only Vital Strike (its 55 Mana is unused until Lv 9), Base and GK have two
skills each. The Level-25 simulator run is the real kit test; the Level-1 run mostly tests pools and
the universal Attack.

## 9. C7 — proposed affinity profiles (wild enemies and the test boss)

Party summons: as the sheet says (Base Strike Resist / Wind Null / Fortune Neutral; Elder Resist /
Null / Resist; Sapling Neutral / Resist / Weak; GK Neutral / Resist / Resist; Slash, Pierce, Fire,
Water, Elec blank → Neutral). The party deals only Strike and Wind in this build (Slash/Pierce via
the debug weapon), so every wild enemy below has at least one weakness **inside Strike/Wind** and
Wind-resistant enemies exist so Wind Ward has a job.

| Enemy | Strike | Slash | Pierce | Wind | Fire | Water | Elec | Fortune (ailments) | Idea |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Wild Sapling | Neutral | Weak | Neutral | **Weak** | Weak | Resist | Neutral | Weak | green, flighty: bends in the wind, easy to daze |
| Wild Tung Tung Sahur | Resist | Neutral | Weak | **Weak** | Weak | Neutral | Resist | Neutral | hardwood shrugs off bonks, dry wood hates gusts |
| Wild Grove-Keeper | **Weak** | Neutral | Neutral | Resist | Weak | Null | Weak | Resist | mossy caster: brittle branches, wind-wise; Wind Ward target |
| Wild Elder | Neutral | Weak | Resist | Resist | Weak | Neutral | Neutral | Neutral | gnarled wall: Wind Ward target; its Strike is Neutral so Lv-1 parties aren't stonewalled |
| Test boss "Grove Warden" (scaled Elder, 16 studs) | Neutral | Resist | **Weak** | **Resist** | Weak | Resist | Neutral | Resist | Wind Resist (changed from Null on approval): Wind Ward still matters, the fight isn't gated on it; Pierce Weak rewards the Spear (C4/C9 debug); ailments mostly bounce |

**Approved 2026-10-09** with the boss changed to Wind Resist / Strike Neutral. Wild Elder stays as
proposed: its only weaknesses (Slash, Fire) are unreachable before C9, it is the "wall", and C7
reports Wild Elder fight lengths specifically. Fire/Water/Elec rows are data only (nothing deals
them). C7 copies this table.

## 10. Data shapes

**C5 (pools, test level, enemy HP)**
- `Summons[id].stats` → `baseStats` (Lv 1, from the sheet) + `ceilings` (sheet Est. Ceiling); a pure
  `Growth.statsAt(summon, level)` = `base + (ceiling − base) × (level − 1) / 98`, rounded to nearest.
  Lv 25 reproduces the sheet's column for all four archetypes (checked: 19/19/23/19/19, 12/15/28/12/19,
  24/12/16/26/21, 12/25/22/19/19).
- `CombatConfig.TestLevel = 1`, overridden by a `TestLevel` attribute on `ServerScriptService`
  (Studio command bar / debug), read when a battle starts; the simulator and tests pass the level in.
- `CombatConfig.Pools = { hp = {135, 650}, mana = {65, 450}, manaExponent = 0.7, floorShare = 0.72 }`;
  RefStat is **derived** from the party roster (highest Lv-1 value and highest ceiling for
  Endurance and Magic: 14→70 and 13→63 today) rather than typed in, so a fifth archetype can't
  silently break it. Verified against the GDD: Lv 1 HP Elder 135 / Base 130 / GK 127 / Sapling 119;
  Mana GK 65 / Base 61 / Elder 58 / Sapling 55 (my values 129.6, 126.9, 118.8, 60.8, 55.2 round to
  the GDD's). Lv 25: HP 261/249/245/230, Mana 186/195/209/178. Lv 99: only the reference archetype
  reaches the school total (Elder 650 HP, GK 450 Mana), as the GDD intends.
- Enemies: `Summons[id].pools = { hp = N, mana = N }` and `level = N`; `pools` wins over the formula.
  Starting guesses for "fights as long as today": Wild Sapling 95/40, Wild Sahur 110/45, Wild GK
  100/55, Wild Elder 140/40 (today 90/95/90/120 HP), boss ~450/120; tuned with the sim in C5.
- `ManaRegenPerTurn = 0`. Refill at battle start unchanged.

**C6 (abilities and mechanics)**
- `Ability` gains `cost: { kind: "Mana" | "HealthPercent", amount, ofCurrent?, cannotKO? }` (replacing
  `manaCost`), `unlockLevel`, `category: "Melee" | "Elemental" | "Fortune" | "Passive"`, `tier`
  (Common/Signature/Rare, data only), `battleUsable` (false for Band Aid), `damageType` extended to
  Strike | Slash | Pierce | Wind | Fire | Water | Elec, `hpShareScaling = { floor = 0.5, slope = 0.7 }`,
  `critBonusVsLowHp = { below = 0.3, bonus = 0.4 }`, `applies = { { status, turns, to = "Target" |
  "Self" | "Attacker", chance? } }` (several per ability: Blind Strike = damage + Fokanda), new
  `kind = "Passive"` (never castable, applied at battle start) and `kind = "Taunt"` folded into
  Status via `drawsAttacks`.
- `StatusDef` gains `damageDealtMultiplier`, `hitBonus`, `evadeBonus`, `healOnHitShare`,
  `onHitAilment`, `tauntIgnoredBy = { "AllTarget", "Charged" }`, `stacking = { max = 5, strengthPerStack = 2 }`,
  `ailmentChanceDealtMultiplier`, `maxManaMultiplier`, `evasionVsType = { Strike = 0.15 }`,
  `partyDamageBonus = { base = 0.05, perOtherArchetype = 0.05, max = 0.15, family = "TungTung" }`,
  `passive = true` (no countdown, not shown as a timer). `ActiveStatus` gains `stacks`.
- Snapshot: `StatusState.stacks?`; `ParticipantState.level`; `ActionResult.selfDamage` (HP costs)
  and `healedOnHit`.

**C7 (affinities)**
- `ReplicatedStorage/Combat/Affinities.luau`: the category list and `CombatConfig.AffinityMultipliers =
  { Weak = 1.5, Neutral = 1, Resist = 0.5, Null = 0 }`, `AffinityAilmentMultipliers = { Weak = 1.5,
  Resist = 0.5, Null = 0 }`.
- `Summons[id].affinities = { Strike = "Resist", Wind = "Null", Fortune = "Neutral" }` (missing = Neutral).
- Break: `Ability.breaks = { element = "Wind", turns = 3 }` → status `Broken_Wind` (generic
  `StatusDef.breaksAffinity = "Wind"`), shown on the plate as a tag.
- `ActionResult.affinity: "Weak" | "Resist" | "Null" | nil`; server keeps `revealedWeaknesses` per
  enemy and sends `ParticipantState.knownWeaknesses`; `Bindings` fills the existing
  `HudParticipant.knownWeaknesses` / `hitsKnownWeakness`; `Flags.ShowAffinities = true`.

**C8 (charged attacks)**
- `kind = "Charged"`: `{ windupTurns = 1, targets = "Enemy" | "AllEnemies", power, scalingStat,
  statRatio, damageType, ignoresTaunt = true }`; `CombatConfig.ChargedAttackMultiplier = 2.5`.
- Status `Charging` with `payload = { abilityId, targetId }`, shown in the snapshot
  (`StatusState.targetId?`) so the HUD can say who is in danger (`Strings.format.charging(boss,
  target)`); on the boss's next turn `beginNextTurn` releases before input, like a lost turn.
- `Summons[id].isBoss`, brain weight for the charged ability; one `EnemySpawns` entry (gym or a
  new arena spot) with `enemies = { "GroveWarden" }`, `look`, `height ≈ 16`.

**C9 (weapons)**
- `ReplicatedStorage/Combat/Weapons.luau`: `{ Club = { type = "Strike", atk = 4, hit = 0.90 }, Sword =
  { type = "Slash", atk = 3.4, hit = 0.95 }, Spear = { type = "Pierce", atk = 4.6, hit = 0.85 } }`
  (±15% of 4; decimals are fine because display is ×10: "ATK 34 / 40 / 46").
- `RosterEntry.weaponId` → `Participant.weapon`; default Club from a server `Loadout` module, debug
  override by a `DebugWeapon` attribute on the Player (Studio only). `Attack.damageType` comes from
  the weapon. `CombatConfig.WeaponAbilityK = { physical = 0.01, magic = 0.006 }`,
  `WeaponAbilityCap = { physical = 0.25, magic = 0.15 }`; `Strings.format.weaponAtk(atk)`.

## 11. Disagreements: sheet vs GDD vs code (none resolved silently)

1. **Grove Bond — resolved (the sheet's reading)**: +5% Strength and Magic for Tung Tung allies,
   +5% per other Tung Tung archetype in the party (teammates' summons count), max +15%, applied
   only to the stats as used in damage and heal formulas, never to max Mana or the pools. The
   GDD's "deal more damage" wording should be updated to match.
2. **Wind Ward — resolved.** The export first read had the Legend's "Ward" rule in two wordings
   (row 62 "actively negates one element's skill", row 63 "strips protection… becomes Neutral")
   and the Base tab saying "Nullifies 1 foe's Wind resistance". The owner confirms the fresh sheet
   describes one behavior, the same as the GDD: an affinity break, the target's Wind Resist or
   Null becomes Neutral for 3 turns, a Weak stays Weak. C7 builds exactly that.
3. **Costs vs the GDD's cost rule — resolved** by GDD commit 353ecea: the table's per-ability
   costs are authoritative and the guide now describes them (plain weak single 4, single with a
   rider 5–6, self light buff 5, weak all-target 6, buffs/debuffs on another target 8, Signatures
   8–12). The data modules copy the table.
4. **HP-cost basis — resolved**: Vital Strike and Stick Driver cost a percent of **max** HP;
   Timber Fall costs 25% of **current** HP; no HP cost can ever KO the user (every HP-cost skill
   leaves at least 1 HP).
5. **Stat-to-effect constants don't fit the 1–99 range — resolved (level-relative)**. The problem:
   `DamageReductionPerEndurance 0.02` caps at 60% once Endurance is 30 (Elder around Lv 28), the
   Agility hit gap pins to the 50% floor mid-game, Luck 48 means 50% crits, the initiative bonus
   outgrows the d20 by Lv 25. Decision: every stat used for a percentage (Endurance damage
   reduction, the Agility hit gap, the Agility initiative bonus, Luck crit and ailment chances) is
   divided by the level's reference value `N(L) = 10 + 38 × (L − 1) / 98` (the Medium-lean curve,
   10 at Lv 1 → 48 at Lv 99) using each participant's own level, i.e. `effective = stat × 10 / N(L)`,
   and the existing constants and caps apply unchanged, so Level 1 numbers stay identical. Damage
   and heal formulas keep raw stats. C5's report shows the percentages flat across Lv 1 / 25 / 99
   per archetype.
6. **Band Aid**: GDD cost "—", sheet "Mana". Moot in battle; data will carry `battleUsable = false`.
7. **Elder has two Signatures** (Windbreak and Heartwood Stand) in both sheet and GDD; the other
   three have one. Just noting.
8. **Evolution tabs refer to abilities not in the Stage 0 kits** (Base "Bark Up" vs kit "Brace";
   Sapling "Splitting Strike"; GK "Tailwind" lean, Tailwind removed). Out of scope for this build,
   but the sheet is inconsistent with itself.
9. **Rounding**: the GDD's Lv-1 pool numbers imply round-to-nearest (129.6 → 130, 118.8 → 119); the
   sheet's Lv-25 stat column also rounds to nearest. Code will round to nearest; flagging because
   floor would give 129/118.
10. **`CLAUDE.md` vs the place**: the Grove-Keeper attack is not in any `AnimSaves` any more (all
    four rigs' saves are empty).
11. **Code vs GDD, already consistent, confirming**: Attack `power 4 + Strength` = the starter club;
    base hit 90% = Club HIT; Guard 72% total vs the GDD's 70–75%; Endurance cap 60%.
12. **Party size**: Grove Bond's "+5% per other archetype, max +15%" assumes 4-member parties;
    `MaxPartySize = 2` caps it at +10%. Not a conflict, a note.

## 12. Simulator baseline (today's rules, 600 battles per party and style, seed 1)

| Party | careless | sensible | turtle | rounds (sensible) |
| --- | --- | --- | --- | --- |
| Sahur + Sahur | 7% | 77% | 2% | 7.4 |
| Elder + Sapling | 3% | 90% | 45% | 8.3 |
| Sapling + Grove-Keeper | 1% | 71% | 13% | 8.9 |
| Elder + Grove-Keeper | 0% | 82% | 17% | 17.8 |
| Sahur + Grove-Keeper | 0% | 80% | 59% | 9.8 |
| Sapling + Sapling | 5% | 51% | 0% | 5.7 |

Sensible play never uses the free Attack (0%) and never guards; turtle loses everywhere (closest:
Sahur + GK, 59 vs 80). "Rounds" are full queue cycles (4 turns each with two-a-side); the C5 report
will add turns. Elder + Grove-Keeper at 17.8 rounds is already the slow outlier and gets slower if
Wild Elder resists Strike, which is why §9 keeps its Strike Neutral.

## 13. Decisions (approved 2026-10-09)

1. **Affinity table (§9)**: approved with the boss at Wind Resist / Strike Neutral / Pierce Weak;
   Wild Elder as proposed; C7 reports Wild Elder fight lengths specifically.
2. **HP costs**: Vital Strike and Stick Driver cost a percent of max HP; Timber Fall 25% of
   current HP; no HP cost can KO the user, for every HP-cost skill.
3. **Stat constants**: level-relative (§11.5): percentage stats divided by `N(L) = 10 + 38 × (L − 1) / 98`
   with the participant's own level; constants and caps unchanged; damage and heals keep raw stats;
   C5 shows flat percentages at Lv 1 / 25 / 99.
4. **Wind Ward**: left out of Base's kit until C7 (not listed-disabled).
5. **Grove Bond**: the sheet's reading, +5% Strength and Magic (+5% per other Tung Tung archetype,
   teammates' summons count, max +15%), on the stats used in damage and heal formulas only.
6. **Grove-Keeper attack clip**: assumed gone; re-authored in C3 unless an id turns up from the
   group's Creator Dashboard. Upload flow as in §1.
7. **Reduced motion**: `UserGameSettings.ReducedMotion` plus a debug attribute, no in-game toggle.
8. **Boss placement**: a single arena spot on the original grass overworld, away from the regular
   enemies' routes and the post-battle return points.
9. Also approved as proposed: Dizzying Gale multiplies the base chance before Luck and the cap;
   Luck vs Luck applies to Windbreak's Daze; Fokanda lowers both hit and evasion; Strike Evade
   subtracts before the 50–98% clamp. Studio playtests of the new kits run at `TestLevel 25`.

Settled earlier: the kit table's costs are authoritative (GDD 353ecea), Wind Ward is a break, and
the animation upload flow (§1). Nothing in this milestone changed code.

## 14. Scope additions after C1 (owner's playtest feedback)

- **C2 gains a knocked-out state for player characters**: a downed pose, or dimmed and out of
  frame, so a knocked-out teammate no longer stands in the survivor's over-the-shoulder shot like
  a ghost.
- **Rubric item for every critic and playtester from C1's review on**: "Can the player clearly see
  the outcome of every action (who was hit, for how much, what changed) before the camera moves
  on?" The playtester checks it on enemy turns specifically.
- Enemy beats hold on their outcome (`CombatConfig.EnemyHoldSeconds`, 0.9 s) and ease back to the
  next actor (`EnemyReturnSeconds`, 0.45 s); both are part of the server's wait for enemy actions.
