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
  `src/ReplicatedStorage` (shared data/types) and `src/StarterPlayerScripts` (client UI/visuals).
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
- After changing combat numbers or rules, run `lune run tools/simulate-battles` (Lune is pinned
  in `rokit.toml`) to see win rates per party comp, what each role does, and how Guard gets used.
  "turtle" play (guard to max Mana, then alpha-strike) must keep losing to "sensible" play.
- Before pushing gameplay or UI changes, run the headless tests from the repo root:
  `lune run tests/run` (about a minute; `quick` and a test-name filter are options, see
  `tests/run.luau`). They build the place with Rojo and play it on a fake Roblox
  (`tests/Sim.luau`), with bots using the real UI. When behavior changes on purpose, update the
  tests that pin it down. They can't check visuals; those need a look in Studio.
- All scripts are `--!strict` Luau; keep them free of type errors.

## Art source assets

- Raw art (meshes, rigs, animations, textures) from the team's art tool lives in
  `art-source/`, organized to mirror `Summons.luau`'s `id` field
  (`art-source/Summons/<id>/`, e.g. `art-source/Summons/TungTungSahur/`). These are
  **not** Rojo-synced or runtime-usable as-is — Roblox needs meshes and animations
  imported through Studio's 3D Importer and uploaded to get asset IDs before anything
  in `src/` can reference them (`rbxassetid://...`). That import/upload step happens
  in Studio, not from this repo.
- Per summon, expect: an optimized mesh (the one to import — check for a note on
  which file is optimized vs. a raw/unoptimized export), a rigged T-pose FBX for
  animation, and an `Animation/` folder of clips (idle, walk/swing/attack, death, etc.
  varies per summon). Textures sit alongside the mesh.
- Once a mesh/animation is imported and uploaded in Studio, its asset ID belongs in
  that summon's entry in `Summons.luau` (or a new field there) — not hardcoded into
  `BattleView.luau` — so content stays data-driven like everything else in
  `ReplicatedStorage/Combat/`.
