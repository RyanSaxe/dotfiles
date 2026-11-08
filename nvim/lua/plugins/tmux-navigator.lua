-- C-hjkl crosses nvim splits and tmux panes as one grid (the rail's
-- nav-skip hook lives on the tmux side).
-- Inside Rex, the Rex config's nvim.lua (rex/ in this repo) replaces this
-- spec when ~/.config/rex has one.
local rex_spec = vim.fn.expand("~/.config/rex/nvim.lua")
if vim.env.REX_BLOCK and not vim.env.TMUX and vim.uv.fs_stat(rex_spec) then
  return dofile(rex_spec)
end
return {
  "christoomey/vim-tmux-navigator",
  cmd = {
    "TmuxNavigateLeft",
    "TmuxNavigateDown",
    "TmuxNavigateUp",
    "TmuxNavigateRight",
    "TmuxNavigatePrevious",
  },
  keys = {
    { "<c-h>", "<cmd><C-U>TmuxNavigateLeft<cr>" },
    { "<c-j>", "<cmd><C-U>TmuxNavigateDown<cr>" },
    { "<c-k>", "<cmd><C-U>TmuxNavigateUp<cr>" },
    { "<c-l>", "<cmd><C-U>TmuxNavigateRight<cr>" },
    { "<c-\\>", "<cmd><C-U>TmuxNavigatePrevious<cr>" },
  },
}
