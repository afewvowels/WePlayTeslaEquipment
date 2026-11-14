# WePlay: Personal Tesla Defense Equipment

![Tesla Defense Equipment chain lightning hitting a biter nest](https://i.imgur.com/4G6r9ci.gif)

A Factorio mod that adds **Tesla Defense Equipment**: a 2×2 armor module that automatically zaps nearby enemies with chain lightning. It works like personal laser defense, but each shot arcs from target to target and hits whole groups at once.

The lightning is fully custom. Each bolt follows a random, arcing path with dead-end branches crackling off it, and it thrashes, settles and twitches at an irregular pace instead of ticking along like a flip book. It's drawn with procedurally generated forking-lightning sprites. It looks and works the same with or without **Space Age**.

- [Features](#features)
- [Stats](#stats)
- [Unlocking and crafting](#unlocking-and-crafting)
- [Settings](#settings)
- [How the lightning works](#how-the-lightning-works)
  - [Overview](#overview)
  - [Damage layer](#damage-layer)
  - [Visual layer: the path](#visual-layer-the-path)
  - [Visual layer: branches](#visual-layer-branches)
  - [Visual layer: timing and moods](#visual-layer-timing-and-moods)
  - [Visual layer: colour and depth](#visual-layer-colour-and-depth)
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
- **Custom lightning.** Each bolt follows a jagged, arcing path through a random number of waypoints, with dead-end branches up to 3.5 tiles long splitting off it. Bolts come in several tints (white, ice, blue, violet) and two depths, so overlapping lightning stays layered instead of blowing out to white. They switch between frantic, normal and calm moods, so they thrash, settle and twitch at an irregular pace, and they track moving targets. It's drawn with custom forking-lightning sprites, with spark bursts at the shooter and the target.
- **Quality or Performance.** A map setting switches between the full lightning and a lighter version for big fights or busy bases. It only changes the look, never the damage.
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

## Settings

**Lightning visuals** (Settings → Mod settings → Map). It's a map setting because the lightning is drawn with real entities, so every player in a multiplayer game has to use the same one. It can be changed mid-game.

| | Quality *(default)* | Performance |
|---|---|---|
| Branches | ✓ | ✗ |
| Average tiles between corners | 1.6 | 2.0 |
| Max corners per bolt | 6 | 4 |
| Length of the straight pieces in a curve | 1.0 tile | 1.5 tiles |
| Redraw interval: frantic / normal / calm | 2–4 / 4–8 / 8–16 ticks | 3–6 / 6–10 / 10–18 ticks |
| Beam pieces created (same simulated fight) | 100% | ~25% |

Everything else (moods, twitching, curves, sprites, sparks) is the same in both.

## How the lightning works

### Overview

Factorio draws every beam as a straight strip of sprites from A to B, and it can't bend a sprite. To get lightning that curves and kinks, the mod splits each shot into two layers:

| Layer | Where | What it does |
|---|---|---|
| **Damage** | `data.lua` | Normal prototypes: the equipment attack, a `chain-active-trigger` and an invisible damage beam. Handles all damage, jumping, forking and research bonuses. |
| **Visuals** | `data.lua` + `control.lua` | Every hit fires a script trigger. The script builds a random path between the two ends and draws it as a chain of short, visual-only "arc" beams. |

The visual layer never deals damage, and the damage layer is never seen. Because the two only share positions, combat balance is unaffected by any visual setting.

**Built on the [WePlay Beam Library](https://mods.factorio.com/mod/WePlayBeamLib) (`WePlayBeamLib` 0.16.0 or later).** The generic lightning machinery lives there and Tesla supplies the look and the rules:

| From the library | Used for |
|---|---|
| `beamlib.bolt` | shapes, twitching, branches, moods |
| `beamlib.arcs.spawn` | creating the visual beam pieces along a path |
| `beamlib.vec` | positions and distances |
| `datalib.make_path_beam_variants` | the tinted, speed-varied visual beam prototypes |
| `datalib.invisible_beam_graphics` | the invisible damage beam |

Tesla keeps what's specific to it: the triggers, finding chain-jump sources, the colour picks, the Quality/Performance presets and the list of live zaps.

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

**Damage beam** (`wp-tesla-equipment-beam`): deals 40 electric damage every 20 ticks. Its graphics come from the library's `invisible_beam_graphics()` (`__core__/graphics/empty.png`, 1×1, one frame), so it's invisible.

### Visual layer: the path

`control.lua` listens to `on_script_trigger_effect` for the two effect IDs.

**Finding the ends**

- **Main shot:** the start is the shooter, offset `{0, -1.3}` so the bolt leaves from around the shoulders, and the end is the target.
- **Chain jumps:** the trigger system doesn't always report the source you'd expect for a jump. If the reported source is missing, is the target itself, is the character, or is more than 9.5 tiles away, the script uses the **nearest point the lightning hit in the last 45 ticks** instead. Every hit is recorded for this.

**The shape** (`beamlib.bolt.new_shape`). Each zap keeps a *shape* measured relative to its two ends, so it stretches and turns with them as they move:

- **Corners**, each stored as `t` (how far along the line, 0–1) and `s` (sideways offset in tiles). The count is `floor(distance / 1.6) - 1`, ±1 at random, clamped to 0–6. They're spaced evenly with ±30% jitter and pushed sideways by up to 30% of the bolt's length (max 2.5 tiles).
- **Bows**, one per span between corners: how far that span bulges to the side, up to ±35% of its length.

**Drawing it** (`beamlib.bolt.points` with `style = "arc"`, then `beamlib.arcs.spawn`):

1. Place the corners between the current end positions.
2. Bow each span into a quadratic Bezier curve and cut it into straight pieces about 1 tile long. The corners stay sharp kinks.
3. Create one visual beam per piece, with `source_position` and `target_position` on consecutive points.
4. Grow the branches off the finished path (see below).

Each set of beams is created with a `duration` equal to the time until the next redraw, so it disappears just as the next set appears. Ends attached to an entity follow it as it moves. When the entity dies, that end stays where it was last seen.

**Path styles** (`DRAW.style` in `control.lua`):

| Style | Look |
|---|---|
| `"arc"` *(default)* | Spans bow out, sharp kinks at corners. Raw and unpredictable. |
| `"smooth"` | One Catmull-Rom spline through all corners. Flowing, whip-like. |
| `"straight"` | Straight lines between corners. |

### Visual layer: branches

Branches (`beamlib.bolt.new_branches` / `branch_paths`) are dead-end bolts that split off the main path and fade out, bulking up the lightning. A piece of sprite can only hold forks as long as the piece itself (1 tile), so long offshoots have to be drawn by the script as separate bolts.

- **Count:** about 0.3 per tile of bolt (rounded at random), max 5 per bolt.
- **Each branch** stores where it attaches (`u`, 10–90% of the way along the path, measured by length), its angle off the path's local direction (0.35–1.25 radians, either side), its length (1–3.5 tiles), and its own corner-and-bow shape (a corner about every 1.2 tiles, swinging up to 35% of its length).
- **Sub-branches:** a branch has a 35% chance of growing one smaller branch (55% length) from 30–80% of the way along it.
- **Pieces:** `wp-tesla-branch-<tint>-<speed>`, with `-first` / `-last` / `-single` from the library. The last (and single) piece's tail is the tip sprite, which fades out instead of pinching to a point, so the branch trails off into nothing.

Because branches attach by fraction and angle, a twitch moves them along with the bolt instead of leaving them behind.

### Visual layer: timing and moods

A fixed redraw rate looks like a flip book, so each zap has a **mood** (`beamlib.bolt.next_step`) that decides how its next redraw behaves:

| Mood | Ticks until next redraw | New shape vs. twitch | Sprite flicker | Chance chosen |
|---|---|---|---|---|
| `frantic` | 2–4 | 90% new | `fast` (0.4) | 30% |
| `normal` | 4–8 | 65% new | `normal` (0.2) | 40% |
| `calm` | 8–16 | 15% new | `slow` (0.1) | 30% |

At each redraw the zap keeps its mood (60% chance for frantic/normal, 50% for calm) or picks a new one, so a bolt thrashes for a while, settles, then flares up again.

- **New shape:** fresh corners, bows and branches.
- **Twitch:** the same shape, nudged. Corners move up to ±4% along the bolt and ±0.3 tiles sideways, bows by ±0.1, branch angles by ±0.2 radians, branch lengths by ±10%. A 30% chance also swaps one branch for a new one, so calm bolts still crackle.

The mood's speed picks which version of the visual beams is used (`-slow`, `-normal` or `-fast`). Every piece of one redraw uses the same speed.

Set `IRREGULAR = false` to go back to the old behavior: a new shape every `FIXED_INTERVAL` (6) ticks at normal speed.

### Visual layer: colour and depth

All visual beams are drawn with additive blending, so overlapping light adds up. With a single colour, a dozen bolts in one spot add up to flat white and the middle of a big fight collapses into one glowing mass. Three things keep it layered:

1. **Tints.** Every visual beam exists in four tints, and each zap picks one when it starts (weights: white 4, ice 3, blue 2, violet 2). Overlapping bolts of different hues mix instead of all piling into white. On a brand-new shape there's a 15% chance the bolt also changes hue.
2. **Depth.** Every tint also has a dim version at 50% brightness. Main shots are dim 15% of the time and chain jumps 60%, so the bright shooter bolts sit in front and the jumps fill in behind them.
3. **Tight glow.** The sprites use a tight, modest halo (see [Sprites](#sprites)), so overlapping glows don't fog over the gaps between bolts.

| Tint | Colour (r, g, b) |
|---|---|
| `white` | 1.0, 1.0, 1.0 |
| `ice` | 0.65, 0.95, 1.0 |
| `blue` | 0.45, 0.62, 1.0 |
| `violet` | 0.78, 0.55, 1.0 |
| `*-dim` | the same × 0.5 |

Tints are applied by the game when drawing (`tint` on each animation), so they reuse the same sprite sheets: no extra graphics memory and no extra runtime cost. Branches use their bolt's tint. Set `COLORFUL = false` in `control.lua` to make every bolt bright white again.

### Visual layer: the arc beams

The visual beams are built by the library's `make_path_beam_variants` in two families, `wp-tesla-arc` (main bolt) and `wp-tesla-branch`. Each comes in eight tints (`white`, `ice`, `blue`, `violet`, each also `-dim`), three animation speeds (`slow` 0.1, `normal` 0.2, `fast` 0.4) and four path positions, for 192 prototypes in total, named `<family>-<tint>-<speed>[-first|-last|-single]`, e.g. `wp-tesla-arc-violet-dim-fast-first`. The positions differ only in their ends, so sparks only appear at the real ends of a bolt and not at every corner:

| Position | Used for | Main bolt (`wp-tesla-arc-*`) | Branch (`wp-tesla-branch-*`) |
|---|---|---|---|
| `-first` | first piece | start spark | pinched tail |
| *(none)* | middle pieces | — | pinched tail |
| `-last` | last piece | ending spark | fading tip |
| `-single` | a path that is only one piece | start and ending sparks | fading tip |

All of them have no `action`, `damage_interval = 1000000`, `hidden = true` and `flags = {"not-on-map"}`.

Each beam's `graphics_set.beam` has these parts:

| Part | Main bolt sprite | Branch sprite | Role |
|---|---|---|---|
| `head` | `wp-tesla-beam-source-end.png` | `wp-tesla-branch-source-end.png` | half-tile piece at the source end |
| `body` | `wp-tesla-beam-body.png` (6 variations) | `wp-tesla-branch-body.png` (4 variations) | 1-tile pieces repeated along the beam |
| `tail` | `wp-tesla-beam-target-end.png` | `wp-tesla-branch-target-end.png`, or `wp-tesla-branch-tip.png` on last/single (`tail_last`) | half-tile piece at the target end |
| `start` | `wp-tesla-beam-start.png` | — | small spark burst at the shooter |
| `ending` | `wp-tesla-beam-ending.png` | — | larger spark burst at the target |

If the pieces don't meet cleanly at the corners in-game, the head and tail are the wrong way round. Set `swap_beam_ends = true` in `data.lua`.

### Sprites

All sprites are on a black background and drawn with `blend_mode = "additive"` and `draw_as_glow = true`. Black adds nothing, and the bolt glows on top of the terrain, even at night. They are high-res and drawn at `scale = 0.5`.

| File | Frame size | Layout | In-game size |
|---|---|---|---|
| `wp-tesla-beam-body.png` | 64×128 | 8 frames × 6 rows (one row per variation) | 1 × 2 tiles |
| `wp-tesla-beam-source-end.png` | 32×128 | 8 frames × 1 row | 0.5 × 2 tiles |
| `wp-tesla-beam-target-end.png` | 32×128 | 8 frames × 1 row | 0.5 × 2 tiles |
| `wp-tesla-branch-body.png` | 64×128 | 8 frames × 4 rows | 1 × 2 tiles |
| `wp-tesla-branch-source-end.png` | 32×128 | 8 frames × 1 row | 0.5 × 2 tiles |
| `wp-tesla-branch-target-end.png` | 32×128 | 8 frames × 1 row | 0.5 × 2 tiles |
| `wp-tesla-branch-tip.png` | 32×128 | 8 frames × 1 row | 0.5 × 2 tiles |
| `wp-tesla-beam-start.png` | 96×96 | 8 frames × 1 row | 1.5 × 1.5 tiles |
| `wp-tesla-beam-ending.png` | 96×96 | 8 frames × 1 row | 1.5 × 1.5 tiles |

**Shared anchors: why the pieces always connect.** Factorio requires every animation in a beam to have the same frame count (8 here), and it plays the same frame number on every piece of a beam at the same time. Each frame number *k* has one **anchor height** shared by every body variation and both end pieces. Every body frame *k* enters and exits at that height, so neighboring body pieces always join up while the whole bolt jumps up and down from frame to frame (up to ±16 px, ±0.25 tile in-game). Consecutive frames' anchors are forced well apart so the jump is visible.

**End pieces** join the body at the anchor height on their inner edge and pinch to dead center on their outer edge. That makes every path piece start and end exactly on its waypoint, so pieces meet at the corners. The branch **tip** joins the body the same way but fades to nothing toward its outer edge.

**Inside each frame:**
- A bright white core over two blue glow layers: a tight inner glow (blur 1.2 px, strength 1.3) and a modest outer one (blur 3.5 px, strength 1.1), kept small so many overlapping bolts stay readable.
- 2–4 forks per body frame, each 30–55% of the frame height long, that branch and split again and fade out before they reach a frame edge.
- A 40% chance of a faint second strand that splits off the main bolt and rejoins it.
- A random brightness per frame number (100%, 85% or 65%), so the whole bolt strobes together.

**Branch sprites** use the same anchors, at 60% brightness and 70% line thickness.

### Tuning

**`control.lua`** (visuals only, no effect on balance). Most settings are option tables passed straight to `beamlib.bolt`. These are the **Quality** values; `SHAPE.segment_length`, `SHAPE.max_corners`, `DRAW.piece_length`, `BRANCHES.per_tile` and `MOODS` are swapped for the **Performance** ones when that setting is chosen.

| Setting | Default | Effect |
|---|---|---|
| `SHAPE.segment_length` | `1.6` | Average tiles between corners. Lower means more corners. |
| `SHAPE.jitter` | `1` | Random ± on the corner count for each new shape. `0` turns it off. |
| `SHAPE.max_corners` | `6` | Cap on corners per bolt. |
| `SHAPE.swing` / `SHAPE.max_swing` | `0.3` / `2.5` | Sideways offset of corners: fraction of bolt length, capped in tiles. |
| `SHAPE.bow` | `0.35` | How far an arc span bulges, as a fraction of its length. |
| `DRAW.style` | `"arc"` | `"arc"`, `"smooth"` or `"straight"`. |
| `DRAW.piece_length` | `1.0` | Length of the straight pieces that make up a curve, in tiles. Higher means fewer pieces and blockier curves. |
| `BRANCHES.per_tile` | `0.3` | Average branches per tile of bolt. `0` turns branches off. |
| `BRANCHES.max` | `5` | Cap on branches per bolt. |
| `BRANCHES.length` | `{1.0, 3.5}` | Branch length range, in tiles. |
| `BRANCHES.angle` | `{0.35, 1.25}` | How far branches turn away from the bolt, in radians. |
| `BRANCHES.sub_chance` | `0.35` | Chance a branch grows a smaller branch. |
| `BRANCHES.segment_length` | `1.2` | Average tiles between corners on a branch. |
| `BRANCHES.swap_chance` | `0.3` | On a twitch, chance one branch is replaced by a new one. |
| `IRREGULAR` | `true` | `false` = new shape every `FIXED_INTERVAL` ticks at normal speed. |
| `FIXED_INTERVAL` | `6` | Redraw rate when `IRREGULAR` is off. |
| `MOODS` | see [moods](#visual-layer-timing-and-moods) | Interval range, new-shape chance, flicker speed, weight and stay chance per mood. |
| `TWITCH.along` / `.side` / `.bow` / `.angle` | `0.04` / `0.3` / `0.1` / `0.2` | How far a twitch nudges corners (along, sideways), bows and branch angles. |
| `PRESETS` | quality / performance | The values the map setting switches between. Quality copies the defaults above. |
| `COLORFUL` | `true` | `false` = every bolt bright white. |
| `HUE_WEIGHTS` | white 4, ice 3, blue 2, violet 2 | How often each tint is picked. |
| `DIM_CHANCE` | main 0.15, jump 0.6 | Chance a bolt uses the dim version. |
| `HUE_SHIFT_CHANCE` | `0.15` | Chance a bolt changes hue when it gets a brand-new shape. |
| `MAIN_DURATION` / `JUMP_DURATION` | `60` / `30` | How long bolts are drawn, in ticks. These match the damage beams. |
| `MAX_JUMP` | `9.5` | Farthest a chain jump can reach, used when checking jump sources. Pieces get `max_length = MAX_JUMP × 3`. |
| `SHOOTER_OFFSET` | `{0, -1.3}` | Where the main bolt leaves the character. |
| `MAX_ZAPS` | `200` | Safety cap on bolts being drawn at once. |

**`data.lua`:**

| Setting | Default | Effect |
|---|---|---|
| `speeds` | `slow = 0.1`, `normal = 0.2`, `fast = 0.4` | Sprite frames per tick for each speed version, passed to `make_path_beam_variants`. |
| `tint_colors` | see [colour and depth](#visual-layer-colour-and-depth) | The four tints, passed to `make_path_beam_variants`. Adding one here also needs it in `HUE_WEIGHTS`. |
| `dim_strength` | `0.5` | Brightness of the dim versions. |
| `swap_beam_ends` | `false` | Swaps the head and tail sprites if the corners don't line up. |

### Performance

Measured with the in-game time usage display:

| Version | Situation | Script time per tick |
|---|---|---|
| any | Idle | ~0.001 ms |
| 0.3.1 | A dozen or so units firing into a nest | ~0.2 ms |
| 0.4.x, Quality | 15 units fighting a populated biter base | ~0.4–0.5 ms typical, ~1 ms peak with everything chaining at once (6% of the 16.7 ms tick budget) |
| 0.4.x, Performance | 15 units fighting a populated biter base | ~0.2 ms (about 1% of the tick budget) |

Almost all of the cost is creating the visual beams. The **Performance** preset creates about a quarter as many beam pieces as Quality, which cut the peak script time by about 80% in the benchmark above. The colours and depth added in 0.4.2 cost nothing (the measurements were the same before and after), and 0.5.0 creates the same number of pieces as 0.4.2 in simulation. For finer control, the values in `PRESETS` and the tuning block at the top of `control.lua` can be edited directly.

### Regenerating the sprites

The sprites come from `tools/make_lightning.py` (Python 3 with `numpy`, `Pillow` and `scipy`). The game doesn't need this folder.

```sh
cd tools
python3 make_lightning.py        # default seed
python3 make_lightning.py 42     # a different batch of bolts
```

It writes all nine sprite sheets plus `preview.gif`, a straight test piece played at normal speed. Copy the PNGs into `graphics/entity/`. Frame sizes, frame count, anchor range, fork length, strand chance, branch brightness and thickness, glow size and strength (`GLOW_INNER`, `GLOW_OUTER`), and colors are constants at the top of the script. If you change the frame count, variation counts or frame sizes, update `beam_frames`, `sprite_sets` and `body_width`/`end_width`/`beam_height` in `data.lua` to match.

## Requirements

- Factorio **2.1**
- `base`
- [`WePlayBeamLib`](https://mods.factorio.com/mod/WePlayBeamLib) 0.16.0 or later
- `space-age` *(optional)*

## Installation

**Mod portal:** Search for *WePlay: Personal Tesla Defense Equipment* in the in-game mod browser. The Beam Library is installed along with it.

**Manual:**
1. Download the latest release zip.
2. Put it and the [WePlay Beam Library](https://mods.factorio.com/mod/WePlayBeamLib) zip in your Factorio `mods` folder without extracting them:
   - Windows: `%APPDATA%\Factorio\mods`
   - Linux: `~/.factorio/mods`
   - macOS: `~/Library/Application Support/factorio/mods`
3. Enable the mod in the in-game Mods menu.

## Changelog

See [changelog.txt](changelog.txt).

## Credits

Made by **WePlay**.
