-- Neovim inside Rex: Ctrl-H/J/K/L move between Neovim windows and, at the
-- edge of Neovim, run `rex focus` to move to the Rex pane beside it. init.lua
-- passes these keys to Neovim rather than moving Rex focus itself.
-- nvim/lua/plugins/tmux-navigator.lua returns this spec in place of its own.

local function navigate(wincmd, direction)
  return function()
    local window = vim.api.nvim_get_current_win()
    vim.cmd.wincmd(wincmd)
    if vim.api.nvim_get_current_win() == window then
      vim.system({ "rex", "focus", direction })
    end
  end
end

-- The spec keeps the tmux plugin so lazy.nvim doesn't uninstall it, and its
-- keys stay lazy key handlers so LazyVim doesn't map them to plain window
-- moves. The plugin's own mappings would replace these, so they stay off.
return {
  "christoomey/vim-tmux-navigator",
  init = function()
    vim.g.tmux_navigator_no_mappings = 1
  end,
  keys = {
    { "<c-h>", navigate("h", "left"), desc = "Go to Left Window or Rex Pane" },
    { "<c-j>", navigate("j", "down"), desc = "Go to Lower Window or Rex Pane" },
    { "<c-k>", navigate("k", "up"), desc = "Go to Upper Window or Rex Pane" },
    { "<c-l>", navigate("l", "right"), desc = "Go to Right Window or Rex Pane" },
  },
}
