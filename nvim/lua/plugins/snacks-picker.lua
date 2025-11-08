-- snacks-picker.lua  ── Snacks picker configuration
-- Custom picker configurations including enhanced buffer picker

return {
  "folke/snacks.nvim",
  opts = {
    picker = {
      layout = {
        preset = "custom_vertical",
      },
      sources = {
        buffers = require("custom.snacks.picker").buffer_config,
        -- Configure explorer to show hidden files by default
        explorer = {
          hidden = true,
          -- Ensure the input window doesn't overlap the main window's winbar
          layout = {
            preset = "sidebar",
            preview = false,
            layout = {
              row = 1, -- Start 1 row down to leave space for winbar
            },
          },
        },
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
        custom_horizontal = {
          layout = {
            box = "horizontal",
            width = 0.8,
            min_width = 120,
            height = 0.8,
            {
              box = "vertical",
              border = true,
              title = "{title} {live} {flags}",
              { win = "input", height = 1, border = "bottom" },
              { win = "list", border = "none" },
            },
            { win = "preview", title = "{preview}", border = true, width = 0.5 },
          },
        },
      },
      actions = {
        switch_to_vertical_layout = require("custom.snacks.actions").switch_to_vertical_layout,
        switch_to_horizontal_layout = require("custom.snacks.actions").switch_to_horizontal_layout,
        restore_original_layout = require("custom.snacks.actions").restore_original_layout,
      },
      win = {
        input = {
          keys = {
            ["<a-->"] = { "switch_to_vertical_layout", mode = { "n", "i" }, desc = "Switch to vertical layout" },
            ["<a-\\>"] = { "switch_to_horizontal_layout", mode = { "n", "i" }, desc = "Switch to horizontal layout" },
            ["<a-'>"] = { "restore_original_layout", mode = { "n", "i" }, desc = "Restore original layout" },
          },
        },
        list = {
          keys = {
            ["<a-->"] = { "switch_to_vertical_layout", desc = "Switch to vertical layout" },
            ["<a-\\>"] = { "switch_to_horizontal_layout", desc = "Switch to horizontal layout" },
            ["<a-'>"] = { "restore_original_layout", desc = "Restore original layout" },
          },
        },
        preview = {
          keys = {
            ["<a-->"] = { "switch_to_vertical_layout", desc = "Switch to vertical layout" },
            ["<a-\\>"] = { "switch_to_horizontal_layout", desc = "Switch to horizontal layout" },
            ["<a-'>"] = { "restore_original_layout", desc = "Restore original layout" },
          },
        },
      },
    },
  },
}
