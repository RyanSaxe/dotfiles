-- Snacks explorer is the tree, opened on the RIGHT to mirror the tmux
-- rail on the window's left. mini.files is the edit layer: batch
-- filesystem mutations as buffer edits.
--
-- All snacks windows share one surface, and it is the OUTER one. The
-- explorer runs to the terminal's right edge and must continue the rail,
-- but snacks builds it out of floats inside a non-float box and asserts
-- its own `winhighlight` last — so neither the anchored/floating test in
-- theme.surfaces nor a per-source `wo` override can single it out. The
-- list background is one group shared by every picker. Rather than fight
-- that, snacks is outer wholesale; theme.surfaces still splits every
-- other plugin correctly.
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
