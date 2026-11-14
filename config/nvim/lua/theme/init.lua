-- Bridge between the theme and nvim. Loads the token file each home switch
-- renders from theme/apps/nvim.nix, which ~/.config/theme links to the current mode,
-- applies the catppuccin floor plus the semantic layer in highlights.lua,
-- and watches that folder so a flip repaints running instances. Without the
-- file (fresh machine, CI) the stock catppuccin floor stands alone.
---@class ThemeRoles
---@field bg string
---@field bg_alt string
---@field bg_highlight string
---@field fg string
---@field fg_muted string
---@field fg_faint string
---@field border string
---@field warn string
---@field success string
---@field info string
---@field ghost string

---@class ThemePalette
---@field rosewater string
---@field flamingo string
---@field pink string
---@field mauve string
---@field red string
---@field maroon string
---@field peach string
---@field yellow string
---@field green string
---@field teal string
---@field sky string
---@field sapphire string
---@field blue string
---@field lavender string
---@field semantic_add string
---@field semantic_delete string
---@field semantic_change string
---@field text string
---@field subtext1 string
---@field subtext0 string
---@field overlay2 string
---@field overlay1 string
---@field overlay0 string
---@field surface2 string
---@field surface1 string
---@field surface0 string
---@field base string
---@field mantle string
---@field crust string
---@field chrome string

---@class ThemeTokens
---@field mode "dark"|"light"
---@field accent string
---@field notify string
---@field roles ThemeRoles
---@field palette ThemePalette
---@field code table<string, string> the code tiers bat, delta and zsh share

local M = {}

---@type string
local generated_dir = vim.env.HOME .. "/.config/theme"
local tokens_path = generated_dir .. "/nvim-tokens.lua"

-- The theme's folder: one folder of files for each mode, and links beside
-- them to the current mode's.
M.dir = generated_dir

---@return ThemeTokens|nil
function M.load()
  local ok, tokens = pcall(dofile, tokens_path)
  if ok and type(tokens) == "table" then
    return tokens
  end
  return nil
end

---@type ThemeTokens|nil
M.tokens = nil

---@type table
M.floor_opts = {}

function M.apply()
  local tokens = M.load()
  M.tokens = tokens
  local light = tokens and tokens.mode == "light"
  local flavour = light and "latte" or "mocha"
  -- The generated palette IS the palette: feed it to the floor so every
  -- plugin integration paints with it, never stock catppuccin values.
  ---@type table
  local opts = M.floor_opts
  if tokens then
    ---@type table
    local merged = vim.tbl_deep_extend("force", opts, { color_overrides = { [flavour] = tokens.palette } })
    opts = merged
  end
  require("catppuccin").setup(opts)
  vim.o.background = light and "light" or "dark"
  vim.cmd.colorscheme("catppuccin-" .. flavour)
end

local function watch()
  local handle = vim.uv.new_fs_event()
  if not handle then
    return
  end
  -- A switch replaces the links in that folder, so watch the directory and
  -- debounce: one repaint per render burst.
  local pending = false
  ---@param filename string|nil
  handle:start(generated_dir, {}, function(_, filename)
    if filename ~= "nvim-tokens.lua" or pending then
      return
    end
    pending = true
    vim.defer_fn(function()
      pending = false
      M.apply()
    end, 100)
  end)
end

---@param floor_opts table catppuccin setup opts from the plugin spec
function M.setup(floor_opts)
  M.floor_opts = floor_opts
  vim.api.nvim_create_autocmd("ColorScheme", {
    pattern = "catppuccin*",
    group = vim.api.nvim_create_augroup("theme_semantic_layer", { clear = true }),
    callback = function()
      if M.tokens then
        require("theme.highlights").apply(M.tokens)
      end
    end,
  })
  M.apply()
  require("theme.surfaces").setup()
  require("theme.statusline").setup()
  require("theme.winbar").setup()
  require("theme.pulse").setup()
  if vim.uv.fs_stat(generated_dir) then
    watch()
  end
end

return M
