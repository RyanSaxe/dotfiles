-- insert-due.lua  ── Simple due date insertion for Obsidian tasks
-- Prompts for number of days and inserts 📅 YYYY-MM-DD at cursor

local M = {}

---Get date N days from today in YYYY-MM-DD format
---@param days_offset number Number of days to add (can be negative)
---@return string date Date in YYYY-MM-DD format
local function get_date_offset(days_offset)
  local time = os.time() + (days_offset * 24 * 60 * 60)
  return os.date("%Y-%m-%d", time)
end

---Prompt user for days and insert due date at end of line
function M.insert_due_date()
  vim.ui.input({
    prompt = "Number of days from today (empty = today): ",
    default = "",
  }, function(input)
    if not input then
      return -- User cancelled
    end

    -- Treat empty input as 0 (today)
    local days = 0
    if input ~= "" then
      days = tonumber(input)
      if not days then
        vim.notify("Invalid number: " .. input, vim.log.levels.WARN)
        return
      end
    end

    -- Calculate date
    local date = get_date_offset(days)
    local formatted = " 📅 " .. date

    -- Get current line
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line_num = cursor[1]
    local line = vim.api.nvim_get_current_line()

    -- Append to end of line
    local new_line = line .. formatted
    vim.api.nvim_set_current_line(new_line)

    -- Move cursor to end of line
    vim.api.nvim_win_set_cursor(0, { line_num, #new_line })
  end)
end

return M
