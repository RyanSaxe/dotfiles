-- The heatmap statusline: the bar IS the file. Every cell maps to a
-- slice of the buffer, colored by what lives there — git changes in
-- the semantic ops colors, diagnostics in error/warn, the cursor as
-- the bright cell. A mode bar and the recording register sit at the
-- left edge; everything else is the map.
local M = {}

---@return string
local function mode_group()
  ---@type string
  local m = vim.fn.mode():sub(1, 1)
  if m == "i" then
    return "ThemeHeatModeInsert"
  elseif m == "v" or m == "V" or m == "\22" or m == "s" then
    return "ThemeHeatModeVisual"
  elseif m == "c" then
    return "ThemeHeatModeCommand"
  elseif m == "R" then
    return "ThemeHeatModeReplace"
  elseif m == "t" then
    return "ThemeHeatModeTerminal"
  end
  return "ThemeHeatModeNormal"
end

-- Bucket priorities: bigger wins the cell.
local PRI = { track = 0, add = 1, delete = 2, change = 3, warn = 4, err = 5, cursor = 6 }
local GROUP = {
  track = "ThemeHeatTrack",
  add = "ThemeHeatAdd",
  delete = "ThemeHeatDelete",
  change = "ThemeHeatChange",
  warn = "ThemeHeatWarn",
  err = "ThemeHeatErr",
  cursor = "ThemeHeatCursor",
}

---@param buckets table<integer, integer>
---@param cells integer
---@param last integer
---@param line integer
---@param kind string
local function mark(buckets, cells, last, line, kind)
  local idx = math.min(cells, math.max(1, math.ceil(line / last * cells)))
  if PRI[kind] > (buckets[idx] or 0) then
    buckets[idx] = PRI[kind]
  end
end

---@return string
function M.render()
  local buf = vim.api.nvim_get_current_buf()
  local last = math.max(1, vim.api.nvim_buf_line_count(buf))
  ---@type string
  local reg = vim.fn.reg_recording()
  ---@type string
  local left = "%#" .. mode_group() .. "#▍ "
  if reg ~= "" then
    left = left .. "%#ThemeHeatRec#● " .. reg .. " "
  end
  -- Left edge takes ~5 columns; the rest of the row is map.
  local cells = math.max(10, vim.o.columns - (reg ~= "" and 9 or 5))

  ---@type table<integer, integer>
  local buckets = {}
  local ok, diff = pcall(require, "mini.diff")
  local data = ok and diff.get_buf_data(buf) or nil
  ---@type table[]
  local hunks = data and data.hunks or {}
  do
    for _, hunk in ipairs(hunks) do
      local kind = hunk.type == "add" and "add" or hunk.type == "delete" and "delete" or "change"
      local count = math.max(1, hunk.buf_count or 1)
      for l = hunk.buf_start, hunk.buf_start + count - 1 do
        mark(buckets, cells, last, math.max(1, l), kind)
      end
    end
  end
  for _, d in ipairs(vim.diagnostic.get(buf)) do
    local kind = d.severity == vim.diagnostic.severity.ERROR and "err"
      or d.severity == vim.diagnostic.severity.WARN and "warn"
      or nil
    if kind then
      mark(buckets, cells, last, d.lnum + 1, kind)
    end
  end
  mark(buckets, cells, last, vim.api.nvim_win_get_cursor(0)[1], "cursor")

  ---@type table<integer, string>
  local by_pri = {}
  for kind, pri in pairs(PRI) do
    by_pri[pri] = GROUP[kind]
  end
  ---@type string[]
  local parts = { left }
  ---@type string
  local current = ""
  for i = 1, cells do
    ---@type string
    local group = by_pri[buckets[i] or 0]
    if group ~= current then
      parts[#parts + 1] = "%#" .. group .. "#"
      current = group
    end
    parts[#parts + 1] = "▮"
  end
  return table.concat(parts)
end

function M.setup()
  vim.opt.cmdheight = 0
  vim.opt.laststatus = 3
  vim.o.showmode = false
  vim.o.statusline = "%!v:lua.require'theme.heatmap'.render()"
end

return M
