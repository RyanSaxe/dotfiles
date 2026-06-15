-- Mason configuration to ensure web development tools are installed
-- This extends LazyVim's default mason setup with additional tools

return {
  "mason-org/mason.nvim",
  opts = {
    ensure_installed = {
      -- TypeScript/JavaScript
      "vtsls", -- TypeScript language server (faster than tsserver)
      "eslint-lsp", -- ESLint language server
      "prettier", -- Code formatter

      -- CSS/Tailwind
      "tailwindcss-language-server",
      "css-lsp",

      -- HTML
      "html-lsp",

      -- Structural lint (byor / ast-grep rules)
      "ast-grep",
    },
  },
}
