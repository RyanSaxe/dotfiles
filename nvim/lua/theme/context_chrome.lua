-- While the sticky context header is visible, the selected tab wears the
-- header's wash instead of the buffer background. The selected tab is
-- drawn "cut out of" whatever sits beneath the row; when the context
-- header slides under it, keeping the plain buffer color leaves a
-- pale notch on top of a tinted band. v1 solved this with a 250-line
-- TokyoNight-coupled module managing twenty groups; today's tab row has
-- no icons, indicators, or diagnostics, so four groups cover it.
--
-- The wash color is read from the TreesitterContext group, so
-- highlights.lua stays the single place that decides what the header
-- looks like.

-- Only the background follows the header; each group's fg comes from
-- its captured base, so the modified-dot stays yellow and the slant
-- glyph keeps carving in the fill color.
--
-- The winbar sits between the tab row and the header, so it joins the
-- wash -- WinBar for the bar's own fill, and every group
-- theme/winbar.lua paints with, since each carries an explicit base
-- background that would otherwise stay behind as an unwashed island.
-- WinBarNC is deliberately absent: the header only ever covers the
-- active window.
local MANAGED = {
  "BufferLineBufferSelected",
  "BufferLineModifiedSelected",
  "BufferLineDuplicateSelected",
  "BufferLineSeparatorSelected",
  "WinBar",
  "ThemeStlAdd",
  "ThemeStlBranch",
  "ThemeStlChange",
  "ThemeStlDelete",
  "ThemeStlError",
  "ThemeStlWarn",
}

local M = {}

---@type table<string, vim.api.keyset.get_hl_info>
local base = {}
---@type boolean|nil
local visible_state
local scheduled = false

---@param name string
---@return vim.api.keyset.get_hl_info|nil
local function get_hl(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  return ok and hl or nil
end

-- Capture lazily, on first non-empty sighting. The groups arrive at
-- different times (highlights.lua at colorscheme, bufferline at
-- VeryLazy), and this module can run before bufferline has painted --
-- an eager capture then "restores" the selected tab to nothing.
---@param name string
local function capture(name)
  if base[name] then
    return
  end
  local hl = get_hl(name)
  if hl and next(hl) ~= nil then
    base[name] = hl
  end
end

---Is a context header currently shown over this window?
---@param winid integer
---@return boolean
local function context_visible(winid)
  if not package.loaded["treesitter-context"] then
    return false
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.w[win].treesitter_context then
      local config = vim.api.nvim_win_get_config(win)
      if config.relative == "win" and config.win == winid then
        return true
      end
    end
  end
  return false
end

---@param visible boolean
local function apply(visible)
  local wash = get_hl("TreesitterContext")
  for _, name in ipairs(MANAGED) do
    capture(name)
    -- A group never sighted has nothing to wash or restore; writing an
    -- empty table would CLEAR it for whoever defines it later.
    local info = base[name]
    if info then
      -- Projected by hand: nvim_get_hl and nvim_set_hl take different
      -- shapes, and these chrome groups only ever carry these attrs.
      ---@type vim.api.keyset.highlight
      local hl = { fg = info.fg, bg = info.bg, bold = info.bold, italic = info.italic }
      if visible and wash and wash.bg then
        hl.bg = wash.bg
      end
      vim.api.nvim_set_hl(0, name, hl)
    end
  end
  -- Plain redraws: the tab row repaints with redrawtabline, the winbar
  -- with the status machinery. Without them the wash visibly lingers
  -- after the state has already flipped. Deliberately not
  -- bufferline.ui.refresh() -- repainting does not need to route
  -- through plugin internals when :redrawtabline is the documented
  -- surface.
  vim.cmd("redrawtabline")
  vim.cmd("redrawstatus!")
end

local function refresh()
  local visible = context_visible(vim.api.nvim_get_current_win())
  if visible_state == visible then
    return
  end
  visible_state = visible
  apply(visible)
end

function M.setup()
  local group = vim.api.nvim_create_augroup("theme_context_chrome", { clear = true })
  -- Two checks per event burst: one on the next tick, one trailing.
  -- treesitter-context throttles its own redraw, so at the first check
  -- the float can still reflect the PREVIOUS cursor position; without
  -- the trailing check the state latches there -- verified by jumping
  -- gg out of a scope and watching the wash stay on.
  vim.api.nvim_create_autocmd({ "CursorMoved", "WinScrolled", "BufEnter", "WinEnter", "WinResized" }, {
    group = group,
    callback = function()
      if scheduled then
        return
      end
      scheduled = true
      vim.schedule(refresh)
      vim.defer_fn(function()
        scheduled = false
        refresh()
      end, 200)
    end,
  })
  -- A theme flip rebuilds every group; recapture the new bases and
  -- reapply against them.
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      vim.schedule(function()
        base = {}
        visible_state = nil
        refresh()
      end)
    end,
  })
end

return M
