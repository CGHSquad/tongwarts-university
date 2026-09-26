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
