# TungWarts University: UI Asset Sheet Prompts (ChatGPT Image)

This turns your approved mockups into the cut-out parts that get imported into Roblox. It covers 13 sheets. Each sheet is one ChatGPT image full of separate UI parts on a flat magenta background. You cut them out with `cut_sheet.py` (included), upload them to Roblox, and the devs assemble the real screens from them.

## Ground rules

- **3D models replace the characters and summons.** The player avatars, Tung Tung Sahur, Wild Sapling, and the battle scenery are live 3D in Roblox. No sheet contains characters, creatures, faces or scenery. Where a portrait goes, the part is an **empty frame**.
- **Almost no baked-in text.** Names, numbers, "WEAK", "DOWN", "MANA" and so on are live Roblox text, so they can change and be localized. Only two pieces of lettering are drawn into art: **ONE MORE!** and **VICTORY**.
- **No compass emblems.** Use four-point stars and rune rings instead.
- **Stretchable parts.** Roblox stretches panels with 9-slice images, but it can't skew them. So every bar and panel is drawn **straight and horizontal, with slanted ends and a plain middle**. All decoration sits in the end caps, so the middle can stretch.
- **Mana, not MP.** Your GDD calls the resource "Mana". The mockups say "MP". Since no text is baked into the art, the game can use either. Decide on one.

## Workflow (per sheet)

1. Start a **new ChatGPT chat** for each sheet. A fresh chat avoids it drifting back to old layouts.
2. Attach the approved screens listed under "Attach" for that sheet. Use `UI_Mockups_Approved.zip` (unzip first; the files are named `S1` to `S7`).
3. Paste the **ASSET PREFIX**, then the **sheet block**, then the **ASSET SUFFIX**.
4. Check the result with the **QA checklist** at the bottom. If it's wrong, reply with a one-line fix (for example: *"Redo this, but with more space between parts and no text in any part."*).
5. Download the PNG and run:
   ```
   python3 cut_sheet.py sheet_03.png out/combat_stamps --prefix combat
   ```
   Open `out/combat_stamps/_preview.png` to see the number on each part. Rename the files from the part list in the sheet block (or pass `--names names.txt`, one name per line in sheet order).
6. Upload the cut files through Roblox Studio's Asset Manager (bulk import). Give the asset IDs to the devs (see the handoff doc).

You can also upload the sheets to a Claude chat and ask it to cut and rename them.

**Resolution.** ChatGPT images commonly come out around 1536×1024, so a part on a 12-part sheet is a few hundred pixels wide. That's enough for phone UI. Large pieces (the VICTORY title, backgrounds) come out better on their own, with fewer parts per sheet. Don't pack extra parts onto a sheet.

**Tinting.** Roblox can tint an image with `ImageColor3`, but only multiplicatively. Parts marked **(NEUTRAL)** are drawn in white and light gray with black ink outlines so they can be recolored in code. Everything else is drawn in final colors.

---

## ASSET PREFIX (paste first, every sheet)

```
You are making a UI ASSET SHEET (a sprite sheet of separate game UI parts) for a Roblox game. The attached images are my approved UI mockups. Match their art style exactly: obsidian and deep navy panels, celestial-gold trim, torn ink-brush edges, angular slanted shapes, cyan and arcane-purple accents, crisp cel-shaded look.

HARD RULES
- Background: one flat solid magenta #FF00FF everywhere. No gradient, no texture, no shadow on the background.
- Every part is a separate object with at least 80 pixels of empty magenta around it. Parts must never touch or overlap.
- Do NOT draw any characters, faces, creatures, scenery or backgrounds. Where a portrait goes, draw an EMPTY frame with a plain dark fill.
- Do NOT put any text, numbers or letters in a part unless the part is marked LETTERING. Leave label areas blank.
- Do not use magenta or hot pink in any part. (Arcane purple #7B3FE4 is fine.)
- Keep glows tight: any outer glow stays within about 12 pixels of the part and must not tint the background. Prefer inner glow and crisp gold outlines.
- No compass emblems or compass icons. Use small four-point stars instead.
- Draw each part flat and front-on: no perspective, no rotation, no drop shadow.
- Bars and panels: draw them straight and horizontal, with slanted left and right ends, a PLAIN uniform middle (no unique details), and all decoration in the end caps.
- Draw parts large. Arrange them on a loose grid, left to right, top to bottom, in the order listed. Output one 3:2 landscape image.
```

