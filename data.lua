local item_sounds = require("__base__.prototypes.item_sounds")
local beamdata = require("__WePlayBeamLib__/datalib")

local space_age = mods["space-age"] ~= nil

---------------------------------------------------------------------------------------------------
-- Attack effects
--
-- Damage and the visuals are split:
--   * The chain and the damage beams are real prototypes, so damage, jumps and research bonuses
--     work exactly like any other weapon. The damage beams are invisible.
--   * Each hit also fires a script trigger. control.lua then draws the lightning with the WePlay
--     Beam Library: a jagged path of short visual-only beam pieces from waypoint to waypoint, with
--     dead-end branches sprouting off it, redrawn at irregular intervals while the zap lasts.
---------------------------------------------------------------------------------------------------
local gfx = "__WePlayTeslaEquipment__/graphics/entity/"

-- Every animation in one beam must have the same number of frames.
-- Frame k of every body variation enters and exits at the same height, so the segments always
-- join up while the bolt jumps around from frame to frame. The two end pieces join the body at
-- that height and pinch to dead centre at the waypoints, so neighbouring path pieces connect.
local beam_frames = 8
local beam_height = 128
local body_width, end_width = 64, 32

-- Main bolt and branch (dead-end offshoot) sprite sets.
local sprite_sets =
{
  beam = {variations = 6, prefix = "wp-tesla-beam-"},
  branch = {variations = 4, prefix = "wp-tesla-branch-"}
}

-- Every visual beam comes in three animation speeds (frames advanced per tick). control.lua picks
-- one each time it redraws a bolt, so the flicker speeds up and slows down instead of ticking
-- along like a flip book. 0.1 = a new frame every 10 ticks, 0.4 = one every 2.5 ticks.
local speeds = {slow = 0.1, normal = 0.2, fast = 0.4}

-- If the path pieces visibly fail to meet at their corners, the head/tail ends are the other way
-- round from what we assumed: flip this.
local swap_beam_ends = false

-- Bolt colours. Each visual beam exists in every tint, bright and dim. Bolts pick one each, so
-- overlapping bolts mix hues instead of all adding up to the same flat white, and dim bolts sit
-- "behind" bright ones for depth. Tinting reuses the same sprite sheets (no extra VRAM).
local tint_colors =
{
  white  = {r = 1.0,  g = 1.0,  b = 1.0},
  ice    = {r = 0.65, g = 0.95, b = 1.0},
  blue   = {r = 0.45, g = 0.62, b = 1.0},
  violet = {r = 0.78, g = 0.55, b = 1.0},
}
local dim_strength = 0.5 -- dim versions are this bright

local tints = {}
for name, c in pairs(tint_colors) do
  tints[name] = {r = c.r, g = c.g, b = c.b, a = 1}
  tints[name .. "-dim"] = {r = c.r * dim_strength, g = c.g * dim_strength, b = c.b * dim_strength, a = 1}
end

-- Untinted, speed-less animation; the library's variants add tint and animation_speed.
local function animation(file, width, height, y)
  return
  {
    filename = gfx .. file,
    width = width,
    height = height,
    y = y or 0,
    frame_count = beam_frames,
    line_length = beam_frames,
    scale = 0.5,
    blend_mode = "additive",
    draw_as_glow = true,
    priority = "extra-high"
  }
end

local function sprite_set(set)
  local info = sprite_sets[set]
  local body = {}
  for row = 0, info.variations - 1 do
    table.insert(body, animation(info.prefix .. "body.png", body_width, beam_height, row * beam_height))
  end
  local head = animation(info.prefix .. "source-end.png", end_width, beam_height)
  local tail = animation(info.prefix .. "target-end.png", end_width, beam_height)
  if swap_beam_ends then head, tail = tail, head end
  return head, body, tail
end

-- Visual-only beam pieces, built by the library: every tint and speed, each in the four
-- path positions (first / middle / last / single), named like "wp-tesla-arc-violet-dim-fast-first".
-- Main bolt: spark bursts at the shooter (first/single) and the target (last/single).
local arc_head, arc_body, arc_tail = sprite_set("beam")
beamdata.make_path_beam_variants{
  name = "wp-tesla-arc",
  head = arc_head,
  body = arc_body,
  tail = arc_tail,
  start = animation("wp-tesla-beam-start.png", 96, 96),
  ending = animation("wp-tesla-beam-ending.png", 96, 96),
  tints = tints,
  speeds = speeds
}

-- Branches: dimmer, thinner sprites, no sparks, and the last piece fades out instead of pinching.
local branch_head, branch_body, branch_tail = sprite_set("branch")
beamdata.make_path_beam_variants{
  name = "wp-tesla-branch",
  head = branch_head,
  body = branch_body,
  tail = branch_tail,
  tail_last = animation("wp-tesla-branch-tip.png", end_width, beam_height),
  tints = tints,
  speeds = speeds
}

local damage_beam =
{
  type = "beam",
  name = "wp-tesla-equipment-beam",
  flags = {"not-on-map"},
  hidden = true,
  width = 0.5,
  damage_interval = 20,
  graphics_set = beamdata.invisible_beam_graphics(),
  action =
  {
    type = "direct",
    action_delivery =
    {
      type = "instant",
      target_effects =
      {
        {type = "damage", damage = {amount = 40, type = "electric"}}
      }
    }
  }
}

