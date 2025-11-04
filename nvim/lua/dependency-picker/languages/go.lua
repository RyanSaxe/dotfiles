-- Go module detector
-- Parses go.mod file to get actual project dependencies
-- Much faster and more accurate than scanning GOMODCACHE

local util = require("dependency-picker.util")

local M = {}

-- Language metadata
M.name = "Go"
M.filetypes = { "go" }
M.requires_buffer_path = true

-- Parse go.mod file to extract dependency module paths
-- Returns list of module paths (e.g., ["github.com/user/repo", ...])
---@param go_mod_path string Path to go.mod file
---@return string[] List of module paths
local function parse_go_mod(go_mod_path)
  -- Use the generic config parser with a custom function
  -- to handle both single-line requires and require blocks
  local in_require_block = false

  return util.parse_config_file(go_mod_path, function(line)
    -- Check for require block start
    if line:match("^require%s*%(") then
      in_require_block = true
      return nil
    -- Check for require block end
    elseif in_require_block and line:match("^%)") then
      in_require_block = false
      return nil
    -- Parse single-line require
    elseif line:match("^require%s+") then
      return line:match("^require%s+([%S]+)")
    -- Parse require block line
    elseif in_require_block then
      return line:match("^%s+([%S]+)")
    end
    return nil
  end)
end

-- Get GOMODCACHE path from go environment
-- Returns nil if go is not installed or GOMODCACHE is not set
---@return string|nil GOMODCACHE path
local function get_gomodcache()
  return util.exec_command("go env GOMODCACHE")
end

-- Detect Go modules from the current project's go.mod
-- Parses dependencies and maps them to GOMODCACHE locations
---@param buffer_path string Current buffer path
---@return table|nil { root = string, packages = string[] }
function M.detect(buffer_path)
  -- Find nearest go.mod file
  local project_root = util.find_marker_upward({ "go.mod" }, vim.fn.fnamemodify(buffer_path, ":h"))
  if not project_root then
    return nil
  end

  local go_mod = project_root .. "/go.mod"

  -- Check cache first (keyed by go.mod path)
  local cache_key = util.make_cache_key("go", go_mod)
  local cached = util.get_cache(cache_key)
  if cached then
    return { root = cached.packages[1], packages = vim.list_slice(cached.packages, 2) }
  end

  -- Get GOMODCACHE path
  local modcache = get_gomodcache()
  if not modcache then
    return nil
  end

  if not util.is_directory(modcache) then
    return nil
  end

  -- Parse go.mod to get dependencies
  local modules = parse_go_mod(go_mod)

  if #modules > 0 then
    table.sort(modules)
    -- Store modcache as first element for cache
    util.set_cache(cache_key, { packages = { modcache, unpack(modules) } })
    return { root = modcache, packages = modules }
  end

  return nil
end

-- ============================================================================
-- OPTIONAL: Language-specific versioning functions
-- ============================================================================

-- Note: Go version stripping is handled by util.strip_version_suffix
-- which supports Go format: modulename@vX.Y.Z including pseudo-versions

-- Resolve a Go module name to its actual versioned directory
-- Uses the generic resolver with Go-specific version separator (@v)
---@param root string GOMODCACHE directory path
---@param module_name string Module name without version (e.g., "github.com/user/repo")
---@return string|nil Full relative path with version (e.g., "github.com/user/repo@v1.2.3"), or nil if not found
function M.resolve_directory(root, module_name)
  -- Use the generic versioned package resolver with Go's @v separator
  return util.resolve_versioned_package(root, module_name, "@v", nil)
end

-- Detect Go standard library packages
-- Scans GOROOT/src for standard library packages
---@return table|nil { root = string, packages = string[] }
function M.detect_stdlib()
  -- Get GOROOT
  local goroot = util.exec_command("go env GOROOT")
  if not goroot then
    return nil
  end

  -- Stdlib is in GOROOT/src
  local stdlib_dir = goroot .. "/src"
  if not util.is_directory(stdlib_dir) then
    return nil
  end

  -- Check cache
  local cache_key = util.make_cache_key("go_stdlib", stdlib_dir)
  local cached = util.get_cache(cache_key)
  if cached then
    return { root = stdlib_dir, packages = cached.packages }
  end

  -- Scan stdlib directory for packages
  -- Go stdlib packages can be nested (e.g., net/http)
  local packages = util.scan_directories(stdlib_dir)

  if #packages > 0 then
    table.sort(packages)
    util.set_cache(cache_key, { packages = packages })
    return { root = stdlib_dir, packages = packages }
  end

  return nil
end

return M
