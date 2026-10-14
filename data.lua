local icon = "__base__/graphics/icons/blueprint.png"

data:extend({
  -- drag over a section: it goes into your cursor as a print to put down where it should go
  {
    type = "selection-tool",
    name = "carry-tool",
    icon = icon,
    icon_size = 64,
    flags = { "only-in-cursor", "not-stackable", "spawnable" },
    subgroup = "tool",
    order = "z[carry]",
    stack_size = 1,
    draw_label_for_cursor_render = true,
    select = {
      border_color = { r = 0.3, g = 0.9, b = 1 },
      cursor_box_type = "copy",
      mode = { "same-force", "any-entity" },
    },
    alt_select = {
      border_color = { r = 0.3, g = 0.9, b = 1 },
      cursor_box_type = "copy",
      mode = { "same-force", "any-entity" },
    },
  },
  {
    type = "shortcut",
    name = "carry-tool",
    order = "b[blueprints]-c[carry]",
    action = "spawn-item",
    item_to_spawn = "carry-tool",
    associated_control_input = "carry-tool",
    icon = icon,
    icon_size = 64,
    small_icon = icon,
    small_icon_size = 64,
  },
  { type = "custom-input", name = "carry-tool", key_sequence = "CONTROL + ALT + C", action = "spawn-item",
    item_to_spawn = "carry-tool", consuming = "game-only" },
})
