-- Ruby/Gems detector
-- Detects gems from GEM_HOME or bundler paths
-- Deduplicates gem names across versions (e.g., rails-7.0.0, rails-7.0.1 -> rails)

local util = require("dependency-picker.util")

local M = {}

-- Language metadata
M.name = "Ruby"
M.filetypes = { "ruby" }
M.requires_buffer_path = true
-- File extension for single-file stdlib modules (e.g., base64.rb, csv.rb)
-- Used to resolve both gem directories and single-file stdlib modules
M.file_extension = ".rb"

-- Get GEM_HOME from environment or try to detect from ruby
---@return string|nil GEM_HOME path
local function get_gem_home()
  -- Try environment variable first
  local gem_home = vim.env.GEM_HOME
  if gem_home and gem_home ~= "" then
    return gem_home
  end

  -- Fallback: ask ruby for gem home
  return util.exec_command("ruby -e 'puts Gem.user_dir'")
end

-- Scan a gems directory and extract unique gem names (strip versions)
-- Filters out directories without version suffixes (likely metadata)
---@param gems_dir string Path to gems directory
---@return string[] List of unique gem names
local function scan_gems(gems_dir)
  -- Use the generic scan_and_deduplicate with a filter for versioned gems only
  return util.scan_and_deduplicate(gems_dir, nil, function(name)
    -- Only include directories that have a version suffix
    -- This filters out non-gem directories in the gems folder
    local base = util.strip_version_suffix(name)
    return base and base ~= name
  end)
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

  if not util.is_directory(gems_dir) then
    return nil
  end

  -- Check cache first
  local cache_key = util.make_cache_key("ruby", gems_dir)
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
-- ============================================================================

-- Note: Ruby version stripping is handled by util.strip_version_suffix
-- which supports Ruby format: gemname-X.Y.Z including prereleases

-- Resolve a gem name to its actual versioned directory
-- Uses the generic resolver with Ruby-specific version separator (-)
---@param root string Gems directory path
---@param gem_name string Gem name without version (e.g., "rack")
---@return string|nil Versioned directory name (e.g., "rack-2.2.21"), or nil if not found
function M.resolve_directory(root, gem_name)
  -- Use the generic versioned package resolver with Ruby's - separator
  -- Also check for .rb files (single-file stdlib modules)
  return util.resolve_versioned_package(root, gem_name, "%-", M.file_extension)
end

-- Detect Ruby standard library modules
-- Queries Ruby for stdlib location and scans for available modules
---@return table|nil { root = string, packages = string[] }
function M.detect_stdlib()
  -- Get Ruby stdlib directory
  local stdlib_dir = util.exec_command("ruby -e \"puts RbConfig::CONFIG['rubylibdir']\"")
  if not stdlib_dir then
    return nil
  end

  if not util.is_directory(stdlib_dir) then
    return nil
  end

  -- Check cache
  local cache_key = util.make_cache_key("ruby_stdlib", stdlib_dir)
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
