-- Vault note types and the Snacks pickers that act on them.
--
-- Creatable types come from the deployed templates. Each one declares its
-- destination in a small header, so people and meetings share the same
-- creation path while remaining separate note families.
local vault = require("vault")

local M = {}

---@class vault.NoteType
---@field name string
---@field dir string vault-relative
---@field body string[] the template with its header removed

---@class vault.NoteItem
---@field text string
---@field title string
---@field file string|nil
---@field relative string|nil
---@field date string|nil
---@field create boolean|nil

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

-- `Template.clone_template` performs substitutions for obsidian.nvim, so the
-- type header has to be stripped before the plugin receives the template.
---@param entry vault.NoteType
---@return string
local function materialize(entry)
  local path = vim.fn.tempname() .. ".md"
  vim.fn.writefile(entry.body, path)
  return path
end

---@param name string
---@return string
function M.slugify(name)
  local slug = vim.trim(name):lower():gsub("[^%w]+", "-")
  slug = slug:gsub("^%-+", ""):gsub("%-+$", "")
  return slug
end

---@param entry vault.NoteType
---@param id string
---@return string
function M.path(entry, id)
  return vim.fs.normalize(vault.dir() .. "/" .. entry.dir .. "/" .. id .. ".md")
end

---@param path string
---@return string
function M.title(path)
  if vim.fn.filereadable(path) == 1 then
    for _, line in ipairs(vim.fn.readfile(path)) do
      local heading = line:match("^#%s+(.+)%s*$")
      if heading then
        return vim.trim(heading)
      end
    end
  end
  return vim.fn.fnamemodify(path, ":t:r")
end

---@param path string
---@return nil
function M.open(path)
  vim.cmd({ cmd = "edit", args = { path } })
end

---@param entry vault.NoteType
---@param opts { id: string, title: string, open: boolean }
---@return string|nil
function M.create(entry, opts)
  if not vault.require_notes() then
    return nil
  end

  local directory = vim.fs.normalize(vault.dir() .. "/" .. entry.dir)
  if vim.fn.mkdir(directory, "p") == 0 and vim.fn.isdirectory(directory) == 0 then
    vim.notify(("could not create note directory: %s"):format(directory), vim.log.levels.ERROR)
    return nil
  end

  -- Typed loosely because obsidian.nvim is a runtime dependency of this
  -- module, not a compile-time dependency of the Lua checker.
  ---@type any
  local note = require("obsidian.note").create({
    id = opts.id,
    title = opts.title,
    verbatim = true,
    dir = directory,
    template = materialize(entry),
  })
  if not note:exists() then
    note:write()
  end
  if opts.open then
    note:open({ sync = true })
  end
  return M.path(entry, opts.id)
end

---@param type_name string
---@return nil
function M.create_prompt(type_name)
  local entry = M.types()[type_name]
  if not entry then
    vim.notify(
      ("no `%s` template under %s — re-run install.sh"):format(type_name, vault.templates_dir()),
      vim.log.levels.ERROR
    )
    return
  end

  ---@param input string|nil
  vim.ui.input({ prompt = ("New %s"):format(type_name) }, function(input)
    local title = input and vim.trim(input) or ""
    if title == "" then
      return
    end
    local id = M.slugify(title)
    if id == "" then
      vim.notify(("no file name can be made from %q"):format(title), vim.log.levels.ERROR)
      return
    end
    local path = M.path(entry, id)
    if vim.fn.filereadable(path) == 1 then
      vim.notify(("%s already exists"):format(path), vim.log.levels.INFO)
      M.open(path)
      return
    end
    M.create(entry, { id = id, title = title, open = true })
  end)
end

