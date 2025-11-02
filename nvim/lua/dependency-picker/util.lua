-- Shared utilities for dependency-picker plugin
-- Contains: caching, path operations, error handling

local M = {}

-- ============================================================================
-- CACHE MANAGEMENT
-- TTL-based cache for expensive filesystem operations (5 min default)
-- ============================================================================

-- Cache structure: { [key] = { packages = {...}, timestamp = ... } }
local cache = {}
local CACHE_TTL = 300 -- 5 minutes in seconds

-- Get cached data if it exists and hasn't expired
-- Returns nil if cache miss or expired
---@param key string Cache key (typically "lang:path")
---@return table|nil Cached data with 'packages' field
function M.get_cache(key)
  local cached = cache[key]
  if not cached then
    return nil
  end

  local age = os.time() - cached.timestamp
  if age > CACHE_TTL then
    cache[key] = nil
    return nil
  end

  return cached
end

-- Store data in cache with current timestamp
---@param key string Cache key
---@param data table Data to cache (must include 'packages' field)
function M.set_cache(key, data)
  cache[key] = {
    packages = data.packages,
    timestamp = os.time(),
  }
end

-- ============================================================================
-- PATH UTILITIES
-- ============================================================================

-- Strip version suffix from package name
-- Handles different version formats:
--   - Ruby/Rust: packagename-X.Y.Z -> packagename
--   - Go: packagename@vX.Y.Z -> packagename
-- Returns original name if no version pattern found
--
-- Supports language-specific version stripping via optional strip_fn parameter
---@param name string Package directory name (may include version)
---@param strip_fn function|nil Optional language-specific version stripping function
---@return string Package name without version suffix
function M.strip_version_suffix(name, strip_fn)
  if not name then
    return nil
  end

  -- Use language-specific function if provided
  if strip_fn then
    return strip_fn(name)
  end

  -- Fallback: Built-in heuristics for common formats

  -- Ruby/Rust format: packagename-X.Y.Z
  local stripped = name:match("^(.+)%-[%d%.]+")
  if stripped then
    return stripped
  end

  -- Go format: packagename@vX.Y.Z
  stripped = name:match("^(.+)@v[%d%.]+")
  if stripped then
    return stripped
  end

  -- No version pattern found, return as-is (e.g., JavaScript/Python packages)
  return name
end

-- Search upward from start_path to find a directory containing one of the marker files
-- Useful for finding project roots (e.g., package.json, go.mod, Gemfile)
---@param markers string[] List of marker files to search for
---@param start_path string Starting directory path
---@return string|nil Directory containing the first found marker, or nil
function M.find_marker_upward(markers, start_path)
  local current = start_path
  local root = vim.loop.os_homedir() or "/"

  -- Walk up the directory tree until we hit the root
  while current and current ~= root do
    for _, marker in ipairs(markers) do
      local marker_path = current .. "/" .. marker
      if vim.loop.fs_stat(marker_path) then
        return current
      end
    end

    -- Move up one directory
    local parent = vim.fn.fnamemodify(current, ":h")
    if parent == current then
      break
    end
    current = parent
  end

  return nil
end

