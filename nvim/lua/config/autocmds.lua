-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`

-- Truncate LSP log file if it exceeds a certain size
local uv = vim.uv or vim.loop
local log = vim.fn.stdpath("state") .. "/lsp.log"

local function trim_lsp_log()
  local max_size = 1024 * 1024 * 5 -- 5 MB
  local stat = uv.fs_stat(log)
  if stat and stat.size > max_size then
    vim.notify("Truncating LSP log file (exceeded 5 MB)", vim.log.levels.WARN)
    vim.fn.writefile({}, log)
  end
end

-- Run on VimEnter (if we haven't entered yet)...
vim.api.nvim_create_autocmd("VimEnter", {
  callback = trim_lsp_log,
})

-- ...and also run immediately if we're already past VimEnter
if vim.v.vim_did_enter == 1 then
  trim_lsp_log()
end
