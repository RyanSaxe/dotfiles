-- Where the vault is. Every other module in this namespace asks here.
--
-- Neovim can be launched with no shell environment at all (Finder, a GUI
-- launcher), so VAULT_DIR is not guaranteed to be set even though zshenv
-- exports it. The fallback below is the only copy of the default path in
-- the tree. The CLI deliberately carries none — it errors rather than
-- guess — so every process spawned from here is handed the resolved value.
local M = {}

local FALLBACK = "~/generic/vault"

---@type string|nil
local resolved

---@param name string
---@return string|nil
local function env(name)
  ---@type string|nil
  local value = vim.env[name]
  if value == nil or value == "" then
    return nil
  end
  return value
end

-- Absolute and normalized. May not exist; `require_dir` is the gate.
---@return string
function M.dir()
  if not resolved then
    resolved = vim.fs.normalize(env("VAULT_DIR") or FALLBACK)
  end
  return resolved
end

---@return boolean
function M.exists()
  return vim.fn.isdirectory(M.dir()) == 1
end

-- The single failure message for the whole layer. A nil return means the
-- user has already been told; the caller just stops.
---@return string|nil
function M.require_dir()
  local dir = M.dir()
  if vim.fn.isdirectory(dir) == 1 then
    return dir
  end
  vim.notify(
    ("no vault at %s — set VAULT_DIR, or run `vault init` (install.sh offers to)"):format(dir),
    vim.log.levels.ERROR
  )
  return nil
end

-- Notes, daily notes, links, and backlinks all go through obsidian.nvim,
-- whose setup is skipped while no vault exists — its workspace check raises
-- on a path that is not there. A vault made while Neovim is running
-- therefore leaves the plugin loaded but never set up, and the first note
-- call would fail on a nil global instead of saying anything useful.
---@return boolean
function M.require_notes()
  if not M.require_dir() then
    return false
  end
  -- The global obsidian.nvim's own :Obsidian command tests for, read the
  -- way it must be read from outside the plugin.
  if rawget(_G, "Obsidian") == nil then
    vim.notify("the vault appeared after Neovim started — restart it to open notes", vim.log.levels.ERROR)
    return false
  end
  return true
end

-- Where install.sh deploys the templates the CLI ships.
--
-- $XDG_CONFIG_HOME is usually unset on macOS, and `vim.fn.expand()` hands
-- back the literal "$XDG_CONFIG_HOME/..." string when it is — a path that
-- silently resolves to nothing. The fallback is spelled out for that
-- reason, and mirrors the CLI's own resolution.
---@return string
function M.templates_dir()
  return vim.fs.normalize(env("XDG_CONFIG_HOME") or "~/.config") .. "/vault/templates"
end

-- Handed to every `vault` spawn: the CLI has no fallback of its own, and a
-- Neovim started outside a shell would otherwise fail its VAULT_DIR check
-- while this layer knows perfectly well where the vault is. `vim.system`
-- merges this into the inherited environment.
---@return table<string, string>
function M.env()
  return { VAULT_DIR = M.dir() }
end

return M
