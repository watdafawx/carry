-- two hidden helpers as other mods make them: one without a collision box, one whose clone its mod takes away
-- (it makes its own with the owner's)
for _, name in ipairs({ "carry-test-tiny", "carry-test-owned" }) do
  local e = table.deepcopy(data.raw["simple-entity-with-owner"]["simple-entity-with-owner"])
  e.name = name
  e.hidden = true
  e.minable = nil
  e.flags = { "placeable-neutral", "player-creation", "not-blueprintable" }
  e.collision_box = { { 0, 0 }, { 0, 0 } }
  e.selection_box = { { 0, 0 }, { 0, 0 } }
  e.collision_mask = { layers = {} }
  data:extend({ e })
end
