-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- local opts = { noremap = true, silent = true }

vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "move lines down in visual selection" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "move lines up in visual selection" })
-- Double-escape exits terminal mode to Neovim normal mode
-- Single escape is passed through to the terminal (needed for Claude Code's vim bindings)
-- Alternative: use <C-\><C-n> directly if you prefer a single-key exit
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { silent = true, desc = "Terminal: exit to Normal mode" })

-- Ensure leader key works in terminal normal mode
-- By default, <Space> in terminal buffers may be mapped to send literal space
-- This autocmd removes that mapping so leader key works as expected
vim.api.nvim_create_autocmd("TermOpen", {
  callback = function()
    local opts = { buffer = 0 }
    -- Remove any buffer-local space mapping that might interfere with leader
    pcall(vim.keymap.del, "n", "<Space>", opts)
  end,
})

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
