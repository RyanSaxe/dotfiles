-- Colors a task's 📅 date by when it's due, as sketchybar's T letter does:
-- overdue, today and tomorrow, or faint once the task is done. A date on
-- any other line stays plain. The colors are ThemeTask* in
-- theme/highlights.lua.
local task = "^%s*[-*+] %[(.)%]"

---@param date string YYYY-MM-DD
---@return string?
local function due_group(date)
  local today = os.date("%Y-%m-%d")
  local tomorrow = os.date("%Y-%m-%d", os.time() + 24 * 60 * 60)
  if date < today then
    return "ThemeTaskOverdue"
  elseif date == today then
    return "ThemeTaskToday"
  elseif date == tomorrow then
    return "ThemeTaskTomorrow"
  end
end

return {
  "nvim-mini/mini.hipatterns",
  opts = function(_, opts)
    opts.highlighters = opts.highlighters or {}
    opts.highlighters.task_due = {
      pattern = function(buf)
        if vim.bo[buf].filetype == "markdown" then
          return "📅 %d%d%d%d%-%d%d%-%d%d"
        end
      end,
      group = function(buf, match, data)
        local line = vim.api.nvim_buf_get_lines(buf, data.line - 1, data.line, false)[1] or ""
        local mark = line:match(task)
        if not mark then
          return nil
        elseif mark ~= " " then
          return "ThemeTaskDone"
        end
        return due_group(match:sub(-10))
      end,
    }
  end,
}
