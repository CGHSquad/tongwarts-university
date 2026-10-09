# TungWarts University: UI Implementation Handoff

**Audience:** (1) a Claude chat that will review this and relay it, and (2) Claude Code, which will build the UI in Roblox Studio via the repo `CGHSquad/tongwarts-university` (Rojo workflow, Studio MCP).
**Source:** the UI design work done in a separate Claude chat with the project owner (Chris). This document is the complete record of that work.
**Status:** 7 screens have approved mockups (look and layout). The mockups are **style and layout references, not pixel specs.** Behavior is specified here.

---

## 0. Instructions for the relaying chat (Part A)

You are receiving a UI handoff package. Do these in order. **Do not redesign anything.**

1. Read `docs/GDD.md` in the repo (or the project doc) and find the existing combat code (`BattleSession`, `BattleView`, `Abilities.luau`, `PartyManager`, `PlayerProfile`, `RewardTable` are named in the GDD).
2. Check this document against the GDD and the code. List every **conflict** and every **open question** you find, in a short table. Section 4 already lists the ones I know of. Add yours. Don't resolve them silently.
3. Put these files in the repo: `docs/ui/UI_HANDOFF.md` (this file), `docs/ui/ASSET_PROMPTS.md`, `docs/ui/mockups/S1_…S7_….png` (the seven mockups), and `tools/cut_sheet.py`. Claude Code can't see images that only exist in a chat, so the mockups must be committed.
4. Send Claude Code the **kickoff prompt in section 14 (Part B)**, adjusted for the real repo layout. Tell it to stop after Milestone 0 and report.

---

## 1. Project context

- **Game:** TungWarts University, a Roblox school-based social RPG. Persona-style **turn-based, party-based combat** (3 to 4 real players per party) where each player fights with a summoned "BrainRot" character (for example Tung Tung Sahur). Wizard101-style pips layered on Mana.
- **Team:** 5 people, first Roblox game. The UI/Artist/Technical Designer owns UI. Code is synced with Rojo; the GDD is `docs/GDD.md`.
- **Platform priority:** **mobile first.** Most Roblox players are on phones. The UI must also work on tablet, PC and console.
- **Architecture (from the GDD):** the server is authoritative for everything (HP, Mana, pips, turn order, rewards). **The client only renders what the server sends and requests actions.** UI must never hold its own copy of truth.
- **Look:** navy and obsidian panels, celestial-gold trim, torn ink-brush edges, angular slanted shapes, cyan and arcane-purple accents, Persona 5 / Metaphor: ReFantazio energy, high contrast, large readable type.
- **Characters:** the game uses the **R15 blocky avatar**. The illustrated characters in the mockups (wizard hats, anime faces) are **not canon**; they're placeholders for the live 3D models.

## 2. Ground rules (apply to everything)

1. **Safe zones (normative).** Keep these clear of UI on every screen:
   - **Top-left corner:** Roblox's own menu and chat icons.
   - **Bottom-left and bottom-right corners (about the bottom 25% of the height at each side):** the mobile thumbstick and jump button.
   - Keep key UI inside the middle ~85% of the screen.
   - Use `ScreenGui.ScreenInsets` (for example `CoreUISafeInsets`) and verify the behavior in Studio. In combat, Roblox's default touch controls can be disabled, which may free the bottom corners; verify before relying on that.
2. **Large text.** Minimum body text about 18 px at 1080p-equivalent, and tap targets at least 48 px, ideally 56 px or more. No tiny text. Use `UIScale` or scale-based sizing.
3. **No controller glyphs.** Use tap icons and key hints. Show key hints (for example `[Q]`) only when a keyboard is the active input (`UserInputService.KeyboardEnabled` and not `TouchEnabled`). Support touch, mouse, keyboard and gamepad (`GuiService.SelectedObject`).
4. **No baked-in text** in image assets, except the two lettering pieces (ONE MORE!, VICTORY). All other text is live and goes through a `Strings` table (localization-ready).
5. **No compass motif.** The compass is not part of the game's identity. Use four-point stars and rune rings. (The S1 and S2 mockups still contain compass shapes; **ignore them**.)
6. **Mana, not MP.** The GDD names the resource **Mana**. The mockups write "MP". Use a `Strings` constant (`Strings.Mana` / `Strings.ManaShort`) so it can change in one place.
7. **3D replaces illustration.** See section 3.
8. **Theme tokens.** Put all colors, fonts and sizes in one `Theme` module (see section 5.3). The schools have their own colors (for example TungWarts is forest green, gold and white), so the UI palette must be swappable per school accent.
9. **Server authority.** UI reacts to server events and sends action requests. It never computes damage, weaknesses, turn order, or rewards.
10. **Do not invent game rules.** If something isn't in the GDD or this document, stub it and list it as an open question.
11. **Placeholders are placeholders.** Names like Kai/Ember/Fern/Nyx, Gale Slash, Ember Burst, Pyromancer, "12,480", and all numbers in the mockups are sample data.

## 3. What the 3D models change

