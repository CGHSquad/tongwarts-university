# TungWarts University (working title)

A Roblox turn-based social RPG — a Wizard101 x Persona hybrid where players attend
a school, build social links, and fight in party-based, initiative-driven turn-based
combat using summoned "BrainRot" meme characters (e.g. Tung Tung Sahur).

## Source of truth for design

**Read `docs/GDD.md` before working on any gameplay, combat, UI, or content system.**
It is the full Game Design Document + Development Plan, covering:

- Core concept, combat philosophy, and the party/multiplayer turn model
- Character stats (Persona-style stat block split between player and summon),
  Mana/Energy, and the Wizard101-inspired pip resource system
- The MVP feature cut (Must/Should/Could/Do-Not-Build-Yet)
- The full development roadmap (Phase 0 through Post-launch)
- Team structure and recommended Git/Rojo workflow
- Technical architecture (Roblox Studio, Luau, DataStoreService, RemoteEvents)
- Turn-based combat architecture in detail (battle state, turn management,
  multiplayer sync, combat depth tiers)
- Economy, retention, Roblox Discovery/growth strategy, risk analysis
- The launch school (TungWarts University — Tung Tung School: Strike melee + Wind
  element) and the four Tung Tung Sahur summon variants
- The finalized initiative rule: a per-battle roll + Agility modifier (not a strict
  Agility sort) — see the "Combat philosophy" and "Step 6" sections

This file is exported from a living design doc maintained outside this repo. When the
design changes there, `docs/GDD.md` gets re-exported and replaces this file wholesale —
treat it as the current source of truth, not something to hand-edit here.

## Working notes

- This is a first Roblox project for a 5-person team — keep scope aggressively
  aligned with the MVP cut in `docs/GDD.md`'s Step 2 unless told otherwise.
- Server-authoritative architecture throughout: the client renders and requests,
  the server validates and decides. See the GDD's Step 5/6 for the specifics.

## Code layout

- Rojo project: `default.project.json` maps `src/ServerScriptService` (server-only),
  `src/ReplicatedStorage` (shared data/types), `src/StarterPlayerScripts` (client UI/visuals) and
  `src/ReplicatedFirst` (loading screen). The map (Workspace) is NOT in Rojo: it lives in the Team
  Create place ("Midnight Mushroom!") and is edited there. Scripts and data are only edited in `src/`;
  if a teammate edits them in Studio, capture that with `rojo syncback` before the next sync.
  Rojo is pinned in `rokit.toml`. Setup and playtest steps are in `README.md`.
- Combat prototype (GDD Phase 1): all rules live in `ServerScriptService/Combat/BattleSession.luau`
  (pure Luau, no Roblox APIs); `BattleDirector.luau` starts fights and runs turn timers;
  `BattleServer.server.luau` is the entry point and network edge. Fights start in the overworld
  (`ServerScriptService/Overworld/`): `Overworld.luau` moves the enemies in `EnemySpawns.luau` and
  starts a fight when a player touches one, and `Encounter.luau` decides who struck first (the
  bonus opening turn, passed to `BattleSession:rollInitiative`). Tuning and content are data in
  `ReplicatedStorage/Combat/` (`CombatConfig` holds every formula's numbers; `Abilities`,
  `Summons`, `StatusEffects` are content); `BattleTypes.luau` defines what the server sends clients.
- On the battle stage (`StarterPlayerScripts/Combat/BattleView.luau`), each player's party member
  is their own character, always on the field. Its summon materializes behind it (Stand/Persona-
  style) only for an ability in its own list, then dismisses; the universal moves (`universal` in
  `Abilities`: `Attack` and `Guard`) are the character's alone. Enemies are just their creature.
  This is presentation only: summons still own every stat, HP and Mana.
