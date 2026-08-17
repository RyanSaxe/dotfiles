-- Pickers respect gitignore but never hide dotfiles: dotfile-heavy
-- trees are daily terrain here and default hiding buries them.

-- Snacks bakes the backdrop's color into a highlight group on every
-- picker open, so it cannot be a group we repaint — the color has to be
-- handed over as a value. Derived from the theme rather than written
-- down, but read once at startup: snacks merges win config as plain
-- tables and never calls a function, so a live inner/outer flip leaves
-- this one color stale until nvim restarts. Everything else repaints.
-- `theme.load()` rather than `theme.tokens`: snacks builds its options
-- before the colorscheme plugin has applied the theme, so the cached
-- table is still empty here. Loading the generated file directly has no
-- ordering dependency.
---@return snacks.win.Backdrop|false
local function backdrop()
  ---@type ThemeTokens|nil
  local tokens = require("theme").load()
  if not tokens then
    return false
  end
  return { bg = tokens.outer.crust, blend = 60, transparent = true }
end

return {
  "folke/snacks.nvim",
  opts = {
    picker = {
      -- The backdrop washes everything behind the picker toward the outer
      -- crust rather than toward black, so what recedes still reads as
      -- this theme. `backdrop` belongs to the layout BOX, one level in —
      -- set on the picker's layout config it is silently ignored.
      layout = { layout = { backdrop = backdrop() } },
      sources = {
        files = { hidden = true },
        grep = { hidden = true },
        explorer = { hidden = true },
      },
    },
  },
}
