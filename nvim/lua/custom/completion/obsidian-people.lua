-- obsidian-people.lua  ── Custom blink.cmp source for @ people mentions
-- Provides completion for people notes in the people/ folder
-- Works with or without obsidian.nvim plugin enabled

local M = {}

-- Fallback vault configuration (used if obsidian.nvim is not available)
local FALLBACK_VAULT_PATH = vim.fn.expand("~/generic/notes")
local PEOPLE_FOLDER = "people"

-- Create a new instance of the source
-- This is called by blink.cmp when the source is first used
function M.new()
  return setmetatable({}, { __index = M })
end

-- Get trigger characters for this source
-- @ symbol triggers people completion in markdown files
function M:get_trigger_characters()
  return { "@" }
end

-- Check if the source should be enabled
-- Only enable in markdown files
function M:is_available()
  local ft = vim.bo.filetype
  return ft == "markdown"
end

-- Get the vault directory path
-- Try obsidian.nvim first, fall back to hardcoded path
local function get_vault_dir()
  -- Try to get vault from obsidian.nvim if available
  local ok, obsidian = pcall(require, "obsidian")
  if ok then
    local client = obsidian.get_client()
    if client and client.dir then
      return client.dir
    end
  end

  -- Fall back to hardcoded vault path
  return require("plenary.path"):new(FALLBACK_VAULT_PATH)
end

-- Get completions for @ mentions
-- This scans the people/ folder and returns matching people
function M:get_completions(context, callback)
  -- Only trigger after @ symbol
  local line = context.line
  local col = context.cursor[2]

  -- Find the @ symbol before cursor
  local before_cursor = line:sub(1, col)
  local trigger_pos = before_cursor:reverse():find("@")

  if not trigger_pos then
    callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
    return
  end

  -- Get the text after @ for filtering
  local after_at = before_cursor:match("@([%w-]*)$") or ""

  -- Get vault directory (try obsidian.nvim first, fall back to hardcoded path)
  local vault_dir = get_vault_dir()
  if not vault_dir then
    callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
    return
  end

  -- Check if people/ folder exists
  local people_dir = vault_dir / PEOPLE_FOLDER
  if not people_dir:is_dir() then
    callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
    return
  end

  -- Scan people/ folder for markdown files
  local items = {}

  -- Get absolute path string for glob
  local people_path_str = tostring(people_dir)
  local files = vim.fn.glob(people_path_str .. "/*.md", false, true)

  for _, file in ipairs(files) do
    local filename = vim.fn.fnamemodify(file, ":t:r") -- Get filename without path and extension
    if filename then
      -- Convert first-last to First Last for display
      local display_name = filename:gsub("-", " "):gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest:lower()
      end)

      -- Filter based on text after @
      local matches = after_at == ""
        or filename:lower():find(after_at:lower(), 1, true)
        or display_name:lower():find(after_at:lower(), 1, true)

      if matches then
        table.insert(items, {
          label = display_name,
          kind = require("blink.cmp.types").CompletionItemKind.Text,
          insertText = "[[" .. filename .. "]]",
          -- Replace from @ to cursor
          textEdit = {
            newText = "[[" .. filename .. "]]",
            range = {
              start = { line = context.cursor[1] - 1, character = col - #after_at - 1 },
              ["end"] = { line = context.cursor[1] - 1, character = col },
            },
          },
          documentation = "Person note: " .. filename .. ".md",
          sortText = filename,
        })
      end
    end
  end

  -- Sort alphabetically
  table.sort(items, function(a, b)
    return a.sortText < b.sortText
  end)

  callback({
    is_incomplete_forward = false,
    is_incomplete_backward = false,
    items = items,
  })
end

-- Resolve additional details for a completion item (optional)
-- We don't need this for people completion
function M:resolve(item, callback)
  callback(item)
end

return M
