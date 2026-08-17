-- Chrome content. The statusline is reduced to two cells at the bottom
-- left — a state dot and the mode capital — on the buffer's own
-- background, so it reads as part of the gutter rather than as an edge
-- band. Everything else moved up: the winbar carries per-window git and
-- diagnostic facts directly under the tab row.
local M = {}

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

local PULSE_MS = 450

---@type boolean
local pulse_lit = false
local pulse_timer = nil

-- The dot rides the mode's color, so the pair reads as one object; while
-- a macro records it blinks red instead.
---@return string
local function state_group()
  if vim.fn.reg_recording() ~= "" and pulse_lit then
    return "ThemeStlRecording"
  end
  return mode_group()
end

---@param group string
---@param text string
---@return string
local function paint(group, text)
  return "%#" .. group .. "#" .. text
end

---@return string
function M.content()
  return paint(state_group(), " ●") .. paint(mode_group(), " " .. vim.fn.mode():sub(1, 1):upper())
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

-- Glyph then count, colored by severity. The glyphs are read from the
-- floor's icon table rather than copied here, so the winbar always
-- shows exactly what the sign column shows.
---@return string
local function diagnostics()
  -- The sign column's own configured text is the single source: whoever
  -- sets the signs, the winbar shows the same mark.
  local signs = vim.diagnostic.config().signs
  ---@type table<integer, string>
  local marks = type(signs) == "table" and signs.text or {}
  ---@type table<integer, integer>
  local counts = {}
  for _, d in ipairs(vim.diagnostic.get(0)) do
    counts[d.severity] = (counts[d.severity] or 0) + 1
  end
  local sev = vim.diagnostic.severity
  ---@type string[]
  local parts = {}
  for _, row in ipairs({ { sev.ERROR, "ThemeStlError" }, { sev.WARN, "ThemeStlWarn" } }) do
    local n = counts[row[1]]
    if n then
      parts[#parts + 1] = paint(row[2], (marks[row[1]] or "") .. n)
    end
  end
  return table.concat(parts, " ")
end

-- Diagnostics sit left, above the number column; git sits right, under
-- the tab row's branch.
---@return string
function M.winbar()
  return " " .. diagnostics() .. "%=" .. git_counts() .. paint("ThemeStlBranch", " ")
end

-- Only real file windows get a winbar. Floats never render one, so
-- pickers are already exempt; splits holding an explorer, help, or
-- terminal must be excluded by hand.
---@param win integer
local function apply_winbar(win)
  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  local normal = vim.bo[buf].buftype == "" and vim.bo[buf].filetype ~= ""
  vim.wo[win].winbar = normal and "%!v:lua.require'theme.statusline'.winbar()" or ""
end

local function apply_all()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    apply_winbar(win)
  end
end

function M.setup()
  require("mini.statusline").setup({
    use_icons = false,
    content = {
      active = M.content,
      inactive = M.content,
    },
  })

  local group = vim.api.nvim_create_augroup("theme_chrome", { clear = true })
  -- The first red frame comes from the autocmd, which runs in the main
  -- loop and flushes before nvim waits for the next key; the blink that
  -- follows needs a full redraw, since a statusline-only redraw from a
  -- timer never reaches an idle screen.
  vim.api.nvim_create_autocmd("RecordingEnter", {
    group = group,
    callback = function()
      pulse_lit = true
      vim.cmd.redrawstatus()
      if pulse_timer then
        return
      end
      pulse_timer = vim.uv.new_timer()
      if not pulse_timer then
        return
      end
      pulse_timer:start(
        PULSE_MS,
        PULSE_MS,
        vim.schedule_wrap(function()
          pulse_lit = not pulse_lit
          vim.cmd("redraw")
        end)
      )
    end,
  })
  vim.api.nvim_create_autocmd("RecordingLeave", {
    group = group,
    callback = function()
      if pulse_timer then
        pulse_timer:stop()
        pulse_timer:close()
        pulse_timer = nil
      end
      pulse_lit = false
      vim.cmd.redrawstatus()
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "FileType", "WinEnter", "WinNew" }, {
    group = group,
    callback = function()
      apply_winbar(vim.api.nvim_get_current_win())
    end,
  })
  -- Setup lands after the first windows exist, so seed them directly.
  apply_all()
end

return M
