-- Each split's own line at its top. The left side says which file the split
-- holds, its folders faint and its name bold while the split has focus. The
-- right side holds that split's facts: git counts, diagnostics by icon, and
-- the cursor's position. A file with unsaved changes gets a yellow dot. The
-- blocks the cursor is in belong to the sticky context header, not here.
local M = {}

---@param group string
---@param text string
---@return string
local function paint(group, text)
  return "%#" .. group .. "#" .. text
end

---@param s string
---@return string
local function esc(s)
  return (s:gsub("%%", "%%%%"))
end

---@param buf integer
---@return string
local function git_counts(buf)
  local ok, diff = pcall(require, "mini.diff")
  if not ok then
    return ""
  end
  local data = diff.get_buf_data(buf)
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

-- Icon then count, colored by severity. The icons are the sign column's own,
-- so the winbar shows exactly the marks the gutter shows.
---@param buf integer
---@return string
local function diagnostics(buf)
  local signs = vim.diagnostic.config().signs
  ---@type table<integer, string>
  local marks = type(signs) == "table" and signs.text or {}
  ---@type table<integer, integer>
  local counts = {}
  for _, d in ipairs(vim.diagnostic.get(buf)) do
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

-- Where a file is: its path from its repository's root, led by the
-- repository's name when that isn't the folder Neovim works in. A file
-- outside any repository shows its path from the home folder.
---@param buf integer
---@return string
local function location(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  local root = vim.fs.root(buf, ".git")
  if not root then
    return vim.fn.fnamemodify(path, ":~")
  end
  local rel = vim.fs.relpath(root, path) or vim.fn.fnamemodify(path, ":t")
  if root == vim.fn.getcwd() then
    return rel
  end
  return vim.fs.basename(root) .. "/" .. rel
end

-- The file's folders, then its name.
---@param buf integer
---@param focus boolean
---@return string
local function crumbs(buf, focus)
  local rel = location(buf)
  ---@type string[]
  local parts = {}
  for part in rel:gmatch("[^/]+") do
    parts[#parts + 1] = esc(part)
  end
  local name = table.remove(parts) or ""
  local file = paint(focus and "ThemeWinbarFile" or "ThemeWinbarFileNC", name)
  if vim.bo[buf].modified then
    file = file .. paint("ThemeWinbarDirty", " ●")
  end
  if #parts == 0 then
    return file
  end
  return paint("ThemeWinbarPath", table.concat(parts, " › ") .. " › ") .. file
end

---@return string
function M.render()
  local win = vim.g.statusline_winid or vim.api.nvim_get_current_win()
  local focus = win == (tonumber(vim.g.actual_curwin) or vim.api.nvim_get_current_win())
  local buf = vim.api.nvim_win_get_buf(win)
  local cursor = vim.api.nvim_win_get_cursor(win)
  ---@type string[]
  local right = {}
  for _, part in ipairs({ git_counts(buf), diagnostics(buf) }) do
    if part ~= "" then
      right[#right + 1] = part
    end
  end
  right[#right + 1] = paint("ThemeWinbarPath", cursor[1] .. ":" .. (cursor[2] + 1))
  return " " .. crumbs(buf, focus) .. "%=" .. table.concat(right, "  ") .. " "
end

-- Only real file windows get a winbar. Floats never render one, so pickers
-- are already exempt; splits holding an explorer, help, or a terminal must
-- be excluded by hand.
---@param win integer
local function apply(win)
  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  local normal = vim.bo[buf].buftype == "" and vim.bo[buf].filetype ~= ""
  vim.wo[win].winbar = normal and "%!v:lua.require'theme.winbar'.render()" or ""
end

function M.setup()
  vim.api.nvim_create_autocmd({ "BufWinEnter", "FileType", "WinEnter", "WinNew" }, {
    group = vim.api.nvim_create_augroup("theme_winbar", { clear = true }),
    callback = function()
      apply(vim.api.nvim_get_current_win())
    end,
  })
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    apply(win)
  end
end

return M
