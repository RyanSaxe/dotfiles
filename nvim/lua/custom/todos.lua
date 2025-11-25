-- TODO management utilities for filesystem-based TODO files
-- Replaces Snacks scratch files with branch-specific TODO.local/ directories

local M = {}

-- Get the git utilities module for branch detection
local git_utils = require("custom.git.utils")

-- Sanitize branch name for filesystem use
-- Replaces special characters with hyphens and converts to lowercase
-- @param branch string: The git branch name to sanitize
-- @return string|nil: Sanitized branch name, or nil if invalid
local function sanitize_branch_name(branch)
  if not branch or branch == "" then
    return nil
  end

  -- Replace forward slashes, spaces, and other special chars with hyphens
  -- Convert to lowercase for consistency
  local sanitized = branch:lower()
  sanitized = sanitized:gsub('[/%s*?"<>|\\:]+', "-")
  -- Remove leading/trailing hyphens
  sanitized = sanitized:gsub("^-+", ""):gsub("-+$", "")

  return sanitized
end

-- Ensure directory exists, create if it doesn't
-- @param path string: The directory path to check/create
-- @return boolean: true if directory exists or was created successfully
local function ensure_directory(path)
  local stat = vim.loop.fs_stat(path)
  if not stat then
    local success = vim.fn.mkdir(path, "p")
    if success == 0 then
      vim.notify("Failed to create directory: " .. path, vim.log.levels.ERROR)
      return false
    end
  end
  return true
end

-- Ensure file exists, create empty file if it doesn't
-- @param filepath string: The file path to check/create
-- @return boolean: true if file exists or was created successfully
local function ensure_file(filepath)
  local stat = vim.loop.fs_stat(filepath)
  if not stat then
    -- File doesn't exist, create it
    local file = io.open(filepath, "w")
    if not file then
      vim.notify("Failed to create file: " .. filepath, vim.log.levels.ERROR)
      return false
    end
    file:close()
  end
  return true
end

-- Open the TODO file for the current context
-- Creates necessary directories and files as needed
-- If in a git repository, creates TODO.local/[branch]/SUMMARY.md
-- Otherwise, creates TODO.local/SUMMARY.md
M.open_todo = function()
  -- Get current working directory (project root)
  local cwd = vim.fn.getcwd()

  -- Ensure TODO.local/ directory exists in current working directory
  local todos_dir = cwd .. "/TODO.local"
  if not ensure_directory(todos_dir) then
    return
  end

  local todo_file

  -- Check if we're in a git repository using Snacks
  -- This is more reliable than checking the output of git commands
  if Snacks.git.get_root() ~= nil then
    -- We're in a git repository, get the current branch
    local branch = git_utils.get_current_branch()
    if branch and branch ~= "" and not branch:match("^fatal:") then
      local sanitized_branch = sanitize_branch_name(branch)
      if sanitized_branch then
        -- Create branch-specific subdirectory
        local branch_dir = todos_dir .. "/" .. sanitized_branch
        if not ensure_directory(branch_dir) then
          return
        end
        todo_file = branch_dir .. "/SUMMARY.md"
      else
        -- Fallback if sanitization fails
        todo_file = todos_dir .. "/SUMMARY.md"
      end
    else
      -- Edge case: in git repo but no valid branch
      todo_file = todos_dir .. "/SUMMARY.md"
    end
  else
    -- Not in a git repository - use root TODO.local/SUMMARY.md
    todo_file = todos_dir .. "/SUMMARY.md"
  end

  -- Ensure the TODO file exists before opening
  if not ensure_file(todo_file) then
    return
  end

  -- Open the TODO file
  vim.cmd("edit " .. vim.fn.fnameescape(todo_file))
end

return M
