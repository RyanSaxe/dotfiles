local M = {}

---@type table<integer, boolean>
local inlay_hints_was_enabled = {}

---@param root string
---@param args string[]
---@return string?
local function git_output(root, args)
  local command = { "git" }
  vim.list_extend(command, args)
  local result = vim.system(command, { cwd = root, text = true }):wait()
  if result.code ~= 0 then
    return nil
  end

  local output = vim.trim(result.stdout or "")
  return output ~= "" and output or nil
end

---@param root string
---@param ref string
---@return boolean
local function ref_exists(root, ref)
  local result = vim
    .system({ "git", "rev-parse", "--verify", "--quiet", ref }, {
      cwd = root,
      text = true,
    })
    :wait()
  return result.code == 0
end

---@param root string
---@return string?
local function branch_created_from(root)
  local branch = git_output(root, { "symbolic-ref", "--quiet", "--short", "HEAD" })
  if not branch then
    return nil
  end

  local configured_base = git_output(root, { "config", "--get", "branch." .. branch .. ".workmux-base" })
  if configured_base and configured_base ~= "HEAD" then
    return configured_base
  end

  local reflog = git_output(root, { "reflog", "show", "--format=%gs", branch })
  if not reflog then
    return nil
  end

  for entry in reflog:gmatch("[^\r\n]+") do
    local created_from = entry:match("^branch: Created from (.+)$")
    if created_from and ref_exists(root, "refs/heads/" .. created_from) then
      return created_from
    end
  end

  return nil
end

---@return string
local function base_branch()
  local root = vim.fs.root(0, { ".git" }) or vim.fn.getcwd()
  local created_from = branch_created_from(root)
  if created_from then
    return created_from
  end

  local remote_head = git_output(root, {
    "symbolic-ref",
    "--quiet",
    "--short",
    "refs/remotes/origin/HEAD",
  })
  local branch = remote_head and remote_head:match("^[^/]+/(.+)$")
  if branch and branch ~= "" then
    return branch
  end

  return "main"
end

---@param branch string
---@param target string
---@return boolean
local function is_base_branch(branch, target)
  return branch == target or branch == "origin/" .. target or branch == "remotes/origin/" .. target
end

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
  local target = base_branch()
  Snacks.picker.git_branches({
    all = true,
    title = title,
    ---@param picker snacks.Picker
    on_show = function(picker)
      for index, item in ipairs(picker:items()) do
        if item.branch and is_base_branch(item.branch, target) then
          picker.list:view(index)
          Snacks.picker.actions.list_scroll_center(picker)
          break
        end
      end
    end,
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
    on_show = function(active_picker)
      active_picker.list:view(2)
    end,
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
