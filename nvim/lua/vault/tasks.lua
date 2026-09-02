-- Tasks flow through the `vault` CLI. Neovim prompts, scopes, and presents
-- them; the CLI owns the Markdown grammar, project resolution, and dates.
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

---@type table<string, integer>
local STATE_ORDER = {
  overdue = 1,
  today = 2,
  tomorrow = 3,
  near = 4,
  later = 5,
  none = 6,
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

---@param cwd string
---@return string|nil
function M.project(cwd)
  if not git(cwd, { "rev-parse", "--show-toplevel" }) then
    return nil
  end
  local remote = git(cwd, { "remote", "get-url", "origin" })
  if not remote then
    local remotes = git(cwd, { "remote" })
    ---@type string|nil
    local first
    local count = 0
    if remotes then
      count = 0
      for name in remotes:gmatch("%S+") do
        count = count + 1
        first = name
      end
    end
    remote = count == 1 and first and git(cwd, { "remote", "get-url", first }) or nil
  end
  if not remote then
    return nil
  end
  local trimmed = remote:gsub("/+$", "")
  local base = trimmed:match("([^/:]+)$") or trimmed
  return base:gsub("%.git$", "")
end

---@param cwd string
---@param branch boolean
---@return string
local function prompt_title(cwd, branch)
  ---@type string[]
  local parts = {}
  local project = M.project(cwd)
  if project then
    parts[#parts + 1] = project
  end

  if branch then
    local head = git(cwd, { "rev-parse", "--abbrev-ref", "HEAD" })
    if head and head ~= "HEAD" then
      parts[#parts + 1] = head
    end
  end

  return #parts == 0 and "Task" or ("Task → " .. table.concat(parts, " / "))
end

-- The date is a suffix on the same line: "Ship the parser @fri".
---@param input string
---@return string text, string|nil due
local function split_due(input)
  local text, due = input:match("^(.-)%s+@(%S+)%s*$")
  if text and vim.trim(text) ~= "" then
    return vim.trim(text), due
  end
  return vim.trim(input), nil
end

---@param branch boolean
---@return nil
function M.capture(branch)
  if not vault.require_dir() then
    return
  end

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

---@param a vault.TaskRow
---@param b vault.TaskRow
---@return boolean
local function task_order(a, b)
  local a_order = STATE_ORDER[a.state] or STATE_ORDER.none
  local b_order = STATE_ORDER[b.state] or STATE_ORDER.none
  if a_order ~= b_order then
    return a_order < b_order
  end
  if a.due ~= b.due then
    if not a.due then
      return false
    end
    if not b.due then
      return true
    end
    return a.due < b.due
  end
  local a_text, b_text = a.text:lower(), b.text:lower()
  if a_text ~= b_text then
    return a_text < b_text
  end
  if a.text ~= b.text then
    return a.text < b.text
  end
  if a.file ~= b.file then
    return a.file < b.file
  end
  return a.line < b.line
end

---@param dir string
---@param row vault.TaskRow
---@return snacks.picker.finder.Item
local function item(dir, row)
  -- This is intentionally plain text. Snacks supplies its normal fuzzy/live
  -- matcher; task state and project are display metadata, not a query syntax.
  local tokens = { row.text, row.file }
  if row.project then
    tokens[#tokens + 1] = row.project
  end
  if row.section then
    tokens[#tokens + 1] = row.section
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
    { "[ ] ", "Special" },
    { row.text, nil },
  }
  if row.project then
    parts[#parts + 1] = { "  " .. row.project, "Comment" }
  end
  if row.section and row.section ~= row.project then
    parts[#parts + 1] = { "  " .. row.section, "Comment" }
  end
  if row.due then
    parts[#parts + 1] = { ("  %s %s"):format(row.state, row.due), STATE_HL[row.state] or "Comment" }
  end
  return parts
end

---@param scope? "all"|"project"
---@return nil
function M.search(scope)
  scope = scope or "all"
  local dir = vault.require_dir()
  if not dir then
    return
  end

  ---@type string|nil
  local project
  if scope == "project" then
    project = M.project(vim.fn.getcwd())
    if not project then
      vim.notify("the current directory has no identifiable git project", vim.log.levels.ERROR)
      return
    end
  end

  ---@param rows vault.TaskRow[]
  M.rows(function(rows)
    ---@type vault.TaskRow[]
    local matching = {}
    for _, row in ipairs(rows) do
      if not row.done and (not project or row.project == project) then
        matching[#matching + 1] = row
      end
    end
    table.sort(matching, task_order)
    if #matching == 0 then
      vim.notify(scope == "project" and ("no open tasks for " .. project) or "no open tasks")
      return
    end

    ---@type snacks.picker.finder.Item[]
    local items = {}
    for _, row in ipairs(matching) do
      items[#items + 1] = item(dir, row)
    end
    Snacks.picker.pick({
      title = scope == "project" and ("Tasks: " .. project) or "Vault tasks",
      items = items,
      format = format,
      preview = "file",
    })
  end)
end

---@param result vim.SystemCompleted
---@return nil
local function refresh_after_due(result)
  if result.code ~= 0 then
    vim.notify(failure(result), vim.log.levels.ERROR)
    return
  end
  vim.cmd.checktime()
  vim.notify(vim.trim(result.stdout or ""))
end

---@return nil
function M.set_due()
  local dir = vault.require_dir()
  if not dir then
    return
  end
  local path = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
  if path == "" or not path:match("%.md$") or vim.fn.filereadable(path) == 0 then
    vim.notify("place the cursor in a saved Markdown task", vim.log.levels.ERROR)
    return
  end
  if path ~= dir and not vim.startswith(path, dir .. "/") then
    vim.notify("the current task is outside the vault", vim.log.levels.ERROR)
    return
  end
  if vim.bo.modified then
    vim.notify("save the note before setting a task date", vim.log.levels.ERROR)
    return
  end

  local relative = vim.fs.relpath(dir, path)
  if not relative then
    vim.notify("could not resolve the current note inside the vault", vim.log.levels.ERROR)
    return
  end
  local line = vim.api.nvim_win_get_cursor(0)[1]
  ---@param input string|nil
  vim.ui.input({ prompt = "Due date (@today, @fri, @tmr, @3d, or YYYY-MM-DD)" }, function(input)
    if not input then
      return
    end
    local value = vim.trim(input):gsub("^@", "")
    if value == "" then
      return
    end
    vault_cli(dir, { "task", "due", (relative .. ":" .. line), value }, refresh_after_due)
  end)
end

return M