| In the mockup | In Roblox |
|---|---|
| Hero, party and enemy illustrations in the battle scene (S1, S7) | Live 3D models in the battle arena. UI is overlaid. |
| Command ribbons "bursting off the hero" (S1) | Screen-space UI placed relative to the hero's screen position (`WorldToViewportPoint`), clamped to the safe area. |
| Enemy name, HP bar, WEAK marker, DOWN tag over enemies (S1, S7) | `BillboardGui` anchored to each enemy (constant pixel size), or screen-space UI projected from the enemy position. |
| "Dizzy" stars on a downed enemy (S1, S7) | A world VFX plus a DOWN tag. The enemy plays a knocked-down animation. |
| Hero profile illustration (S2) | The player's own R15 avatar in a `ViewportFrame` (with `WorldModel`), or a hub camera shot. One viewport at a time on mobile. |
| Summon illustration (S3) | The summon's 3D model in a `ViewportFrame` + `WorldModel`, slowly rotating, with an idle animation. |
| Party portraits and head icons (S5, S1 cards, S6 rows) | Avatar headshots: `Players:GetUserThumbnailAsync` (handle failure with a fallback) or a small head-only `ViewportFrame`. |
| Party celebration pose (S6) | The live party models on the victory stage, with a victory animation. |
| Backgrounds (S2, S6, S1, S7) | The live 3D world, blurred or dimmed with `BlurEffect` / `DepthOfField` when a menu opens. |
| Backgrounds with no 3D scene (S3, S4, S5) | Full-screen 2D images (see `ASSET_PROMPTS.md`, Sheet 11). |

The GDD says the **player character** stays on the field and the **summon only appears** during a summon ability (Stand/Persona-style, behind or alongside the character). Enemies fight as themselves.

## 4. Mockup vs. GDD: conflicts and open decisions

**Resolve these with the project owner. Don't guess.**

| # | Topic | What the mockup shows | What the GDD says / issue | Proposed handling |
|---|---|---|---|---|
| 1 | Resource name | "MP" | GDD: "Mana" | Use `Strings.Mana`. |
| 2 | **Down system** (DOWN, ONE MORE!, ALL-OUT ATTACK) | Shown in S1, S7 | The GDD says there's no weakness/knockdown/1 More system yet (tied to the on-hold type chart). Chris has since **decided** to use Persona's Down system: **ONE MORE! only when a hit lands on a weakness or a crit; ALL-OUT ATTACK only when all enemies are Down.** Combat rules are deferred to a combat GDD discussion. | Build the UI as **event-driven and behind a feature flag** (`Flags.DownSystem`). Don't invent rules. |
| 3 | Affinity row (S3) | 6 elements: Physical, Fire, Ice, Wind, Light, Dark, with Weak/Resist/Null | MVP has **one** weakness/resistance axis tied to school/BrainRot affinity; the full chart is "later". | Make the row **data-driven**: a list of 1 to N affinity entries `{id, icon, state}`. |
| 4 | **Skill tree** (S4) | Branching class tree (Pyromancer, Stormcaller, Warden, Oracle, Runesmith) | GDD: summon evolution is "stronger, doesn't change identity", **"not a branching job tree"**. The class names don't match anything in the GDD. | **Unresolved.** Build the node/graph component generically; keep S4 last and behind a flag. Don't hard-code the class names. Ask what this screen should be (summon skill tree? school mastery?). |
| 5 | Party roles (S5) | LEADER / STRIKER / HEALER / CONTROLLER | GDD: roles are design language, not mandatory | Show only the party-leader marker at MVP. Role tags hidden by flag. |
| 6 | Party members | Names and levels | The party is **real players** (3 to 4), tracked by `PartyManager`. HP/Mana belong to each player's **active summon**. | Party rows bind to `PartyManager` + each player's active summon. |
| 7 | **Front/back rows, formation** | Removed | Undecided | Not in the UI. Leave a hook only. |
| 8 | Pips | Not shown | The GDD has Regular/Power pips that gate abilities. | **Not designed.** Add a placeholder pip display (open question). Ability rows still need pip cost/type fields in the data contract. |
| 9 | Command set | Attack, Spell, Item, Guard, Pass | GDD: Base Attack (free), Guard (free), summon abilities, **Items are a future feature**; "Pass" isn't defined (the GDD merged the pass idea into Guard). | Data-driven command list. **MVP shows Attack, Spell, Guard.** Item and Pass are behind flags. The ring must lay out 3 to 5 ribbons. |
| 10 | "Take the stage!" callout (S1) | A support-character banner | No such character in the GDD | **Optional / remove.** Reuse the component for tutorial hints only if wanted. |
| 11 | Currency | A gem icon, and the word MONEY in S6 | Soft currency name TBD | `Strings.Currency`, the icon is swappable. |
| 12 | Safe-zone violations in mockups | See table below | Rules in section 2 win. | Implement the rules, not the mockup positions. |
| 13 | Missing screens | N/A | See section 12 | Stub them. |
| 14 | UI palette vs. school colors | Navy / gold / purple / cyan | Schools have distinct color identities | Theme tokens with a school accent. |

**Mockup safe-zone deviations (implement per the rules, not the mockups):**
- **S1:** party cards sit in the bottom-right, and the skill card and the command ribbons are in the bottom-left.
- **S3:** the "next skill" plate ends at about 83% of the height.
- **S4:** the node tree and the detail card extend into both bottom corners.
- **S6:** the party rows extend to about 90% of the height in the bottom-left.
- S2, S5 and S7 are within the rules.

## 5. Architecture proposal

> Inspect the repo first and follow its existing conventions. This is a proposal.

### 5.1 Folder layout (Rojo)

