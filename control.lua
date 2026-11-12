---------------------------------------------------------------------------------------------------
-- Lightning visuals
--
-- The real damage beams are invisible (see data.lua). Every hit fires a script trigger, and here we
-- draw the bolt as a jagged path: a few random waypoints between the two ends, joined by short
-- visual-only "arc" beams. While the zap lasts, the path is thrown away and re-rolled every few
-- ticks, and it follows its ends if they move.
---------------------------------------------------------------------------------------------------

-- Tuning ------------------------------------------------------------------------------------------
local REPATH_TICKS = 6       -- re-roll the path this often; 0 = path stays put for the whole zap
local SEGMENT_LENGTH = 1.6   -- average distance between corners, in tiles
local CORNER_JITTER = 1      -- the number of corners varies by up to this much each time
local MAX_WAYPOINTS = 6      -- cap on corners per bolt
local CURVE = "arc"          -- "arc": each span bows out, sharp kinks at corners
                             -- "smooth": one flowing curve through all corners
                             -- "straight": straight lines between corners (v0.3.0 look)
local BOW = 0.35             -- how far an "arc" span bulges, as a fraction of its length
local PIECE_LENGTH = 1.0     -- curves are drawn as straight pieces about this long, in tiles
local SWING = 0.3            -- max sideways offset of a corner, as a fraction of the bolt's length
local MAX_SWING = 2.5        -- ...but never more than this many tiles
local MAIN_DURATION = 60     -- ticks: shooter -> first target (matches the damage beam)
local JUMP_DURATION = 30     -- ticks: each chain jump (matches the damage beam)
local MAX_JUMP = 9.5         -- tiles: farthest a chain jump can reach (chain range + a margin)
local SHOOTER_OFFSET = {x = 0, y = -1.3} -- bolt leaves from around the character's shoulders
local MAX_ZAPS = 200         -- safety cap on bolts being drawn at once
-----------------------------------------------------------------------------------------------------

local ARC = "wp-tesla-arc"
local ARC_FIRST = "wp-tesla-arc-first"
local ARC_LAST = "wp-tesla-arc-last"
local ARC_SINGLE = "wp-tesla-arc-single"

local function init_storage()
  storage.zaps = storage.zaps or {}
  storage.recent = storage.recent or {}
end

local function copy_pos(p)
  return {x = p.x or p[1], y = p.y or p[2]}
end

