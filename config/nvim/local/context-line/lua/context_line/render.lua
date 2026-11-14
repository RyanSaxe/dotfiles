-- Draws the pinned headers in a float over the top rows of a window: the
-- block's line number in the gutter, then its collapsed header.
local M = {}

local ns = vim.api.nvim_create_namespace("context_line")

---@class context_line.Row
---@field lnum integer the block's first line, 1-based
---@field text string
---@field marks context_line.Mark[]

---@type table<integer, { win: integer, buf: integer }>
local floats = {}

--- The gutter text for `lnum`, from 'statuscolumn' when it is set, with
--- line number highlights recolored for the header. A window without line
--- numbers gets a blank gutter.
---@param winid integer
---@param lnum integer
---@param width integer
---@return string text
---@return context_line.Mark[]
local function gutter(winid, lnum, width)
  if not (vim.wo[winid].number or vim.wo[winid].relativenumber) then
    return string.rep(" ", width), {}
  end
  local statuscolumn = vim.wo[winid].statuscolumn
  if statuscolumn ~= "" then
    local ok, result = pcall(vim.api.nvim_eval_statusline, statuscolumn, {
      winid = winid,
      use_statuscol_lnum = lnum,
      highlights = true,
      fillchar = " ",
    })
    if ok then
      local marks = {} ---@type context_line.Mark[]
      for i, item in ipairs(result.highlights) do
        local next_item = result.highlights[i + 1]
        local groups = item.groups or { item.group }
        for _, group in ipairs(groups) do
          marks[#marks + 1] = {
            col = item.start,
            end_col = next_item and next_item.start or #result.str,
            hl_group = group:find("LineNr") and "TreesitterContextLineNumber" or group,
            priority = 1,
          }
        end
      end
      return result.str .. string.rep(" ", width - result.width), marks
    end
  end
  local number = lnum
  if vim.wo[winid].relativenumber then
    number = math.abs(vim.api.nvim_win_get_cursor(winid)[1] - lnum)
  end
  return ("%" .. (width - 1) .. "d "):format(number), {}
end

---@param parent integer
---@param height integer
---@param config context_line.Config
---@return { win: integer, buf: integer }
local function open_float(parent, height, config)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].undolevels = -1
  -- The separator is the float's bottom border, so it spans the gutter too.
  local line = config.separator and { config.separator, "TreesitterContextSeparator" }
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "win",
    win = parent,
    row = 0,
    col = 0,
    width = vim.api.nvim_win_get_width(parent),
    height = height,
    focusable = false,
    style = "minimal",
    border = line and { "", "", "", "", line, line, line, "" } or "none",
    noautocmd = true,
    zindex = config.zindex,
  })
  vim.wo[win].winhighlight = "NormalFloat:TreesitterContext"
  vim.wo[win].wrap = false
  return { win = win, buf = buf }
end

---@param buf integer
---@param row integer
---@param offset integer
---@param marks context_line.Mark[]
local function apply_marks(buf, row, offset, marks)
  for _, mark in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(buf, ns, row, offset + mark.col, {
      end_col = offset + mark.end_col,
      hl_group = mark.hl_group,
      priority = mark.priority,
    })
  end
end

--- Shows `rows` over the top of `winid`, outermost block first.
---@param winid integer
---@param rows context_line.Row[]
---@param config context_line.Config
function M.show(winid, rows, config)
  local float = floats[winid]
  if float and vim.api.nvim_win_is_valid(float.win) then
    vim.api.nvim_win_set_config(float.win, {
      relative = "win",
      win = winid,
      row = 0,
      col = 0,
      width = vim.api.nvim_win_get_width(winid),
      height = #rows,
    })
  else
    float = open_float(winid, #rows, config)
    floats[winid] = float
  end

  local gutter_width = vim.fn.getwininfo(winid)[1].textoff
  local lines, gutters = {}, {}
  for i, row in ipairs(rows) do
    local text, marks = "", {}
    if gutter_width > 0 then
      text, marks = gutter(winid, row.lnum, gutter_width)
    end
    gutters[i] = { text = text, marks = marks }
    lines[i] = text .. row.text
  end

  vim.api.nvim_buf_set_lines(float.buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(float.buf, ns, 0, -1)
  for i, row in ipairs(rows) do
    local line_number = gutters[i]
    if #line_number.text > 0 then
      vim.api.nvim_buf_set_extmark(float.buf, ns, i - 1, 0, {
        end_col = #line_number.text,
        hl_group = "TreesitterContextLineNumber",
        priority = 0,
      })
    end
    apply_marks(float.buf, i - 1, 0, line_number.marks)
    apply_marks(float.buf, i - 1, #line_number.text, row.marks)
  end
  local last = #rows - 1
  vim.api.nvim_buf_set_extmark(float.buf, ns, last, 0, {
    end_row = last + 1,
    hl_group = "TreesitterContextBottom",
    hl_eol = true,
  })
  if #gutters[#rows].text > 0 then
    vim.api.nvim_buf_set_extmark(float.buf, ns, last, 0, {
      end_col = #gutters[#rows].text,
      hl_group = "TreesitterContextLineNumberBottom",
    })
  end
end

---@param winid integer
function M.close(winid)
  local float = floats[winid]
  floats[winid] = nil
  if float and vim.api.nvim_win_is_valid(float.win) then
    vim.api.nvim_win_close(float.win, true)
  end
end

--- Closes every float whose window is gone or is not in `keep`.
---@param keep table<integer, true>
---@param tabpage integer only floats over windows in this tab page close for not being kept
function M.close_others(keep, tabpage)
  for winid in pairs(floats) do
    local gone = not vim.api.nvim_win_is_valid(winid)
    if gone or (not keep[winid] and vim.api.nvim_win_get_tabpage(winid) == tabpage) then
      M.close(winid)
    end
  end
end

return M
