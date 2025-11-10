-- tiny-glimmer.nvim: smooth animations for yank, paste, search, undo, and redo operations
-- Uses dynamic highlight groups to adapt to colorscheme changes
return {
  "rachartier/tiny-glimmer.nvim",
  event = "VeryLazy",
  -- Low priority to ensure it loads after other plugins and can hijack their keybindings
  priority = 10,
  -- Tell LazyVim to load the plugin when these keys are pressed
  keys = { "y", "p", "P", "n", "N", "u", "<C-r>" },
  enabled = true,
  opts = {
    -- Enable/disable the plugin
    enabled = true,

    -- Disable warnings for debugging highlight issues
    disable_warnings = true,

    -- Animation refresh rate in milliseconds
    refresh_interval_ms = 8,

    -- Automatic keybinding overwrites
    overwrite = {
      -- Automatically map keys to overwrite operations
      -- Set to false if you have custom mappings or prefer manual API calls
      auto_map = true,

      -- Yank operation animation
      yank = {
        enabled = true,
        default_animation = "fade",
        yank_mapping = "y",
      },

      -- Search navigation animation
      search = {
        enabled = false, -- this messes with highlights while searching so disabling
        default_animation = "fade",
        next_mapping = "n", -- Key for next match
        prev_mapping = "N", -- Key for previous match
      },

      -- Paste operation animation
      paste = {
        enabled = true,
        default_animation = "fade",
        paste_mapping = "p", -- Paste after cursor
        Paste_mapping = "P", -- Paste before cursor
      },

      -- Undo operation animation
      undo = {
        enabled = true,
        default_animation = "fade",
        undo_mapping = "u",
      },

      -- Redo operation animation
      redo = {
        enabled = true,
        default_animation = "fade",
        redo_mapping = "<c-r>",
      },
    },

    -- Override background color for animations (for transparent backgrounds)
    transparency_color = nil,

    -- Animation configurations
    animations = {
      fade = {
        max_duration = 600, -- Maximum animation duration in ms
        min_duration = 400, -- Minimum animation duration in ms
        easing = "outQuad", -- Easing function
        chars_for_max_duration = 10, -- Character count for max duration
        from_color = "#9d7cd8", -- Start color (TokyoNight purple - matches keywords/operators)
        to_color = "Normal", -- End color (highlight group or hex)
      },
    },
    -- Filetypes to disable hijacking/overwrites
    hijack_ft_disabled = {
      "alpha",
      "snacks_dashboard",
    },

    -- Virtual text display priority
    virt_text = {
      priority = 2048, -- Higher values appear above other plugins
    },
  },
}
