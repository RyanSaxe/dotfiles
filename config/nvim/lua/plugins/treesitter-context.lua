-- Sticky scope header: the enclosing blocks stay pinned to the top of the
-- window while their bodies scroll, one row per block, each header
-- collapsed to one line. context-line draws it from nvim-treesitter-context's
-- queries and highlight groups, whose colors are in theme/highlights.lua.
return {
  dir = vim.fn.stdpath("config") .. "/local/context-line",
  main = "context_line",
  dependencies = { "nvim-treesitter/nvim-treesitter-context" },
  event = "LazyFile",
  opts = {
    max_lines = 4,
    trim_scope = "inner",
    separator = "─",
  },
}
