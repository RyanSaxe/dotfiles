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
local diff = require("custom.git.diff")
vim.keymap.set("n", "<leader>tg", function()
  if diff.is_diffview_open() then
    vim.cmd("DiffviewClose")
  else
    -- pass base_refName = nil (so it falls back to origin/<default>),
    -- head_refName = "HEAD"
    diff.toggle_diffview(nil)
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
      diff.toggle_diffview(base)
    end)
  end
end, {
  desc = "Toggle Diffview (fetch & diff against a specified branch)",
})
-- keymaps/gh.lua ---------------------------------------------------------

-- lua/keymaps/gh-picker.lua ----------------------------------------------
local git = require("custom.git.pickers")

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

-- LSP related toggles
-- NOTE: consider extending this to other LSP servers as needed
-- NOTE: consider extensind to other types of analysis settings like type checking strictness
local function toggle_pyright_diagnostic_mode()
  local clients = vim.lsp.get_clients({ bufnr = vim.api.nvim_get_current_buf(), name = "basedpyright" })
  if vim.tbl_isempty(clients) then
    vim.notify("basedpyright isn’t attached here", vim.log.levels.WARN)
    return
  end

  for _, client in ipairs(clients) do
    local cfg = client.config.settings or {}

    if type(cfg.basedpyright) ~= "table" then
      cfg.basedpyright = {}
    end
    if type(cfg.basedpyright.analysis) ~= "table" then
      cfg.basedpyright.analysis = {}
    end

    local current = cfg.basedpyright.analysis.diagnosticMode or "openFilesOnly"
    local next_mode = (current == "openFilesOnly") and "workspace" or "openFilesOnly"

    cfg.basedpyright.analysis.diagnosticMode = next_mode

    client.config.settings = cfg

    client.notify("workspace/didChangeConfiguration", { settings = nil })
    -- vim.cmd("LspRestart basedpyright")

    vim.notify(("basedpyright diagnosticMode → %s"):format(next_mode), vim.log.levels.INFO)
  end
end

vim.keymap.set("n", "<leader>pd", toggle_pyright_diagnostic_mode, { desc = "Toggle basedpyright diagnosticMode" })
-- TODO: get the picker to reload as more diagnostics come in ... live is very bad for this
vim.keymap.set("n", "<leader>pD", function()
  toggle_pyright_diagnostic_mode()
  Snacks.picker.diagnostics({
    live = true,
    supports_live = true,
  })
end, { desc = "TESTING PICKER" })
