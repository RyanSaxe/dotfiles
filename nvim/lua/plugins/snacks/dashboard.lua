-- snacks-dashboard.lua  ── Snacks dashboard configuration
-- Custom git dashboard with project sections and snorlax integration

return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  opts = {
    dashboard = {
      -- Use the modular dashboard configuration
      sections = require("custom.snacks.dashboard").create_sections,
      layout = { anchor = "center" },
    },
  },
  config = function(_, opts)
    -- Setup snacks with opts
    require("snacks").setup(opts)

    -- Register custom GitHub actions
    require("custom.snacks.gh").register()
  end,
}
