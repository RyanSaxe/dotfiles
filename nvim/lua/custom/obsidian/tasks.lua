-- tasks.lua  ── Obsidian task picker for Neovim
-- Scans the Obsidian vault for incomplete tasks and displays them in a snacks picker
-- with color coding and sorting based on due dates and daily note context

local M = {}

-- Configuration
local DAILY_FOLDER = "daily"
local DATE_PATTERN = "📅%s*(%d%d%d%d%-%d%d%-%d%d)" -- Match 📅 YYYY-MM-DD
local TASK_PATTERN = "^%s*%-%s*%[%s%]%s*(.+)" -- Match - [ ] task text

---Get vault path dynamically from Obsidian
---@return string|nil vault_path Path to vault, or nil if Obsidian not initialized
local function get_vault_path()
  if not Obsidian or not Obsidian.dir then
    return nil
  end
  return tostring(Obsidian.dir)
end

---Get today's date in YYYY-MM-DD format
---@return string today Today's date
---@return string today_file Path to today's daily note file (relative)
local function get_today_info()
  local today = os.date("%Y-%m-%d")
  local today_file = DAILY_FOLDER .. "/" .. today .. ".md"
  return today, today_file
end

---Parse date from task text
---Looks for 📅 YYYY-MM-DD pattern in the task text
---@param text string Task text to parse
---@return string|nil date Date in YYYY-MM-DD format or nil if not found
local function parse_due_date(text)
  local date = text:match(DATE_PATTERN)
  return date
end

---Calculate days between two dates
---@param date1 string Date in YYYY-MM-DD format
---@param date2 string Date in YYYY-MM-DD format
---@return number days Number of days (can be negative if date1 < date2)
local function days_between(date1, date2)
  -- Convert YYYY-MM-DD to timestamp
  local y1, m1, d1 = date1:match("(%d+)-(%d+)-(%d+)")
  local y2, m2, d2 = date2:match("(%d+)-(%d+)-(%d+)")

  local t1 = os.time({ year = y1, month = m1, day = d1, hour = 0 })
  local t2 = os.time({ year = y2, month = m2, day = d2, hour = 0 })

  return math.floor((t2 - t1) / 86400) -- 86400 seconds in a day
end

