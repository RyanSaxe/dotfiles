-- for integrating git workflows into neovim. Mostly for viewing diffs.
return {
  "sindrets/diffview.nvim",
  cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFocusFiles" },
  opts = {
    view = {
      default = {
        layout = "diff2_horizontal",
        disable_diagnostics = false,
      },
    },
    enhanced_diff_hl = false,
    -- if you want to have the file panel on the bottom instead
    -- I recommend this if you prefer diff2_horizontal as the layout
    file_panel = {
      listing_style = "list", -- change to "tree" to get a file tree instead of a list
      tree_options = {
        flatten_dirs = true,
        folder_statuses = "only_folded",
      },
      win_config = {
        position = "bottom", -- move file tree here
        height = 10, -- adjust as needed
        win_opts = {},
      },
    },
  },
  config = function(_, opts)
    -- Setup diffview with the provided options
    require("diffview").setup(opts)

    -- Custom asymmetric coloring: red DiffText on left (old), green on right (new)
    -- This makes it visually clear: "change the red (left) into the green (right)"
    local ns_left = vim.api.nvim_create_namespace("diffview_left")
    local ns_right = vim.api.nvim_create_namespace("diffview_right")

    -- Wait for diffview to initialize, then set up our event listener
    vim.defer_fn(function()
      -- Access the global DiffviewGlobal object
      if not _G.DiffviewGlobal or not _G.DiffviewGlobal.emitter then
        vim.notify("DiffviewGlobal not initialized", vim.log.levels.ERROR)
        return
      end

      local Util = require("tokyonight.util")
      local colors = require("tokyonight.colors").setup()

      -- NOTE: Asymmetric DiffText coloring - red on left (old), green on right (new)
      -- This uses window-local highlight namespaces to override DiffText per window.
      --
      -- IMPORTANT LEARNINGS if we want to add more namespace customization:
      -- - Window namespaces override ALL highlights in that window
      -- - Diffview uses BASE Vim highlights (DiffAdd, DiffDelete, DiffChange, DiffText)
      --   NOT the Diffview-prefixed ones (DiffviewDiffAdd, etc.) for actual diff content
      -- - Any highlight not defined in the namespace falls back to namespace 0 (global)
      -- - To support enhanced_diff_hl (dimmed deletes, left-side adds as deletes):
      --   * Must define DiffDelete with dimmed styling in both namespaces
      --   * Must define DiffAdd differently: red (delete-like) in ns_left, green in ns_right
      --   * This gets complex fast - only do it if really needed!

      -- Left side (old): red foreground for "this is being removed/changed"
      vim.api.nvim_set_hl(ns_left, "DiffText", {
        fg = colors.red,
        bg = Util.blend_bg("#0000FF", 0.1),
      })

      -- Right side (new): green foreground for "this is the new version"
      vim.api.nvim_set_hl(ns_right, "DiffText", {
        fg = colors.green,
        bg = Util.blend_bg("#0000FF", 0.1),
      })

      -- Listen for when diff buffers enter windows (register once)
      -- Note: first parameter is the event object, then the emitted args
      _G.DiffviewGlobal.emitter:on("diff_buf_win_enter", function(event, bufnr, winid, ctx)
        -- Only apply to 2-way diffs (diff2_horizontal or diff2_vertical)
        if not ctx.layout_name:match("^diff2") then
          return
        end

        -- Set window-local highlight namespace based on left (a) vs right (b)
        if ctx.symbol == "a" then
          vim.api.nvim_win_set_hl_ns(winid, ns_left)
        elseif ctx.symbol == "b" then
          vim.api.nvim_win_set_hl_ns(winid, ns_right)
        end
      end)
    end, 100) -- Small delay to ensure diffview is fully loaded
  end,
}
