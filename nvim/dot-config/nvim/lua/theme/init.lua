-- Bridge between the theme system and nvim. Loads the generated token
-- file (inner layer), applies the catppuccin floor plus the semantic
-- layer in highlights.lua, and watches the generated dir so mode and
-- mascot changes repaint running instances. Without a generated file
-- (fresh machine, CI) the stock catppuccin floor stands alone.
local M = {}

local state_home = vim.env.XDG_STATE_HOME or (vim.env.HOME .. "/.local/state")
local generated_dir = state_home .. "/dotfiles/generated"
local tokens_path = generated_dir .. "/nvim-tokens.lua"

---@return table|nil
function M.load()
  local ok, tokens = pcall(dofile, tokens_path)
  if ok and type(tokens) == "table" then
    return tokens
  end
  return nil
end

M.tokens = nil

function M.apply()
  local tokens = M.load()
  M.tokens = tokens
  local light = tokens and tokens.mode == "light"
  vim.o.background = light and "light" or "dark"
  vim.cmd.colorscheme(light and "catppuccin-latte" or "catppuccin-mocha")
end

local function watch()
  local handle = vim.uv.new_fs_event()
  if not handle then
    return
  end
  -- The theme system writes via tmp+mv, so watch the directory and
  -- debounce: one repaint per render burst.
  local pending = false
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

function M.setup()
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
  if vim.uv.fs_stat(generated_dir) then
    watch()
  end
end

return M
