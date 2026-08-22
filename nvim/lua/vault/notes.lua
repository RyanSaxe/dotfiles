-- Notes: what kinds exist, how one is created, and how they are found.
--
-- The kinds are not listed here. Every template the CLI deploys declares its
-- own destination in a header:
--
--   ---
--   type: person
--   dir: people
--   ---
--   # {{title}}
--
-- so dropping a template into the deployed directory adds a type with no
-- change to this file. `daily.md` carries no header and is therefore not a
-- creatable type — obsidian.nvim reads it verbatim as the daily template.
local vault = require("vault")

local M = {}

---@class vault.NoteType
---@field name string
---@field dir string vault-relative
---@field body string[] the template with its header removed

---@param path string
---@return vault.NoteType|nil
local function read_type(path)
  local lines = vim.fn.readfile(path)
  if lines[1] ~= "---" then
    return nil
  end

  ---@type integer|nil
  local close
  for row = 2, #lines do
    if lines[row] == "---" then
      close = row
      break
    end
  end
  if not close then
    return nil
  end

  ---@type table<string, string>
  local header = {}
  for row = 2, close - 1 do
    local key, value = lines[row]:match("^(%w+):%s*(.-)%s*$")
    if key then
      header[key] = value
    end
  end
  if not header.type or not header.dir then
    return nil
  end

  local body = vim.list_slice(lines, close + 1)
  while body[1] == "" do
    table.remove(body, 1)
  end
  return { name = header.type, dir = header.dir, body = body }
end

---@return table<string, vault.NoteType>
function M.types()
  ---@type table<string, vault.NoteType>
  local types = {}
  local dir = vault.templates_dir()
  if vim.fn.isdirectory(dir) == 0 then
    return types
  end
  -- Not filtered on the entry kind: install.sh deploys these as symlinks.
  for name in vim.fs.dir(dir) do
    if name:match("%.md$") then
      local entry = read_type(dir .. "/" .. name)
      if entry then
        types[entry.name] = entry
      end
    end
  end
  return types
end

-- `Template.clone_template` copies the file line by line, substituting as it
-- goes, so the header has to be gone before the plugin ever opens it.
-- Stripping it into a temp file keeps that substitution engine rather than
-- reimplementing `{{...}}` here.
--
-- The engine knows {{id}}, {{title}}, {{path}}, {{date}} and {{time}}, each
-- with a {{var:format}} variant. Anything else it PROMPTS for, so a template
-- carrying an unknown variable will stop and wait — including where nothing
-- is driving it, like meeting capture.
---@param entry vault.NoteType
---@return string
local function materialize(entry)
  local path = vim.fn.tempname() .. ".md"
  vim.fn.writefile(entry.body, path)
  return path
end

-- Two traps sit in this one call. `should_write` was removed from
-- `Note.create`, so the note lives in memory until `write`. And
-- `note_id_func` is handed `opts.id` and never `opts.title`, so a title
-- alone yields a random zettel identifier like `1787334446-USPT.md` — `id`
-- plus `verbatim` is what makes the file name the name that was asked for.
-- The two differ only for a meeting's person note, whose file is a slug.
---@param entry vault.NoteType
---@param opts { id: string, title: string, open: boolean }
---@return nil
function M.create(entry, opts)
  if not vault.require_notes() then
    return
  end

  -- Typed loosely on purpose: obsidian.nvim is a runtime dependency of this
  -- module, not a compile-time one, and the strict Lua check has to pass on
  -- a machine that has not synced the plugin yet.
  ---@type any
  local note = require("obsidian.note").create({
    id = opts.id,
    title = opts.title,
    verbatim = true,
    dir = vim.fs.normalize(vault.dir() .. "/" .. entry.dir),
    template = materialize(entry),
  })
  if not note:exists() then
    note:write()
  end
  if opts.open then
    note:open({ sync = true })
  end
end

---@return nil
function M.new()
  if not vault.require_notes() then
    return
  end

  local types = M.types()
  ---@type string[]
  local names = {}
  for name in pairs(types) do
    table.insert(names, name)
  end
  if #names == 0 then
    vim.notify(("no note templates under %s — re-run install.sh"):format(vault.templates_dir()), vim.log.levels.ERROR)
    return
  end
  table.sort(names)

  ---@param choice string|nil
  vim.ui.select(names, { prompt = "New note" }, function(choice)
    if not choice then
      return
    end
    ---@param title string|nil
    vim.ui.input({ prompt = ("New %s"):format(choice) }, function(title)
      title = title and vim.trim(title) or ""
      if title == "" then
        return
      end
      M.create(types[choice], { id = title, title = title, open = true })
    end)
  end)
end

return M
