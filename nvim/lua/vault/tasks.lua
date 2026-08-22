-- Tasks, all of them through the `vault` CLI. Neovim never edits a task line
-- and never parses one: the CLI owns the grammar, the project resolution,
-- and every date spelling, so this file is a prompt, a picker, and two
-- process calls.
local vault = require("vault")

local M = {}

---@class vault.TaskRow
---@field id string
---@field text string
---@field done boolean
---@field due string|nil
---@field state string
---@field project string|nil
---@field section string|nil
---@field file string vault-relative
---@field line integer 1-based

---@type table<string, string>
local STATE_HL = {
  overdue = "DiagnosticError",
  today = "DiagnosticWarn",
  tomorrow = "DiagnosticWarn",
  near = "DiagnosticHint",
}

---@param cwd string
---@param args string[]
---@param on_done fun(result: vim.SystemCompleted)
---@return nil
local function vault_cli(cwd, args, on_done)
  vim.system(vim.list_extend({ "vault" }, args), {
    cwd = cwd,
    env = vault.env(),
    text = true,
  }, vim.schedule_wrap(on_done))
end

---@param result vim.SystemCompleted
---@return string
local function failure(result)
  local message = vim.trim(result.stderr or "")
  if message == "" then
    message = vim.trim(result.stdout or "")
  end
  return message ~= "" and message or ("`vault` exited %d"):format(result.code)
end

---@param cwd string
---@param args string[]
---@return string|nil
local function git(cwd, args)
  local result = vim.system(vim.list_extend({ "git", "-C", cwd }, args), { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end
  local out = vim.trim(result.stdout or "")
  return out ~= "" and out or nil
end

-- Display only, and deliberately so. `vault task add` resolves the project
-- from the git remote of the directory it runs in and prints where the task
-- landed; that printed line is what the notification reports. This asks the
-- same question early enough to put the answer in the prompt title. When it
-- cannot answer — no repository, no origin — the title simply says less,
-- and the CLI still resolves and still reports.
---@param cwd string
---@param branch boolean
---@return string
local function prompt_title(cwd, branch)
  ---@type string[]
  local parts = {}

  local remote = git(cwd, { "remote", "get-url", "origin" })
  if remote then
    local trimmed = (remote:gsub("/+$", ""))
    local base = trimmed:match("([^/:]+)$") or trimmed
    parts[#parts + 1] = (base:gsub("%.git$", ""))
  end

  if branch then
    local head = git(cwd, { "rev-parse", "--abbrev-ref", "HEAD" })
    if head and head ~= "HEAD" then
      parts[#parts + 1] = head
    end
  end

  return #parts == 0 and "Task" or ("Task → " .. table.concat(parts, " / "))
end

-- The date is a suffix on the same line: "Ship the parser @fri". Only a
-- token after whitespace counts, so an address inside the text survives.
-- Everything after the @ goes to the CLI untouched — every spelling of a
-- date is read in exactly one place, and it is not this one.
---@param input string
---@return string text, string|nil due
local function split_due(input)
  local text, due = input:match("^(.-)%s+@(%S+)%s*$")
  if text and vim.trim(text) ~= "" then
    return vim.trim(text), due
  end
  return vim.trim(input), nil
end

-- `--branch` files the task under a heading named for the checked-out
-- branch; without it the task lands under the project file's own H1.
---@param branch boolean
---@return nil
function M.capture(branch)
  if not vault.require_dir() then
    return
  end

  -- The project comes from the working directory, so the window's cwd is
  -- the question being asked — including where `:lcd` has moved it.
  local cwd = vim.fn.getcwd()

  ---@param input string|nil
  vim.ui.input({ prompt = prompt_title(cwd, branch) }, function(input)
    if not input then
      return
    end
    local text, due = split_due(input)
    if text == "" then
      return
    end

    ---@type string[]
    local args = { "task", "add", text }
    if due then
      vim.list_extend(args, { "--due", due })
    end
    if branch then
      args[#args + 1] = "--branch"
    end

    ---@param result vim.SystemCompleted
    vault_cli(cwd, args, function(result)
      if result.code ~= 0 then
        vim.notify(failure(result), vim.log.levels.ERROR)
        return
      end
      vim.notify(vim.trim(result.stdout or ""))
    end)
  end)
end

-- Every task in the vault, as the CLI sees it. Its own seam so the picker
-- above it is the only part that needs a window.
---@param on_rows fun(rows: vault.TaskRow[])
---@return nil
function M.rows(on_rows)
  local dir = vault.require_dir()
  if not dir then
    return
  end

  ---@param result vim.SystemCompleted
  vault_cli(dir, { "tasks", "--json" }, function(result)
    if result.code ~= 0 then
      vim.notify(failure(result), vim.log.levels.ERROR)
      return
    end
    local ok, decoded = pcall(vim.json.decode, result.stdout or "", {
      luanil = { object = true, array = true },
    })
    if not ok then
      vim.notify("`vault tasks --json` returned something that is not JSON", vim.log.levels.ERROR)
      return
    end
    ---@type vault.TaskRow[]
    local rows = decoded
    on_rows(rows)
  end)
end

-- The query grammar is the matcher's, not a parser here: each item carries
-- `#project`, `@state`, its section, and its text in the string the matcher
-- scores, so `overdue`, `@today`, `#dotfiles`, and plain words all work
-- without anything in this file knowing about them.
---@param dir string
---@param row vault.TaskRow
---@return snacks.picker.finder.Item
local function item(dir, row)
  ---@type string[]
  local tokens = { row.text, "@" .. row.state }
  if row.project then
    tokens[#tokens + 1] = "#" .. row.project
  end
  if row.section then
    tokens[#tokens + 1] = row.section
  end
  if row.done then
    tokens[#tokens + 1] = "@done"
  end

  return {
    text = table.concat(tokens, " "),
    file = dir .. "/" .. row.file,
    pos = { row.line, 0 },
    task = row,
  }
end

---@param picker_item snacks.picker.Item
---@return snacks.picker.Highlight[]
local function format(picker_item)
  ---@type vault.TaskRow
  local row = picker_item.task
  ---@type snacks.picker.Highlight[]
  local parts = {
    { row.done and "[x] " or "[ ] ", row.done and "Comment" or "Special" },
    { row.text, row.done and "Comment" or nil },
  }
  if row.project then
    parts[#parts + 1] = { "  #" .. row.project, "Comment" }
  end
  if row.section and row.section ~= row.project then
    parts[#parts + 1] = { "  " .. row.section, "Comment" }
  end
  if row.due then
    parts[#parts + 1] = { ("  %s %s"):format(row.state, row.due), STATE_HL[row.state] or "Comment" }
  end
  return parts
end

---@return nil
function M.search()
  local dir = vault.require_dir()
  if not dir then
    return
  end

  ---@param rows vault.TaskRow[]
  M.rows(function(rows)
    if #rows == 0 then
      vim.notify("no tasks in the vault")
      return
    end
    ---@type snacks.picker.finder.Item[]
    local items = {}
    for _, row in ipairs(rows) do
      items[#items + 1] = item(dir, row)
    end
    Snacks.picker.pick({
      title = "Vault tasks",
      items = items,
      format = format,
      preview = "file",
    })
  end)
end

return M
