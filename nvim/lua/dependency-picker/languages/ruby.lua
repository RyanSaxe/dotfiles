-- Ruby/Gems detector
-- Detects gems from GEM_HOME or bundler paths
-- Deduplicates gem names across versions (e.g., rails-7.0.0, rails-7.0.1 -> rails)

local util = require("dependency-picker.util")

local M = {}

-- Language metadata
M.name = "Ruby"
M.filetypes = { "ruby" }
M.requires_buffer_path = true

-- Get GEM_HOME from environment or try to detect from ruby
---@return string|nil GEM_HOME path
local function get_gem_home()
  -- Try environment variable first
  local gem_home = vim.env.GEM_HOME
  if gem_home and gem_home ~= "" then
    return gem_home
  end

  -- Fallback: ask ruby for gem home
  local handle = io.popen("ruby -e 'puts Gem.user_dir' 2>/dev/null")
  if not handle then
    return nil
  end

  local output = handle:read("*a"):gsub("%s+", "")
  handle:close()

  if output ~= "" then
    return output
  end

  return nil
end

-- Scan a gems directory and extract unique gem names (strip versions)
---@param gems_dir string Path to gems directory
---@return string[] List of unique gem names
local function scan_gems(gems_dir)
  local handle = util.safe_scandir(gems_dir)
  if not handle then
    return {}
  end

  local gems = {}
  local seen = {} -- Track unique gem names (deduplicate versions)

  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end

    if type == "directory" and not name:match("^%.") then
      -- Extract gem name by stripping version suffix
      -- Handles multi-hyphenated names like "active-record-7.0.0" -> "active-record"
      local gem_name = util.strip_version_suffix(name)
      if gem_name and gem_name ~= name and not seen[gem_name] then
        seen[gem_name] = true
        table.insert(gems, gem_name)
      end
    end
  end

  return gems
end

-- Detect Ruby gems from GEM_HOME or bundler paths
---@param buffer_path string Current buffer path
---@return table|nil { root = string, packages = string[] }
function M.detect(buffer_path)
  -- Find nearest Gemfile (optional, but helps scope detection)
  local project_root = util.find_marker_upward({ "Gemfile" }, vim.fn.fnamemodify(buffer_path, ":h"))

  -- Check for local bundler path first (project-specific gems)
  local bundler_gems
  if project_root then
    -- Try .bundle/ruby/*/gems pattern
    local bundle_pattern = project_root .. "/.bundle/ruby/*/gems"
    local raw = vim.fn.glob(bundle_pattern, false, false)
    if raw ~= "" then
      bundler_gems = raw:match("([^\n]+)")
    end
  end

  -- Fallback to GEM_HOME
  local gems_dir
  if bundler_gems then
    gems_dir = bundler_gems
  else
    local gem_home = get_gem_home()
    if gem_home then
      gems_dir = gem_home .. "/gems"
    end
  end

  if not gems_dir then
    return nil
  end

  local stat = util.safe_stat(gems_dir)
  if not stat or stat.type ~= "directory" then
    return nil
  end

  -- Check cache first
  local cache_key = "ruby:" .. gems_dir
  local cached = util.get_cache(cache_key)
  if cached then
    return { root = gems_dir, packages = cached.packages }
  end

  -- Scan gems directory
  local packages = scan_gems(gems_dir)

  if #packages > 0 then
    table.sort(packages)
    util.set_cache(cache_key, { packages = packages })
    return { root = gems_dir, packages = packages }
  end

  return nil
end

-- ============================================================================
-- OPTIONAL: Language-specific versioning functions
-- These functions provide Ruby-specific version handling for full extensibility
-- ============================================================================

-- Strip version suffix from Ruby gem directory names
-- Ruby gems use format: gemname-X.Y.Z (e.g., rack-2.2.21 -> rack)
-- Handles multi-hyphenated gems: rack-protection-3.2.0 -> rack-protection
---@param name string Gem directory name (may include version)
---@return string Gem name without version suffix
function M.strip_version(name)
  if not name then
    return nil
  end

  -- Match gems with version suffix: gemname-X.Y.Z
  -- The pattern matches the last hyphen followed by version numbers
  local stripped = name:match("^(.+)%-[%d%.]+")
  if stripped then
    return stripped
  end

  -- No version pattern found, return as-is
  return name
end

-- Resolve a gem name to its actual versioned directory
-- Scans the gems directory to find the versioned directory (e.g., rack -> rack-2.2.21)
-- Returns the latest version if multiple versions exist
---@param root string Gems directory path
---@param gem_name string Gem name without version (e.g., "rack")
---@return string|nil Versioned directory name (e.g., "rack-2.2.21"), or nil if not found
function M.resolve_directory(root, gem_name)
  local handle = util.safe_scandir(root)
  if not handle then
    return nil
  end

  local matches = {}
  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end

    if type == "directory" then
      -- Match versioned gems: gemname-X.Y.Z
      -- Pattern must end with version numbers to avoid matching metadata dirs
      -- Use vim.pesc to escape special pattern characters in gem_name
      if name:match("^" .. vim.pesc(gem_name) .. "%-[%d%.]+$") then
        table.insert(matches, name)
      end
    end
  end

  if #matches > 0 then
    table.sort(matches)
    return matches[#matches] -- Return latest version
  end

  return nil
end

-- Detect Ruby standard library modules
-- Queries Ruby for stdlib location and scans for available modules
---@return table|nil { root = string, packages = string[] }
function M.detect_stdlib()
  -- Get Ruby stdlib directory
  local handle = io.popen("ruby -e \"puts RbConfig::CONFIG['rubylibdir']\" 2>/dev/null")
  if not handle then
    return nil
  end

  local stdlib_dir = handle:read("*a"):gsub("%s+", "")
  handle:close()

  if not stdlib_dir or stdlib_dir == "" then
    return nil
  end

  local stat = util.safe_stat(stdlib_dir)
  if not stat or stat.type ~= "directory" then
    return nil
  end

  -- Check cache
  local cache_key = "ruby_stdlib:" .. stdlib_dir
  local cached = util.get_cache(cache_key)
  if cached then
    return { root = stdlib_dir, packages = cached.packages }
  end

  -- Scan stdlib directory for modules
  local packages = util.scan_directories(stdlib_dir)

  if #packages > 0 then
    table.sort(packages)
    util.set_cache(cache_key, { packages = packages })
    return { root = stdlib_dir, packages = packages }
  end

  return nil
end

return M
