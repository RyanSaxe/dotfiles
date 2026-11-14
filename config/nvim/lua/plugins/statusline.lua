-- The status line is our own, in theme/statusline.lua, so LazyVim's
-- status line plugins stay off.
return {
  { "nvim-lualine/lualine.nvim", enabled = false },
  { "nvim-mini/mini.statusline", enabled = false },
}
