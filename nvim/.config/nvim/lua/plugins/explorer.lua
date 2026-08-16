-- The tree is snacks explorer on the RIGHT, mirroring the tmux rail on
-- the left of the window (bake-off verdict 2026-08-16; fyler lost on
-- information density). Width, background, and padding get unified with
-- the rail's look in the theme phase. mini.files is the edit layer:
-- batch filesystem mutations as buffer edits.
return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          explorer = {
            layout = { layout = { position = "right" } },
          },
        },
      },
    },
  },

  {
    "nvim-mini/mini.files",
    opts = {
      windows = {
        preview = true,
        width_focus = 30,
        width_preview = 100,
      },
      options = {
        use_as_default_explorer = true,
        -- Trash, never permanent delete.
        permanent_delete = false,
      },
      mappings = {
        go_in_plus = "<CR>",
        synchronize = "'",
      },
    },
  },
}
