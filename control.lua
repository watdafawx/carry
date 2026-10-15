-- Carry: drag over a section with the Carry tool, it goes into the cursor as a print (the game draws it there, R
-- turns it); click where it should go and the section is moved there as it is (carry.lua). A card after each move
-- offers Move back.
local carry = require("carry")

local CARD = "carry_card"

local function held() storage.held = storage.held or {} return storage.held end    -- player index -> the section in hand
local function last() storage.last = storage.last or {} return storage.last end    -- player index -> the last move (Move back)
local function drops() storage.drops = storage.drops or {} return storage.drops end -- player index -> tick of a drop

local function say(player, text, pos)
  if pos then
    player.create_local_flying_text({ text = text, position = pos })
  else
    player.create_local_flying_text({ text = text, create_at_cursor = true })
  end
end

local function card(player, text)
  local screen = player.gui.screen
  if screen[CARD] then screen[CARD].destroy() end
  if not text then return end
  local f = screen.add({ type = "frame", name = CARD, direction = "vertical", caption = { "carry.title" } })
  local l = f.add({ type = "label", caption = text })
  l.style.single_line = false
  l.style.maximal_width = 320
  local row = f.add({ type = "flow", direction = "horizontal" })
  row.style.top_margin = 6
  row.add({ type = "empty-widget" }).style.horizontally_stretchable = true
  row.add({ type = "button", name = "carry_back", caption = { "carry.back" }, tooltip = { "carry.back-tip" } })
  row.add({ type = "button", name = "carry_close", caption = { "carry.close" } })
  local scale = player.display_scale
  f.location = { math.max(0, (player.display_resolution.width - 360 * scale) / 2), math.floor(80 * scale) }
end

--- a red box round where it was blocked, for 5 s
local function mark(player, pos)
  if not pos then return end
  rendering.draw_rectangle({ color = { 1, 0.2, 0.2 }, width = 3, filled = false, surface = player.surface,
    left_top = { pos.x - 0.6, pos.y - 0.6 }, right_bottom = { pos.x + 0.6, pos.y + 0.6 }, players = { player },
    time_to_live = 300 })
end

