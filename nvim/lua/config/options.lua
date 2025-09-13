-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- default update time is 200, which i notice, so putting it at shorter
vim.opt.updatetime = 50
-- highlight the search results
vim.opt.hlsearch = true
-- since I use flash to jump, I prefer absolute line numbers
vim.opt.relativenumber = false
-- merge signs into number column to eliminate signcolumn padding
vim.opt.signcolumn = "number"

vim.opt.swapfile = false
-- enable system clipboard integration
vim.opt.clipboard = "unnamedplus"
