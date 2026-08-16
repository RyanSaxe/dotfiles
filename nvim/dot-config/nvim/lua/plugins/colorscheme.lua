-- Catppuccin is the floor; lua/theme applies the generated tokens and
-- the semantic layer on top, following the theme system's INNER mode.
return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    opts = { flavour = "mocha" },
    config = function(_, opts)
      require("catppuccin").setup(opts)
      require("theme").setup()
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
