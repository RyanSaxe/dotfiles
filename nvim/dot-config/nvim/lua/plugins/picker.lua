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

---@type table<number, snacks.picker.layout.Config>
local original_picker_layouts = {}

---@param picker snacks.Picker
---@param layout string
local function set_review_layout(picker, layout)
  if not original_picker_layouts[picker.id] then
    original_picker_layouts[picker.id] = vim.deepcopy(picker.resolved_layout)
  end
  picker:set_layout(layout)
end

---@param picker snacks.Picker
local function set_review_vertical_layout(picker)
  set_review_layout(picker, "review_vertical")
end

---@param picker snacks.Picker
local function set_review_horizontal_layout(picker)
  set_review_layout(picker, "review_horizontal")
end

---@param picker snacks.Picker
local function restore_picker_layout(picker)
  local original = original_picker_layouts[picker.id]
  picker:set_layout(original)
end

---@param picker snacks.Picker
local function toggle_preview_wrap(picker)
  local preview = picker.preview and picker.preview.win
  if not preview or not preview:valid() then
    return
  end

  local wrap = not vim.wo[preview.win].wrap
  vim.wo[preview.win].wrap = wrap
  vim.wo[preview.win].linebreak = wrap
  vim.wo[preview.win].breakindent = wrap
end

---@param mode string|string[]
---@return table<string, snacks.picker.Action.spec>
local function review_layout_keys(mode)
  return {
    ["<a-->"] = {
      "set_review_vertical_layout",
      mode = mode,
      desc = "Switch to vertical layout",
    },
    ["<a-\\>"] = {
      "set_review_horizontal_layout",
      mode = mode,
      desc = "Switch to horizontal layout",
    },
    ["<a-'>"] = {
      "restore_picker_layout",
      mode = mode,
      desc = "Restore original layout",
    },
    ["<c-w>"] = {
      "toggle_preview_wrap",
      mode = mode,
      desc = "Toggle preview wrap",
    },
  }
end

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
      layout = {
        preset = "review_vertical",
        layout = { backdrop = backdrop() },
      },
      actions = {
        set_review_vertical_layout = set_review_vertical_layout,
        set_review_horizontal_layout = set_review_horizontal_layout,
        restore_picker_layout = restore_picker_layout,
        toggle_preview_wrap = toggle_preview_wrap,
      },
      layouts = {
        review_vertical = {
          fullscreen = true,
          layout = {
            backdrop = false,
            box = "vertical",
            border = true,
            title = "{title} {live} {flags}",
            { win = "preview", border = "bottom" },
            { win = "input", height = 1, border = "bottom" },
            { win = "list", height = 5, border = "none" },
          },
        },
        review_horizontal = {
          fullscreen = true,
          layout = {
            backdrop = false,
            box = "horizontal",
            {
              box = "vertical",
              border = true,
              title = "{title} {live} {flags}",
              { win = "input", height = 1, border = "bottom" },
              { win = "list", border = "none" },
            },
            { win = "preview", title = "{preview}", border = true, width = 0.5 },
          },
        },
      },
      win = {
        input = { keys = review_layout_keys({ "n", "i" }) },
        list = { keys = review_layout_keys("n") },
        preview = { keys = review_layout_keys("n") },
      },
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
