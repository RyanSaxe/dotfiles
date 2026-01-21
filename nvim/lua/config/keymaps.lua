-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- local opts = { noremap = true, silent = true }

vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "move lines down in visual selection" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "move lines up in visual selection" })
-- make escape go to normal mode when in a terminal
vim.keymap.set("t", "<Esc>", "<C-\\><C-n>", { silent = true, desc = "Terminal: go to Normal mode" })

-- Swap ; and : for easier command access
-- ; now enters command mode (was :)
-- : now repeats last f/t/F/T search (was ;)
-- vim.keymap.set({ "n", "v" }, ";", ":", { desc = "Enter command mode" })
-- vim.keymap.set({ "n", "v" }, ":", ";", { desc = "Repeat last f/t/F/T search" })

-- GitHub Comments picker (review threads needing attention)
-- <leader>gc = current repo (falls back to all if not in git repo)
-- <leader>gC = all repos
vim.keymap.set("n", "<leader>gc", function()
  local rt = require("custom.git.review_threads")
  rt.picker({ repo = rt.get_current_repo() })
end, { desc = "GitHub Comments (repo)" })

vim.keymap.set("n", "<leader>gC", function()
  require("custom.git.review_threads").picker()
end, { desc = "GitHub Comments (all)" })
