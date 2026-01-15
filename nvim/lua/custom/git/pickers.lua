-- Git pickers using snacks.nvim for commit and branch selection
-- Provides unified interface for selecting commits or branches with diff previews

local M = {}
local git_utils = require("custom.git.utils")

--- Open commit picker with diff preview
-- Commits are sorted by recency (first = HEAD, second = HEAD~1, etc.)
-- @param on_select function(commit: string) Called with selected commit hash
-- @param opts table|nil Optional picker options:
--   - current_file: boolean - Only show commits for current file (default: false)
--   - title: string - Custom picker title
function M.pick_commit(on_select, opts)
  opts = opts or {}

  local picker_opts = {
    title = opts.title or "Select Commit",
    -- git_log already shows commits in reverse chronological order (most recent first)
    -- Preview shows full diff via `git show <commit>`
    confirm = function(picker, item)
      picker:close()
      if item and item.commit then
        on_select(item.commit)
      end
    end,
  }

  -- For current file only
  if opts.current_file then
    picker_opts.current_file = true
    Snacks.picker.git_log_file(picker_opts)
  else
    Snacks.picker.git_log(picker_opts)
  end
end

--- Open branch picker with base branch highlighted
-- Fetches from origin first to ensure all remote branches are visible
-- Base branch (origin/main or similar) is scrolled to view on open
-- @param on_select function(branch: string) Called with selected branch name (without origin/ prefix)
-- @param opts table|nil Optional picker options:
--   - title: string - Custom picker title
--   - include_local: boolean - Include local branches (default: true)
function M.pick_branch(on_select, opts)
  opts = opts or {}
  local base_branch = git_utils.get_base_branch()

  -- Fetch first to ensure remote branches are up to date
  git_utils.fetch_origin(function()
    Snacks.picker.git_branches({
      title = opts.title or "Select Branch",
      all = true, -- Include remote branches
      confirm = function(picker, item)
        picker:close()
        if item then
          -- item.branch is the branch name, or item.commit for detached HEAD
          local branch = item.branch or item.commit
          -- Strip "origin/" prefix if present for consistency
          branch = branch:gsub("^origin/", "")
          on_select(branch)
        end
      end,
      on_show = function(picker)
        -- Find and scroll to base branch
        for i, item in ipairs(picker:items()) do
          local branch = item.branch or ""
          -- Match base branch (could be "main", "origin/main", etc.)
          if branch == base_branch or branch == "origin/" .. base_branch then
            picker.list:view(i)
            Snacks.picker.actions.list_scroll_center(picker)
            break
          end
        end
      end,
    })
  end)
end

return M
