local util = require("dependency-picker.util")

local M = {}

M.name = "Ruby"
M.filetypes = { "ruby" }
M.requires_buffer_path = true
M.file_extension = ".rb"

---@return string|nil GEM_HOME path
local function get_gem_home()
  local gem_home = vim.env.GEM_HOME
  if gem_home and gem_home ~= "" then
    return gem_home
  end
  return util.exec_command("ruby -e 'puts Gem.user_dir'")
end

---@param gems_dir string Path to gems directory
---@return string[] List of unique gem names
local function scan_gems(gems_dir)
  return util.scan_and_deduplicate(gems_dir, nil, function(name)
    local base = util.strip_version_suffix(name)
    return base and base ~= name
  end)
end

---@param buffer_path string Current buffer path
---@return table|nil { root = string, packages = string[] }
function M.detect(buffer_path)
  local project_root = util.find_marker_upward({ "Gemfile" }, vim.fn.fnamemodify(buffer_path, ":h"))

  local bundler_gems
  if project_root then
    local bundle_pattern = project_root .. "/.bundle/ruby/*/gems"
    local raw = vim.fn.glob(bundle_pattern, false, false)
    if raw ~= "" then
      bundler_gems = raw:match("([^\n]+)")
    end
  end

  local gems_dir
  if bundler_gems then
    gems_dir = bundler_gems
  else
    local gem_home = get_gem_home()
    if gem_home then
      gems_dir = gem_home .. "/gems"
    end
  end

  if not gems_dir or not util.is_directory(gems_dir) then
    return nil
  end

  local cache_key = util.make_cache_key("ruby", gems_dir)
  local cached = util.get_cache(cache_key)
  if cached then
    return { root = gems_dir, packages = cached.packages }
  end

  local packages = scan_gems(gems_dir)
  if #packages > 0 then
    table.sort(packages)
    util.set_cache(cache_key, { packages = packages })
    return { root = gems_dir, packages = packages }
  end

  return nil
end

---@param root string Gems directory path
---@param gem_name string Gem name without version
---@return string|nil Versioned directory name, or nil if not found
function M.resolve_directory(root, gem_name)
  return util.resolve_package_dir(root, gem_name, nil, M.file_extension, nil, "%-")
end

---@return table|nil { root = string, packages = string[] }
function M.detect_stdlib()
  local stdlib_dir = util.exec_command("ruby -e \"puts RbConfig::CONFIG['rubylibdir']\"")
  if not stdlib_dir or not util.is_directory(stdlib_dir) then
    return nil
  end

  local cache_key = util.make_cache_key("ruby_stdlib", stdlib_dir)
  local cached = util.get_cache(cache_key)
  if cached then
    return { root = stdlib_dir, packages = cached.packages }
  end

  local packages = util.scan_directories(stdlib_dir)
  if #packages > 0 then
    table.sort(packages)
    util.set_cache(cache_key, { packages = packages })
    return { root = stdlib_dir, packages = packages }
  end

  return nil
end

return M
