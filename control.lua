---------------------------------------------------------------------------------------------------
-- Lightning visuals
--
-- The real damage beams are invisible (see data.lua). Every hit fires a script trigger, and here we
-- draw the bolt with the WePlay Beam Library (beamlib.bolt + beamlib.arcs): a few random corners
-- between the two ends, each span bowed into an arc, drawn as short visual-only beam pieces, with
-- dead-end branches sprouting off the path.
--
-- Each zap keeps a shape (corners, bows, branches) measured relative to its two ends, so it follows
-- them as they move. While the zap lasts it is redrawn at irregular intervals driven by a "mood":
--   frantic: redraws every few ticks with a brand-new shape and fast flicker
--   normal:  medium pace, mostly new shapes, sometimes just a twitch
--   calm:    holds its shape for a while, only twitching it, with slow flicker
-- and the mood changes at random, so a bolt thrashes, settles, then thrashes again.
--
-- What stays here is Tesla-specific: the triggers, finding chain-jump sources, colours, the
-- quality setting and the list of live zaps.
---------------------------------------------------------------------------------------------------

local beamlib = require("__WePlayBeamLib__/beamlib")
local bolt, arcs, V = beamlib.bolt, beamlib.arcs, beamlib.vec

-- Tuning ------------------------------------------------------------------------------------------
-- Path shape (beamlib.bolt.new_shape options)
local SHAPE =
{
  segment_length = 1.6,      -- average distance between corners, in tiles
  jitter = 1,                -- the number of corners varies by up to this much each time
  max_corners = 6,           -- cap on corners per bolt
  swing = 0.3,               -- max sideways offset of a corner, as a fraction of the bolt's length
  max_swing = 2.5,           -- ...but never more than this many tiles
  bow = 0.35,                -- how far an "arc" span bulges, as a fraction of its length
}
-- How the path is drawn (beamlib.bolt.points options)
local DRAW =
{
  style = "arc",             -- "arc": each span bows out, sharp kinks at corners
                             -- "smooth": one flowing curve through all corners
                             -- "straight": straight lines between corners
  piece_length = 1.0,        -- curves are drawn as straight pieces about this long, in tiles
}

-- Branches: dead-end offshoots (beamlib.bolt branch options)
local BRANCHES =
{
  per_tile = 0.3,            -- average branches per tile of bolt
  max = 5,                   -- cap on branches per bolt
  length = {1.0, 3.5},       -- tiles
  angle = {0.35, 1.25},      -- radians away from the bolt's direction, either side
  sub_chance = 0.35,         -- chance a branch grows a smaller branch of its own
  segment_length = 1.2,      -- average distance between corners on a branch
  swap_chance = 0.3,         -- on a twitch, chance one branch is replaced by a new one
}

-- Timing
local IRREGULAR = true       -- false = redraw every FIXED_INTERVAL ticks with a new shape (v0.3 feel)
local FIXED_INTERVAL = 6
-- interval = random ticks between redraws, reroll = chance of a brand-new shape (otherwise twitch),
-- speed = sprite flicker speed (matches the prototype names from data.lua), weight = how likely
-- the mood is chosen, stay = chance of keeping the mood at each redraw.
local MOODS =
{
  frantic = {interval = {2, 4},  reroll = 0.9,  speed = "fast",   weight = 3, stay = 0.6},
  normal  = {interval = {4, 8},  reroll = 0.65, speed = "normal", weight = 4, stay = 0.6},
  calm    = {interval = {8, 16}, reroll = 0.15, speed = "slow",   weight = 3, stay = 0.5},
}
-- How far a twitch moves things (beamlib.bolt.twitch options).
local TWITCH =
{
  along = 0.04,              -- corner position along the bolt (fraction)
  side = 0.3,                -- corner sideways offset (tiles)
  bow = 0.1,                 -- span bow (fraction of span length)
  angle = 0.2,               -- branch angle (radians)
}

-- Colour and depth
local COLORFUL = true        -- false = every bolt bright white (the pre-0.4.2 look)
local HUE_WEIGHTS = {white = 4, ice = 3, blue = 2, violet = 2} -- how often each tint is picked
local DIM_CHANCE = {main = 0.15, jump = 0.6} -- chance a bolt is dim (sits "behind" the bright ones)
local HUE_SHIFT_CHANCE = 0.15 -- on a brand-new shape, chance the bolt also changes hue

