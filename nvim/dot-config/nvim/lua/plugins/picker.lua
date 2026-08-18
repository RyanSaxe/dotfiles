-- Pickers respect gitignore but never hide dotfiles: dotfile-heavy
-- trees are daily terrain here and default hiding buries them.
--
-- The backdrop washes everything behind the picker toward the OUTER
-- crust rather than toward black, so what recedes still reads as this
-- theme. Snacks bakes that color into a highlight group on every open,
-- so it cannot be a group we repaint — the color has to be handed over
-- as a value. It re-reads `Snacks.config.picker` on every open though,
-- so writing the new value back on a theme change is enough to keep it
-- live.

---@return snacks.win.Backdrop|false
local function backdrop()
  -- `theme.load()` rather than `theme.tokens`: snacks builds its options
  -- before the colorscheme plugin has applied the theme, so the cached
  -- table is still empty here. Loading the generated file directly has
  -- no ordering dependency.
  ---@type ThemeTokens|nil
  local tokens = require("theme").load()
  if not tokens then
    return false
  end
  return { bg = tokens.outer.crust, blend = 60, transparent = true }
end

return {
  "folke/snacks.nvim",
  init = function()
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("picker_backdrop", { clear = true }),
      callback = function()
        ---@type table|nil
        local picker = require("snacks").config.picker
        if picker and picker.layout and picker.layout.layout then
          picker.layout.layout.backdrop = backdrop()
        end
      end,
    })
  end,
  opts = {
    picker = {
      -- `backdrop` belongs to the layout BOX, one level in — set on the
      -- picker's layout config it is silently ignored.
      layout = { layout = { backdrop = backdrop() } },
      sources = {
        files = { hidden = true },
        grep = { hidden = true },
        explorer = { hidden = true },
        gh_diff = {
          win = {
            preview = {
              keys = {
                ["<leader>gdr"] = {
                  function()
                    require("review_surfaces").from_snacks()
                  end,
                  mode = { "n", "x" },
                  desc = "Open Local CodeDiff",
                },
              },
            },
          },
        },
      },
    },
  },
}
