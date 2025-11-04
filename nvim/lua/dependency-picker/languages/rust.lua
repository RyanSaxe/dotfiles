-- Rust/Cargo detector
-- Project-scoped: Detects crates from current Cargo.toml dependencies
-- Resolves to Cargo registry paths for actual crate source code

local util = require("dependency-picker.util")

local M = {}

-- Language metadata
M.name = "Rust"
M.filetypes = { "rust" }
M.requires_buffer_path = true

-- Parse Cargo.toml to extract dependency crate names
-- Returns list of crate names from [dependencies] and [dev-dependencies]
---@param cargo_toml_path string Path to Cargo.toml file
---@return string[] List of crate names
local function parse_cargo_toml(cargo_toml_path)
  -- Use the generic config parser with a custom function
  -- to handle TOML dependency sections
  local in_dependencies = false

  return util.parse_config_file(cargo_toml_path, function(line)
    -- Check for dependency sections
    if line:match("^%[dependencies%]") or line:match("^%[dev%-dependencies%]") then
      in_dependencies = true
      return nil
    -- Exit section when we hit another [section]
    elseif line:match("^%[") then
      in_dependencies = false
      return nil
    -- Parse dependency lines
    elseif in_dependencies then
      -- Match lines like: serde = "1.0" or serde = { version = "1.0" }
      return line:match("^([%w_%-]+)%s*=")
    end
    return nil
  end)
end

-- Get cargo registry hash directory
-- Example: ~/.cargo/registry/src/github.com-1ecc6299db9ec823/
---@return string|nil Hash directory path
local function get_cargo_hash_dir()
  local cargo_home = vim.env.CARGO_HOME or (vim.env.HOME .. "/.cargo")
  local registry_src = cargo_home .. "/registry/src"

  if not util.is_directory(registry_src) then
    return nil
  end

  -- Find the registry hash directory (usually only one)
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

  return hash_dir
end

-- Detect Rust crates from current project's Cargo.toml dependencies
-- Project-scoped: Only shows crates listed in Cargo.toml, not all global crates
---@param buffer_path string Current buffer path
---@return table|nil { root = string, packages = string[] }
function M.detect(buffer_path)
  -- Find nearest Cargo.toml
  local project_root = util.find_marker_upward({ "Cargo.toml" }, vim.fn.fnamemodify(buffer_path, ":h"))
  if not project_root then
    return nil
  end

  local cargo_toml = project_root .. "/Cargo.toml"

  -- Check cache first (keyed by Cargo.toml path)
  local cache_key = util.make_cache_key("rust", cargo_toml)
  local cached = util.get_cache(cache_key)
  if cached then
    -- First item is hash_dir, rest are packages
    return { root = cached.packages[1], packages = vim.list_slice(cached.packages, 2) }
  end

  -- Get cargo registry hash directory
  local hash_dir = get_cargo_hash_dir()
  if not hash_dir then
    return nil
  end

  -- Parse Cargo.toml to get project dependencies
  local crates = parse_cargo_toml(cargo_toml)

  if #crates > 0 then
    table.sort(crates)
    -- Store hash_dir as first element for cache
    util.set_cache(cache_key, { packages = { hash_dir, unpack(crates) } })
    return { root = hash_dir, packages = crates }
  end

  return nil
end

-- ============================================================================
-- OPTIONAL: Language-specific versioning functions
-- ============================================================================

-- Note: Rust version stripping is handled by util.strip_version_suffix
-- which supports Rust format: cratename-X.Y.Z including prereleases

-- Resolve a crate name to its actual versioned directory
-- Uses the generic resolver with Rust-specific version separator (-)
---@param root string Cargo registry src directory path (hash directory)
---@param crate_name string Crate name without version (e.g., "serde")
---@return string|nil Versioned directory name (e.g., "serde-1.0.0"), or nil if not found
function M.resolve_directory(root, crate_name)
  -- Use the generic versioned package resolver with Rust's - separator
  return util.resolve_versioned_package(root, crate_name, "%-", nil)
end

-- Detect Rust standard library source
-- Requires: rustup component add rust-src
-- Returns stdlib crates like std, core, alloc, etc.
---@return table|nil { root = string, packages = string[] }
function M.detect_stdlib()
  -- Get rustc sysroot
  local sysroot = util.exec_command("rustc --print sysroot")
  if not sysroot then
    return nil
  end

  -- Stdlib source is in sysroot/lib/rustlib/src/rust/library
  local stdlib_dir = sysroot .. "/lib/rustlib/src/rust/library"
  if not util.is_directory(stdlib_dir) then
    return nil
  end

  -- Check cache
  local cache_key = util.make_cache_key("rust_stdlib", stdlib_dir)
  local cached = util.get_cache(cache_key)
  if cached then
    return { root = stdlib_dir, packages = cached.packages }
  end

  -- Scan stdlib directory for crates
  local packages = util.scan_directories(stdlib_dir)

  if #packages > 0 then
    table.sort(packages)
    util.set_cache(cache_key, { packages = packages })
    return { root = stdlib_dir, packages = packages }
  end

  return nil
end

return M
