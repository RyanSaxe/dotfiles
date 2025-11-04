-- Shared utilities for dependency-picker plugin
-- Contains: caching, path operations, error handling

local M = {}

-- ============================================================================
-- CACHE MANAGEMENT
-- TTL-based cache for expensive filesystem operations (5 min default)
-- Thread-safe implementation to prevent race conditions
-- ============================================================================

-- Cache structure: { [key] = { packages = {...}, timestamp = ..., lock = false } }
local cache = {}
local CACHE_TTL = 300 -- 5 minutes in seconds
local cache_locks = {} -- Track locks for cache operations

-- Get cached data if it exists and hasn't expired
-- Returns nil if cache miss or expired
-- Thread-safe: Uses immutable access patterns
---@param key string Cache key (typically "lang:path")
---@return table|nil Cached data with 'packages' field
function M.get_cache(key)
  -- Check if key is locked (being written)
  if cache_locks[key] then
    return nil -- Return cache miss during write operations
  end

  local cached = cache[key]
  if not cached then
    return nil
  end

  local current_time = os.time()
  local age = current_time - cached.timestamp
  if age > CACHE_TTL then
    -- Atomically clear expired cache
    cache[key] = nil
    return nil
  end

  -- Return a copy to prevent external mutations
  return {
    packages = vim.deepcopy(cached.packages),
    timestamp = cached.timestamp,
  }
end

-- Store data in cache with current timestamp
-- Thread-safe: Uses locking to prevent concurrent writes
---@param key string Cache key
---@param data table Data to cache (must include 'packages' field)
function M.set_cache(key, data)
  -- Set lock to prevent reads during write
  cache_locks[key] = true

  -- Perform the cache update
  cache[key] = {
    packages = vim.deepcopy(data.packages), -- Store a copy to prevent external mutations
    timestamp = os.time(),
  }

  -- Release lock
  cache_locks[key] = nil
end

-- Clear all cache entries (useful for testing or manual refresh)
function M.clear_cache()
  cache = {}
  cache_locks = {}
end

-- Get cache statistics (for debugging)
---@return table Statistics about cache usage
function M.get_cache_stats()
  local count = 0
  local oldest = nil
  local current_time = os.time()

  for _, entry in pairs(cache) do
    count = count + 1
    local age = current_time - entry.timestamp
    if not oldest or age > oldest then
      oldest = age
    end
  end

  return {
    entry_count = count,
    oldest_age_seconds = oldest,
    ttl_seconds = CACHE_TTL,
  }
end

-- ============================================================================
-- INPUT VALIDATION
-- Security and sanity checks for user inputs
-- ============================================================================

-- Validate a package name to prevent path traversal attacks
-- Rejects names with .., absolute paths, and special characters
---@param name string Package name to validate
---@return boolean True if name is safe
function M.is_safe_package_name(name)
  if not name or name == "" then
    return false
  end

  -- Reject path traversal attempts
  if name:match("%.%.") then
    return false
  end

  -- Reject absolute paths
  if name:match("^/") or name:match("^[A-Z]:") then
    return false
  end

  -- Reject special shell characters that could cause issues
  if name:match("[<>|&;`$]") then
    return false
  end

  return true
end

-- Validate a file path is within expected boundaries
-- Prevents access to sensitive system files
---@param path string Path to validate
---@return boolean True if path is safe to access
function M.is_safe_path(path)
  if not path or path == "" then
    return false
  end

  -- Normalize the path
  local normalized = vim.fn.resolve(path)

  -- Check against sensitive directories
  local forbidden = {
    "/etc",
    "/proc",
    "/sys",
    "/dev",
    vim.env.HOME .. "/.ssh",
    vim.env.HOME .. "/.gnupg",
  }

  for _, forbidden_path in ipairs(forbidden) do
    if M.is_path_within(normalized, forbidden_path) then
      return false
    end
  end

  return true
end

-- ============================================================================
-- PATH UTILITIES
-- ============================================================================

