-- Rust/Cargo detector
-- Scans Cargo registry for installed crates
-- Deduplicates crate names across versions (e.g., serde-1.0.0, serde-1.0.1 -> serde)

local util = require("dependency-picker.util")

local M = {}

-- Language metadata
M.name = "Rust"
M.filetypes = { "rust" }
M.requires_buffer_path = false

-- Detect Rust crates from Cargo registry
-- Automatically strips version suffixes to get unique crate names
---@return table|nil { root = string, packages = string[] }
function M.detect()
  local cargo_home = vim.env.CARGO_HOME or (vim.env.HOME .. "/.cargo")
  local registry_src = cargo_home .. "/registry/src"

  local stat = util.safe_stat(registry_src)
  if not stat or stat.type ~= "directory" then
    return nil
  end

  -- Check cache first
  local cache_key = "rust:" .. registry_src
  local cached = util.get_cache(cache_key)
  if cached then
    -- First item is actual src path (hash dir)
    return { root = cached.packages[1], packages = vim.list_slice(cached.packages, 2) }
  end

  -- Find the registry hash directory (usually only one)
  -- Example: ~/.cargo/registry/src/github.com-1ecc6299db9ec823/
  local handle = util.safe_scandir(registry_src)
  if not handle then
    return nil
  end

  local hash_dir
  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end
    if type == "directory" then
      hash_dir = registry_src .. "/" .. name
      break
    end
  end

  if not hash_dir then
    return nil
  end

  -- Scan crates in hash directory
  -- Crate directories are named: cratename-version (e.g., serde-1.0.0)
  local crates_handle = util.safe_scandir(hash_dir)
  if not crates_handle then
    return nil
  end

  local packages = {}
  local seen = {} -- Track unique crate names (deduplicate versions)

  while true do
    local name, type = vim.loop.fs_scandir_next(crates_handle)
    if not name then
      break
    end

    if type == "directory" and not name:match("^%.") then
      -- Extract crate name by stripping version suffix
      -- Handles multi-hyphenated names like "serde-json-1.0.0" -> "serde-json"
      local crate_name = util.strip_version_suffix(name)
      if crate_name and crate_name ~= name and not seen[crate_name] then
        seen[crate_name] = true
        table.insert(packages, crate_name)
      end
    end
  end

  if #packages > 0 then
    table.sort(packages)
    -- Store hash_dir as first element for cache
    util.set_cache(cache_key, { packages = { hash_dir, unpack(packages) } })
    return { root = hash_dir, packages = packages }
  end

  return nil
end

-- ============================================================================
-- OPTIONAL: Language-specific versioning functions
-- These functions provide Rust-specific version handling for full extensibility
-- ============================================================================

-- Strip version suffix from Rust crate directory names
-- Rust crates use format: cratename-X.Y.Z (e.g., serde-1.0.0 -> serde)
-- Handles multi-hyphenated crates: serde-json-1.0.0 -> serde-json
---@param name string Crate directory name (may include version)
---@return string Crate name without version suffix
function M.strip_version(name)
  if not name then
    return nil
  end

  -- Match crates with version suffix: cratename-X.Y.Z
  -- The pattern matches the last hyphen followed by version numbers
  local stripped = name:match("^(.+)%-[%d%.]+")
  if stripped then
    return stripped
  end

  -- No version pattern found, return as-is
  return name
end

-- Resolve a crate name to its actual versioned directory
-- Scans the cargo registry to find the versioned directory (e.g., serde -> serde-1.0.0)
-- Returns the latest version if multiple versions exist
---@param root string Cargo registry src directory path (hash directory)
---@param crate_name string Crate name without version (e.g., "serde")
---@return string|nil Versioned directory name (e.g., "serde-1.0.0"), or nil if not found
function M.resolve_directory(root, crate_name)
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
      -- Match versioned crates: cratename-X.Y.Z
      -- Pattern must end with version numbers to avoid matching metadata dirs
      -- Use vim.pesc to escape special pattern characters in crate_name
      if name:match("^" .. vim.pesc(crate_name) .. "%-[%d%.]+$") then
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

return M