---Categorize a task based on its due date and file location
---@param file string Relative file path
---@param due_date string|nil Due date from task text
---@param today string Today's date
---@param today_file string Path to today's daily note
---@return string category Category: "today", "due_today", "overdue", "week", "later"
---@return number sort_priority Sort priority (lower = earlier in list)
---@return number|nil days_diff Days until/since due (negative = overdue, nil = no date)
local function categorize_task(file, due_date, today, today_file)
  -- Tasks in today's daily note
  if file == today_file then
    -- If task has an explicit due date, use that for categorization
    -- This allows adding future tasks to daily notes without them being marked urgent
    if due_date then
      local days_diff = days_between(today, due_date)
      if days_diff < 0 then
        -- Overdue - red
        return "overdue", 2, days_diff
      elseif days_diff == 0 then
        -- Due today - orange
        return "due_today", 1, days_diff
      elseif days_diff <= 7 then
        -- Due within a week - green, not urgent
        return "week", 3, days_diff
      else
        -- Due later - gray, not urgent
        return "later", 4, days_diff
      end
    end
    -- No explicit due date = implicitly due today (green)
    return "today", 1, nil
  end

  -- Tasks with explicit due dates (not in today's daily note)
  if due_date then
    local days_diff = days_between(today, due_date)
    if days_diff < 0 then
      -- Overdue - red
      return "overdue", 2, days_diff
    elseif days_diff == 0 then
      -- Due today - orange
      return "due_today", 1, days_diff
    elseif days_diff <= 7 then
      -- Due within a week - green
      return "week", 3, days_diff
    else
      -- Due later - gray
      return "later", 4, days_diff
    end
  end

  -- Red: Tasks in old daily notes (before today)
  if file:match("^" .. DAILY_FOLDER .. "/") then
    local date_match = file:match("(%d%d%d%d%-%d%d%-%d%d)")
    if date_match then
      local days_diff = days_between(date_match, today)
      if days_diff > 0 then
        -- Old daily note = overdue (date_match is in the past)
        -- days_diff is positive (today - old_date), convert to negative for consistency
        return "overdue", 2, -days_diff
      end
    end
  end

  -- Gray: Everything else (no due date, not in daily notes)
  return "later", 4, nil
end

---Get highlight group for task category
---@param category string Category: "today", "due_today", "overdue", "week", "later"
---@return string hl_group Highlight group name
local function get_category_highlight(category)
  if category == "today" then
    return "DiagnosticOk" -- Green (in daily note, no explicit date)
  elseif category == "due_today" then
    return "DiagnosticWarn" -- Orange (explicit due date is today)
  elseif category == "overdue" then
    return "DiagnosticError" -- Red
  elseif category == "week" then
    return "DiagnosticOk" -- Green (due within 7 days)
  else
    return "Comment" -- Gray
  end
end

---Get category icon - shows number of days when due date exists, dot otherwise
---@param category string Category: "today", "due_today", "overdue", "week", "later"
---@param days_diff number|nil Days until/since due (negative = overdue, nil = no date)
---@return string icon Icon to display (number or dot)
local function get_category_icon(category, days_diff)
  -- No due date = gray circle (unchanged behavior)
  if days_diff == nil then
    return " ○ "
  end

  -- Format number: negative values show as positive (days overdue)
  -- Positive values show days until due
  -- Pad to 2 chars for alignment (e.g., " 3" or "12")
  local display_num
  if days_diff <= 0 then
    -- Overdue or due today: show absolute value (days overdue)
    display_num = math.abs(days_diff)
  else
    -- Future: show days until due
    display_num = days_diff
  end

  -- Format with padding for alignment (right-aligned in 2-char width)
  return string.format("%2d ", display_num)
end

---Scan vault for all incomplete tasks using ripgrep (much faster for large vaults)
---@return table[] tasks Array of task items
function M.scan_tasks()
  local vault_path = get_vault_path()
  if not vault_path then
    return {} -- Obsidian not initialized
  end

  local today, today_file = get_today_info()
  local tasks = {}

  -- Use ripgrep with JSON output to find all incomplete tasks in one pass
  -- This is MUCH faster than fd + reading every file, especially for large vaults

  local cmd = string.format(
    'rg --json --line-number "^\\s*-\\s*\\[\\s\\]\\s*(.+)" --glob "!**/templates/**" %s',
    vim.fn.shellescape(vault_path)
  )

  local output = vim.fn.systemlist(cmd)

  if vim.v.shell_error ~= 0 and vim.v.shell_error ~= 1 then
    -- Exit code 1 means no matches found, which is fine
    -- Other exit codes indicate an error
    if vim.v.shell_error ~= 1 then
      vim.notify("Failed to scan vault for tasks", vim.log.levels.ERROR)
    end
    return tasks
  end

  -- Parse ripgrep JSON output
  for _, json_line in ipairs(output) do
    -- Try to decode JSON line
    local ok, decoded = pcall(vim.json.decode, json_line)
    if ok and decoded.type == "match" then
      local data = decoded.data
      local file = data.path.text
      local line_num = data.line_number
      local line_text = data.lines.text:gsub("\n$", "") -- Remove trailing newline

      -- Extract task text from the matched line
      local task_text = line_text:match(TASK_PATTERN)
      if task_text then
        -- Convert to relative path from vault
        local rel_path = file:gsub("^" .. vim.pesc(vault_path) .. "/", "")

        -- Parse due date from task text
        local due_date = parse_due_date(task_text)

        -- If no explicit due date but file is a daily note, derive from filename
        -- This allows daily note tasks to show their implicit due date in the picker
        if not due_date and rel_path:match("^" .. DAILY_FOLDER .. "/") then
          due_date = rel_path:match("(%d%d%d%d%-%d%d%-%d%d)")
        end

        -- Categorize and get sort priority (days_diff for numeric display)
        local category, sort_priority, days_diff = categorize_task(rel_path, due_date, today, today_file)

        -- Add task to list with source = "notes" for unified picker
        table.insert(tasks, {
          file = file, -- Absolute path for opening
          rel_path = rel_path, -- Relative path for display
          line = line_num,
          text = task_text,
          raw_line = line_text, -- Store raw line for toggling
          due_date = due_date,
          category = category,
          sort_priority = sort_priority,
          days_diff = days_diff, -- Days until/since due (nil = no date)
          source = "notes", -- Source identifier for unified picker badge [N]
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

---Toggle checkbox for a task
---Marks the task as complete or incomplete by replacing [ ] with [x] or vice versa
---@param item table Task item from scan_tasks
local function toggle_task(item)
  -- Read file
  local file = io.open(item.file, "r")
  if not file then
    vim.notify("Failed to open file: " .. item.file, vim.log.levels.ERROR)
    return
  end

  local lines = {}
  local line_num = 0
  for line in file:lines() do
    line_num = line_num + 1
    if line_num == item.line then
      -- Toggle checkbox: [ ] -> [x] or [x] -> [ ]
      if line:match("%-%s*%[%s%]") then
        line = line:gsub("%-%s*%[%s%]", "- [x]", 1)
      elseif line:match("%-%s*%[x%]") then
        line = line:gsub("%-%s*%[x%]", "- [ ]", 1)
      end
    end
    table.insert(lines, line)
  end
  file:close()

  -- Write back to file
  file = io.open(item.file, "w")
  if not file then
    vim.notify("Failed to write file: " .. item.file, vim.log.levels.ERROR)
    return
  end

  for _, line in ipairs(lines) do
    file:write(line .. "\n")
  end
  file:close()
end

---Format task item for picker display with source badges
---Shows: [icon] [date] [source badge] task text (file:line)
---@param item table Task item with source field
---@return table highlights Array of {text, hl_group} pairs
local function format_task(item)
  local ret = {}

  -- Category icon with color (urgency indicator)
  -- Pass days_diff to show number instead of dot when due date exists
  local icon = get_category_icon(item.category, item.days_diff)
  local hl = get_category_highlight(item.category)
  ret[#ret + 1] = { icon, hl }

  -- Due date (padded for alignment, 10 chars for YYYY-MM-DD or spaces)
  -- Show "today" for daily note tasks without explicit due dates
  local due_text
  if item.due_date then
    due_text = item.due_date
  elseif item.category == "today" then
    due_text = "today     " -- Padded to match YYYY-MM-DD width
  else
    due_text = "          "
  end
  ret[#ret + 1] = { due_text .. " ", "Comment" }

  -- Source badge with color: [L]=yellow, [G]=purple, [N]=cyan
  -- Use bracket syntax for "local" since it's a Lua reserved keyword
  local badge_hl = {
    ["local"] = "DiagnosticWarn", -- yellow for local TODO.local tasks
    ["global"] = "Statement", -- Purple for project-wide markdown tasks
    ["notes"] = "DiagnosticHint", -- Teal for Obsidian vault tasks
  }
  local source = item.source or "notes" -- Default to notes for backwards compatibility
  local badge = "[" .. source:sub(1, 1):upper() .. "] "
  ret[#ret + 1] = { badge, badge_hl[source] or "Comment" }

  -- Task text - let the picker handle truncation, show full text
  ret[#ret + 1] = { item.text .. " ", "Normal" }

  -- File path (dimmed) - show full relative path for project files, shorter for notes
  -- Project files (local/global) need full path since there may be multiple README.md files
  -- Notes files can use shorter paths since they're in a separate vault context
  ret[#ret + 1] = { "(" .. item.rel_path .. ":" .. item.line .. ")", "Comment" }

  return ret
end

---Create picker configuration (helper to avoid duplication)
---@param items table[] List of picker items
---@return table picker_config Snacks picker configuration
local function create_picker_config(items)
  return {
    title = "Obsidian Tasks",
    items = items,
    layout = "custom_horizontal",
    -- Use default file previewer for task items
    preview = Snacks.picker.preview.file,
    format = function(item)
      -- Handle navigation items (distinctive → icon)
      if item.is_navigation then
        return { { "→ " .. item.nav_label, "DiagnosticHint" } }
      end

      -- Handle placeholder items (dimmed, indicates action to create TODO)
      if item.is_placeholder then
        return { { item.text or "", "Comment" } }
      end

      -- Handle regular task items
      if item.task then
        return format_task(item.task)
      end

      -- Fallback for any other items
      return { { item.text or "", "Normal" } }
    end,
    confirm = function(picker, item)
      -- Navigation items: open file (use ObsidianToday for daily notes to apply template)
      if item and item.is_navigation then
        picker:close()
        -- Check if this is the daily note and doesn't exist yet
        local is_daily = item.file and item.file:match("/daily/%d%d%d%d%-%d%d%-%d%d%.md$")
        if is_daily and vim.fn.filereadable(item.file) == 0 then
          -- Use ObsidianToday to create with template
          vim.cmd("ObsidianToday")
        else
          vim.cmd("edit " .. vim.fn.fnameescape(item.file))
        end
        return
      end

      -- Placeholder opens the TODO file for editing (creates it if needed)
      if item and item.is_placeholder then
        picker:close()
        local ok, todos = pcall(require, "custom.todos")
        if ok then
          todos.open_todo()
        end
        return
      end

      -- Regular task items: navigate to file and line
      if item and item.file and item.pos then
        picker:close()
        vim.cmd("edit " .. vim.fn.fnameescape(item.file))
        vim.api.nvim_win_set_cursor(0, item.pos)
      end
    end,
    actions = {
      toggle = function(picker)
        local item = picker:current()
        if item and item.task then
          -- Toggle the task in the file
          toggle_task(item.task)

          -- Remove from items list (efficient - no vault rescan needed)
          for i, list_item in ipairs(items) do
            if list_item == item then
              table.remove(items, i)
              break
            end
          end

          -- Update picker with remaining tasks
          if #items == 0 then
            picker:close()
          else
            picker:close()
            -- Reopen with updated items (no rescan - just use filtered list)
            Snacks.picker(create_picker_config(items))
          end
        end
      end,
    },
    win = {
      preview = require("custom.snacks.picker").preview_with_wrap,
      input = {
        keys = {
          ["<c-t>"] = { "toggle", mode = { "n", "i" }, desc = "Toggle task completion" },
        },
      },
      list = {
        keys = {
          ["<c-t>"] = { "toggle", desc = "Toggle task completion" },
        },
      },
    },
  }
end

---Convert a task to a picker item
---The text field is used for filtering/searching, format_task handles display
---@param task table Task data from any scan function
---@return table item Picker item with text, file, pos, task fields
local function task_to_picker_item(task)
  -- Build searchable text (used for filtering) - include full task text and path
  local source_badge = task.source and ("[" .. task.source:sub(1, 1):upper() .. "]") or ""
  local due_text = task.due_date or ""
  local display = source_badge .. " " .. due_text .. " " .. task.text .. " " .. task.rel_path

  return {
    text = display, -- Used for filtering/searching
    file = task.file,
    pos = { task.line, 0 },
    task = task, -- Store full task data for format_task and actions
  }
end

---Create a placeholder item for starting a new project TODO list
---@param todo_path string Path to the TODO file
---@return table item Placeholder picker item
local function create_placeholder_item(todo_path)
  return {
    text = "○ Start project TODO list...",
    file = todo_path,
    pos = { 1, 0 },
    is_placeholder = true,
  }
end

---Create a navigation item for quick access to related files
---@param label string Display label (e.g., "Go to daily note")
---@param file string|nil File path to open
---@return table|nil item Navigation picker item, or nil if file unavailable
local function create_navigation_item(label, file)
  if not file then
    return nil
  end
  return {
    text = label,
    file = file,
    pos = { 1, 0 },
    is_navigation = true,
    nav_label = label,
  }
end

---Open unified task picker
---Merges tasks from three sources: Local (TODO.local), Global (project *.md), Notes (Obsidian)
---All tasks are sorted by urgency (overdue → today → week → later → no date)
---Source badges [L], [G], [N] indicate where each task comes from
function M.open_picker()
  -- Load the todos module for local and global scanning
  local todos_module = nil
  local ok, todos = pcall(require, "custom.todos")
  if ok then
    todos_module = todos
  end

  -- Collect tasks from all three sources
  -- Each task already has a .source field ("local", "global", or "notes")
  local all_tasks = {}

  -- 1. Local TODOs from TODO.local/[branch]/*.md
  if todos_module then
    local local_tasks = todos_module.scan_project_todos()
    vim.list_extend(all_tasks, local_tasks)
  end

  -- 2. Global TODOs from project-wide *.md files (excluding TODO.local)
  if todos_module then
    local global_tasks = todos_module.scan_global_markdown_todos()
    vim.list_extend(all_tasks, global_tasks)
  end

  -- 3. Notes TODOs from Obsidian vault
  local notes_tasks = M.scan_tasks()
  vim.list_extend(all_tasks, notes_tasks)

  -- Sort all tasks uniformly by urgency, then due date, then source, then file
  -- This ensures urgent tasks from ANY source appear at the top
  -- Within same urgency/date, local tasks appear before global, then notes
  table.sort(all_tasks, function(a, b)
    -- Primary sort: urgency (sort_priority: 1=today, 2=overdue, 3=week, 4=later)
    if a.sort_priority ~= b.sort_priority then
      return a.sort_priority < b.sort_priority
    end
    -- Secondary sort: due date (earlier dates first)
    if a.due_date and b.due_date then
      return a.due_date < b.due_date
    elseif a.due_date then
      return true -- Tasks with dates before tasks without
    elseif b.due_date then
      return false
    end
    -- Tertiary sort: source priority (local=1, global=2, notes=3)
    -- This ensures contextually-relevant tasks appear first when urgency/date match
    local source_priority = { ["local"] = 1, global = 2, notes = 3 }
    local a_source = source_priority[a.source] or 999
    local b_source = source_priority[b.source] or 999
    if a_source ~= b_source then
      return a_source < b_source
    end
    -- Quaternary sort: file path for stable ordering
    return a.rel_path < b.rel_path
  end)

  -- Create navigation items at the top for quick access
  local nav_items = {}

  -- 1. Go to daily note
  local vault_path = get_vault_path()
  if vault_path then
    local _, today_file = get_today_info()
    local daily_path = vault_path .. "/" .. today_file
    local nav = create_navigation_item("Go to daily note", daily_path)
    if nav then
      table.insert(nav_items, nav)
    end
  end

  -- 2. Go to local todo list
  if todos_module then
    local todo_path = todos_module.get_todo_file_path()
    local nav = create_navigation_item("Go to local todo list", todo_path)
    if nav then
      table.insert(nav_items, nav)
    end
  end

  -- Build final items: navigation first, then tasks
  local items = {}
  vim.list_extend(items, nav_items)
  for _, task in ipairs(all_tasks) do
    table.insert(items, task_to_picker_item(task))
  end

  -- If no items at all (no nav items and no tasks), notify user
  if #items == 0 then
    vim.notify("No tasks found", vim.log.levels.INFO)
    return
  end

  -- Open picker with unified title
  local config = create_picker_config(items)
  config.title = "All Tasks"
  Snacks.picker(config)
end

return M
