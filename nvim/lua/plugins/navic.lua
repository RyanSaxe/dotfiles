return {
  {
    "SmiteshP/nvim-navic",
    lazy = true,
    init = function()
      vim.g.navic_silence = true
    end,
    opts = {
      lsp = {
        auto_attach = true,
      },
      highlight = true,
      separator = " > ",
      depth_limit = 0,
      safe_output = true,
      lazy_update_context = false,
      click = false,
    },
  },
}