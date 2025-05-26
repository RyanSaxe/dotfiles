-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local opts = { noremap = true, silent = true }

vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "move lines down in visual selection" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "move lines up in visual selection" })

vim.keymap.set("n", "<C-d>", "<C-d>zz", { desc = "page down and center cursor" })
vim.keymap.set("n", "<C-u>", "<C-u>zz", { desc = "page up and center cursor" })

-- center cursor during search results
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")
-- tab visual blocks
vim.keymap.set("v", "<", "<gv", opts)
vim.keymap.set("v", ">", ">gv", opts)

-- custom toggles, all at <leader>u + character to integrate with existing lazyvim toggles UI

-- example for inline type hints -- not needed since comes built with lazyvim
-- local function _toggle_inlay_hints()
--   vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
-- end
--
-- vim.keymap.set("n", "<leader>th", _toggle_inlay_hints, {
--   desc = "Toggle LSP Inlay Hints",
-- })
