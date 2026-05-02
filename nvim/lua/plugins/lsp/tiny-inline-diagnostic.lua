return {
  {
    "rachartier/tiny-inline-diagnostic.nvim",
    event = "VeryLazy",
    priority = 1000,
    keys = {
      {
        "[d",
        function()
          vim.diagnostic.goto_prev({ float = false })
        end,
        desc = "Go to previous diagnostic (no float)",
      },
      {
        "]d",
        function()
          vim.diagnostic.goto_next({ float = false })
        end,
        desc = "Go to next diagnostic (no float)",
      },
    },
    -- Keep only the behavior overrides that differ from upstream defaults.
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
  {
    "neovim/nvim-lspconfig",
    opts = {
      diagnostics = {
        virtual_text = false,
      },
    },
  },
}
