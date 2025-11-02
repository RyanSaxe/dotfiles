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
  local modules = {}
  local in_require_block = false

  -- Read go.mod file line by line
  local file = io.open(go_mod_path, "r")
  if not file then
    return modules
  end

  for line in file:lines() do
    -- Check for require block start
    if line:match("^require%s*%(") then
      in_require_block = true
    -- Check for require block end
    elseif in_require_block and line:match("^%)") then
      in_require_block = false
    -- Parse single-line require
    elseif line:match("^require%s+") then
      local module = line:match("^require%s+([%S]+)")
      if module then
        table.insert(modules, module)
      end
    -- Parse require block line
    elseif in_require_block then
      local module = line:match("^%s+([%S]+)")
      if module then
        table.insert(modules, module)
      end
    end
  end

  file:close()
  return modules
end

-- Get GOMODCACHE path from go environment
-- Returns nil if go is not installed or GOMODCACHE is not set
---@return string|nil GOMODCACHE path
local function get_gomodcache()
  local handle = io.popen("go env GOMODCACHE 2>/dev/null")
  if not handle then
    return nil
  end

  local modcache = handle:read("*a"):gsub("%s+", "")
  handle:close()

  if modcache == "" then
    return nil
  end

  return modcache
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
  local cache_key = "go:" .. go_mod
  local cached = util.get_cache(cache_key)
  if cached then
    return { root = cached.packages[1], packages = vim.list_slice(cached.packages, 2) }
  end

  -- Get GOMODCACHE path
  local modcache = get_gomodcache()
  if not modcache then
    return nil
  end

  local stat = util.safe_stat(modcache)
  if not stat or stat.type ~= "directory" then
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
-- These functions provide Go-specific version handling for full extensibility
-- ============================================================================

-- Strip version suffix from Go module directory names
-- Go modules use format: modulename@vX.Y.Z (e.g., repo@v1.2.3 -> repo)
-- For nested paths: github.com/user/repo@v1.2.3 -> github.com/user/repo
---@param name string Module directory name (may include version)
---@return string Module name without version suffix
function M.strip_version(name)
  if not name then
    return nil
  end

  -- Match Go modules with version suffix: modulename@vX.Y.Z
  local stripped = name:match("^(.+)@v[%d%.]+")
  if stripped then
    return stripped
  end

  -- No version pattern found, return as-is
  return name
end

-- Resolve a Go module name to its actual versioned directory
-- For nested paths like "github.com/user/repo", scans the parent directory
-- to find the versioned subdirectory (e.g., repo@v1.2.3)
-- Returns the latest version if multiple versions exist
---@param root string GOMODCACHE directory path
---@param module_name string Module name without version (e.g., "github.com/user/repo")
---@return string|nil Full relative path with version (e.g., "github.com/user/repo@v1.2.3"), or nil if not found
function M.resolve_directory(root, module_name)
  -- Handle nested module paths (contain slashes)
  -- For "github.com/user/repo", we need to:
  -- 1. Extract parent path: "github.com/user"
  -- 2. Extract module base name: "repo"
  -- 3. Scan in root/github.com/user/ for "repo@vX.Y.Z"
  if module_name:match("/") then
    local parent_path, module_base = module_name:match("^(.+)/([^/]+)$")
    if not parent_path or not module_base then
      return nil
    end

    local scan_dir = root .. "/" .. parent_path
    local handle = util.safe_scandir(scan_dir)
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
        -- Match Go modules: modulename@vX.Y.Z
        -- Pattern must end with version numbers to avoid matching metadata dirs
        -- Use vim.pesc to escape special pattern characters in module_base
        if name:match("^" .. vim.pesc(module_base) .. "@v[%d%.]+$") then
          table.insert(matches, parent_path .. "/" .. name)
        end
      end
    end

    if #matches > 0 then
      table.sort(matches)
      return matches[#matches] -- Return latest version
    end

    return nil
  end

  -- Handle simple module names (no nested path)
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
      -- Match Go modules: modulename@vX.Y.Z
      -- Pattern must end with version numbers to avoid matching metadata dirs
      -- Use vim.pesc to escape special pattern characters in module_name
      if name:match("^" .. vim.pesc(module_name) .. "@v[%d%.]+$") then
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

-- Detect Go standard library packages
-- Scans GOROOT/src for standard library packages
---@return table|nil { root = string, packages = string[] }
function M.detect_stdlib()
  -- Get GOROOT
  local handle = io.popen("go env GOROOT 2>/dev/null")
  if not handle then
    return nil
  end

  local goroot = handle:read("*a"):gsub("%s+", "")
  handle:close()

  if not goroot or goroot == "" then
    return nil
  end

  -- Stdlib is in GOROOT/src
  local stdlib_dir = goroot .. "/src"
  local stat = util.safe_stat(stdlib_dir)
  if not stat or stat.type ~= "directory" then
    return nil
  end

  -- Check cache
  local cache_key = "go_stdlib:" .. stdlib_dir
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
