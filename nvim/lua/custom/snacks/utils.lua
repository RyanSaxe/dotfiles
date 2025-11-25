-- utils.lua  ── shared utility functions for Snacks configuration
-- Contains reusable helper functions used across multiple snacks modules

local M = {}

---@param max integer|nil
---@return string[]
function M.recent_files_in_cwd(max)
  max = max or 10
  local cwd = vim.loop.cwd()
  local list = {}
  for _, abs in ipairs(vim.v.oldfiles) do
    if vim.startswith(abs, cwd) and vim.fn.filereadable(abs) == 1 then
      table.insert(list, vim.fn.fnamemodify(abs, ":.")) -- relative path
      if #list == max then
        break
      end
    end
  end
  return list
end

-- Get time since most recent file was accessed
---@return string Time description like "2h ago", "5m ago", etc.
function M.get_recent_file_time()
  local cwd = vim.loop.cwd()
  local most_recent_time = 0

  for _, abs in ipairs(vim.v.oldfiles) do
    if vim.startswith(abs, cwd) and vim.fn.filereadable(abs) == 1 then
      local stat = vim.loop.fs_stat(abs)
      if stat and stat.mtime.sec > most_recent_time then
        most_recent_time = stat.mtime.sec
      end
      break -- We only need the first (most recent) file
    end
  end

  if most_recent_time == 0 then
    return "none"
  end

  local now = os.time()
  local diff = now - most_recent_time

  if diff < 60 then
    return math.floor(diff) .. "s ago"
  elseif diff < 3600 then
    return math.floor(diff / 60) .. "m ago"
  elseif diff < 86400 then
    return math.floor(diff / 3600) .. "h ago"
  else
    return math.floor(diff / 86400) .. "d ago"
  end
end

