-- Sticky scope header: the enclosing function/class stays pinned to the
-- top of the window while its body scrolls. Ported from v1 with its
-- tuning; the colors moved into theme/highlights.lua with everything
-- else (v1 derived them from TokyoNight at runtime, which the token
-- system replaces).
return {
  "nvim-treesitter/nvim-treesitter-context",
  event = "LazyFile",
  opts = {
    max_lines = 4,
    mode = "cursor",
    trim_scope = "inner",
    -- One line per nested scope, so four levels never eat the viewport.
    multiline_threshold = 1,
  },
}
