# WePlay: Personal Tesla Defense Equipment

![Tesla Defense Equipment chain lightning hitting a biter nest](https://i.imgur.com/4G6r9ci.gif)

A Factorio mod that adds **Tesla Defense Equipment**: a 2×2 armor module that automatically zaps nearby enemies with chain lightning. It works like personal laser defense, but each shot arcs from target to target and hits whole groups at once.

The lightning is fully custom. Each bolt follows a random, arcing path that re-rolls several times a second, drawn with hand-generated forking lightning sprites. It looks and works the same with or without **Space Age**.

- [Features](#features)
- [Stats](#stats)
- [Unlocking and crafting](#unlocking-and-crafting)
- [How the lightning works](#how-the-lightning-works)
  - [Overview](#overview)
  - [Damage layer](#damage-layer)
  - [Visual layer: the path](#visual-layer-the-path)
  - [Visual layer: the arc beams](#visual-layer-the-arc-beams)
  - [Sprites](#sprites)
  - [Tuning](#tuning)
  - [Performance](#performance)
  - [Regenerating the sprites](#regenerating-the-sprites)
- [Requirements](#requirements)
- [Installation](#installation)

## Features

- **Automatic chain lightning.** The equipment fires on its own at enemies within range, and the bolt jumps to nearby targets.
- **2×2 armor equipment.** It fits in power armor grids next to your other gear.
- **Runs on suit power.** Each shot draws energy from your armor's power grid, so pack generators or batteries to keep it firing.
- **Custom lightning.** Each bolt follows a jagged, arcing path through a random number of waypoints. The path re-rolls several times a second and tracks moving targets. It's drawn with custom forking-lightning sprites, with spark bursts at the shooter and the target.
- **Space Age optional.** The lightning looks and behaves the same either way. Space Age only changes the recipe, the unlocking technology and which damage research applies.
- **Compatible with overhaul mods.** If the expected technology is missing, the recipe gets attached to whatever technology unlocks Personal Laser Defense. If no such tech exists, the recipe is available from the start.

## Stats

| Property | Value |
|---|---|
| Grid size | 2×2 |
| Range | 20 tiles |
| Fire rate | 1 shot per second (60 tick cooldown) |
| Energy per shot | 110 kJ |
| Internal buffer | 1 MJ |
| Damage modifier | 1.1× |
| Damage | 40 electric per beam damage tick (every 20 ticks) |
| Chain | Up to 6 jumps, 8 tiles per jump, 6 ticks between jumps, 25% fork chance per jump |
| Damage upgrades | Tesla weapon research with Space Age, laser weapons damage research without it |

## Unlocking and crafting

### With Space Age

- **Unlocked by:** Tesla weapons
- **Crafted in:** Electromagnetic plant (20 s)
- **Ingredients:** 1× Tesla gun, 1× Processing unit, 2× Low density structure, 4× Battery, 1× Superconductor

### Without Space Age

- **Unlocked by:** the technology that unlocks Personal Laser Defense
- **Crafted in:** any assembling machine, or by hand (20 s)
- **Ingredients:** 1× Personal laser defense, 5× Processing unit, 5× Low density structure, 10× Battery

## How the lightning works

### Overview

Factorio draws every beam as a straight strip of sprites from A to B, and it can't bend a sprite. To get lightning that curves and kinks, the mod splits each shot into two layers:

| Layer | Where | What it does |
|---|---|---|
| **Damage** | `data.lua` | Normal prototypes: the equipment attack, a `chain-active-trigger` and an invisible damage beam. Handles all damage, jumping, forking and research bonuses. |
| **Visuals** | `data.lua` + `control.lua` | Every hit fires a script trigger. The script builds a random path between the two ends and draws it as a chain of short, visual-only "arc" beams. |

The visual layer never deals damage, and the damage layer is never seen. Because the two only share positions, combat balance is unaffected by any visual setting.

```
equipment fires
 ├─ script trigger "wp-tesla-zap"        → control.lua draws shooter → target 1
 ├─ chain "wp-tesla-equipment-chain"
 │    └─ every jump:
 │         ├─ script trigger "wp-tesla-zap-jump" → control.lua draws target n → target n+1
 │         └─ damage beam (invisible)
 └─ damage beam (invisible)               → shooter → target 1
```

### Damage layer

**Equipment attack** (`wp-personal-tesla-defense-equipment`): a `beam` attack whose ammo action runs three effects, in this order:

1. `script` trigger `wp-tesla-zap`. This goes first so the script knows about the hit before any chain jumps start from it.
2. The chain `wp-tesla-equipment-chain`. This goes before the beam in case the beam kills the target.
3. The damage beam `wp-tesla-equipment-beam` (60 ticks, max length 20).

**Chain** (`wp-tesla-equipment-chain`): 6 jumps, 8 tiles per jump, 6 ticks between jumps, 25% fork chance. On each jump it runs:

1. `script` trigger `wp-tesla-zap-jump`
2. The damage beam (30 ticks, max length 9)

**Damage beam** (`wp-tesla-equipment-beam`): deals 40 electric damage every 20 ticks. Its graphics are `__core__/graphics/empty.png` (1×1, one frame), so it's invisible.

### Visual layer: the path

`control.lua` listens to `on_script_trigger_effect` for the two effect IDs.

**Finding the ends**

- **Main shot:** the start is the shooter, offset `{0, -1.3}` so the bolt leaves from around the shoulders, and the end is the target.
- **Chain jumps:** the trigger system doesn't always report the source you'd expect for a jump. If the reported source is missing, is the target itself, is the character, or is more than 9.5 tiles away, the script uses the **nearest point the lightning hit in the last 45 ticks** instead. Every hit is recorded for this.

**Building the path**, every time the bolt is drawn:

1. **Corners.** The number of corners is `floor(distance / 1.6) - 1`, ±1 at random, clamped to 0–6. Corners are spaced evenly along the line with ±30% jitter and pushed sideways by up to 30% of the bolt's length (max 2.5 tiles).
2. **Curves** (`"arc"` style). Each span between two corners bows out to a random side by up to 35% of its length, as a quadratic Bezier curve. The curve is cut into straight pieces about 1 tile long. The corners themselves stay sharp kinks.
3. **Arc beams.** One visual beam is created for each piece, with `source_position` and `target_position` on consecutive points.

**Re-rolling.** While a zap is alive (60 ticks for the main shot, 30 for a jump), the path is rebuilt every 6 ticks. Each set of arc beams is created with `duration = 6`, so it disappears just as the next set appears. Ends attached to an entity follow it as it moves. When the entity dies, that end stays where it was last seen.

**Path styles** (`CURVE` in `control.lua`):

| Style | Look |
|---|---|
| `"arc"` *(default)* | Spans bow out, sharp kinks at corners. Raw and unpredictable. |
| `"smooth"` | One Catmull-Rom spline through all corners. Flowing, whip-like. |
| `"straight"` | Straight lines between corners. |

### Visual layer: the arc beams

There are four visual-only beam prototypes. They're identical except for their spark bursts, so sparks only appear at the real ends of a bolt and not at every corner:

| Prototype | Used for | Start spark | Ending spark |
|---|---|---|---|
| `wp-tesla-arc-first` | first piece of a path | ✓ | |
| `wp-tesla-arc` | middle pieces | | |
| `wp-tesla-arc-last` | last piece | | ✓ |
| `wp-tesla-arc-single` | a path that is only one piece | ✓ | ✓ |

All four have no `action`, `damage_interval = 1000000`, `hidden = true` and `flags = {"not-on-map"}`.

Each beam's `graphics_set.beam` has these parts:

| Part | Sprite | Role |
|---|---|---|
| `head` | `wp-tesla-beam-source-end.png` | half-tile piece at the source end |
| `body` | `wp-tesla-beam-body.png` | 1-tile pieces repeated along the beam, picked from 6 variations |
| `tail` | `wp-tesla-beam-target-end.png` | half-tile piece at the target end |
| `start` | `wp-tesla-beam-start.png` | small spark burst at the shooter (first/single only) |
| `ending` | `wp-tesla-beam-ending.png` | larger spark burst at the target (last/single only) |

If the pieces don't meet cleanly at the corners in-game, the head and tail are the wrong way round. Set `swap_beam_ends = true` in `data.lua`.

### Sprites

All sprites are on a black background and drawn with `blend_mode = "additive"` and `draw_as_glow = true`. Black adds nothing, and the bolt glows on top of the terrain, even at night. They are high-res and drawn at `scale = 0.5`.

| File | Frame size | Layout | In-game size |
|---|---|---|---|
| `wp-tesla-beam-body.png` | 64×96 | 8 frames × 6 rows (one row per variation) | 1 × 1.5 tiles |
| `wp-tesla-beam-source-end.png` | 32×96 | 8 frames × 1 row | 0.5 × 1.5 tiles |
| `wp-tesla-beam-target-end.png` | 32×96 | 8 frames × 1 row | 0.5 × 1.5 tiles |
| `wp-tesla-beam-start.png` | 96×96 | 8 frames × 1 row | 1.5 × 1.5 tiles |
| `wp-tesla-beam-ending.png` | 96×96 | 8 frames × 1 row | 1.5 × 1.5 tiles |

**Shared anchors: why the pieces always connect.** Factorio requires every animation in a beam to have the same frame count (8 here), and it plays the same frame number on every piece of a beam at the same time. Each frame number *k* has one **anchor height** shared by every body variation and both end pieces. Every body frame *k* enters and exits at that height, so neighboring body pieces always join up while the whole bolt jumps up and down from frame to frame (up to ±16 px, ±0.25 tile in-game). Consecutive frames' anchors are forced well apart so the jump is visible.

**End pieces** join the body at the anchor height on their inner edge and pinch to dead center on their outer edge. That makes every path piece start and end exactly on its waypoint, so pieces meet at the corners.

**Inside each frame:**
- A bright white core over two blue glow layers.
- Forks that branch and split again, fading out before they reach a frame edge so nothing gets cut off.
- A 40% chance of a faint second strand that splits off the main bolt and rejoins it.
- A random brightness per frame number (100%, 85% or 65%), so the whole bolt strobes together.

**Animation speed:** `animation_speed = 0.2`, a new frame every 5 ticks.

### Tuning

**`control.lua`** (visuals only, no effect on balance):

| Setting | Default | Effect |
|---|---|---|
| `REPATH_TICKS` | `6` | Re-roll the path this often. `0` keeps one path for the whole zap. |
| `SEGMENT_LENGTH` | `1.6` | Average tiles between corners. Lower means more corners. |
| `CORNER_JITTER` | `1` | Random ± on the corner count each re-roll. `0` turns it off. |
| `MAX_WAYPOINTS` | `6` | Cap on corners per bolt. |
| `CURVE` | `"arc"` | `"arc"`, `"smooth"` or `"straight"`. |
| `BOW` | `0.35` | How far an arc span bulges, as a fraction of its length. |
| `PIECE_LENGTH` | `1.0` | Length of the straight pieces that make up a curve, in tiles. Higher means fewer pieces and blockier curves. |
| `SWING` / `MAX_SWING` | `0.3` / `2.5` | Sideways offset of corners: fraction of bolt length, capped in tiles. |
| `MAIN_DURATION` / `JUMP_DURATION` | `60` / `30` | How long bolts are drawn, in ticks. These match the damage beams. |
| `MAX_JUMP` | `9.5` | Farthest a chain jump can reach, used when checking jump sources. |
| `SHOOTER_OFFSET` | `{0, -1.3}` | Where the main bolt leaves the character. |
| `MAX_ZAPS` | `200` | Safety cap on bolts being drawn at once. |

**`data.lua`:**

| Setting | Default | Effect |
|---|---|---|
| `beam_animation_speed` | `0.2` | Sprite frames per tick. Higher means more frantic flicker. |
| `swap_beam_ends` | `false` | Swaps the head and tail sprites if the corners don't line up. |

### Performance

Measured with the in-game time usage display:

| Situation | Script time per tick |
|---|---|
| Idle | ~0.001 ms |
| A dozen or so units firing into a nest | ~0.2 ms (about 1% of the 16.7 ms tick budget) |

Most of that cost is creating the arc beams. If it's ever a problem, raise `REPATH_TICKS` (for example to 8) or `PIECE_LENGTH` (for example to 1.3).

### Regenerating the sprites

The sprites come from `tools/make_lightning.py` (Python 3 with `numpy`, `Pillow` and `scipy`). The game doesn't need this folder.

```sh
cd tools
python3 make_lightning.py        # default seed
python3 make_lightning.py 42     # a different batch of bolts
```

It writes the five sprite sheets plus `preview.gif`, a straight test piece played at the in-game frame rate. Copy the PNGs into `graphics/entity/`. Frame sizes, frame count, anchor range, strand chance and colors are constants at the top of the script. If you change the frame count, variation count or frame sizes, update `beam_frames`, `beam_variations` and `body_width`/`end_width`/`beam_height` in `data.lua` to match.

## Requirements

- Factorio **2.1**
- `base`
- `space-age` *(optional)*

## Installation

**Mod portal:** Search for *WePlay: Personal Tesla Defense Equipment* in the in-game mod browser.

**Manual:**
1. Download the latest release zip.
2. Put it in your Factorio `mods` folder without extracting it:
   - Windows: `%APPDATA%\Factorio\mods`
   - Linux: `~/.factorio/mods`
   - macOS: `~/Library/Application Support/factorio/mods`
3. Enable the mod in the in-game Mods menu.

## Changelog

See [changelog.txt](changelog.txt).

## Credits

Made by **WePlay**.
