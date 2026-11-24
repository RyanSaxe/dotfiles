-- Colors a task's 📅 date by when it's due, as sketchybar's T letter does:
-- overdue, today and tomorrow, or faint once the task is done. A date on a
-- line a task wraps onto takes that task's color, and a date anywhere else
-- stays plain. The colors are ThemeTask* in theme/highlights.lua.
--
-- In a task in any Markdown file, @ completes a due date (markdown/due_source.lua).
local tasks = require("markdown.tasks")

local DATE = "%d%d%d%d%-%d%d%-%d%d"

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

---@param buf integer
---@param row integer 1-based
---@return string line # "" above the first line or below the last
local function line_at(buf, row)
  return row >= 1 and vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
end

---@param pattern string
---@return fun(buf: integer): string?
local function in_markdown(pattern)
  return function(buf)
    if vim.bo[buf].filetype == "markdown" then
      return pattern
    end
  end
end

return {
  {
    "nvim-mini/mini.hipatterns",
    opts = function(_, opts)
      opts.highlighters = opts.highlighters or {}
      opts.highlighters.task_due = {
        -- rumdl can wrap a line between 📅 and its date.
        pattern = {
          in_markdown("📅 " .. DATE),
          in_markdown("()📅()%s*$"),
          in_markdown("^%s*()" .. DATE .. "()"),
        },
        group = function(buf, match, data)
          local date = match:match(DATE)
          if match == "📅" then
            date = line_at(buf, data.line + 1):match("^%s*(" .. DATE .. ")")
          elseif not match:find("📅") and not line_at(buf, data.line - 1):find("📅%s*$") then
            date = nil
          end
          local first, mark = tasks.find(buf, data.line)
          if not (date and first) then
            return nil
          elseif mark ~= " " then
            return "ThemeTaskDone"
          end
          return due_group(date)
        end,
      }
      -- mini.hipatterns redraws only the lines that change, and a wrapped
      -- date's color comes from the task's first line, so a change in
      -- Normal mode or the end of an Insert redraws the lines in view.
      vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave" }, {
        group = vim.api.nvim_create_augroup("task_dates", { clear = true }),
        callback = function(event)
          if vim.bo[event.buf].filetype == "markdown" then
            pcall(MiniHipatterns.update, event.buf, vim.fn.line("w0"), vim.fn.line("w$"))
          end
        end,
      })
    end,
  },
  {
    "saghen/blink.cmp",
    opts = {
      sources = {
        per_filetype = { markdown = { inherit_defaults = true, "task_due" } },
        providers = {
          task_due = { name = "Due", module = "markdown.due_source", min_keyword_length = 0, score_offset = 100 },
        },
      },
    },
  },
}
