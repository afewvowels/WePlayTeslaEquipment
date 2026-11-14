data:extend({
  {
    -- Map setting: the lightning is drawn with real entities, so every player must use the same one.
    type = "string-setting",
    name = "wp-tesla-lightning-quality",
    setting_type = "runtime-global",
    default_value = "quality",
    allowed_values = {"quality", "performance"},
    order = "a"
  }
})
