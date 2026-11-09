-- Per-window chrome. There is no statusline at all: it spanned the full
-- width and cut the chrome surface off before the terminal's bottom edge,
-- so a right-hand explorer never reached the floor. Global state (mode,
-- recording, branch) moved to the tab row, which is genuinely global;
-- what is left here is per-window and belongs under the tab row —
-- diagnostics on the left, git counts on the right.
local M = {}

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
  vim.wo[win].winbar = normal and "%!v:lua.require'theme.winbar'.winbar()" or ""
end

local function apply_all()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    apply_winbar(win)
  end
end

function M.setup()
  vim.api.nvim_create_autocmd({ "BufWinEnter", "FileType", "WinEnter", "WinNew" }, {
    group = vim.api.nvim_create_augroup("theme_winbar", { clear = true }),
    callback = function()
      apply_winbar(vim.api.nvim_get_current_win())
    end,
  })
  -- Setup lands after the first windows exist, so seed them directly.
  apply_all()
end

return M
