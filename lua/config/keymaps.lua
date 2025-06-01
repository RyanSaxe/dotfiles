-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- local opts = { noremap = true, silent = true }

vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "move lines down in visual selection" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "move lines up in visual selection" })

-- custom toggles, all at <leader>u + character to integrate with existing lazyvim toggles UI

-- example for inline type hints -- not needed since comes built with lazyvim
-- local function _toggle_inlay_hints()
--   vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
-- end
--
-- vim.keymap.set("n", "<leader>th", _toggle_inlay_hints, {
--   desc = "Toggle LSP Inlay Hints",
-- })
--
-- Helper: return true if any Diffview buffer is open

-- Toggle mapping: <leader>tg
local diff = require("functions.diff")
vim.keymap.set("n", "<leader>tg", diff.toggle_diffview, { desc = "Toggle Diffview (fetch & diff against remote HEAD)" })

-- <leader>tG: prompt for a branch, then toggle Diffview against that
vim.keymap.set("n", "<leader>tG", function()
  if diff.is_diffview_open() then
    vim.cmd("DiffviewClose")
  else
    vim.ui.input({ prompt = "Base branch (empty for default): " }, function(input)
      -- If user pressed <Esc> or left blank, `input` will be nil or ""
      diff.fetch_and_diff(input)
    end)
  end
end, {
  desc = "Toggle Diffview (fetch & diff against a specified branch)",
})
