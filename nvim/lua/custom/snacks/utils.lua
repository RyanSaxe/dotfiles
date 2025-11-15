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
  local gap = 4 -- Gap between panes
  edge_margin = edge_margin or 4 -- Default margin if not specified
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
  local pane_gap = 4
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

return M

