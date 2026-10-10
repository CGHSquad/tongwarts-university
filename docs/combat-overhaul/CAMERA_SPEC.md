<!--
How to use this spec in this repo (added by the design chat; the spec below is the owner's, unedited):

1. Precedence: the owner's playtest feedback beats this spec. In particular, enemy turns HOLD on the
   result (target reaction, damage number, status, knockout) for ~0.9 s after impact before the camera
   moves on. The spec's "snappy transitions" apply to the MOVES between shots (hard cuts or <= 0.25 s
   ease-out sweeps), never to how long a shot holds. Section 6B's "snaps to the player on impact" and
   6D's "brief freeze" mean: cut to the reaction, then hold it long enough to read.
2. The pseudocode offsets in section 8 are illustrative only. The owner asked for the over-the-shoulder
   camera to sit further back than C1's first version; tune distances in Studio, don't copy numbers.
3. Milestone mapping: idle/command framing, Dutch tilt, FOV ranges, sub-menu micro-push + DoF,
   target-select framing (single and AoE), buff/heal framing, enemy single and AoE framing -> C1
   alignment pass. Hit-stop, FOV punch values, directional trauma, staggered AoE damage registration
   -> C2. 2D cut-in masking for summons -> C3 (live-text/flash fallback until UI art exists).
   Boss low-angle wind-up -> C8. "Weak/Down" ground snaps apply to knockouts and crits only (the
   Down system is off). Breathing synced to music tempo -> backlog (no music system yet).
4. Reduced motion: drift, sway, shake, FOV punches and whip-pans are reduced or removed under the
   reduced-motion setting; Dutch tilt and static framing are kept.
5. Depth of field: only where the spec calls for it, and switched off on low graphics quality.
-->

# Turn-Based Combat Camera Specification: Atlus Style (*Persona 5* / *Metaphor: ReFantazio*)

## 1. Executive Summary & Philosophy

In modern Atlus turn-based RPGs (*Persona 5*, *Persona 3 Reload*, *Metaphor: ReFantazio*), the combat camera operates not as a static spectator rig, but as an **event-driven cinematic director**. It balances two competing priorities:
1. **Mechanical Clarity:** The player must always clearly parse turn order, target selection, health values, and state changes.
2. **Kinetic Momentum:** Eliminate the "static waiting room" feel common to traditional turn-based systems through continuous subtle motion, high focal compression, stylized Dutch angles, and aggressive hit-stop reactions.

---

## 2. Core Cinematography & Rendering Principles

* **Telephoto / High Focal Compression (Narrow FOV):**
  * Wide-angle lenses are rarely used during action beats.
  * Idle states maintain around **$50^\circ$ to $55^\circ$ FOV**.
  * Execution beats, cut-ins, and target focuses drop to **$35^\circ$ to $42^\circ$ FOV**, compressing background depth to evoke manga and anime panel framing.
* **The Stylized "Dutch Tilt" Rule:**
  * True horizontal horizons are avoided in command menus and wind-ups.
  * A consistent roll between **$-3^\circ$ and $-8^\circ$** is applied to match diagonal UI vectors, keeping idle stances looking dynamic.
* **Snappy Transitions Over Floats:**
  * Avoid long, loose linear camera interpolations.
  * Transitions use **hard cuts** or **accelerated ease-out sweeps** (typically $0.15\text{s}$ to $0.25\text{s}$ maximum duration) so input latency feels arcade-sharp.
* **2D Cut-In Masking:**
  * Full-screen or banner 2D UI cut-ins (e.g., eye flashes, summoning splashes) are utilized as masking buffers. The 3D camera snaps position behind the graphic, avoiding disorienting camera sweeps across the arena.

---

## 3. Player Phase Architecture

### A. Neutral Command State (Over-the-Shoulder)
* **Anchor:** Active party member's root coordinate with a local shoulder/hip offset.
* **Composition:** Two-thirds rule. The active hero occupies roughly one-third of the foreground/side, angled diagonally toward the opposing enemy lineup.
* **Motion:** 
  * Procedural micro-drift/idle bob to prevent a static frame.
  * Subtle camera breathing synchronized to combat music tempo.
* **Turn Cycling (Pass / Next Hero):**
  * Executed via high-speed lateral ease-out whip. The camera sweeps horizontally behind party members rather than jumping disorientingly across the front.

### B. Sub-Menu & Skill Selection
* **Micro-Push:** Opening sub-menus (Skills, Items, Archetypes/Personas) triggers a subtle forward dolly ($0.3\text{m}$ to $0.5\text{m}$) and tightens the Dutch tilt.
* **Depth of Field (DoF):** Subtle background falloff blurs non-active entities and the arena, isolating the character and floating UI.

