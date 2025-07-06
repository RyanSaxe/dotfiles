local M = {}

--TODO: complete this with many custom layouts and update all pickers to use them

M.wide_with_preview_wrap = {
  layout = {
    box = "vertical", -- stack children top→bottom
    border = "rounded",
    height = 0.8,
    width = 0.8,
    {
      win = "input",
      height = 1,
      border = "bottom",
    },
    {
      win = "list",
      height = 0.4, -- exactly two rows tall
      border = "bottom", -- optional separator
    },
    {
      on_win = function(win)
        vim.api.nvim_set_option_value("wrap", true, { scope = "local", win = win.win })
        -- TODO: figure out why this does not work
        vim.api.nvim_set_option_value("number", false, { scope = "local", win = win.win })
        vim.api.nvim_set_option_value("relativenumber", false, { scope = "local", win = win.win })
      end,
      win = "preview",
      -- no height ⇒ whatever is left
    },
  },
}

return M
