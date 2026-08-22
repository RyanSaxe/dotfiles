-- There is no statusline. A global one spans the full width, so it cut
-- the outer surface off one row above the terminal floor and a
-- right-hand explorer stopped short of the edge instead of reading as
-- the frame's right wall. Its two facts moved to surfaces that were
-- already there: mode and recording to the tab row (global state on a
-- global bar), per-window git and diagnostics to the winbar.
return {
  { "nvim-lualine/lualine.nvim", enabled = false },
  { "nvim-mini/mini.statusline", enabled = false },
}
