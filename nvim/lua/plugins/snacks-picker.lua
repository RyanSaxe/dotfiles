-- snacks-picker.lua  ── Snacks picker configuration
-- Custom picker configurations including enhanced buffer picker

return {
  "folke/snacks.nvim",
  opts = {
    -- uncomment below to enable fyler
    -- explorer = { enabled = false },
    picker = {
      sources = {
        -- Enhanced buffer picker with visual indicators and save action
        buffers = require("custom.snacks.picker").buffer_config,
      },
    },
  },
}