## ASSET SUFFIX (paste last, every sheet)

```
Draw ONLY the parts listed, once each. Do not add a title, labels, a legend, a border, a caption, or extra parts.
```

---

## Sheet 01: Buttons and badges
**Attach:** S2, S3, S4, S6.

```
SHEET: buttons and badges. PARTS, in order:
1. BACK button plate, small, blank, black ink-brush slab with gold edge, slanted ends. Normal state.
2. BACK button plate, pressed state (slightly darker, inset look).
3. Primary button plate, wide, blank, glossy gold with a black ink edge. Normal state.
4. Primary button plate, pressed state.
5. Primary button plate, disabled state (desaturated gray-gold).
6. Small round tap icon: a white pointing-hand cursor with a thin black outline.
7. Plus badge: a small purple circle with a white plus sign and a gold ring.
8. Lock badge: a small dark circle with a gray padlock and a thin gold ring.
9. Level-up badge, blank: a green rounded-angle plate with a bold white up arrow on the left and an empty area on the right.
10. Divider line: a thin gold line with a four-point star in the center.
11. Four-point star, gold, large.
12. Sparkle, small, gold and white (draw three in a row, three sizes).
```

## Sheet 02: Element and ability icons
**Attach:** S3, S7, S4.

```
SHEET: round icon medallions, all the same size, each a dark navy disc with a thin gold ring, and a bold simple glyph in the center. PARTS, in order:
1. Empty medallion (ring only, no glyph), normal.
2. Empty medallion, selected (bright cyan ring and soft inner glow).
3. Physical: a sword.
4. Fire: a flame, red and orange.
5. Ice: a snowflake, pale blue.
6. Wind: a spiral swirl, teal-green.
7. Nature: a leaf, green.
8. Lightning: a yellow bolt.
9. Light: an eight-point gold star.
10. Dark: a purple vortex.
11. Heal: a bright green cross.
12. Guard: a shield, gold and brown.
13. Item: a round potion bottle, teal.
14. Pass: a pair of footsteps, silver.
```

## Sheet 03: Combat command ribbons and stamps
**Attach:** S1, S7.

```
SHEET: combat command ribbons and stamps. PARTS, in order:
1. COMMAND RIBBON, steel blue: an explosive ink-splatter brush shape pointing right, with a torn edge and a blank dark area on the right for text. Blank.
2. COMMAND RIBBON, arcane purple. Same shape, blank.
3. COMMAND RIBBON, emerald green. Same shape, blank.
4. COMMAND RIBBON, amber gold. Same shape, blank.
5. COMMAND RIBBON, pale silver. Same shape, blank.
6. ALL-OUT ATTACK ribbon: a wide, jagged gold-and-yellow burst with a black ink core and a blank text area. Blank.
7. LETTERING: the words "ONE MORE!" in a bold, slanted, gold-and-white display font with a thick black outline, inside a gold-and-cyan spiky star burst.
8. TAG blank, crimson: a small angular tag with a torn edge (for the word WEAK).
9. TAG blank, blue (for RESIST).
10. TAG blank, gray (for NULL).
11. TAG blank, crimson and gold (for DOWN), slightly larger than the others.
12. Dizzy effect: a spiral and three small gold stars, arranged as if circling above something's head.
13. NEUTRAL ink-brush ribbon, white fill with a black ink outline, wide, blank (will be tinted in the game).
```

## Sheet 04A: Turn order bar and enemy overlay
**Attach:** S1, S7.

