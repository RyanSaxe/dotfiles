-- Git diff utilities for codediff.nvim integration
-- Provides functions for opening diffs against commits or branches

local M = {}
local git_utils = require("custom.git.utils")
local pickers = require("custom.git.pickers")

local git_log_field_separator = string.char(31)

local function codediff(...)
  local args = { ... }
  for i, arg in ipairs(args) do
    args[i] = vim.fn.fnameescape(arg)
  end
  vim.cmd("CodeDiff " .. table.concat(args, " "))
end

local function git_systemlist(args, cwd)
  local cmd = { "git" }
  if cwd then
    vim.list_extend(cmd, { "-C", cwd })
  end
  vim.list_extend(cmd, args)

  local lines = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    local message = table.concat(lines or {}, "\n")
    if message == "" then
      message = "git command failed: " .. table.concat(args, " ")
    end
    return nil, message
  end

  return lines, nil
end

local function git_line(args, cwd)
  local lines, err = git_systemlist(args, cwd)
  if err then
    return nil, err
  end

  return vim.trim(lines[1] or ""), nil
end

local function current_git_root()
  return git_line({ "rev-parse", "--show-toplevel" })
end

local function resolve_commit(git_root, rev)
  return git_line({ "rev-parse", "--verify", rev .. "^{commit}" }, git_root)
end

local function ref_exists(git_root, ref)
  local _, err = git_systemlist({ "rev-parse", "--verify", "--quiet", ref }, git_root)
  return err == nil
end

local function resolve_branch_ref(git_root, branch)
  if not branch or branch == "" then
    return branch
  end

  if branch:match("^origin/") then
    if ref_exists(git_root, branch) then
      return branch
    end

    local local_branch = branch:gsub("^origin/", "")
    if ref_exists(git_root, local_branch) then
      return local_branch
    end

    return branch
  end

  local remote_branch = "origin/" .. branch
  if ref_exists(git_root, remote_branch) then
    return remote_branch
  end

  if ref_exists(git_root, branch) then
    return branch
  end

  return remote_branch
end

local function short_commit(git_root, rev)
  return git_line({ "rev-parse", "--short", rev }, git_root)
end

local function commit_metadata_range(git_root, base, target)
  local format = "%H%x1f%h%x1f%s"
  local lines, err = git_systemlist({ "log", "--reverse", "--format=" .. format, base .. ".." .. target }, git_root)
  if err then
    return nil, err
  end

  local commits = {}
  for _, line in ipairs(lines) do
    local full, short, subject =
      line:match("^(.-)" .. git_log_field_separator .. "(.-)" .. git_log_field_separator .. "(.*)$")
    if full and full ~= "" then
      commits[#commits + 1] = {
        hash = full,
        short = short,
        subject = subject ~= "" and subject or "(no subject)",
      }
    end
  end

  return commits, nil
end

