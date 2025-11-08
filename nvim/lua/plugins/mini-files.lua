-- another plugin like fyler to manage files as neovim buffer
-- currently disabling as I want to get used to snacks explorer
return {
  enabled = false,
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
