-- This is intentionally a surface handoff, not a comment or ref-resolution
-- adapter. Snacks owns GitHub review actions; CodeDiff owns local navigation.
local M = {}

local switch_key = "<leader>gdr"

---@class ReviewSurfaceContext
---@field repo string
---@field number integer
---@field path? string
---@field base? string
---@field head? string
---@field source_tab? integer

---@class ReviewSurfaceEventData
---@field tabpage? integer
---@field path? string

---@class ReviewSurfaceEvent
---@field data? ReviewSurfaceEventData

---@type table<integer, ReviewSurfaceContext>
local contexts = {}
---@type table<integer, boolean>
local codediff_tabs = {}
---@type ReviewSurfaceContext?
local pending_context
local did_setup = false

---@param message string
---@param level? integer
local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Review surfaces" })
end

---@param root string
---@param path string
---@return string
local function relative_path(root, path)
  local normalized_root = vim.fs.normalize(root):gsub("/$", "")
  local normalized_path = vim.fs.normalize(path)
  local prefix = normalized_root .. "/"
  if normalized_path:sub(1, #prefix) == prefix then
    return normalized_path:sub(#prefix + 1)
  end
  return normalized_path
end

---@param picker snacks.Picker
---@return ReviewSurfaceContext?
local function context_from_picker(picker)
  local item = picker:current()
  if not item then
    notify("No PR diff file is selected", vim.log.levels.WARN)
    return nil
  end

  local gh_item = item.gh_item
  local preview_buf = picker.preview and picker.preview.win and picker.preview.win.buf
  local buffer_meta = preview_buf and vim.b[preview_buf].snacks_gh or nil
  if not gh_item and buffer_meta then
    gh_item = buffer_meta
  end

  if not gh_item or not gh_item.repo or not gh_item.number then
    notify("The selected diff has no PR context", vim.log.levels.WARN)
    return nil
  end

  local number = tonumber(gh_item.number)
  if not number then
    notify("The selected diff has no valid PR number", vim.log.levels.WARN)
    return nil
  end

  ---@type ReviewSurfaceContext
  local context = {
    repo = gh_item.repo,
    number = number,
    path = item.file,
    base = gh_item.baseRefName,
    head = gh_item.headRefName,
  }

  if not context.path or context.path == "" then
    notify("The selected diff has no local file path", vim.log.levels.WARN)
    return nil
  end

  if not context.base or not context.head then
    notify("Could not resolve the PR's base and head refs", vim.log.levels.ERROR)
    return nil
  end

  return context
end

---@param context ReviewSurfaceContext
---@return string
local function review_range(context)
  assert(context.base and context.head)
  return context.base .. "..." .. context.head
end

---@param tabpage integer
local function map_tab(tabpage)
  if not vim.api.nvim_tabpage_is_valid(tabpage) then
    return
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    local buf = vim.api.nvim_win_get_buf(win)
    vim.keymap.set({ "n", "x" }, switch_key, function()
      M.to_snacks(tabpage)
    end, {
      buffer = buf,
      desc = "Open GitHub PR diff",
      silent = true,
    })
  end
end

---@param tabpage integer
---@param source_tab integer?
local function close_source_tab(tabpage, source_tab)
  if not source_tab or source_tab == tabpage or not vim.api.nvim_tabpage_is_valid(source_tab) then
    return
  end

  local tab_number = vim.api.nvim_tabpage_get_number(source_tab)
  if vim.api.nvim_tabpage_is_valid(tabpage) then
    vim.cmd(tab_number .. "tabclose")
  end
end

---@param event ReviewSurfaceEvent
local function on_codediff_open(event)
  local data = event.data
  if not data then
    return
  end

  local tabpage = data.tabpage
  if not tabpage then
    return
  end

  codediff_tabs[tabpage] = true

  local context = pending_context
  if context then
    contexts[tabpage] = context
    local source_tab = context.source_tab
    pending_context = nil
    vim.schedule(function()
      close_source_tab(tabpage, source_tab)
    end)
  end

  if contexts[tabpage] then
    map_tab(tabpage)
  end
end

---@param event ReviewSurfaceEvent
local function on_codediff_file_select(event)
  local data = event.data
  if not data then
    return
  end

  local tabpage = data.tabpage
  local path = data.path
  if not tabpage or not path then
    return
  end

  local context = contexts[tabpage]
  if context then
    context.path = path
    map_tab(tabpage)
  end
end

---@param event ReviewSurfaceEvent
local function on_codediff_close(event)
  local data = event.data
  if not data then
    return
  end

  local tabpage = data.tabpage
  if not tabpage then
    return
  end

  codediff_tabs[tabpage] = nil
  contexts[tabpage] = nil
end

function M.setup()
  if did_setup then
    return
  end
  did_setup = true

  local group = vim.api.nvim_create_augroup("review_surfaces", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeDiffOpen",
    group = group,
    callback = on_codediff_open,
  })
  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeDiffFileSelect",
    group = group,
    callback = on_codediff_file_select,
  })
  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeDiffClose",
    group = group,
    callback = on_codediff_close,
  })
end

function M.from_snacks()
  local pickers = require("snacks.picker").get({ source = "gh_diff" })
  local picker = pickers[1]
  if not picker then
    notify("No active Snacks PR diff picker", vim.log.levels.WARN)
    return
  end

  local context = context_from_picker(picker)
  if not context then
    return
  end

  local root = picker:cwd()
  if not root or root == "" then
    notify("The PR diff has no local repository", vim.log.levels.ERROR)
    return
  end

  local path = context.path
  if not path then
    notify("The PR diff has no local file path", vim.log.levels.ERROR)
    return
  end

  context.path = relative_path(root, path)
  local local_path = vim.fs.joinpath(root, context.path)
  pending_context = context
  picker:close()

  vim.schedule(function()
    vim.cmd("tabnew " .. vim.fn.fnameescape(local_path))
    context.source_tab = vim.api.nvim_get_current_tabpage()
    vim.cmd("CodeDiff file " .. vim.fn.fnameescape(review_range(context)))
  end)
end

---@param tabpage integer?
function M.to_snacks(tabpage)
  tabpage = tabpage or vim.api.nvim_get_current_tabpage()
  local context = contexts[tabpage]
  if not context then
    notify("This CodeDiff session is not attached to a PR", vim.log.levels.WARN)
    return
  end
  if not context.path or context.path == "" then
    notify("Select a file in CodeDiff before opening the PR diff", vim.log.levels.WARN)
    return
  end

  require("snacks.picker").gh_diff({
    pr = context.number,
    repo = context.repo,
    group = false,
    pattern = context.path,
  })
end

---@param tabpage integer?
---@return boolean
function M.is_codediff_tab(tabpage)
  tabpage = tabpage or vim.api.nvim_get_current_tabpage()
  return codediff_tabs[tabpage] == true
end

return M