-- Zaps
local MAIN_DURATION = 60     -- ticks: shooter -> first target (matches the damage beam)
local JUMP_DURATION = 30     -- ticks: each chain jump (matches the damage beam)
local MAX_JUMP = 9.5         -- tiles: farthest a chain jump can reach (chain range + a margin)
local SHOOTER_OFFSET = {x = 0, y = -1.3} -- bolt leaves from around the character's shoulders
local MAX_ZAPS = 200         -- safety cap on bolts being drawn at once
-----------------------------------------------------------------------------------------------------

-- Presets for the "Lightning visuals" map setting -------------------------------------------------
-- Quality is the tuning above. Performance draws fewer, longer pieces, no branches, and redraws less
-- often. Each preset lists the values it uses for these settings.
local SETTING = "wp-tesla-lightning-quality"
local PRESETS =
{
  quality =
  {
    segment_length = SHAPE.segment_length,
    max_corners = SHAPE.max_corners,
    piece_length = DRAW.piece_length,
    branches_per_tile = BRANCHES.per_tile,
    moods = MOODS
  },
  performance =
  {
    segment_length = 2.0,
    max_corners = 4,
    piece_length = 1.5,
    branches_per_tile = 0,
    moods =
    {
      frantic = {interval = {3, 6},   reroll = 0.9,  speed = "fast",   weight = 3, stay = 0.6},
      normal  = {interval = {6, 10},  reroll = 0.65, speed = "normal", weight = 4, stay = 0.6},
      calm    = {interval = {10, 18}, reroll = 0.15, speed = "slow",   weight = 3, stay = 0.5},
    }
  }
}

local function apply_preset()
  local setting = settings.global[SETTING]
  local preset = PRESETS[setting and setting.value or "quality"] or PRESETS.quality
  SHAPE.segment_length = preset.segment_length
  SHAPE.max_corners = preset.max_corners
  DRAW.piece_length = preset.piece_length
  BRANCHES.per_tile = preset.branches_per_tile
  MOODS = preset.moods
end
-----------------------------------------------------------------------------------------------------

local function init_storage()
  storage.zaps = storage.zaps or {}
  storage.recent = storage.recent or {}
end

-- Current position of one end of a zap. Follows the entity while it's alive, then stays where it
-- last was.
local function end_position(e, entity_key, pos_key, offset)
  local ent = e[entity_key]
  if ent and ent.valid then
    local p = ent.position
    if offset then
      e[pos_key] = {x = p.x + offset.x, y = p.y + offset.y}
    else
      e[pos_key] = {x = p.x, y = p.y}
    end
  end
  return e[pos_key]
end