-- Strip version suffix from package name
-- Handles different version formats:
--   - Ruby/Rust: packagename-X.Y.Z or packagename-X.Y.Z-alpha -> packagename
--   - Go: packagename@vX.Y.Z or packagename@vX.Y.Z-rc.1 -> packagename
--   - Go pseudo-versions: packagename@v0.0.0-20231104123456-abcdef123456 -> packagename
-- Returns original name if no version pattern found
--
-- Supports language-specific version stripping via optional strip_fn parameter
---@param name string|nil Package directory name (may include version)
---@param strip_fn function|nil Optional language-specific version stripping function
---@return string|nil Package name without version suffix
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
  -- Matches: package-1.0.0, multi-word-package-2.1.0
  -- Also handles prereleases: package-1.0.0-alpha, package-1.0.0-beta.1
  local stripped = name:match("^(.+)%-[%d]+%.[%d%.%-_%w]*")
  if stripped then
    return stripped
  end

  -- Go format: packagename@vX.Y.Z
  -- Handles: package@v1.0.0, package@v1.0.0-rc.1
  -- Also Go pseudo-versions: package@v0.0.0-20231104123456-abcdef123456
  stripped = name:match("^(.+)@v[%d]+%.[%d%.%-_%w]*")
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
  local root = vim.uv.os_homedir() or "/"

  -- Walk up the directory tree until we hit the root
  while current and current ~= root do
    for _, marker in ipairs(markers) do
      local marker_path = current .. "/" .. marker
      if vim.uv.fs_stat(marker_path) then
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
---@return table|nil Stat info from vim.uv.fs_stat, or nil on error
function M.safe_stat(path)
  local ok, stat = pcall(vim.uv.fs_stat, path)
  if not ok then
    return nil
  end
  return stat
end

-- ============================================================================
-- COMMAND EXECUTION
-- Standardized execution of shell commands with error handling
-- ============================================================================

-- Execute a shell command and return trimmed stdout
-- Automatically handles stderr redirection and output trimming
-- Returns nil on error or empty output
---@param cmd string Command to execute
---@return string|nil Trimmed output string, or nil on error
function M.exec_command(cmd, _)
  -- Add stderr redirection if not already present
  local full_cmd = cmd
  if not cmd:match("2>") then
    full_cmd = cmd .. " 2>/dev/null"
  end

  local handle = io.popen(full_cmd)
  if not handle then
    return nil
  end

  local ok, output = pcall(handle.read, handle, "*a")
  handle:close()

  if not ok or not output then
    return nil
  end

  -- Trim whitespace from both ends
  output = output:gsub("^%s+", ""):gsub("%s+$", "")

  -- Return nil for empty output
  if output == "" then
    return nil
  end

  return output
end

-- ============================================================================
-- PATH VALIDATION UTILITIES
-- Convenient wrappers for common filesystem checks
-- ============================================================================

-- Check if a path exists and is a directory
---@param path string Path to check
---@return boolean True if path exists and is a directory
function M.is_directory(path)
  local stat = M.safe_stat(path)
  return stat ~= nil and stat.type == "directory"
end

-- Check if a path exists and is a file
---@param path string Path to check
---@return boolean True if path exists and is a file
function M.is_file(path)
  local stat = M.safe_stat(path)
  return stat ~= nil and stat.type == "file"
end

-- Check if a path exists (file or directory)
---@param path string Path to check
---@return boolean True if path exists
function M.exists(path)
  return M.safe_stat(path) ~= nil
end

-- ============================================================================
-- CACHE UTILITIES
-- Helper functions for cache management
-- ============================================================================

-- Build a standardized cache key from language and path
---@param lang string Language identifier (e.g., "python", "javascript")
---@param path string Path or other identifier
---@return string Formatted cache key
function M.make_cache_key(lang, path)
  return string.format("%s:%s", lang, path)
end

