-- Tasks in any Markdown file. A task is a `- [ ]` or `- [x]` line, with
-- `*` or `+` also allowed as the bullet, and the lines it wraps onto, which
-- end where ws ends them in pkgs/ws/tasks.go: at a blank line, a list item,
-- a heading, a quote, a table or a code fence.
local M = {}

local TASK = "^%s*[-*+] %[([ xX])%]%s+%S"

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

---Finds the task that a line is part of.
---@param buf integer
---@param row integer 1-based
---@return integer? first the task's line with the box
---@return string? mark the character in the box
function M.find(buf, row)
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

return M
