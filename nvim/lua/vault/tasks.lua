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

---@param dir string
---@param project string
---@return string|nil
local function project_file(dir, project)
  if project == "" or project == "." or project == ".." or project:find("[/\\]") then
    vim.notify(("unsafe project name: %s"):format(project), vim.log.levels.ERROR)
    return nil
  end

  local path = vim.fs.normalize(dir .. "/projects/" .. project .. "/TODO.md")
  if path ~= dir and not vim.startswith(path, dir .. "/") then
    vim.notify("the project task file would be outside the vault", vim.log.levels.ERROR)
    return nil
  end
  if vim.fn.isdirectory(path) == 1 then
    vim.notify(("project task path is a directory: %s"):format(path), vim.log.levels.ERROR)
    return nil
  end

  local parent = vim.fs.dirname(path)
  if vim.fn.mkdir(parent, "p") == 0 and vim.fn.isdirectory(parent) == 0 then
    vim.notify(("could not create project task directory: %s"):format(parent), vim.log.levels.ERROR)
    return nil
  end
  if vim.fn.filereadable(path) == 0 then
    if vim.fn.writefile({ "# " .. project, "" }, path) ~= 0 or vim.fn.filereadable(path) == 0 then
      vim.notify(("could not create project task file: %s"):format(path), vim.log.levels.ERROR)
      return nil
    end
  end
  return path
end

---@param with_branch boolean
---@return nil
function M.open_project(with_branch)
  local dir = vault.require_dir()
  if not dir then
    return
  end
  local cwd = vim.fn.getcwd()
  local project = M.project(cwd)
  if not project then
    vim.notify("the current directory has no identifiable git project", vim.log.levels.ERROR)
    return
  end

  ---@type string|nil
  local branch
  if with_branch then
    branch = git(cwd, { "rev-parse", "--abbrev-ref", "HEAD" })
    if not branch or branch == "HEAD" then
      vim.notify("the current checkout has no branch", vim.log.levels.ERROR)
      return
    end
  end

  local path = project_file(dir, project)
  if not path then
    return
  end
  vim.cmd({ cmd = "edit", args = { path } })
  if not branch then
    return
  end

  local heading = "## " .. branch
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for row, line in ipairs(lines) do
    if line == heading then
      vim.api.nvim_win_set_cursor(0, { row, 0 })
      return
    end
  end
  if vim.bo.modified then
    vim.notify("save the project task file before adding its branch section", vim.log.levels.ERROR)
    return
  end

  ---@type string[]
  local block = {}
  local heading_line = #lines + 1
  if #lines > 0 and vim.trim(lines[#lines]) ~= "" then
    block[#block + 1] = ""
    heading_line = heading_line + 1
  end
  block[#block + 1] = heading
  block[#block + 1] = ""
  vim.api.nvim_buf_set_lines(0, #lines, #lines, false, block)
  vim.cmd.update()
  vim.api.nvim_win_set_cursor(0, { heading_line, 0 })
end

---@return nil
function M.checkbox()
  local path = vim.api.nvim_buf_get_name(0)
  if vim.bo.filetype ~= "markdown" and not path:match("%.md$") then
    vim.notify("place the cursor in a Markdown file", vim.log.levels.ERROR)
    return
  end
  if not vim.bo.modifiable then
    vim.notify("the current buffer is not modifiable", vim.log.levels.ERROR)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local current = vim.api.nvim_get_current_line()
  local indent = current:match("^%s*") or ""
  ---@type string
  local text = indent .. "- [ ] "
  vim.api.nvim_buf_set_lines(0, cursor[1], cursor[1], false, { text })
  vim.api.nvim_win_set_cursor(0, { cursor[1] + 1, #text })
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
