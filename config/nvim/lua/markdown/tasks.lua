-- Tasks in any Markdown file, outside fenced code. A task is a `- [ ]` or
-- `- [x]` line, with `*` or `+` also allowed as the bullet, and the lines it
-- wraps onto, which end where ws ends them in pkgs/ws/tasks.go: at a blank
-- line, a list item, a heading, a quote, a table or a code fence. Its due
-- date is 📅 and a YYYY-MM-DD date anywhere in that text, even with a line
-- break between them.
local M = {}

local TASK = "^%s*[-*+] %[([ xX])%]%s+%S"
local DUE = "%s*📅%s*()%d%d%d%d%-%d%d%-%d%d"
local WEEKDAYS = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }

---@param line string
---@return boolean
local function ends_text(line)
  -- The space lets a bare marker such as "-" match "%s" at the end.
  local spaced = line .. " "
  return line:find("^%s*$") ~= nil
    or spaced:find("^%s*[-*+]%s") ~= nil
    or spaced:find("^%s*%d+[.)]%s") ~= nil
    or spaced:find("^%s*#+%s") ~= nil
    or line:find("^%s*[>|]") ~= nil
    or line:find("^%s*```") ~= nil
    or line:find("^%s*~~~") ~= nil
end

---@param buf integer
---@param row integer 1-based
---@return string
local function line_at(buf, row)
  return vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
end

---@param buf integer
---@param row integer 1-based
---@return boolean
local function in_fence(buf, row)
  local parser = vim.treesitter.get_parser(buf, nil, { error = false })
  if not parser or parser:lang() ~= "markdown" then
    return false
  end
  -- Inside a list item, the first column belongs to the item, so look where the line's text starts.
  local col = (line_at(buf, row):find("%S") or 1) - 1
  local node = parser:parse()[1]:root():named_descendant_for_range(row - 1, col, row - 1, col)
  while node do
    if node:type() == "fenced_code_block" then
      return true
    end
    node = node:parent()
  end
  return false
end

---Finds the task that a line is part of. A line in fenced code is part of
---none, as ws skips fenced code.
---@param buf integer
---@param row integer 1-based
---@return integer? first the task's line with the box
---@return string? mark the character in the box
function M.find(buf, row)
  if in_fence(buf, row) then
    return nil
  end
  for r = row, 1, -1 do
    local line = line_at(buf, r)
    local mark = line:match(TASK)
    if mark then
      return r, mark
    elseif ends_text(line) then
      return nil
    end
  end
end

---@param buf integer
---@param first integer the task's line with the box
---@return integer last the task's last line
local function last_row(buf, first)
  local count = vim.api.nvim_buf_line_count(buf)
  local last = first
  while last < count and not ends_text(line_at(buf, last + 1)) do
    last = last + 1
  end
  return last
end

---@param days integer
---@return string YYYY-MM-DD that many days from today
function M.day(days)
  local today = os.date("*t")
  return os.date("%Y-%m-%d", os.time({ year = today.year, month = today.month, day = today.day + days, hour = 12 }))
end

---@param date string
---@return integer? time noon on that day, or nil when date is not a real YYYY-MM-DD
local function noon(date)
  local year, month, day = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if not year then
    return nil
  end
  local time = os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12 })
  if os.date("%Y-%m-%d", time) == date then
    return time
  end
end

---@param date string YYYY-MM-DD
---@return string label such as "Friday 2026-11-20"
function M.label(date)
  return WEEKDAYS[os.date("*t", noon(date)).wday] .. " " .. date
end

---Reads a date as ws's dueDate does: today, tmr or tomorrow, a number of
---days such as 3d, three or more letters of a weekday, where today's
---weekday means today, or YYYY-MM-DD.
---@param word string
---@return string? date YYYY-MM-DD, or nil when word is none of those
function M.due_date(word)
  word = word:lower()
  if noon(word) then
    return word
  elseif word == "today" then
    return M.day(0)
  elseif word == "tmr" or word == "tomorrow" then
    return M.day(1)
  elseif word:match("^%d+d$") then
    return M.day(tonumber(word:sub(1, -2)))
  elseif #word >= 3 then
    local today = os.date("*t").wday
    for wday, name in ipairs(WEEKDAYS) do
      if vim.startswith(name:lower(), word) then
        return M.day((wday - today) % 7)
      end
    end
  end
