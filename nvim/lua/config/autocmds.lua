-- Deliberately sparse: the LazyVim floor is the autocmd surface.

-- tmux routes C-hjkl (and C-b/f/u/d) by asking whether nvim owns the
-- pane. It asks per keypress, so the answer must never fork: the
-- @is_vim pane option lets tmux read it in-server instead of walking
-- the process table with ps. This side owns the option — set while
-- this nvim holds the pane, unset the moment it lets go.
local pane = vim.env.TMUX_PANE ---@type string?
if pane then
  local group = vim.api.nvim_create_augroup("tmux_is_vim", { clear = true })

  -- pcall: vim.system throws when the binary is missing entirely (PATH
  -- stripped, tmux uninstalled); a marker option is never worth an error.
  local function mark()
    pcall(vim.system, { "tmux", "set-option", "-p", "-t", pane, "@is_vim", "1" })
  end
  ---@return vim.SystemObj?
  local function unmark()
    local ok, handle = pcall(vim.system, { "tmux", "set-option", "-pu", "-t", pane, "@is_vim" })
    return ok and handle or nil
  end

  vim.api.nvim_create_autocmd({ "VimEnter", "VimResume" }, {
    group = group,
    callback = mark,
  })
  -- LazyVim defers this file past VimEnter when nvim starts bare, so the
  -- event may already be gone by the time the autocmd exists.
  if vim.v.vim_did_enter == 1 then
    mark()
  end

  vim.api.nvim_create_autocmd("VimSuspend", {
    group = group,
    callback = function()
      unmark()
    end,
  })
  -- Exit clears synchronously: the shell prompt is back the instant
  -- nvim dies, and an unset still in flight would leave a beat where
  -- tmux keeps feeding C-hjkl to a pane with no nvim in it.
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      local handle = unmark()
      if handle then
        handle:wait()
      end
    end,
  })
end
