-- Pickers respect gitignore but never hide dotfiles: dotfile-heavy
-- trees are daily terrain here and default hiding buries them.
--
-- The backdrop washes everything behind the picker toward crust
-- rather than toward black, so what recedes still reads as this
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

-- `<leader>sf` scopes a search to a directory picked from the current
-- file's ancestors. Root detection cannot answer "this package":
-- LazyVim's lsp detector returns the attached client's root_dir, which
-- for a file inside node_modules or site-packages is the project, not
-- the dependency. Locating a real package root needs per-ecosystem
-- knowledge that does not extend to the next language, so the choice is
-- offered rather than guessed. That also keeps "search my project from
-- inside a dependency" reachable, which an automatic override would take
-- away.

-- Deep enough to reach a repo root from a nested dependency, short
-- enough that the list stays scannable.
local MAX_ANCESTORS = 12

---Directories from the current file upward, nearest first.
---@return string[]
local function ancestors()
  local name = vim.api.nvim_buf_get_name(0)
  -- Trailing "." is unreachable in practice; it keeps the value a plain
  -- string, since both dirname and cwd are optional.
  local start = (name ~= "" and vim.fs.dirname(name)) or vim.uv.cwd() or "."
  ---@type string[]
  local dirs = { start }
  for parent in vim.fs.parents(start) do
    if #dirs >= MAX_ANCESTORS or parent == "/" then
      break
    end
    dirs[#dirs + 1] = parent
  end
  return dirs
end

---@type fun(source: string, cwd: string)
local open_scoped

-- Snacks binds a picker's finder once at construction, so a live picker
-- cannot change source. Closing and reopening on the same cwd is the
-- pattern its own explorer uses. The typed query does not carry over:
-- query history is namespaced per source.
---@param picker snacks.Picker
local function scope_to_files(picker)
  local cwd = picker:cwd()
  picker:close()
  open_scoped("files", cwd)
end

---@param picker snacks.Picker
local function scope_to_grep(picker)
  local cwd = picker:cwd()
  picker:close()
  open_scoped("grep", cwd)
end

---Open one scoped picker. The flip keys are attached per picker rather
---than globally, because <c-g> is toggle_live everywhere else.
---@param source string `"grep"` or `"files"`
---@param cwd string
function open_scoped(source, cwd)
  Snacks.picker[source]({
    cwd = cwd,
    actions = { scope_to_files = scope_to_files, scope_to_grep = scope_to_grep },
    win = {
      input = {
        keys = {
          ["<c-f>"] = { "scope_to_files", mode = { "n", "i" }, desc = "File names in this directory" },
          ["<c-g>"] = { "scope_to_grep", mode = { "n", "i" }, desc = "File contents in this directory" },
        },
      },
    },
  })
end

---@param item string
---@return string
local function shorten(item)
  return vim.fn.fnamemodify(item, ":~")
end

---@param choice string? nil when the selection is cancelled
local function grep_chosen_directory(choice)
  if choice then
    open_scoped("grep", choice)
  end
end

---Pick an ancestor directory, then search inside it.
local function search_in_directory()
  Snacks.picker.select(ancestors(), { prompt = "Search in", format_item = shorten }, grep_chosen_directory)
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
  return { bg = tokens.palette.crust, blend = 60, transparent = true }
end

return {
  "folke/snacks.nvim",
  keys = {
    { "<leader>sf", search_in_directory, desc = "Search in Directory" },
  },
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
            { win = "list", height = 8, border = "none" },
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
          group = false,
          ---@param picker snacks.Picker
          on_show = function(picker)
            Snacks.picker.actions.focus_preview(picker)
          end,
        },
      },
    },
  },
  ---@param opts table
  config = function(_, opts)
    require("snacks").setup(opts)
    require("git_review").setup()
  end,
}
