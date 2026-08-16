-- lspeek.nvim: peek LSP definitions in a read-only float without leaving
-- the buffer. Inside the float: q close, <CR> open here, s/v split, t tab;
-- nested peeks stack.
--
-- gp/gP override vim's rarely used paste-and-move-cursor defaults.
return {
  "r4ppz/lspeek.nvim",
  cmd = { "LSPeekDef", "LSPeekTypeDef" },
  opts = {
    window = {
      width = 120,
      -- Effectively "as tall as the terminal": nvim clamps oversized floats.
      height = 80,
      border = "single",
    },
    stack_limit = 5,
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
