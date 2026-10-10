# Camera polish: known rough edges

A running list of the battle camera's known rough edges, parked by the owner after C1 ("we're
parking camera polish for now and coming back near the end of the overhaul"). Every milestone adds
what it surfaces here and doesn't fix it unless it blocks that milestone. Numbers come from the C1
reviews and Studio traces (PR #19). The camera's numbers all live in
`StarterPlayerScripts/Combat/Presentation/CameraSpec.luau`.

| # | Rough edge | Where it shows up | Found | Notes |
| --- | --- | --- | --- | --- |
| 1 | **Feels finicky overall** | Every turn | Owner playtest after C1 | Distance is good and enemy results are mostly readable; the moves between shots feel fussy. Likely contributors are the next five rows. |
| 2 | Many small Dutch-tilt changes | Idle −4°, skill list −6°, single target −2°, ally/party/reaction 0°, enemy wind-up +3° | C1 alignment | Each shot change also springs the roll; a turn can pass through four tilts. Consider fewer distinct tilts, or tilt only the idle and menu shots. |
| 3 | The whip-pan roll kick | Every sweep under 0.3 s that travels over 2 studs | C1 (round 1 P4) | 2° peak by design, settling in 0.3 s; reads as a wobble on short moves. |
| 4 | The confirm FOV punch widens (+8°) | Confirming any move; opens the party overhead at FOV 70 settling to 62 over ~0.4 s | C1 round 1 (P2), round 2 | The spec's punch narrows (−3 to −6). C2 owns the punch values; any change is listed in the C2 report. |
| 5 | Lots of 0.2–0.25 s sweeps back to back | Ring → list → target → confirm can be four moves in two seconds | C1 alignment | Each is "snappy" on its own; together they can read as busy. Candidates: skip the menu micro-push when the list opens and closes quickly; cut instead of sweep for menu ↔ target. |
| 6 | FOV springs overshoot slightly | Entering the party overhead (~1.4°), after punches | C1 round 1 (P7) | The punch rides on top of the shot's FOV spring. |
| 7 | Popups linger after the camera cuts away | A MISS stayed over the command-ring area for ~0.3 s after the cut to the next idle shot (phone) | C1 round 2 (L11) | Popups live 1.6 s (the outcome-timing rule). Could fade on the next shot change. |
| 8 | Hero partly behind the mana plate in the idle shot | Desktop and phone; worse since the idle aim was lifted 2 studs | C1 round 2 | The lift keeps damage numbers on enemies clear of a phone's status block. |
| 9 | Phone single-target shot is small | Emulated iPhone 14 (safe area): the enemy stands low (29% of the frame) under a row of plates | C1 round 2 | The phone HUD's plate box is two plates wide and ~80 px tall; the mana plate hides while picking. A bigger enemy would need a HUD change. |
| 10 | Desktop single-target shot is mostly sky above the enemy | 1920×1080 and the Studio window | C1 round 1 (P6) | Partly addressed (enemy head at 48% of the frame). |
| 11 | A pinned plate nudges up to ~12 px as the sway turns the camera | Plates pinned to the HUD box's edge | C1 round 3 (C3-L2) | Within the design slack. |
| 12 | Plate tap during a truck is unverified live | Target select, switching enemies | C1 | Headless test only: Studio's MCP mouse can't click BillboardGui buttons. |
| 13 | The party-wide overhead's retiming (~1.1 s) is unmeasured live | Tailwind | C1 round 2 | Headless measurement only. |
| 14 | All-enemy target framing and the enemy party-lineup shot have never run live | Target select for all enemies; enemy AoE | C1 | No ability targets every enemy until C6, and no enemy has a party-wide attack. Check both when they exist. |
| 15 | On a teammate's screen the summon pops in ~0.25 s before the camera reaches the summon shot | Teammate's summon ability | C1 round 2 (C2-L1) | C3's summon cut-in replaces this beat. |
| 16 | No floor clamp or raycast guard | Any future stage dressing | C1 round 1 (C-L7) | The stage is a floor and figures today. |
| 17 | Overworld geometry visible around the stage | Wide shots, the start sweep, the victory orbit | C1 round 1 (P-10) | No set dressing in scope yet. |
| 18 | The KO'd teammate stands in the survivor's shot like a ghost | Over-the-shoulder shots with a fallen teammate | C1 round 1 (P-4) | Fixed in C2: verified live, the knocked-out character lies dimmed below the survivor's shot. |
| 19 | A blow travelling along the camera's view loses its direction: only its on-screen part drives the trauma, so it shakes mostly sideways | The reaction cut on an enemy's blow (looking along the blow) | C2 critic round 1 | The spec's push-back along an incoming blow would need a dolly kick rather than a screen-space shake. |
| 20 | On a phone, a downed teammate and its dropped weapon show low at the right edge of the survivor's turn shot, under the feed | Over-the-shoulder turn shot with a fallen teammate (phone) | C2 live test | Not standing in the shot, so not a ghost; a wider gap or a slight yaw would take it out of frame. |
| 21 | On an enemy's attack the attacker is on screen only about 0.5 s before the cut to the hero, and the hero recoils from nothing in frame (the enemy never leaves its spot) | Enemy single-target attacks | C2 playtester round 1 | Needs an enemy approach move or a longer incoming shot. |
