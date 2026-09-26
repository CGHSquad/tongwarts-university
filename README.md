# TungWarts University (working title)

A Roblox turn-based social RPG: a Wizard101 x Persona hybrid where you fight with summoned
BrainRot meme characters like Tung Tung Sahur. The design lives in [`docs/GDD.md`](docs/GDD.md).

## Setup

Code lives in `src/` and syncs into Roblox Studio with [Rojo](https://rojo.space).

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` in this folder.
   That installs the Rojo version pinned in `rokit.toml` (7.7.0), so everyone uses the same one.
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

The GDD's Phase 1 goal: prove the turn-based loop works with placeholder art. Two Tung Tung
Sahurs (colored blocks) fight two Wild Saplings.

### Playtest it with two people

1. In Studio, open the **Test** tab, set the **Clients and Servers** option to **2 players**, and
   click **Start**. Studio opens a server plus one window per player.
   (On two computers, use Team Create and **Team Test** instead so you join the same server.)
2. Both players press **READY**. After a 3-second countdown the battle starts.
3. Each player controls one Tung Tung Sahur. On your turn, pick an attack and a target and
   press **ATTACK!**. The enemies act on their own.
4. When one side is knocked out you get a Victory or Defeat screen, then everyone returns to
   the lobby and can ready up for another battle.

Playing alone? Press **Play**, then **READY**, and you control both party summons.

### Rules

- **Initiative:** at the start of each battle every summon rolls 1-20 and adds an Agility
  bonus (`floor(Agility / 2)`). Turns go from the highest total down, one summon at a time,
  allies and enemies interleaved. The order is fixed for that battle; exact ties go to the party.
- **Mana:** both attacks cost Mana. Strike (2 Mana) is a cheap, reliable hit; Gale Clap, the
  Wind skill (8 Mana), hits harder. Each summon gets +3 Mana at the start of its turn.
- **The server decides everything.** Clients send "use this ability on this target"; the
  server checks it's really your turn, the ability is yours and affordable, and the target is
  an enemy still standing. Anything else is refused with a message, and the client never
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
| `ReplicatedStorage/Combat/CombatConfig.luau` | Every tuning number: formulas, timers, party size, who fights. |
| `ReplicatedStorage/Combat/Abilities.luau`, `Summons.luau` | Abilities and summons as data. Add new ones here, not in the combat code. |
| `ReplicatedStorage/Combat/BattleTypes.luau` | The shape of the state the server sends to clients. |
| `StarterPlayerScripts/BattleClient.client.luau` | Client entry point: draws each server update, sends button presses. |
| `StarterPlayerScripts/Combat/BattleUI.luau`, `BattleView.luau`, `BattleTheme.luau` | The HUD, the placeholder blocks and battle camera, and their colors and fonts. |

### Tuning

The numbers are placeholders; the GDD's formula question (Step 11, Q6) is still open. In
simulated battles with the current values, a party that focus-fires and uses Gale Clap
whenever it can wins about 87% of the time, while random play wins about 40%. Battles last
around five rounds. Change `CombatConfig.luau`, `Abilities.luau` and `Summons.luau` freely.
