local util = require("dependency-picker.util")

local M = {}

M.name = "Rust"
M.filetypes = { "rust" }
M.requires_buffer_path = true
M.file_extensions = { "rs" }

---@param cargo_toml_path string Path to Cargo.toml file
---@return string[] List of crate names
local function parse_cargo_toml(cargo_toml_path)
  local in_dependencies = false
  return util.parse_config_file(cargo_toml_path, function(line)
    if line:match("^%[dependencies%]") or line:match("^%[dev%-dependencies%]") then
      in_dependencies = true
      return nil
    elseif line:match("^%[") then
      in_dependencies = false
      return nil
    elseif in_dependencies then
      return line:match("^([%w_%-]+)%s*=")
    end
    return nil
  end)
end

---@return string|nil Hash directory path
local function get_cargo_hash_dir()
  local cargo_home = vim.env.CARGO_HOME or (vim.env.HOME .. "/.cargo")
  local registry_src = cargo_home .. "/registry/src"
  if not util.is_directory(registry_src) then
    return nil
  end

  local handle = util.safe_scandir(registry_src)
  if not handle then
    return nil
  end

  local hash_dir
  while true do
    local name, type = vim.uv.fs_scandir_next(handle)
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

---@param buffer_path string Current buffer path
---@return table|nil { root = string, packages = string[] }
function M.detect(buffer_path)
  local project_root = util.find_marker_upward({ "Cargo.toml" }, vim.fn.fnamemodify(buffer_path, ":h"))
  if not project_root then
    return nil
  end

  local cargo_toml = project_root .. "/Cargo.toml"
  local cache_key = util.make_cache_key("rust", cargo_toml)
  local cached = util.get_cache(cache_key)
  if cached then
    return { root = cached.packages[1], packages = vim.list_slice(cached.packages, 2) }
  end

  local hash_dir = get_cargo_hash_dir()
  if not hash_dir then
    return nil
  end

  local crates = parse_cargo_toml(cargo_toml)
  if #crates > 0 then
    table.sort(crates)
    util.set_cache(cache_key, { packages = { hash_dir, unpack(crates) } })
    return { root = hash_dir, packages = crates }
  end

  return nil
end

---@param root string Cargo registry src directory path (hash directory)
---@param crate_name string Crate name without version
---@return string|nil Versioned directory name, or nil if not found
function M.resolve_directory(root, crate_name)
  return util.resolve_package_dir(root, crate_name, nil, nil, nil, "%-")
end

---@return table|nil { root = string, packages = string[] }
function M.detect_stdlib()
  local sysroot = util.exec_command("rustc --print sysroot")
  if not sysroot then
    return nil
  end

  local stdlib_dir = sysroot .. "/lib/rustlib/src/rust/library"
  if not util.is_directory(stdlib_dir) then
    return nil
  end

  local cache_key = util.make_cache_key("rust_stdlib", stdlib_dir)
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
