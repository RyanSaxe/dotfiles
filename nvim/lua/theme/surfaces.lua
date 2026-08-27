-- Which windows paint on the OUTER layer.
--
-- Neovim already separates hovering from anchored chrome: floats get
-- `NormalFloat`, everything else gets `Normal`. So the only windows that
-- need saying are the anchored non-file ones — an explorer, a help
-- split, a diagnostics list. Those run to a terminal edge and continue
-- the tmux rail, so they take the outer surface via `winhighlight`.
--
-- Doing it here rather than per-plugin means a new sidebar plugin is
-- themed the day it is installed, with no entry to add. The snacks
-- explorer is the single named exception, below: it is a sidebar built
-- out of floats, so the rule above cannot see it.
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

-- The explorer is the one snacks window that belongs on the outer layer:
-- it runs to the terminal's right edge and continues the tmux rail. It
-- cannot say so in `winhighlight`, because snacks owns that value for the
-- windows it builds and re-asserts it from `win.opts.wo` on every layout
-- update — inside `eventignore=all`, so nothing here can even react to it.
-- Per-source config is no way in either: the picker resolves `win.list`
-- and `win.input` UNDER its own defaults rather than over them, so the
-- value never reaches the window (folke/snacks.nvim#2942).
--
-- So the surface moves out of `winhighlight`. These windows get their own
-- highlight namespace, in which the groups snacks paints them through mean
-- the outer surface instead. A namespace is not a window option, so snacks
-- never touches it: attach once and it holds. Groups left out keep their
-- global definition, which is why only the ones carrying a surface are
-- named here — and naming links rather than colors keeps every color
-- decision in theme.highlights, where a mode change repaints the targets
-- and these follow.
local OUTER_NS = vim.api.nvim_create_namespace("theme_outer_surface")

for group, link in pairs({
  -- The box takes `Normal`, the list and input that float inside it take
  -- `NormalFloat`. Which group carries either depends on the duplicate key
  -- that won inside snacks, so both spellings of each are named.
  SnacksNormal = "ThemeOuterNormal",
  SnacksNormalNC = "ThemeOuterNormalNC",
  SnacksPicker = "ThemeOuterNormal",
  SnacksPickerBox = "ThemeOuterNormal",
  SnacksPickerList = "ThemeOuterNormal",
  SnacksPickerInput = "ThemeOuterNormal",
  SignColumn = "ThemeOuterNormal",
  EndOfBuffer = "ThemeOuterNormal",
  SnacksPickerBorder = "ThemeOuterFrame",
  SnacksPickerBoxBorder = "ThemeOuterFrame",
  SnacksPickerListBorder = "ThemeOuterFrame",
  SnacksPickerInputBorder = "ThemeOuterFrame",
  SnacksTitle = "ThemeOuterFrame",
  SnacksPickerTitle = "ThemeOuterFrame",
  SnacksPickerBoxTitle = "ThemeOuterFrame",
  SnacksPickerListTitle = "ThemeOuterFrame",
  SnacksPickerInputTitle = "ThemeOuterFrame",
  SnacksWinSeparator = "ThemeOuterWinSeparator",
}) do
  vim.api.nvim_set_hl(OUTER_NS, group, { link = link })
end

---@param set table<integer, boolean>
---@param wins table<any, snacks.win>|nil
local function collect(set, wins)
  if not wins then
    return
  end
  for _, win in pairs(wins) do
    ---@type integer|nil
    local id = win.win
    if id and vim.api.nvim_win_is_valid(id) then
      set[id] = true
    end
  end
end

-- Windows belonging to an open explorer. `wins` holds its input and list,
-- `box_wins` the container they float inside. A previewed file stays in the
-- main editor window and is in neither, so this never claims the buffer.
---@return table<integer, boolean>
local function explorer_wins()
  ---@type table<integer, boolean>
  local set = {}
  local ok, snacks = pcall(require, "snacks")
  if not ok or not snacks.picker then
    return set
  end
  ---@type snacks.Picker[]
  local open = snacks.picker.get({ source = "explorer" })
  for _, picker in ipairs(open) do
    if picker.layout then
      collect(set, picker.layout.wins)
      collect(set, picker.layout.box_wins)
    end
  end
  return set
end

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
  -- Three of these now, which is past the point where the rule is worth
  -- revisiting: an allowlist of chrome filetypes would default new content
  -- buffers to the inner surface, which is correct more often than the
  -- reverse. Recorded in notes/handoff/theme-role-completion.md rather than
  -- changed here, because it is a judgement about every plugin at once.
  local name = vim.api.nvim_buf_get_name(buf)
  if name:match("^codediff://") or name:match("^gh://") then
    return false
  end
  -- The start screen is a thing you look at, not a sidebar. It is caught
  -- late rather than at startup: snacks sets `nofile` after the first pass
  -- runs, so the dashboard only turns to crust once something else — an
  -- explorer, say — triggers another pass.
  if vim.bo[buf].filetype == "snacks_dashboard" then
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
---@param explorer table<integer, boolean>
local function apply(win, explorer)
  -- The explorer carries its surface in a namespace, not in `winhighlight`.
  if explorer[win] then
    if vim.api.nvim_get_hl_ns({ winid = win }) ~= OUTER_NS then
      vim.api.nvim_win_set_hl_ns(win, OUTER_NS)
    end
    return
  end
  -- A window that once held the explorer is an ordinary window again.
  if vim.api.nvim_get_hl_ns({ winid = win }) == OUTER_NS then
    vim.api.nvim_win_set_hl_ns(win, -1)
  end
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
  local explorer = explorer_wins()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    apply(win, explorer)
  end
end

-- For a window that appears on a later tick than the call that asked for it:
-- an autocmd pass would land after the first redraw and the window would be
-- seen on the wrong surface before it corrected. Callers that know the moment
-- their windows exist call this instead (see plugins/explorer.lua).
function M.refresh()
  apply_all()
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
