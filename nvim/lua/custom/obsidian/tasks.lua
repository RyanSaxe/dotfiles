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
---@return string category Category: "today", "overdue", "week", "later"
---@return number sort_priority Sort priority (lower = earlier in list)
local function categorize_task(file, due_date, today, today_file)
  -- Green: Tasks in today's daily note (no due date required)
  if file == today_file then
    return "today", 1
  end

  -- Red: Overdue or due today
  if due_date then
    local days_diff = days_between(today, due_date)
    if days_diff <= 0 then
      -- Overdue or due today
      return "overdue", 2
    elseif days_diff <= 7 then
      -- Orange: Due in next 7 days
      return "week", 3
    else
      -- Gray: Due later than 7 days
      return "later", 4
    end
  end

  -- Red: Tasks in old daily notes (before today)
  if file:match("^" .. DAILY_FOLDER .. "/") then
    local date_match = file:match("(%d%d%d%d%-%d%d%-%d%d)")
    if date_match then
      local days_diff = days_between(date_match, today)
      if days_diff > 0 then
        -- Old daily note = overdue (date_match is in the past)
        return "overdue", 2
      end
    end
  end

  -- Gray: Everything else (no due date, not in daily notes)
  return "later", 4
end

---Get highlight group for task category
---@param category string Category: "today", "overdue", "week", "later"
---@return string hl_group Highlight group name
local function get_category_highlight(category)
  if category == "today" then
    return "DiagnosticOk" -- Green
  elseif category == "overdue" then
    return "DiagnosticError" -- Red
  elseif category == "week" then
    return "DiagnosticWarn" -- Orange
  else
    return "Comment" -- Gray
  end
end

---Get category icon
---@param category string Category: "today", "overdue", "week", "later"
---@return string icon Icon to display
local function get_category_icon(category)
  if category == "today" then
    return "● " -- Green dot
  elseif category == "overdue" then
    return "● " -- Red dot
  elseif category == "week" then
    return "● " -- Orange dot
  else
    return "○ " -- Gray circle
  end
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
  local cmd = string.format('rg --json --line-number "^\\s*-\\s*\\[\\s\\]\\s*(.+)" %s', vault_path)
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

        -- Categorize and get sort priority
        local category, sort_priority = categorize_task(rel_path, due_date, today, today_file)

        -- Add task to list
        table.insert(tasks, {
          file = file, -- Absolute path for opening
          rel_path = rel_path, -- Relative path for display
          line = line_num,
          text = task_text,
          raw_line = line_text, -- Store raw line for toggling
          due_date = due_date,
          category = category,
          sort_priority = sort_priority,
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

  vim.notify("Task toggled", vim.log.levels.INFO)
end

---Format task item for picker display
---@param item table Task item
---@param picker table Snacks picker instance
---@return table highlights Array of {text, hl_group} pairs
local function format_task(item, picker)
  local ret = {}

  -- Category icon with color
  local icon = get_category_icon(item.category)
  local hl = get_category_highlight(item.category)
  ret[#ret + 1] = { icon, hl }

  -- Task text (truncate if too long)
  local max_text_len = 50
  local text = item.text
  if #text > max_text_len then
    text = text:sub(1, max_text_len - 3) .. "..."
  end
  ret[#ret + 1] = { text .. " ", "Normal" }

  -- File path (dimmed)
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
    -- Custom preview: handle separators specially, delegate to file preview for tasks
    preview = function(ctx)
      if ctx.item.is_separator then
        -- Show simple text for separator items
        ctx.preview:reset()
        ctx.preview:set_lines({ "", "  Section: " .. (ctx.item.text or ""), "" })
        return
      end
      -- Delegate to default file previewer for task items
      Snacks.picker.preview.file(ctx)
    end,
    format = function(item)
      -- Handle separator items (non-selectable headers)
      if item.is_separator then
        return { { item.text or "", "Comment" } }
      end

      -- Handle placeholder items (dimmed, indicates action to create TODO)
      if item.is_placeholder then
        return { { item.text or "", "Comment" } }
      end

      -- Handle regular task items
      if item.task then
        return format_task(item.task, nil)
      end

      -- Fallback for any other items
      return { { item.text or "", "Normal" } }
    end,
    confirm = function(picker, item)
      -- Separators are not actionable
      if item and item.is_separator then
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
            vim.notify("All tasks completed!", vim.log.levels.INFO)
          else
            picker:close()
            -- Reopen with updated items (no rescan - just use filtered list)
            Snacks.picker(create_picker_config(items))
          end
        end
      end,
    },
    win = {
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

---Convert a task to a picker item with proper display format
---@param task table Task data from scan_tasks or scan_project_todos
---@return table item Picker item with text, file, pos, task fields
local function task_to_picker_item(task)
  local icon = get_category_icon(task.category)
  local due_text = task.due_date and (task.due_date .. " ") or "           "
  local task_text = task.text
  if #task_text > 50 then
    task_text = task_text:sub(1, 47) .. "..."
  end
  local display = icon .. due_text .. task_text .. " (" .. task.rel_path .. ":" .. task.line .. ")"

  return {
    text = display,
    file = task.file,
    pos = { task.line, 0 },
    task = task, -- Store full task data for actions
  }
end

---Create a separator item for the picker
---@param label string Label to display in separator
---@return table item Separator picker item
local function create_separator_item(label)
  return {
    text = "── " .. label .. " ──",
    is_separator = true,
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

---Open task picker
---Shows project TODOs first (if any), then Obsidian tasks with separator
function M.open_picker()
  -- Scan both sources
  local obsidian_tasks = M.scan_tasks()

  -- Always scan project TODOs
  local todos_module = nil
  local project_tasks = {}
  local ok, todos = pcall(require, "custom.todos")
  if ok then
    todos_module = todos
    project_tasks = todos.scan_project_todos()
  end

  -- Check if we have any tasks at all
  local has_project_tasks = #project_tasks > 0
  local has_obsidian_tasks = #obsidian_tasks > 0

  -- No tasks at all - offer to create project TODOs
  if not has_project_tasks and not has_obsidian_tasks then
    local todo_path = todos_module and todos_module.get_todo_file_path()
    if todo_path then
      todos_module.open_todo()
      return
    end
    vim.notify("No tasks found", vim.log.levels.INFO)
    return
  end

  -- Build the items list: project tasks first (no header), then Obsidian with separator
  local items = {}

  -- Project tasks first (no separator header)
  if has_project_tasks then
    for _, task in ipairs(project_tasks) do
      table.insert(items, task_to_picker_item(task))
    end
  else
    -- No project tasks - add placeholder to create them
    local todo_path = todos_module and todos_module.get_todo_file_path()
    if todo_path then
      table.insert(items, create_placeholder_item(todo_path))
    end
  end

  -- Add Obsidian section with separator (only if there are Obsidian tasks)
  if has_obsidian_tasks then
    table.insert(items, create_separator_item("Obsidian Tasks"))
    for _, task in ipairs(obsidian_tasks) do
      table.insert(items, task_to_picker_item(task))
    end
  end

  -- Open picker with unified title
  local config = create_picker_config(items)
  config.title = "All Tasks"
  Snacks.picker(config)
end

return M