### C. Target Selection Phase
* **Single-Target Mode:**
  * Camera swings from behind the hero to frame the targeted enemy.
  * Tight FOV ($\approx 40^\circ$), low-angle pitch up toward the enemy.
  * Switching targets triggers a fast horizontal truck/pan directly to the next enemy's center point.
* **All-Target (AoE) Selection Mode:**
  * Camera pulls back along the Z-axis and elevates along the Y-axis.
  * FOV widens to **$60^\circ$ to $65^\circ$** to keep all viable targets within the camera frustum simultaneously.

---

## 4. Execution & Impact Phases

### A. Attack Wind-Up (Hero Isolation)
* Hard cut or snappy dolly to a low-angle three-quarters frontal shot of the caster/attacker.
* Isolates the character performing invocation gestures, weapon flourishes, or Archetype summonings.
* FOV compresses down to $\approx 38^\circ$.

### B. Single-Target Impact & The "Hit Stop"
* **Framing:** Medium close-up of the target contact point or a dynamic profile shot framing both attacker and victim.
* **Hit Stop (Freeze Frame):** Target and attacker rigs freeze for $2$ to $6$ frames on hit contact.
* **FOV Punch:** The camera FOV snaps narrower by **$-3^\circ$ to $-6^\circ$ instantly** on impact frame, then eases back out over $0.15\text{s}$ to $0.2\text{s}$.
* **Directional Impulse Trauma:** Directional screen shake aligned with attack vector (e.g., vertical trauma for overhead bludgeoning; lateral trauma for horizontal slashes).

### C. Multi-Target (AoE) Impact Staging
* **Framing:** Elevated three-quarters wide view ($\approx 60^\circ$ FOV) framed either behind the caster pointing at the pack, or elevated in front of the pack.
* **Staggered Damage Registration:**
  * Enemies do not register hits simultaneously; impacts stagger by $3$ to $5$ frames between targets ($T_1 \to T_2 \to T_3$).
  * Camera executes a global screen shudder and FOV pulse on each individual hit tick.
* **Downed Priority Auto-Focus:** If a specific enemy in the pack is critically struck or killed while others resist, the camera rapidly trucks slightly toward that unit as the spell ends.

---

## 5. Support Abilities: Buffs, Debuffs, and Healing

Support and restorative actions use distinct choreography to maintain pace without dragging down combat momentum.

### A. Single-Target Buffs & Heals (e.g., *Dia*, *Tarukaja*)
1. **Cast Initiation:** Brief frontal/profile medium shot of the caster performing the invocation ($0.2\text{s}$ to $0.3\text{s}$).
2. **Recipient Framing:** Instant snap to the recipient, framed from the chest up.
3. **Vertical Pedestal Lift:** As aura VFX (pillars of light, stat rings) shoots upward, the camera executes a slight vertical elevation movement ($+0.5\text{m}$ to $+1.0\text{m}$) accompanied by an FOV breathe-out to follow energy flow.

### B. Party-Wide Buffs & Heals (e.g., *Media*, *Matarukaja*)
* **Overview Framing:** Instead of cycling four separate character shots, the camera immediately pulls into a high-angle three-quarters overhead shot ($\approx 30^\circ$ downward pitch, $60^\circ$ to $65^\circ$ FOV).
* **Radial Composition:** Party members are framed within the lower and middle thirds of the screen as effects detonate simultaneously under their feet.
* **Cadence:** Kept strictly under $1.2\text{s}$ to prevent defensive rounds from slowing turn flow.

---

## 6. Enemy Turn Phases

Enemy actions are staged to maximize **threat, scale, and vulnerability**, contrasting with the heroic framing of player turns.

### A. Turn Handoff & Wind-Up
* Camera executes a fast whip-pan or direct cut to a low, upward-tilted perspective facing the enemy.
* For boss or large-scale encounters, the camera adopts a ground-level pitch ($15^\circ$ to $25^\circ$ up) with a compressed lens ($35^\circ$ to $40^\circ$ FOV) to force visual mass and make the model loom over the viewport.

### B. Enemy Single-Target Attacks
* **Incoming Framing:** Camera cuts over the targeted hero's shoulder looking out at the incoming attack, or takes a tight two-shot profile.
* **Defensive Reaction Focus:** Snaps directly to the player character on impact.
* **Directional Pushback:** Trauma shake sends the camera back along the incoming impact trajectory.

### C. Enemy AoE on Player Party
1. **Caster Wind-up:** Low-angle profile of the enemy charging or unleashing the attack.
2. **Party Defense Lineup:** Wide rear-diagonal or frontal lineup capturing all standing heroes in a single frame.
3. **Contrast Framing:** The camera stays wide throughout the blast so distinct animations register simultaneously (e.g., Party Member 1 dodges, Member 2 blocks, Member 3 is knocked down).

