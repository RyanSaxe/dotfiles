-- Which windows paint on the OUTER layer.
--
-- Neovim already separates hovering from anchored chrome: floats get
-- `NormalFloat`, everything else gets `Normal`. So the only windows that
-- need saying are the anchored non-file ones — an explorer, a help
-- split, a diagnostics list. Those run to a terminal edge and continue
-- the tmux rail, so they take the outer surface via `winhighlight`.
--
-- Doing it here rather than per-plugin means a new sidebar plugin is
-- themed the day it is installed, with no entry to add.
local M = {}

local WINHL = table.concat({
  "Normal:ThemeOuterNormal",
  "NormalNC:ThemeOuterNormalNC",
  "SignColumn:ThemeOuterNormal",
  "EndOfBuffer:ThemeOuterNormal",
  "WinSeparator:ThemeOuterWinSeparator",
  -- Snacks routes every one of its windows through these, float or not.
  "SnacksNormal:ThemeOuterNormal",
  "SnacksNormalNC:ThemeOuterNormalNC",
  "SnacksPickerList:ThemeOuterNormal",
}, ",")

---@param win integer
---@return boolean
local function is_anchored_sidebar(win)
  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return false
  end
  local buf = vim.api.nvim_win_get_buf(win)
  -- Content that happens to live in a virtual buffer is still content, and
  -- belongs on the inner surface. `buftype ~= ""` below means "not a file",
  -- which is a good proxy for chrome right up until a plugin renders
  -- something to read this way — CodeDiff's file panes, Snacks' pull request
  -- and issue buffers. Both are anchored, neither is a sidebar.
  --
  -- Two exemptions is the point at which the rule is worth revisiting: an
  -- allowlist of chrome filetypes would default new content buffers to the
  -- inner surface, which is correct more often than the reverse. Noted in
  -- notes/handoff/theme-role-completion.md rather than changed here.
  local name = vim.api.nvim_buf_get_name(buf)
  if name:match("^codediff://") or name:match("^gh://") then
    return false
  end
  return vim.bo[buf].buftype ~= "" or vim.bo[buf].filetype == "snacks_picker_list"
end

-- `winhighlight` is window-local, not buffer-local: a window that once
-- held a sidebar keeps painting outer after a file is opened in it.
-- So every pass rebuilds the value from scratch — strip what we own,
-- then re-add it only if the window still qualifies.
---@param winhighlight string
---@return string
local function without_ours(winhighlight)
  ---@type string[]
  local kept = {}
  for entry in winhighlight:gmatch("[^,]+") do
    if not entry:find("ThemeOuter", 1, true) then
      kept[#kept + 1] = entry
    end
  end
  return table.concat(kept, ",")
end

---@param win integer
local function apply(win)
  local base = without_ours(vim.wo[win].winhighlight)
  ---@type string
  local wanted = base
  if is_anchored_sidebar(win) then
    wanted = base == "" and WINHL or (base .. "," .. WINHL)
  end
  if vim.wo[win].winhighlight ~= wanted then
    vim.wo[win].winhighlight = wanted
  end
end

local function apply_all()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    apply(win)
  end
end

function M.setup()
  -- Every window, not just the current one: plugins open sidebars
  -- without ever focusing them.
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "FileType", "WinNew", "WinEnter" }, {
    group = vim.api.nvim_create_augroup("theme_surfaces", { clear = true }),
    callback = apply_all,
  })
  apply_all()
end

return M
