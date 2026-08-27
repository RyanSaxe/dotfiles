-- Diagnostics render as tidy inline annotations at the end of the line
-- instead of nvim's raw virtual text, so [d / ]d never needs a float to
-- be readable. Ported from v1; goto_prev/goto_next became
-- vim.diagnostic.jump since.
return {
  {
    "rachartier/tiny-inline-diagnostic.nvim",
    -- BufReadPre, not VeryLazy: the plugin attaches per-buffer on
    -- LspAttach, and the startup buffer's server attaches BEFORE
    -- VeryLazy fires -- so the first file of every session silently got
    -- no inline diagnostics (with stock virtual text off below, that
    -- read as "diagnostics are broken"). Loading before the first read
    -- puts the LspAttach handler in place before any server exists.
    event = { "BufReadPre", "BufNewFile" },
    priority = 1000,
    keys = {
      {
        "[d",
        function()
          vim.diagnostic.jump({ count = -1, float = false })
        end,
        desc = "Prev diagnostic (no float)",
      },
      {
        "]d",
        function()
          vim.diagnostic.jump({ count = 1, float = false })
        end,
        desc = "Next diagnostic (no float)",
      },
    },
    -- Only the deviations from upstream defaults.
    opts = {
      disabled_ft = { "snacks_dashboard" },
      options = {
        show_source = true,
        set_arrow_to_diag_color = true,
        show_related = false,
        multilines = false,
        add_messages = {
          show_multiple_glyphs = false,
        },
      },
    },
  },
  -- The plugin replaces virtual text; both on would double-print every
  -- diagnostic.
  {
    "neovim/nvim-lspconfig",
    opts = {
      diagnostics = {
        virtual_text = false,
      },
    },
  },
}
