-- Meeting heading helper for daily notes.

local M = {}

local PERSON_DIR = "people"
local PERSON_TEMPLATE = "person"

local TITLE_ONLY = "__title_only"
local NEW_PERSON = "__new_person"

local function trim(value)
  return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function slugify(value)
  return trim(value):gsub("%s+", "-"):gsub("[^A-Za-z0-9-]", ""):lower()
end

local function display_name(value)
  local name = trim(value):gsub("-", " ")
  return (name:gsub("(%a)([%w']*)", function(first, rest)
    return first:upper() .. rest:lower()
  end))
end

local function parse_person(input)
  local value = trim(input)
  value = value:gsub("^%[%[", ""):gsub("%]%]$", "")

  local link, alias = value:match("^([^|]+)|(.+)$")
  value = trim(alias or link or value)

  local slug = slugify(link or value)
  return slug, display_name(value)
end

local function vault_path()
  if not Obsidian or not Obsidian.dir then
    vim.notify("Obsidian not initialized. Open a markdown file in your vault first.", vim.log.levels.WARN)
    return nil
  end
  return tostring(Obsidian.dir)
end

local function person_file(slug)
  local root = vault_path()
  if not root then
    return nil
  end
  return table.concat({ root, PERSON_DIR, slug .. ".md" }, "/")
end

local function person_exists(slug)
  local file = person_file(slug)
  return file ~= nil and vim.uv.fs_stat(file) ~= nil
end

local function create_person_note(title)
  local root = vault_path()
  if not root then
    return
  end

  vim.fn.mkdir(root .. "/" .. PERSON_DIR, "p")

  local Note = require("obsidian.note")
  Note.create({
    title = title,
    dir = root .. "/" .. PERSON_DIR,
    template = PERSON_TEMPLATE,
    should_write = true,
  })
end

local function insert_heading(time, title)
  local heading = ("## %s: %s"):format(time, title)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_get_current_line()

  if trim(line) == "" then
    vim.api.nvim_set_current_line(heading)
  else
    vim.api.nvim_buf_set_lines(0, row, row, false, { heading })
    row = row + 1
  end

  vim.api.nvim_win_set_cursor(0, { row, #heading })
end

local function insert_person_heading(time, slug)
  insert_heading(time, ("[[%s]]"):format(slug))
end

local function maybe_create_person(time, slug, title)
  if person_exists(slug) then
    insert_person_heading(time, slug)
    return
  end

  vim.ui.select({
    "Create person note",
    "Insert link only",
    "Cancel",
  }, {
    prompt = ("No person note exists for [[%s]]. What do you want to do?"):format(slug),
  }, function(choice)
    if choice == "Create person note" then
      create_person_note(title)
      insert_person_heading(time, slug)
    elseif choice == "Insert link only" then
      insert_person_heading(time, slug)
    end
  end)
end

local function list_people()
  local root = vault_path()
  if not root then
    return {}
  end

  local people_dir = root .. "/" .. PERSON_DIR
  local files = vim.fn.globpath(people_dir, "*.md", false, true)
  table.sort(files)

  local people = {}
  for _, path in ipairs(files) do
    local filename = vim.fs.basename(path)
    local slug = filename:gsub("%.md$", "")

    table.insert(people, {
      kind = "person",
      slug = slug,
      label = ("%s  [[%s]]"):format(display_name(slug), slug),
    })
  end

  return people
end

local function prompt_title(time)
  vim.ui.input({ prompt = "Meeting title: " }, function(title)
    title = trim(title)
    if title == "" then
      vim.notify("Meeting title cannot be empty", vim.log.levels.WARN)
      return
    end

    insert_heading(time, title)
  end)
end

local function prompt_new_person(time)
  vim.ui.input({ prompt = "Person: " }, function(person)
    local slug, title = parse_person(person)
    if slug == "" then
      vim.notify("Person cannot be empty", vim.log.levels.WARN)
      return
    end

    maybe_create_person(time, slug, title)
  end)
end

local function select_meeting_target(time)
  local choices = {
    {
      kind = TITLE_ONLY,
      label = "Title only",
    },
    {
      kind = NEW_PERSON,
      label = "Create or link new person",
    },
  }

  vim.list_extend(choices, list_people())

  vim.ui.select(choices, {
    prompt = "Meeting target:",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if not choice then
      return
    end

    if choice.kind == TITLE_ONLY then
      prompt_title(time)
    elseif choice.kind == NEW_PERSON then
      prompt_new_person(time)
    elseif choice.kind == "person" then
      insert_person_heading(time, choice.slug)
    end
  end)
end

function M.insert_meeting()
  vim.ui.input({
    prompt = "Meeting time: ",
    default = os.date("%H:%M"),
  }, function(time)
    time = trim(time)
    if time == "" then
      return
    end

    select_meeting_target(time)
  end)
end

return M
