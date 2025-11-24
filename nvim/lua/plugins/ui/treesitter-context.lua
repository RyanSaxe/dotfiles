return {
  -- enable this if you want to have context (e.g. the class you're in) shown at the top of the window
  enabled = false,
  "nvim-treesitter/nvim-treesitter-context",
  event = "LazyFile",
  opts = {
    separator = "-",
    max_lines = 2,
    mode = "topline",
    trim_scope = "inner",
    multiline_threshold = 1,
  },
}