local function build_stack(git_root, base_rev, target_rev, source_label)
  local base_hash, base_err = resolve_commit(git_root, base_rev)
  if base_err then
    return nil, base_err
  end

  local target_hash, target_err = resolve_commit(git_root, target_rev)
  if target_err then
    return nil, target_err
  end

  local commits, log_err = commit_metadata_range(git_root, base_hash, target_hash)
  if log_err then
    return nil, log_err
  end
  if #commits == 0 then
    return nil, "No commits to review in " .. source_label
  end

  local pairs = {}
  local previous = base_hash
  for index, commit in ipairs(commits) do
    pairs[#pairs + 1] = {
      index = index,
      total = #commits,
      left = previous,
      right = commit.hash,
      commit = commit.hash,
      short = commit.short,
      subject = commit.subject,
      label = string.format("%d/%d %s %s", index, #commits, commit.short, commit.subject),
    }
    previous = commit.hash
  end

  local stack = {
    git_root = git_root,
    base = base_hash,
    target = target_hash,
    source_label = source_label,
    index = 1,
    pairs = pairs,
  }

  return stack, nil
end

local function attach_stack_to_current_tab(stack, focus_direction)
  local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
  if not ok then
    return nil
  end

  local tabpage = vim.api.nvim_get_current_tabpage()
  local session = lifecycle.get_session(tabpage)
  if not session then
    return nil
  end

  session.custom_stack_review = stack
  session.custom_stack_focus_direction = focus_direction or "next"
  return tabpage
end

local function close_tabpage(tabpage)
  if not tabpage or not vim.api.nvim_tabpage_is_valid(tabpage) then
    return
  end
  if tabpage == vim.api.nvim_get_current_tabpage() then
    return
  end

  local tab_number = vim.api.nvim_tabpage_get_number(tabpage)
  pcall(vim.cmd, tab_number .. "tabclose")
end

function M.notify_stack_position(stack)
  if not stack or not stack.pairs then
    return
  end

  local pair = stack.pairs[stack.index]
  if not pair then
    return
  end

  local message = "Stack " .. pair.label
  vim.api.nvim_echo({ { message, "DiagnosticInfo" } }, false, {})
  vim.notify(message, vim.log.levels.INFO)
end

-- Check if a codediff tab is currently open
-- Looks for buffers with the vscode-diff:// scheme that codediff uses
function M.is_codediff_open()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if name:match("^vscode%-diff://") then
      return true
    end
  end
  return false
end

--------------------------------------------------------------------------------
-- File Diff: Compare current buffer against a ref using codediff
--------------------------------------------------------------------------------

-- Open codediff for current file against a commit
function M.file_diff_commit(commit)
  local relpath = vim.fn.expand("%:.")
  if relpath == "" then
    vim.notify("No file in current buffer", vim.log.levels.WARN)
    return
  end
  -- CodeDiff file <ref> compares current buffer against that ref
  codediff("file", commit)
end

-- Open codediff for current file against a branch
function M.file_diff_branch(branch)
  local relpath = vim.fn.expand("%:.")
  if relpath == "" then
    vim.notify("No file in current buffer", vim.log.levels.WARN)
    return
  end
  local ref = git_utils.resolve_branch_ref(branch)
  codediff("file", ref)
end

-- Pick a commit and open file diff
function M.pick_file_diff_commit()
  pickers.pick_commit(function(commit)
    M.file_diff_commit(commit)
  end, {
    title = "File Diff: Select Commit",
    current_file = true, -- Only show commits that touched this file
  })
end

-- Pick a branch and open file diff
function M.pick_file_diff_branch()
  pickers.pick_branch(function(branch)
    M.file_diff_branch(branch)
  end, {
    title = "File Diff: Select Branch",
  })
end

--------------------------------------------------------------------------------
-- All Files Diff: Compare all files against a ref using codediff explorer
--------------------------------------------------------------------------------

-- Open codediff explorer showing all changes against a commit
function M.all_diff_commit(commit)
  -- CodeDiff <ref> compares working tree against that ref
  codediff(commit)
end

-- Open codediff explorer showing all changes against a branch
function M.all_diff_branch(branch)
  local ref = git_utils.resolve_branch_ref(branch)
  codediff(ref)
end

-- Fetch base branch and open PR-style diff against the merge-base.
function M.fetch_and_diff(base_branch)
  base_branch = base_branch or git_utils.get_base_branch()

  git_utils.fetch_origin(function()
    local ref = git_utils.resolve_branch_ref(base_branch)
    if not git_utils.ref_exists(ref) then
      vim.notify("Unable to open CodeDiff because base ref is unavailable: " .. ref, vim.log.levels.ERROR)
      return
    end

    codediff(ref .. "...")
  end, { base_branch }, { notify_success = false, use_cached_on_failure = true })
end

-- Pick a commit and open all-files diff
function M.pick_all_diff_commit()
  pickers.pick_commit(function(commit)
    M.all_diff_commit(commit)
  end, {
    title = "All Files Diff: Select Commit",
  })
end

-- Pick a branch and open all-files diff
function M.pick_all_diff_branch()
  pickers.pick_branch(function(branch)
    M.all_diff_branch(branch)
  end, {
    title = "All Files Diff: Select Branch",
  })
end

--------------------------------------------------------------------------------
-- Stack Review: Review adjacent commit pairs in one active CodeDiff tab
--------------------------------------------------------------------------------

function M.open_stack_pair(stack, index, opts)
  opts = opts or {}
  if not stack or type(stack.pairs) ~= "table" or #stack.pairs == 0 then
    vim.notify("No stack review pairs available", vim.log.levels.WARN)
    return false
  end
  if index < 1 or index > #stack.pairs then
    vim.notify("Stack review pair is out of range", vim.log.levels.WARN)
    return false
  end

  local next_stack = vim.deepcopy(stack)
  next_stack.index = index
  local pair = next_stack.pairs[index]
  local git = require("codediff.core.git")

  git.get_diff_revisions(pair.left, pair.right, next_stack.git_root, function(err, status_result)
    vim.schedule(function()
      if err then
        vim.notify("Failed to open stack pair: " .. err, vim.log.levels.ERROR)
        return
      end

      local view = require("codediff.ui.view")
      view.create({
        mode = "explorer",
        git_root = next_stack.git_root,
        original_path = "",
        modified_path = "",
        original_revision = pair.left,
        modified_revision = pair.right,
        explorer_data = {
          status_result = status_result,
        },
      }, "")

      local tabpage = attach_stack_to_current_tab(next_stack, opts.focus_direction)
      if tabpage then
        close_tabpage(opts.close_tabpage)
        M.notify_stack_position(next_stack)
        vim.schedule(function()
          vim.api.nvim_exec_autocmds("User", {
            pattern = "CodeDiffStackPairOpen",
            modeline = false,
            data = {
              tabpage = tabpage,
            },
          })
        end)
      end
    end)
  end)

  return true
end

function M.stack_review_commit(commit)
  local git_root, root_err = current_git_root()
  if root_err then
    vim.notify(root_err, vim.log.levels.ERROR)
    return
  end

  local base_hash, base_err = resolve_commit(git_root, commit)
  if base_err then
    vim.notify(base_err, vim.log.levels.ERROR)
    return
  end

  local base_short = short_commit(git_root, base_hash) or commit
  local stack, stack_err = build_stack(git_root, base_hash, "HEAD", base_short .. "..HEAD")
  if stack_err then
    vim.notify(stack_err, vim.log.levels.INFO)
    return
  end

  M.open_stack_pair(stack, 1, { focus_direction = "next" })
end

function M.stack_review_branch(branch)
  local git_root, root_err = current_git_root()
  if root_err then
    vim.notify(root_err, vim.log.levels.ERROR)
    return
  end

  local ref = resolve_branch_ref(git_root, branch)
  local merge_base, merge_err = git_line({ "merge-base", ref, "HEAD" }, git_root)
  if merge_err then
    vim.notify("Failed to find merge-base for " .. ref .. ": " .. merge_err, vim.log.levels.ERROR)
    return
  end

  local stack, stack_err = build_stack(git_root, merge_base, "HEAD", ref .. "..HEAD")
  if stack_err then
    vim.notify(stack_err, vim.log.levels.INFO)
    return
  end

  M.open_stack_pair(stack, 1, { focus_direction = "next" })
end

function M.pick_stack_review_commit()
  pickers.pick_commit(function(commit)
    M.stack_review_commit(commit)
  end, {
    title = "Stack Review: Select Base Commit",
  })
end

function M.pick_stack_review_branch()
  pickers.pick_branch(function(branch)
    M.stack_review_branch(branch)
  end, {
    title = "Stack Review: Select Base Branch",
  })
end

local function format_stack_item(item)
  local current = item.current == true
  local ret = {}
  local index_text = string.format("%d/%d", item.pair.index, item.pair.total)

  ret[#ret + 1] = { current and "▶ " or "  ", current and "SnacksPickerSelected" or "Comment" }
  ret[#ret + 1] = { Snacks.picker.util.align(index_text, 5) .. " ", current and "DiagnosticInfo" or "Comment" }
  ret[#ret + 1] = { item.pair.short .. " ", current and "DiagnosticHint" or "Comment" }
  ret[#ret + 1] = { item.pair.subject, current and "SnacksPickerSelected" or "Normal" }

  return ret
end

local function preview_stack_item(git_root)
  return function(ctx)
    ctx.preview:reset()
    local item = ctx.item
    if not item or not item.pair then
      return
    end

    local lines, err = git_systemlist({ "show", "--stat", "--oneline", "--decorate", item.pair.commit }, git_root)
    if err then
      lines = { err }
    end

    ctx.preview:set_lines(lines)
    ctx.preview:highlight({ ft = "git" })
  end
end

function M.open_stack_picker(stack, on_select)
  if not stack or type(stack.pairs) ~= "table" or #stack.pairs == 0 then
    vim.notify("No active CodeDiff stack review", vim.log.levels.WARN)
    return
  end

  local items = {}
  for index, pair in ipairs(stack.pairs) do
    items[#items + 1] = {
      text = pair.label,
      stack_index = index,
      pair = pair,
      current = index == stack.index,
    }
  end

  Snacks.picker({
    title = "CodeDiff Stack: " .. (stack.source_label or "commits"),
    items = items,
    layout = "custom_horizontal",
    format = format_stack_item,
    preview = preview_stack_item(stack.git_root),
    confirm = function(picker, item)
      picker:close()
      if item and item.stack_index then
        on_select(item.stack_index)
      end
    end,
    on_show = function(picker)
      for index, item in ipairs(picker:items()) do
        if item.stack_index == stack.index then
          picker.list:view(index)
          Snacks.picker.actions.list_scroll_center(picker)
          break
        end
      end
    end,
  })
end

return M