end

---Reads the text of the task that a line is part of, and finds its due
---date there.
---@param buf integer
---@param row integer 1-based
---@return integer first, string[] lines, string text the lines joined with "\n"
---@return integer? from where the date's 📅 and the space before it start in text
---@return integer? to where the date ends
---@return integer? at where the date's digits start
local function task_text(buf, row)
  local first = assert(M.find(buf, row))
  local lines = vim.api.nvim_buf_get_lines(buf, first - 1, last_row(buf, first), false)
  local text = table.concat(lines, "\n")
  return first, lines, text, text:find(DUE)
end

---The range that removing the due date of the task that a line is part of
---takes out, from the space before its 📅 to its last digit.
---@param buf integer
---@param row integer 1-based
---@return lsp.Range? range 0-based lines and byte columns, or nil when the task has no date
function M.due_range(buf, row)
  local first, lines, _, from, to = task_text(buf, row)
  if not from then
    return nil
  end
  ---@param offset integer 1-based, in the lines joined with "\n"
  local function position(offset)
    for i, line in ipairs(lines) do
      if offset <= #line + 1 then
        return { line = first + i - 2, character = offset - 1 }
      end
      offset = offset - #line - 1
    end
  end
  return { start = position(from), ["end"] = position(to + 1) }
end

---Changes the due date of the task that a line is part of, removes it when
---date is nil, or adds it at the end of the task's text.
---@param buf integer
---@param row integer 1-based
---@param date string? YYYY-MM-DD
local function set_due(buf, row, date)
  local first, lines, text, from, to, at = task_text(buf, row)
  local last = first + #lines - 1
  if from and date then
    text = text:sub(1, at - 1) .. date .. text:sub(to + 1)
  elseif from then
    text = text:sub(1, from - 1) .. text:sub(to + 1)
  elseif date then
    text = (text:gsub("%s+$", "")) .. " 📅 " .. date
  end
  if text ~= table.concat(lines, "\n") then
    vim.api.nvim_buf_set_lines(buf, first - 1, last, false, vim.split(text, "\n", { plain = true }))
  end
end

local function no_task()
  vim.notify("The cursor is not on a task", vim.log.levels.WARN)
end

---Ticks or unticks the task under the cursor.
function M.toggle()
  local buf = vim.api.nvim_get_current_buf()
  local first, mark = M.find(buf, vim.fn.line("."))
  if not first then
    return no_task()
  end
  local box = line_at(buf, first):find("%[")
  vim.api.nvim_buf_set_text(buf, first - 1, box, first - 1, box + 1, { mark == " " and "x" or " " })
end

---Sets, changes or removes the due date of the task under the cursor,
---picked from today, tomorrow, the weekdays after them, a week from today
---or no date.
function M.pick_due()
  local buf, row = vim.api.nvim_get_current_buf(), vim.fn.line(".")
  if not M.find(buf, row) then
    return no_task()
  end
  ---@type { name?: string, date?: string }[]
  local choices = { { name = "Today", date = M.day(0) }, { name = "Tomorrow", date = M.day(1) } }
  for days = 2, 6 do
    choices[#choices + 1] = { date = M.day(days) }
  end
  vim.list_extend(choices, { { name = "Next week", date = M.day(7) }, { name = "No date" } })
  vim.ui.select(choices, {
    prompt = "Due date",
    format_item = function(choice)
      if not choice.date then
        return choice.name
      end
      return (choice.name and choice.name .. ", " or "") .. M.label(choice.date)
    end,
  }, function(choice)
    if choice then
      set_due(buf, row, choice.date)
    end
  end)
end

return M
