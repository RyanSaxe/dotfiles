-- snacks-picker.lua  ── Snacks picker configuration
-- Custom picker configurations including enhanced buffer picker
-- also, disables Snacks explorer to avoid conflicts with Fyler

return {
  "folke/snacks.nvim",
  keys = {
    { "<leader>fe", false },
    { "<leader>fE", false },
    { "<leader>E", false },
    { "<leader>e", false },
  },
  opts = {
    explorer = { enabled = false },
    picker = {
      sources = {
        -- Enhanced buffer picker with visual indicators and save action
        buffers = require("custom.snacks.picker").buffer_config,
      },
    },
  },
}

