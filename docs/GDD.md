# Walkthrough: Roblox Game Dev & Success Plan

Sep 26, 2026

## What this document is

This is a design brief you (and four teammates) wrote to hand to Claude before your first Roblox game goes into production. It's structured as an evolving **Game Design Document + Development Plan**, not a one-off brainstorm — the doc says explicitly that future ideas should be checked against it for consistency and slotted into the roadmap.

The game: a **school-based social RPG with turn-based, party-based combat**, drawing on Persona and Wizard101. Two design pillars are called out as non-negotiable: the school/social-life structure, and turn-based (not real-time) combat. Everything else — schools, pets, dungeons, UI — is explicitly open for scoping down given the team is 5 people making their first Roblox game.

## Core concept

Players attend one of several **schools**, each with its own specialization, teachers, story, aesthetics, and combat abilities — closer to Wizard101's houses than a single shared curriculum. Character growth happens both in combat and out of it (social life, exploration).

**"BrainRot"** is named as a central but still-undefined mechanic — it's meant to touch combat, abilities, and school identity, and the doc explicitly asks for help turning it from a joke/theme into an actual system rather than flavor text.

**My ideas for BrainRot, includes using characters like Tung Tung Sahur, etc.**

## BrainRot as a system

Building on using real internet "brainrot" meme characters (Tung Tung Tung Sahur and similar) as the actual roster rather than an abstract theme:

