-- Custom note creation with directory picker
-- This module provides a note creation workflow that prompts the user
-- to select a target directory before creating a new note
-- Templates are automatically applied based on the selected directory

local M = {}

-- Directory to template mapping
-- Add directory names here to automatically apply templates
local DIRECTORY_TEMPLATES = {
  people = "person", -- people/ directory uses person.md template
  -- Add more mappings as needed:
  -- projects = "project",
  -- meetings = "meeting",
}

-- Get all subdirectories in the vault (excluding special folders)
local function get_note_directories()
  -- Use the global Obsidian.dir (set by obsidian.nvim during setup)
  if not Obsidian or not Obsidian.dir then
    vim.notify("Obsidian not initialized. Open a markdown file in your vault first.", vim.log.levels.WARN)
    return {}
  end

  local vault_path = tostring(Obsidian.dir)

  local exclude_dirs = { "daily", "templates", "assets", ".obsidian", ".git" }

  -- Get all directories using fd (faster than find)
  local cmd = string.format(
    "fd --type d --max-depth 1 --base-directory %s",
    vim.fn.shellescape(vault_path)
  )

  local dirs = vim.fn.systemlist(cmd)

  -- Filter out excluded directories and add root option
  local result = { { name = "Root", path = vault_path } }
  for _, dir in ipairs(dirs) do
    local should_include = true
    for _, exclude in ipairs(exclude_dirs) do
      if dir:match("^" .. exclude) then
        should_include = false
        break
      end
    end
    if should_include then
      table.insert(result, {
        name = dir,
        path = vault_path .. "/" .. dir,
      })
    end
  end

  return result
end

-- Create a note in a specific directory with optional template
local function create_note_in_dir(title, dir_path, dir_name)
  -- Check if this directory has an associated template
  local template_name = DIRECTORY_TEMPLATES[dir_name]

  if template_name then
    -- Create note with template using ObsidianNewFromTemplate
    -- This ensures the template is properly applied
    vim.cmd(string.format(
      "ObsidianNewFromTemplate %s %s/%s",
      template_name,
      dir_path,
      title:gsub(" ", "-"):gsub("[^A-Za-z0-9-]", ""):lower() .. ".md"
    ))
  else
    -- Create note without template (default behavior)
    local Note = require("obsidian.note")

    local note = Note.create({
      title = title,
      dir = dir_path,
    })

    -- Open the note and write to buffer
    note:open({ sync = true })
    note:write_to_buffer()

    return note
  end
end

-- Show directory picker first, then prompt for note name
function M.prompt_and_create()
  local dirs = get_note_directories()

  if #dirs == 0 then
    return -- No directories available (Obsidian not initialized)
  end

  -- First: Show directory picker using vim.ui.select
  vim.ui.select(dirs, {
    prompt = "Select directory for new note:",
    format_item = function(item)
      return item.name
    end,
  }, function(selected_dir)
    if not selected_dir then
      return -- User cancelled
    end

    -- Second: Prompt for note title
    vim.ui.input({ prompt = "Note title: " }, function(title)
      if title and title ~= "" then
        create_note_in_dir(title, selected_dir.path, selected_dir.name:lower())
      end
    end)
  end)
end

return M
