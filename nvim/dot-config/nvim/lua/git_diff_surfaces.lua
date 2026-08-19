local M = {}

---@type table<integer, boolean>
local inlay_hints_was_enabled = {}

---@param message string
---@param level? integer
local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Git diff" })
end

---@param args string[]
function M.open_codediff(args)
  vim.cmd({ cmd = "CodeDiff", args = args })
end

---@param title string
---@param callback fun(ref: string)
function M.pick_branch(title, callback)
  Snacks.picker.git_branches({
    all = true,
    title = title,
    ---@param picker snacks.Picker
    ---@param item snacks.picker.Item
    confirm = function(picker, item)
      local ref = item and (item.branch or item.commit)
      picker:close()
      if ref then
        vim.schedule(function()
          callback(ref)
        end)
      end
    end,
  })
end

---@param title string
---@param current_file boolean
---@param callback fun(ref: string)
function M.pick_commit(title, current_file, callback)
  local picker = current_file and Snacks.picker.git_log_file or Snacks.picker.git_log
  picker({
    title = title,
    ---@param active_picker snacks.Picker
    ---@param item snacks.picker.Item
    confirm = function(active_picker, item)
      local ref = item and item.commit
      active_picker:close()
      if ref then
        vim.schedule(function()
          callback(ref)
        end)
      end
    end,
  })
end

---@param ref string
function M.open_history_from_commit(ref)
  M.open_codediff({ "history", ref .. "..HEAD", "--reverse" })
end

---@param ref string
function M.open_history_from_branch(ref)
  local root = vim.fs.root(0, { ".git" }) or vim.fn.getcwd()
  ---@param result vim.SystemCompleted
  vim.system({ "git", "merge-base", ref, "HEAD" }, { cwd = root, text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        notify("Could not find a merge base for " .. ref, vim.log.levels.ERROR)
        return
      end

      local merge_base = vim.trim(result.stdout or "")
      if merge_base == "" then
        notify("Could not find a merge base for " .. ref, vim.log.levels.ERROR)
        return
      end

      M.open_codediff({ "history", merge_base .. "..HEAD", "--reverse" })
    end)
  end)
end

---@param bufnr integer
local function disable_inlay_hints(bufnr)
  if not vim.lsp.inlay_hint then
    return
  end

  if vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }) then
    inlay_hints_was_enabled[bufnr] = true
    vim.lsp.inlay_hint.enable(false, { bufnr = bufnr })
  end
end

---@param bufnr integer
local function restore_inlay_hints(bufnr)
  if inlay_hints_was_enabled[bufnr] and vim.lsp.inlay_hint then
    vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
  end
  inlay_hints_was_enabled[bufnr] = nil
end

---@param bufnr integer
---@return boolean toggled
local function toggle_overlay_with_hints(bufnr)
  local mini_diff = require("mini.diff")
  local data = mini_diff.get_buf_data(bufnr)
  if not data then
    return false
  end

  if data.overlay then
    mini_diff.toggle_overlay(bufnr)
    restore_inlay_hints(bufnr)
  else
    disable_inlay_hints(bufnr)
    mini_diff.toggle_overlay(bufnr)
  end
  return true
end

---@param ref string
function M.open_overlay(ref)
  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" then
    notify("The current buffer has no file to compare", vim.log.levels.WARN)
    return
  end

  local root = vim.fs.root(bufnr, { ".git" })
  if not root then
    notify("The current buffer is not inside a Git repository", vim.log.levels.WARN)
    return
  end

  local relative_path = vim.fs.relpath(root, path)
  if not relative_path then
    notify("Could not resolve the current file inside its Git repository", vim.log.levels.ERROR)
    return
  end

  ---@param result vim.SystemCompleted
  vim.system({ "git", "show", ref .. ":" .. relative_path }, { cwd = root, text = true }, function(result)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      if result.code ~= 0 then
        notify("Could not read " .. relative_path .. " at " .. ref, vim.log.levels.ERROR)
        return
      end

      local mini_diff = require("mini.diff")
      mini_diff.set_ref_text(bufnr, result.stdout or "")
      local data = mini_diff.get_buf_data(bufnr)
      if data and not data.overlay then
        toggle_overlay_with_hints(bufnr)
      elseif data then
        disable_inlay_hints(bufnr)
      end
    end)
  end)
end

---@return boolean closed
function M.close_overlay()
  local bufnr = vim.api.nvim_get_current_buf()
  local mini_diff = require("mini.diff")
  local data = mini_diff.get_buf_data(bufnr)
  if not data or not data.overlay then
    return false
  end

  toggle_overlay_with_hints(bufnr)
  return true
end

---@return boolean toggled
function M.toggle_overlay()
  return toggle_overlay_with_hints(vim.api.nvim_get_current_buf())
end

return M