```
SHEET: turn order and enemy overlay. PARTS, in order:
1. Turn-order bar frame: very wide, obsidian with gold trim and slanted ends, EMPTY inside. The left end has a small blank block (for a round label).
2. Turn token frame, normal: a small square with slanted corners, gold rim, empty dark fill.
3. Turn token frame, active: same shape, bright cyan glowing rim.
4. Turn token frame, enemy: same shape, crimson rim.
5. Enemy name plate, blank: a slanted crimson-and-black plate.
6. Enemy HP bar track: a slim, slanted, empty dark bar with a thin gold outline.
7. Enemy HP bar fill: a slim slanted bright red fill shape (no outline), same size as the track interior.
8. Enemy target bracket pair: a left bracket and a right bracket, thin crimson, angular, drawn with a gap between them (draw them close together as one part).
9. Enemy target bracket pair, selected: the same shape in bright gold, with a glow.
10. Weak marker: a round crimson medallion with a gold ring and an empty center (a flame icon will be placed inside).
```

## Sheet 04B: Party cards, bars, and mana plate
**Attach:** S1, S5, S7.

```
SHEET: party cards and bars. PARTS, in order:
1. Party card frame, normal: a slanted obsidian card with a gold edge, an EMPTY square socket on the left (for a portrait), and two empty bar tracks on the right. Blank.
2. Party card frame, active: the same card with a bright gold-and-cyan glowing edge.
3. HP bar track (green theme): a slim slanted empty dark bar with a thin outline.
4. HP bar fill: a slim slanted bright green fill with a lighter top edge.
5. Mana bar track: same as the HP track.
6. Mana bar fill: a slim slanted bright blue fill.
7. Hero mana plate, blank: a wide obsidian-and-gold plate with an EMPTY square socket on the left and an empty bar track on the right.
8. Callout banner, blank: a slanted black ink banner with a gold edge, an EMPTY round socket on the left, and a blank text area. (OPTIONAL: only if the team keeps teammate callouts.)
```

## Sheet 05: Skill list parts
**Attach:** S7, S3.

```
SHEET: skill and item list parts. PARTS, in order:
1. List header plate, blank: a purple-and-black ink-burst slab, wide, for a title word.
2. Skill row, normal: a wide row (about 6:1), obsidian with a gold edge and slanted ends, an EMPTY round socket on the left, a blank middle, and an empty cost slot on the right.
3. Skill row, selected: the same row with a bright gold-and-cyan jagged glowing edge, slightly taller.
4. Skill row, dimmed: the same row, desaturated gray, no glow.
5. Skill row, locked: the same row, very dark, with a small gray padlock on the left and a dashed outline.
6. Description plate: a wide, slim obsidian plate with a gold underline, blank, that sits under the selected row.
7. Weak row tag, blank: a small bright crimson angular tag that attaches to the left edge of a row.
8. Cost capsule, blank: a purple pill with slanted ends (for "8 Mana").
9. Cost capsule, dimmed: the same capsule, gray.
10. Quantity capsule, blank: a dark gold pill with slanted ends (for "x3").
```

## Sheet 06: Main menu parts
**Attach:** S2.

```
SHEET: main menu parts. PARTS, in order:
1. Menu slab, short: a black torn-ink brush slab with slanted ends, blank.
2. Menu slab, medium: same, wider.
3. Menu slab, long: same, widest.
4. Menu slab, selected: a large black ink slab with a purple-and-gold jagged glowing edge, blank.
5. Gold brush streak accent, long and thin.
6. Gold brush streak accent, short.
7. White ink-splash streak, long diagonal, ragged (draw it on a diagonal).
8. Currency plaque, blank: a wide obsidian plaque with slanted ends, an EMPTY round socket on the left, and thin gold arcs on both sides.
9. Rune ring: a large, thin gold circle with small rune marks around it and a faint inner ring. No compass points.
```