- **Enemy/collectible layer**: each character becomes a catchable or fightable unit with its own element/weakness — a lightweight typing system (chaotic, unsettling, wholesome, cursed, etc.) layered onto the turn-based combat, similar to how Pokémon types interact.
- **School tie-in**: a school could specialize in one "genre" of brainrot, giving it a distinct ability flavor and cosmetic identity almost for free, since the source material already has strong visual variety.
- **Live-service hook**: brainrot memes as a category refresh constantly, so new characters can be added as limited-time seasonal content — lining up with the retention system asked for later in the doc.
- **Risk to flag**: meme-based content ages fast and carries IP/trend risk (a character could fall out of relevance, or read as too close to someone else's copyrighted work) — original designs *inspired by* the meme format age better than 1:1 recreations.

## Launch School: TungWarts University — Tung Tung School

**This resolves Critical Q1.** Working title *TungWarts University* (nature-fantasy: a Grand Quad with a fountain, a Clocktower, Arcane Library, an Arena, Greenhouse District, Campus Lake, a living/animated Tree, Underground Campus, Nature Preserve, Residence Halls, Student Center, Transit Hub — grounded, wood-and-stone architecture wrapped in greenery rather than a floating/candy-colored fantasy look). This gives the Hub (Step 5's `#8 Main Hub`) a real identity: the Grand Quad and Student Center double as your party-forming social hub, the Arena is your dueling/PvE testing ground, the Greenhouse District and Nature Preserve are exploration/social areas, and the Underground Campus is a natural home for the launch dungeon.

**School identity — Tung Tung School:**

- **Primary melee type: Strike** (of the three — Slash, Strike, Pierce). Fits a woody, blunt-force BrainRot character better than an edged weapon.
- **Primary element: Wind.** Thematically "woody, life type" as you said — read as a nature/life element rather than a pure air element, which keeps room for later schools to contrast with something like Fire, Water, or Earth without immediately overlapping.
- **Combat identity on the double-type axis (Step 6's damage-type weakness system):** Strike (melee category) + Wind (elemental category) gives Tung Tung a two-axis identity — an enemy or summon can resist/be-weak-to the melee type and the element independently, which is exactly the lightweight, non-mandatory-role system Step 6 called for.

**Second axis needed for balance:** a Wind-only, Strike-only launch roster has nothing to be weak *or* strong against yet. Recommend the second launch summon-type introduce a contrasting pair (e.g., a Pierce/Water or Slash/Earth type) so the MVP's "one damage-type weakness axis" (Step 6) has an actual back-and-forth from day one, even with only one school live.

## Tung Tung Sahur — summon variants

Proposing four launch variants built around one recognizable base character, each pulling a different combat role from Step 6's design-language roles (never mandatory, just a kit lean):

1. **Tung Tung Sahur (Base)** — the balanced/default variant. Even Strength/Vitality/Agility, no glaring weakness. Kit: a reliable Strike basic attack, one Wind skill (small AoE or minor push/knockback — fits a "clapping wood" motion), one light self-buff. This is the one every new player gets first, so it should read as fully viable, not a tutorial-only unit.
2. **Tung Tung Sahur, Elder (Tank)** — higher Vitality, lower Agility. A bigger, gnarled/older-tree-styled recolor. Kit: a taunt-style ability (draws enemy targeting), a Wind-based damage-reduction or knockback-on-hit defensive skill.
3. **Tung Tung Sahur, Sapling (Damage/Glass cannon)** — higher Strength and Agility, lower Vitality. Smaller, faster-looking recolor with more aggressive posture. Kit: a hard-hitting single-target Strike skill with a higher pip cost, lower Mana pool.
4. **Tung Tung Sahur, Grove-Keeper (Support/Utility)** — higher Magic, lower Strength. Kit: a Wind-based party buff (e.g., party-wide Agility or accuracy boost — ties nicely back into the initiative system below) and a minor heal or status-cleanse.

All four share the same base model with palette/silhouette variation (bark color, size, posture) rather than fully unique art — keeps this achievable for a 5-person team's art budget while still giving four distinct-*feeling* summons at launch, matching the "3–4 starting summons" scope from Step 2/11.

**Open question for your team:** should these four count as your full MVP roster (Critical Q2 answered), or do you want Tung Tung School to launch with just the Base + one specialist, saving the other two variants for a Should-have content update? Either works with the scope in Step 2 — just flagging the choice.

## Summon evolution and acquisition

**Evolution — confirmed.** All four Tung Tung Sahur variants (Base, Elder, Sapling, Grove-Keeper) stay as separate, parallel archetypes — you get meaningful role choice from day one, not a single line you unlock piece by piece. What's new: **each of the four independently evolves** into a stronger form of *itself* at a level threshold, e.g. Tung Tung Sahur (Base) → Tung Tung Tung Sahur (Crook) at Lv 20 — same role, bigger numbers, maybe one new ability. Elder gets its own evolved tank form, Sapling its own evolved glass-cannon form, and so on. This is the Metaphor-style "archetype gets stronger, doesn't change identity" pattern, not a branching job tree.

- **MVP scope:** ship the four base forms only. Evolution is the first Should-have content update once the base roster is proven fun — flag if you'd rather have it live at launch instead.
- **Cost for a 5-person team:** cheap if an evolved form is a recolor/bigger model + a stat bump (+ maybe one ability), not a full new kit — keeps this in line with the palette/silhouette-variation approach already used for the four base variants.

**Acquisition — still being figured out, here's a starting shape to react to.** New summons (future families beyond Tung Tung School, and possibly sibling variants) are earned, not just handed out:

- **In-game currency purchase**, gated by **player level** (can't buy a high-tier summon before you're leveled enough to use it) and possibly other unlock conditions (a quest, a Social Link milestone, a dungeon clear) — stacking gates the way social stats already gate content elsewhere in this GDD.
- **Cross-school premium:** a summon from a school other than your own costs more currency to acquire than an in-school one. This pairs naturally with the existing pip system — an off-school summon's abilities already get single (not double) Power Pip value without a Mastery item, so a currency premium on top is a second, separate cost layer. Worth deciding whether both penalties apply at once or whether the currency premium alone is enough friction — open question, not locked yet.
- **Possible skill-cost premium:** off-school abilities costing more Mana to cast (on top of the single-pip-value penalty) is on the table but risks double-penalizing the same choice — flag this as something to playtest rather than commit to now.

This is exactly the "second axis needed for balance" gap already flagged in the Launch School section above — acquisition is how a contrasting melee-type/element family actually enters the game post-launch.

## Skill Variety, Evolution Branching, Leveling & Cards

This section extends the evolution/acquisition model above and locks in the leveling architecture that everything else (evolution gates, acquisition gates, catch-up balance) hooks into.

### Fortune — a skill category for Luck

Luck currently has nothing to *cast* (it's crit rate + ailment infliction/resist, a passive-only stat). Rather than add a 5th element — which multiplies the melee×element type-chart math and art budget — **Fortune** is a separate skill category: status/crit-focused abilities that aren't melee or elemental at all (bleeds, stuns, debuff-stacking, execute-on-low-HP, gamble-for-bigger-effect skills). Every school can carry 1-2 Fortune skills alongside its main melee+element axis, regardless of which of the four schools it is.

**Concrete Fortune content, to anchor the category:** Fortune's identity is "the payoff is a bet, not a guarantee," and it's the one category that scales off **Luck** specifically rather than Strength/Magic — that's the mechanical tell separating it from Melee/Elemental skills. Starting content ideas:

- Stacking debuffs (Accuracy Down, Defense Down, Attack Down — multiple casts compound)
- Ailments (Poison/DoT, Stun, Sleep, Charm — make a target act randomly or attack an ally)
- Execute effects (bonus damage below an HP threshold)
- Gamble skills (wide damage variance — can whiff or crit unusually hard)
- The temporary Repel/Absorb skill (single-category, costed, short-duration — this is Fortune's actual home, not an innate affinity)
- A minor drain/steal effect (HP or Mana), Luck-scaled — distinct from the full Absorb affinity

### Evolution branching (usage-based)

Instead of a single fixed evolved form per archetype, each **summon instance** (your specific Tung Tung Sahur, not the species) tracks usage counters on its non-universal kit abilities — anything in its own ability list (Strike/elemental/Fortune skills). The character's universal actions (`Attack`, `Guard`, future `Items`) are never tracked, since they aren't part of the summon's kit at all.

At the archetype's evolution level-gate, whichever tracked ability has the highest usage count decides which evolved form the instance becomes (e.g., a Wind-leaning Tung Tung Sahur (Base) evolves into a different form than a self-buff-leaning one). Every branch table has a **default fallback** for players who never clearly favor one ability, so nothing is ever blocked. This doesn't change the four independent archetype lines (Base/Elder/Sapling/Grove-Keeper each still evolve into a stronger version of themselves) — it just means "a stronger version of itself" can have two or three possible shapes depending on how it was played. Same recolor + stat-bump art cost as a single evolution path, just one branch table and one extra recolor per archetype.

**Second evolution stage, confirmed new: a late-game continuation, not a full 5-tier chain.** Each archetype now gets a **second** evolution at a later level gate (default Level 65, inside a "Mid-Late" pacing band), on top of the Stage 1 usage-branch above (default Level 25). Stage 2 does **not** re-fork by usage — each Stage 1 variant (including the default fallback) gets exactly one further named upgrade, continuing the same branch rather than opening a new choice point. This was weighed against building a full 5-stage evolution chain per archetype (one stage per level-pacing band, 20 total forms across the four archetypes) and intentionally scaled back: a full 5-tier chain was judged too much scope for a first 5-person Roblox project, each stage needing its own kit/art/balance pass. Two stages keeps the total manageable (1 base + up to 3 Stage-1 forms + up to 3 Stage-2 forms per archetype) while still giving late-game players a visible, earned milestone beyond the first evolution.

**Update — Stage 2 reclassified as post-launch-only; a new Mastery Upgrade fills the launch-window gap, confirmed.** If launch caps player level at 50 (still being decided, but a real candidate), Stage 2's default Level 65 gate is unreachable at launch — every player would hit a progression wall at Level 25 with nothing further until the cap is eventually raised post-launch. Stage 2 stays in the design exactly as described above, but is now explicitly **post-launch content**, unlocked by the existing level-cap-raise lever (see "Level cap: design the full curve now, gate the live cap separately") rather than something built for launch.

In its place, a new **Mastery Upgrade** fills the mid-to-late launch window:

- **Dual gate, tying the two level tracks together:** unlocks only when the **player** reaches Level 40 **and** the summon has hit its own current ceiling at Level 25 (the same level as the Stage 1 evolution trigger — so in practice, "the summon has evolved to Stage 1" and "the summon is capped at its ceiling" are the same condition, not two separate numbers to track). This uses the already-locked "player level gates how high a summon can level" rule as Mastery's actual unlock condition, rather than adding an unrelated new check: no amount of combat grinding lets a summon outgrow what the player's own level currently allows, so reaching player Level 40 is what both frees a capped summon to keep leveling *and* earns it the Mastery upgrade as the visible reward for that moment.
- **Continues the Stage 1 branch, does not re-fork:** same principle as Stage 2 above — whichever Stage 1 variant (including the default fallback) the summon already became gets one Mastery upgrade (a new or meaningfully upgraded ability flavored to that branch), not a new usage-based choice.
- **No new model or recolor — cheaper than even a Stage evolution:** Mastery is visually marked with an emissive/glow texture accent on the existing material (no new texture upload) plus a `ParticleEmitter`-based ambient effect (a wind-wisp trail or glowing motes) attached to the existing rig, built directly in Studio/Rojo — no 3D-import pipeline step at all. Keeps the "this one's mastered" tell readable at a glance without any new art-pipeline cost.
- **Possible additional cost, still W.I.P.:** on top of the level dual-gate, Mastery may also cost a new progression currency earned through play (working name candidates: Glimmer/GLM or Arcana/AR) — separate from Mana. Name, amount, and exact earn-rate are all undecided; this is noted here as a real direction being considered, not a locked requirement.

### Per-school subclass divergence

The four-role skeleton (Balanced / Tank / Glass-Cannon / Support — Base / Elder / Sapling / Grove-Keeper for Tung Tung) is reused by every school, but **how** each role fulfills its job should differ by school identity so schools don't read as reskins of each other by school #3-4. For example, an Agility-priority school's "tank" role can be built as an evasion tank (dodge-based) rather than an Endurance-mitigation tank; a Strength-priority school's "support" role can lean armor-shred/debuff rather than healing, keeping healing as another school's actual signature. Same low art cost as the shared skeleton — the divergence is in kit design, not new models.

**The Glass-Cannon role's cross-school signature, confirmed: HP-cost skills.** Most physical skills spend Mana (Metaphor-style, not Persona's all-HP model), but the Glass-Cannon role in every school's roster (Sapling, for Tung Tung) spends **Health** instead of Mana for some of its kit — trading survivability directly for burst damage. This is a deliberate identity marker for that role specifically, not a random per-class assignment: it's mechanically exactly what "glass cannon" should feel like, and it gives that role a distinct resource-management puzzle (risk your own Health for damage) that no other role has, on top of its existing stat lean.

### Tiered cross-school skill transfer

Replaces the earlier open "cross-school premium" brainstorm with a concrete rule. Transferable skills split into three tiers:

- **Common** — basic attacks, generic buffs. Cheap, freely transferable.
- **Signature** — anything tied to a school's primary axis (e.g. Tung Tung's Wind knockback). **Locked, never transferable.** This is what protects "why pick this school" as the roster grows.
- **Rare/Fortune** — status-based skills. Transferable, but pricier — the main currency sink for cross-school customization, and it reinforces Fortune as a genuine progression sink rather than a stat afterthought.

**Common/Signature pairing for elemental skills, confirmed:** every element gets a generic, cheap, cross-school-available Common version — a tiered Basic/Medium/High single-target spell (with a possible AoE variant), the same shape across every school (e.g. TungWarts's Wind version: Gale / Galen / Galor, names W.I.P.). Basic buffs are Common too, same reasoning. Each school's actual **Signature** spell for that element is the stronger, flashier, locked version of the same element — giving every element a clean weak/strong pairing (a generic option anyone can use, and a school-specific upgrade that's the real reason to pick that school) instead of two unrelated skill lists.

### On adding a 5th school (or a 4th melee type)

The real ceiling isn't elements (Fortune buys headroom there) — it's melee types. Slash/Strike/Pierce are already covered across schools #1-3. A future 5th school should double up on an existing melee type with a different element/stat pairing rather than introduce a 4th melee category; hold off on a new melee type until 3-4 schools have shipped and the grid is proven thin, matching the Step 2 "don't build past what's proven" discipline.

### Leveling: player level and summon level are separate tracks

Player level and summon level are tracked independently, but both advance from the same activity (combat) — they level **simultaneously**, not on a shared counter.

- **Summon level** is per-instance and auto-growth (no manual stat allocation): each summon instance gains its own XP and levels up on its archetype's own growth curve.
- **Player level is the gate/ceiling**, not a second stat pool. It caps how high a summon's level (and therefore its stats) can currently reach, and it's the number evolution and acquisition checks read against — **not** the summon's own level. A freshly-acquired or freshly-started archetype is bounded by the player's level the same way every other summon is.

### Player-level Health/Mana floor

**Confirmed:** player level grants a universal bonus to max Health and max Mana, on top of whatever the active summon's Endurance/Magic already provide — the standard "leveling up gives you a bigger bar" convention, so it needs no explanation for players. This is scoped to Health/Mana only, not the full stat block — offense (Strength/Magic damage output) stays entirely summon-owned, so an under-leveled or off-meta summon is still noticeably weaker to fight *with*, it just doesn't get you killed instantly to fight *as*.

Why this over the alternative (letting Health/Mana scale only through the existing player-level ceiling on summon growth): the ceiling is invisible — it only manifests as "my summon's growth is capped," which a player has no clear way to notice or feel. A direct player-level bonus to the bars is something every player already intuitively understands from nearly every other RPG, at the cost of one extra formula to tune (a flat or scaling bonus per player level, additive to the summon's own Endurance/Magic-derived pool).

**Relationship to Mentor Bond:** this is the permanent floor; Mentor Bond (the temporary, decaying stat-assist borrowed from another owned summon) is unchanged and still does its own job — it stays in as described, closing the gap faster for a specific under-leveled build rather than replacing this universal bonus.

### HP/Mana curve, stat ceilings & the level cap

Refines the leveling model above with the actual curve shape and how the player-level floor and summon stats split the total.

**Priority-stat pool rule, confirmed:** each school's priority stat determines which pool (Health or Mana) is highest in that school's roster — Endurance-priority schools have the highest Health totals, Magic-priority schools have the highest Mana totals. This isn't a separate mechanic to build, it's a rule for picking the numbers: when setting a school's HP/Mana totals, the priority stat's matching pool should be the highest among the four schools.

**Curve shape — different for each pool, not mirrored:**

- **Mana** follows a diminishing-returns (concave) curve — large gains early, flattening at higher levels — e.g. `MP(L) = MP1 + (MP99 − MP1) × ((L−1)/98)^p` with `p` roughly 0.6–0.75. This keeps early game from feeling Mana-starved without making the late-game pool unbounded.
- **Health** is more linear. HP and Mana don't have to share a curve shape — they serve different jobs (survivability needs to keep pace with enemy damage scaling; Mana needs to avoid an early dry spell), so they're tuned independently.

**Floor/gap split, confirmed:** each school's full HP/Mana total (as sketched in the team's numbers) splits into two sources:

- **Player-level floor** (\~70–75% of the total) — flat, universal, already locked above. This is the safety-net portion; it doesn't change based on which summon is active.
- **Summon's own Endurance/Magic contribution** (\~25–30% of the total) — closes the remaining gap, scaling with the active summon's stats. A fresh or under-leveled summon sits at roughly the floor; a fully-invested one closes the gap.

**Stat contribution is multiplicative, not additive, confirmed:** `MaxMP = FloorMP × (1 + Magic × k)` (same shape for `MaxHP`/`Endurance`), not a flat bonus added on top. A flat bonus becomes a rounding error once the level-based floor is large, which would make summon choice matter less at exactly the levels where it should matter most. Multiplicative scaling keeps the stat's contribution meaningful at every level. **Tuning risk to plan for:** multiplicative stacking can run away if uncapped (the same risk already flagged for Guard's Endurance reduction) — put a soft cap or diminishing curve on the multiplier itself once real numbers are being tuned, not left open-ended.

**Stat ceilings are per-archetype, not shared, confirmed.** A shared ceiling (every archetype's best stat capping at the same number) would make different archetypes converge at max level, undercutting the whole point of archetype choice. Instead: a "High" stat lean (per the Stat Growth Lean table already in the team's content spreadsheet) tops out around 70 at level 90+, and Medium/Low leans scale down proportionally from that anchor — per archetype, per stat. Sapling's Strength ceiling should sit well above what Elder's Strength ceiling ever gets, and vice versa for Endurance, so the trade-off stays meaningful all the way to max level, not just early game.

**Base stat hard boundary, confirmed explicit.** No archetype's BASE stat value may exceed 70 unless that stat's Growth Lean is "High" (the one \~70-ceiling stat each archetype specializes in) — this restates what the per-archetype ceiling table above already enforces, now as an explicit rule rather than an implication. A stat can only read above 70 through an EXTERNAL source — gear, consumables, or an active buff skill — never from leveling alone. The external-buff/gear system is still Later/Could-have scope (see the Gear System section); don't design specific numbers against it yet.

**Level cap: design the full curve now, gate the live cap separately.** Build the HP/Mana/stat formulas across the full intended range (the team is designing against a Level 1–99 shape) rather than a smaller range that would need rebuilding later. The actual level cap players can reach *at launch* stays a separate, lower configuration value layered on top of that formula (per "Level cap pacing" above) — raising the cap post-launch just moves the gate, it doesn't require redesigning the curve.

### Stats stay fully summon-owned

Confirmed (reverting an earlier considered split): all five combat stats — Strength, Magic, Endurance, Agility, Luck — live entirely on the summon, along with the HP/Mana pools. The player character carries no combat stat block of its own. This keeps every school's priority-stat identity mapped 1:1 with no asymmetry: Tungwarts → Endurance, Cappuccino Assassino → Agility, Tralalero Tralala → Strength, Ballerina Cappuccino → Magic, all expressed the same way (that school's summon roster leans its growth curve toward that stat).

### Card system

A third equip layer, distinct from Gear (direct stat/damage modifiers) and from summon kit abilities (what the summon can *do*). Cards are **Persona Trait-style passive procs** — conditional triggers like "chance for next attack to double damage" — rather than flat stat sticks.

- **Equip:** a card is equipped on the **player character**, not the summon, and its passive effect is **universal** — it applies no matter which summon is currently active. Confirmed: **1 card slot** to start, with **2 slots** as a possible future expansion.
- **Acquisition:** gameplay-first — dungeon drops, rotating reward tables, and a soft in-game currency — as the core acquisition loop. Robux spend is reserved for **convenience and cosmetics only** (faster drop rates, extra inventory/loadout slots, cosmetic card skins), never for buying power directly. This avoids pay-to-win/loot-box perception, which matters for Roblox's disclosure norms around randomized paid rewards and for a younger-skewing audience.

### Level cap pacing

Start with a **shorter, lower level cap for MVP/testing** rather than committing to a large number (e.g. 99) up front. Treat cap increases as a **post-launch content lever** — each raise ships with new unlock bands (stat tiers, evolution/acquisition gates, card slots) — the same pattern most live-service RPGs use to keep bringing players back. The full leveling curve/formula is still to be jotted down in detail.

**Progression tiers for content pacing, confirmed new.** Levels 1-99 are divided into 5 bands for CONTENT DESIGN purposes (dungeon difficulty, enemy stat scaling, drop tables) — not additional evolution stages: Tier 1 Early (1-15) · Tier 2 Mid-Early (16-35) · Tier 3 Mid (36-55) · Tier 4 Mid-Late (56-75) · Tier 5 Late (76+). Evolution itself stays at the two stages described above (see "Second evolution stage"); these tiers exist so content/difficulty design has a shared vocabulary for "what level range is this dungeon/enemy aimed at," independent of any individual summon's evolution state.

### Catch-up mechanics for under-leveled summons

Two related but distinct problems, with two different fixes:

- **"Mentor Bond" (using a summon that's genuinely behind):** pick another owned summon as a mentor for an under-leveled or freshly-started archetype. The mentored summon gets a **temporary, percentage-based, decaying stat assist**, sized to the level gap and leaning toward survivability (Endurance / damage reduction) rather than offense, so it isn't crushed by current-tier content without also hitting as hard as a fully-leveled summon. The assist shrinks to zero as the summon catches up on its own growth curve — it's training wheels, not a permanent stat transplant, and it doesn't undercut the incentive to actually level the archetype.
- **Encounter-level-sync (helping a lower-level party member/friend):** when joining content well below your own tier, the encounter (or your effective combat power within it) scales down to match that content's intended difficulty, rather than requiring the player to deliberately bench their main summon for a weak one. Keeps low-tier content fair for the lower-level player without penalizing the higher-level one.

## Combat philosophy

Turn-based combat is flagged as **the** foundational pillar — explicitly not a real-time action RPG. It's meant to run on turn order, strategic decisions, team composition, and school synergy rather than reflexes. Because of that, party-based multiplayer isn't a bolt-on feature — it's a direct consequence of the combat choice: fights are built around 3-4 players filling roles like damage, healing, tank, and utility, though the doc is careful to say these roles aren't finalized or mandatory.

You've since pointed toward a more specific model to build the pillar from: an **Agility stat** on every character and enemy sets the baseline turn order, and turns alternate **individually** rather than by team — so a round might go ally → enemy → ally → ally → enemy depending on speed, not a rigid "your whole team, then their whole team" pattern.

Positioning outside combat feeds into this too: striking an enemy first in the overworld gives your party the advantage going in, getting hit from behind hands the enemy a free turn, and a clean sneak-attack ambush grants your entire party a full bonus turn before normal combat even starts.

This effectively answers the multiplayer turn-resolution question raised below in favor of **individual, speed-based turns** (Option A), extended with an initiative/ambush layer on top.

**Update — Critical Q3 answered:** you've refined this to a D&D-style initiative roll rather than a strict Agility sort. Turn order is decided by a roll (e.g., a die roll or randomized value) modified by each participant's Agility — higher Agility improves your odds of an earlier turn, but never guarantees it. This keeps Agility valuable without making it fully deterministic, and adds a small amount of turn-order variance that a purely stat-sorted system wouldn't have. Step 6's Battle State and Turn Management below reflect this as the final rule.

## Core stats & Mana/Energy

You're weighing the classic Atlus stat block (Strength, Magic, Vitality, Agility, Intelligence, Luck) and asking whether it belongs on the **player character** or the **summon/persona**.

Given the game already leans on summons (BrainRot characters) as the combat roster, the Persona-model split is the one that scales best here:

- **Player character carries progression identity**: level, HP/Mana pool size, equipment slots, school affiliation, and social stats (Charisma, Guts, etc. from the Social Stats system above). The player is *who you are*.
- **Summon/BrainRot carries combat stats — finalized:** Strength, Magic, Endurance, Agility, Luck (the modern combined Atlus model — Magic and Intelligence merged into one stat, not kept separate). HP and Mana stay named Health and Mana (not "SP"), but scale the same way:
  - **Strength** — physical/Strike damage
  - **Magic** — elemental (Wind, etc.) damage and boosts max Mana
  - **Endurance** — reduces incoming physical *and* magical damage, and is the largest factor in max Health
  - **Agility** — turn order (the initiative roll bonus) *and* base accuracy/evasion
  - **Luck** — critical hit rate, chance to inflict/resist status ailments, and resist/succeed on instant-kill effects; minor effect on escape success and item drops

  This replaces the earlier 6-stat draft (which kept Intelligence separate) — Intelligence is gone, folded into Magic (damage) and Agility/Luck (accuracy, status). Live on the summoned character, since that's what's actually swinging or casting. The summon is *what you fight with*.
- **The bridge between them**: player level and equipped gear scale the summon's stat ceiling (like a Persona's level being capped by the player's level in the source games), so switching summons doesn't waste your progression, but each summon still has a distinct stat spread and personality in combat.

This keeps the collect/swap loop (multiple BrainRot summons) meaningful — you're not just re-skinning one character, you're changing your stat profile — while player-side progression (the thing that persists no matter which summon is active) stays legible.

**Mana/Energy**: sits on the summon (scaled by its Magic stat, as in the reference material), refills on a per-battle or per-turn basis, and is the resource that skills/abilities consume — giving you a lever for pacing fights without touching HP directly.

## Pip-style resource system

Adapting Wizard101's Power Pip system on top of Mana/Energy rather than replacing it — pips gate *which* abilities you can afford to cast, Mana/Energy gates *how often*:

- **Regular pips** build up each round (like a simplified action-point economy) and are spent on abilities.
- **Power pips** count double, but only for abilities matching your **school/BrainRot's primary affinity** — this is the mechanic that makes school identity matter turn-to-turn, not just at character creation. An off-affinity ability only gets single value from a Power pip, mirroring the wand-school penalty.
- **Mastery items** (the Mastery Amulet equivalent) let a player invest in a secondary school/affinity, unlocking double value there too — a soft multiclassing lever without diluting the core school identity.
- **Power Pip Chance** becomes a gear stat, giving itemization/progression something concrete to build around (matches the Character Customization and Economy sections above — gear as a currency sink that isn't just cosmetic).

**Open design question for you:** do you want Power Pip Chance pushed toward a 100%-achievable ceiling at end-game (Wizard101's model, where late gear trivializes the RNG), or capped below 100% so it stays a meaningful stat throughout? The MVP-scope answer is likely simpler — flat pip generation, no chance-based Power Pips — with the RNG layer added post-launch once the core loop is proven; flagging this for the MVP feature list in Step 2.

## Step 1 — Game Design Overview

**Core premise:** A school-based social RPG where players attend one of several schools, build relationships and social stats outside combat, and fight in turn-based, Agility-ordered battles using summoned BrainRot-meme characters as their combat roster.

**Genre:** Social RPG / turn-based tactics hybrid (Persona-style social sim + Wizard101-style school structure + a summon-based battle system).

**Target audience:** Younger Roblox players (roughly tween/early-teen core, per the UI section's stated audience) who already engage with brainrot meme culture, with systems designed to also read as stylish/deep enough for older Roblox players.

**Core gameplay loop:** Explore school/hub → build social links & stats → form a party → enter a dungeon → turn-based combat with BrainRot summons → earn rewards → customize character/summons → return to hub/school. Matches the loop diagram already in the source brief — it holds together because every loop (social, combat, progression) feeds the same hub-and-party structure rather than running in parallel systems.

**Progression loop:** Player level/gear raises the ceiling on summon stats; social stats unlock new activities/dialogue/areas; summon collection (BrainRot roster) is a separate, parallel progression track from character level.

**Social loop:** Persona-style Social Links with NPCs, gated by Social Stats (Charisma, Guts, etc.), feeding rewards, dialogue and eventually gameplay bonuses.

**Turn-based combat loop:** Individual, Agility-ordered turns (allies and enemies interleaved) + overworld initiative/ambush + Mana/Energy on the summon + a pip-style resource layered on top for school-affinity payoff.

**Multiplayer loop:** Party formation → shared dungeon run → individually-resolved turns inside one battle → shared rewards.

**Exploration loop:** Hub → school areas → dungeons, with fast travel and social/activity hotspots along the way.

**Long-term progression:** Summon collection, social link completion, school mastery, gear/pip-chance itemization, cosmetics.

**What makes it unique on Roblox:** the combination itself — there's real-time action combat and there's Persona-style social sims on Roblox separately, but a turn-based, Agility-driven, summon-collecting combat system paired with a school/social sim is not a common Roblox combination; the BrainRot summon layer also gives it a built-in, constantly-refreshable hook for short-form video (TikTok/Shorts) clips.

**Contradictions/weaknesses to flag now:**

- The brief asks for both "exploration" and "a school-based world" as pillars — worth deciding whether exploration means large overworld traversal (higher cost) or dense, activity-rich hub areas (lower cost, still satisfies the loop). Recommend the latter for a 5-person team.
- Individual pip-style resources plus Mana/Energy plus social stats plus summon stats is four separate resource/stat systems before a single line of combat code exists. That's a real complexity risk for a first Roblox project and is the central question Step 2 (MVP) needs to resolve.
- "Multiple schools at launch" and "realistic scope for a 5-person team" are already in tension in the source brief — Step 2 addresses this directly with a launch-school-count recommendation.
- ## Step 2 — MVP Definition

  Sorted for a first-time, 5-person Roblox team. The rule: one school, one dungeon, one full combat loop, working end to end, before anything else gets built.

  ### Must have
  - One school (not multiple)
  - One hub area
  - Character creation with basic customization
  - Turn-based combat: Agility-ordered individual turns, HP, Mana/Energy, one BrainRot summon per player
  - Flat pip generation (no Power Pip RNG yet)
  - Party system: create/invite/join, 3–4 players, basic role variety
  - One dungeon (explore → fight → boss → reward)
  - Basic quests (linear, no branching social system yet)
  - Basic currency + a simple shop sink
  - Core HUD + turn-based combat UI (this is Must, not Should — per your own UI/UX priority note, unreadable combat kills the MVP regardless of how good the mechanics are)

  ### Should have (soon after launch)
  - Social Links with a small number of NPCs (2–3), no full calendar/schedule system yet
  - 2–3 additional BrainRot summons to collect
  - Social stats (start with 2, e.g. Charisma + Guts, not the full 6)
  - Power Pip Chance as a gear stat (turns on the RNG layer once the flat-pip version is proven fun)
  - Basic pets (cosmetic only)
  - Daily login/activity rewards

  ### Could have (post-launch, once retention data exists)
  - A second school
  - Mounts
  - Mastery items (secondary-school pip bypass)
  - Leaderboards, clubs/organizations
  - Seasonal BrainRot summon events
  - Additional dungeons with mechanical variety (not just reskins)
  - Gear system (weapons, armor, accessories — see the dedicated Gear System section after Step 7)

  ### Do not build yet
  - Trading
  - PvP
  - Hngousing
  - Crafting
  - Full NPC schedule/calendar system
  - More than one school at launch
  - More than ≊6 UI screen types beyond what's listed as Must-have

  **Why this cut:** every system marked Must directly serves the one loop that has to prove itself first — does turn-based, summon-based combat with a party actually feel good? Social depth, a second school, and pip RNG all make an already-fun loop richer; none of them can rescue a combat loop that isn't fun on its own. Trading, PvP, housing and crafting are common Roblox feature-creep traps for first-time teams — each is a full subsystem (economy/anti-cheat for trading, balance for PvP, persistence/UGC tooling for housing) that competes directly with finishing the core loop.

  ## Step 3 — Development Roadmap

  Each phase lists goals, deliverables, and what to explicitly avoid touching yet.

  ### Phase 0 — Pre-production
  - **Goals:** lock the MVP cut above, write short design docs for combat math (Agility/turn order, HP/Mana formulas, pip values) and the school/summon relationship
  - **Deliverables:** this GDD kept current, a one-page technical architecture sketch, a rough content list (1 school, 1 dungeon, \~4 summons)
  - **Avoid:** any UI polish, any art beyond placeholder blocks, any system not in Must-have
  - **Done when:** every Must-have system has a one-paragraph design spec someone could implement from

  ### Phase 1 — Prototype
  - **Goals:** prove the turn-based loop is fun with placeholder art
  - **Deliverables:** basic movement, a working turn-based battle (Agility order, one summon each side, basic attack/skill/Mana), a barebones party (2 players, no matchmaking), one NPC interaction, one quest, basic XP/level
  - **Avoid:** social links, pip system, cosmetics, more than 2 summons
  - **Done when:** two teammates can fight one battle together start-to-finish without a developer present

  ### Phase 2 — Vertical slice
  - **Goals:** one small area that feels like the final game
  - **Deliverables:** the one launch school (real art pass), a small hub, 2–3 NPCs with basic Social Link stubs, the one dungeon fully built (explore → fight → mini-boss → final boss → reward), representative combat/HUD UI, 3–4 BrainRot summons with distinct kits
  - **Avoid:** second school, pip RNG, mounts, trading/PvP/housing/crafting (still Do-Not-Build-Yet)
  - **Done when:** an outside playtester can go character-creation → dungeon clear → reward loop with no explanation from the team

  ### Phase 3 — Production
  - **Goals:** build out the Should-have list from Step 2 on top of a proven core
  - **Deliverables:** full Social Link roster for launch NPCs, remaining launch summons, Power Pip Chance gear stat turned on, daily rewards, polish pass on Must-have UI
  - **Avoid:** starting a second school unless Phase 2 playtests clearly show demand and time allows

  ### Phase 4 — Alpha
  - **Goals:** feature-complete for launch scope, internal/closed testing
  - **Deliverables:** all Must + Should systems implemented, known-bug list, first monetization hooks (cosmetic-only) wired but not necessarily priced

  ### Phase 5 — Beta
  - **Goals:** stability and balance, small external playtest group
  - **Deliverables:** combat balance pass using playtest data, onboarding/first-session flow finalized, performance pass (mobile especially, per the UI section's platform note)

  ### Phase 6 — Launch
  - **Goals:** ship the MVP
  - **Deliverables:** store page, thumbnail/icon (Step 9 territory), Discord/community presence live, launch-day monitoring plan

  ### Phase 7 — Post-launch
  - **Goals:** work the Could-have list based on real retention data, not assumptions
  - **Deliverables:** second school evaluation, mounts, seasonal BrainRot events, first content update cadence established

  **Sequencing note:** Phases 0–2 are where scope discipline matters most — a 5-person first-time team's biggest risk is polishing Phase 3+ features before Phase 1–2 prove the core loop works at all.

## Multiplayer & party system

The doc lists the full surface area of party mechanics it wants worked out — party size, invites, matchmaking, public/private/friends-only parties, what happens on disconnect, late-join, death, and reward splits.

The sharpest open question is **how simultaneous turn-based combat actually works with multiple humans in one battle**, and it lays out four options to weigh rather than picking one upfront:

- **A — Individual turns:** each character acts on its own, ordered by speed
- **B — Team planning:** everyone picks actions during a shared planning phase, then it all resolves
- **C — Simultaneous selection:** everyone picks at once; the game decides resolution order
- **D — Hybrid:** actions chosen within a shared turn structure

It asks for a real analysis of trade-offs (complexity, feel, technical cost) across these, not just a recommendation.

**Update:** this has been decided — see Combat philosophy above. Turns go individually by Agility across the whole battle (allies and enemies interleaved), not team-by-team, with an overworld initiative/ambush layer on top. The remaining multiplayer-specific question is narrower: how each human player's action gets *submitted* on their turn (real-time input vs. a short per-turn timer) and how the game communicates whose turn is next when it isn't yours.

## The eight systems it wants designed

Each gets its own numbered section (1-8) with a bullet list of open questions rather than fixed answers:

1. **Multiple schools** — how many at launch, permanent vs. changeable, how they stay balanced against each other
2. **Character customization** — what's free vs. earned vs. monetized
3. **School/social life** (Persona-inspired) — social links, NPC schedules, whether there's an in-game calendar or daily action limit
4. **Social stats** (Charisma, Guts, Intelligence, etc.) — how they gate content without becoming a grind
5. **Pets & mounts** — cosmetic vs. functional, how to avoid gacha-style predatory acquisition
6. **Dungeons / multiplayer PvE** — party-based structure (explore → fight → mini-boss → final boss → rewards), scaling for a 5-person dev team
7. **Social features & events** — friends, clubs, seasonal events, leaderboards, explicitly asking to prioritize by value vs. cost rather than adding everything
8. **Main hub** — a social space (shops, minigames, part-time jobs) meant to double as where parties form

All eight are explicitly meant to be evaluated against the same rubric later in the doc: player value, dev cost, technical complexity, long-term value, multiplayer value, UI/UX value, and MVP priority.

## UI/UX

This section is treated as its own discipline, not an afterthought — the doc says explicitly to treat UI as **part of the MVP**, and splits it into MVP UI, Polished UI, and Post-Launch UI so the team doesn't polish menus before gameplay works.

It covers main menu, HUD, turn-based combat UI, party UI, social/Persona-style UI, character UI, quest UI, map UI, notifications, animation, and even UI sound design — then asks for **22 separate UI deliverables** (design philosophy, visual identity, screen inventory, and a layout proposal for each screen type) plus guidance on tools (Figma, Roblox Studio, etc.) and workflow for a beginner team.

## The 11-step process it wants followed

After the concept/systems sections, the doc lays out an 11-step planning sequence for Claude to work through:

1. Game Design Overview (plus naming contradictions in the current concept)
2. **MVP definition** — sorting every feature into Must/Should/Could/Do-Not-Build-Yet
3. Development roadmap (Phase 0 pre-production through Phase 7 post-launch)
4. Team structure for the 5 people
5. Technical architecture (Roblox Studio, Luau, DataStoreService, RemoteEvents, etc.)
6. Turn-based combat architecture specifically (battle state, turn management, sync, roles, depth)
7. Game economy (currencies, sources, sinks)
8. Retention (short/medium/long-term hooks)
9. Roblox discovery & growth (thumbnails, Discover algorithm, realistic retention/session targets)
10. Risk analysis with mitigations
11. A prioritized list of open questions (Critical / Important / Later)

It then asks for a **32-item final deliverable list** — everything from the Game Vision down to "First 10 things our team should do" — built from the analysis in steps 1-11, with scope control (MVP-first, no 30-system feature pile) as the recurring constraint throughout.

## What's actually being asked, and a suggested next step

The doc's closing lines frame this as an ongoing GDD relationship: Claude is asked to act as designer, systems designer, UI/UX designer, and technical PM all at once, and to keep evaluating new ideas against this doc as they come in rather than starting fresh each time.

Given the scope (a 32-item deliverable list), the realistic path is to work through it in the order the doc itself proposes — Game Design Overview and MVP scoping first, since nearly everything downstream (roadmap, team structure, architecture) depends on which features actually make the cut. Happy to start there whenever you're ready.

## Step 4 — Team Structure (5 people)

Recommended roles, mapped to the MVP scope above:

1. **Game Designer / Producer** — owns this GDD, the MVP cut, combat math (Agility/turn order/pip values), and keeps the team pointed at the roadmap phases. Runs weekly check-ins and is the tiebreaker on scope disputes.
2. **Gameplay Programmer** — owns turn-based combat implementation, party/multiplayer sync, and quest/NPC interaction logic. Primary owner of the single highest-risk system (Step 6's combat architecture).
3. **Systems/Backend Programmer** — owns DataStoreService/player data, inventory, progression math, economy, and RemoteEvent/RemoteFunction security (validating actions server-side).
4. **Builder/Environment Artist** — owns the hub, the one launch school, and the one launch dungeon's physical layout and set-dressing.
5. **UI/Artist/Technical Designer** — sole owner of UI/UX (per the source brief's explicit ask for clear UI ownership): HUD, combat UI, menus, and the visual identity pass on BrainRot summons/cosmetics.

**Overlap that's fine:** Gameplay Programmer and Systems Programmer will both touch combat (one client-facing feel, one server-side validation) — that's expected, not a conflict, as long as Step 6's battle-state ownership is written down.

**Avoiding a bottleneck:** the Game Designer/Producer role should not also be the sole engineer on the combat system — if the same person holds both, combat becomes a single point of failure. If your 5 people don't cleanly map to these 5 roles, it's fine for one person to cover two lighter roles (e.g., Builder + a share of UI) rather than splitting Gameplay Programming.

**Version control & workflow:**

- Use GitHub (or Roblox's own Team Create as a supplement, not a replacement) with one repo per game, feature branches per system, and PRs reviewed by at least one other person before merging into main.
- Rojo (a standard open-source tool) to sync your GitHub repo with Roblox Studio, so code lives in real files instead of only inside Studio's own script objects — this is close to a Must-have for a 5-person team, since Studio's built-in collaboration doesn't diff or branch well.
- Weekly short syncs (not daily standups — overkill for 5 people) plus an async task board (Trello/Notion/GitHub Projects) tracking Must-have items against the current phase.
- Code review: even a quick "one other person reads it before merge" catches most early bugs; the Systems Programmer should review anything touching DataStoreService, since data-loss bugs are the hardest to recover from post-launch.

## Step 5 — Technical Architecture

High-level structure, not a full codebase — organized as ModuleScripts by system, with server authority over anything that affects progression or fairness.

**General pattern:** client scripts handle input and visuals only; server ModuleScripts own state and validate every action a client requests. RemoteEvents carry requests one-way (client → server) for actions like "cast this ability"; RemoteEvents also push state updates back (server → client) like "here's the new turn order." RemoteFunctions are used sparingly, for the few cases that need a direct request/response (e.g., "can I afford this shop item?").

**Player data (DataStoreService):** one player-data module per player, loaded on join and saved on leave plus periodic auto-save; store a versioned schema (a `version` field in the saved table) from day one so later balance changes don't break old saves.

**Inventory & progression:** a shared `PlayerProfile` module holding level, XP, currency, unlocked summons, equipped gear, and social stat values — one canonical source server-side, mirrored to the client as read-only display data.

**Schools:** each school is data, not code — a ModuleScript table listing its abilities, stat modifiers, and cosmetic set, so adding a second school later (Phase 7) means writing new data, not new systems.

**Turn-based combat & combat state:** a `BattleSession` object (server-only) per active fight, holding participants, HP/Mana, pip counts, turn queue (sorted by Agility), and battle phase (input/resolve/reward) — detailed further in Step 6.

**Abilities & status effects:** abilities defined as data (school, Mana cost, pip cost/type, effect function reference) so designers can add abilities without touching combat-loop code; status effects as a table of `{ effect, duration, sourceStat }` ticked each turn by the BattleSession.

**Quests & NPCs:** quest state stored per player in `PlayerProfile`; NPCs use CollectionService tags (e.g., `"NPC"`, `"QuestGiver"`) so interaction scripts can query by tag instead of hardcoding NPC lists.

**Social links & social stats:** stored alongside progression in `PlayerProfile`; social stat gains route through one shared function so every activity that grants them (studying, working, questing) reports through the same code path — avoids balance drift from scattered `+stat` calls.

**Pets & mounts:** cosmetic-only at MVP, so this is just an equipped-appearance field on `PlayerProfile`; deferring functional pet logic entirely until Could-have.

**Dungeons:** each dungeon is a separate place or a teleport-gated area (TeleportService only if you split dungeons into separate Roblox places — not required at MVP scope if the one launch dungeon lives in the same place as the hub).

**Parties:** a server-side `PartyManager` module tracking party membership, independent of combat — a party persists across a dungeon run and only gets consumed into a `BattleSession` when a fight starts.

**Matchmaking:** MVP skips real matchmaking — friend/manual invite only; queue-based matchmaking is a Could-have, not required to prove the core loop.

**Rewards & shops:** a shared `RewardTable` data format ( item/currency/summon + weight or fixed amount) consumed by both dungeon-clear rewards and shop purchases, so you're not writing two separate reward systems.

**Events:** MVP has none; when added post-launch, model them as time-boxed modifiers to existing `RewardTable`s and drop-in-only content, not new systems.

**UI systems:** client-side only, driven entirely by data pushed from server modules (BattleSession state, PlayerProfile fields) — UI should never hold its own copy of truth, only render what the server sends, to avoid desync between what a player sees and what actually happened.

**MarketplaceService:** wired only for cosmetic purchases at MVP/Alpha, kept isolated from any system that affects combat stats, per the no-pay-to-win goal in the source brief.

## Step 6 — Turn-Based Combat Architecture

The highest-risk, highest-value system in the game — given special detail per the source brief.

### Battle state

A server-only `BattleSession` table created when a fight starts (either from an overworld initiative strike or an ambush), holding:

- `participants`: list of `{ characterRef, side, HP, maxHP, Mana, maxMana, pips, agility, statusEffects }` — characters are summons (BrainRot), so `characterRef` points at the active summon's data, not the player directly
- `turnQueue`: participants ordered by a per-battle initiative roll (random value + Agility-scaled modifier), rolled once at battle start — see the finalized rule below
- `phase`: `"input"` (waiting on the current actor), `"resolve"` (executing the chosen action), or `"reward"` (fight over)
- `initiativeBonus`: flags whether this fight opened with a player-side ambush (full bonus turn) or an enemy sneak attack (enemy free turn), set once at battle start per the overworld rules already defined
- turnQueue's ordering is finalized: at battle start, each participant rolls an initiative value (e.g., a random roll + an Agility-scaled bonus), and the queue sorts by that rolled total, not by raw Agility — so a low-Agility unit can occasionally act before a high-Agility one, while Agility still meaningfully shifts the odds.

### Turn management

- **Begin/end:** a turn begins when `phase` becomes `"input"` for the next entry in `turnQueue`; it ends when that actor's action fully resolves and the queue advances
- **Action submission:** for a human turn, the client sends one RemoteEvent (`ability id + target`) which the server queues; the server does not accept a second action from that player until this turn resolves
- **Simultaneous actions:** per the earlier Multiplayer decision (Option A, individual turns), only one actor acts at a time — there is no true simultaneous-selection case to resolve, which is exactly what removes the biggest source of netcode complexity in Options B–D
- **Action priority:** within one actor's turn, effects resolve in a fixed order — pre-action triggers (e.g., a "counter" status) → the action itself → post-action triggers (e.g., poison tick) → death checks
- **Speed & turn order (final):** initiative is rolled once per battle — a random roll + an Agility-scaled modifier per participant, sorted into `turnQueue` — not a pure Agility sort. Agility raises the odds of an early slot without guaranteeing one. Ties broken by a stable rule (player side before enemy side on an exact tie); a mid-fight Agility buff/debuff affects that participant's roll bonus in their *next* battle, not the current queue, so an in-progress fight is never re-sorted.
- **Enemy action selection:** a simple weighted-choice table per enemy type at MVP (e.g., 60% attack lowest-HP target, 40% attack current target) — full enemy AI trees are explicitly a post-MVP investment
- **Server validation:** every submitted action is checked server-side for legality (enough Mana/pips, valid target, actor's actual turn) before it's allowed to resolve — the client never determines outcomes, only requests them

### Multiplayer synchronization

- **Multiple players selecting actions:** not simultaneous under Option A — the server simply won't accept an action from anyone except the current `turnQueue` entry, which removes most of the sync problem by construction
- **Disconnects:** a disconnected player's remaining turns auto-pass (or use a simple default action) after a short timeout, so the party isn't stuck; on reconnect within the same session, they resume control
- **Late-join:** not supported mid-battle at MVP — a party member who joins late waits for the next fight; simpler than reconstructing battle state for a joiner
- **Latency:** the server is authoritative and the only source of truth; clients show an optimistic "submitted" state but the server's resolution is what actually plays out, so latency affects delay-to-feedback, not correctness
- **AFK players:** the same turn-timeout/auto-pass rule as disconnects covers this without a separate system
- **Invalid actions:** silently rejected server-side with a client-side error message; never trust client-reported outcomes
- **Players leaving combat:** their summon is removed from `turnQueue`; if it was their turn, the queue advances immediately
- **Server authority:** absolute — HP, Mana, pips, and turn order all live and are computed server-side; the client only renders what it's told

### Combat roles

Damage/Tank/Healer/Support/Debuffer/Crowd-Control/Utility are useful *design language* for building distinct BrainRot summon kits, but per the source brief's own caution, none should be mechanically mandatory — the school/summon-affinity system (pip double-value) is a stronger, more flexible source of team-comp variety than rigid class locks. Recommend: every summon leans toward one or two roles through its ability list, but parties are never blocked from entering content without a specific role present at MVP scope (add role-gated content later, deliberately, only if playtesting shows comps are too same-y without it).

### Combat depth — MVP vs. later

**MVP:** Agility turn order, HP/Mana, flat pips, basic attack + a small skill list per summon, one damage-type weakness/resistance axis tied to school/BrainRot affinity (a lightweight stand-in for the full elemental chart), one or two status effects (e.g., a damage-over-time and an accuracy-down).

**Should-have:** Power Pip Chance (the RNG layer), Mastery items, a wider status-effect roster, simple combo triggers (e.g., a debuff that empowers a specific follow-up ability).

**Later:** full elemental/BrainRot-type chart with multiple weaknesses per unit, team attacks (multi-player combo abilities), chain effects, ultimate abilities with charge meters. These add real depth but each multiplies QA surface area — sequence them after the MVP loop is proven fun, not before.

**Affinity tier scoping — confirmed.** The MVP damage-type axis above uses three tiers: **Weak / Neutral / Resist**. The fuller SMT/Persona-style set — **Null, Repel, Absorb** — stays in the "Later" bucket, not because the idea's wrong (it's a great thematic fit) but because Repel/Absorb specifically invert or redirect damage rather than just scale it, which is exactly the kind of thing that could quietly produce a new unkillable "turtle" build (stack Endurance + a Repel/Absorb affinity against a common attack type) that `tools/simulate-battles` wasn't originally built to catch — that combination needs its own dedicated balance pass before it ships, not a casual addition on top of the MVP loop. Null is the cheapest of the three to pull forward early if wanted, since it's a flat zero rather than a redirect.

**Design-ahead is fine, implementation is not:** full Weak/Neutral/Resist/Null/Repel/Absorb affinity values can be designed now in the team's content spreadsheet for every archetype/build (cheap, it's just data) — the gate is specifically on turning Null/Repel/Absorb affinities on in a live build before they've had a dedicated balance pass.

**Refinement, confirmed: Repel/Absorb are asymmetric between player and enemy.** Weak / Neutral / Resist / Null can be innate, static affinities on both sides (player summons and enemies/bosses alike) — that part ships as originally scoped. **Repel and Absorb are player-accessible only as a temporary, activated skill, not an innate stat:**

- **Costed** — Mana and/or the turn itself, same philosophy as Guard: an active read with real opportunity cost, not a free passive.
- **Single-category, not blanket** — the player picks one damage category (e.g. Wind) to Repel/Absorb that activation, not "immune to everything." This is what makes it a skill expression (read the incoming attack, react correctly) instead of a panic button.
- **Short duration** — until the player's next turn, or a small fixed number of turns.
- **Natural home: a Fortune-category skill** — fits Fortune's "gamble for bigger effect" flavor (you're betting on a correct read), and keeps it distinct from Cards (which are meant to be always-on/universal, not a per-turn activation).
- **Enemies and bosses keep full access to permanent, innate Repel/Absorb** — this is standard SMT/Persona design (a boss nulling/absorbing your favorite element punishes blind attacking) and doesn't reintroduce the turtle-build risk, since that risk was specifically about a *player* stacking a permanent version.
- **Dependency to plan for:** this read-and-react loop only feels fair if enemies/bosses telegraph their next move (a wind-up animation, a UI tell) — `EnemyAI.luau`'s move-choice tables would need to expose "what's coming" to the client somehow. Worth scoping as its own small system alongside this, not assumed for free.

**School-wide affinity protection rule, confirmed.** No archetype in a school's roster should be **Weak** to that school's own signature damage type (Tung Tung = Strike melee, Wind element) — this is a roster-wide guarantee, not a requirement that every individual archetype personally specialize in that stat. Checking the current Tung Tung roster against this turned up one real conflict: Grove-Keeper's Affinity Profile had it Weak to Melee — Strike, which contradicted the rule even though Grove-Keeper itself has the roster's *lowest* Strength (it's the Magic-focused support, not a Strike specialist — the contradiction was with the school's identity, not with Grove-Keeper's own stat lean). Fixed by softening Grove-Keeper's Strike affinity from Weak to Neutral: it no longer undercuts the school's signature type, but it also isn't rewarded with a Resist it hasn't earned through its own stats. Base, Elder, and Sapling already satisfied the rule (Resist/Resist/Neutral respectively) and are unchanged.

### Guard — a universal defensive action

Every summon gets a **Guard** option on its turn, alongside its abilities — no Mana cost, no target. Combines Persona's Guard command with Wizard101's "pass to bank resources" idea, adapted to our Mana economy instead of pips:

**Why the conditional Mana and softer numbers matter:** the first draft stacked full damage reduction, crit immunity, ailment resist, *and* guaranteed resource gain onto one free, no-downside action — strictly better than attacking whenever there's no rush, which turns "sensible play" into "everyone guards to max Mana, then alpha-strikes" rather than a real turn-by-turn decision. Persona's Guard costs your whole turn for defense only; Wizard101's Pass gives no defense at all, just a bet on the resource. This version keeps Guard genuinely good without letting it dominate every turn where nothing is urgent.

- **Damage reduction:** a moderate additional cut (\~25–30%), applied **multiplicatively with Endurance's own reduction**, not stacked on top additively — a tank guarding gets meaningfully tankier, but doesn't approach near-immunity. (Endurance alone caps at 60% per the current formula; guarding a fully-built Endurance tank should land somewhere around 70–75% total reduction, not 80%+.)
- **Blocks critical hits:** an attacker cannot land a critical hit against a guarding target, regardless of their Luck.
- **Resists ailments (not blocks):** the attacker's effective Luck (or the resist roll) is reduced against a guarding target — meaningfully harder to daze, not immune.
- **Duration:** lasts exactly until this summon's own next turn, same as other turn-scoped statuses.

**Update — Guard's Mana bonus removed entirely.** Guard no longer grants any Mana, conditional or otherwise — it's now purely a defensive action (damage reduction, crit immunity, softened ailment resist). This is a further revision on top of the fix above, not a reversal of it: the conditional-Mana fix solved the original "free and resource-positive" brokenness, but the new HP/Mana leveling model (below) reworks the Mana economy enough that Guard doesn't need to be a Mana faucet at all anymore — removing it keeps Guard's job simple (a defensive choice, not a resource mechanic) and avoids the two systems fighting over the same lever.

**Open item — Guard has no enemy that rewards it yet.** With the Mana bonus gone, the battle simulator was run with several "guard when it makes sense" heuristics for sensible play against Wild Sapling, and every one of them lost win rate versus never guarding (by 2–37 points). Sensible play currently never guards, and the old "never guards" archetype was removed from the simulator's roster since it's now identical to sensible play. This isn't a sign Guard is broken — it's a sign Wild Sapling can't test it: it's a fast, low-durability placeholder dummy with no real burst, so a turn spent attacking is always worth more than the damage Guard would save. Don't chase this by buffing Guard's numbers against the current roster — that risks reopening the exact turtle-stalling problem the Mana removal closed, just against an enemy too weak to punish it either. Before any of this is called validated (in either direction), it needs testing against an enemy with meaningful burst or a telegraphed heavy hit — something Phase 1's roster doesn't have yet. Treat that as a requirement for whenever tougher enemy content is designed, not a Guard-tuning task.

**Telegraphed heavy attacks for bosses, confirmed — the answer to the Guard open item above.** A boss can spend a turn visibly winding up (charge animation, glow, a HUD warning, the camera holding on it) and release a heavy hit on its next turn, roughly 2.5–3× a normal attack (the exact multiplier is a `CombatConfig` number, tuned with `simulate-battles`).

- **Who gets it:** mainly bosses, and many of them, not every one. Regular enemies don't use it by default.
- **Target shape is per boss:** each boss's charged attack is either single-target (the targeted player has to react) or party-wide (everyone has a reason to Guard). It's a field on the ability, not a global rule.
- **Player answers:** Guard (its existing damage cut and crit immunity, unchanged), healing up ahead of the release, or racing the boss down. Guard's numbers are not changed for this.
- **Validation:** with a charging boss in the simulator, sensible play that guards against the telegraphed hit must beat sensible play that never guards, and turtle play must still lose. That's the test the open item above asked for.
- **Later hook:** if the Down system is built, knocking a charging boss Down could cancel the charge. Not part of the first build.

**Down / ONE MORE! / ALL-OUT ATTACK — current status.** Down and ONE MORE! are likely but not designed yet; ALL-OUT ATTACK is undecided. The UI handoff described all three as decided; this supersedes that. The HUD pieces for all three stay built but switched off (`Flags.DownSystem`), and none of their rules exist on the server.

**What doesn't carry over from Persona, and why:** Persona's Guard also negates a would-be Knockdown when a hit lands on an elemental weakness — we don't have a weakness/knockdown/"1 More" bonus-turn system yet (that's tied to the still-open Slash/Pierce type chart, currently on hold). Guard's damage/crit/ailment protection ports over cleanly now; the weakness-negation piece becomes relevant once a real type-weakness system exists.

**Relationship to the existing `Guarded` status:** the Elder's Windbreak ability already applies a `Guarded` status (damage taken × 0.6) as a costed active skill. This new universal Guard action is a separate, stronger, free defensive choice available to *every* summon — keep both: Windbreak is a Mana-cost skill with its own numbers, universal Guard is name-your-own-poison risk management with no cost. Give the new one its own status id (e.g. `Bracing`) so they don't collide or overwrite each other if both are active.

### The player character on the field (Persona/Metaphor-style presentation)

**Confirmed:** the visible combat model on your side is the **player character**, not the summon. The summon is an extension of the character, not a stand-in for them — it only visually appears when its own ability is used, then returns to the character. This matches how Persona's protagonist stays on-field while their Persona flashes in for a spell, and how Metaphor's Archetypes work the same way.

**What the player character does directly (no summon flash-in):**

- **Base Attack** — a new, universal, **free** action (no Mana cost) every player character has. Damage scales off the active summon's Strength for now (there's only one Strength value to draw from until gear exists); once weapons are added (Gear System, above), the equipped weapon modifies this attack directly — base attack is the action a future weapon actually affects, per your Persona reference.
- **Guard** — already spec'd above; performed by the character, not the summon.
- **Items** — a future feature (not built now), also performed by the character, not the summon.

**What triggers a summon appearance, and how it's staged (Stand/Persona-style):** using one of the active summon's own abilities (Strike, Gale Clap, Windbreak, Sap Mend, etc.) summons it into frame **behind or alongside the character** — not a full-screen replacement of the character model, and not the character vanishing. Think JoJo's Stands manifesting at their user's shoulder, or a Persona looming up behind its wielder: the character stays visible and grounded in the pose that triggered the cast, the summon materializes in its own space next to/behind them for the duration of the ability, then derezzes/dismisses back out once the ability resolves. This is a two-model composition during a summon-ability turn (character + summon on screen together), not a swap between two mutually-exclusive models — the earlier "swap to the summon model" phrasing is superseded by this: the character model never leaves frame during Base Attack, Guard, or a summon ability.

**What doesn't change:** the summon still owns all five combat stats (Strength, Magic, Endurance, Agility, Luck) and the HP/Mana pools — this is a presentation and action-ownership layer on top of the existing data model, not a change to who carries stats. `BattleSession`'s internal participant data doesn't need to change; this is primarily how the client (`BattleView`) renders each turn — the character model is always on screen, and the summon model is spawned in behind/alongside it only for the duration of a summon-ability animation (Stand/Persona-style), then despawned — plus one new zero-cost `Attack` entry in `Abilities.luau`.

**Enemy side is unaffected:** enemy BrainRot creatures (Wild Sapling, etc.) keep fighting as themselves — there's no "enemy trainer" character, since only the player party has a character/summon split.

## Step 7 — Game Economy

### Currencies

- **Main currency (soft):** earned through normal play — dungeon clears, quests, hub activities. Spent on gear, Power Pip Chance items, and consumables.
- **Premium currency:** purchasable, spent only on cosmetics and convenience (extra summon storage, cosmetic recolors) — never on anything that raises combat stats, per the no-pay-to-win goal.
- **Dungeon rewards:** a dungeon-specific token or drop table feeding gear and summon unlocks, separate from soft currency so dungeon progression can't be entirely bought out with grinding elsewhere.
- **Event currency:** introduced only with seasonal events post-launch; not needed at MVP.

### Sources

Dungeon clears (primary), daily/weekly activities, quest completion, hub part-time-job-style minigames, social-link milestone rewards.

### Sinks

Gear upgrades and Power Pip Chance items, cosmetics (character and summon), consumables (single-use combat items, if added), a summon-roster expansion cost if collection isn't purely drop-based.

### Avoiding the failure modes named in the brief

- **Inflation:** cap or taper soft-currency gain from repeated content (diminishing dungeon-clear rewards past the first clear per day/week) rather than letting a fixed grind loop print unlimited currency.
- **Excessive grinding:** gate summon/gear progression on multiple sources (dungeon drops *and* currency *and* quests) so no single repetitive loop is the only path forward.
- **Pay-to-win:** hard rule — premium currency touches cosmetics and convenience only; every combat-relevant item (gear, Power Pip Chance boosts, summons) is earnable through play. This is the single rule most worth protecting as scope grows.
- **Currency becoming meaningless:** keep sinks slightly ahead of sources early (small persistent costs — gear repair/upgrade fees, cosmetic rotation) so currency stays relevant instead of piling up unused.
- **Reaching endgame too fast:** the MVP's one school/one dungeon scope means "endgame" is intentionally small at launch — the real anti-rush lever is Phase 7's content cadence (new dungeons, second school), not artificial currency throttling.

### Monetization while maintaining trust

Cosmetics (character outfits, summon skins/recolors) and convenience (inventory space, faster summon-roster browsing) are the only premium-currency spends at launch. Avoid loot-box-style random premium purchases for anything gameplay-relevant — if BrainRot summons are ever sold, sell a specific named one directly rather than a randomized pull, especially given the audience skews younger.

## Gear System (Later/Could-have)

Wanted eventually, not for MVP — a Persona-style equipment layer sitting on top of the five-stat model:

- **Weapons:** drive physical (Strike/Slash/Pierce) basic-attack and skill damage. Carry a crit-rate modifier and can grant an elemental boost (a Wind-Boost equivalent) — this is where melee-type identity (once Slash/Pierce exist) becomes a gear choice, not just a school trait.
- **Armor:** sets base defense and evasion against both physical and magical damage — layers on top of the Endurance/Agility formulas already in the combat architecture (Step 6), rather than replacing them.
- **Accessories:** the flexible slot — can grant a skill outright, a flat stat boost, or immunity/high evasion to a specific element (a Wind-immunity accessory, say). Precedent: Persona's Reaper-drop "Divine Pillar" grants Almighty-damage immunity.
- **Passives:** any gear piece can carry a passive independent of its slot — extra max Mana, a flat Strength/Endurance boost, or, rarely, an accessory that grants an entire bonus ability.

**Why this waits:** gear is a real itemization/economy sink (ties directly into Step 7's Sinks list) and a natural next step after Power Pip Chance gear is already live, but it's a full new system — inventory slots, drop tables, an equip UI — layered on top of everything else. Consistent with the MVP-scope discipline elsewhere in this doc: prove the four-summon combat loop is fun first, then add gear once there's a reason to keep playing past the first few fights.

**Weapon damage-category mapping and affix architecture, confirmed (still Later/Could-have — not pulled into MVP).** The Weapons bullet above already specified Strike/Slash/Pierce as the physical damage categories weapons drive; this fills in the concrete mapping: **Slash** (swords, axes), **Pierce** (spears, bows), **Strike** (hammers, gauntlets/brass knuckles) — Strike is Tung Tung's own school signature, so a Tung Tung player's natural weapon affinity is Strike-type gear. Affixes (the Passives bullet above) get a placeholder shape to design against: an affix specifies a Type (flat stat boost, percent stat/resource boost, or an on-hit status proc), what stat/resource it affects, and its effect text — e.g. "+2 Strength" (flat), "+8% Max HP" (percent), "Burn Chance" (proc, ties into Fortune-style ailments later). None of these example values are final rules; they only pin down the table shape ahead of the real affix-design pass, consistent with this whole section staying deferred past MVP.

**Weapon ATK/HIT combat rules, confirmed scope (formulas still W.I.P. — design-only for now, since weapons aren't in the game yet).** How a weapon's two stats will plug into the combat math once gear exists, locked as a design decision but explicitly not implemented in `BattleSession.luau` yet — the user's own words: "weapons are not in the game yet, we can develop this later," and "we still need to work that out to make sure it doesn't make builds completely broken." Two different rules apply depending on who's swinging the weapon:

- **The player's own universal Attack (the one action that's actually theirs, not the summon's):** a weapon fully defines it. Weapon ATK becomes the attack's power value (replacing today's flat placeholder), still scaled by the active summon's Strength exactly as now. Weapon HIT (e.g. 85%, 95%) becomes this attack's hit chance outright, replacing the Agility-vs-Agility roll for this one action only.
- **The summon's own abilities — Strike, elemental, Fortune, heals, everything in its kit:** Weapon ATK is only a small *amplifier* multiplied onto the ability's existing stat-driven output (in the same "multiply an already-small base" shape as the HP/Mana floor+gap formula), never a second additive power source and never a replacement for Strength or Magic. That construction is what guarantees the balancing constraint holds by math, not by tuning discipline: amplifying a low-Magic character's small Magic-driven base keeps the result small no matter how strong the weapon is, so a high-ATK weapon on a non-magic tank still can't out-damage or out-heal a dedicated mage. The exact amplifier constant (likely different, and small, for Strength-scaled vs. Magic-scaled abilities) is unset — it needs real weapon numbers and a `simulate-battles` pass before it's trustworthy, the same caution that applied to Guard's numbers earlier.
- **Weapon HIT never touches the summon's own abilities.** Skills and spells keep resolving accuracy independently through the existing Agility-vs-Agility `hitChanceFor` formula, completely unchanged — the HIT stat only ever gates the player's bare-handed/weapon-handed universal Attack above.

No code changes land from this yet: there's no weapon data on a `Participant` at all, so this is a rules lock to build against once the gear system actually gets picked up, not a handoff for this round.

## Step 8 — Retention

### Short-term (10–30 minutes, one session)

What has to land in a single sitting: a readable combat loop that feels good within one or two fights, a visible reward at the end of the one launch dungeon, and a hub that gives the player something to do (a quest hook, an NPC, a shop) the moment they land. If a first-time player can't clear at least one small fight and see a reward within their first session, the rest of retention design doesn't matter.

### Medium-term (several sessions)

- Quest chain progression through the single launch school
- Social Link milestones with the 2–3 launch NPCs (each level-up is a natural "come back for the next one" hook)
- Summon collection — "I don't have that BrainRot yet" is a strong, low-cost medium-term pull once 3–4 summons exist
- Daily login/activity rewards (Should-have) giving a light reason to check in even on a short session

### Long-term (weeks/months)

- Full social stat progression once all 6 stats are live (post-MVP)
- Power Pip Chance gear chase (Should-have) — itemization goals that don't cap out quickly
- Seasonal BrainRot events (Could-have) as the recurring "new content" drumbeat
- A second school (Could-have/Phase 7) as a major long-term unlock, not a launch feature

### What NOT to lean on

Per the brief's own instruction: no artificial grinding purely to pad playtime. Concretely, that means daily rewards should feel like a bonus for playing, not a system the player feels penalized for skipping, and drop rates for summons/gear should be tuned so persistence pays off rather than requiring extreme repetition. Retention should come from the loop being genuinely worth returning to (a fun fight, a summon you want, a relationship you're building) — anything that only works by making play tedious is a red flag to cut, not tune.

**Realistic framing for a first Roblox game from a 5-person team:** most of medium/long-term retention here depends on Should-have and Could-have systems, which is intentional — MVP's job is to prove the short-term loop is fun at all; retention systems get built once that's confirmed, not before.

## Step 9 — Roblox Discovery & Growth

### How Roblox Discover works, in short

Roblox's algorithm surfaces games largely based on early engagement signals — click-through rate on your thumbnail/icon, and how long/often players who click actually stay and return. A great first-session experience isn't just good design, it's directly what earns more Discover placement.

- **Thumbnails/icon:** clear, high-contrast, readable at small size, and should communicate genre fast — a BrainRot summon mid-attack or a stylized turn-based battle moment reads better than a hub screenshot. This is worth real art time even at a 5-person team's scale, since it's your highest-leverage single asset for discovery.
- **Title & description:** front-load the hook (summon-battling meme characters, school RPG) rather than a generic "RPG game" — players and the algorithm both reward specificity.
- **First-session experience:** the single biggest lever — Roblox weighs early retention heavily, so a confusing first five minutes costs you algorithmically, not just anecdotally. This is the direct payoff of Step 2's Must-have UI requirement.

### Community building

- **Discord:** set this up before launch, even small — it's where your most engaged early players give feedback and where you'll source your first playtesters for Phase 5 (Beta).
- **TikTok/YouTube Shorts:** the BrainRot summon concept is genuinely well-suited to short clips (a recognizable meme character doing a flashy combat move) — treat a few shareable combat moments as a content-creation goal, not an afterthought.
- **Creator/influencer outreach:** realistic for a 5-person team only at small scale — a handful of small Roblox-focused creators covering your launch is a more attainable goal than chasing large influencers.

### Metrics that matter, and why

| Metric | Why it matters |
| --- | --- |
| Day 1 retention | Signals whether the first session actually lands; the single most important early number |
| Day 7 retention | Signals whether the medium-term loop (Step 8) is working |
| Average session length | Too short = pacing/onboarding problem; healthy length varies by genre, so compare against your own baseline over time, not an external target |
| Concurrent players | Drives Discover visibility somewhat, but is a lagging indicator of the above, not something to chase directly |
| Conversion to monetization | Matters for sustainability, but should be tracked without letting it influence combat balance (see Step 7's no-pay-to-win rule) |

### Realistic goals for a first Roblox game from a 5-person team

Don't benchmark against large studio Roblox titles. A modest, achievable early target: enough Day 1 retention that a meaningful fraction of new players return at least once, and slow organic growth via Discover + your own Discord/social presence over the first few months — rather than a large launch spike. Most Roblox games, including well-made ones, do not go viral immediately; treat Phase 6–7 as a slow-build phase, and let actual Day 1/Day 7 numbers from your Beta (Phase 5) set realistic targets rather than guessing pre-launch.

## Step 10 — Risk Analysis

| Risk | Mitigation |
| --- | --- |
| Scope creep | The Must/Should/Could/Do-Not-Build-Yet cut in Step 2 is the primary defense — any new idea gets sorted into that list before it's built, never added ad hoc |
| Too many systems / too much content | One school, one dungeon, \~4 summons at MVP; expansion only after Phase 2's vertical slice proves the loop |
| Complex multiplayer architecture | Resolved by the individual-turn (Option A) decision — removes the simultaneous-resolution problem that made Options B–D riskier |
| Poor onboarding | Combat/HUD UI is Must-have, not Should-have, specifically to prevent this; playtest the first 10 minutes repeatedly in Phase 2–5 |
| Boring combat | Prototype (Phase 1) exists specifically to test this with placeholder art before any art/content investment goes in |
| Empty world | MVP scope keeps the world small (one hub, one school) so it can be dense rather than large-and-empty on a 5-person budget |
| Weak progression | Player-scales-summon-ceiling model (Combat stats section) gives progression to both the character and the summon-collection layers |
| Excessive grinding | Addressed directly in Steps 7–8 — multiple progression sources, no artificial padding |
| Lack of differentiation | The Persona-social + Wizard101-school + BrainRot-summon combination is the differentiator; Step 1 already flags this as the core "why this and not another Roblox RPG" |
| Development bottlenecks | Step 4's role split plus the explicit "don't combine Producer + sole combat engineer" warning |
| Team burnout | The phase-gated roadmap (Step 3) exists so the team is never trying to build Should/Could-have features and Must-have features simultaneously under launch pressure |
| Poor monetization | The cosmetics/convenience-only rule (Step 7) heads off both pay-to-win backlash and the younger-audience trust risk |
| Technical debt | Server-authoritative, data-driven architecture (Step 5) — schools/abilities as data rather than hardcoded logic — keeps early shortcuts from compounding as badly |
| Inconsistent UI/UX | Sole UI/UX ownership (Step 4) rather than splitting visual identity across multiple people |

### The compounding risk: Persona-social + turn-based + multiplayer + school-sim + live-service, all at once

This combination is real risk, but it's already been substantially de-risked by the decisions made earlier in this doc, not by cutting ambition:

- **Turn-based + multiplayer** was the riskiest pairing on paper (real-time netcode for simultaneous turns is hard) — the individual-turn/Agility decision sidesteps most of that complexity by construction.
- **School-sim + social system** is the most content-hungry pairing — mitigated by launching with one school and 2–3 NPCs rather than the full social-stat/multi-school vision.
- **Live-service (retention/events)** is explicitly deferred past MVP in Step 8 — it's a Phase 7 concern, not something the core build has to support from day one.

The remaining real risk is simply **total system count** — even at MVP scope, this is combat + party + social link stub + economy + progression + UI, all interconnected. The single biggest thing that keeps this achievable for 5 people is refusing to add a 7th or 8th system (trading, PvP, housing, crafting, matchmaking) until the first six are proven fun together.

## Step 11 — Prioritized Open Questions

### Critical (answer before development starts)

1. ✅ **Answered:** TungWarts University — Tung Tung School (Strike melee + Wind element). See Launch School section above.
2. 🟡 **Partially answered:** four Tung Tung Sahur variants proposed (Base, Elder, Sapling, Grove-Keeper) — open question is whether all four launch at once or two are held back.
3. ✅ **Answered:** initiative is a per-battle roll + Agility modifier (D&D-style), not a strict Agility sort — see Combat philosophy and Step 6.
4. Team role assignments against the 5 people you actually have (Step 4 is a template, not yet mapped to real names)
5. Whether Rojo + GitHub is the team's actual workflow, or whether Roblox Studio's built-in Team Create is preferred for a first project (affects Phase 0 setup time)

### Important (answer during prototyping)

6. Exact HP/Mana/pip formulas — how stats translate to numbers (e.g., does 1 Vitality = X HP?)
7. The single damage-type weakness axis for MVP (Step 6) — what are the actual types, and which summons/schools map to which
8. Enemy AI weighting specifics for the one launch dungeon's encounters
9. What the 2–3 launch Social Link NPCs actually are, and their relationship-level reward beats
10. Whether flat pip generation is 1-per-turn or scales with something (Agility? a fixed rate?)

### Later (can wait until the core loop works)

11. Second-school concept and timing (Phase 7)
12. Mounts — functional or purely traversal/cosmetic
13. Full 6-stat social system rollout order
14. Seasonal BrainRot event cadence and format
15. Long-term monetization catalog beyond the initial cosmetic set

---

## Final Deliverable Summary

The source brief asked for these 32 items. Status: ✅ drafted above, 🔲 blocked on a Critical open question (Step 11) being answered first.

1. ✅ Game Vision — Step 1
2. ✅ Core Gameplay Loop — Step 1
3. ✅ Core Progression Loop — Step 1
4. ✅ Multiplayer Loop — Step 1
5. ✅ Turn-Based Combat Loop — Step 1 / Combat philosophy
6. ✅ MVP Feature List — Step 2
7. ✅ Post-Launch Feature List — Step 2 (Could-have / Do-Not-Build-Yet)
8. ✅ Game Systems Overview — The eight systems section
9. 🔲 School System Proposal — needs the launch-school choice (Critical Q1)
10. ✅ Party System Proposal — Multiplayer & party system / Step 6
11. ✅ Turn-Based Combat Proposal — Combat philosophy / Step 6
12. 🔲 Social Link Proposal — needs the launch NPCs (Important Q9)
13. 🔲 Social Stat Proposal — needs which 2 stats launch first (Step 2 names Charisma + Guts as a placeholder; needs confirming)
14. ✅ Dungeon Proposal — The eight systems section / Step 3 Phase 2
15. 🔲 Pet/Mount Proposal — cosmetic-only decided (Step 2); full proposal needs Later Q12 (functional vs. cosmetic mounts)
16. ✅ Hub/World Structure — The eight systems section / Step 1 exploration loop
17. ✅ UI/UX Design Philosophy — UI/UX section
18. 🔲 Visual Identity Proposal — needs the launch school/summon roster locked first (Critical Q1–2)
19. ✅ UI Screen Inventory — UI/UX section (the 22-deliverable list)
20. 🔲 Combat/Party UI Proposal — layout work blocked on Step 6 combat depth being finalized
21. 🔲 Social/Character/Quest UI Proposal — blocked on Critical Q1/Important Q9
22. ✅ Economy Proposal — Step 7
23. ✅ Monetization Proposal — Step 7
24. ✅ Retention Strategy — Step 8
25. 🔲 5-Person Team Structure — Step 4 gives the template; needs mapping to your actual 5 names (Critical Q4)
26. ✅ Roblox Technical Architecture — Step 5
27. ✅ UI Development Workflow — UI/UX section (tools/pipeline)
28. ✅ Development Roadmap — Step 3
29. ✅ Risk Analysis — Step 10
30. 🔲 Launch Strategy — needs Step 9's Discord/community setup actually scheduled against Step 3's Phase 6
31. ✅ Questions We Need to Answer — Step 11
32. 🔲 First 10 Things Our Team Should Do — best written once Critical Q1, Q2 and Q4 are answered, so the list points at real tasks instead of placeholders

**Bottom line:** 21 of 32 are drafted. The remaining 11 all trace back to the same handful of decisions — pick the launch school, pick 3–4 starting summons, name the 2–3 launch NPCs, and assign your 5 real teammates to the Step 4 roles — and I can fill in the rest against real content.

**Recommended next step:** work through the 5 Critical questions above — once the launch school and starting summon roster are picked, I can draft the remaining school/party/combat/dungeon/pet system proposals (items 9–15) and the UI screen layouts (items 19–21) against real content instead of placeholders.
