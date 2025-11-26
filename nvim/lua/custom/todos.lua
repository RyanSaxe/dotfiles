-- TODO management utilities for filesystem-based TODO files
-- Replaces Snacks scratch files with branch-specific TODO.local/ directories
-- Also provides scanning functions for integrating project TODOs into the unified picker

local M = {}

-- Get the git utilities module for branch detection
local git_utils = require("custom.git.utils")

-- Constants for task parsing (matching Obsidian format)
local DATE_PATTERN = "📅%s*(%d%d%d%d%-%d%d%-%d%d)" -- Match 📅 YYYY-MM-DD
local TASK_PATTERN = "^%s*%-%s*%[%s%]%s*(.+)" -- Match - [ ] task text

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

-- ══════════════════════════════════════════════════════════════════════════════
-- PROJECT TODO SCANNING FUNCTIONS
-- These functions scan TODO.local/SUMMARY.md for incomplete tasks
-- Used by the unified task picker when opened from the dashboard
-- ══════════════════════════════════════════════════════════════════════════════

---Get today's date in YYYY-MM-DD format
---@return string today Today's date
local function get_today()
  return os.date("%Y-%m-%d")
end

---Parse due date from task text
---Looks for 📅 YYYY-MM-DD pattern in the task text
---@param text string Task text to parse
---@return string|nil date Date in YYYY-MM-DD format or nil if not found
local function parse_due_date(text)
  return text:match(DATE_PATTERN)
end

---Calculate days between two dates
---@param date1 string Date in YYYY-MM-DD format
---@param date2 string Date in YYYY-MM-DD format
---@return number days Number of days (positive if date2 > date1)
local function days_between(date1, date2)
  local y1, m1, d1 = date1:match("(%d+)-(%d+)-(%d+)")
  local y2, m2, d2 = date2:match("(%d+)-(%d+)-(%d+)")

  local t1 = os.time({ year = y1, month = m1, day = d1, hour = 0 })
  local t2 = os.time({ year = y2, month = m2, day = d2, hour = 0 })

  return math.floor((t2 - t1) / 86400) -- 86400 seconds in a day
end

---Categorize a project task based on its due date
---Uses same color scheme as Obsidian tasks for consistency:
---  - "overdue" (red): due today or past
---  - "week" (orange): due within 7 days
---  - "later" (gray): due later or no date
---@param due_date string|nil Due date from task text
---@param today string Today's date
---@return string category Category: "overdue", "week", "later"
---@return number sort_priority Sort priority (lower = earlier in list)
local function categorize_project_task(due_date, today)
  if due_date then
    local days_diff = days_between(today, due_date)
    if days_diff <= 0 then
      -- Due today or overdue
      return "overdue", 2
    elseif days_diff <= 7 then
      -- Due within 7 days
      return "week", 3
    else
      -- Due later than 7 days
      return "later", 4
    end
  end

  -- No due date = treat as later (gray)
  return "later", 4
end

---Get the path to the current project's TODO file
---Returns the path without creating the file (for placeholder functionality)
---@return string|nil todo_path Path to TODO.local/[branch]/SUMMARY.md, or nil if not determinable
function M.get_todo_file_path()
  local cwd = vim.fn.getcwd()
  local todos_dir = cwd .. "/TODO.local"

  -- Check if we're in a git repository
  if Snacks.git.get_root() ~= nil then
    local branch = git_utils.get_current_branch()
    if branch and branch ~= "" and not branch:match("^fatal:") then
      local sanitized_branch = sanitize_branch_name(branch)
      if sanitized_branch then
        return todos_dir .. "/" .. sanitized_branch .. "/SUMMARY.md"
      end
    end
  end

  -- Fallback to root TODO.local/SUMMARY.md
  return todos_dir .. "/SUMMARY.md"
end

---Scan the project TODO file for incomplete tasks
---Uses same format as Obsidian: - [ ] task text 📅 YYYY-MM-DD
---@return table[] tasks Array of task items with file, line, text, due_date, category, sort_priority
function M.scan_project_todos()
  local todo_path = M.get_todo_file_path()
  if not todo_path then
    return {}
  end

  -- Check if file exists
  local stat = vim.loop.fs_stat(todo_path)
  if not stat then
    return {} -- File doesn't exist yet, no tasks
  end

  local today = get_today()
  local tasks = {}

  -- Read file line by line
  local file = io.open(todo_path, "r")
  if not file then
    return {}
  end

  local line_num = 0
  for line in file:lines() do
    line_num = line_num + 1

    -- Check if line matches task pattern
    local task_text = line:match(TASK_PATTERN)
    if task_text then
      -- Parse due date from task text
      local due_date = parse_due_date(task_text)

      -- Categorize and get sort priority
      local category, sort_priority = categorize_project_task(due_date, today)

      -- Add task to list
      table.insert(tasks, {
        file = todo_path, -- Absolute path for opening
        rel_path = "TODO.local", -- Short display name for project todos
        line = line_num,
        text = task_text,
        raw_line = line, -- Store raw line for toggling
        due_date = due_date,
        category = category,
        sort_priority = sort_priority,
        is_project_todo = true, -- Flag to identify project todos
      })
    end
  end
  file:close()

  -- Sort tasks by priority, then by due date
  table.sort(tasks, function(a, b)
    if a.sort_priority ~= b.sort_priority then
      return a.sort_priority < b.sort_priority
    end
    if a.due_date and b.due_date then
      return a.due_date < b.due_date
    elseif a.due_date then
      return true
    elseif b.due_date then
      return false
    end
    return a.line < b.line
  end)

  return tasks
end

---Check if any project or Obsidian tasks are due today or overdue
---Used by dashboard to show 🔴 indicator when urgent items exist
---@return boolean has_urgent True if any tasks are due today or overdue
function M.has_urgent_todos()
  -- Check project TODOs first (faster, local file)
  local project_tasks = M.scan_project_todos()
  for _, task in ipairs(project_tasks) do
    if task.category == "overdue" then
      return true
    end
  end

  -- Check Obsidian tasks if available
  -- Use pcall in case Obsidian is not set up
  local ok, obsidian_tasks = pcall(function()
    return require("custom.obsidian.tasks").scan_tasks()
  end)

  if ok and obsidian_tasks then
    for _, task in ipairs(obsidian_tasks) do
      -- Obsidian uses "overdue" and "today" categories for urgent items
      if task.category == "overdue" or task.category == "today" then
        return true
      end
    end
  end

  return false
end

return M
