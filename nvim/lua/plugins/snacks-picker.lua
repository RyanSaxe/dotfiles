-- snacks-picker.lua  ── Snacks picker configuration
-- Custom picker configurations including enhanced buffer picker

return {
  "folke/snacks.nvim",
  opts = {
    picker = {
      sources = {
        -- Enhanced buffer picker with visual indicators and save action
        buffers = require("custom.snacks.picker").buffer_config,
      },
    },
  },
}