-- Check if a path is within another path (path is a subdirectory of parent)
---@param path string The path to check
---@param parent string The potential parent path
---@return boolean True if path is within parent
function M.is_path_within(path, parent)
  if not path or not parent then
    return false
  end
  -- Normalize paths and check prefix
  local normalized_path = vim.fn.resolve(path)
  local normalized_parent = vim.fn.resolve(parent)
  return normalized_path:sub(1, #normalized_parent + 1) == normalized_parent .. "/"
end

-- Extract the package name from a path within a dependency root
-- Automatically strips version suffixes for versioned packages
-- Examples:
--   - /path/to/node_modules/lodash/index.js -> "lodash"
--   - /path/to/gems/rails-7.0.0/lib/rails.rb -> "rails"
--   - /GOMODCACHE/github.com/user/repo@v1.2.3/file.go -> "repo"
--
-- Supports language-specific version stripping via optional strip_fn parameter
---@param path string Full path to current file
---@param dep_root string Dependency root path (e.g., site-packages, node_modules)
---@param strip_fn function|nil Optional language-specific version stripping function
---@return string|nil Package name without version (suitable for lookup in packages list)
function M.extract_package_name(path, dep_root, strip_fn)
  if not M.is_path_within(path, dep_root) then
    return nil
  end

  local rel = path:sub(#dep_root + 2) -- Strip dep_root + "/"
  local pkg = rel:match("^([^/]+)")

  -- Strip version suffix so it matches the deduplicated packages list
  return M.strip_version_suffix(pkg, strip_fn)
end

-- ============================================================================
-- ERROR HANDLING
-- Wrap filesystem operations with error handling and user notifications
-- ============================================================================

-- Safely check if a path exists and return its stat info
-- Returns nil on error instead of throwing
---@param path string Path to check
---@return table|nil Stat info from vim.loop.fs_stat, or nil on error
function M.safe_stat(path)
  local ok, stat = pcall(vim.loop.fs_stat, path)
  if not ok then
    return nil
  end
  return stat
end

-- Safely open a directory for scanning
-- Returns nil and logs error on failure
---@param path string Directory path to scan
---@return userdata|nil Directory handle from vim.loop.fs_scandir, or nil on error
function M.safe_scandir(path)
  local ok, handle = pcall(vim.loop.fs_scandir, path)
  if not ok or not handle then
    -- Silent failure - callers will check for nil
    return nil
  end
  return handle
end

-- ============================================================================
-- DIRECTORY SCANNING
-- Common pattern: scan a directory and collect directories matching criteria
-- ============================================================================

-- Scan a directory and return all subdirectories matching a filter function
-- Automatically excludes hidden directories (starting with .)
---@param dir_path string Directory to scan
---@param filter_fn function|nil Optional filter function(name) -> boolean
---@return string[] List of directory names (not full paths)
function M.scan_directories(dir_path, filter_fn)
  local handle = M.safe_scandir(dir_path)
  if not handle then
    return {}
  end

  local results = {}
  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end

    -- Only include directories, exclude hidden
    if type == "directory" and not name:match("^%.") then
      if not filter_fn or filter_fn(name) then
        table.insert(results, name)
      end
    end
  end

  return results
end

-- Resolve a package name to its actual directory name
-- Handles different versioning strategies:
--   1. Versioned packages (Ruby/Rust/Go): Finds packagename-X.Y.Z or packagename@vX.Y.Z
--   2. Non-versioned packages (JavaScript/Python): Returns exact match
--
-- For Go modules with nested paths (e.g., "github.com/user/repo"), this function
-- scans the parent directory to find the versioned subdirectory.
--
-- Supports language-specific directory resolution via optional resolve_fn parameter
--
-- Returns the full relative path, or nil if no match exists
---@param root string Root path to search in (e.g., gems directory, GOMODCACHE, node_modules)
---@param package_name string Package name without version (e.g., "rails", "lodash", "github.com/user/repo")
---@param resolve_fn function|nil Optional language-specific directory resolution function
---@return string|nil Full directory path (relative to root), or nil if not found
function M.resolve_package_dir(root, package_name, resolve_fn)
  -- Use language-specific resolution function if provided
  if resolve_fn then
    return resolve_fn(root, package_name)
  end

  -- Fallback: Built-in heuristics for common formats

  -- Handle Go module paths (contain slashes)
  -- For "github.com/user/repo", we need to:
  -- 1. Extract parent path: "github.com/user"
  -- 2. Extract package name: "repo"
  -- 3. Scan in root/github.com/user/ for "repo@vX.Y.Z"
  if package_name:match("/") then
    local parent_path, pkg_base = package_name:match("^(.+)/([^/]+)$")
    if not parent_path or not pkg_base then
      return nil
    end

    local scan_dir = root .. "/" .. parent_path
    local handle = M.safe_scandir(scan_dir)
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
        -- Go format: packagename@vX.Y.Z
        if name:match("^" .. vim.pesc(pkg_base) .. "@v[%d%.]") then
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

  -- Handle simple package names
  local handle = M.safe_scandir(root)
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
      -- Versioned format: packagename-X.Y.Z (Ruby/Rust)
      if name:match("^" .. vim.pesc(package_name) .. "%-[%d%.]") then
        table.insert(matches, name)
      -- Exact match: packagename (JavaScript/Python)
      elseif name == package_name then
        table.insert(matches, name)
      end
    end
  end

  if #matches > 0 then
    table.sort(matches)
    return matches[#matches] -- Return latest version or exact match
  end

  return nil
end

return M
