-- TODO management utilities for filesystem-based TODO files
-- Replaces Snacks scratch files with branch-specific TODO.local/ directories
-- Also provides scanning functions for integrating project TODOs into the unified picker

local M = {}

-- Get the git utilities module for branch detection
local git_utils = require("custom.git.utils")

-- Constants for task parsing (matching Obsidian format)
local DATE_PATTERN = "📅%s*(%d%d%d%d%-%d%d%-%d%d)" -- Match 📅 YYYY-MM-DD
local TASK_PATTERN = "^%s*%-%s*%[%s%]%s*(.+)" -- Match - [ ] task text

-- ══════════════════════════════════════════════════════════════════════════════
-- PARTIAL EXCLUSION CONFIG
-- Folders that should be mostly excluded but allow specific files (like README.md)
-- These are global defaults; projects can override via TODO.local/config.lua
-- ══════════════════════════════════════════════════════════════════════════════
local DEFAULT_PARTIAL_EXCLUDES = {
  -- .claude folder contains non-task checklists, but README.md may have real tasks
  [".claude"] = { "README.md" },
}

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
---  - "overdue" (red): past due
---  - "due_today" (orange): due today
---  - "week" (green): due within 7 days
---  - "later" (gray): due later or no date
---@param due_date string|nil Due date from task text
---@param today string Today's date
---@return string category Category: "overdue", "due_today", "week", "later"
---@return number sort_priority Sort priority (lower = earlier in list)
---@return number|nil days_diff Days until/since due (negative = overdue, nil = no date)
local function categorize_project_task(due_date, today)
  if due_date then
    local days_diff = days_between(today, due_date)
    if days_diff < 0 then
      -- Overdue - red
      return "overdue", 2, days_diff
    elseif days_diff == 0 then
      -- Due today - orange
      return "due_today", 1, days_diff
    elseif days_diff <= 7 then
      -- Due within 7 days - green
      return "week", 3, days_diff
    else
      -- Due later than 7 days - gray
      return "later", 4, days_diff
    end
  end

  -- No due date = treat as later (gray)
  return "later", 4, nil
end

---Get the path to the current project's TODO directory
---Returns the directory path (not file path) for scanning all *.md files
---@return string|nil todo_dir Path to TODO.local/[branch]/, or nil if not determinable
function M.get_todo_dir_path()
  local cwd = vim.fn.getcwd()
  local todos_dir = cwd .. "/TODO.local"

  -- Check if we're in a git repository
  if Snacks.git.get_root() ~= nil then
    local branch = git_utils.get_current_branch()
    if branch and branch ~= "" and not branch:match("^fatal:") then
      local sanitized_branch = sanitize_branch_name(branch)
      if sanitized_branch then
        return todos_dir .. "/" .. sanitized_branch
      end
    end
  end

  -- Fallback to root TODO.local/
  return todos_dir
end

---Get the path to the current project's TODO file (SUMMARY.md)
---Returns the path without creating the file (for placeholder functionality)
---@return string|nil todo_path Path to TODO.local/[branch]/SUMMARY.md, or nil if not determinable
function M.get_todo_file_path()
  local todo_dir = M.get_todo_dir_path()
  if not todo_dir then
    return nil
  end
  return todo_dir .. "/SUMMARY.md"
end

---Load project-specific TODO configuration from TODO.local/config.lua
---Config is project-wide (not branch-specific) since exclusions apply to the whole project
---Example config.lua:
---   return { partial_excludes = { ["claude"] = { "README.md" } } }
---@return table config Project config table, or empty table if not found
local function load_project_config()
  local cwd = vim.fn.getcwd()
  local config_path = cwd .. "/TODO.local/config.lua"
  local stat = vim.loop.fs_stat(config_path)
  if not stat then
    return {} -- No project config file
  end

  -- Safely load the Lua config file
  local ok, config = pcall(dofile, config_path)
  if ok and type(config) == "table" then
    return config
  end

  -- Log warning if config exists but failed to load
  if not ok then
    vim.notify("Failed to load TODO config: " .. config_path, vim.log.levels.WARN)
  end
  return {}
end

