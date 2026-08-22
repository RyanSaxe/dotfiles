-- What the vault surface needs from outside Neovim: a vault directory that
-- resolves, the `vault` CLI that owns every task write, and whatever the
-- CLI's own `check` has to say about the vault's contract.
--
-- Vault-structure knowledge lives in the CLI and nowhere else, so this
-- reports `vault check` rather than re-deriving it. A machine with no vault
-- yet is a normal state — install.sh offers one and never forces it — so it
-- warns rather than failing.
local M = {}

local vault = require("vault")

---@class vault.health.Finding
---@field level string
---@field message string
---@field detail string|nil

---@type table<string, fun(msg: string, advice?: string|string[])>
local REPORT = { ok = vim.health.ok, warn = vim.health.warn, fail = vim.health.error }

-- `vault check` prints "<level>  <message>", each optionally followed by an
-- indented detail line.
---@param stdout string
---@return vault.health.Finding[]
local function findings(stdout)
  ---@type vault.health.Finding[]
  local list = {}
  for line in vim.gsplit(stdout, "\n", { plain = true }) do
    local level, message = line:match("^(%a+)%s+(.+)$")
    if level and REPORT[level] then
      table.insert(list, { level = level, message = message })
    elseif #list > 0 and line:match("^%s+%S") then
      list[#list].detail = vim.trim(line)
    end
  end
  return list
end

---@param dir string
local function check_contract(dir)
  local result = vim
    .system({ "vault", "check", "--color", "never" }, {
      cwd = dir,
      env = vault.env(),
      text = true,
    })
    :wait(15000)

  local reported = findings(result.stdout or "")
  if #reported == 0 then
    vim.health.error("`vault check` produced nothing", { vim.trim(result.stderr or "") })
    return
  end
  for _, finding in ipairs(reported) do
    REPORT[finding.level](finding.message, finding.detail)
  end
end

function M.check()
  vim.health.start("vault")

  local dir = vault.dir()
  if vim.env.VAULT_DIR and vim.env.VAULT_DIR ~= "" then
    vim.health.info(("VAULT_DIR=%s"):format(dir))
  else
    vim.health.info(("VAULT_DIR is unset; falling back to %s"):format(dir))
  end

  local has_cli = vim.fn.executable("vault") == 1
  if has_cli then
    vim.health.ok("`vault` is on PATH")
  else
    vim.health.error("`vault` is not on PATH", {
      "re-run install.sh — every task write goes through it",
      "the vault's own contract goes unchecked without it",
    })
  end

  if not vault.exists() then
    vim.health.warn(("no vault at %s"):format(dir), {
      "re-run install.sh, which offers to clone or create one",
      "or run `vault init` against that path",
    })
    return
  end

  -- Everything below this line is `vault check` speaking. Its first finding
  -- names the vault, so nothing here repeats it.
  if has_cli then
    check_contract(dir)
  end
end

return M