local function dist(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
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

-- Corners of the bolt: a, corner, corner, ..., b.
local function make_corners(a, b, d)
  local corners = math.floor(d / SEGMENT_LENGTH) - 1
  if CORNER_JITTER > 0 then corners = corners + math.random(-CORNER_JITTER, CORNER_JITTER) end
  corners = math.min(MAX_WAYPOINTS, math.max(0, corners))
  local points = {a}
  if corners > 0 then
    local dx, dy = (b.x - a.x) / d, (b.y - a.y) / d
    local nx, ny = -dy, dx
    local swing = math.min(d * SWING, MAX_SWING)
    local step = 1 / (corners + 1)
    for i = 1, corners do
      local t = step * i + (math.random() - 0.5) * step * 0.6
      local s = (math.random() * 2 - 1) * swing
      table.insert(points, {x = a.x + (b.x - a.x) * t + nx * s, y = a.y + (b.y - a.y) * t + ny * s})
    end
  end
  table.insert(points, b)
  return points
end

local function pieces_for(length)
  return math.max(1, math.floor(length / PIECE_LENGTH + 0.5))
end

-- "arc": bow each span between corners into a curve (quadratic Bezier, random side).
local function arc_path(corners)
  local out = {corners[1]}
  for i = 1, #corners - 1 do
    local p, q = corners[i], corners[i + 1]
    local len = dist(p, q)
    local n = pieces_for(len)
    if n == 1 then
      table.insert(out, q)
    else
      local bow = (math.random() * 2 - 1) * BOW * len
      local cx = (p.x + q.x) / 2 - (q.y - p.y) / len * bow
      local cy = (p.y + q.y) / 2 + (q.x - p.x) / len * bow
      for k = 1, n do
        local t = k / n
        local u = 1 - t
        table.insert(out, {
          x = u * u * p.x + 2 * u * t * cx + t * t * q.x,
          y = u * u * p.y + 2 * u * t * cy + t * t * q.y
        })
      end
    end
  end
  return out
end

-- "smooth": Catmull-Rom spline through every corner.
local function smooth_path(corners)
  local out = {corners[1]}
  local count = #corners
  for i = 1, count - 1 do
    local p0 = corners[math.max(1, i - 1)]
    local p1, p2 = corners[i], corners[i + 1]
    local p3 = corners[math.min(count, i + 2)]
    local n = pieces_for(dist(p1, p2))
    for k = 1, n do
      local t = k / n
      local t2, t3 = t * t, t * t * t
      local function axis(c)
        return 0.5 * (2 * p1[c] + (p2[c] - p0[c]) * t
          + (2 * p0[c] - 5 * p1[c] + 4 * p2[c] - p3[c]) * t2
          + (3 * p1[c] - p0[c] - 3 * p2[c] + p3[c]) * t3)
      end
      table.insert(out, {x = axis("x"), y = axis("y")})
    end
  end
  return out
end

local function make_path(a, b)
  local corners = make_corners(a, b, dist(a, b))
  if CURVE == "arc" then return arc_path(corners) end
  if CURVE == "smooth" then return smooth_path(corners) end
  return corners
end

local function draw(zap, tick)
  local surface = game.get_surface(zap.surface)
  if not surface then return false end
  local a = end_position(zap, "source", "source_pos", zap.offset)
  local b = end_position(zap, "target", "target_pos")
  if not a or not b or dist(a, b) < 0.3 then return true end

  local remaining = zap.expires - tick
  if remaining <= 0 then return false end
  local duration = remaining
  if REPATH_TICKS > 0 then duration = math.min(REPATH_TICKS, remaining) end

  local points = make_path(a, b)
  local last = #points - 1
  for i = 1, last do
    local name = ARC
    if last == 1 then
      name = ARC_SINGLE
    elseif i == 1 then
      name = ARC_FIRST
    elseif i == last then
      name = ARC_LAST
    end
    surface.create_entity{
      name = name,
      position = points[i],
      source_position = points[i],
      target_position = points[i + 1],
      duration = duration,
      max_length = MAX_JUMP * 3
    }
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
    local d = dist(s.position, target_pos)
    if d > 0.3 and d <= MAX_JUMP then
      return s, copy_pos(s.position)
    end
  end
  local best, best_d
  for _, hit in pairs(storage.recent[event.surface_index] or {}) do
    if tick - hit.tick <= 45 then
      local d = dist(hit, target_pos)
      if d > 0.3 and d <= MAX_JUMP and (not best_d or d < best_d) then
        best, best_d = hit, d
      end
    end
  end
  if best then return nil, {x = best.x, y = best.y} end
end

local function add_zap(zap, tick)
  if #storage.zaps >= MAX_ZAPS then return end
  zap.next_draw = tick + REPATH_TICKS
  if draw(zap, tick) and REPATH_TICKS > 0 then
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
  local target_pos = target and copy_pos(target.position)
    or (event.target_position and copy_pos(event.target_position))
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
      source_pos = copy_pos(event.source_position)
    end
    duration = MAIN_DURATION
  else
    source, source_pos = find_jump_source(event, target_pos, tick)
    duration = JUMP_DURATION
  end

  remember_hit(event.surface_index, target_pos, tick)
  if not source_pos then return end

  add_zap({
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
      zap.next_draw = tick + REPATH_TICKS
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

script.on_init(init_storage)
script.on_configuration_changed(init_storage)
script.on_event(defines.events.on_script_trigger_effect, on_script_trigger_effect)
script.on_event(defines.events.on_tick, on_tick)
