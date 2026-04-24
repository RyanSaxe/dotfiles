local Util = require("tokyonight.util")

local M = {}

local managed_groups = {
  TreesitterContext = { bg = true },
  TreesitterContextLineNumber = { bg = true },
  TreesitterContextBottom = { bg = true, underline = true },
  TreesitterContextLineNumberBottom = { bg = true, underline = true },
  BufferLineBufferSelected = { bg = true },
  BufferLineSeparatorSelected = { bg = true },
  BufferLineIndicatorSelected = { bg = true, fg_matches_bg = true },
  BufferLineModifiedSelected = { bg = true },
  BufferLineCloseButtonSelected = { bg = true },
  BufferLineTabSelected = { bg = true },
  BufferLineTabSeparatorSelected = { bg = true, fg_matches_bg = true },
  BufferLineDuplicateSelected = { bg = true },
  BufferLinePickSelected = { bg = true },
  BufferLineNumbersSelected = { bg = true },
  BufferLineErrorSelected = { bg = true },
  BufferLineErrorDiagnosticSelected = { bg = true },
  BufferLineWarningSelected = { bg = true },
  BufferLineWarningDiagnosticSelected = { bg = true },
  BufferLineInfoSelected = { bg = true },
  BufferLineInfoDiagnosticSelected = { bg = true },
  BufferLineHintSelected = { bg = true },
  BufferLineHintDiagnosticSelected = { bg = true },
  BufferLineDiagnosticSelected = { bg = true },
}

local state = {
  base_highlights = nil,
  context_visible = nil,
  wrapped = false,
}

local refresh_scheduled = false

local function current_colors()
  local c = require("tokyonight.colors").setup()
  return {
    base_bg = c.bg,
    context_bg = Util.blend_bg(c.purple, 0.1),
    underline_sp = Util.blend_bg(c.purple, 0.5),
  }
end

local function get_highlight(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  if ok then
    return hl
  end
end

local function capture_base_highlights()
  state.base_highlights = {}
  for name in pairs(managed_groups) do
    local hl = get_highlight(name)
    if hl then
      state.base_highlights[name] = hl
    end
  end
end

local function ensure_wrapped()
  if state.wrapped or not package.loaded["treesitter-context"] then
    return
  end

  local ts = require("treesitter-context")
  if ts._custom_treesitter_context_chrome_wrapped then
    state.wrapped = true
    return
  end

  local original_enable = ts.enable
  local original_disable = ts.disable

  ts.enable = function(...)
    local ret = original_enable(...)
    M.schedule_refresh()
    return ret
  end

  ts.disable = function(...)
    local ret = original_disable(...)
    M.schedule_refresh()
    return ret
  end

  ts._custom_treesitter_context_chrome_wrapped = true
  state.wrapped = true
end

local function has_visible_context(winid)
  if not winid or not vim.api.nvim_win_is_valid(winid) or not package.loaded["treesitter-context"] then
    return false
  end

  local ts = require("treesitter-context")
  if not ts.enabled or not ts.enabled() then
    return false
  end

  for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(vim.api.nvim_get_current_tabpage())) do
    local ok, is_context = pcall(function()
      return vim.w[candidate].treesitter_context
    end)
    if ok and is_context then
      local config = vim.api.nvim_win_get_config(candidate)
      local parent = tonumber(config.win) or config.win
      if config.relative == "win" and parent == winid then
        return true
      end
    end
  end

  return false
end

local function apply_state(context_visible)
  if not state.base_highlights then
    capture_base_highlights()
  end

  local colors = current_colors()
  local bg = context_visible and colors.context_bg or colors.base_bg

  for name, spec in pairs(managed_groups) do
    local base = state.base_highlights[name]
    if base then
      local hl = vim.deepcopy(base)
      if spec.bg then
        hl.bg = bg
      end
      if spec.fg_matches_bg then
        hl.fg = bg
      end
      if spec.underline then
        hl.underline = true
        hl.sp = colors.underline_sp
      end
      vim.api.nvim_set_hl(0, name, hl)
    end
  end

  local ok, ui = pcall(require, "bufferline.ui")
  if ok then
    ui.refresh()
  end
end

function M.refresh()
  ensure_wrapped()

  local visible = has_visible_context(vim.api.nvim_get_current_win())
  if state.context_visible == visible then
    return
  end

  state.context_visible = visible
  apply_state(visible)
end

function M.schedule_refresh()
  if refresh_scheduled then
    return
  end

  refresh_scheduled = true
  vim.schedule(function()
    refresh_scheduled = false
    M.refresh()
  end)
end

function M.setup()
  local group = vim.api.nvim_create_augroup("custom_treesitter_context_chrome", { clear = true })

  capture_base_highlights()
  ensure_wrapped()

  vim.api.nvim_create_autocmd({ "CursorMoved", "WinScrolled", "BufEnter", "WinEnter", "VimResized", "WinResized" }, {
    group = group,
    callback = function()
      M.schedule_refresh()
    end,
  })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      vim.schedule(function()
        capture_base_highlights()
        state.context_visible = nil
        M.refresh()
      end)
    end,
  })

  M.schedule_refresh()
end

return M