```
src/shared/UITypes.luau            -- data contracts (section 6)
src/client/UI/
  init.client.luau                 -- bootstrap, creates ScreenGuis, ScreenManager
  Core/
    Theme.luau                     -- colors, fonts, sizes, school accent
    Strings.luau                   -- all visible text (Mana, Currency, labels)
    Layout.luau                    -- safe-zone rects, scale helpers, device mode
    Input.luau                     -- touch/keyboard/gamepad mode + key hints
    ScreenManager.luau             -- open/close/stack screens, focus, back
    Audio.luau                     -- named UI sound events (no assets yet)
    Assets.luau                    -- asset ids + fallbacks (section 9)
    Flags.luau                     -- DownSystem, ShowRoles, ShowItem, ShowPass, ...
  Components/
    SlicedPanel, TapButton, StatBar, Capsule, Tag, IconMedallion,
    ListRow, ViewportPortrait, HeadIcon, NodeHex, ThreadLine, TallyPlate
  Screens/
    CombatHUD/ (init, TurnOrderBar, CommandRing, EnemyOverlay, PartyCards,
                SkillList, Stamps)
    MainMenu, SummonStatus, SkillTree, PartyStatus, Results
  Preview/
    MockData.luau, Harness.luau, SafeZoneDebug.luau
```

### 5.2 Fallback-first approach (important)

Build every component to work with **zero art**: colored frames, `UIStroke`, `UIGradient`, plain text. Each component asks `Assets.luau` for its image; if the asset id is empty, it uses the fallback look. This lets all screens be functional, testable and reviewable **before** the art pack arrives, and lets art drop in later without code changes.

### 5.3 Theme tokens

```lua
Theme.Colors = {
  Obsidian = "#0B0D1A", Navy = "#121A3A", Gold = "#F2C14E",
  Purple = "#7B3FE4", Cyan = "#36D6F5", Crimson = "#D8283C",  -- crimson: enemy / weak only
  HpGreen, ManaBlue, TextLight, TextDim, Disabled
}
Theme.SchoolAccent = Color3  -- swapped per school
Theme.Fonts = { Display, Body }   -- pick from Roblox's built-in font library; verify in Studio
Theme.Sizes = { TapMin = 48, TextBody = 18, TextLabel = 14, ... }
```
Display lettering = a bold font + `UIStroke` outline (black) approximates the mockups.

### 5.4 Screen manager

Screens are a state: `None | Combat | MainMenu | SummonStatus | SkillTree | Party | Results | ...`. `ScreenManager` opens one, handles Back (Esc / BACK button / gamepad B), keeps focus order, and blocks gameplay input while a menu is open. Combat sub-states (command ring, skill list, target select) live **inside** `CombatHUD`.

### 5.5 Remote contract (proposal; match the existing code)

Client → server: `SubmitAction { battleId, actorId, kind = "Attack"|"Ability"|"Guard"|"Item"|"Pass", abilityId?, targetIds? }`
Server → client events (all drive the UI):

