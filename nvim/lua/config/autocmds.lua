-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`

-- Snacks dashboard: hide terminal cursor + make Neovim cursor unobtrusive
local grp = vim.api.nvim_create_augroup("SnacksDashboardHideCursor", { clear = true })

-- depth guards re-entrancy across WinEnter/BufEnter
local state = { depth = 0, saved = nil, hidden = false }

-- Raw write to the terminal (stdout) for escape sequences.
-- Works in TUI (Ghostty/iTerm/Alacritty/tmux). No-op if something goes wrong.
local function term_write(s)
  local ok = pcall(function()
    io.write(s)
    io.flush()
  end)
  return ok
end

local function really_hide_cursor()
  if not state.hidden then
    -- ESC[?25l  → hide terminal cursor
    term_write("\x1b[?25l")
    state.hidden = true
  end
end

local function really_show_cursor()
  if state.hidden then
    -- ESC[?25h  → show terminal cursor
    term_write("\x1b[?25h")
    state.hidden = false
  end
end

local function apply()
  if state.depth == 0 then
    -- Hide ASAP to avoid the initial “block flash”
    really_hide_cursor()

    -- Save & set a barely-there cursor as a fallback (in case the terminal ignores hide)
    state.saved = vim.o.guicursor
    vim.o.guicursor = "a:hor1-blinkon0" -- thin underline, no blink
    vim.wo.cursorline = false
    vim.wo.cursorcolumn = false
  end
  state.depth = state.depth + 1
end

local function restore()
  if state.depth > 0 then
    state.depth = state.depth - 1
    if state.depth == 0 then
      -- Restore terminal cursor and guicursor
      really_show_cursor()
      if state.saved then
        vim.o.guicursor = state.saved
        state.saved = nil
      end
    end
  end
end

local function is_dashboard(buf)
  return vim.bo[buf].filetype == "snacks_dashboard"
end

vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
  group = grp,
  callback = function(args)
    if is_dashboard(args.buf) then
      apply()
    end
  end,
})

vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave", "BufWipeout" }, {
  group = grp,
  callback = function(args)
    if is_dashboard(args.buf) then
      restore()
    end
  end,
})

-- Safety net: if Neovim exits while hidden, make sure the cursor is shown again.
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = grp,
  callback = function()
    really_show_cursor()
  end,
})

-- If this file loads after the dashboard is already open, apply immediately.
if is_dashboard(0) then
  apply()
end
