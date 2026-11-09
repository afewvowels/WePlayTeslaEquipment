local item_sounds = require("__base__.prototypes.item_sounds")

local space_age = mods["space-age"] ~= nil

---------------------------------------------------------------------------------------------------
-- Attack effects
-- With Space Age: the real tesla gun chain + beam.
-- Without it: our own chain lightning built from the base game's electric beam (the destroyer's).
---------------------------------------------------------------------------------------------------
local ammo_category
local chain_name
local beam_name

if space_age then
  ammo_category = "tesla"
  chain_name = "chain-tesla-gun-chain"
  beam_name = "chain-tesla-gun-beam-start"
else
  ammo_category = "laser" -- benefits from the base game's laser weapon damage research

  local base_beam = data.raw["beam"]["electric-beam"] or data.raw["beam"]["laser-beam"]
  local beam = table.deepcopy(base_beam)
  beam.name = "wp-tesla-equipment-beam"
  beam.damage_interval = 20
  beam.action =
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

  data:extend({beam, chain})
  chain_name = "wp-tesla-equipment-chain"
  beam_name = "wp-tesla-equipment-beam"
end

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
              -- Chain effect must go first in case the beam kills the target
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
