local util = require("dependency-picker.util")

local M = {}

M.name = "Go"
M.filetypes = { "go" }
M.requires_buffer_path = true
M.file_extensions = { "go" }

---@param go_mod_path string Path to go.mod file
---@return string[] List of module paths
local function parse_go_mod(go_mod_path)
  local in_require_block = false
  return util.parse_config_file(go_mod_path, function(line)
    if line:match("^require%s*%(") then
      in_require_block = true
      return nil
    elseif in_require_block and line:match("^%)") then
      in_require_block = false
      return nil
    elseif line:match("^require%s+") then
      return line:match("^require%s+([%S]+)")
    elseif in_require_block then
      return line:match("^%s+([%S]+)")
    end
    return nil
  end)
end

---@return string|nil GOMODCACHE path
local function get_gomodcache()
  return util.exec_command("go env GOMODCACHE")
end

---@param buffer_path string Current buffer path
---@return table|nil { root = string, packages = string[] }
function M.detect(buffer_path)
  local project_root = util.find_marker_upward({ "go.mod" }, vim.fn.fnamemodify(buffer_path, ":h"))
  if not project_root then
    return nil
  end

  local go_mod = project_root .. "/go.mod"
  local cache_key = util.make_cache_key("go", go_mod)
  local cached = util.get_cache(cache_key)
  if cached then
    return { root = cached.packages[1], packages = vim.list_slice(cached.packages, 2) }
  end

  local modcache = get_gomodcache()
  if not modcache or not util.is_directory(modcache) then
    return nil
  end

  local modules = parse_go_mod(go_mod)
  if #modules > 0 then
    table.sort(modules)
    util.set_cache(cache_key, { packages = { modcache, unpack(modules) } })
    return { root = modcache, packages = modules }
  end

  return nil
end

---@param root string GOMODCACHE directory path
---@param module_name string Module name without version
---@return string|nil Full relative path with version, or nil if not found
function M.resolve_directory(root, module_name)
  return util.resolve_package_dir(root, module_name, nil, nil, nil, "@v")
end

---@return table|nil { root = string, packages = string[] }
function M.detect_stdlib()
  local goroot = util.exec_command("go env GOROOT")
  if not goroot then
    return nil
  end

  local stdlib_dir = goroot .. "/src"
  if not util.is_directory(stdlib_dir) then
    return nil
  end

  local cache_key = util.make_cache_key("go_stdlib", stdlib_dir)
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