- Combat overhaul (plan and decisions in `docs/combat-overhaul/C0_REPORT.md`). C1 added the
  presentation layer under `StarterPlayerScripts/Combat/Presentation/`: `Sequencer` (a timeline of
  cues per beat that owns what it creates and reports when the stage is busy), `BattleCamera`
  (critically damped springs between `Shots` poses, with sway, shake, FOV punch and whip roll, all
  scaled by the reduced-motion setting), `Shots` (pure CFrame math per beat) and `Transition` (the
  battle-start swirl). Every camera number (FOV, Dutch tilt, offsets, sweep times, the enemy return
  style) is in `Presentation/CameraSpec.luau`, aligned to the owner's `docs/combat-overhaul/CAMERA_SPEC.md`
  (section 7's state matrix) with the owner's playtest feedback on top: moves between shots are
  cuts or sweeps of at most 0.25 s, holds stay long. The HUD tells the view what the player is
  looking at on their turn (`onFramingChanged`: ring, skill list, a target) and `BattleView:setFraming`
  frames it: the skill list gets a micro-push and the camera's own depth of field (off on low
  graphics quality), one enemy a tight low shot with a truck between targets (the other enemies'
  plates stay pinned to the HUD box's edge so they can still be tapped; a plate the box pushes onto
  its own enemy's head goes beside it; plate offsets are an exact back-projection of their pixel,
  written in the spot's own frame (the engine applies `StudsOffsetWorldSpace` in the Adornee's frame,
  and the spots are turned; the tests read it back with `PointToWorldSpace`),
  and the overlay writes its box as BoxLeft/Top/Right/Bottom attributes on its folder), one ally
  chest-up. Any move that turns the camera more than 90 degrees is a cut (a target truck excepted).
  Heals and buffs open on the caster and cut to the recipient (lifting) or hold a party overhead;
  an enemy's attack cuts over the targeted hero's shoulder, then to the hero on impact.
  `ReplicatedStorage/Combat/Pacing.luau` gives the seconds the server waits
  after each action (`CombatConfig.ResolvePauseSeconds` plus `ResolveExtraSeconds` per beat);
  BattleDirector waits exactly that and the client treats it as its budget, which the tests'
  observer checks on every turn. `UI/Core/Motion.luau` reads Roblox's reduce-motion switch
  (`GuiService.ReducedMotionEnabled`) or a `ReducedMotion` attribute on the LocalPlayer (debug).
  The HUD holds the command ring while the stage is busy, at most `CombatHUD.RING_WAIT_CAP`;
  BattleClient mirrors the stage's `StageBusy` / `StageOwned` as attributes on PlayerGui for the
  tests. Clip, sound and effect ids stay in data modules, never in BattleView. The Sim projects
  world points through the client's camera (`Camera:WorldToViewportPoint`, a pinhole like the
  engine's) and gives animation tracks a length when a test sets `sim.clipLengths[rbxassetid]`,
  so plate placement and clip compression run headlessly; the C1 tests pin the shots, the
  reduced-motion setting, Pacing, the ring gate and the plates' HUD box. Enemy beats hold on their
  outcome (`CombatConfig.EnemyHoldSeconds`) and ease back (`EnemyReturnSeconds`); a clip whose
  length isn't loaded yet is stopped at its beat's budget. Every critic and playtester pass also
  checks: can the player clearly see the outcome of every action (who was hit, for how much, what
  changed) before the camera moves on, on enemy turns especially.
- Playtests can field other party summons without a code change: set a `PartySummons` attribute
  on ServerScriptService (e.g. `"TungTungGroveKeeper,TungTungSahur"`) before the fight starts;
  BattleServer reads it per fight, in Studio only (the Grove-Keeper has the only heal and party
  buff today). The Sim's `RunService:IsStudio()` answers true unless a test sets `sim.isStudio = false`.
- After changing combat numbers or rules, run `lune run tools/simulate-battles` (Lune is pinned
  in `rokit.toml`) to see win rates per party comp, what each role does, and how Guard gets used.
  "turtle" play (guard whenever it's likely to be attacked, stacking Guard's damage cut) must keep
  losing to "sensible" play. Guard gives no Mana (GDD Step 6), so sensible play currently never guards.
- Before pushing gameplay or UI changes, run the headless tests from the repo root:
  `lune run tests/run` (about eight minutes; `quick` takes under two, and a test-name filter is an option, see
  `tests/run.luau`). They build the place with Rojo and play it on a fake Roblox
  (`tests/Sim.luau`), with bots using the real UI. When behavior changes on purpose, update the
  tests that pin it down. They can't check visuals; those need a look in Studio.
- All scripts are `--!strict` Luau; keep them free of type errors. `lune run tools/typecheck` checks
  `src/` with luau-lsp (pinned in `rokit.toml`) against Roblox's API and the Rojo sourcemap.

## Art source assets

- The pipeline moved: art now gets imported and rigged **directly in Roblox Studio**
  (mesh + animation FBX both imported there), not staged as loose files in this repo
  first. A session with access to the team's Studio place (e.g. through a Studio MCP
  connection) may be able to work with an already-imported summon's mesh, rig, and
  animations straight from Studio, without needing anything checked in here.
- `art-source/Summons/<id>/` (mirroring `Summons.luau`'s `id` field, e.g.
  `art-source/Summons/TungTungSahur/`) still holds the **first** batch of raw
  source files (mesh, rig, animations, textures) checked in before this shift. Treat
  them as historical/reference only, not a current mirror of what's imported in
  Studio — they are not being kept in sync with Studio going forward, so don't assume
  a summon's art-source folder reflects its latest imported state, and don't rely on
  its absence to mean a summon hasn't been imported yet.