## Sheet 07: Summon and party status parts
**Attach:** S3, S5.

```
SHEET: status screen parts. PARTS, in order:
1. Name header plate, blank: a wide black plate with a jagged gold-and-cyan lightning edge and slanted ends, with an empty area on the right for a level.
2. Small tag plate, blank: a slim cyan-and-gold tag (for "NEXT EXP").
3. Affinity medallion ring, empty: a round dark disc with a gold ring (no glyph).
4. Affinity thread: a thin gold line with a small four-point star at each end, horizontal.
5. Stat row frame, blank: a slanted black row with a gold edge, a blank area on the left for a number, a blank area for a label, and an empty bar track on the right.
6. Stat bar fill: a slanted fill with a gradient from bright cyan on the left to gold on the right (no outline).
7. Party banner row, normal: a wide slanted obsidian-and-gold banner with an EMPTY small square socket on the left and blank areas for a name, level and two bars. Blank.
8. Party banner row, selected: the same banner, wider, with a gold-and-cyan jagged glowing edge.
9. Title plate, blank: a jagged black-and-gold plate for a big title word.
10. Question plate, blank: a slim torn-ink black plate with gold edges.
```

## Sheet 08: Skill tree parts
**Attach:** S4.

```
SHEET: skill tree parts. PARTS, in order:
1. Hex node frame, unlocked: a thick beveled gold hexagon rim with a soft gold-and-cyan glow and an EMPTY dark interior.
2. Hex node frame, available: a gold rim with a dim purple glow and an EMPTY dark interior.
3. Hex node frame, locked: a dull dark-gray rim, no glow, EMPTY black interior.
4. Hex node frame, selected: the unlocked hexagon surrounded by a bright white double ring with a soft glow.
5. Thread, active: a straight, thin glowing gold line, horizontal, long.
6. Thread, inactive: a straight, thin dark-gray line, horizontal, long.
7. Thread junction: a small four-point gold star with a glow.
8. Name ribbon, NEUTRAL: a torn ink-brush ribbon with a white fill, a black outline and a blank text area (will be tinted per branch).
9. Detail card frame, blank: a tall obsidian card with a jagged torn gold-and-cyan edge, a large empty hexagon socket at the top, and blank areas below.
10. Cost tag, blank: a purple slanted tag with a small blue crystal icon on the left and an empty text area on the right.
11. Skill-point plate, blank: a slim black plate with gold edges, a small blue crystal icon on the left and an empty text area.
```

## Sheet 09A: Results screen parts
**Attach:** S6.

```
SHEET: results screen parts. PARTS, in order:
1. LETTERING: the word "VICTORY" in huge, bold, slanted display letters, white and gold, with a thick black ink outline, torn paint edges, and small gold sparks around it. Draw this part as large as possible.
2. Subtitle ribbon, blank: a small slanted black ribbon with a gold edge and a cyan edge, with an empty text area.
3. Tally plate, normal: a wide black torn-ink plate with a jagged cyan edge, an EMPTY square socket on the left (for an icon), and blank areas for a label and a number.
4. Tally plate, gold: the same plate with a jagged gold edge.
5. Tally plate, green: the same plate with a jagged green edge.
6. Item slot frame: a round hexagon-cut gemstone frame with a thick gold rim, a glowing edge, and an EMPTY dark interior.
7. Item quantity tag, blank: a small dark-gold angled tag.
8. Result party row, blank: a wide slanted obsidian row with a gold edge, an EMPTY square socket on the left, and blank areas for a name, a level, and an empty slim bar track.
```

## Sheet 09B: Item icons and particles
**Attach:** S6, S7.

```
SHEET: item icons and particles, as simple, bold, game-ready pictures with a thin black outline, no frames. PARTS, in order:
1. Red potion (round flask).
2. Blue potion (tall flask).
3. Green herb (a sprig of leaves).
4. Rune shard (a blue crystal with a glowing rune).
5. Amber gem (a faceted gold-orange crystal, the currency icon).
6. Scroll (a rolled parchment with a gold tie).
7. Gold spark particle, large.
8. Gold spark particle, small.
9. Gold shard particle (a thin diamond-shaped sliver).
10. Leaf particle (a single flat green-gold leaf).
```

