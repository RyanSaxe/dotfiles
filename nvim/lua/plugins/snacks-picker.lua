-- snacks-picker.lua  ── Snacks picker configuration
-- Custom picker configurations including enhanced buffer picker

return {
  "folke/snacks.nvim",
  opts = {
    -- uncomment below to enable fyler
    -- explorer = { enabled = false },
    picker = {
      sources = {
        buffers = require("custom.snacks.picker").buffer_config,
      },
      layouts = {
        custom_vertical = {
          layout = {
            box = "vertical",
            width = 0.8,
            min_width = 120,
            height = 0.8,
            border = true,
            title = "{title} {live} {flags}",
            { win = "preview", border = "bottom" },
            { win = "input", height = 1, border = "bottom" },
            { win = "list", height = 5, border = "none" },
          },
        },
      },
      actions = {
        switch_to_vertical_layout = require("custom.snacks.actions").switch_to_vertical_layout,
        switch_to_default_layout = require("custom.snacks.actions").switch_to_default_layout,
        restore_original_layout = require("custom.snacks.actions").restore_original_layout,
      },
      win = {
        input = {
          keys = {
            ["<a-->"] = { "switch_to_vertical_layout", mode = { "n", "i" }, desc = "Switch to vertical layout" },
            ["<a-\\>"] = { "switch_to_default_layout", mode = { "n", "i" }, desc = "Switch to default layout" },
            ["<a-'>"] = { "restore_original_layout", mode = { "n", "i" }, desc = "Restore original layout" },
          },
        },
        list = {
          keys = {
            ["<a-->"] = { "switch_to_vertical_layout", desc = "Switch to vertical layout" },
            ["<a-\\>"] = { "switch_to_default_layout", desc = "Switch to default layout" },
            ["<a-'>"] = { "restore_original_layout", desc = "Restore original layout" },
          },
        },
        preview = {
          keys = {
            ["<a-->"] = { "switch_to_vertical_layout", desc = "Switch to vertical layout" },
            ["<a-\\>"] = { "switch_to_default_layout", desc = "Switch to default layout" },
            ["<a-'>"] = { "restore_original_layout", desc = "Restore original layout" },
          },
        },
      },
    },
  },
}
