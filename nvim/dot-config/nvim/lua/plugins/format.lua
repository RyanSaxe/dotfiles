-- Formatting on top of LazyVim's conform defaults (stylua for lua,
-- shfmt for shell come with the floor; the formatting.prettier extra
-- wires prettier into conform for web/json/yaml/markdown and has mason
-- install the binary).
-- Python is static ruff: projects that want different tools configure
-- ruff in their own pyproject.
return {
  "stevearc/conform.nvim",
  opts = {
    formatters_by_ft = {
      python = { "ruff_organize_imports", "ruff_format" },
      zsh = { "shfmt" },
    },
  },
}