local chain =
{
  type = "chain-active-trigger",
  name = "wp-tesla-equipment-chain",
  max_jumps = 6,
  max_range_per_jump = 8,
  jump_delay_ticks = 6,
  fork_chance = 0.25,
  action =
  {
    -- Tell control.lua about the jump first, so it can draw the bolt.
    {
      type = "direct",
      action_delivery =
      {
        type = "instant",
        target_effects = {{type = "script", effect_id = "wp-tesla-zap-jump"}}
      }
    },
    {
      type = "direct",
      action_delivery =
      {
        type = "beam",
        beam = "wp-tesla-equipment-beam",
        max_length = 9,
        duration = 30,
        add_to_shooter = false,
        destroy_with_source_or_target = false
      }
    }
  }
}

data:extend({damage_beam, chain})

-- Tesla weapon research with Space Age, laser weapon research without it.
local ammo_category = space_age and "tesla" or "laser"
local chain_name = "wp-tesla-equipment-chain"
local beam_name = "wp-tesla-equipment-beam"

---------------------------------------------------------------------------------------------------
-- Equipment + item
---------------------------------------------------------------------------------------------------
data:extend({
  {
    type = "active-defense-equipment",
    name = "wp-personal-tesla-defense-equipment",
    sprite =
    {
      filename = "__WePlayTeslaEquipment__/graphics/icon/wp-personal-tesla-equipment.png",
      width = 128,
      height = 128,
      priority = "medium",
      scale = 0.5
    },
    shape =
    {
      width = 2,
      height = 2,
      type = "full"
    },
    energy_source =
    {
      type = "electric",
      usage_priority = "secondary-input",
      buffer_capacity = "1MJ"
    },

    attack_parameters =
    {
      type = "beam",
      cooldown = 60,
      range = 20,
      range_mode = "center-to-bounding-box",
      fire_penalty = 0.9,
      damage_modifier = 1.1,
      source_direction_count = 64,
      source_offset = {0, -0.55},
      ammo_category = ammo_category,
      ammo_type =
      {
        energy_consumption = "110kJ",
        action =
        {
          type = "direct",
          action_delivery =
          {
            type = "instant",
            target_effects =
            {
              -- Script first so control.lua knows about this hit before any chain jumps from it
              {type = "script", effect_id = "wp-tesla-zap"},
              -- Chain effect must go before the beam in case the beam kills the target
              {
                type = "nested-result",
                action =
                {
                  type = "direct",
                  action_delivery =
                  {
                    type = "chain",
                    chain = chain_name,
                  }
                }
              },
              {
                type = "nested-result",
                action =
                {
                  type = "direct",
                  action_delivery =
                  {
                    type = "beam",
                    beam = beam_name,
                    max_length = 20,
                    duration = 60,
                    add_to_shooter = false,
                    destroy_with_source_or_target = false,
                    source_offset = {0, -1.55}
                  }
                }
              }
            }
          }
        }
      }
    },

    automatic = true,
    categories = {"armor"}
  },
  {
    type = "item",
    name = "wp-personal-tesla-defense-equipment",
    icon = "__WePlayTeslaEquipment__/graphics/icon/wp-personal-tesla-equipment.png",
    icon_size = 128,
    place_as_equipment_result = "wp-personal-tesla-defense-equipment",
    subgroup = "military-equipment",
    order = "b[active-defense]-z[personal-laser-defense-equipment]",
    inventory_move_sound = item_sounds.turret_inventory_move,
    pick_sound = item_sounds.turret_inventory_pickup,
    drop_sound = item_sounds.turret_inventory_move,
    stack_size = 20,
    weight = 200*kg
  }
})

---------------------------------------------------------------------------------------------------
-- Recipe
---------------------------------------------------------------------------------------------------
local recipe =
{
  type = "recipe",
  name = "wp-personal-tesla-defense-equipment",
  subgroup = "equipment",
  order = "zz",
  energy_required = 20,
  results = {
    {type = "item", name = "wp-personal-tesla-defense-equipment", amount = 1}
  },
  enabled = false
}

if space_age then
  recipe.categories = {"electromagnetics"}
  recipe.ingredients = {
    { type = "item", name = "processing-unit", amount = 1},
    { type = "item", name = "low-density-structure", amount = 2},
    { type = "item", name = "battery", amount = 4},
    { type = "item", name = "superconductor", amount = 1},
    { type = "item", name = "teslagun", amount = 1}
  }
else
  -- No category set: uses the default "crafting" category, so it works in any assembler or by hand.
  recipe.ingredients = {
    { type = "item", name = "processing-unit", amount = 5},
    { type = "item", name = "low-density-structure", amount = 5},
    { type = "item", name = "battery", amount = 10},
    { type = "item", name = "personal-laser-defense-equipment", amount = 1}
  }
end

data:extend({recipe})

---------------------------------------------------------------------------------------------------
-- Technology unlock
---------------------------------------------------------------------------------------------------
local function add_unlock(tech)
  tech.effects = tech.effects or {}
  table.insert(tech.effects, {type = "unlock-recipe", recipe = "wp-personal-tesla-defense-equipment"})
end

local function find_tech_unlocking(recipe_name)
  for _, tech in pairs(data.raw["technology"]) do
    for _, effect in pairs(tech.effects or {}) do
      if effect.type == "unlock-recipe" and effect.recipe == recipe_name then
        return tech
      end
    end
  end
end

local unlock_tech
if space_age then
  unlock_tech = data.raw["technology"]["tesla-weapons"]
end
-- Fallback: whatever tech unlocks personal laser defense (works with overhaul mods that move it)
unlock_tech = unlock_tech or find_tech_unlocking("personal-laser-defense-equipment")

if unlock_tech then
  add_unlock(unlock_tech)
else
  -- No suitable tech found: just make the recipe available from the start
  data.raw["recipe"]["wp-personal-tesla-defense-equipment"].enabled = true
end