- Whatever the source, the rule stays the same: once a mesh/animation is imported and
  uploaded in Studio, its resulting asset ID (`rbxassetid://...`) belongs in that
  summon's entry in `Summons.luau` (or a new field there) — not hardcoded into
  `BattleView.luau` — so content stays data-driven like everything else in
  `ReplicatedStorage/Combat/`.
- Wired so far: the four Tung Tung archetypes. Each rig (skinned mesh + AnimationController,
  facing -Z) is saved from Studio as `src/ReplicatedStorage/SummonModels/<id>.rbxm`, which Rojo
  syncs into `ReplicatedStorage.SummonModels`; its `art` entry in `Summons.luau` names the model and
  holds its stage height, clip IDs by beat (idle/attack/death/walk) and, while the uploaded clips
  still carry a stray hip offset, a `groundOffset`. A summon with no `art` (e.g. `WildSapling`)
  stays a colored block. Missing clips: the Elder's idle/death, all of the Grove-Keeper's.

## UI work

- The UI handoff (spec, screen-by-screen behavior, asset-sheet prompts, approved mockups) lives in `docs/ui/`: `UI_HANDOFF.md` (read section 16 first, it reconciles the spec with this repo), `ASSET_PROMPTS.md`, `mockups/S1`-`S7`, and `M0_REPORT.md` (the approved plan: conflicts, folder layout, safe zones, testing, assets). `tools/cut_sheet.py` cuts generated asset sheets into transparent PNGs. Only milestones 0-3 (foundation, skill list, combat HUD, results) are in scope for now; the mockups are style/layout references, not pixel specs.
- Where the new UI lives (Milestone 1): data in `src/ReplicatedStorage/UI/` (`Theme`, `Strings`, `Flags`, `Assets`, `UITypes`, `MockData`; no Roblox API calls, so the Lune tests require them too) and code in `src/StarterPlayerScripts/UI/` (`Core/` Layout, Gui, Fallbacks, Input, ScreenManager, Audio; `Components/`; `Screens/` (M2: `CombatHUD/` is S1, the combat screen, with its `Widgets`, `CommandRing`, `EnemyOverlay`, `OverworldNotice` and flag-gated `Stamps`; `SkillList/` is S7, with the enemies' status tags on their plates, a recent-actions feed of the last log lines (two, wrapped, under the party cards) and the ring's hover/hold descriptions; M3: `Results/` is S6, opened by the combat screen in the reward phase, with the "Returning in N..." countdown in place of CONTINUE (R24) and mock rewards from `MockData.reward` until the server has a reward payload (Q3)); `Preview/` the Studio harness and safe-zone overlay). `ReplicatedStorage/UI/Bindings` turns a snapshot into the view-models the screens render and mirrors the server's targeting/affordability rules as a filter (R22); `Core/Controls` turns the touch controls and Sprint button off while in a fight (R21). Rules that every screen and component follow: all text through `Strings` (the resource is Mana), every image through `Assets` by key with a drawn fallback when the id is empty, sizes in design pixels at `Layout.DESIGN` (a phone) scaled up by the root `UIScale`, nothing in `Layout.KEEP_OUT`, tap targets at least 48 px, and no game rule computed on the client. Flags (`Flags.luau`) are all off. `BattleClient` runs this HUD; the old `BattleUI` is gone (Q1, parity), so every headless test drives the new screens. `lune run tests/run quick M2` runs the HUD's own tests (a real fight through the ring on the fake Roblox, included).
- Preview the components and every mock state in Studio during Play, from the command bar:
  `require(game.Players.LocalPlayer.PlayerScripts.UI.Preview.Harness).open(game.Players.LocalPlayer.PlayerGui)`
  (or set `Flags.UIHarness`). Its HUD button swaps the gallery for the real combat screen and skill list on the current mock state (Stamp forces ONE MORE! / ALL-OUT, which have no server source); the enemy plates need a battle stage, so they only show in a real fight. The layout tests in `tests/run.luau` open the same harness on the fake Roblox and measure it with `Layout.resolve`, since Lune has no `AbsoluteSize`. Lune only resolves an instance reference (a BillboardGui's `Adornee`) within one tree, so the Sim keeps its PlayerGui inside the client DataModel, and like Roblox it clears that PlayerGui of everything but opted-out ScreenGuis when the character respawns (the HUD's enemy-plate folder is rebuilt when that happens). Two Studio findings: BillboardGuis with `AlwaysOnTop` never appear in the MCP screen capture (the enemy plates keep it on; from the fixed battle camera nothing sits in front of them anyway, checked by raycast), and the enemy plates are placed inside a box clear of the HUD (between the status line and the feed, the ring column and the party column), and plates that would overlap are displaced below or beside each other.
