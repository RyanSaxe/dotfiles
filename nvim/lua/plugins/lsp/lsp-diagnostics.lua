-- Disable built-in diagnostic virtual text to prevent conflicts with tiny-inline-diagnostic
-- This ensures that only tiny-inline-diagnostic handles virtual text display
return {
  "neovim/nvim-lspconfig",
  opts = {
    diagnostics = {
      virtual_text = false, -- Disable LazyVim's diagnostic virtual text
    },
  },
}