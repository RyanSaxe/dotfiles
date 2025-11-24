-- LSP split navigation configuration
-- Provides intuitive keymaps for opening go to definition in splits:
-- g- : horizontal split (- looks like a horizontal divider)
-- g| : vertical split (| looks like a vertical divider)

return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      -- Apply these keymaps to all LSP servers
      ["*"] = {
        keys = {
          {
            "g|",
            function()
              vim.cmd("vsplit")
              vim.lsp.buf.definition()
            end,
            desc = "Go to Definition (vertical split)",
            has = "definition",
          },
          {
            "g-",
            function()
              -- Store cursor position before split
              local pos = vim.api.nvim_win_get_cursor(0)
              vim.cmd("split")
              -- Restore cursor position after split
              vim.api.nvim_win_set_cursor(0, pos)
              vim.lsp.buf.definition()
            end,
            desc = "Go to Definition (horizontal split)",
            has = "definition",
          },
        },
      },
    },
  },
}

