-- Git diff utilities for codediff.nvim integration
-- Provides functions for opening diffs against commits or branches

local M = {}
local git_utils = require("custom.git.utils")
local pickers = require("custom.git.pickers")

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
  vim.cmd(string.format("CodeDiff file %s", commit))
end

-- Open codediff for current file against a branch
function M.file_diff_branch(branch)
  local relpath = vim.fn.expand("%:.")
  if relpath == "" then
    vim.notify("No file in current buffer", vim.log.levels.WARN)
    return
  end
  -- Use origin/<branch> to compare against remote
  vim.cmd(string.format("CodeDiff file origin/%s", branch))
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
  vim.cmd(string.format("CodeDiff %s", commit))
end

-- Open codediff explorer showing all changes against a branch
function M.all_diff_branch(branch)
  -- Fetch first to ensure we have latest, then open diff
  git_utils.fetch_origin(function()
    -- Use origin/<branch> to compare against remote
    vim.cmd(string.format("CodeDiff origin/%s", branch))
  end)
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

return M
