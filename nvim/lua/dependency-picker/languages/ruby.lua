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
      -- Pattern: gemname-X.Y.Z or gemname-X.Y.Z.something
      local gem_name = name:match("^(.-)%-[%d%.]+")
      if gem_name and not seen[gem_name] then
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

return M
