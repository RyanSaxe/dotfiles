-- which-key.nvim  ── Keybinding hints and custom group names
-- Adds descriptive names and icons for custom keybinding groups

return {
  "folke/which-key.nvim",
  opts = {
    -- show popup immediately (default is 200ms)
    delay = 0,
    spec = {
      { "<leader>a", group = "AI", icon = "󰚩" },
      { "<leader>o", group = "Obsidian", icon = "󰎞" },
      { "<leader>p", group = "Package", icon = "󰏗" },
      { "<leader>t", group = "Toggle", icon = "󰔡" },
      -- Git diff groups
      { "<leader>gd", group = "Diff", icon = "" },
    },
  },
}
