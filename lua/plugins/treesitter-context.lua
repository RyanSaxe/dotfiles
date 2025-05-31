return {
  enabled = false,
  "nvim-treesitter/nvim-treesitter-context",
  event = "LazyFile",
  opts = {
    separator = "-",
    max_lines = 3,
    mode = "topline",
    -- the below makes sure that formatting doesnt get weird and nested for function arguments
    trim_scope = "inner",
    multiline_threshold = 1,
  },
}
