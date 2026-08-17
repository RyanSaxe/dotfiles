-- Chrome color access for the statusline and bufferline: theme tokens
-- when the generated file exists, catppuccin constants otherwise (CI,
-- fresh machines). One table so both bars agree on every surface.

---@class ChromeColors
---@field crust string
---@field mantle string
---@field base string
---@field text string
---@field muted string
---@field dim string
---@field warn string
---@field err string
---@field info string
---@field hint string
---@field add string
---@field change string
---@field delete string
---@field accent string
---@field notify string
---@field mauve string
---@field pink string
---@field red string
---@field green string

local M = {}

---@return ChromeColors
function M.colors()
  ---@type ThemeTokens|nil
  local tokens = require("theme").tokens
  ---@type ThemePalette|nil
  local p = tokens and tokens.palette
  ---@type ThemeRoles|nil
  local r = tokens and tokens.roles
  return {
    crust = p and p.crust or "#11111b",
    mantle = p and p.mantle or "#181825",
    base = p and p.base or "#1e1e2e",
    text = r and r.fg or "#cdd6f4",
    muted = r and r.fg_faint or "#6c7086",
    dim = p and p.surface0 or "#313244",
    warn = p and p.yellow or "#f9e2af",
    err = p and p.red or "#f38ba8",
    info = p and p.blue or "#89b4fa",
    hint = p and p.teal or "#94e2d5",
    add = p and p.semantic_add or "#60a474",
    change = p and p.semantic_change or "#6197cd",
    delete = p and p.semantic_delete or "#c16771",
    accent = tokens and tokens.accent or "#d8b44a",
    notify = tokens and tokens.notify or "#69ceea",
    mauve = p and p.mauve or "#cba6f7",
    pink = p and p.pink or "#f5c2e7",
    red = p and p.red or "#f38ba8",
    green = p and p.green or "#a6e3a1",
  }
end

-- Git facts for the chrome, cached async so no bar render ever shells
-- out: branch, plus commits ahead/behind upstream.
function M.track_git()
  local group = vim.api.nvim_create_augroup("chrome_git", { clear = true })
  vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged", "FocusGained", "BufWritePost" }, {
    group = group,
    callback = function()
      vim.system({ "git", "rev-parse", "--abbrev-ref", "HEAD" }, { text = true }, function(out)
        local branch = out.code == 0 and vim.trim(out.stdout or "") or ""
        vim.schedule(function()
          vim.g.chrome_branch = branch
        end)
      end)
      vim.system({ "git", "rev-list", "--left-right", "--count", "HEAD...@{upstream}" }, { text = true }, function(out)
        local ahead, behind = 0, 0
        if out.code == 0 then
          local a, b = vim.trim(out.stdout or ""):match("^(%d+)%s+(%d+)$")
          ahead, behind = tonumber(a) or 0, tonumber(b) or 0
        end
        vim.schedule(function()
          vim.g.chrome_ahead = ahead
          vim.g.chrome_behind = behind
        end)
      end)
    end,
  })
end

return M
