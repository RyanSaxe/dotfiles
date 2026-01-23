-- Terminal management with snacks.nvim
-- Provides toggleable terminals that persist their state (hiding doesn't quit)

--- Calculate terminal window configuration based on monitor aspect ratio
--- Wide monitors get a left-side vertical split, tall monitors get a bottom horizontal split
---@return table win_opts Window options for Snacks.terminal
local function get_terminal_win_opts()
  local width = vim.o.columns
  local height = vim.o.lines

  -- Compare aspect ratio: if wider than tall, use right position
  if width > height then
    return { position = "right", width = 0.33 }
  else
    return { position = "bottom", height = 0.33 }
  end
end

--- Get the ipython command, preferring the active virtualenv's ipython if available
--- Neovim inherits VIRTUAL_ENV from the parent shell, but spawned terminals start fresh
--- shells that may reset PATH. Using the full path ensures we get the right ipython.
---@return string The ipython command or full path to venv ipython
local function get_ipython_cmd()
  local venv = vim.env.VIRTUAL_ENV
  if venv then
    local venv_ipython = venv .. "/bin/ipython"
    if vim.fn.executable(venv_ipython) == 1 then
      return venv_ipython
    end
  end
  return "ipython"
end

return {
  "folke/snacks.nvim",
  keys = {
    {
      "<leader>tt",
      function()
        Snacks.terminal.toggle(nil, { win = get_terminal_win_opts() })
      end,
      desc = "Toggle terminal",
    },
    {
      "<leader>tp",
      function()
        Snacks.terminal.toggle(get_ipython_cmd(), { win = get_terminal_win_opts() })
      end,
      desc = "Toggle IPython REPL",
    },
  },
}
