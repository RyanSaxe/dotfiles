-- Disable Copilot LSP server for markdown files
-- The ai.sidekick extra adds Copilot as an LSP server for NES (Next Edit Suggestions)
-- This server is separate from copilot.lua and needs its own filetype configuration
return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      copilot = {
        -- Disable Copilot LSP for markdown and text files
        filetypes = {
          ["*"] = true, -- Enable for all filetypes by default
          markdown = false, -- Disable for markdown (note-taking with obsidian.nvim)
          text = false, -- Disable for plain text files
        },
      },
    },
  },
}
