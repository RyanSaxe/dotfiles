-- snacks-dashboard.lua  ── Snacks dashboard configuration
-- Custom git dashboard with project sections and snorlax integration

return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  dependencies = { "ibhagwan/fzf-lua", "folke/todo-comments.nvim" },
  opts = {
    dashboard = {
      -- Use the modular dashboard configuration
      sections = require("custom.snacks.dashboard").create_sections,
      layout = { anchor = "center" },
    },
  },
}