-- Go to definition in a split. The keys are mnemonic: `|` is a vertical
-- divider, `-` a horizontal one.
--
-- Registered under the `*` server so every attached client gets them,
-- and gated on `has = "definition"` so they never appear on a client
-- that cannot answer.
return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      ["*"] = {
        keys = {
          {
            "g|",
            function()
              vim.cmd("vsplit")
              vim.lsp.buf.definition()
            end,
            desc = "Goto Definition (vertical split)",
            has = "definition",
          },
          {
            "g-",
            function()
              -- `split` puts the new window at the top and leaves the
              -- cursor on a different line than the one being asked
              -- about, so restore it before requesting the definition.
              local pos = vim.api.nvim_win_get_cursor(0)
              vim.cmd("split")
              vim.api.nvim_win_set_cursor(0, pos)
              vim.lsp.buf.definition()
            end,
            desc = "Goto Definition (horizontal split)",
            has = "definition",
          },
        },
      },
    },
  },
}