### D. Downed / Weakness / Critical Reactions
* **Ground Snap:** When a character is downed via weakness or critical hit, the camera snaps to a ground-level shot looking upward at the falling unit.
* **Brief Freeze:** Pauses briefly to let the state change register before snapping directly back to the active attacker's neutral rig.

---

## 7. Camera State Matrix

| Combat State | Primary Anchor Point | FOV | Dutch Roll | Camera Dynamics |
| :--- | :--- | :--- | :--- | :--- |
| **Idle Turn (Player)** | Active Hero Root / Shoulder | $50^\circ - 55^\circ$ | $-3^\circ \text{ to } -6^\circ$ | Idle breathing drift; snappy ease-out on hero swap |
| **Sub-Menu Open** | Active Hero Root | $48^\circ - 52^\circ$ | $-5^\circ \text{ to } -8^\circ$ | Micro-dolly forward; background DoF blur enabled |
| **Target Select (Single)**| Targeted Enemy Torso | $40^\circ - 45^\circ$ | $0^\circ \text{ to } -3^\circ$ | Snappy horizontal truck between targets |
| **Target Select (AoE)** | Enemy Squad Midpoint | $60^\circ - 65^\circ$ | $0^\circ \text{ (Level)}$ | Pull back + upward elevation to frame all units |
| **Player Attack Wind-up** | Attacker Torso / Head | $38^\circ - 42^\circ$ | $+4^\circ \text{ to } +6^\circ$ | Low-angle frontal isolation; fast dolly-in |
| **Impact (Single Hit)** | Hit Contact Point | $35^\circ \text{ (Pulse)}$ | Vector-dependent | 2–6 frame hit-stop; $-5^\circ$ FOV punch with bounce-back |
| **AoE Spell Detonation** | Squad Formation Center | $60^\circ$ | $-2^\circ \text{ to } +2^\circ$ | Staggered camera vibrations per damage tick |
| **Buff / Heal (Single)** | Target Ally Chest-Up | $45^\circ$ | $0^\circ \text{ (Level)}$ | Upward vertical pedestal lift following VFX trajectory |
| **Buff / Heal (Party)** | Hero Party Midpoint | $60^\circ - 65^\circ$ | $0^\circ \text{ (Level)}$ | High-angle overhead shot; static hold ($< 1.2\text{s}$) |
| **Enemy Wind-up (Boss)** | Enemy Ground Plane | $35^\circ - 40^\circ$ | $+5^\circ \text{ to } +8^\circ$ | Extreme low-angle pitch looking upward for scale |
| **Downed / Critical Hit** | Downed Unit Floor Plane | $35^\circ$ | $-6^\circ \text{ to } -8^\circ$ | Instant ground snap; low-angle reaction hold |

---

## 8. Pseudocode: State Machine Implementation

```lua
-- Conceptual State Machine for Atlus-Style Combat Camera
local CombatCameraController = {}
CombatCameraController.__index = CombatCameraController

function CombatCameraController:SetState(newState, context)
    self.CurrentState = newState
    
    if newState == "IDLE_COMMAND" then
        self:SetAnchor(context.ActiveCharacter.RootPart)
        self:SetOffset(Vector3.new(-2.6, 1.4, -4.2)) -- Over-the-shoulder offset
        self:SetFOV(52, 0.25, Easing.ExponentialOut)
        self:SetDutchTilt(-4)
        self:EnableIdleDrift(true)

    elseif newState == "TARGET_SELECT" then
        self:EnableIdleDrift(false)
        if context.IsAoE then
            self:SetAnchor(context.EnemySquadCenter)
            self:SetOffset(Vector3.new(0, 3.5, -8.0))
            self:SetFOV(62, 0.2, Easing.QuarticOut)
            self:SetDutchTilt(0)
        else
            self:SetAnchor(context.SelectedEnemy.RootPart)
            self:SetOffset(Vector3.new(1.8, 0.8, -3.8))
            self:SetFOV(42, 0.15, Easing.QuarticOut)
            self:SetDutchTilt(-2)
        end

    elseif newState == "ACTION_IMPACT" then
        self:EnableIdleDrift(false)
        -- Instant CFrame snap to hit point
        self:SnapToTarget(context.ImpactTarget.RootPart)
        
        -- Execute Hitstop and FOV punch
        self:TriggerHitStop(context.FreezeFrames or 4)
        self:PunchFOV(deltaFOV = -5, returnTime = 0.18)
        self:ApplyTrauma(context.ImpactVector, context.Intensity or 1.0)

    elseif newState == "BUFF_PARTY" then
        self:EnableIdleDrift(false)
        self:SetAnchor(context.PartyCenter)
        self:SetOffset(Vector3.new(0, 5.0, -7.5))
        self:SetFOV(60, 0.25, Easing.CubicOut)
        self:SetDutchTilt(0)
    end
end
```