-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- local opts = { noremap = true, silent = true }

vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "move lines down in visual selection" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "move lines up in visual selection" })
-- make escape go to normal mode when in a terminal
vim.keymap.set("t", "<Esc>", "<C-\\><C-n>", { silent = true, desc = "Terminal: go to Normal mode" })

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

-- TODO: clean this up and likely move it to a separate file
--[[
Select a Python package from the current virtual environment and then grep inside it.

This script provides a two-stage picker workflow using `snacks.nvim`:
1. A picker to select a package from the active `$VIRTUAL_ENV`.
2. A grep picker that automatically opens for the selected package.

This is not dependent on the current buffer and can be triggered from anywhere.
]]

local _last_venv, _site_cache
local snacks = require("snacks")

local function find_site_packages()
  local venv = vim.env.VIRTUAL_ENV
  if not venv or venv == "" then
    vim.notify("Error: VIRTUAL_ENV not set", vim.log.levels.ERROR, { title = "Venv Grep" })
    return
  end

  -- If venv hasn't changed, return cached path
  if _site_cache and _last_venv == venv then
    return _site_cache
  end

  -- 1) Fast one-level glob: returns a **string** of paths separated by "\n"
  local raw = vim.fn.glob(venv .. "/lib/python*/site-packages", false, false)
  local candidate
  if raw ~= "" then
    -- pick the first line
    candidate = raw:match("([^\n]+)")
  else
    -- 2) Fallback recursive (returns a table)
    local tbl = vim.fn.globpath(venv, "**/site-packages", false, true)
    if type(tbl) == "table" and #tbl > 0 then
      candidate = tbl[1]
    end
  end

  if candidate and candidate ~= "" then
    _site_cache, _last_venv = candidate, venv
    return candidate
  end

  vim.notify("Error: could not find site-packages", vim.log.levels.ERROR, { title = "Venv Grep" })
end
-- A helper function to get a clean list of importable packages.
local function get_all_packages(site_packages_path)
  local packages = {}
  local entries = vim.fn.readdir(site_packages_path)

  for _, entry in ipairs(entries) do
    -- We filter out metadata, egg-info, and cache directories to get a clean list of
    -- actual Python packages that are directories.
    if not (entry:match("%.dist%-info$") or entry:match("%.egg%-info$") or entry == "__pycache__") then
      if vim.fn.isdirectory(site_packages_path .. "/" .. entry) == 1 then
        table.insert(packages, entry)
      end
    end
  end
  return packages
end

-- The main function that orchestrates the picker workflow.
local function select_and_grep_package()
  -- 2. Find the site-packages directory.
  local site_packages_path = find_site_packages()
  if not site_packages_path then
    return -- Error message is handled inside the function.
  end

  -- 3. Get the list of all packages.
  local packages = get_all_packages(site_packages_path)
  if vim.tbl_isempty(packages) then
    vim.notify("No packages found in '" .. site_packages_path .. "'", vim.log.levels.WARN, { title = "Venv Grep" })
    return
  end

  -- 4. Open the first picker to let the user select a package.
  snacks.picker.select(packages, {}, function(selected_package)
    if not selected_package then
      vim.notify("No package selected.", vim.log.levels.INFO, { title = "Venv Grep" })
      return
    end

    -- Construct the full path to the chosen package.
    local search_path = site_packages_path .. "/" .. selected_package

    -- 5. Open the second picker (grep) scoped to the selected package directory.
    snacks.picker.grep({
      title = "Grep in " .. selected_package,
      dirs = { search_path }, -- This is the crucial part!
      ignored = true, -- allow searching in files in .gitignore
    })
  end)
end

local function grep_or_select_package()
  local site_packages = find_site_packages()
  if not site_packages then
    return
  end

  -- Get full path of current buffer
  local bufpath = vim.api.nvim_buf_get_name(0)
  -- Check if it's under site-packages
  if bufpath:sub(1, #site_packages + 1) == site_packages .. "/" then
    -- Strip off the site_packages prefix, get the package name
    local rel = bufpath:sub(#site_packages + 2)
    local pkg = rel:match("^([^/]+)")
    if pkg then
      local pkg_path = site_packages .. "/" .. pkg
      snacks.picker.grep({
        title = "Grep in " .. pkg,
        dirs = { pkg_path },
        ignored = true,
      })
      return
    end
  end

  -- Fallback: two-stage selector
  select_and_grep_package()
end

-- Create a user command and mapping for the new behavior
vim.api.nvim_create_user_command("GrepVenvCurrentOrSelect", grep_or_select_package, {
  desc = "If in a venv package, grep it; otherwise select a package to grep",
})

vim.keymap.set("n", "<leader>ps", "<Cmd>GrepVenvCurrentOrSelect<CR>", {
  noremap = true,
  silent = true,
  desc = "Smart grep: current venv package or select one",
})

-- Create a user command so you can run this with `:GrepVenvSelectPackage`.
vim.api.nvim_create_user_command("GrepVenvSelectPackage", select_and_grep_package, {
  desc = "Select a venv package and grep in it",
})

vim.keymap.set("n", "<leader>pS", "<Cmd>GrepVenvSelectPackage<CR>", {
  noremap = true,
  silent = true,
  desc = "Select and Grep in venv package",
})