---@param root string
---@return string[]
local function markdown_files(root)
  ---@type string[]
  local files = {}
  if vim.fn.isdirectory(root) == 0 then
    return files
  end

  ---@param directory string
  local function walk(directory)
    for name, kind in vim.fs.dir(directory) do
      if not name:match("^%.") then
        local path = directory .. "/" .. name
        if kind == "directory" then
          walk(path)
        elseif kind == "file" and name:match("%.md$") then
          files[#files + 1] = vim.fs.normalize(path)
        end
      end
    end
  end

  walk(root)
  table.sort(files)
  return files
end

---@param root string
---@param path string
---@return string
local function relative(root, path)
  return vim.fs.relpath(root, path) or path
end

---@param path string
---@return string|nil
local function note_date(path)
  return path:match("^daily/(%d%d%d%d%-%d%d%-%d%d)%.md$")
end

---@param path string
---@param root string
---@return vault.NoteItem
local function item(path, root)
  local rel = relative(root, path)
  local title = M.title(path)
  return {
    text = table.concat({ title, rel }, " "),
    title = title,
    file = path,
    relative = rel,
    date = note_date(rel),
    create = false,
  }
end

---@param picker_item vault.NoteItem
---@return snacks.picker.Highlight[]
local function format(picker_item)
  if picker_item.create then
    return { { picker_item.title, "Special" } }
  end
  return {
    { picker_item.title, "Normal" },
    { "  " .. (picker_item.relative or ""), "Comment" },
  }
end

---@param a vault.NoteItem
---@param b vault.NoteItem
---@return boolean
local function note_order(a, b)
  local today = os.date("%Y-%m-%d")
  if a.date == today and b.date ~= today then
    return true
  end
  if b.date == today and a.date ~= today then
    return false
  end
  if a.date ~= b.date then
    if not a.date then
      return false
    end
    if not b.date then
      return true
    end
    return a.date > b.date
  end
  local a_text = (a.title .. " " .. (a.relative or "")):lower()
  local b_text = (b.title .. " " .. (b.relative or "")):lower()
  if a_text ~= b_text then
    return a_text < b_text
  end
  return (a.relative or "") < (b.relative or "")
end

---@param callback fun(item: vault.NoteItem)
---@param opts { title: string, files: string[], create: string|nil }
---@return nil
local function pick_items(callback, opts)
  local root = vault.dir()
  ---@type vault.NoteItem[]
  local items = {}
  for _, path in ipairs(opts.files) do
    items[#items + 1] = item(path, root)
  end
  table.sort(items, note_order)
  if opts.create then
    items[#items + 1] = {
      text = opts.create,
      title = opts.create,
      file = nil,
      relative = nil,
      date = nil,
      create = true,
    }
  end

  if #items == 0 then
    vim.notify("no matching vault notes")
    return
  end

  Snacks.picker.pick({
    title = opts.title,
    items = items,
    format = format,
    ---@param ctx snacks.picker.preview.ctx
    preview = function(ctx)
      if ctx.item.file then
        Snacks.picker.preview.file(ctx)
      else
        Snacks.picker.preview.none(ctx)
      end
    end,
    ---@param picker snacks.Picker
    ---@param selected vault.NoteItem
    confirm = function(picker, selected)
      picker:close()
      if selected then
        vim.schedule(function()
          callback(selected)
        end)
      end
    end,
  })
end

---@param type_name string
---@param callback fun(item: vault.NoteItem)
---@return nil
function M.pick(type_name, callback)
  local dir = vault.require_dir()
  if not dir then
    return
  end
  local entry = M.types()[type_name]
  if not entry then
    vim.notify(
      ("no `%s` template under %s — re-run install.sh"):format(type_name, vault.templates_dir()),
      vim.log.levels.ERROR
    )
    return
  end
  pick_items(callback, {
    title = type_name:sub(1, 1):upper() .. type_name:sub(2),
    files = markdown_files(vim.fs.normalize(dir .. "/" .. entry.dir)),
    create = "Create " .. type_name,
  })
end

---@param callback fun(item: vault.NoteItem)
---@return nil
function M.pick_all(callback)
  local dir = vault.require_dir()
  if not dir then
    return
  end
  pick_items(callback, {
    title = "Link vault note",
    files = markdown_files(dir),
    create = nil,
  })
end

---@param type_name string
---@param selected vault.NoteItem
---@return nil
function M.open_or_create(type_name, selected)
  if selected.create then
    M.create_prompt(type_name)
  elseif selected.file then
    M.open(selected.file)
  end
end

---@return { path: string, relative: string, title: string }|nil
function M.current()
  local dir = vault.require_dir()
  if not dir then
    return nil
  end
  local path = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
  if path == "" or not path:match("%.md$") or vim.fn.filereadable(path) == 0 then
    vim.notify("the current buffer is not a saved Markdown note", vim.log.levels.ERROR)
    return nil
  end
  if path ~= dir and not vim.startswith(path, dir .. "/") then
    vim.notify("the current note is outside the vault", vim.log.levels.ERROR)
    return nil
  end
  return { path = path, relative = relative(dir, path), title = M.title(path) }
end

---@param path string
---@return boolean
function M.editable(path)
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  if vim.bo[buf].modified then
    vim.notify(("save the note before adding a link: %s"):format(path), vim.log.levels.ERROR)
    return false
  end
  return true
end

---@param path string
---@param line string
---@param heading string
---@return boolean|nil
function M.append_unique(path, line, heading)
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  if not M.editable(path) then
    return nil
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for _, existing in ipairs(lines) do
    if existing == line then
      return false
    end
  end

  ---@type integer|nil
  local section
  for row, existing in ipairs(lines) do
    if existing == heading then
      section = row
      break
    end
  end

  if not section then
    ---@type string[]
    local block = {}
    if #lines > 0 and vim.trim(lines[#lines]) ~= "" then
      block[#block + 1] = ""
    end
    block[#block + 1] = heading
    block[#block + 1] = ""
    block[#block + 1] = line
    block[#block + 1] = ""
    vim.api.nvim_buf_set_lines(buf, #lines, #lines, false, block)
  else
    local finish = #lines + 1
    for row = section + 1, #lines do
      if lines[row]:match("^#{1,2}%s+") then
        finish = row
        break
      end
    end
    while finish > section + 1 and vim.trim(lines[finish - 1]) == "" do
      finish = finish - 1
    end
    ---@type string[]
    local block = {}
    if finish == section + 1 or lines[finish - 1] == heading then
      block[#block + 1] = ""
    end
    block[#block + 1] = line
    if finish <= #lines then
      block[#block + 1] = ""
    end
    vim.api.nvim_buf_set_lines(buf, finish - 1, finish - 1, false, block)
  end

  vim.api.nvim_buf_call(buf, function()
    vim.cmd.update()
  end)
  return true
end

---@return nil
function M.people()
  if not vault.require_notes() then
    return
  end
  ---@param selected vault.NoteItem
  M.pick("person", function(selected)
    M.open_or_create("person", selected)
  end)
end

---@return nil
function M.find()
  local dir = vault.require_dir()
  if not dir then
    return
  end
  Snacks.picker.files({ cwd = dir, ft = "md", hidden = true, ignored = true, title = "Vault notes" })
end

---@return nil
function M.grep()
  local dir = vault.require_dir()
  if not dir then
    return
  end
  Snacks.picker.grep({ cwd = dir, hidden = true, ignored = true, title = "Grep notes" })
end

return M