## Sheet 10: Ink overlays
**Attach:** S2, S3, S5, S6.

```
SHEET: full-screen ink overlays. Each part is a large, wide, ragged brush-stroke shape meant to sit over the screen. Draw them large, one per row. PARTS, in order:
1. Diagonal white ink streaks: three long, ragged white streaks running from lower-left to upper-right.
2. Diagonal gold ink streaks: two long, ragged gold streaks, same direction.
3. Diagonal cyan ink streaks: two long, ragged cyan streaks, same direction.
4. Black torn-ink panel, large: a big black ragged-edged brush shape (for a menu backdrop), with some small white flecks.
5. Black torn-ink panel, tall: a tall black ragged-edged shape.
6. Paint splatter: white, purple and gold splashes scattered in one cluster.
```

## Sheet 11: Full-screen backgrounds (separate images, NOT a sheet)
**Attach:** S3, S4, S5.

For the three screens with no 3D scene, make **three separate full-screen 16:9 images**, one at a time. These are normal images with no magenta background. They are drawn by the image tool, not cut.

```
BACKGROUND A (summon status screen): a dark navy-and-black graphic background with large diagonal white-edged shards, a halftone dot texture, and soft purple and cyan rune circles in the right half. No UI, no text, no characters, no creatures. Keep the left 45% simple and dark so text is readable on it. 16:9.
```
```
BACKGROUND B (party screen): a dark textured paint-splatter background in deep navy, black and purple, with white and gold ink splashes streaking diagonally from lower-left to upper-right, high contrast. No UI, no text, no characters. Keep the left 45% simple and dark so text is readable on it. 16:9.
```
```
BACKGROUND C (skill tree screen): a deep midnight-navy star chart with fine concentric rune rings, thin gold coordinate lines, tiny stars, faint ink sketch lines, and subtle ink bleed, darker at the edges. No nodes, no UI, no text, no compass roses. Keep the middle quiet so skill nodes stand out. 16:9.
```

---

## QA checklist (check every sheet before cutting)

- Background is flat magenta, with no gradients or shadows on it.
- Parts don't touch each other, and there's clear space around each.
- No faces, characters, creatures or scenery appear anywhere.
- No text appears except on the parts marked LETTERING (ONE MORE!, VICTORY).
- No compass shapes. Stars and rune rings are fine.
- No part contains magenta or hot pink.
- Bars and panels are straight (not rotated) with a plain middle.
- Parts in a family match each other (all the "normal / selected / dimmed" rows are the same size).
- The parts are all there, in the order listed. If some are missing, ask for another sheet with only the missing parts.

## After cutting: naming and Roblox settings

Name each file `UI_<screen>_<part>.png`, for example `UI_Combat_CommandBlue.png`, `UI_SkillList_RowSelected.png`, `UI_Tree_NodeLocked.png`.

| Part type | Roblox setting |
|---|---|
| Bars and panels with a plain middle | `ImageLabel.ScaleType = Enum.ScaleType.Slice`. Set `SliceCenter` across the plain middle, spanning the full height for a horizontal 3-slice. If you cut at 2x, set `SliceScale = 0.5`. Verify it in Studio. |
| Fixed-size parts (icons, badges, nodes, stamps) | `ScaleType = Fit`, with a `UIAspectRatioConstraint` to keep the shape |
| NEUTRAL parts | Tint with `ImageColor3` |
| Particle parts | Use as a `ParticleEmitter` texture |
| Backgrounds | `ScaleType = Crop`, full-screen `ImageLabel` behind the UI |

Large PNGs cost memory on phones, so downsize the backgrounds (about 1920×1080 at most) and compress with a tool like TinyPNG before uploading.
