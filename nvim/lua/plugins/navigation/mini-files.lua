-- enabling this as it's more intuitive to use for some navigation and file
-- changes than snacks explorere
return {
  enabled = true,
  "nvim-mini/mini.files",
  opts = {
    windows = {
      preview = true,
      width_focus = 30,
      width_preview = 100,
    },
    options = {
      use_as_default_explorer = true,
      -- move to trash instead of permanent delete
      permanent_delete = false,
    },
    mappings = {
      go_in_plus = "<CR>",
      synchronize = "'",
    },
  },
}
