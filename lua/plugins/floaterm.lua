-- TODO: explore REPL sending integration with this (e.g. slime, iron)
return {
  "nvzone/floaterm",
  dependencies = "nvzone/volt",
  opts = {
    border = true,
    size = { h = 70, w = 80 },
    terminals = {
      -- TODO: maybe only make the REPL if opening from a python file? Or have keybinds with different configs.
      -- when opening the first time, default to a terminal and an ipython REPL
      { name = "Terminal" },
      -- NOTE: cmd can be a function -- though I should look into how this works
      { name = "Python REPL", cmd = "ipython" },
    },
  },
  cmd = "FloatermToggle",
  keys = {
    { "<leader>tt", ":FloatermToggle<CR>", desc = "Toggle Terminal" },
  },
}