local function pick_hue()
  local names = {}
  for name in pairs(HUE_WEIGHTS) do names[#names + 1] = name end
  table.sort(names)
  local total = 0
  for _, name in ipairs(names) do total = total + HUE_WEIGHTS[name] end
  local r = math.random() * total
  for _, name in ipairs(names) do
    r = r - HUE_WEIGHTS[name]
    if r <= 0 then return name end
  end
  return "white"
end

-- Tint part of the prototype names, e.g. "violet" or "ice-dim".
local function tint_name(zap)
  if not COLORFUL then return "white" end
  return zap.hue .. (zap.dim and "-dim" or "")
end

local function next_step(zap)
  if not IRREGULAR then return {speed = "normal", interval = FIXED_INTERVAL, reroll = true} end
  return bolt.next_step(zap, MOODS)
end

local function draw(zap, tick)
  local surface = game.get_surface(zap.surface)
  if not surface then return false end
  local remaining = zap.expires - tick
  if remaining <= 0 then return false end

  local a = end_position(zap, "source", "source_pos", zap.offset)
  local b = end_position(zap, "target", "target_pos")
  local step = next_step(zap)
  zap.next_draw = tick + step.interval
  if not a or not b or V.dist(a, b) < 0.3 then return true end

  local d = V.dist(a, b)
  if step.reroll or not zap.shape then
    if zap.shape and math.random() < HUE_SHIFT_CHANCE then zap.hue = pick_hue() end
    zap.shape = bolt.new_shape(d, SHAPE)
    zap.branches = bolt.new_branches(d, BRANCHES)
  else
    bolt.twitch(zap.shape, TWITCH)
    bolt.twitch_branches(zap.branches, BRANCHES, TWITCH)
  end

  -- Prototype names: "wp-tesla-arc-<tint>-<speed>" plus -first / -last / -single from the library.
  local suffix = "-" .. tint_name(zap) .. "-" .. step.speed
  local duration = math.min(step.interval, remaining)
  local points = bolt.points(a, b, zap.shape, DRAW)
  arcs.spawn(surface, "wp-tesla-arc" .. suffix, points, duration, MAX_JUMP * 3)
  for _, branch_points in pairs(bolt.branch_paths(points, zap.branches, DRAW)) do
    arcs.spawn(surface, "wp-tesla-branch" .. suffix, branch_points, duration, MAX_JUMP * 3)
  end
  return true
end

local function remember_hit(surface_index, pos, tick)
  local list = storage.recent[surface_index]
  if not list then
    list = {}
    storage.recent[surface_index] = list
  end
  table.insert(list, {x = pos.x, y = pos.y, tick = tick})
end

-- The trigger system doesn't always report the source we'd expect for a chain jump, so if it looks
-- wrong, use the nearest thing the lightning hit in the last moment instead.
local function find_jump_source(event, target_pos, tick)
  local s = event.source_entity
  if s and s.valid and s ~= event.target_entity and s.type ~= "character" then
    local d = V.dist(s.position, target_pos)
    if d > 0.3 and d <= MAX_JUMP then
      return s, {x = s.position.x, y = s.position.y}
    end
  end
  local best, best_d
  for _, hit in pairs(storage.recent[event.surface_index] or {}) do
    if tick - hit.tick <= 45 then
      local d = V.dist(hit, target_pos)
      if d > 0.3 and d <= MAX_JUMP and (not best_d or d < best_d) then
        best, best_d = hit, d
      end
    end
  end
  if best then return nil, {x = best.x, y = best.y} end
end

local function add_zap(zap, tick)
  if #storage.zaps >= MAX_ZAPS then return end
  if draw(zap, tick) then
    table.insert(storage.zaps, zap)
  end
end

local function on_script_trigger_effect(event)
  local id = event.effect_id
  if id ~= "wp-tesla-zap" and id ~= "wp-tesla-zap-jump" then return end
  init_storage()
  local tick = event.tick

  local target = event.target_entity
  if target and not target.valid then target = nil end
  local target_pos
  if target then
    target_pos = {x = target.position.x, y = target.position.y}
  elseif event.target_position then
    local p = V.pos(event.target_position)
    target_pos = {x = p.x, y = p.y}
  end
  if not target_pos then return end

  local source, source_pos, offset, duration
  if id == "wp-tesla-zap" then
    source = event.source_entity or event.cause_entity
    if source and not source.valid then source = nil end
    if source then
      offset = SHOOTER_OFFSET
      local p = source.position
      source_pos = {x = p.x + offset.x, y = p.y + offset.y}
    elseif event.source_position then
      local p = V.pos(event.source_position)
      source_pos = {x = p.x, y = p.y}
    end
    duration = MAIN_DURATION
  else
    source, source_pos = find_jump_source(event, target_pos, tick)
    duration = JUMP_DURATION
  end

  remember_hit(event.surface_index, target_pos, tick)
  if not source_pos then return end

  local kind = id == "wp-tesla-zap" and "main" or "jump"
  add_zap({
    hue = pick_hue(),
    dim = math.random() < DIM_CHANCE[kind],
    surface = event.surface_index,
    source = source,
    source_pos = source_pos,
    offset = offset,
    target = target,
    target_pos = target_pos,
    expires = tick + duration
  }, tick)
end

local function on_tick(event)
  local zaps = storage.zaps
  if not zaps then return end
  local tick = event.tick
  for i = #zaps, 1, -1 do
    local zap = zaps[i]
    if tick >= zap.expires then
      table.remove(zaps, i)
    elseif tick >= zap.next_draw then
      if not draw(zap, tick) then table.remove(zaps, i) end
    end
  end
  -- Forget old hits.
  for surface_index, list in pairs(storage.recent) do
    for i = #list, 1, -1 do
      if tick - list[i].tick > 45 then table.remove(list, i) end
    end
    if #list == 0 then storage.recent[surface_index] = nil end
  end
end

script.on_init(function()
  init_storage()
  apply_preset()
end)
script.on_load(apply_preset)
script.on_configuration_changed(function()
  init_storage()
  storage.zaps = {} -- bolts from an older version may not match the current shape data
  apply_preset()
end)
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if event.setting == SETTING then apply_preset() end
end)
script.on_event(defines.events.on_script_trigger_effect, on_script_trigger_effect)
script.on_event(defines.events.on_tick, on_tick)
