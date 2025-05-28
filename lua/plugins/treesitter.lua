-- lua/plugins/treesitter.lua
return {
  {
    "nvim-treesitter/nvim-treesitter",
    dependencies = { "nvim-treesitter/nvim-treesitter-refactor" },
    build = ":TSUpdate", -- keep parsers up to date
    opts = {
      highlight = { enable = true },
      refactor = {
        highlight_definitions = { enable = true },
        highlight_current_scope = { enable = false },
        clear_on_cursor_move = true,
        smart_rename = {
          enable = true,
          -- Assign keymaps to false to disable them, e.g. `smart_rename = false`.
          keymaps = {
            smart_rename = "<leader>r",
          },
        },
      },
    },
  },
}