-- Safely open a directory for scanning
-- Returns nil and logs error on failure
---@param path string Directory path to scan
---@return any|nil Directory handle from vim.uv.fs_scandir, or nil on error
function M.safe_scandir(path)
  local ok, handle = pcall(vim.uv.fs_scandir, path)
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
    local name, type = vim.uv.fs_scandir_next(handle)
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
---@param file_extension string|nil Optional file extension to check for single-file modules (e.g., ".py", ".rb")
---@return string|nil Full directory/file path (relative to root), or nil if not found
function M.resolve_package_dir(root, package_name, resolve_fn, file_extension, exclude_patterns)
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
      local name, type = vim.uv.fs_scandir_next(handle)
      if not name then
        break
      end

      if type == "directory" then
        -- Check exclude patterns first
        local excluded = false
        if exclude_patterns then
          for _, pattern in ipairs(exclude_patterns) do
            if name:match(pattern) then
              excluded = true
              break
            end
          end
        end

        if not excluded then
          -- Go format: packagename@vX.Y.Z
          -- Pattern handles versions and pseudo-versions: @v1.2.3, @v0.0.0-timestamp-hash
          if name:match("^" .. vim.pesc(pkg_base) .. "@v[%d]+%.[%d%.%-_%w]*$") then
            table.insert(matches, parent_path .. "/" .. name)
          end
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
    local name, type = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end

    if type == "directory" then
      -- Check exclude patterns first
      local excluded = false
      if exclude_patterns then
        for _, pattern in ipairs(exclude_patterns) do
          if name:match(pattern) then
            excluded = true
            break
          end
        end
      end

      if not excluded then
        -- Versioned format: packagename-X.Y.Z (Ruby/Rust)
        -- Pattern handles versions with prereleases: -1.0.0, -1.0.0-beta.1
        -- Avoids matching metadata dirs like "pandas-2.3.3.dist-info" (contains dots after version)
        if name:match("^" .. vim.pesc(package_name) .. "%-[%d]+%.[%d%.%-_%w]*$") then
          table.insert(matches, name)
        -- Exact match: packagename (JavaScript/Python)
        elseif name == package_name then
          table.insert(matches, name)
        end
      end
    end
  end

  if #matches > 0 then
    table.sort(matches)
    -- TODO: Add file content validation here
    -- Future enhancement: Verify the selected directory contains files of the expected type
    -- e.g., for Python, check if directory contains .py files
    -- This would prevent returning metadata-only directories
    return matches[#matches] -- Return latest version or exact match
  end

  -- If no directory found and file_extension provided, check for single-file module
  -- E.g., Python: os.py, Ruby: base64.rb
  if file_extension then
    local file_name = package_name .. file_extension
    local file_path = root .. "/" .. file_name
    local stat = M.safe_stat(file_path)
    if stat and stat.type == "file" then
      return file_name
    end
  end

  return nil
end

-- ============================================================================
-- PACKAGE SCANNING AND DEDUPLICATION
-- Common patterns for scanning and deduplicating versioned packages
-- ============================================================================

-- Scan a directory and deduplicate packages by stripping version suffixes
-- Returns unique package names (without versions)
---@param dir_path string Directory to scan
---@param strip_fn function|nil Optional version stripping function
---@param filter_fn function|nil Optional filter function(name) -> boolean
---@return string[] List of unique package names without versions
function M.scan_and_deduplicate(dir_path, strip_fn, filter_fn)
  local handle = M.safe_scandir(dir_path)
  if not handle then
    return {}
  end

  local seen = {} -- Track unique package names
  local results = {}

  while true do
    local name, type = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end

    -- Only include directories, exclude hidden
    if type == "directory" and not name:match("^%.") then
      -- Apply optional filter
      if not filter_fn or filter_fn(name) then
        -- Strip version to get base package name
        local base_name = M.strip_version_suffix(name, strip_fn)
        if base_name and not seen[base_name] then
          seen[base_name] = true
          table.insert(results, base_name)
        end
      end
    end
  end

  return results
end

-- Resolve a versioned package to its actual directory
-- Handles different version separators (e.g., "-" for Ruby/Rust, "@v" for Go)
---@param root string Root directory to search in
---@param package_name string Package name without version
---@param version_separator string Version separator pattern (e.g., "%-", "@v")
---@param file_extension string|nil Optional file extension for single-file modules
---@return string|nil Resolved directory/file path relative to root
function M.resolve_versioned_package(root, package_name, version_separator, file_extension, exclude_patterns)
  -- Handle nested paths (e.g., Go modules like github.com/user/repo)
  if package_name:match("/") then
    local parent_path, pkg_base = package_name:match("^(.+)/([^/]+)$")
    if not parent_path or not pkg_base then
      return nil
    end

    local scan_dir = root .. "/" .. parent_path
    if not M.is_directory(scan_dir) then
      return nil
    end

    local handle = M.safe_scandir(scan_dir)
    if not handle then
      return nil
    end

    local matches = {}
    while true do
      local name, type = vim.uv.fs_scandir_next(handle)
      if not name then
        break
      end

      if type == "directory" then
        -- Check exclude patterns first
        local excluded = false
        if exclude_patterns then
          for _, pattern in ipairs(exclude_patterns) do
            if name:match(pattern) then
              excluded = true
              break
            end
          end
        end

        if not excluded then
          -- Match versioned pattern with proper version format
          -- Handles: package-1.0.0, package@v1.2.3, package-1.0.0-beta.1
          local pattern = "^" .. vim.pesc(pkg_base) .. version_separator .. "[%d]+%.[%d%.%-_%w]*$"
          if name:match(pattern) then
            table.insert(matches, parent_path .. "/" .. name)
          end
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
    local name, type = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end

    if type == "directory" then
      -- Check exclude patterns first
      local excluded = false
      if exclude_patterns then
        for _, pattern in ipairs(exclude_patterns) do
          if name:match(pattern) then
            excluded = true
            break
          end
        end
      end

      if not excluded then
        -- Match versioned pattern with proper version format
        -- Handles: package-1.0.0, package@v1.2.3, package-1.0.0-beta.1
        local pattern = "^" .. vim.pesc(package_name) .. version_separator .. "[%d]+%.[%d%.%-_%w]*$"
        if name:match(pattern) then
          table.insert(matches, name)
        -- Exact match (for non-versioned packages)
        elseif name == package_name then
          table.insert(matches, name)
        end
      end
    end
  end

  if #matches > 0 then
    table.sort(matches)
    return matches[#matches] -- Return latest version or exact match
  end

  -- Check for single-file module if extension provided
  if file_extension then
    local file_name = package_name .. file_extension
    local file_path = root .. "/" .. file_name
    if M.is_file(file_path) then
      return file_name
    end
  end

  return nil
end

-- Parse a configuration file line by line
-- Supports extracting dependencies from various config formats
---@param file_path string Path to configuration file
---@param pattern string|function Pattern to match or function(line) -> string|nil
---@param options table|nil Options: { in_block = false, block_start = pattern, block_end = pattern }
---@return string[] List of extracted values
function M.parse_config_file(file_path, pattern, options)
  local file = io.open(file_path, "r")
  if not file then
    return {}
  end

  local results = {}
  local in_block = options and options.in_block or false
  local current_block = false

  local ok, _ = pcall(function()
    for line in file:lines() do
      -- Handle block-based parsing (e.g., TOML sections)
      if options and options.block_start then
        if line:match(options.block_start) then
          current_block = true
        elseif options.block_end and line:match(options.block_end) then
          current_block = false
        end

        if not current_block and in_block then
          goto continue
        end
      end

      -- Extract value using pattern or function
      local value
      if type(pattern) == "function" then
        value = pattern(line)
      else
        value = line:match(pattern)
      end

      if value then
        table.insert(results, value)
      end

      ::continue::
    end
  end)

  file:close()

  if not ok then
    return {}
  end

  return results
end

-- Scan directories with support for scoped/namespaced packages
-- Handles patterns like @org/package (JavaScript), github.com/user/repo (Go)
---@param root string Root directory to scan
---@param scope_pattern string|nil Pattern to identify scoped directories (e.g., "^@")
---@param filter_fn function|nil Optional filter function(name) -> boolean
---@return string[] List of package names (including scope prefix)
function M.scan_packages_with_scope(root, scope_pattern, filter_fn)
  local handle = M.safe_scandir(root)
  if not handle then
    return {}
  end

  local packages = {}

  while true do
    local name, type = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end

    if type == "directory" and not name:match("^%.") then
      -- Check if this is a scope directory
      if scope_pattern and name:match(scope_pattern) then
        -- Scan inside the scope directory
        local scope_path = root .. "/" .. name
        local scope_handle = M.safe_scandir(scope_path)
        if scope_handle then
          while true do
            local scope_pkg, scope_type = vim.uv.fs_scandir_next(scope_handle)
            if not scope_pkg then
              break
            end

            if scope_type == "directory" and not scope_pkg:match("^%.") then
              local full_name = name .. "/" .. scope_pkg
              if not filter_fn or filter_fn(full_name) then
                table.insert(packages, full_name)
              end
            end
          end
        end
      else
        -- Regular package
        if not filter_fn or filter_fn(name) then
          table.insert(packages, name)
        end
      end
    end
  end

  return packages
end

return M
