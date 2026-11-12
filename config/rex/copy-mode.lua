-- Copy mode for Rex. init.lua opens a float that pipes a pane's text into
-- read-only Neovim and sources this file. Select with v, V or Ctrl-V, then y
-- or Enter copies to the system clipboard and closes the float. q closes it
-- without copying.
vim.bo.modifiable = false
vim.cmd("normal! G")
vim.keymap.set("x", "<cr>", "y")
vim.keymap.set("n", "q", "<cmd>qa!<cr>")
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function()
    vim.fn.setreg("+", vim.v.event.regcontents, vim.v.event.regtype)
    vim.schedule(function()
      vim.cmd("qa!")
    end)
  end,
})
