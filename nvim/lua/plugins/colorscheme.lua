-- Catppuccin is the floor; lua/theme applies the generated tokens and
-- the semantic layer on top, following the theme system's mode.
return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    opts = { flavour = "mocha" },
    ---@param opts table catppuccin setup opts from this spec
    config = function(_, opts)
      require("theme").setup(opts)
    end,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = function()
        require("theme").apply()
      end,
    },
  },
}
