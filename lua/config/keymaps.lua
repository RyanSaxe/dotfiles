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

-------------------------------------------------------------------------------
-- 1) <leader>tg: “Toggle Diffview (fetch & diff against remote default HEAD)”
--    When no arguments are given, we treat head_refName = "HEAD".
-------------------------------------------------------------------------------
local diff = require("functions.diff")
vim.keymap.set("n", "<leader>tg", function()
  if diff.is_diffview_open() then
    vim.cmd("DiffviewClose")
  else
    -- pass base_refName = nil (so it falls back to origin/<default>),
    -- head_refName = "HEAD"
    diff.toggle_diffview(nil, "HEAD")
  end
end, {
  desc = "Toggle Diffview (fetch & diff against remote HEAD)",
})

-------------------------------------------------------------------------------
-- 2) <leader>tG: prompt for a base branch name, then toggle Diffview.
--    Again, head_refName = "HEAD".
-------------------------------------------------------------------------------
vim.keymap.set("n", "<leader>tG", function()
  if diff.is_diffview_open() then
    vim.cmd("DiffviewClose")
  else
    vim.ui.input({ prompt = "Base branch (empty for default): " }, function(input)
      -- `input` may be nil or "" if <Esc> or blank
      --
      -- Treat any non-empty string as the “base_refName” and
      -- always use head_refName = "HEAD" here.
      local base = (input ~= nil and input ~= "") and input or nil
      diff.toggle_diffview(base, "HEAD")
    end)
  end
end, {
  desc = "Toggle Diffview (fetch & diff against a specified branch)",
})
-- keymaps/gh.lua ---------------------------------------------------------

-- lua/keymaps/gh-picker.lua ----------------------------------------------
local git = require("pickers.git")

vim.keymap.set("n", "<leader>gp", function()
  local items = git.fetch_prs()
  Snacks.picker.pick({
    prompt_title = "  Open Pull-Requests",
    items = items,
    -- format = git.format_pr_row,
    -- preview = git.preview_pr,
    layout = "select",
  })
end, { desc = "GitHub PR picker" })