---Get merged partial exclusions (global defaults + project-local overrides)
---@return table partial_excludes Map of folder -> allowed filenames
local function get_partial_excludes()
  local excludes = vim.deepcopy(DEFAULT_PARTIAL_EXCLUDES)
  local project_config = load_project_config()

  -- Merge project-specific partial excludes
  if project_config.partial_excludes then
    for folder, files in pairs(project_config.partial_excludes) do
      excludes[folder] = files
    end
  end

  return excludes
end

---Scan ALL markdown files in TODO.local/[branch]/ for incomplete tasks
---Uses ripgrep for fast scanning across multiple files
---Each task gets source = "local" for the unified picker
---@return table[] tasks Array of task items with file, line, text, due_date, category, sort_priority, source
function M.scan_project_todos()
  local todo_dir = M.get_todo_dir_path()
  if not todo_dir then
    return {}
  end

  -- Check if directory exists
  local stat = vim.loop.fs_stat(todo_dir)
  if not stat then
    return {} -- Directory doesn't exist yet, no tasks
  end

  local cwd = vim.fn.getcwd()
  local today = get_today()
  local tasks = {}

  -- Use ripgrep with JSON output to find all incomplete tasks in all *.md files
  -- This allows multiple TODO files (SUMMARY.md, BACKLOG.md, etc.) in the same directory
  local cmd = string.format('rg --json --line-number "^\\s*-\\s*\\[\\s\\]\\s*(.+)" --glob "*.md" %s', todo_dir)
  local output = vim.fn.systemlist(cmd)

  -- Exit code 1 means no matches found, which is fine
  if vim.v.shell_error ~= 0 and vim.v.shell_error ~= 1 then
    return tasks
  end

  -- Parse ripgrep JSON output
  for _, json_line in ipairs(output) do
    local ok, decoded = pcall(vim.json.decode, json_line)
    if ok and decoded.type == "match" then
      local data = decoded.data
      local file = data.path.text
      local line_num = data.line_number
      local line_text = data.lines.text:gsub("\n$", "") -- Remove trailing newline

      -- Extract task text from the matched line
      local task_text = line_text:match(TASK_PATTERN)
      if task_text then
        -- Convert absolute path to relative path from project root for display
        local rel_path = file:gsub("^" .. vim.pesc(cwd) .. "/", "")

        -- Parse due date from task text
        local due_date = parse_due_date(task_text)

        -- Categorize and get sort priority (days_diff for numeric display)
        local category, sort_priority, days_diff = categorize_project_task(due_date, today)

        -- Add task to list with source = "local" for unified picker
        table.insert(tasks, {
          file = file, -- Absolute path for opening
          rel_path = rel_path, -- Relative path for display (e.g., TODO.local/main/SUMMARY.md)
          line = line_num,
          text = task_text,
          raw_line = line_text, -- Store raw line for toggling
          due_date = due_date,
          category = category,
          sort_priority = sort_priority,
          days_diff = days_diff, -- Days until/since due (nil = no date)
          source = "local", -- Source identifier for unified picker badge [L]
        })
      end
    end
  end

  -- Sort tasks by priority, then by due date, then by file
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
    return a.rel_path < b.rel_path
  end)

  return tasks
end

---Parse ripgrep JSON output and add tasks to the provided tasks table
---@param output string[] Lines of ripgrep JSON output
---@param tasks table[] Table to append tasks to
---@param cwd string Current working directory for relative path calculation
---@param today string Today's date for categorization
local function parse_ripgrep_output(output, tasks, cwd, today)
  for _, json_line in ipairs(output) do
    local ok, decoded = pcall(vim.json.decode, json_line)
    if ok and decoded.type == "match" then
      local data = decoded.data
      local file = data.path.text
      local line_num = data.line_number
      local line_text = data.lines.text:gsub("\n$", "") -- Remove trailing newline

      -- Extract task text from the matched line
      local task_text = line_text:match(TASK_PATTERN)
      if task_text then
        -- Convert absolute path to relative path from project root for display
        local rel_path = file:gsub("^" .. vim.pesc(cwd) .. "/", "")

        -- Parse due date from task text
        local due_date = parse_due_date(task_text)

        -- Categorize and get sort priority (days_diff for numeric display)
        local category, sort_priority, days_diff = categorize_project_task(due_date, today)

        -- Add task to list with source = "global" for unified picker
        table.insert(tasks, {
          file = file, -- Absolute path for opening
          rel_path = rel_path, -- Relative path for display (e.g., README.md, docs/TODO.md)
          line = line_num,
          text = task_text,
          raw_line = line_text, -- Store raw line for toggling
          due_date = due_date,
          category = category,
          sort_priority = sort_priority,
          days_diff = days_diff, -- Days until/since due (nil = no date)
          source = "global", -- Source identifier for unified picker badge [G]
        })
      end
    end
  end
