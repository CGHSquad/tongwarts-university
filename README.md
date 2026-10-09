# TungWarts University (working title)

A Roblox turn-based social RPG: a Wizard101 x Persona hybrid where you fight with summoned
BrainRot meme characters like Tung Tung Sahur. The design lives in [`docs/GDD.md`](docs/GDD.md).

## Setup

Code lives in `src/` and syncs into Roblox Studio with [Rojo](https://rojo.space).

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` in this folder.
   That installs the tool versions pinned in `rokit.toml` (Rojo 7.7.0, Lune for the scripts
   in `tools/` and `tests/`, and luau-lsp for type checking), so everyone uses the same ones.
   The first time, answer yes when it asks you to trust each tool.
2. Install the matching Studio plugin: `rojo plugin install`.
3. Then either:
   - **Day to day:** run `rojo serve`, open the team's place in Studio (Team Create, "Midnight
     Mushroom!"), and click **Connect** in the Rojo plugin. Edits to `src/` show up in Studio live.
   - **One-off:** run `rojo build -o TungWarts.rbxlx` for a place with all the code but no map
     (the headless tests use one of these).

**The map lives in the Team Create place, not in this repo.** The lobby, the overworld and the four
campuses are about 85k parts, which git can't usefully diff or merge, so build and edit them in
Studio and use its version history. Rojo doesn't manage Workspace at all. Everything else (scripts,
content data, remotes, zone lighting) lives in `src/` and syncs through Rojo. Don't edit those in
Studio: Rojo overwrites them. If someone does, capture it with `rojo syncback` (download a copy of
the place, then `rojo syncback default.project.json --input <place>.rbxl`) and review the diff.

`default.project.json` maps the repo onto the game:

| Folder | Becomes | What goes here |
| --- | --- | --- |
| `src/ReplicatedFirst` | ReplicatedFirst | The loading screen. |
| `src/ServerScriptService` | ServerScriptService | Server-only code. Game state and every rule live here. |
| `src/ReplicatedStorage` | ReplicatedStorage | Data and types both sides read (abilities, summons, tuning). |
| `src/StarterPlayerScripts` | StarterPlayer > StarterPlayerScripts | Client code: UI and visuals only. |

The battle RemoteEvents (`ReplicatedStorage.Remotes.Battle`) are declared in `default.project.json`
as well. The enemies (on the overworld grass and on each campus's gym stage) are created by the
server from `ServerScriptService/Overworld/EnemySpawns.luau`. File suffixes pick the script type:
`.server.luau` is a Script, `.client.luau` a LocalScript, plain `.luau` a ModuleScript.

Besides combat, `src/` holds the world's systems that go with the map: zone travel between the lobby,
the overworld and the campuses (`ZoneTravel`, `PortalTeleporter`, `ReturnPortal`, `ZoneClient`),
the campuses (`CampusServer`, `CampusDoors`, `CampusFallCatch`, `TralalaServer`), the lobby
(`AbyssRespawn`, `AFKClient`) and effects (`SummonFX`, `SeaLifeClient`, `SnowfallClient`,
`CloudSeaClient`, `MainHallTVs`, `Sprint`). Players spawn in the cave lobby (`LobbySpawn`, the only
enabled SpawnLocation) and travel through portals.

## Combat prototype (Phase 1)

The GDD's Phase 1 goal: prove the turn-based loop works with placeholder art. You walk around a
baseplate where packs of Wild Saplings (red blocks with eyes) patrol or stand around, and walking
into one starts a fight: your party of two Tung Tung summons against two Wild Saplings. The four
Tung Tung summons have their real 3D models and animations on the battle stage; the Wild Saplings
are still colored blocks.

### Playtest it with two people

1. In Studio, open the **Test** tab, set the **Clients and Servers** option to **2 players**, and
   click **Start**. Studio opens a server plus one window per player.
   (On two computers, use Team Create and **Team Test** instead so you join the same server.)
2. Walk (WASD) into one of the enemy blocks. Which way you're facing when you touch it decides
   how the fight opens (see **Starting a fight** below), and it pulls both players in, wherever
   the other one is.
3. Each player is on the field as their own character, with one summon. On your turn, pick a
   move (your character's **Attack** or **Guard**, or one of your summon's abilities), pick a
   target if it needs one, and press the big button. The enemies act on their own.
4. When one side is knocked out you get a Victory or Defeat screen, then you're back exploring.
   A beaten enemy disappears for 20 seconds; if your party lost, you respawn at the spawn point.

Playing alone? Press **Play** and walk into an enemy. You control both party summons.

To try other summons, change `PartySummons` in `ReplicatedStorage/Combat/CombatConfig.luau`,
e.g. `{ "TungTungElder", "TungTungGroveKeeper" }`. The first summon goes to whoever touched the
enemy.

### Summons

The four Tung Tung Sahur variants from the GDD. Each has the basic Strike plus its own kit. On
top of that, your character always has Attack and Guard (see Rules):

| Summon | Role | Leans on | Abilities |
| --- | --- | --- | --- |
| Tung Tung Sahur | Balanced | even stats | **Gale Clap** (Wind): a harder hit that can daze |
| Tung Tung Elder | Tank | Endurance; slow, unlucky | **Knock on Wood**: enemies must target it. **Windbreak**: takes less damage |
| Tung Tung Sapling | Damage | Strength, Agility, Luck; fragile | **Splinter Slam**: a huge, pricey hit with extra critical chance |
| Tung Tung Grove-Keeper | Support | Magic, Luck; weak Strike | **Tailwind**: the party gets more accurate and harder to hit. **Sap Mend**: heals an ally and clears ailments |

### Rules

- **Starting a fight** (the GDD's overworld initiative): touching an enemy pulls everyone in the
  server into the fight (up to 2 players), and where the enemy was compared with the way the
  player who touched it was facing decides the opening:
  - **Face-on** (within 60° of straight ahead): you struck first, so everyone in your party
    takes a **bonus turn** before round 1.
  - **From behind** (within 60° of straight behind): it caught you, so every enemy takes the
    bonus turn.
  - **From the side:** an even start.

  During the fight your characters are frozen in place and the enemy stops. Afterwards you get
  4 seconds to walk away before another fight can start. Only one fight runs at a time; a third
  player sits it out and keeps exploring.
- **Initiative:** at the start of each battle every summon rolls 1-20 and adds an Agility
  bonus (`floor(Agility / 2)`). Turns go from the highest total down, one summon at a time,
  allies and enemies interleaved. The order is fixed for that battle; exact ties go to the party.
  A bonus turn goes in this same order, then round 1 starts from the top.
- **Stats** (the GDD's final model):
  - **Strength** powers Strike attacks.
  - **Magic** powers Wind attacks and heals, and sets max Mana.
  - **Endurance** cuts all incoming damage (2% per point, up to 60%) and makes up most of max
    Health.
  - **Agility** gives the initiative bonus plus accuracy and evasion.
  - **Luck** drives critical hits and ailments.
- **Attacks roll to hit:** 90% base, ±2% per point of Agility difference between attacker and
  target. **Critical hits** (×1.5 damage) come from the attacker's Luck.
- **Ailments:** Gale Clap can **daze** its target. The chance goes up or down with the
  attacker's Luck against the target's. A dazed summon may lose its turn. Sap Mend clears it.
- **Your character on the field** (GDD Step 6, the Persona-style presentation): your own character
  stands in your spot for the whole fight and makes two moves of its own:
  - **Attack:** free, and hits for 4 + your summon's Strength. That makes it weaker than the
    summon's 2-Mana Strike, so it's the move for when you'd rather not spend Mana.
  - **Guard:** see below.

  Your summon only appears for one of its own abilities (Strike, Gale Clap, Windbreak, Sap Mend
  and so on): its model, idling, swinging its attack clip for an attack, or a colored block for a
  summon with no model yet (`art` in `Summons.luau`; the models are `.rbxm` files in
  `src/ReplicatedStorage/SummonModels/`). It comes out once more to play its death clip when it's
  knocked out. Like a JoJo Stand or a Persona, it materializes behind your character, up over its
  shoulder, performs the move and dismisses again, while your character stays on the field the
  whole time. When you're hit, your character flinches. The summon still owns all the stats, Health and Mana; this is
  how a turn looks, not who fights. Enemies are just their creature. The character on the field is
  a copy of your avatar, or a blocky stand-in if a teammate's avatar hasn't loaded on your screen
  or they're mid-respawn.
- **Guard:** instead of an ability, any summon can Guard. It's free and needs no target, and it
  lasts until that summon's next turn. While guarding it:
  - takes 30% less damage. That multiplies with Endurance's cut rather than adding to it, so a
    maxed-Endurance tank guarding blocks 72%, and nothing ever blocks more than 75%.
  - can't be hit by a critical hit.
  - is half as likely to get an ailment.

  It's purely defensive: it never gives Mana back, and it costs your whole turn. It's separate
  from the Elder's Windbreak, and the two stack. (Enemies don't guard yet.)
- **Statuses** (taunt, Windbreak, Tailwind, Dazed, and Guard's Bracing) last a few of that
  summon's own turns. Buffs never change the turn order mid-battle.
- **Mana:** every ability costs Mana (Attack and Guard are free), and each summon gets +3 at the
  start of its turn.
- **The server decides everything.** Clients send "use this ability on this target"; the
  server checks it's really your turn, the ability is yours (or Attack or Guard) and affordable,
  and the target is legal for that ability. Anything else is refused with a message, and the
  client never computes an outcome.
- **AFK and leaving:** a player who doesn't act within 30 seconds skips that turn. A player who
  leaves mid-battle drops out, and if it was their turn the battle moves on right away.

### Where the code is

| File | What it does |
| --- | --- |
| `ServerScriptService/Combat/BattleSession.luau` | All combat rules for one fight: initiative, turn order, validation, damage, win check. Pure Luau with no Roblox APIs. |
| `ServerScriptService/Combat/BattleDirector.luau` | Starts a fight when someone walks into an enemy, then runs its real-time loop: turn timers, enemy turns, pacing, players leaving. |
| `ServerScriptService/Combat/EnemyAI.luau` | Enemy move choice: a weighted table per enemy type. |
| `ServerScriptService/Overworld/Overworld.luau` | The overworld: moves the enemies, notices a player touching one, freezes the party during the fight, and cleans up afterwards. |
| `ServerScriptService/Overworld/Encounter.luau` | Face-on, from behind or from the side: which side gets the bonus turn. |
| `ServerScriptService/Overworld/EnemySpawns.luau` | Where the enemies are, how they move (patrol a path or stand and look around), and who you fight. |
| `ServerScriptService/BattleServer.server.luau` | Entry point: connects players, RemoteEvents and the overworld to the director, and type-checks client input. |
| `ReplicatedStorage/Combat/CombatConfig.luau` | Every formula's numbers (Health, Endurance, hit chance, crits, ailments, Guard, how fights start), timers, party size, who fights. |
| `ReplicatedStorage/Combat/Abilities.luau`, `Summons.luau`, `StatusEffects.luau` | Abilities, summons and statuses as data. Add new ones here, not in the combat code. |
| `ReplicatedStorage/Combat/BattleTypes.luau` | The shape of the state the server sends to clients. |
| `StarterPlayerScripts/BattleClient.client.luau` | Client entry point: draws each server update, sends button presses. |
| `StarterPlayerScripts/Combat/BattleUI.luau`, `BattleView.luau`, `BattleTheme.luau` | The overworld panel and battle HUD; the stage (each player's character, with its summon appearing behind it for the summon's own abilities, and the enemy blocks) and battle camera, in its own arena past the edge of the map; and their colors and fonts. |
| `tools/simulate-battles.luau` | Plays thousands of battles with the real rules to compare party comps (see below). |
| `tools/typecheck.luau` | Type-checks `src/` the way Studio sees it: `lune run tools/typecheck`. |
| `tests/run.luau`, `tests/Sim.luau` | Headless tests: bots play the real game on a fake Roblox, no Studio needed (see below). |

### Tuning and the battle simulator

The numbers are placeholders; the GDD's formula question (Step 11, Q6) is still open. Change
`CombatConfig.luau`, `Abilities.luau`, `Summons.luau` and `StatusEffects.luau` freely, then
check what it did with the simulator:

```
lune run tools/simulate-battles          # 2000 battles per party comp and play style
lune run tools/simulate-battles 10000 7  # more battles, different random seed
```

It runs the real `BattleSession` and `EnemyAI` code (no Studio needed) against the enemies in
`CombatConfig`. Each party comp plays three ways:

- **careless:** random buttons, the character's Attack and Guard included.
- **sensible:** heal the hurt, keep buffs up, and hit the weakest enemy with the hardest-hitting
  attack you can afford (the character's free Attack counts). It never guards (see below).
- **turtle:** sensible, but it guards whenever the enemies are likely to come after it, stacking
  Guard's damage cut on Endurance (and Windbreak) instead of attacking. If it beat sensible play,
  Guard would be too strong (GDD Step 6).

For each party comp it reports:

- **win rates** for the three play styles
- **what each member does:** damage dealt and taken, healing, and the share of enemy attacks
  aimed at it
- **Guard:** how often each turtle member guards, and how often those guards got attacked
- **Attack:** how often each member uses the character's free Attack
- **the dice:** hits, crits, dazes and turns lost
- **the opening turn:** sensible play again, with the party or the enemies taking the bonus turn,
  to show what striking first is worth

To compare other comps, edit `PARTIES` at the top of the script. With the current numbers:

| Party | Sensible | Turtle | Rounds (sensible) |
| --- | --- | --- | --- |
| Sahur + Sahur | 79% | 2% | 7.3 |
| Elder + Sapling | 92% | 43% | 8.3 |
| Sapling + Grove-Keeper | 72% | 11% | 8.9 |
| Elder + Grove-Keeper | 81% | 18% | 17.8 |
| Sahur + Grove-Keeper | 79% | 57% | 9.9 |
| Sapling + Sapling | 51% | 1% | 5.7 |

Careless play wins 0–7%.

- **Attack is never the best pick.** Sensible play never uses it (0% of turns): a summon's Strike
  costs only 2 Mana, Mana comes back 3 a turn, and Strike always hits harder. Only button-mashing
  uses it (20–27% of careless turns).

- **Turtling loses badly.** Guarding whenever you're likely to be attacked loses in every comp,
  by 22 to 77 points. The turtle's guards nearly all get attacked (85–98%), so the damage cut is
  real, but the turns it doesn't attack cost more than the damage it saves.
- **Guard doesn't pay anywhere yet.** With no Mana coming back, every rule tried for when sensible
  play should guard lost win rate against never guarding: a hurt healer that's being attacked
  and can't afford its heal (up to 2 points), a hurt member that's being attacked while a teammate
  can heal it next (up to 7), a hurt taunting tank (up to 12), and anyone being attacked under 35%
  Health (up to 37). Against these enemies the turn is worth more than the damage it saves, so
  sensible play never guards. A tougher enemy, or one that telegraphs a big hit, is where Guard
  should start to earn its place.

Striking first is worth a lot. The same sensible play, depending on how the fight opened:

| Party | Party's bonus turn | Even start | Enemies' bonus turn |
| --- | --- | --- | --- |
| Sahur + Sahur | 96% | 79% | 38% |
| Elder + Sapling | 99% | 92% | 56% |
| Sapling + Grove-Keeper | 90% | 72% | 44% |
| Elder + Grove-Keeper | 93% | 81% | 62% |
| Sahur + Grove-Keeper | 94% | 79% | 60% |
| Sapling + Sapling | 89% | 51% | 14% |

### Headless tests

`tests/` plays the real game without Studio. It builds the place with Rojo, then runs it in Lune
on a fake Roblox (`tests/Sim.luau`): a server plus a client per test player, all running the real
scripts from `src/`. Bots walk into enemies and click the real battle UI, and every update each
client receives is checked: whose turn it is, what the HUD offers, who's on the stage, and so on.

```
lune run tests/run                # everything, about a minute
lune run tests/run quick          # fewer seeded battles at the end
lune run tests/run quick Guard    # only the tests whose names contain "Guard"
```

Run them from the repo root before pushing gameplay or UI changes. They cover the combat rules and
stat model, Guard, two players through the UI, disconnects, cheating clients, overworld
encounters, the battle stage, every summon variant, and a few hundred seeded battles checked turn
by turn.

They can't tell you how anything looks: there's no rendering or physics, tweens jump straight to
where they end, and players' avatars are simple stand-ins. Check those in Studio. When you change
how the game behaves on purpose, change the tests that pin that behavior down with it.
