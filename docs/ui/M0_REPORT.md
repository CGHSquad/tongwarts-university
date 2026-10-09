# UI Milestone 0 report

**Status:** report only, no UI code. Written against `main` at `868328b` (after PR #10). Approving this report starts Milestone 1.
**Reads:** CLAUDE.md, `docs/GDD.md`, `docs/ui/UI_HANDOFF.md` (section 16 first), the seven mockups, `docs/ui/ASSET_PROMPTS.md`, `tools/cut_sheet.py`, and the combat and client code named below.
**Owner decisions already taken (section 16.2):** Q1 replace `BattleUI` once at parity · Q2 Down system stays off · Q3 S6 runs on mock rewards · Q4 hide WEAK/affinity UI · Q5 mockup palette as the base, one per-school accent · R19 (new, below) add a tiny nameplate opt-out to `BattleView`.

## 1. What exists today

**Server → client contract** (`ReplicatedStorage/Combat/BattleTypes.luau`). One `StateUpdate` remote carries a whole `Snapshot { overworld, battle? }`. `BattleState` has `phase` (`setup | input | resolve | reward`), `round` (0 = the opening bonus turn), `turnNumber`, `currentActorId`, `turnQueue` (fixed for the fight), `opening` / `startedBy`, `participants`, `winner`, `lastAction { sequence, actorId, abilityId, results[] }` with per-target `hit, critical, damage, healed, knockedOut, inflicted, applied, cleansed`, `log`, `turnDeadline`, `overworldReturnAt`. Each `ParticipantState`: `id, side, slot, name, summonId, ownerUserId?, ownerName?, hp/maxHp, mana/maxMana, status (Active | KnockedOut | Left), statuses[], abilities[] (ids), initiative?`. Client → server: `SubmitAction(abilityId, targetId)`, `RequestSync()`; server → client: `Notice(message)`. Pacing in `CombatConfig`: initiative reveal 3 s, enemy think 1.25 s, resolve pause 1.5 s, turn timeout 30 s, result screen 8 s.

**`StarterPlayerScripts/BattleClient.client.luau`** is the client entry: it wires the remotes to `BattleView` (3D) and `BattleUI` (2D), ticks countdowns on Heartbeat, and shows the overworld banner from the player's `Zone` attribute (set by `ZoneClient`).

**`StarterPlayerScripts/Combat/BattleUI.luau`** (~1130 lines) is the current HUD: a `ScreenGui` named `BattleUI` with `IgnoreGuiInset`, a `UIScale` per panel fitted to a 1280×720 design. Overworld panel; header (turn title and detail, initiative chips); party and enemy side panels with HP/Mana bars and RichText statuses; the action panel at bottom-center (`Moves` row Attack/Guard, `Abilities` row, `Targets` row, `AttackButton`); a log bottom-left; a result panel; a notice label. It remembers only `selectedAbilityId`, `selectedTargetId` and `submittedTurn`. All text is baked in. It mirrors the server's *targeting legality* (`canTarget`, `mana >= manaCost`) to decide what is selectable; it never computes an outcome.

**`StarterPlayerScripts/Combat/BattleView.luau`** (the 3D stage; untouched except for R19): a fixed camera, each spot has a `BillboardGui` nameplate (name + HP), damage / MISS / CRIT / status popups, and `Highlight` outlines for the actor and the target. `BattleView.setTarget(targetId, friendly)` is the hook the HUD calls. Summons with `art` are real rigs from `ReplicatedStorage.SummonModels`.

**`BattleTheme.luau`**: colors plus the BuilderSans fonts, 45 lines. **`Abilities.luau`**: kinds `Attack | Heal | Status | Guard`, targets `Enemy | Ally | Self | AllAllies`, `universal` Attack (Party) and Guard (Everyone), `damageType` `Strike | Wind`. **`Summons.luau`**: the four archetypes plus wild enemies, with stats and `art`. **`BattleSession.luau`**: every rule, pure Luau.

**Tests.** `tests/Sim.luau` fakes Roblox on a virtual clock and runs only `BattleClient` (and what it requires) on each client. Bots click buttons by instance name; `sim:gui()` is rooted at the `BattleUI` ScreenGui; about 30 lines of `tests/run.luau` pin the old UI's names (`Battle.Actions.Moves.Attack`, `Abilities.<id>`, `Targets.<id>`, `AttackButton`, `Header`, `TurnOrder`, `Result`, `Overworld.Status`).

## 2. Section 16 reconciliation: confirmed, corrected, added

All 18 rows of 16.1 hold against the code. Refinements and additions:

| # | Finding | Handling |
|---|---|---|
| R1 ✔ | Correct. Refinement: `Assets.luau` and `MockData.luau` are pure data, so they live in `ReplicatedStorage/UI` with Theme / Strings / Flags (the same split as `ReplicatedStorage/Combat` data vs `StarterPlayerScripts/Combat` code, and the Lune tests can `require` them). The repo doesn't use `init.client.luau`; `BattleClient.client.luau` stays the entry. | §3 |
| R3 ✔ | Q1 answered: replace at parity. Cost: ~30 test references and `Sim:gui`'s root name move with it. | `Flags.NewHud` exists during M2 only; the parity PR deletes `BattleUI.luau` and the flag. |
| R4 ✔ | Correct. The "ActionResolved" window is `phase == "resolve"` plus `lastAction`, 1.5 s before the next turn opens; HP tweens and stamps must fit in it. | Derive every UI event from changes in `lastAction.sequence`. |
| R6 ✔ | Correct. Attack targets an Enemy (needs a pick); Guard's target is `Self`, sent as the actor's own id. | The ring submits `("Attack", enemyId)` / `("Guard", actorId)`. |
| R12 ✔ | Correct, plus: a **solo player owns both party members**. "Local actor" is per turn, but two party cards are "you", and the hero Mana plate shows the **current actor's** summon. | Mock data covers 1 player/2 members and 2 players/2 members. |
| R13 ✔ | Correct. Setup lasts 3 s with `initiative.roll / bonus / total`; `turnDeadline` is 30 s out; `round == 0` is the bonus turn; `opening` and `startedBy` feed the headline. | Added to S1 acceptance. |
| R14 ✔ | Probed Lune 0.10.5 (the test runtime). **Works:** `ScreenGui.ScreenInsets`, `SafeAreaCompatibility`, ViewportFrame, WorldModel, UIScale, UIAspectRatioConstraint, 9-slice ImageLabels, UIGradient / UIStroke / CanvasGroup, ScrollingFrame, BlurEffect, ParticleEmitter, `Font.fromEnum`, gamepad KeyCodes. **Missing:** `AbsoluteSize` / `AbsolutePosition`, `TextBounds`, `GuiState`, `UserInputService.TouchEnabled / KeyboardEnabled`, `GuiService:GetGuiInset` and `SelectedObject`, `ContentProvider:PreloadAsync`, `TextService:GetTextSize`, `Players:GetUserThumbnailAsync`. | Fakes for each in `Sim.luau`; layout verified by arithmetic (§4). |
| R17 ✔ | Correct: Stage 1 branch at Lv 25, Mastery at player Lv 40, Stage 2 post-launch. S4 stays blocked. | — |
| **R19 new** | `BattleView` already draws enemy name/HP plates, damage popups and target outlines; S1's enemy overlay would duplicate the plates. | **Decided:** a tiny opt-out in `BattleView` that skips its own enemy nameplates, defaulting to plates ON so `BattleUI` and today's tests are unchanged. Only the new HUD, with its flag on, turns the plates off and draws its own. Nothing else in `BattleView` changes. |
| **R20 new** | Other client scripts own ScreenGuis at DisplayOrder 40 (PortalToast), 50 (AbyssFlash), 55 / 60 (ZoneClient's whiteout and fade), 100 (LoadingScreen). They must cover the HUD. | All UI ScreenGuis use DisplayOrder 10–30. |
| **R21 new** | In combat the character is frozen, but Roblox's thumbstick and jump button (and the Sprint touch button, §8) stay on screen. The handoff says "verify". | M1: try `PlayerModule:GetControls():Disable()` during battle (client-only, no rules change). The bottom corners stay clear per the rules either way. |
| **R22 new** | `BattleUI` mirrors targeting legality and affordability on the client (what is *selectable*); the handoff wants `canAfford` from the server. The server re-checks everything, so this is a filter, not an outcome. | Keep it, sourced only from `Abilities` data and snapshot numbers; no new remote. |
| **R23 new** | `Strings` needs format *functions*, not just constants: Guard's description is built from `CombatConfig` numbers, headlines interpolate names. | `Strings.luau` exports constants and `Strings.format.*`. |
| **R24 new** | S6 CONTINUE: the server returns everyone after 8 s (`overworldReturnAt`); there is no remote to leave early and none is added. | CONTINUE hides the results panel; the auto-return stands. Logged as a later server question. |
| **R25 new** | The "overworld HUD" isn't designed (§12), but the current overworld panel (arrival banner, "a fight is on") is tested behavior. | Keep it as a stub component, `OverworldNotice`, so nothing regresses at parity. |

## 3. Folder layout and module names

```
src/ReplicatedStorage/UI/              data only, no Roblox API calls; the Lune tests require these too
  UITypes.luau       view-models: HudParticipant, HudBattle, AbilityRow, CommandView,
                     RewardView (mock), AffinityEntry (Weak | Neutral | Resist | Null | Unknown)
  Theme.luau         Colors (the mockup palette), SchoolAccent, Fonts, Sizes, Motion (durations, reduced motion)
  Strings.luau       every visible string plus format functions (Mana, ManaShort, Currency, headlines, Guard)
  Flags.luau         NewHud, DownSystem = false, ShowAffinities = false, ShowItem = false,
                     ShowPass = false, ShowRoles = false, UIHarness = false
  Assets.luau        asset keys → { id?, slice?, sliceScale? }, plus per-screen preload lists (§5)
  MockData.luau      snapshots and view-models for every harness state

src/StarterPlayerScripts/UI/
  Core/        Layout.luau (safe rects, scale, device mode: pure functions)
               Input.luau (touch / mouse / keyboard / gamepad mode, key hints)
               ScreenManager.luau · Audio.luau (named hooks, no assets) · Fallbacks.luau
  Components/  SlicedPanel, TapButton, StatBar, Capsule, Tag, IconMedallion, ListRow,
               HeadIcon, TallyPlate, Toast, ViewportPortrait (stub until M4)
  Screens/
    CombatHUD/ init.luau, Bindings.luau (Snapshot → HudBattle), TurnOrderBar, CommandRing,
               EnemyOverlay, PartyCards, ManaPlate, Stamps (flag-gated), InitiativeReveal, OverworldNotice
    SkillList/ init.luau (S7; also a read-only mode)
    Results/   init.luau (S6)
  Preview/     Harness.luau (opened from the Studio command bar or the MCP; gated by Flags.UIHarness)
               SafeZoneDebug.luau
```

`BattleClient.client.luau` keeps its job and swaps `BattleUI` for `UI/Screens/CombatHUD` behind `Flags.NewHud`. `BattleView` is reused as-is, plus the R19 opt-out.

## 4. Safe zones and testing

**Layout.** One root `ScreenGui` per screen with `ScreenInsets = CoreUISafeInsets` and `SafeAreaCompatibility = FullscreenExtension`, so Roblox's top bar and device notches are already excluded. `Layout.luau` then computes three keep-out rects from the viewport size: top-left (chat and menu), bottom-left and bottom-right (the bottom 25% of the height, about 22% of the width each). Everything is placed with Scale + Offset inside a `SafeArea` frame, and the party cards and command ring use `Layout` constants that end above the 25% line. A root `UIScale` keeps the 1280×720 design readable at 844×390 (minimum 0.5) and at 1080p, as today. `TapButton` enforces the 48 px minimum after scaling.

**Studio.** Device Emulator at a small phone (about 844×390), a tablet, and 1920×1080, with touch controls visible. Through the Studio MCP I read `Camera.ViewportSize`, `GuiService:GetGuiInset()` and each element's `AbsolutePosition` / `AbsoluteSize` during Play, and take screenshots with `SafeZoneDebug` on. The owner picks the emulator device; I verify the numbers and the screenshots.

**`tests/Sim.luau`.** Lune can't lay out GUIs, so: `Layout` is pure math, unit-tested at the three sizes; a test helper resolves each element's rect from `Position / Size / AnchorPoint / UIScale` up the tree and asserts that nothing intersects a keep-out rect and every button is at least 48 px; `client.env.viewportSize` (already supported) sets the phone size per test; new fakes cover `UserInputService`, `GuiService`, `ContentProvider`, `TextService` and `GetUserThumbnailAsync`. The bots keep clicking by name, so instance names stay stable (`CommandRing.Attack`, `SkillList.Rows.<abilityId>`, `Targets.<id>`, `Confirm`).

## 5. Assets

```lua
export type AssetEntry = { id: string?, slice: Rect?, sliceScale: number? }
Assets.Images = { Combat_CommandBlue = { slice = Rect.new(...) }, Combat_OneMoreLettering = {}, ... }
Assets.Screens = { CombatHUD = { "Combat_CommandBlue", ... }, SkillList = { ... }, Results = { ... } }
function Assets.image(key): string?     -- nil → the component uses its fallback look
function Assets.preload(screen)         -- PreloadAsync on filled ids only, pcall'd
```

Keys follow the sheet names in `ASSET_PROMPTS.md` (`Combat_*`, `Turn_*`, `Party_*`, `SkillList_*`, `Results_*`). Fallback looks live in each component. The two lettering pieces fall back to styled text.

**Uploading through the Studio MCP.** `upload_image` takes http URLs and returns an `rbxassetid` map, so the cut PNGs can be served from a local `python -m http.server` and the ids written straight into `Assets.luau`. Untested so far (it creates assets under the owner's account, so it waits for a go-ahead in M6). `search_asset` with `scope = "user", assetType = "Image"` reads back the ids of anything the artist uploads through Asset Manager, which is likely the simpler path.

## 6. Q1–Q5, with what each answer means

- **Q1, replace at parity:** `Flags.NewHud` during M2 only; the parity PR deletes `BattleUI.luau` and rewrites the ~30 test references. Parity means every current test passes against the new HUD.
- **Q2, Down off:** `Flags.DownSystem = false`; Stamps and the DOWN tag are built on mock data and never read `KnockedOut`.
- **Q3, S6 on mock rewards:** `RewardView` comes from `MockData`; only VICTORY / DEFEAT, the party list and CONTINUE / auto-return bind to the snapshot.
- **Q4, hide affinity UI:** the Tag / WEAK components exist, gated by `Flags.ShowAffinities = false` and empty data.
- **Q5, mockup palette plus school accent:** `Theme.Colors` is the navy / gold / purple / cyan set; `Theme.SchoolAccent` (TungWarts forest green) replaces the highlight and trim token only, so crimson stays enemy-only.

## 7. Tools

- **Blender MCP:** the server answered but its handshake with Blender failed ("connection lost"), so Blender wasn't running or its MCP add-on's server wasn't started. The four extensions (Blender Studio Plugin, Validation Tool, Calisthenics Tool, Roblox Rig for Animations) couldn't be verified; none belong to the MCP's own libraries (Poly Haven / Sketchfab / Poly Pizza and the generators are all off). With Blender open and the MCP server started, the installed add-ons can be listed read-only and reported before M3's victory poses need them.
- **Studio MCP:** `upload_image` (http URLs → asset ids), `store_image` (local file → image URI for the generators; not an upload), `search_asset`, `insert_asset`, `execute_luau`, `screen_capture`.

## 8. PR #10's client scripts against the safe-zone rules

These came with the map sync and were not written for the UI spec. None of them run in the tests (the Sim only runs `BattleClient`).

| Script | What it puts on screen | Safe zones | Notes |
|---|---|---|---|
| `ReplicatedFirst/LoadingScreen` | Full-screen cover, DisplayOrder 100, removed when the lobby has streamed in (20 s cap). | Fine: a cover, by design. | Baked title "Midnight Mushroom" (the Studio place's name, not the game's) and subtitle; fonts FredokaOne / GothamMedium, off-theme. Candidate to restyle with `Theme` / `Strings` in M6. |
| `PortalToast` | A 420×86 px toast at top-center (y = 24 px), DisplayOrder 40, 2.6 s. | Fine: top-center is allowed; it doesn't set `IgnoreGuiInset`, so it sits below Roblox's top bar. | Fixed pixel size (no scaling); baked text; off-theme fonts. Overlaps the planned `Toast` component; fold it in at M1 or leave it. |
| `ZoneClient` | Two full-screen overlays: `CloudWhiteout` (55) and `ZoneFade` (60), non-interactive. Also sets the `Zone` attribute. | Fine: covers by design. | The HUD must sit under them (R20). |
| `MainHallTVs` | `SurfaceGui`s on world parts, not screen UI. | Not applicable. | In-world flavor text only. |
| `Sprint` | On touch devices, a `ContextActionService` button at `UDim2.new(1, -170, 1, -150)`: the bottom-right corner, next to the jump button. | Inside the bottom-right keep-out, which is the zone the rule reserves for touch controls, so it is consistent with the rule's intent. | It stays visible during combat; if R21 disables the touch controls in battle, unbind this too. |
| `SummonFX` | A full-screen `AbyssFlash` (50) for about 1 s. | Fine. | — |
| `AFKClient` | Nothing on screen. | — | — |

Two cross-cutting notes: the DisplayOrder ladder (40 / 50 / 55 / 60 / 100) leaves room for the UI at 10–30, which is what §2 R20 assumes; and these scripts aren't `--!strict` and have no type annotations, which CLAUDE.md asks for. That is a code-quality cleanup, not UI scope.

## Milestone 1 scope (on approval)

Foundation modules (`Theme`, `Strings`, `Flags`, `Assets`, `UITypes`, `MockData`, `Layout`, `Input`, `ScreenManager`, `Audio`); the base components with fallbacks; the harness and `SafeZoneDebug`; the R19 opt-out in `BattleView`; the Sim fakes and layout tests. Done when a blank screen opens and closes, the components render with no art, and `lune run tools/typecheck` and `lune run tests/run` stay green.
