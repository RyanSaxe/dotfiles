-- Snacks explorer is the tree, opened on the RIGHT to mirror the tmux
-- rail on the window's left. mini.files is the edit layer: batch
-- filesystem mutations as buffer edits.
--
-- All snacks windows share one surface, and it is the INNER one. The
-- explorer is the exception: it runs to the terminal's right edge and must
-- continue the rail. It cannot be singled out where the colors are chosen,
-- because snacks builds it out of floats inside a non-float box, paints the
-- list through the one group every picker shares, and asserts its own
-- `winhighlight` last — which defeats both the anchored/floating test in
-- theme.surfaces and a per-source `wo` override. So theme.surfaces names
-- the explorer's own windows and repaints them outer after the fact.
return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          explorer = {
            layout = { layout = { position = "right" } },
            -- The picker builds its windows a tick after the call that opens
            -- it, so an autocmd pass only reaches them after the first redraw
            -- — long enough to see the explorer painted on the wrong surface.
            -- `on_show` runs in the tick that creates them, before any paint.
            on_show = function()
              require("theme.surfaces").refresh()
            end,
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
