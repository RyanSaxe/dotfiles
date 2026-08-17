-- Content and highlights for the six-fact statusline (see
-- plugins/statusline.lua for the layout contract).
local M = {}

local PULSE_MS = 450

---@type boolean
local pulse_lit = false
local pulse_timer = nil

---@return string
local function mode_group()
  ---@type string
  local m = vim.fn.mode():sub(1, 1)
  if m == "i" then
    return "ThemeStlInsert"
  elseif m == "v" or m == "V" or m == "\22" or m == "s" then
    return "ThemeStlVisual"
  elseif m == "c" then
    return "ThemeStlCommand"
  elseif m == "R" then
    return "ThemeStlReplace"
  elseif m == "t" then
    return "ThemeStlTerminal"
  end
  return "ThemeStlNormal"
end

---@param group string
---@param text string
---@return string
local function paint(group, text)
  return "%#" .. group .. "#" .. text
end

---@return string
local function git_counts()
  local ok, diff = pcall(require, "mini.diff")
  if not ok then
    return ""
  end
  local data = diff.get_buf_data(0)
  local s = data and data.summary
  if not s then
    return ""
  end
  ---@type string[]
  local parts = {}
  if (s.add or 0) > 0 then
    parts[#parts + 1] = paint("ThemeStlAdd", "+" .. s.add)
  end
  if (s.change or 0) > 0 then
    parts[#parts + 1] = paint("ThemeStlChange", "~" .. s.change)
  end
  if (s.delete or 0) > 0 then
    parts[#parts + 1] = paint("ThemeStlDelete", "-" .. s.delete)
  end
  return table.concat(parts, " ")
end

-- Counts only, colored by severity: the color IS the label.
---@return string
local function diagnostics()
  ---@type table<integer, integer>
  local counts = {}
  for _, d in ipairs(vim.diagnostic.get(0)) do
    counts[d.severity] = (counts[d.severity] or 0) + 1
  end
  local sev = vim.diagnostic.severity
  ---@type string[]
  local parts = {}
  -- Errors and warnings only: info and hint live in the gutter.
  for _, pair in ipairs({
    { sev.ERROR, "ThemeStlError" },
    { sev.WARN, "ThemeStlWarn" },
  }) do
    local n = counts[pair[1]]
    if n then
      parts[#parts + 1] = paint(pair[2], tostring(n))
    end
  end
  return table.concat(parts, " ")
end

---@return string
local function location_group()
  if vim.fn.reg_recording() ~= "" and pulse_lit then
    return "ThemeStlRecording"
  end
  return "ThemeStlLocation"
end

---@return string
function M.content()
  ---@type string
  local branch = vim.g.chrome_branch or ""
  local left = table.concat({
    paint(mode_group(), " " .. vim.fn.mode():sub(1, 1):upper() .. " "),
    branch ~= "" and paint("ThemeStlBranch", branch .. "  ") or "",
    git_counts(),
  })
  local right = table.concat({
    diagnostics(),
    "  ",
    paint(location_group(), "%l:%c "),
  })
  return left .. "%=" .. right
end

local function start_pulse()
  if pulse_timer then
    return
  end
  pulse_timer = vim.uv.new_timer()
  if not pulse_timer then
    return
  end
  pulse_timer:start(
    0,
    PULSE_MS,
    vim.schedule_wrap(function()
      pulse_lit = not pulse_lit
      vim.cmd.redrawstatus()
    end)
  )
end

local function stop_pulse()
  if pulse_timer then
    pulse_timer:stop()
    pulse_timer:close()
    pulse_timer = nil
  end
  pulse_lit = false
  vim.cmd.redrawstatus()
end

function M.setup()
  require("mini.statusline").setup({
    use_icons = false,
    content = {
      active = M.content,
      inactive = function()
        return "%#ThemeStlBranch#"
      end,
    },
  })
  require("theme.chrome").track_git()

  local group = vim.api.nvim_create_augroup("theme_statusline", { clear = true })
  vim.api.nvim_create_autocmd("RecordingEnter", { group = group, callback = start_pulse })
  vim.api.nvim_create_autocmd("RecordingLeave", { group = group, callback = stop_pulse })
end

return M
