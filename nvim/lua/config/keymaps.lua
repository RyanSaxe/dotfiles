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

-- TODO: set up full different set of git toggles
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

-- LSP related toggles
-- NOTE: consider extending this to other LSP servers as needed
-- NOTE: consider extensind to other types of analysis settings like type checking strictness
-- TODO: look into seeing if sonarlint can also be executed workspace wide
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

vim.keymap.set("n", "<leader>tp", toggle_pyright_diagnostic_mode, { desc = "Toggle basedpyright diagnosticMode" })

-- Generic dependency picker for multiple languages (Neovim, JS/TS, Python, Go, Rust, Ruby, Lua)
-- See nvim/lua/dependency-picker/ for implementation details
local dep_picker = require("dependency-picker")

-- Configure dependency picker behavior
-- Smart detector selection: prefer Neovim packages when "nvim" is in the file path
dep_picker.setup({
  -- All languages enabled by default
  select_detector = function(matching_detectors, context)
    -- If "nvim" is anywhere in the absolute path, prefer Neovim detector
    if context.bufpath:match("nvim") then
      for _, match in ipairs(matching_detectors) do
        if match.detector.name == "Neovim" then
          return match
        end
      end
    end
    -- Default: return first match
    return matching_detectors[1]
  end,
})

-- LEADER KEYBINDINGS (global, with language selection)
-- Grep mode
vim.keymap.set("n", "<leader>ps", function()
  dep_picker.smart_grep()
end, {
  noremap = true,
  silent = true,
  desc = "Smart grep: auto-detect dependency from filetype",
})

vim.keymap.set("n", "<leader>pS", function()
  dep_picker.manual_search("grep")
end, {
  noremap = true,
  silent = true,
  desc = "Manual grep: select language then dependency",
})

-- File search mode
vim.keymap.set("n", "<leader>pf", function()
  dep_picker.smart_files()
end, {
  noremap = true,
  silent = true,
  desc = "Smart file search: auto-detect dependency from filetype",
})

vim.keymap.set("n", "<leader>pF", function()
  dep_picker.manual_search("files")
end, {
  noremap = true,
  silent = true,
  desc = "Manual file search: select language then dependency",
})

-- Standard library search (builtins)
vim.keymap.set("n", "<leader>pb", function()
  dep_picker.smart_search_stdlib("grep")
end, {
  noremap = true,
  silent = true,
  desc = "Smart stdlib grep: auto-detect language stdlib",
})

vim.keymap.set("n", "<leader>pB", function()
  dep_picker.manual_search_stdlib("grep")
end, {
  noremap = true,
  silent = true,
  desc = "Manual stdlib grep: select language stdlib",
})

-- LOCALLEADER KEYBINDINGS (filetype-specific, no language selection)
-- These auto-detect based on current filetype and skip language picker
vim.keymap.set("n", "<localleader>/", function()
  dep_picker.smart_grep()
end, {
  noremap = true,
  silent = true,
  desc = "Grep in dependency (filetype-specific)",
})

vim.keymap.set("n", "<localleader>f", function()
  dep_picker.smart_files()
end, {
  noremap = true,
  silent = true,
  desc = "Search files in dependency (filetype-specific)",
})
