-- a small running section (a belt with plates, a chest, an assembler mid-craft, a pipe of water, a combinator wired
-- to a pole, that pole powered from outside) moved about through Carry's remote interface: shifted onto itself,
-- back, turned, back, blocked, and dropped as a player's print; what's in it kept every time
local out, fails = {}, 0
local function log(s) out[#out + 1] = s end
local function check(ok, what)
  if not ok then
    fails = fails + 1
    log("FAIL: " .. what)
  end
end

local E, S = defines.direction.east, defines.direction.south
local s, f
local AREA = { { 0, 0 }, { 10, 7 } }

local function area(dx, dy) return { { AREA[1][1] + dx, AREA[1][2] + dy }, { AREA[2][1] + dx, AREA[2][2] + dy } } end

--- what's in the section at (dx, dy) from where it was built: counts by name, belt items, chest plates, ...
local function state(dx, dy)
  local a = area(dx, dy)
  local st = { names = {}, n = 0, belt = 0 }
  for _, e in pairs(s.find_entities_filtered({ area = a, force = f })) do
    st.names[e.name] = (st.names[e.name] or 0) + 1
    st.n = st.n + 1
    if e.type == "transport-belt" then
      st.belt = st.belt + e.get_transport_line(1).get_item_count() + e.get_transport_line(2).get_item_count()
      st.belt_dir = e.direction
    elseif e.name == "iron-chest" then st.chest = e.get_item_count("iron-plate")
    elseif e.name == "assembling-machine-2" then
      st.recipe = e.get_recipe() and e.get_recipe().name
      st.progress = e.crafting_progress
      st.powered = e.is_connected_to_electric_network()
    elseif e.name == "pipe" then st.water = e.fluidbox[1] and e.fluidbox[1].amount or 0
    elseif e.name == "constant-combinator" then
      local c = e.get_wire_connector(defines.wire_connector_id.circuit_red, false)
      st.red = c and #c.connections or 0
    end
  end
  return st
end

local function same(a, b, what)
  check(a.n == b.n, what .. ": " .. b.n .. " entities, " .. a.n .. " before")
  for k, v in pairs(a.names) do check(b.names[k] == v, what .. ": " .. k .. " " .. tostring(b.names[k]) .. " of " .. v) end
  check(b.belt == a.belt, what .. ": belt items " .. b.belt .. " of " .. a.belt)
  check(b.chest == a.chest, what .. ": chest plates " .. tostring(b.chest))
  check(b.recipe == a.recipe, what .. ": recipe " .. tostring(b.recipe))
  check(b.water and math.abs(b.water - a.water) < 0.5, what .. ": water " .. tostring(b.water))
  check(b.red == 1, what .. ": the combinator's wire " .. tostring(b.red))
end

local function setup()
  s, f = game.surfaces.nauvis, game.forces.player
  s.always_day = true
  local all = { { -30, -30 }, { 90, 50 } }
  for _, e in pairs(s.find_entities_filtered({ area = all })) do if e.type ~= "character" then e.destroy() end end
  local tiles = {}
  for x = -30, 90 do for y = -30, 50 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
  s.set_tiles(tiles)
  local function make(name, x, y, dir)
    local e = s.create_entity({ name = name, position = { x, y }, direction = dir, force = f })
    assert(e, "can't place " .. name)
    return e
  end
  local function cu(a, b) a.get_wire_connector(defines.wire_connector_id.pole_copper, true).connect_to(
    b.get_wire_connector(defines.wire_connector_id.pole_copper, true), false) end
  -- outside: power and a pole
  local eei = make("electric-energy-interface", -4, 3)
  eei.power_production, eei.electric_buffer_size = 1e9, 1e9
  local outer = make("medium-electric-pole", -1.5, 4.5)
  -- the section
  for x = 0, 9 do
    local b = make("transport-belt", x + 0.5, 0.5, E)
    for i = 1, 2 do b.get_transport_line(i).insert_at_back({ name = "iron-plate", count = 1 }) end
  end
  local ch = make("iron-chest", 2.5, 2.5)
  ch.insert({ name = "iron-plate", count = 50 })
  local pole = make("medium-electric-pole", 4.5, 4.5)
  cu(outer, pole)
  local am = make("assembling-machine-2", 6.5, 3.5)
  am.set_recipe("iron-gear-wheel")
  am.insert({ name = "iron-plate", count = 20 })
  local pipe = make("pipe", 9.5, 5.5)
  pipe.fluidbox[1] = { name = "water", amount = 50 }
  local cc = make("constant-combinator", 0.5, 6.5)
  cc.get_wire_connector(defines.wire_connector_id.circuit_red, true).connect_to(
    pole.get_wire_connector(defines.wire_connector_id.circuit_red, true), false)
end

script.on_event(defines.events.on_tick, function(e)
  if e.tick == 2 then setup() end
  if e.tick ~= 120 then return end
  local before = state(0, 0)
  log(string.format("section: %d entities, belt %d, chest %s, recipe %s, water %s, powered %s", before.n, before.belt,
    tostring(before.chest), tostring(before.recipe), tostring(before.water), tostring(before.powered)))
  check(before.powered, "the section isn't powered to start with")

  -- shifted 3 east, onto where it stood
  local r = remote.call("carry", "move_by", "nauvis", "player", AREA, 3, 0, 0)
  check(r.ok, "move 3 east: " .. tostring(r.why))
  local a = state(3, 0)
  same(before, a, "moved 3 east")
  check(a.powered, "moved 3 east: not powered (its pole not joined to the one outside)")
  check(s.count_entities_filtered({ area = { { 0, 0 }, { 3, 7 } }, force = f }) == 0, "moved 3 east: left something")
  log(string.format("moved 3 east: %d entities, belt %d, powered %s", a.n, a.belt, tostring(a.powered)))

  -- back
  r = remote.call("carry", "back")
  check(r.ok, "back: " .. tostring(r.why))
  same(before, state(0, 0), "back")
  check(state(0, 0).powered, "back: not powered")

  -- turned a quarter and moved 30 east
  r = remote.call("carry", "move_by", "nauvis", "player", AREA, 30, 0, 1)
  check(r.ok, "turned: " .. tostring(r.why))
  local tt = s.find_entities_filtered({ area = { { 25, -5 }, { 45, 15 } }, force = f })
  local names = {}
  for _, x in pairs(tt) do names[x.name] = (names[x.name] or 0) + 1 end
  check(#tt == before.n, "turned: " .. #tt .. " entities near the target, " .. before.n .. " before")
  local belt = s.find_entities_filtered({ area = { { 25, -5 }, { 45, 15 } }, name = "transport-belt", limit = 1 })[1]
  check(belt and belt.direction == S, "turned: the belts don't face south")
  local cc = s.find_entities_filtered({ area = { { 25, -5 }, { 45, 15 } }, name = "constant-combinator", limit = 1 })[1]
  local red = cc and cc.get_wire_connector(defines.wire_connector_id.circuit_red, false)
  check(red and #red.connections == 1, "turned: the combinator's wire lost")
  local ch = s.find_entities_filtered({ area = { { 25, -5 }, { 45, 15 } }, name = "iron-chest", limit = 1 })[1]
  check(ch and ch.get_item_count("iron-plate") == 50, "turned: chest plates lost")
  log("turned: " .. #tt .. " entities, belts face " .. tostring(belt and belt.direction))

  -- back again, as it was
  r = remote.call("carry", "back")
  check(r.ok, "back from turned: " .. tostring(r.why))
  local b2 = state(0, 0)
  same(before, b2, "back from turned")
  check(b2.belt_dir == E, "back from turned: the belts don't face east")

  -- blocked: a chest where the assembler would land; nothing moves
  local block = s.create_entity({ name = "wooden-chest", position = { 46.5, 3.5 }, force = "neutral" })
  r = remote.call("carry", "move_by", "nauvis", "player", AREA, 40, 0, 0)
  check(not r.ok and r.why == "carry.blocked", "blocked: " .. tostring(r.ok) .. " " .. tostring(r.why))
  local b3 = state(0, 0)
  same(before, b3, "after a blocked move")
  check(b3.powered, "after a blocked move: not powered")
  block.destroy()

  -- trees and a rock where it lands: blocked, unless cleared (a shift-click drop)
  local trees = {}
  for _, p in ipairs({ { 46.5, 3.5 }, { 42.5, 2.5 }, { 49.5, 5.5 } }) do  -- (assembler, chest, pipe)
    trees[#trees + 1] = s.create_entity({ name = "tree-01", position = p })
  end
  local rock = s.create_entity({ name = "big-rock", position = { 44, 0.5 } })
  check(#trees == 3 and rock, "trees: not all made")
  r = remote.call("carry", "move_by", "nauvis", "player", AREA, 40, 0, 0)
  check(not r.ok and r.why == "carry.blocked", "trees, not cleared: " .. tostring(r.ok) .. " " .. tostring(r.why))
  same(before, state(0, 0), "after a move blocked by trees")
  r = remote.call("carry", "move_by", "nauvis", "player", AREA, 40, 0, 0, true)
  check(r.ok, "trees cleared: " .. tostring(r.why) .. " " .. tostring(r.name))
  check(r.ok and r.cleared == 4, "trees cleared: " .. tostring(r.cleared))
  check(not (rock and rock.valid), "trees cleared: the rock is still there")
  same(before, state(40, 0), "moved over the trees")
  log("cleared: " .. tostring(r.cleared))
  r = remote.call("carry", "back")
  check(r.ok, "back from the trees: " .. tostring(r.why))
  for _, t in pairs(trees) do if t.valid then t.destroy() end end
  if rock and rock.valid then rock.destroy() end

  -- dropped as a player's print: 15 tiles south, unturned
  r = remote.call("carry", "drop", "nauvis", "player", AREA, { x = 5, y = 3.5 + 15 }, defines.direction.north)
  check(r.ok, "drop: " .. tostring(r.why))
  local found = s.find_entities_filtered({ area = { { -2, 10 }, { 14, 26 } }, force = f })
  check(#found == before.n, "drop: " .. #found .. " entities 15 south, " .. before.n .. " before")
  log("dropped: " .. #found .. " entities")
  r = remote.call("carry", "back")
  check(r.ok, "back from the drop: " .. tostring(r.why))
  same(before, state(0, 0), "back from the drop")

  -- a big section: 2500 belts with plates on them, moved 25 south (onto half of itself) and back, timed
  for x = 40, 89 do
    for y = -25, 24 do
      local b = s.create_entity({ name = "transport-belt", position = { x + 0.5, y + 0.5 }, direction = E, force = f })
      if b then b.get_transport_line(1).insert_at_back({ name = "iron-plate", count = 1 }) end
    end
  end
  local big = { { 40, -25 }, { 90, 25 } }
  local prof = helpers.create_profiler()
  r = remote.call("carry", "move_by", "nauvis", "player", big, 0, 25, 0)
  prof.stop()
  check(r.ok and r.n == 2500, "big: " .. tostring(r.ok) .. " " .. tostring(r.why) .. " " .. tostring(r.n))
  check(s.count_entities_filtered({ area = { { 40, 0 }, { 90, 50 } }, name = "transport-belt" }) == 2500,
    "big: not all 2500 belts where they went")
  r = remote.call("carry", "back")
  check(r.ok, "big back: " .. tostring(r.why))

  -- other mods' hidden helpers in the section: the one without a box moves, the owned one is its mod's business
  local hx = -20
  local hc = s.create_entity({ name = "iron-chest", position = { hx + 0.5, 0.5 }, force = f })
  hc.insert({ name = "iron-plate", count = 7 })
  s.create_entity({ name = "carry-test-tiny", position = { hx + 1.5, 0.5 }, force = f })
  s.create_entity({ name = "carry-test-owned", position = { hx + 2.5, 0.5 }, force = f })
  r = remote.call("carry", "move_by", "nauvis", "player", { { hx, 0 }, { hx + 3, 1 } }, 0, 5, 0)
  check(r.ok, "helpers: " .. tostring(r.why) .. " " .. tostring(r.name))
  local mc = s.find_entity("iron-chest", { hx + 0.5, 5.5 })
  check(mc and mc.get_item_count("iron-plate") == 7, "helpers: the chest didn't move with its plates")
  check(#s.find_entities_filtered({ name = "carry-test-tiny", area = { { hx + 1, 5 }, { hx + 2, 6 } } }) == 1,
    "helpers: the one without a box didn't move")
  r = remote.call("carry", "back")
  check(r.ok, "helpers back: " .. tostring(r.why))
  check(s.find_entity("iron-chest", { hx + 0.5, 0.5 }), "helpers back: the chest isn't back")

  helpers.write_file("carry-test.txt", table.concat(out, "\n") .. "\n")
  helpers.write_file("carry-test.txt", { "", "big: 2500 belts moved in ", prof, "\n" }, true)
  helpers.write_file("carry-test.txt", (fails == 0 and "ALL PASS" or (fails .. " FAILED")) .. "\n", true)
end)

-- (as a mod that makes its helper again with its owner: the helper's own clone taken away)
script.on_event(defines.events.on_entity_cloned, function(e)
  if e.destination.valid and e.destination.name == "carry-test-owned" then e.destination.destroy() end
end)
