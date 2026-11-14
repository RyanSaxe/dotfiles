-- Notes in the vault through obsidian.nvim. Its defaults also give Enter to
-- follow a link or tick a task, gd and gr on links, [[ completion and a
-- backlink count under each note.
--
-- The vault's notes are in notes/. private/ is an optional second git
-- repository inside the vault, with notes of the same kinds in
-- private/notes/. obsidian.nvim finds links, completions and backlinks in
-- it because the vault's .ignore contains !*, so ripgrep also searches the
-- folders .gitignore lists.
--
--   strict        pins the vault root, which otherwise moves to any folder
--                 above it that has a .obsidian/ directory.
--   frontmatter   off, or every save writes id, aliases and tags into the note.
--   ui            off, because render-markdown.nvim draws the Markdown.
--   templates     are named by full path. templates.folder stays unset,
--                 because the plugin creates that folder inside the vault.
--   daily.md      heads a daily note with {{id}}, its date, because {{date}}
--                 is the day the note was made.
--   notes_subdir  is notes/, where obsidian.nvim puts a note it makes with
--                 no folder named, such as one from :Obsidian link_new.
local vault = vim.fs.normalize(vim.env.VAULT_DIR or "~/generic/vault")
local templates = (vim.env.XDG_CONFIG_HOME or vim.fn.expand("~/.config")) .. "/vault/templates"

---@param command string
---@return string
local function obsidian(command)
  return "<cmd>Obsidian " .. command .. "<cr>"
end

---@param folder string relative to the vault
---@return boolean
local function in_vault(folder)
  return vim.fn.isdirectory(vault .. "/" .. folder) == 1
end

---Finds the note with this file name anywhere in the vault, private/
---included. A link names a note by its file name alone, so a new note must
---not take a name that is in use.
---@param name string such as jane-doe.md
---@return string? path
local function find_note(name)
  local function not_hidden(dir)
    return not vim.startswith(vim.fs.basename(dir), ".")
  end
  for path, type in vim.fs.dir(vault, { depth = math.huge, skip = not_hidden }) do
    if type == "file" and vim.fs.basename(path) == name then
      return vault .. "/" .. path
    end
  end
end

---@class vault.Kind
---@field text string
---@field folder string relative to the vault, or to private/ for a private note
---@field prompt? string what vim.ui.input asks for. Today asks nothing.

---@param kind vault.Kind
---@param root string "" for the vault or "private/"
---@param title string
local function open_new_note(kind, root, title)
  local slug = require("obsidian.builtin").title_to_slug(title)
  local folder = root .. kind.folder
  -- Project Dotfiles is notes/projects/dotfiles/dotfiles.md.
  if kind.text == "Project" then
    folder = folder .. "/" .. slug
  end
  local existing = find_note(slug .. ".md")
  if existing then
    vim.cmd.edit(vim.fn.fnameescape(existing))
  else
    vim.cmd.Obsidian({ args = { "new", folder .. "/" .. title } })
  end
end

---Picks a kind of note, asks for its title and opens the note, after making
---it from note.md when no note in the vault has its file name. When the
---vault has private/, Tab switches the new note between the vault and
---private/.
local function new_note()
  ---@type vault.Kind[]
  local kinds = {
    { text = "Today", folder = "notes/daily" },
    { text = "Person", folder = "notes/people", prompt = "Name" },
    { text = "Project", folder = "notes/projects", prompt = "Project" },
    { text = "Note", folder = "notes", prompt = "Title" },
  }
  local has_private = in_vault("private")
  local private = false
  local function root()
    return private and "private/" or ""
  end
  local function title()
    if not has_private then
      return "New note"
    end
    return private and "New note · private · Tab for vault" or "New note · vault · Tab for private"
  end
  local tab = has_private and { "toggle_private", mode = { "n", "i" } } or nil

  Snacks.picker.pick({
    source = "new_note",
    title = title(),
    items = kinds,
    layout = {
      preset = "select",
      -- The list is as tall as the kinds, as in Snacks' vim.ui.select.
      config = function(layout)
        for _, box in ipairs(layout.layout) do
          if box.win == "list" then
            box.height = #kinds
          end
        end
      end,
    },
    ---@param kind vault.Kind
    format = function(kind)
      -- Today's note is always the vault's, so its date names one note.
      local folder = (kind.prompt and root() or "") .. kind.folder .. "/"
      return {
        { kind.text },
        { col = 0, virt_text = { { folder, "SnacksPickerDir" } }, virt_text_pos = "right_align" },
      }
    end,
    actions = {
      toggle_private = function(picker)
        private = not private
        picker.title = title()
        picker:update_titles()
        picker.list:update({ force = true })
      end,
    },
    win = {
      input = { keys = { ["<Tab>"] = tab } },
      list = { keys = { ["<Tab>"] = tab } },
    },
    ---@param kind vault.Kind?
    confirm = function(picker, kind)
      picker:close()
      if not kind then
        return
      end
      local target = root()
      vim.schedule(function()
        if not kind.prompt then
          return vim.cmd.Obsidian("today")
        end
        vim.ui.input({ prompt = kind.prompt .. (target ~= "" and " in private/" or "") .. ": " }, function(input)
          if input and vim.trim(input) ~= "" then
            open_new_note(kind, target, vim.trim(input))
          end
        end)
      end)
    end,
  })
end

---The project ws files a task under: the name of the origin remote of the
---current buffer's git repository, or of the working directory's, and the
---repository's folder name when it has no origin.
---@return string?
local function project_name()
  local file = vim.api.nvim_buf_get_name(0)
  local dir = (vim.bo.buftype == "" and file ~= "") and vim.fs.dirname(file) or vim.fn.getcwd()
  local function git(...)
    local result = vim.system({ "git", "-C", dir, ... }, { text = true }):wait()
    return result.code == 0 and vim.trim(result.stdout) or nil
  end
  local url = git("remote", "get-url", "origin")
  if url then
    url = url:gsub("/+$", ""):gsub("%.git$", "")
    return url:match("([^/:]+)$")
  end
  local top = git("rev-parse", "--show-toplevel")
  return top and vim.fs.basename(top)
end

---Opens the project's TODO.md, the note ws adds its tasks to, and first
---writes the heading ws starts that note with when it does not exist.
local function project_tasks()
  local name = project_name()
  if not name then
    return vim.notify("Not in a git repository, so no project to open tasks for", vim.log.levels.WARN)
  end
  local file = ("%s/notes/projects/%s/TODO.md"):format(vault, name)
  if vim.fn.filereadable(file) == 0 then
    vim.fn.mkdir(vim.fs.dirname(file), "p")
    vim.fn.writefile({ "# " .. name }, file)
  end
  vim.cmd.edit(vim.fn.fnameescape(file))
end

local function people()
  local search = {}
  for _, folder in ipairs({ "notes/people", "private/notes/people" }) do
    if in_vault(folder) then
      vim.list_extend(search, { "--search-path", folder })
    end
  end
  if #search == 0 then
    return vim.notify("The vault has no notes/people/ yet", vim.log.levels.WARN)
  end
  -- fd prints each path relative to the vault, such as private/notes/people/jane-doe.md.
  Snacks.picker.files({ title = "People", cwd = vault, cmd = "fd", ignored = true, ft = "md", args = search })
end

return {
  "obsidian-nvim/obsidian.nvim",
  -- A computer without the vault gets no notes keys instead of an error.
  cond = vim.fn.isdirectory(vault) == 1,
  -- Loaded at startup, so :Obsidian works before any note is open.
  lazy = false,
  opts = {
    legacy_commands = false,
    workspaces = { { name = "vault", path = vault, strict = true } },
    ui = { enable = false },
    frontmatter = { enabled = false },
    -- notes/people/Jane Doe is notes/people/jane-doe.md, and naming a note that exists opens it.
    note_id_func = function(title)
      return require("obsidian.builtin").title_to_slug(title)
    end,
    notes_subdir = "notes",
    new_notes_location = "notes_subdir",
    note = { template = templates .. "/note.md" },
    daily_notes = { folder = "notes/daily", template = templates .. "/daily.md", default_tags = {} },
    completion = { min_chars = 1, create_new = false },
    checkbox = { order = { " ", "x" } },
    attachments = { folder = "notes/assets" },
    footer = { format = "{{backlinks}} backlinks" },
  },
  keys = {
    { "<leader>o", group = "Notes" },
    { "<leader>od", obsidian("today"), desc = "Today's note" },
    { "<leader>oy", obsidian("yesterday"), desc = "Yesterday's note" },
    { "<leader>oD", obsidian("tomorrow"), desc = "Tomorrow's note" },
    { "<leader>on", new_note, desc = "New note" },
    { "<leader>ot", project_tasks, desc = "Project's tasks" },
    {
      "<leader>of",
      function()
        Snacks.picker.files({ cwd = vault, ignored = true })
      end,
      desc = "Find note",
    },
    {
      "<leader>og",
      function()
        Snacks.picker.grep({ cwd = vault, ignored = true })
      end,
      desc = "Grep notes",
    },
    { "<leader>op", people, desc = "People" },
    { "<leader>ob", obsidian("backlinks"), desc = "Backlinks" },
    { "<leader>ox", obsidian("toggle_checkbox"), desc = "Tick or untick a task" },
  },
}