end

---Scan ALL markdown files in the project (excluding TODO.local) for incomplete tasks
---Uses ripgrep for fast scanning with exclusion patterns for common vendor directories
---Supports partial exclusions: folders can be excluded but allow specific files (e.g., README.md)
---Each task gets source = "global" for the unified picker
---NOTE: Skips scanning if cwd is the Obsidian vault to avoid duplicating [N] tasks as [G]
---@return table[] tasks Array of task items with file, line, text, due_date, category, sort_priority, source
function M.scan_global_markdown_todos()
  local cwd = vim.fn.getcwd()

  -- Skip global scan if cwd is the Obsidian vault
  -- This prevents duplicate tasks appearing as both [G] and [N] when inside the notes project
  if Obsidian and Obsidian.dir then
    local vault_path = tostring(Obsidian.dir)
    if cwd == vault_path then
      return {} -- Let the Obsidian scanner handle these tasks with [N] badge
    end
  end

  local today = get_today()
  local tasks = {}

  -- Get partial exclusions (global defaults merged with project-local config)
  local partial_excludes = get_partial_excludes()

  -- Build exclusion globs for ripgrep
  -- Always exclude: TODO.local, .git, node_modules, vendor, .venv, __pycache__
  local exclude_globs = {
    "!TODO.local/**",
    "!.git/**",
    "!node_modules/**",
    "!vendor/**",
    "!.venv/**",
    "!__pycache__/**",
  }

  -- Add partial exclusion folders to the exclusion list
  -- These will be scanned separately with only their allowlisted files
  for folder, _ in pairs(partial_excludes) do
    table.insert(exclude_globs, "!" .. folder .. "/**")
  end

  -- Build the main ripgrep command with all exclusions
  local glob_args = table.concat(
    vim.tbl_map(function(g)
      return '--glob "' .. g .. '"'
    end, exclude_globs),
    " "
  )

  local cmd = string.format('rg --json --line-number "^\\s*-\\s*\\[\\s\\]\\s*(.+)" --glob "*.md" %s %s', glob_args, cwd)
  local output = vim.fn.systemlist(cmd)

  -- Exit code 1 means no matches found, which is fine
  if vim.v.shell_error == 0 or vim.v.shell_error == 1 then
    parse_ripgrep_output(output, tasks, cwd, today)
  end

  -- Second pass: scan only allowlisted files in partial exclusion folders
  -- This allows folders like .claude/ to be mostly excluded but still scan README.md
  for folder, allowed_files in pairs(partial_excludes) do
    for _, filename in ipairs(allowed_files) do
      local file_path = cwd .. "/" .. folder .. "/" .. filename
      local stat = vim.loop.fs_stat(file_path)
      if stat then
        -- File exists, scan it with ripgrep
        local allowlist_cmd = string.format('rg --json --line-number "^\\s*-\\s*\\[\\s\\]\\s*(.+)" %s', file_path)
        local allowlist_output = vim.fn.systemlist(allowlist_cmd)
        if vim.v.shell_error == 0 or vim.v.shell_error == 1 then
          parse_ripgrep_output(allowlist_output, tasks, cwd, today)
        end
      end
    end
  end

  -- Sort tasks by priority, then by due date, then by file
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
    return a.rel_path < b.rel_path
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
    -- Urgent categories: overdue (red), due_today (orange)
    if task.category == "overdue" or task.category == "due_today" then
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
      -- Urgent categories: overdue (red), due_today (orange), today (green, in daily note)
      if task.category == "overdue" or task.category == "due_today" or task.category == "today" then
        return true
      end
    end
  end

  return false
end

return M
