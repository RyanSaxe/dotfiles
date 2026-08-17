-- The heatmap (lua/theme/heatmap.lua) owns the statusline: one
-- hand-rolled expression, no framework. LazyVim's lualine would
-- otherwise claim it on load.
return {
  { "nvim-lualine/lualine.nvim", enabled = false },
  {
    "folke/snacks.nvim",
    opts = function()
      require("theme.heatmap").setup()
      return {}
    end,
  },
}
