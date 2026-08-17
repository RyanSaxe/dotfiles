-- Six facts, no backgrounds. Left: mode (one bold capital in the mode
-- color), branch, git counts. Right: diagnostic counts, then location.
-- Volatile segments sit at each group's inner end, so growth eats empty
-- middle instead of moving anything — location stays pinned to the
-- right edge, mode and branch to the left. While a macro records, the
-- location pulses red: no extra cells, no layout shift.
return {
  { "nvim-lualine/lualine.nvim", enabled = false },
  {
    "nvim-mini/mini.statusline",
    event = "VeryLazy",
    config = function()
      require("theme.statusline").setup()
    end,
  },
}
