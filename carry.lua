-- A section of the base moved as it is: picked up (its entities, kept as a list), its targets worked out (a print
-- built where the player dropped it, or a shift and turn), then moved in one tick: cloned to a staging surface, the
-- originals gone, each target checked against the base round it, then cloned to its target (or back, when one is
-- blocked). Clones keep what's in them: items, belt contents, fluids, recipes and progress; wires within the section
-- are kept, poles that had power from outside are joined to the nearest pole there again.
local M = {}

local SCRATCH = "carry-scratch"  -- (prints built here to see where each entity lands)
local STAGE = "carry-stage"      -- (the section while it moves)
-- what doesn't move: the player and vehicles, robots, trains, proxies and ghosts
local SKIP = {
  ["character"] = true, ["car"] = true, ["spider-vehicle"] = true, ["spider-leg"] = true,
  ["locomotive"] = true, ["cargo-wagon"] = true, ["fluid-wagon"] = true, ["artillery-wagon"] = true,
  ["construction-robot"] = true, ["logistic-robot"] = true, ["combat-robot"] = true, ["capture-robot"] = true,
  ["item-request-proxy"] = true, ["entity-ghost"] = true, ["tile-ghost"] = true, ["item-entity"] = true,
  ["deconstructible-tile-proxy"] = true, ["character-corpse"] = true, ["corpse"] = true, ["rail-remnants"] = true,
  ["projectile"] = true, ["stream"] = true, ["fire"] = true, ["sticker"] = true, ["smoke-with-trigger"] = true,
  ["particle-source"] = true, ["highlight-box"] = true, ["speech-bubble"] = true, ["flying-text"] = true,
}
local RAILS = {
  ["straight-rail"] = true, ["curved-rail-a"] = true, ["curved-rail-b"] = true, ["half-diagonal-rail"] = true,
  ["legacy-straight-rail"] = true, ["legacy-curved-rail"] = true, ["elevated-straight-rail"] = true,
  ["elevated-curved-rail-a"] = true, ["elevated-curved-rail-b"] = true, ["elevated-half-diagonal-rail"] = true,
  ["rail-ramp"] = true, ["rail-support"] = true, ["rail-signal"] = true, ["rail-chain-signal"] = true,
}
M.RAILS = RAILS
-- what a shift-click drop clears out of the way (as the game's shift-paste marks them): trees, rocks, cliffs
local OBSTACLES = { ["tree"] = true, ["simple-entity"] = true, ["cliff"] = true }
local function obstacle(o) return OBSTACLES[o.type] and o.force.name == "neutral" end

local function key(name, p) return string.format("%s|%.2f|%.2f", name, p.x, p.y) end

--- a hidden surface of its own, ground laid round `box` ({x1, y1, x2, y2}) as needed
local function hidden(name, box)
  local s = game.get_surface(name)
  if not s then
    s = game.create_surface(name, {
      default_enable_all_autoplace_controls = false,
      autoplace_settings = {
        entity = { treat_missing_as_default = false, settings = {} },
        decorative = { treat_missing_as_default = false, settings = {} },
        tile = { treat_missing_as_default = false, settings = {} },
      },
      no_enemies_mode = true,
      peaceful_mode = true,
    })
    for _, f in pairs(game.forces) do pcall(f.set_surface_hidden, s, true) end
  end
  if box then
    local x1, y1, x2, y2 = math.floor(box[1]) - 2, math.floor(box[2]) - 2, math.ceil(box[3]) + 2, math.ceil(box[4]) + 2
    for cx = math.floor(x1 / 32), math.floor(x2 / 32) do
      for cy = math.floor(y1 / 32), math.floor(y2 / 32) do s.request_to_generate_chunks({ cx * 32 + 16, cy * 32 + 16 }, 0) end
    end
    s.force_generate_chunk_requests()
    local tiles = {}
    for x = x1, x2 - 1 do
      for y = y1, y2 - 1 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end
    end
    s.set_tiles(tiles, false, false, false, false)
  end
  return s
end

--- the box round a list of entities ({x1, y1, x2, y2})
local function bounds(ents)
  local b
  for _, e in ipairs(ents) do
    local bb = e.bounding_box
    if b then
      b = { math.min(b[1], bb.left_top.x), math.min(b[2], bb.left_top.y), math.max(b[3], bb.right_bottom.x),
        math.max(b[4], bb.right_bottom.y) }
    else
      b = { bb.left_top.x, bb.left_top.y, bb.right_bottom.x, bb.right_bottom.y }
    end
  end
  return b
end
M.bounds = bounds

--- what moves in `area` of `surface` for `force`: -> list of entities (rails included; rolling stock and the rest of
--- SKIP not), and how many were left out because they can't move (trains, cars)
function M.collect(surface, force, area)
  local out, left = {}, 0
  for _, e in pairs(surface.find_entities_filtered({ area = area, force = force })) do
    if e.valid then
      if SKIP[e.type] then
        if e.type == "locomotive" or e.type:find("wagon", 1, true) or e.type == "car" or e.type == "spider-vehicle" then
          left = left + 1
        end
      else
        out[#out + 1] = e
      end
    end
  end
  return out, left
end

--- the section as a print in `stack` (a blueprint: what the cursor shows), each entity tagged carry = its index in
--- `ents`; no wires, no tiles (the preview only). -> true, or false (nothing printable)
function M.print(stack, surface, force, area, ents)
  local want = {}
  for i, e in ipairs(ents) do want[key(e.name, e.position)] = i end
  stack.set_stack({ name = "blueprint" })
  local map = stack.create_blueprint({ surface = surface, force = force, area = area, always_include_tiles = false,
    include_entities = true, include_modules = true, include_station_names = true, include_trains = false,
    include_fuel = false })
  if not stack.is_blueprint_setup() then return false end
  local list, out = stack.get_blueprint_entities() or {}, {}
  for _, be in ipairs(list) do
    local e = map[be.entity_number]
    local i = e and e.valid and want[key(e.name, e.position)]
    if i then
      be.entity_number = #out + 1
      be.wires = nil
      be.tags = be.tags or {}
      be.tags.carry = i
      out[#out + 1] = be
    end
  end
  if #out == 0 then return false end
  stack.set_blueprint_entities(out)
  stack.set_blueprint_tiles({})
  return true
end

--- where each entity lands when the print in `stack` is put down at `position` facing `direction` (as the player's
--- paste: the game's own rounding, rails on their grid) -> {i = {position, direction}}, or nil
function M.landing(stack, ents, position, direction)
  -- (built near the scratch surface's origin, an even number of tiles off: the same rounding, rails on their grid)
  local ox, oy = 2 * math.floor(position.x / 2), 2 * math.floor(position.y / 2)
  local b = bounds(ents)
  local r = math.max(b[3] - b[1], b[4] - b[2]) / 2 + 4
  local s = hidden(SCRATCH, { -r, -r, r + 2, r + 2 })
  local out = {}
  local ghosts = stack.build_blueprint({ surface = s, force = ents[1].force, position = { position.x - ox, position.y - oy },
    direction = direction, build_mode = defines.build_mode.forced, skip_fog_of_war = true })
  for _, g in pairs(ghosts) do
    if g.valid then
      local i = g.type == "entity-ghost" and g.tags and g.tags.carry
      if i then out[i] = { position = { x = g.position.x + ox, y = g.position.y + oy }, direction = g.direction } end
      g.destroy()
    end
  end
  return out
end

--- a quarter turn clockwise of (x, y), k times
local function turned(x, y, k)
  for _ = 1, k % 4 do x, y = -y, x end
  return x, y
end

--- the targets of a move by a shift and a turn: each entity turned k quarters clockwise about the section's middle
--- (on the tile grid), then moved (dx, dy). -> {i = {position, direction}}
function M.shifted(ents, dx, dy, k)
  local b = bounds(ents)
  local cx, cy = math.floor((b[1] + b[3]) / 2 + 0.5), math.floor((b[2] + b[4]) / 2 + 0.5)
  local out = {}
  for i, e in ipairs(ents) do
    local x, y = turned(e.position.x - cx, e.position.y - cy, k)
    out[i] = { position = { x = cx + x + dx, y = cy + y + dy }, direction = (e.direction + 4 * k) % 16 }
  end
  return out
end

--- fill in targets a print couldn't land (a pump off water, say): the same shift and turn as the first that did
local function complete(ents, targets, k)
  local first
  for i, t in pairs(targets) do first = first or i break end
  if not first then return false end
  local px, py = turned(ents[first].position.x, ents[first].position.y, k)
  local tx, ty = targets[first].position.x - px, targets[first].position.y - py
  for i, e in ipairs(ents) do
    if not targets[i] then
      local x, y = turned(e.position.x, e.position.y, k)
      targets[i] = { position = { x = x + tx, y = y + ty }, direction = (e.direction + 4 * k) % 16 }
    end
  end
  return true
end
M.complete = complete

--- each entity's wires: {i, connector id, j (an entity of the section), its connector id, origin} and the circuit
--- wires and copper wires that go outside it
local function wires(ents, index)
  local inner, outer_circuit, powered = {}, 0, {}
  for i, e in ipairs(ents) do
    local ok, cons = pcall(e.get_wire_connectors, false)
    for id, c in pairs(ok and cons or {}) do
      for _, w in pairs(c.connections) do
        local t = w.target
        local j = t and t.owner and t.owner.valid and index[key(t.owner.name, t.owner.position)]
        if j then
          if j > i or (j == i and t.wire_connector_id > id) then  -- (each wire once)
            inner[#inner + 1] = { i, id, j, t.wire_connector_id, w.origin }
          end
        elseif id == defines.wire_connector_id.pole_copper then
          powered[i] = true
        elseif id ~= defines.wire_connector_id.power_switch_left_copper
            and id ~= defines.wire_connector_id.power_switch_right_copper then
          outer_circuit = outer_circuit + 1
        end
      end
    end
  end
  return inner, outer_circuit, powered
end

local capture  -- (while clone_all runs: on_entity_cloned's source -> destination pairs)
--- on_entity_cloned (control.lua): each clone of clone_all noted
function M.on_cloned(e)
  if capture and e.source and e.destination then capture[#capture + 1] = { e.source, e.destination } end
end

--- `list` ({i = entity}, all on `src`) cloned onto `dst`, (dx, dy) off: clone_entities keeps the wires between them;
--- it answers nothing, so each clone is taken from on_entity_cloned, else found where it went (by name; a small box,
--- not a point: an entity without a collision box isn't found at a point). -> {i = clone}
local function clone_all(src, dst, list, n, dx, dy, force)
  local ents, at, by_unit, by_key = {}, {}, {}, {}
  for i = 1, n do
    local e = list[i]
    ents[#ents + 1] = e
    at[i] = { name = e.name, x = e.position.x + dx, y = e.position.y + dy }
    if e.unit_number then by_unit[e.unit_number] = i else by_key[key(e.name, e.position)] = i end
  end
  capture = {}
  local ok, err = pcall(src.clone_entities, { entities = ents, destination_offset = { dx, dy }, destination_surface = dst,
    destination_force = force, snap_to_grid = false, create_build_effect_smoke = false })
  local pairs_ = capture
  capture = nil
  if not ok then log("carry: clone_entities failed: " .. tostring(err)) end
  local out = {}
  for _, p in ipairs(pairs_) do
    local s, d = p[1], p[2]
    if s.valid and d.valid and d.surface == dst then
      local i = s.unit_number and by_unit[s.unit_number] or by_key[key(s.name, s.position)]
      if i and not out[i] and d.name == at[i].name then out[i] = d end
    end
  end
  for i = 1, n do
    if not (out[i] and out[i].valid) then
      out[i] = nil
      local a = at[i]
      for _, c in pairs(dst.find_entities_filtered({ name = a.name, area = { { a.x - 0.05, a.y - 0.05 }, { a.x + 0.05, a.y + 0.05 } } })) do
        if math.abs(c.position.x - a.x) < 0.01 and math.abs(c.position.y - a.y) < 0.01 then out[i] = c break end
      end
    end
  end
  return out
end

--- a hidden helper of another entity (a mod's: its clone is that mod's business, made with its owner's)
local function helper(e)
  local p = e.prototype
  return p.hidden or p.has_flag("not-blueprintable") or p.has_flag("not-selectable-in-game")
    or not (p.mineable_properties and p.mineable_properties.minable)
end

--- (diagnosis) `ents` cloned to the staging surface and gone again: -> the ones that couldn't be found there
--- ({name, type, position, near = names of what is at that spot on the stage})
function M.probe(surface, ents)
  local b = bounds(ents)
  local stage = hidden(STAGE, b)
  local staged = clone_all(surface, stage, ents, #ents, 0, 0, ents[1].force)
  local out = {}
  for i, e in ipairs(ents) do
    if not staged[i] then
      local near = {}
      for _, c in pairs(stage.find_entities_filtered({ position = e.position, radius = 1 })) do
        near[#near + 1] = c.name .. "@" .. c.position.x .. "," .. c.position.y
      end
      out[#out + 1] = { name = e.name, type = e.type, position = e.position, near = near }
      if #out >= 20 then break end
    end
  end
  for _, c in pairs(stage.find_entities_filtered({ area = { { b[1] - 2, b[2] - 2 }, { b[3] + 2, b[4] + 2 } } })) do
    c.destroy({ raise_destroy = true })
  end
  return out
end

--- the entity's collision box at `t` ({position, direction}): {{x1, y1}, {x2, y2}}
local function box_at(proto, t)
  local cb = proto.collision_box
  local x1, y1, x2, y2 = cb.left_top.x, cb.left_top.y, cb.right_bottom.x, cb.right_bottom.y
  local q = math.floor(((t.direction or 0) % 16) / 4)  -- (quarter turns: east and west swap width and height)
  if q % 2 == 1 then x1, y1, x2, y2 = -y2, x1, -y1, x2 end
  if q >= 2 then x1, y1, x2, y2 = -x2, -y2, -x1, -y1 end
  return { { t.position.x + x1 + 0.01, t.position.y + y1 + 0.01 }, { t.position.x + x2 - 0.01, t.position.y + y2 - 0.01 } }
end

local function collide(a, b)
  for layer in pairs(a.collision_mask.layers) do
    if b.collision_mask.layers[layer] then return true end
  end
  return false
end

--- the first thing of the base (not of the section) in the way of a target (trees, rocks and cliffs left out when
--- they're to be cleared): -> the entity, or nil
local function in_way(surface, ents, targets, index, clear)
  for i, t in ipairs(targets) do
    local proto = ents[i].prototype
    for _, o in pairs(surface.find_entities_filtered({ area = box_at(proto, t) })) do
      if o.valid and not index[key(o.name, o.position)] and o.type ~= "character" and o.type ~= "item-entity"
          and o.type ~= "entity-ghost" and o.type ~= "item-request-proxy" and o.type ~= "resource"
          and not (clear and obstacle(o))
          and o.prototype.collision_mask and collide(proto, o.prototype) then
        return o, i
      end
    end
  end
end

--- the trees, rocks and cliffs in the way of the targets cleared: mined by `miner` (a player: what they give goes
--- into their inventory) where it can, else removed. -> how many
local function clear_way(surface, ents, targets, miner)
  local n = 0
  for i, t in ipairs(targets) do
    local proto = ents[i].prototype
    for _, o in pairs(surface.find_entities_filtered({ area = box_at(proto, t), type = { "tree", "simple-entity", "cliff" } })) do
      if o.valid and obstacle(o) and o.prototype.collision_mask and collide(proto, o.prototype) then
        if o.type ~= "cliff" and miner and miner.valid then pcall(miner.mine_entity, o, true) end
        if o.valid then o.destroy({ do_cliff_correction = o.type == "cliff", raise_destroy = true }) end
        n = n + 1
      end
    end
  end
  return n
end

local retrying  -- (M.move again without the helpers it couldn't clone)

--- `ents` (on `surface`) moved to `targets` ({i = {position, direction}}), turned k quarters (0: a plain shift).
--- powered: {i = true} poles to join to power outside even if they have no wire there now (they had before an
--- earlier move). clear: trees, rocks and cliffs in the way cleared (a player: mined into their inventory; or true).
--- -> true, {ents = the moved entities (in order), dropped = circuit wires to outside dropped, cleared = trees and
--- rocks cleared, powered = the poles that had power from outside (for the next move)} or false, why (a locale key),
--- where, what
function M.move(surface, ents, targets, k, also, clear)
  local force = ents[1].force
  local index = {}
  for i, e in ipairs(ents) do
    if not e.valid then return false, "carry.gone" end
    index[key(e.name, e.position)] = i
    if k % 4 ~= 0 and RAILS[e.type] then return false, "carry.no-turn-rails" end
  end
  local blocker = in_way(surface, ents, targets, index, clear)
  if blocker then return false, "carry.blocked", blocker.position, blocker.name end
  local cleared = clear and clear_way(surface, ents, targets, clear ~= true and clear or nil) or 0
  local inner, dropped, powered = wires(ents, index)
  for i in pairs(also or {}) do powered[i] = true end
  local from = {}
  for i, e in ipairs(ents) do from[i] = { name = e.name, position = e.position, direction = e.direction } end
  -- the section to the staging surface, as it is (wires within it kept), then gone from the base
  local b = bounds(ents)
  local stage = hidden(STAGE, b)
  for _, c in pairs(stage.find_entities_filtered({ area = { { b[1] - 2, b[2] - 2 }, { b[3] + 2, b[4] + 2 } } })) do
    c.destroy()  -- (an earlier move's leftovers)
  end
  local staged = clone_all(surface, stage, ents, #ents, 0, 0, force)
  local missing, hard = {}, nil
  for i = 1, #ents do
    if not staged[i] then  -- (couldn't be cloned: nothing has moved yet)
      missing[i] = true
      if not helper(ents[i]) then hard = hard or i end
      log("carry: no clone of " .. from[i].name .. " (" .. ents[i].type .. ") at " .. serpent.line(from[i].position))
    end
  end
  if next(missing) then
    for _, c in pairs(staged) do if c.valid then c.destroy({ raise_destroy = true }) end end
    if hard or retrying then return false, "carry.cant-clone", from[hard or next(missing)].position, from[hard or next(missing)].name end
    -- (only mods' hidden helpers: moved without them, their owners' mods make them again)
    local e2, t2, a2, j = {}, {}, {}, {}
    for i = 1, #ents do
      if not missing[i] then
        e2[#e2 + 1], t2[#t2 + 1], j[i] = ents[i], targets[i], #e2 + 1
      end
    end
    for i in pairs(also or {}) do if j[i] then a2[j[i]] = true end end
    if #e2 == 0 then return false, "carry.cant-clone", from[1].position, from[1].name end
    retrying = true
    local r = { pcall(M.move, surface, e2, t2, k, a2, nil) }
    retrying = false
    if not r[1] then error(r[2]) end
    if r[2] and r[3] then r[3].cleared = cleared end
    return table.unpack(r, 2, 5)
  end
  for _, e in ipairs(ents) do if e.valid then e.destroy({ raise_destroy = true }) end end
  local function back()
    local again = clone_all(stage, surface, staged, #ents, 0, 0, force)
    for _, c in pairs(staged) do if c.valid then c.destroy({ raise_destroy = true }) end end
    return again
  end
  -- every target free (the base round it; the section itself is off the base now)
  for i, t in ipairs(targets) do
    if not surface.can_place_entity({ name = from[i].name, position = t.position, direction = t.direction, force = force,
        build_check_type = defines.build_check_type.script }) then
      M.rejoin(surface, back(), powered)
      return false, "carry.blocked", t.position, from[i].name
    end
  end
  local moved = {}
  if k % 4 == 0 then
    -- (a plain shift: every target the same distance off)
    local dx, dy = targets[1].position.x - from[1].position.x, targets[1].position.y - from[1].position.y
    moved = clone_all(stage, surface, staged, #ents, dx, dy, force)
  else
    for i, t in ipairs(targets) do
      local c = staged[i].clone({ position = t.position, surface = surface, force = force, create_build_effect_smoke = false })
      if c then
        if c.direction ~= t.direction then pcall(function() c.direction = t.direction end) end
        moved[i] = c
      end
    end
    for _, w in ipairs(inner) do  -- (wires within the section, joined again)
      local a, b = moved[w[1]], moved[w[3]]
      if a and b then
        local ca, cb = a.get_wire_connector(w[2], true), b.get_wire_connector(w[4], true)
        if ca and cb then ca.connect_to(cb, false, w[5]) end
      end
    end
  end
  for _, c in pairs(staged) do if c.valid then c.destroy({ raise_destroy = true }) end end
  local list = {}
  for i = 1, #ents do list[i] = moved[i] end
  M.rejoin(surface, moved, powered)
  return true, { ents = list, dropped = dropped, cleared = cleared, from = from, powered = powered }
end

--- each pole of `moved` ({i = entity}) marked in `powered` joined by a copper wire to the nearest pole in reach that
--- isn't one of `moved`
function M.rejoin(surface, moved, powered)
  local mine = {}
  for _, m in pairs(moved) do if m.valid and m.unit_number then mine[m.unit_number] = true end end
  -- power: each pole that had a wire to a pole outside joined to the nearest one there in reach
  for i in pairs(powered) do
    local p = moved[i]
    if p and p.valid and p.type == "electric-pole" then
      local reach = p.prototype.get_max_wire_distance(p.quality)
      local best, bd
      for _, o in pairs(surface.find_entities_filtered({ type = "electric-pole", position = p.position, radius = reach,
          force = p.force })) do
        if not mine[o.unit_number] then
          local d = (o.position.x - p.position.x) ^ 2 + (o.position.y - p.position.y) ^ 2
          if not bd or d < bd then best, bd = o, d end
        end
      end
      if best then
        local a = p.get_wire_connector(defines.wire_connector_id.pole_copper, true)
        local b = best.get_wire_connector(defines.wire_connector_id.pole_copper, true)
        if a and b then a.connect_to(b, true) end
      end
    end
  end
end

return M
