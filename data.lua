local item_sounds = require("__base__.prototypes.item_sounds")

local space_age = mods["space-age"] ~= nil

---------------------------------------------------------------------------------------------------
-- Attack effects
--
-- Damage and the visuals are split:
--   * The chain and the damage beams are real prototypes, so damage, jumps and research bonuses
--     work exactly like any other weapon. The damage beams are invisible.
--   * Each hit also fires a script trigger. control.lua then draws the lightning as a jagged path
--     of short visual-only "arc" beams from waypoint to waypoint, re-rolling it every few ticks.
---------------------------------------------------------------------------------------------------
local gfx = "__WePlayTeslaEquipment__/graphics/entity/"

-- Every animation in one beam must have the same number of frames.
-- Frame k of every body variation enters and exits at the same height, so the segments always
-- join up while the bolt jumps around from frame to frame. The two end pieces join the body at
-- that height and pinch to dead centre at the waypoints, so neighbouring path pieces connect.
local beam_frames = 8
local beam_variations = 6
local body_width, end_width, beam_height = 64, 32, 96

-- Frames advanced per tick: 0.2 = a new frame every 5 ticks (12 per second).
local beam_animation_speed = 0.2

-- If the path pieces visibly fail to meet at their corners, the head/tail ends are the other way
-- round from what we assumed: flip this.
local swap_beam_ends = false

local function beam_animation(file, width, height, y)
  return
  {
    filename = gfx .. file,
    width = width,
    height = height,
    y = y or 0,
    frame_count = beam_frames,
    line_length = beam_frames,
    scale = 0.5,
    animation_speed = beam_animation_speed,
    blend_mode = "additive",
    draw_as_glow = true,
    priority = "extra-high"
  }
end

-- with_start / with_ending: spark bursts only at the shooter and the target, not at every corner.
local function lightning_graphics(with_start, with_ending)
  local body = {}
  for row = 0, beam_variations - 1 do
    table.insert(body, beam_animation("wp-tesla-beam-body.png", body_width, beam_height, row * beam_height))
  end
  local source_end = beam_animation("wp-tesla-beam-source-end.png", end_width, beam_height)
  local target_end = beam_animation("wp-tesla-beam-target-end.png", end_width, beam_height)
  if swap_beam_ends then
    source_end, target_end = target_end, source_end
  end
  return
  {
    beam =
    {
      start = with_start and beam_animation("wp-tesla-beam-start.png", 96, 96) or nil,
      ending = with_ending and beam_animation("wp-tesla-beam-ending.png", 96, 96) or nil,
      head = source_end,
      tail = target_end,
      body = body
    }
  }
end

-- Visual-only path pieces. control.lua picks the variant by where the piece sits in the path.
local function arc(name, with_start, with_ending)
  return
  {
    type = "beam",
    name = name,
    flags = {"not-on-map"},
    hidden = true,
    width = 0.5,
    damage_interval = 1000000, -- never deals damage: it has no action
    graphics_set = lightning_graphics(with_start, with_ending)
  }
end

-- Invisible graphics for the damage beams.
local empty = {filename = "__core__/graphics/empty.png", width = 1, height = 1, frame_count = 1}

local damage_beam =
{
  type = "beam",
  name = "wp-tesla-equipment-beam",
  flags = {"not-on-map"},
  hidden = true,
  width = 0.5,
  damage_interval = 20,
  graphics_set = {beam = {head = empty, tail = empty, body = {empty}}},
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

data:extend({
  damage_beam,
  chain,
  arc("wp-tesla-arc", false, false),
  arc("wp-tesla-arc-first", true, false),
  arc("wp-tesla-arc-last", false, true),
  arc("wp-tesla-arc-single", true, true)
})

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
