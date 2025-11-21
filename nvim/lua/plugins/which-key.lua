-- which-key.nvim  ── Keybinding hints and custom group names
-- Adds descriptive names for custom keybinding groups

return {
  "folke/which-key.nvim",
  opts = {
    spec = {
      { "<leader>t", group = "Toggle" },
      { "<leader>o", group = "Obsidian" },
      { "<leader>p", group = "Package" },
    },
  },
}
