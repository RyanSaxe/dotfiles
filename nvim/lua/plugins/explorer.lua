-- Snacks explorer is the tree, opened on the RIGHT to mirror the tmux
-- rail on the window's left. mini.files is the edit layer: batch
-- filesystem mutations as buffer edits.
--
-- All snacks windows share one surface, and it is the INNER one. The
-- explorer is the exception: it runs to the terminal's right edge and must
-- continue the rail. It cannot be singled out where the colors are chosen,
-- because snacks builds it out of floats inside a non-float box and paints
-- the list through the one group every picker shares — which defeats the
-- anchored/floating test in theme.surfaces. So theme.surfaces names the
-- explorer's own windows and hands them a highlight namespace in which
-- those shared groups mean the outer surface.
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
    -- mini.files pins its cascade to the top LEFT — `anchor = 'NW'` and a
    -- column that counts up from zero, neither of them configurable. The
    -- documented lever is its window event, which fires once per window
    -- after every window has been placed, so the whole cascade can be
    -- shifted as a unit and keeps growing in its usual direction.
    init = function()
      vim.api.nvim_create_autocmd("User", {
        pattern = "MiniFilesWindowUpdate",
        group = vim.api.nvim_create_augroup("mini_files_right", { clear = true }),
        callback = function()
          ---@type integer[]
          local wins = {}
          local right = 0
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "minifiles" then
              wins[#wins + 1] = win
              local config = vim.api.nvim_win_get_config(win)
              -- +2: the width excludes the border column on either side.
              right = math.max(right, config.col + config.width + 2)
            end
          end
          -- Already flush against the right edge — which is also what a
          -- second pass over the same cascade sees, so this is idempotent.
          local shift = vim.o.columns - right
          if #wins == 0 or shift <= 0 then
            return
          end
          for _, win in ipairs(wins) do
            local config = vim.api.nvim_win_get_config(win)
            config.col = config.col + shift
            vim.api.nvim_win_set_config(win, config)
          end
        end,
      })
    end,
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