| Event | Payload | UI effect |
|---|---|---|
| `BattleStarted` | full snapshot | Build HUD, spawn name plates, turn bar |
| `TurnQueueChanged` | ordered `actorId[]`, active id | Slide tokens, mark NOW |
| `AwaitingInput` | `actorId`, `availableCommands`, `abilities[]` (cost, canAfford, `hitsKnownWeakness`) | Show the command ring (if it's your turn) |
| `ActionResolved` | `events[]` (see below) | Play effects, tween bars |
| `BattleEnded` | `result`, `rewards` | Open Results |

`events[]` entries: `DamageDealt{targetId, amount, crit, hitWeakness}`, `HealApplied`, `StatusApplied/Removed`, `EnemyDown{targetId}`, `DownCleared`, `OneMoreGranted{actorId}`, `AllOutAvailable{actorId}`, `Defeated{id}`, `WeaknessRevealed{targetId, element}`, `GuardStarted{id}`.
The server must reject illegal actions; the UI shows a short error toast.

## 6. Data contracts (Luau types, `src/shared/UITypes.luau`)

```lua
export type Id = string

export type Resource = { current: number, max: number }

export type Participant = {
  id: Id, side: "Player" | "Enemy",
  name: string, level: number?,
  hp: Resource, mana: Resource?,
  pips: { regular: number, power: number }?,   -- not designed yet
  statuses: { string }, isDown: boolean, isAlive: boolean,
  knownWeaknesses: { Id },                      -- element ids the player has discovered
  portrait: { userId: number? , modelId: Id? },
}

export type AbilityView = {
  id: Id, name: string, elementId: Id?, iconKey: string,
  cost: { mana: number?, pips: number? },
  canAfford: boolean, hitsKnownWeakness: boolean,
  description: string, needsTarget: "None"|"Single"|"All",
}

export type CommandView = { id: "Attack"|"Spell"|"Item"|"Guard"|"Pass", enabled: boolean }

export type BattleView = {
  battleId: Id, round: number,
  turnQueue: { Id }, activeId: Id,
  participants: { [Id]: Participant },
  localActorId: Id?,                 -- nil if it's not this client's actor
  phase: "Input" | "Resolve" | "Reward",
  allEnemiesDown: boolean,
}

export type AffinityEntry = { elementId: Id, iconKey: string, state: "Weak"|"Resist"|"Null"|"Normal"|"Unknown" }
export type StatEntry = { id: "Strength"|"Magic"|"Endurance"|"Agility"|"Luck", value: number, max: number }
export type SkillRow = { id: Id, name: string, iconKey: string, cost: number, locked: boolean, unlockLevel: number? }

export type SummonView = {
  id: Id, name: string, level: number, nextExp: number,
  modelId: Id, affinities: { AffinityEntry }, stats: { StatEntry },
  skills: { SkillRow }, nextSkill: SkillRow?,
}

export type PartyMemberView = {
  userId: number, name: string, level: number, isLeader: boolean,
  hp: Resource, mana: Resource, summonName: string, roleTag: string?,
}

export type RewardView = {
  exp: number, currency: number,
  items: { { id: Id, name: string, iconKey: string, count: number } },
  members: { { userId: number, name: string, expGained: number, leveledUp: boolean, newLevel: number } },
}

export type TreeNode = { id: Id, name: string?, iconKey: string, state: "Unlocked"|"Available"|"Locked", cost: number, parents: { Id }, desc: string, bonuses: { string } }
```

All strings come pre-translated or keyed from `Strings`. The UI never sends or trusts numeric outcomes.

---

## 7. Screen specs

Layout numbers are **approximate regions of a 16:9 screen** read off the 1672×941 mockups. Use scale-based sizing, anchored to the safe area.

### S1: Combat HUD (`S1_combat_hud.png`)

**Purpose.** The main battle screen. A live 3D battle with HUD overlays. The player taps a command, picks a target, and the server resolves it.

**Regions.**
- **Turn-order bar**, top center (x 27–70%, y 6–17%): a "ROUND n" label at its left end, then one token per participant in `turnQueue` order (player tokens gold-framed, enemy tokens crimson-framed). The active token glows cyan with a "NOW" label.
- **Enemy overlay**, over each enemy: name plate, HP bar (with numbers), crimson target brackets (when targeting), a **WEAK** marker (only when the weakness is known), a **DOWN** tag (when down). A downed enemy still shows its HP.
- **Command ring**, left side, near the hero: ribbons Attack, Spell, Item, Guard, Pass (3 to 5 shown per flags). Each ribbon is a big, separate tap target in a fixed color: Attack steel blue, Spell purple, Item green, Guard amber, Pass silver. They burst in with a stagger. The ring is shown only when it's the local player's turn and nothing else is open.
- **Party cards**, right side: one slanted card per party member (head icon, HP bar, Mana bar, active-turn highlight). Move them inward from the corner; the rules in section 2 apply.
- **Stamps**, center: **ONE MORE!** and **ALL-OUT ATTACK** (see states).
- **Hero Mana plate:** a small plate at the bottom center.
- **Optional** "callout" banner, top right (open question 10).

**Flow.**
1. `AwaitingInput` for the local actor → the command ring bursts in.
2. **Attack** → target select (tap an enemy; brackets appear) → `SubmitAction(Attack, target)`.
3. **Spell** → opens the S7 skill list. Choosing an ability → target select if needed → `SubmitAction(Ability)`.
4. **Guard** → `SubmitAction(Guard)` (no target).
5. **Item / Pass** → behind flags.
6. After submit, lock input and show "waiting" until `ActionResolved`.
7. When it isn't the local player's turn, hide the ring and show whose turn it is (the active token + name).

**States (all server-driven).**

| Element | Shown when |
|---|---|
| WEAK marker | The enemy's weakness is known to the player (`knownWeaknesses` is non-empty). How a weakness becomes known (scan, first hit) is a GDD decision. |
| DOWN tag + knocked-down pose | `isDown` is true |
| **ONE MORE!** stamp | `OneMoreGranted` event: the last hit landed on a weakness or a crit. **Only then.** |
| **ALL-OUT ATTACK** ribbon | `AllOutAvailable` event: **all enemies are Down.** **Only then.** |
| Command ribbons | It is the local player's turn |
| Guard indicator | `GuardStarted` for that participant |

**Animation.** Ribbons burst in over 0.2 s with a 40 ms stagger; selected ribbon scales to 1.08. ONE MORE! pops in with an overshoot (0.25 s), holds about 0.8 s, then fades. DOWN drops in and shakes once. ALL-OUT pulses a gold glow until chosen. HP bars tween with a delayed "damage" trail. Token slide 0.25 s.

**3D.** Enemy plates are `BillboardGui`s with fixed pixel size. Hero screen position comes from the character's root part. The ring layout must clamp inside the safe area and keep tap rects from overlapping (min 48 px).

**Acceptance.**
- With mock data the HUD renders at phone (for example 844×390), tablet and 1080p sizes with nothing in the safe zones.
- Every state in the table can be triggered from the preview harness.
- No button is smaller than 48 px. All text is readable at phone size.
- With `Flags.DownSystem` off, none of DOWN / ONE MORE! / ALL-OUT appear.

### S7: Skill selection (`S7_skill_select.png`)

**Purpose.** The list opened by **Spell** (and reused read-only for the Skill menu, and for Item with quantities).

**Regions.** A header plate ("SPELL") at the top right of the list (x 73–87%, y 8–18%); the list (x 73–95%, y 19–62%); BACK button top right; turn bar and hero Mana plate persist; the battle scene stays visible behind (dim and blur lightly).

**Rows.** Each row: element icon medallion, ability name, and a Mana cost capsule. Six rows maximum on screen, more scroll. States:
- **Selected:** wider, gold-cyan glow, expands to show a one-line description.
- **WEAK tag:** a crimson tag on the row's left edge, shown **only if `hitsKnownWeakness`.**
- **Dimmed:** the player can't afford it (`canAfford = false`). Visible but unselectable; tapping shows "Not enough Mana".
- **Locked:** (Skill menu only) very dark with a padlock.

**Interaction.** Tap a row to select (first tap selects and expands, second tap or a confirm button confirms), BACK or Esc returns to the command ring. Scroll for long lists. Selecting a row with `needsTarget = "All"` skips target select.

**Item variant.** Same layout with a quantity capsule (`x3`) in place of cost; the header reads ITEM. Items are a future feature (flag).

**Acceptance.** The list ends above the bottom corners. With 10 abilities it scrolls. WEAK tags and dimmed rows track the mock data.

### S2: Main menu / pause hub (`S2_main_menu.png`)

**Purpose.** The hub menu opened from the overworld.

**Layout.** Right half: the player's own 3D avatar (profile pose, looking up and forward) in a `ViewportFrame`. Left side: a kinetic stack of seven words (**SKILL, ITEM, EQUIPMENT, PARTY, SUMMON, QUEST, SYSTEM**), tilted along a shared perspective, with the selected word larger on an ink-brush slab. A currency plaque at the bottom center-right.

**Routing.** SKILL → S7 layout (read-only, active summon's skills). ITEM → item list (stub). EQUIPMENT → stub. PARTY → S5. SUMMON → S3. QUEST → stub. SYSTEM → stub (settings).

**Implementation notes.** Each word is a tappable slab with `Rotation` applied to the slab and its text together (Roblox can't skew). Selection moves with swipe, arrows or tap. The selected word animates in (scale 1.0 to 1.25, slab slides in). The menu opens with a slide-in from the left and the avatar sliding in from the right. **How the menu is opened on touch is undecided** (propose a small button at the middle of the right edge, not a corner).

**Acceptance.** Seven words are readable and separately tappable on a phone. The first menu opens in under 0.5 s. Only one `ViewportFrame` is alive.

### S3: Summon status (`S3_summon_status.png`)

**Purpose.** Inspect a summon: stats, affinities, skills, next skill.

**Layout.** Left column: name plate + "LV n" + "NEXT EXP n" tag; affinity row of round icons with status flags (WEAK red, RESIST blue, NULL gray, a dot for normal); five stat rows **Strength, Magic, Endurance, Agility, Luck** (number, label, bar, in a stair-step); a skill list (up to five rows, each with a cost capsule, the selected row highlighted); one dimmed **"NEXT Lv 13: Holy Arrow"** plate with a padlock. Right side: the summon's 3D model (rotating) in a `ViewportFrame` + `WorldModel`. BACK button top right. Background: a full-screen 2D image.

**Data.** `SummonView`. Stats use the GDD's five: Strength, Magic, Endurance, Agility, Luck.

**Interaction.** Tap a skill to select it (its description shows in the live text area). Drag on the model to rotate (optional). **A summon switcher is missing** (see section 12).

**Acceptance.** The left column ends above the bottom-left corner, text is large, and affinity count can be 1 to 6.

### S5: Party status (`S5_party_status.png`)

**Purpose.** Pick a party member to view their stats, and the party at a glance.

**Layout.** Left: title "PARTY", a "Whose stats?" plate, and up to four slanted banner rows (head icon, name, level, HP bar, Mana bar; the party leader marked). Right: overlapping profile busts of the party's avatars (non-interactive art). Background: full-screen 2D image. BACK button top right.

**Interaction.** Tap a row to select (highlight), tap again or confirm to open that member's active summon in S3. Tapping the busts does nothing.

**Data.** `PartyMemberView[]` from `PartyManager` plus each player's active summon HP/Mana. 1 to 4 rows; hide empty slots.

**Acceptance.** Rows end at about 75% of the screen height. 1 to 4 members all render.

### S6: Battle results (`S6_results_victory.png`)

**Purpose.** The reward screen after a battle.

**Layout.** A huge diagonal **VICTORY** (lettering image) with a "RESULT" ribbon; three stacked tallies (**EXP**, **Currency**, **Items** with item icons and counts); a party list (head icon, name, level, EXP gained, a **LEVEL UP!** badge where `leveledUp`); a **CONTINUE** button at the right-center (not in a corner); the party's 3D models posed on the right, with a victory animation.

**Animation.** Title slams in (0.3 s). Tallies count up from 0 over about 1 s with a tick sound, one after another. Level-up badges pop in. Gold sparks emit continuously (`ParticleEmitter`). CONTINUE appears after the tallies finish; tap anywhere during the count to skip it.

**Data.** `RewardView` (the GDD's `RewardTable` format).

**Flow.** CONTINUE → close results → return to the overworld.

**Acceptance.** Counting can be skipped. Nothing sits in the bottom corners.

### S4: Skill tree (`S4_skill_tree.png`): **UNRESOLVED (see section 4, #4)**

**Purpose (as designed).** A star-chart of hex nodes connected by gold threads, with a detail card on the right.

**Layout.** Full-screen 2D star-chart background; a graph of hexagonal nodes (about 12 in the mockup) connected by glowing threads; node states **Unlocked** (glow), **Available** (purple, "+" badge), **Locked** (dark, padlock); one **selected** node with a double ring; a detail card (emblem, name, description, bonuses, **UNLOCK** button with a cost tag); a skill-points plate at the top; BACK at the top right.

**Implementation.** Build a **generic graph component**: nodes (`TreeNode`) with positions in a normalized 0–1 canvas, drawn threads between parents and children. The canvas **pans (drag) and zooms (pinch)** inside the screen, since a real tree is larger than a phone screen. Node tap targets at least 56 px at the default zoom. Don't hard-code any class names; labels come from data.

**Acceptance.** Pan and zoom work with touch and mouse. All node states and the detail card render from mock data. **Don't build the game logic** until the GDD defines what this tree is.

---

## 8. Shared components (build first)

| Component | Used by | Notes |
|---|---|---|
| `SlicedPanel` | everything | 9-slice or 3-slice image + fallback frame |
| `TapButton` | everywhere | normal / pressed / disabled, 48 px min, press scale 0.95, sound hook |
| `StatBar` | S1, S3, S5, S6 | track + fill, tween, optional trailing damage bar |
| `Capsule` | S3, S7 | cost / quantity pill |
| `Tag` | S1, S7, S3 | WEAK / RESIST / NULL / DOWN / FRONT |
| `IconMedallion` | S3, S4, S7 | ring + icon, selected state |
| `ListRow` | S3, S7 | normal / selected / dimmed / locked, expandable |
| `ViewportPortrait` | S2, S3 | one 3D model, rotatable, with `WorldModel` |
| `HeadIcon` | S1, S5, S6 | avatar headshot with fallback |
| `TallyPlate` | S6 | animated count-up |
| `NodeHex`, `ThreadLine` | S4 | generic graph |
| `Toast` | all | short messages ("Not enough Mana") |

## 9. Assets

- Parts are produced from sheets in `docs/ui/ASSET_PROMPTS.md` (13 sheets, cut with `tools/cut_sheet.py`) and uploaded through Studio's Asset Manager. Record asset ids in `Assets.luau` as `rbxassetid://…`, keyed by name like `Combat_CommandBlue`, `SkillList_RowSelected`, `Tree_NodeLocked`.
- **Until an id is filled in, the component uses its fallback look (section 5.2).** Don't block on art.
- Stretchable parts use `ScaleType.Slice` with `SliceCenter`. Slanted shapes can't be skewed in Roblox, so panels are drawn horizontal with slanted ends and a plain middle. Whole-row tilt (for example S2's menu) uses `Rotation`.
- Use `ContentProvider:PreloadAsync` for each screen's assets before opening it. Keep images small (backgrounds about 1920×1080 at most).

## 10. Input and accessibility

- Touch: tap to select, tap again or a confirm button to confirm. Mouse: hover highlight, click. Keyboard: arrows or WASD to move, Enter or Space to confirm, Esc or Backspace for back, and `1` to `5` for commands. Gamepad: `GuiService.SelectedObject` navigation.
- Always provide a **BACK** button on sub-screens.
- Don't rely on color alone: WEAK, DOWN, etc. also have text or a shape.
- Respect reduced-motion: a setting to shorten shakes and flashes.

## 11. Testing

- **`Preview/Harness.luau`:** a Studio-only harness that opens any screen with mock data (`MockData.luau`) and cycles states: weakness known, enemy down, one more, all enemies down, can't afford a skill, 1 to 4 party members, long names, many abilities, level-ups, no items.
- **`SafeZoneDebug.luau`:** a toggle that overlays translucent red rectangles on the top-left and bottom corners so violations are obvious.
- Test in Studio's **Device Emulator** with at least a small phone (about 844×390), a tablet, and 1920×1080.
- Each screen's acceptance criteria (section 7) must pass before moving on.

## 12. Not yet designed (stub these; do not invent)

Equipment, Item inventory, Quest log, System/settings, a **summon collection / switcher** (needed for S3 and the summon "collect and swap" loop), a **pip display**, formation, shop, overworld HUD, the menu button on touch, a target-select presentation beyond the brackets, and defeat / game-over. Stub each with a "Coming soon" panel built from shared components.

## 13. Milestones

| M | Scope | Done when |
|---|---|---|
| **0** | **No code.** Read the GDD, repo and this doc. Report conflicts, a proposed folder plan, and the safe-zone approach. | Report delivered; owner approves. |
| 1 | Foundation: `Theme`, `Strings`, `Layout`/safe zones, `Input`, `ScreenManager`, `Flags`, `Assets` with fallbacks, `MockData`, harness, safe-zone debug, base components (section 8). | A blank screen opens/closes; components render with fallbacks. |
| 2 | **S7 + S1** on mock data, then wired to the real `BattleSession` events. | Section 7 acceptance for S1 and S7 passes; a real fight is playable with Attack, Spell, Guard. |
| 3 | **S6** results, wired to `RewardView`. | A fight ends in the results screen, counts up, returns to the world. |
| 4 | **S2, S5, S3** (with `ViewportPortrait`). | Menu to Party to Summon works end to end. |
| 5 | **S4**, only after the GDD defines it. | Blocked on a decision. |
| 6 | Art integration and polish (assets, animations, audio hooks, reduced-motion). | All fallbacks replaced; visual pass against the mockups. |

## 14. Kickoff prompt for Claude Code (Part B)

```
You're building the UI for TungWarts University, a mobile-first Roblox turn-based RPG, in this repo (Rojo + Studio MCP).

Read these first, completely:
1. docs/GDD.md
2. docs/ui/UI_HANDOFF.md (the full UI spec; follow it)
3. The mockups in docs/ui/mockups/ (S1 to S7). They are STYLE AND LAYOUT references, not pixel specs. Where they conflict with the safe-zone rules in the spec, the spec wins.
4. docs/ui/ASSET_PROMPTS.md for how the art will arrive later.

Non-negotiable rules:
- The server is authoritative. The UI only renders server data and requests actions. Never compute damage, weaknesses, turn order, or rewards on the client.
- Mobile first. Keep the top-left corner and the bottom 25% of both bottom corners free of UI. Large text, 48 px minimum tap targets, no controller glyphs.
- No baked-in text; use a Strings table. The resource is called Mana (not MP).
- Build every component to work with NO art (fallback frames, strokes, gradients) and read images from Assets.luau when available.
- Do not invent game rules. The Down system (DOWN, ONE MORE!, ALL-OUT ATTACK) must be event-driven and behind a feature flag. The skill tree (S4) is unresolved; don't build its game logic.
- Reuse existing code (BattleSession, BattleView, Abilities, PartyManager, PlayerProfile, RewardTable). Don't rewrite combat.

Do MILESTONE 0 ONLY and then STOP:
- Inspect the repo and summarize the existing combat and client code.
- List every conflict between the spec and the GDD or code (section 4 of the handoff has the ones already known; add yours).
- Propose the exact folder layout and module names for the repo's conventions.
- State how you'll handle safe zones (ScreenInsets) and the Studio test setup.
- List your questions for the project owner.
Do not write UI code until I approve the report.
```

---

## 15. Reference: mockup file map

| File | Screen | Notes |
|---|---|---|
| `S1_combat_hud.png` | Combat HUD | Contains compass shapes; ignore them. Safe-zone violations (see section 4). |
| `S2_main_menu.png` | Main menu | Contains a compass ring and clasp; ignore. |
| `S3_summon_status.png` | Summon status | Affinity set is a placeholder. |
| `S4_skill_tree.png` | Skill tree | Unresolved vs. GDD. |
| `S5_party_status.png` | Party status | Names and roles are placeholders. |
| `S6_results_victory.png` | Battle results | "MONEY" is a placeholder currency name. |
| `S7_skill_select.png` | Skill selection | Ability names are placeholders. |

---

## 16. Repo reconciliation (added by the relaying chat; the sections above are unchanged)

Checked against `docs/GDD.md` and the code at commit `cd9d12b`. Where this section and sections 5 to 14 disagree about **paths, names or what exists in code**, this section wins. Design intent (look, layout, behavior) is untouched.

### 16.1 Conflicts with the real repo

| # | Topic | Handoff says | Repo reality | Proposed handling |
|---|---|---|---|---|
| R1 | Folder layout | `src/shared/`, `src/client/UI/` | `default.project.json` maps only `src/ServerScriptService`, `src/ReplicatedStorage`, `src/StarterPlayerScripts`. | Use `src/ReplicatedStorage/UI/` (types, `Strings`, `Theme`, `Flags`) and `src/StarterPlayerScripts/UI/` (everything else). No Rojo mapping change needed. |
| R2 | Classes named in the handoff | `PartyManager`, `PlayerProfile`, `RewardTable` | These exist **only in the GDD**, not in code. The party is "the first `MaxPartySize` (2) players in the server", dealt summons in touch order (`CombatConfig`). | Don't look for them. Party rows bind to `BattleState.participants` (`side == "Party"`, `ownerUserId`, `ownerName`). |
| R3 | A combat UI already exists | Builds a new UI under `src/client/UI` | `StarterPlayerScripts/Combat/BattleUI.luau` (~1100 lines, working HUD, UIScale, `IgnoreGuiInset = true`), `BattleTheme.luau`, `BattleView.luau` (3D stage, nameplate BillboardGuis), and the headless tests drive that UI with bots. | **Decision needed (Q1).** Recommended: build the new HUD alongside, behind a flag, reuse `BattleView` (3D) untouched, switch over when S1/S7 reach parity, then delete `BattleUI`. Update the tests that pin the old UI in the same PR. |
| R4 | Remote contract (5.5) | New events: `BattleStarted`, `TurnQueueChanged`, `AwaitingInput`, `ActionResolved`, `BattleEnded` | One snapshot remote: `Remotes.Battle.StateUpdate` (`Snapshot`), plus `SubmitAction`, `RequestSync`, `Notice`. | **Add no remotes.** Derive UI events client-side from snapshots: `battle.lastAction` (`sequence`, per-target `hit/critical/damage/healed/knockedOut`) already carries what `DamageDealt`/`HealApplied`/`Defeated` need. `SubmitAction` takes an ability id; see R6. |
| R5 | View-model type names | `Participant`, `BattleView`, `Resource` in `UITypes` | `BattleTypes.ParticipantState` is the real shape, and `BattleView` is already a module name (the 3D stage). | Name UI view-models differently (for example `HudParticipant`) and build them from `BattleTypes` on the client. Keep the server types as the single source of truth. |
| R6 | Commands | Attack, Spell, Item, Guard, Pass as command kinds | Attack and Guard are **universal abilities** (`universal` in `Abilities.luau`), owned by the character, not the summon. "Spell" is the active summon's own ability list. No Item, no Pass (an idle player just times out via `turnDeadline`). | Ring = Attack (universal), Spell (opens S7 with the summon's abilities), Guard (universal). Submit them as ability ids. Item/Pass stay behind flags with no server support. |
| R7 | "Down" vs "KnockedOut" | `isDown` = Persona-style Down | `ParticipantStatus = "KnockedOut"` means **HP 0, out of the fight**. There is no Persona Down state. | Keep the words separate in code and strings. `Flags.DownSystem` stays off; there is no server source for DOWN / ONE MORE! / ALL-OUT (GDD: no weakness/knockdown/1 More system yet). Never map KnockedOut to the DOWN tag. |
| R8 | Weakness / affinities (S1 WEAK marker, S3 affinity row, S7 WEAK tag) | `knownWeaknesses`, `hitsKnownWeakness`, `AffinityEntry` | No affinity data anywhere in code or snapshots. `Abilities.damageType` ("Strike" or "Wind") exists as the future hook only. | Build the components data-driven and feed them empty/mock data. Hide WEAK/affinity UI when the data is empty. Don't invent a weakness rule. |
| R9 | Pips | Placeholder pip display | Phase 1 deliberately has no pips (`CombatConfig`); the GDD MVP is flat pips, not built. | No pip UI at M1 to M3. Leave the `cost.pips` field in the view-model only. |
| R10 | Results data (S6) | `RewardView` with exp, currency, items, per-member level-ups | Server has `phase = "reward"`, `winner`, `overworldReturnAt` and nothing else. No EXP, currency, items or levels exist. | S6 runs on mock data. Wire only VICTORY/DEFEAT, the party list and CONTINUE/auto-return to the real snapshot. Needs a server decision before real rewards (Q3). |
| R11 | Summon level / EXP / skill unlocks (S3) | `level`, `nextExp`, `nextSkill`, `unlockLevel` | Summons are static stat blocks in `Summons.luau`; leveling is GDD-only (Level 25 evolution, Mastery at Player Lv 40, etc.). | S3 shows stats, kit and the 3D model from real data; level/EXP/next-skill render from mock data or are hidden by flag. |
| R12 | Party size | "3 to 4 real players" | `MaxPartySize = 2`; a solo player controls both summons. | Make the HUD and S5 data-driven for 1 to 4 members (the handoff already says so). Test at 1, 2 and 4. |
| R13 | Missing phases the handoff doesn't mention | none | `phase = "setup"` (3 s initiative reveal, with `initiative.roll/bonus/total` per participant), `opening` (a side gets a bonus turn before round 1), and `turnDeadline` (turn timer). | The HUD needs an initiative-reveal state (show rolls and who struck first), a turn-timer indicator, and "opening turn" handling. Add to S1 acceptance. |
| R14 | Test harness | "Studio-only Preview harness" | `tests/Sim.luau` is a fake Roblox with bots using the real UI, and `lune run tests/run` must pass before pushing. It fakes TweenService but probably not ViewportFrame, ScreenInsets, GuiService, UserInputService device flags, or `GetUserThumbnailAsync`. | Extend `Sim.luau` as needed, add tests for the new HUD, and keep `lune run tools/typecheck` clean (all files `--!strict`). |
| R15 | Player/summon visuals | Avatar headshots and rotating summon model in a ViewportFrame | `BattleView` already has `copyAvatar(...)` and builds summon rigs from `ReplicatedStorage.SummonModels` via the `art` field in `Summons.luau` (skinned mesh + AnimationController, no Humanoid, facing -Z). `WildSapling` has no model (colored block). | Reuse that code path for S3's `ViewportPortrait`; use a stand-in when a summon has no `art`. Asset ids for UI images go in `Assets.luau`; summon asset ids stay in `Summons.luau`. |
| R16 | Scope | Milestones 4 and 5 (S2 menu, S3, S5, S4 tree) | CLAUDE.md: keep scope aggressively aligned to the MVP cut. Menus, summon status and party screens are not Phase 1 combat. S4's class tree contradicts the GDD ("not a branching job tree"). | Authorize **M0 to M3 only** (foundation, S7, S1, S6). Hold M4 until the roadmap reaches it; keep M5 blocked. |
| R17 | S4 skill tree vs. evolution | Section 4 #4 quotes the GDD as "not a branching job tree" | That line is outdated. The GDD now branches each archetype once at **Stage 1 (Lv 25)**, chosen automatically by which kit ability the player used most (2 to 3 named forms plus a default). The **Mastery Upgrade** (Player Lv 40 and the summon at its Lv 25 ceiling) continues that branch with one new ability and a visual accent. **Stage 2 (Lv 65)** is post-launch only. Players don't spend points and there is no skill-point currency (a Mastery currency, working name Glimmer/Arcana, is still W.I.P.). | S4 stays blocked. If it gets built later, the likeliest fit is a read-only **evolution path viewer** (Base → Stage 1 branches → Mastery) using the same generic node graph, not a point-spend class tree. Still don't hard-code names. |
| R18 | Affinity states | `Weak / Resist / Null / Normal / Unknown` | GDD's MVP affinity tiers are **Weak / Neutral / Resist**. Null, Repel and Absorb are post-MVP. | Use `Neutral` (not `Normal`) and support `Weak`, `Neutral`, `Resist`, `Unknown` at MVP. Keep `Null` in the type for later, but nothing should emit it yet. |

### 16.2 Questions for the project owner

1. **Q1 (R3):** Replace the existing `BattleUI` once the new HUD reaches parity (recommended), or keep both long term?
2. **Q2 (R7):** Confirm the Down system stays flag-off and server-less for now.
3. **Q3 (R10):** Should the next server task add a minimal reward payload (EXP/currency/items) to `BattleState`, or should S6 stay mock-only until the progression system exists?
4. **Q4 (R8):** Should the first real weakness data be the Strike/Wind `damageType` axis from the GDD's MVP line, or stay hidden until the type chart is decided?
5. **Q5:** Display font and `Theme` colors: the handoff's palette (navy/gold/purple/cyan) is global, but the GDD gives each school its own color identity (TungWarts = forest green, gold, white). Which one skins the launch UI?

### 16.3 Kickoff prompt: path corrections

Use the prompt in section 14 with these substitutions: the files are already committed (`docs/ui/UI_HANDOFF.md`, `docs/ui/ASSET_PROMPTS.md`, `docs/ui/mockups/S1_combat_hud.png` ... `S7_skill_select.png`, `tools/cut_sheet.py`); read section 16 of the handoff too; the existing combat code is `StarterPlayerScripts/Combat/BattleUI.luau`, `BattleView.luau`, `BattleTheme.luau`, `ReplicatedStorage/Combat/*` and `ServerScriptService/Combat/BattleSession.luau` (there is no `PartyManager`, `PlayerProfile` or `RewardTable`); Milestone 0 must also answer Q1 to Q5 with a recommendation.