-- Normalize and format file paths for prettier display
---@param path string Path to normalize
---@param max_length? number Maximum display length (default: 40)
---@return string Normalized and formatted path
function M.normalize_path(path, max_length)
  max_length = max_length or 40
  local normalized = vim.fs.normalize(path)

  if #normalized <= max_length then
    return normalized
  end

  -- Keep filename and truncate from the middle
  local parts = vim.split(normalized, "/")
  local filename = parts[#parts]

  if #filename >= max_length - 3 then
    return "..." .. filename:sub(-(max_length - 3))
  end

  -- Build path keeping filename and as much directory structure as possible
  local result = filename
  for i = #parts - 1, 1, -1 do
    local candidate = parts[i] .. "/" .. result
    if #candidate > max_length - 3 then
      return "..." .. result
    end
    result = candidate
  end

  return result
end

-- Create a separator line of dashes using the configured pane width
---@return string Separator line of dashes
function M.create_separator()
  -- Always use Snacks.config.dashboard.width (set by create_sections)
  local pane_width = Snacks.config.dashboard.width
  return string.rep("-", pane_width)
end

-- Create title with right-aligned content by padding with spaces
---@param left string The left side content
---@param right string The right side content to align
---@return string Title with right-aligned content and proper spacing
function M.create_aligned_title(left, right)
  -- Always use Snacks.config.dashboard.width (set by create_sections)
  local pane_width = Snacks.config.dashboard.width
  local left_len = vim.fn.strdisplaywidth(left)
  local right_len = vim.fn.strdisplaywidth(right)
  local total_content = left_len + right_len

  if total_content >= pane_width then
    -- If content is too long, just return left as-is
    return left
  end

  local spaces_needed = pane_width - total_content - 2 -- Account for parentheses
  return left .. string.rep(" ", spaces_needed) .. "(" .. right .. ")"
end

-- Calculate dynamic pane width based on terminal/window size
-- Returns optimal pane width that prioritizes readability (wider panes, fewer columns)
-- Edge margins can match vertical centering for perfectly balanced appearance
---@param window_width? number Optional window width (defaults to vim.o.columns)
---@param edge_margin? number Optional edge margin (defaults to 4)
---@return number pane_width Calculated width between 45-75 characters
function M.calculate_dynamic_pane_width(window_width, edge_margin)
  local width = window_width or vim.o.columns
  edge_margin = edge_margin or 4 -- Default margin if not specified
  -- Use edge margin as gap between panes for visual consistency
  local gap = edge_margin -- Gap between panes now matches edge margin
  local min_width = 45
  local max_width = 75

  -- Account for edge margins in all calculations
  local available_width = width - (edge_margin * 2) -- Subtract left and right margins

  -- Check if we can fit 2 panes at minimum width
  -- Formula: (available_width - gap) / 2 >= min_width
  -- Rearranged: available_width >= min_width * 2 + gap
  local min_for_2_panes = min_width * 2 + gap

  if available_width >= min_for_2_panes then
    -- Calculate width for 2 panes, prioritizing readability
    -- Subtract gap between panes, then divide by 2
    local pane_width = math.floor((available_width - gap) / 2)
    return math.max(min_width, math.min(pane_width, max_width))
  else
    -- Use 1 pane with available width (already accounts for edge margins)
    return math.max(min_width, math.min(available_width, max_width))
  end
end

-- Check if snacks dashboard allows a second pane based on terminal width
-- Uses Snacks.config.dashboard.width (set by create_sections), with fallback to dynamic calculation
function M.show_if_has_second_pane()
  -- taken from snacks.dashboard. Only enable this visual if snacks allows a second pane.
  local width = vim.o.columns
  -- Use config width if set (by create_sections), otherwise calculate dynamically
  local pane_width = Snacks.config.dashboard.width or M.calculate_dynamic_pane_width()
  -- Use actual pane_gap from config (set by dashboard based on feature flag), fallback to 4
  local pane_gap = Snacks.config.dashboard.pane_gap or 4
  local max_panes = math.max(1, math.floor((width + pane_gap) / (pane_width + pane_gap)))
  return max_panes > 1
end

-- Create a pane structure for dashboard sections
-- Returns both the sections array and the total height they occupy
---@param header table Header section config
---@param specs table Array of spec entries
---@param bottom_padding number Padding to add after last entry
---@return table sections Array of section configs
---@return number height Total height of sections (1 for header + N for specs + bottom_padding)
function M.create_pane(header, specs, bottom_padding)
  local pane = header.pane
  header.padding = header.padding or 2
  header.indent = header.indent or 0

  local output = { header }
  for i, spec in ipairs(specs) do
    -- set padding on the spec itself
    spec.padding = (i == #specs) and bottom_padding or 0

    -- start with defaults
    local row = {
      pane = pane,
      indent = 0,
    }
    -- copy all spec fields in
    for k, v in pairs(spec) do
      row[k] = v
    end

    table.insert(output, row)
  end

  -- Calculate height: 1 (header with its padding) + N (specs) + bottom_padding (on last spec)
  -- Header padding is accounted for separately
  local height = 1 + header.padding + #specs + bottom_padding

  return output, height
end

-- Conditionally select between git and non-git spec configurations
function M.different_key_if_condition(condition, base_spec, git_spec, non_git_spec)
  if condition then
    return vim.tbl_deep_extend("force", {}, base_spec, git_spec)
  else
    return vim.tbl_deep_extend("force", {}, base_spec, non_git_spec)
  end
end

-- Evaluate if a section is enabled (handles both function and boolean)
-- Moved from dashboard.lua to allow reuse across all section creators
---@param section table Section configuration
---@return boolean enabled Whether the section is enabled
function M.is_section_enabled(section)
  if section.enabled == nil then
    return true -- Default to enabled if not specified
  end
  if type(section.enabled) == "function" then
    return section.enabled() -- Call the function to get boolean result
  end
  return section.enabled -- Use the boolean value directly
end

-- Calculate total height of a section group
-- Dynamically calculates height by iterating through sections and respecting enabled state
---@param sections table Array of section configurations
---@return number height Total height of enabled sections
function M.calculate_section_group_height(sections)
  local height = 0
  for _, section in ipairs(sections) do
    if M.is_section_enabled(section) then
      -- Add main content height
      if section.section == "terminal" then
        height = height + (section.height or 1)
      elseif section.title or section.desc or section.key then
        height = height + 1
      end

      -- Add padding
      if section.padding then
        height = height + section.padding
      end
    end
  end
  return height
end

-- Extract height of git sections from a sections array
-- Identifies git sections by checking for specific git-related keys
---@param sections table Array of all sections
---@return number height Total height of git sections
function M.calculate_git_sections_height(sections)
  local height = 0
  local in_git_section = false

  for _, section in ipairs(sections) do
    -- Identify start of git section (usually has "Git" in title or specific git keys)
    if section.title and section.title:match("Git") then
      in_git_section = true
    end

    -- Check for git-specific keys (b/B for branches, s for status, etc)
    if
      section.key
      and (
        section.key == "b"
        or section.key == "B"
        or section.key == "s"
        or section.key == "l"
        or section.key == "d"
        or section.key == "c"
        or section.key == "p"
        or section.key == "P"
        or section.key == "z"
      )
    then
      in_git_section = true
    end

    -- Count height if in git section
    if in_git_section and M.is_section_enabled(section) then
      if section.section == "terminal" then
        height = height + (section.height or 1)
      elseif section.title or section.desc or section.key then
        height = height + 1
      end
      if section.padding then
        height = height + section.padding
      end
    end

    -- End of git section detection (when we hit a separator or different section)
    if in_git_section and section.desc and section.desc:match("^%-+$") then
      -- This is the git section separator, count it and stop
      if M.is_section_enabled(section) then
        height = height + 1
        if section.padding then
          height = height + section.padding
        end
      end
      break
    end
  end

  return height
end

-- Extract height of recent files sections from a sections array
-- Identifies recent files by checking for specific patterns in descriptions
---@param sections table Array of all sections
---@return number height Total height of recent files sections
function M.calculate_recent_files_height(sections)
  local height = 0
  local in_recent_section = false

  for _, section in ipairs(sections) do
    -- Identify recent files section by title
    if section.title and section.title:match("[Rr]ecent") then
      in_recent_section = true
    end

    -- Check for file-like descriptions (paths with extensions)
    if section.desc and section.desc:match("%.%w+$") then
      -- This looks like a file path
      in_recent_section = true
    end

    -- Count height if in recent section
    if in_recent_section and M.is_section_enabled(section) then
      if section.section == "terminal" then
        height = height + (section.height or 1)
      elseif section.title or section.desc or section.key then
        height = height + 1
      end
      if section.padding then
        height = height + section.padding
      end
    end

    -- End of recent section detection (separator after recent files)
    if in_recent_section and section.desc and section.desc:match("^%-+$") then
      -- This is the recent files separator, count it and stop
      if M.is_section_enabled(section) then
        height = height + 1
        if section.padding then
          height = height + section.padding
        end
      end
      break
    end
  end

  return height
end

-- Find git root directory, fallback to current working directory
---@return string The git root or current working directory
local function find_git_root()
  -- Try to find .git directory walking up from cwd
  local cwd = vim.loop.cwd()
  local git_root = vim.fn.finddir(".git", cwd .. ";")

  if git_root ~= "" then
    -- Return the parent directory of .git
    return vim.fn.fnamemodify(git_root, ":h")
  end

  -- Fallback to current working directory
  return cwd
end

-- Detect available filetypes by scanning files in the git repository
-- Uses rg to find all files, extracts extensions, maps to Neovim filetypes,
-- and returns them sorted by prevalence (most common first)
---@return table[] Array of filetype objects { text = "filetype" }, sorted by prevalence
function M.detect_available_filetypes()
  local search_root = find_git_root()

  -- Use rg to get all files, extract extensions, count them, and sort by count
  -- Command breakdown:
  --   rg --files: List all files (respects .gitignore)
  --   grep -o '\.[^.]*$': Extract file extensions (everything after last dot)
  --   sort: Sort extensions alphabetically
  --   uniq -c: Count unique extensions
  --   sort -rn: Sort by count (reverse numeric, most common first)
  local cmd = string.format(
    "cd %s && rg --files 2>/dev/null | grep -o '\\.[^.]*$' | sort | uniq -c | sort -rn",
    vim.fn.shellescape(search_root)
  )

  local output = vim.fn.system(cmd)

  -- Handle errors (no files found, rg not available, etc.)
  if vim.v.shell_error ~= 0 or output == "" then
    -- Fallback to a minimal set of common filetypes
    return {
      { text = "markdown" },
      { text = "lua" },
      { text = "python" },
    }
  end

  -- Parse output and build filetype list
  local filetypes = {}
  local seen = {} -- Track seen filetypes to avoid duplicates

  for line in output:gmatch("[^\r\n]+") do
    -- Extract extension from lines like "  123 .lua"
    local ext = line:match("%s+%d+%s+%.(%S+)")

    if ext and ext ~= "" then
      -- Map extension to Neovim filetype using vim.filetype.match
      -- This uses Neovim's built-in filetype detection, so it handles all known extensions
      local dummy_filename = "dummy." .. ext
      local filetype = vim.filetype.match({ filename = dummy_filename })

      -- Only add if we got a valid filetype and haven't seen it before
      if filetype and filetype ~= "" and not seen[filetype] then
        seen[filetype] = true
        table.insert(filetypes, { text = filetype })
      end
    end
  end

  -- If we didn't find any valid filetypes, return fallback
  if #filetypes == 0 then
    return {
      { text = "markdown" },
      { text = "lua" },
      { text = "python" },
    }
  end

  return filetypes
end

return M
