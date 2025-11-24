return {
  {
    "ryansaxe/buffergolf.nvim",
    dependencies = { "nvim-mini/mini.diff" },
    opts = {
      -- Auto-detect and disable conflicting plugins (including Copilot)

      disabled_plugins = {
        _auto = true, -- Keep auto-disabling other plugins
        blink = false, -- Don't disable blink.cmp
      },

      -- Automatic deindentation for consistent practice
      auto_dedent = true,

      -- Keymaps configuration
      keymaps = {
        toggle = "<leader>bg",
        countdown = "<leader>bG",
        golf = {
          next_hunk = "]h",
          prev_hunk = "[h",
          first_hunk = "[H",
          last_hunk = "]H",
        },
      },

      -- Window positioning
      windows = {
        reference = {
          position = "right", -- right side split for reference text
          size = 50, -- 50 columns wide
        },
        stats = {
          position = "top", -- stats window at the top
          height = 3,
        },
      },

      -- Mode-specific overrides
      typing_mode = {
        disabled_plugins = {
          _inherit = true, -- inherit global disabled_plugins
          matchparen = true, -- disable match parens in typing mode
          treesitter_context = true, -- disable context in typing mode
        },
      },
      golf_mode = {
        disabled_plugins = {
          _inherit = true,
          matchparen = false, -- keep match parens enabled in golf mode
        },
      },
    },
    config = function(_, opts)
      require("buffergolf").setup(opts)
    end,
  },
}
