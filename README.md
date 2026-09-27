# TungWarts University (working title)

A Roblox turn-based social RPG: a Wizard101 x Persona hybrid where you fight with summoned
BrainRot meme characters like Tung Tung Sahur. The design lives in [`docs/GDD.md`](docs/GDD.md).

## Setup

Code lives in `src/` and syncs into Roblox Studio with [Rojo](https://rojo.space).

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` in this folder.
   That installs the tool versions pinned in `rokit.toml` (Rojo 7.7.0, plus Lune for the scripts
   in `tools/`), so everyone uses the same ones. The first time, answer yes when it asks you to
   trust each tool.
2. Install the matching Studio plugin: `rojo plugin install`.
3. Then either:
   - **Day to day:** run `rojo serve`, open a place in Studio (the Baseplate template is fine),
     and click **Connect** in the Rojo plugin. Edits to `src/` show up in Studio live.
   - **One-off:** run `rojo build -o TungWarts.rbxlx` and open that file in Studio.

`default.project.json` maps the repo onto the game:

| Folder | Becomes | What goes here |
| --- | --- | --- |
| `src/ServerScriptService` | ServerScriptService | Server-only code. Game state and every rule live here. |
| `src/ReplicatedStorage` | ReplicatedStorage | Data and types both sides read (abilities, summons, tuning). |
| `src/StarterPlayerScripts` | StarterPlayer > StarterPlayerScripts | Client code: UI and visuals only. |

The battle RemoteEvents (`ReplicatedStorage.Remotes.Battle`) and a baseplate with a spawn point
are declared in `default.project.json` as well. File suffixes pick the script type:
`.server.luau` is a Script, `.client.luau` a LocalScript, plain `.luau` a ModuleScript.

## Combat prototype (Phase 1)

The GDD's Phase 1 goal: prove the turn-based loop works with placeholder art. A party of two
Tung Tung summons (colored blocks) fights two Wild Saplings.

### Playtest it with two people

1. In Studio, open the **Test** tab, set the **Clients and Servers** option to **2 players**, and
   click **Start**. Studio opens a server plus one window per player.
   (On two computers, use Team Create and **Team Test** instead so you join the same server.)
2. Both players press **READY**. After a 3-second countdown the battle starts.
3. Each player controls one summon. On your turn, pick an ability (or **Guard**), pick a target
   if it needs one, and press the big button. The enemies act on their own.
4. When one side is knocked out you get a Victory or Defeat screen, then everyone returns to
   the lobby and can ready up for another battle.

Playing alone? Press **Play**, then **READY**, and you control both party summons.

To try other summons, change `PartySummons` in `ReplicatedStorage/Combat/CombatConfig.luau`,
e.g. `{ "TungTungElder", "TungTungGroveKeeper" }`. The first summon goes to the first player
to join.

### Summons

The four Tung Tung Sahur variants from the GDD. Each has the basic Strike plus its own kit, and
can Guard (see Rules):

| Summon | Role | Leans on | Abilities |
| --- | --- | --- | --- |
| Tung Tung Sahur | Balanced | even stats | **Gale Clap** (Wind): a harder hit that can daze |
| Tung Tung Elder | Tank | Endurance; slow, unlucky | **Knock on Wood**: enemies must target it. **Windbreak**: takes less damage |
| Tung Tung Sapling | Damage | Strength, Agility, Luck; fragile | **Splinter Slam**: a huge, pricey hit with extra critical chance |
| Tung Tung Grove-Keeper | Support | Magic, Luck; weak Strike | **Tailwind**: the party gets more accurate and harder to hit. **Sap Mend**: heals an ally and clears ailments |

### Rules

- **Initiative:** at the start of each battle every summon rolls 1-20 and adds an Agility
  bonus (`floor(Agility / 2)`). Turns go from the highest total down, one summon at a time,
  allies and enemies interleaved. The order is fixed for that battle; exact ties go to the party.
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
- **Guard:** instead of an ability, any summon can Guard. It's free and needs no target, and it
  lasts until that summon's next turn. While guarding it:
  - takes 30% less damage. That multiplies with Endurance's cut rather than adding to it, so a
    maxed-Endurance tank guarding blocks 72%, and nothing ever blocks more than 75%.
  - can't be hit by a critical hit.
  - is half as likely to get an ailment.
  - gets 6 Mana back if something attacks it before its next turn (hit or miss, once). If
    nothing does, it gets nothing.

  It's a bet that you'll be the one attacked, and it costs your whole turn. It's separate from the
  Elder's Windbreak, and the two stack. (Enemies don't guard yet.)
- **Statuses** (taunt, Windbreak, Tailwind, Dazed, and Guard's Bracing) last a few of that
  summon's own turns. Buffs never change the turn order mid-battle.
- **Mana:** every ability costs Mana (Guard is free), and each summon gets +3 at the start of its
  turn.
- **The server decides everything.** Clients send "use this ability on this target"; the
  server checks it's really your turn, the ability is yours (or Guard) and affordable, and the target is
  legal for that ability. Anything else is refused with a message, and the client never
  computes an outcome.
- **AFK and leaving:** a player who doesn't act within 30 seconds skips that turn. A player who
  leaves mid-battle drops out, and if it was their turn the battle moves on right away.

### Where the code is

| File | What it does |
| --- | --- |
| `ServerScriptService/Combat/BattleSession.luau` | All combat rules for one fight: initiative, turn order, validation, damage, win check. Pure Luau with no Roblox APIs. |
| `ServerScriptService/Combat/BattleDirector.luau` | The ready-up lobby and the real-time loop: turn timers, enemy turns, pacing, players leaving. |
| `ServerScriptService/Combat/EnemyAI.luau` | Enemy move choice: a weighted table per enemy type. |
| `ServerScriptService/BattleServer.server.luau` | Network edge: connects players and RemoteEvents to the director, and type-checks client input. |
| `ReplicatedStorage/Combat/CombatConfig.luau` | Every formula's numbers (Health, Endurance, hit chance, crits, ailments, Guard), timers, party size, who fights. |
| `ReplicatedStorage/Combat/Abilities.luau`, `Summons.luau`, `StatusEffects.luau` | Abilities, summons and statuses as data. Add new ones here, not in the combat code. |
| `ReplicatedStorage/Combat/BattleTypes.luau` | The shape of the state the server sends to clients. |
| `StarterPlayerScripts/BattleClient.client.luau` | Client entry point: draws each server update, sends button presses. |
| `StarterPlayerScripts/Combat/BattleUI.luau`, `BattleView.luau`, `BattleTheme.luau` | The HUD, the placeholder blocks and battle camera, and their colors and fonts. |
| `tools/simulate-battles.luau` | Plays thousands of battles with the real rules to compare party comps (see below). |

### Tuning and the battle simulator

The numbers are placeholders; the GDD's formula question (Step 11, Q6) is still open. Change
`CombatConfig.luau`, `Abilities.luau`, `Summons.luau` and `StatusEffects.luau` freely, then
check what it did with the simulator:

```
lune run tools/simulate-battles          # 2000 battles per party comp and play style
lune run tools/simulate-battles 10000 7  # more battles, different random seed
```

It runs the real `BattleSession` and `EnemyAI` code (no Studio needed) against the enemies in
`CombatConfig`. Each party comp plays four ways:

- **careless:** random buttons, Guard included.
- **sensible:** heal the hurt, keep buffs up, focus the weakest enemy, and Guard only in the one
  spot where it pays: a healer that's hurt, being attacked, and can't afford its heal.
- **no Guard:** sensible, but never guards.
- **turtle:** sensible, but it guards whenever its Mana isn't full, then spends it all on its
  biggest attack. This is the "guard to max Mana, then alpha-strike" pattern Guard mustn't
  reward (GDD Step 6).

For each party comp it reports:

- **win rates** for the four play styles
- **what each member does:** damage dealt and taken, healing, and the share of enemy attacks
  aimed at it
- **Guard:** how often each member guards, how often those guards got attacked (paying Mana), and
  the same for the turtle
- **the dice:** hits, crits, dazes and turns lost

To compare other comps, edit `PARTIES` at the top of the script. With the current numbers:

| Party | Sensible | No Guard | Turtle | Rounds (sensible) |
| --- | --- | --- | --- | --- |
| Sahur + Sahur | 78% | 77% | 8% | 7.4 |
| Elder + Sapling | 91% | 91% | 1% | 8.3 |
| Sapling + Grove-Keeper | 77% | 72% | 47% | 12.7 |
| Elder + Grove-Keeper | 90% | 81% | 0% | 23.1 |
| Sahur + Grove-Keeper | 80% | 81% | 25% | 10.7 |
| Sapling + Sapling | 50% | 48% | 7% | 5.7 |

Careless play wins 0–10%.

- **Turtling loses badly.** Guarding until Mana is full, then alpha-striking, loses in every comp.
- **Guard helps in one spot.** A healer that's hurt, being attacked, and can't afford its heal
  should guard. It guards on 5–9% of its turns, nearly every guard gets attacked, and the Mana it
  wins back pays for the heal. That adds 5–9 points of win rate to two of the three healer comps.
- **Everyone else should attack.** In the simulator, guarding to bank Mana for a big attack, or
  to put off a knockout, costs more than it saves.

A handful of healer battles (up to about 1%) are still going after 100 rounds and count as losses: a
lone Grove-Keeper alternating Guard and Sap Mend can outlast the last enemy without ever killing
it.
