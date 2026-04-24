return {
  -- enable this if you want to have context (e.g. the class you're in) shown at the top of the window
  enabled = true,
  "nvim-treesitter/nvim-treesitter-context",
  event = "LazyFile",
  config = function(_, opts)
    require("treesitter-context").setup(opts)
    require("custom.visual.treesitter_context_chrome").setup()
  end,
  opts = {
    max_lines = 2,
    mode = "cursor",
    trim_scope = "inner",
    multiline_threshold = 1,
    -- separator = "-",
  },
}
