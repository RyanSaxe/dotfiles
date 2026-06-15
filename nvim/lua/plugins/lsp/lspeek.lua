-- lspeek.nvim: preview LSP definitions / type definitions in a read-only float.
--
-- This is the "peek-first" counterpart to lsp-splits.lua (g| / g-), which
-- *jumps* to a definition in a split. Here you inspect the definition in a
-- floating window without leaving the current buffer. Inside the float:
--   q      close the preview
--   <CR>   open the definition in the current buffer
--   s / v  open in a horizontal / vertical split
--   t      open in a new tab
-- Nested peeks stack (up to stack_limit) so you can drill through definitions.
--
-- Note: gp / gP override Vim's default paste-and-move-cursor commands, which
-- are rarely used; remap below if you rely on them.

return {
  "r4ppz/lspeek.nvim",
  -- Load lazily: keys pull the plugin in on first use, the user commands on demand.
  cmd = { "LSPeekDef", "LSPeekTypeDef" },
  opts = {
    window = {
      width = 70,
      height = 15,
      border = "single",
    },
    -- Cap how many nested preview floats can stack at once.
    stack_limit = 5,
    -- Keymaps active *inside* a preview float.
    keymaps = {
      close = "q",
      split = "s",
      vsplit = "v",
      enter = "<CR>",
      tab = "t",
    },
  },
  keys = {
    {
      "gp",
      function()
        require("lspeek").peek_definition()
      end,
      desc = "Peek Definition",
    },
    {
      "gP",
      function()
        require("lspeek").peek_type_definition()
      end,
      desc = "Peek Type Definition",
    },
  },
}
