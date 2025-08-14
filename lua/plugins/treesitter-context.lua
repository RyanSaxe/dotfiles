return {
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