--- the move's answer told to the player; a move done becomes the card's Move back
local function told(player, ok, res, pos, name, record)
  if not ok then
    mark(player, pos)
    if res == "carry.blocked" then
      local p = name and prototypes.entity[name]
      local hint = p and (p.type == "tree" or p.type == "simple-entity" or p.type == "cliff")
      return say(player, { hint and "carry.blocked-shift" or "carry.blocked", name and ("[entity=" .. name .. "]") or "?" }, pos)
    end
    return say(player, { res })
  end
  if record then last()[player.index] = record end
  local text = { "", { "carry.moved", #res.ents } }
  if (res.cleared or 0) > 0 then table.insert(text, " ") table.insert(text, { "carry.cleared", res.cleared }) end
  if res.dropped > 0 then table.insert(text, " ") table.insert(text, { "carry.dropped", res.dropped }) end
  card(player, text)
end

-- picked up: the section into the cursor as a print
local function on_selected(e)
  if e.item ~= "carry-tool" then return end
  local player = game.get_player(e.player_index)
  local area = { left_top = e.area.left_top, right_bottom = e.area.right_bottom }
  local ents, left = carry.collect(player.surface, player.force, area)
  if #ents == 0 then return say(player, { "carry.nothing" }) end
  player.clear_cursor()
  local stack = player.cursor_stack
  if not (stack and carry.print(stack, player.surface, player.force, area, ents)) then
    if stack then stack.clear() end
    return say(player, { "carry.nothing" })
  end
  player.cursor_stack_temporary = true
  local label = "Carry: " .. #ents
  stack.label = label
  held()[player.index] = { surface = player.surface.name, ents = ents, label = label, area = area }
  say(player, left > 0 and { "", { "carry.picked", #ents }, " ", { "carry.left", left } } or { "carry.picked", #ents })
end
script.on_event(defines.events.on_player_selected_area, on_selected)
script.on_event(defines.events.on_player_alt_selected_area, on_selected)

local function holding(player, h)
  local s = player.cursor_stack
  return h and s and s.valid_for_read and s.is_blueprint and s.label == h.label
end

-- dropped: moved where the print was put down (shift-click: trees, rocks and cliffs in the way cleared)
script.on_event(defines.events.on_pre_build, function(e)
  local player = game.get_player(e.player_index)
  local h = held()[e.player_index]
  if not holding(player, h) then return end
  drops()[e.player_index] = game.tick  -- (the paste's own ghosts: removed as they come, see on_built_entity)
  if e.flip_horizontal or e.flip_vertical then return say(player, { "carry.no-flip" }) end
  if player.surface.name ~= h.surface then return say(player, { "carry.other-surface" }) end
  for _, x in ipairs(h.ents) do
    if not x.valid then
      held()[e.player_index] = nil
      storage.clear = storage.clear or {}
      storage.clear[e.player_index] = true
      return say(player, { "carry.changed" })
    end
  end
  local k = math.floor((e.direction or 0) / 4) % 4
  local targets = carry.landing(player.cursor_stack, h.ents, e.position, e.direction or 0)
  if not carry.complete(h.ents, targets, k) then return say(player, { "carry.cant-land" }) end
  local from = {}
  for i, x in ipairs(h.ents) do from[i] = { position = x.position, direction = x.direction } end
  local clear = e.build_mode ~= nil and e.build_mode ~= defines.build_mode.normal and player or nil
  local ok, res, pos, name = carry.move(player.surface, h.ents, targets, k, nil, clear)
  if ok then
    held()[e.player_index] = nil
    storage.clear = storage.clear or {}
    storage.clear[e.player_index] = true
    told(player, ok, res, pos, name, { surface = player.surface.name, ents = res.ents, targets = from, k = (4 - k) % 4,
      powered = res.powered })
  else
    told(player, ok, res, pos, name)
  end
end)

script.on_event(defines.events.on_built_entity, function(e)
  local t = drops()[e.player_index]
  local g = e.entity
  if t and t >= game.tick - 1 and g.valid and g.type == "entity-ghost" and g.tags and g.tags.carry then g.destroy() end
end)

-- (a shift-click paste marks the trees and rocks under it for deconstruction: the drop cleared what was in the way)
script.on_event(defines.events.on_marked_for_deconstruction, function(e)
  local t = e.player_index and drops()[e.player_index]
  local o = e.entity
  if t and t >= game.tick - 1 and o.valid and (o.type == "tree" or o.type == "simple-entity" or o.type == "cliff") then
    o.cancel_deconstruction(o.force, e.player_index)
  end
end)

script.on_event(defines.events.on_tick, function()
  if not storage.clear or not next(storage.clear) then return end
  for i in pairs(storage.clear) do
    local p = game.get_player(i)
    if p then p.clear_cursor() end
  end
  storage.clear = {}
end)

script.on_event(defines.events.on_player_cursor_stack_changed, function(e)
  local h = held()[e.player_index]
  if h and not holding(game.get_player(e.player_index), h) then held()[e.player_index] = nil end
end)

--- the last move undone (and that one's undo kept, so it can be done again)
local function move_back(player_index)
  local r = last()[player_index]
  if not r then return false, "carry.none" end
  local s = game.get_surface(r.surface)
  for _, x in ipairs(r.ents) do if not x.valid then return false, "carry.changed" end end
  local from = {}
  for i, x in ipairs(r.ents) do from[i] = { position = x.position, direction = x.direction } end
  local ok, res, pos, name = carry.move(s, r.ents, r.targets, r.k, r.powered)
  if ok then
    last()[player_index] = { surface = r.surface, ents = res.ents, targets = from, k = (4 - r.k) % 4,
      powered = res.powered }
  end
  return ok, res, pos, name
end

script.on_event(defines.events.on_gui_click, function(e)
  local el = e.element
  if not (el and el.valid) then return end
  local player = game.get_player(e.player_index)
  if el.name == "carry_close" then
    card(player, nil)
  elseif el.name == "carry_back" then
    local ok, res, pos, name = move_back(e.player_index)
    told(player, ok, res, pos, name)
  end
end)

-- for tests (no player to drag in a headless run)
remote.add_interface("carry", {
  -- as if the player dragged the Carry tool over `area`
  pick = function(player_index, area)
    on_selected({ item = "carry-tool", player_index = player_index,
      area = { left_top = { x = area[1][1], y = area[1][2] }, right_bottom = { x = area[2][1], y = area[2][2] } } })
  end,
  -- the entities in `area` moved (dx, dy) and turned k quarters about their middle -> {ok, why, n, dropped}
  -- (clear: trees, rocks and cliffs in the way cleared, as a shift-click drop)
  move_by = function(surface_name, force_name, area, dx, dy, k, clear)
    local s, f = game.get_surface(surface_name), game.forces[force_name]
    local ents = carry.collect(s, f, area)
    if #ents == 0 then return { ok = false, why = "carry.nothing" } end
    local from = {}
    for i, x in ipairs(ents) do from[i] = { position = x.position, direction = x.direction } end
    local ok, res, pos, name = carry.move(s, ents, carry.shifted(ents, dx, dy, k or 0), k or 0, nil, clear or nil)
    if not ok then return { ok = false, why = res, at = pos, name = name } end
    last()[0] = { surface = surface_name, ents = res.ents, targets = from, k = (4 - (k or 0)) % 4,
      powered = res.powered }
    return { ok = true, n = #res.ents, dropped = res.dropped, cleared = res.cleared }
  end,
  -- as a player's drop: the section's print put down at `position` facing `direction`
  drop = function(surface_name, force_name, area, position, direction)
    local s, f = game.get_surface(surface_name), game.forces[force_name]
    local ents = carry.collect(s, f, area)
    if #ents == 0 then return { ok = false, why = "carry.nothing" } end
    local inv = game.create_inventory(1)
    if not carry.print(inv[1], s, f, area, ents) then inv.destroy() return { ok = false, why = "carry.nothing" } end
    local k = math.floor((direction or 0) / 4) % 4
    local targets = carry.landing(inv[1], ents, position, direction or 0)
    inv.destroy()
    if not carry.complete(ents, targets, k) then return { ok = false, why = "carry.cant-land" } end
    local from = {}
    for i, x in ipairs(ents) do from[i] = { position = x.position, direction = x.direction } end
    local ok, res, pos, name = carry.move(s, ents, targets, k)
    if not ok then return { ok = false, why = res, at = pos, name = name } end
    last()[0] = { surface = surface_name, ents = res.ents, targets = from, k = (4 - k) % 4, powered = res.powered }
    return { ok = true, n = #res.ents, dropped = res.dropped }
  end,
  back = function()
    local ok, res, pos, name = move_back(0)
    if not ok then return { ok = false, why = res, at = pos, name = name } end
    return { ok = true, n = #res.ents }
  end,
})
