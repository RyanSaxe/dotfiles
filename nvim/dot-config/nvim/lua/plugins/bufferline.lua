-- The tab row straddles both theme layers. Its fill and the branch name
-- ride the OUTER surface, because the row touches the terminal's top
-- edge and must read as one piece with the tmux rail; the tabs
-- themselves ride the INNER surface, so the active tab looks cut out of
-- the buffer below it. When inner and outer run different modes, the
-- row is genuinely two-toned — that is the point, not a bug.
--
-- `highlights` is a function on purpose: bufferline re-invokes it on
-- every ColorScheme, so a live mode flip repaints the row. A baked table
-- would freeze whichever mode happened to be active at startup.

-- The branch name for the tab row, cached async so no render shells out.
local function track_git()
  local function refresh()
    vim.system({ "git", "rev-parse", "--abbrev-ref", "HEAD" }, { text = true }, function(out)
      local branch = out.code == 0 and vim.trim(out.stdout or "") or ""
      vim.schedule(function()
        vim.g.chrome_branch = branch
      end)
    end)
  end
  vim.api.nvim_create_autocmd({ "DirChanged", "FocusGained", "BufWritePost" }, {
    group = vim.api.nvim_create_augroup("chrome_git", { clear = true }),
    callback = refresh,
  })
  -- Setup runs after VimEnter has fired, so seed the value now too.
  refresh()
end

---@class TabRowSurfaces
---@field fill string outer: the row's own background
---@field fill_fg string outer: text sitting directly on the fill
---@field tab string inner: an unselected tab
---@field tab_fg string inner
---@field active string inner: the selected tab, matching the buffer
---@field active_fg string inner
---@field warn string inner: a dirty tab's label
---@field mode table<string, string> outer: one color per vim mode
---@field recording string outer

-- Every color is tagged with the layer it belongs to. Text on a tab must
-- come from the INNER roles and text on the fill from the OUTER ones —
-- otherwise the two halves of the row disagree the moment the layers run
-- different modes, which is exactly the case this split exists for.
---@return TabRowSurfaces
local function surfaces()
  ---@type ThemeTokens|nil
  local tokens = require("theme").tokens
  if not tokens then
    -- No generated theme (fresh machine, CI). There is only one layer,
    -- and its colors come from the floor's own palette — never from
    -- hexes written down here, which would be a second source of truth
    -- that silently drifts from the colorscheme.
    local c = require("catppuccin.palettes").get_palette()
    return {
      fill = c.crust,
      fill_fg = c.overlay0,
      tab = c.mantle,
      tab_fg = c.overlay0,
      active = c.base,
      active_fg = c.text,
      warn = c.yellow,
    }
  end
  local o, p = tokens.outer, tokens.palette
  return {
    fill = o.crust,
    fill_fg = o.fg_faint,
    tab = p.mantle,
    tab_fg = tokens.roles.fg_faint,
    active = p.base,
    active_fg = tokens.roles.fg,
    warn = p.yellow,
  }
end

-- Returns the mode's display letter and the highlight group that paints
-- it. Segments link to a group rather than carrying colors, because
-- bufferline registers custom-area colors with `default = true` — the
-- first paint of the session would win and the color would then never
-- change again, however often the row redraws.
---@return string letter, string group
local function mode()
  ---@type string
  local m = vim.fn.mode():sub(1, 1)
  if m == "i" then
    return "I", "ThemeModeInsert"
  elseif m == "v" or m == "V" or m == "\22" or m == "s" then
    return "V", "ThemeModeVisual"
  elseif m == "c" then
    return "C", "ThemeModeCommand"
  elseif m == "R" then
    return "R", "ThemeModeReplace"
  elseif m == "t" then
    return "T", "ThemeModeTerminal"
  end
  return "N", "ThemeModeNormal"
end

return {
  "akinsho/bufferline.nvim",
  event = "VeryLazy",
  -- Branch tracking starts at startup, not when the row is first built:
  -- `opts` may be evaluated once, late, or never, and the first paint
  -- would then have no branch to show.
  init = track_git,
  opts = function()
    return {
      options = {
        numbers = "none",
        separator_style = "slant",
        indicator = { style = "none" },
        show_buffer_icons = false,
        show_buffer_close_icons = false,
        show_close_icon = false,
        always_show_bufferline = true,
        diagnostics = false,
        custom_areas = {
          -- The right end of the row is the global-state readout: branch,
          -- then a state dot, then the mode capital. Both belong on a
          -- global bar — which the tab row is and a winbar is not.
          right = function()
            ---@type string
            local branch = vim.g.chrome_branch or ""
            local letter, group = mode()
            ---@type { text: string, link: string }[]
            local segments = {}
            if branch ~= "" then
              segments[#segments + 1] = { text = "  " .. branch, link = "ThemeBranch" }
            end
            local dot = require("theme.pulse").frame() or group
            segments[#segments + 1] = { text = "  ●", link = dot }
            segments[#segments + 1] = { text = " " .. letter .. " ", link = group }
            return segments
          end,
        },
      },
      highlights = function()
        local s = surfaces()
        local tab = { bg = s.tab, fg = s.tab_fg }
        local tab_active = { bg = s.active, fg = s.active_fg }
        -- The slant glyph is drawn in the fill color over the tab it
        -- trails, which is what carves the tab out of the row.
        return {
          fill = { bg = s.fill },
          background = tab,
          buffer_selected = { bg = s.active, fg = s.active_fg, bold = false, italic = false },
          buffer_visible = tab,
          modified = { bg = s.tab, fg = s.warn },
          modified_selected = { bg = s.active, fg = s.warn },
          modified_visible = { bg = s.tab, fg = s.warn },
          separator = { bg = s.tab, fg = s.fill },
          separator_selected = { bg = s.active, fg = s.fill },
          separator_visible = { bg = s.tab, fg = s.fill },
          duplicate = tab,
          duplicate_selected = tab_active,
          duplicate_visible = tab,
        }
      end,
    }
  end,
}
