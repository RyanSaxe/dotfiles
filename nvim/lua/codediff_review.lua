local M = {}

local review_key = "<localleader>c"
local lifecycle = require("codediff.ui.lifecycle")

---@type table<integer, table<integer, { value: boolean? }>>
local saved_scroll = {}
---@type table<integer, boolean>
local open_tabs = {}
local did_setup = false

---@param tabpage integer
---@return integer[]
local function session_buffers(tabpage)
  local original, modified = lifecycle.get_buffers(tabpage)
  local buffers = {} ---@type integer[]
  local candidates = { original, modified } ---@type (integer|nil)[]
  for _, bufnr in ipairs(candidates) do
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) and not vim.tbl_contains(buffers, bufnr) then
      buffers[#buffers + 1] = bufnr
    end
  end
  return buffers
end

---@param tabpage integer
---@param bufnr integer
local function disable_scroll(tabpage, bufnr)
  local states = saved_scroll[tabpage] or {}
  if not states[bufnr] then
    states[bufnr] = { value = vim.b[bufnr].snacks_scroll }
  end
  vim.b[bufnr].snacks_scroll = false
  saved_scroll[tabpage] = states
end

---@param tabpage integer
---@return boolean
local function configure_tab(tabpage)
  local session = lifecycle.get_session(tabpage)
  if not session then
    return false
  end

  lifecycle.set_tab_keymap(tabpage, "n", review_key, function()
    require("git_review").open_snacks(tabpage)
  end, { desc = "Open PR diff in Snacks" })

  for _, bufnr in ipairs(session_buffers(tabpage)) do
    disable_scroll(tabpage, bufnr)
  end
  return true
end

---@param tabpage integer
local function configure_later(tabpage)
  vim.defer_fn(function()
    if vim.api.nvim_tabpage_is_valid(tabpage) then
      configure_tab(tabpage)
    end
  end, 0)
end

---@param event vim.api.keyset.create_autocmd.callback_args
local function on_open(event)
  local data = event.data
  local tabpage = data and data.tabpage
  if type(tabpage) ~= "number" then
    return
  end

  open_tabs[tabpage] = true
  configure_later(tabpage)
end

---@param event vim.api.keyset.create_autocmd.callback_args
local function on_file_select(event)
  local data = event.data
  local tabpage = data and data.tabpage
  if type(tabpage) ~= "number" then
    return
  end

  open_tabs[tabpage] = true
  configure_later(tabpage)
end

---@param event vim.api.keyset.create_autocmd.callback_args
local function on_virtual_file_loaded(event)
  local data = event.data
  local bufnr = data and data.buf
  if type(bufnr) ~= "number" then
    return
  end

  local tabpage = lifecycle.find_tabpage_by_buffer(bufnr)
  if tabpage then
    configure_later(tabpage)
    return
  end

  for open_tabpage in pairs(open_tabs) do
    configure_later(open_tabpage)
  end
end

---@param event vim.api.keyset.create_autocmd.callback_args
local function on_close(event)
  local data = event.data
  local tabpage = data and data.tabpage
  if type(tabpage) ~= "number" then
    return
  end

  local states = saved_scroll[tabpage]
  saved_scroll[tabpage] = nil
  open_tabs[tabpage] = nil
  if not states then
    return
  end

  for bufnr, state in pairs(states) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.b[bufnr].snacks_scroll = state.value
    end
  end
end

function M.setup()
  if did_setup then
    return
  end
  did_setup = true

  local group = vim.api.nvim_create_augroup("codediff_review", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffOpen",
    callback = on_open,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffFileSelect",
    callback = on_file_select,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffVirtualFileLoaded",
    callback = on_virtual_file_loaded,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffClose",
    callback = on_close,
  })

  -- Virtual CodeDiff buffers are in the target window before the diff session
  -- exists, so mark them at read time. They are disposable and need no restore.
  vim.api.nvim_create_autocmd("BufReadCmd", {
    group = group,
    pattern = "codediff:///*",
    ---@param event vim.api.keyset.create_autocmd.callback_args
    callback = function(event)
      vim.b[event.buf].snacks_scroll = false
    end,
  })
end

return M
