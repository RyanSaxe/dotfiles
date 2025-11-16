local util = require("dependency-picker.util")

local M = {}

M.name = "Lua"
M.filetypes = { "lua" }
M.requires_buffer_path = true
M.file_extensions = { "lua" }

---@param base_path string Base luarocks path
---@return string[] List of paths to scan
local function get_rocks_paths(base_path)
  local paths = {}
  local share_glob = vim.fn.glob(base_path .. "/share/lua/*", false, true)
  if type(share_glob) == "table" then
    for _, path in ipairs(share_glob) do
      table.insert(paths, path)
    end
  end

  local lib_glob = vim.fn.glob(base_path .. "/lib/lua/*", false, true)
  if type(lib_glob) == "table" then
    for _, path in ipairs(lib_glob) do
      table.insert(paths, path)
    end
  end

  return paths
end

---@param rock_paths string[] List of paths to scan
---@return string[] Unique package names
local function scan_rocks(rock_paths)
  local seen = {}
  local packages = {}

  for _, rock_path in ipairs(rock_paths) do
    local rocks = util.scan_directories(rock_path)
    for _, rock in ipairs(rocks) do
      if not seen[rock] then
        seen[rock] = true
        table.insert(packages, rock)
      end
    end
  end

  return packages
end

---@return string[] List of luarocks tree root paths
local function get_luarocks_trees()
  local output = util.exec_command("luarocks config rocks_trees")
  if not output then
    return {}
  end

  local trees = {}
  for root in output:gmatch('root%s*=%s*"([^"]+)"') do
    table.insert(trees, root)
  end

  return trees
end

---@param buffer_path string Current buffer path
---@return table|nil { root = string, packages = string[] }
function M.detect(buffer_path)
  local candidates = {}

  local project_root = util.find_marker_upward({ "lua_modules" }, vim.fn.fnamemodify(buffer_path, ":h"))
  if project_root then
    local lua_modules = project_root .. "/lua_modules"
    table.insert(candidates, { name = "local", path = lua_modules })
  end

  local luarocks_trees = get_luarocks_trees()
  for _, tree_path in ipairs(luarocks_trees) do
    table.insert(candidates, { name = "luarocks", path = tree_path })
  end

  for _, candidate in ipairs(candidates) do
    if util.is_directory(candidate.path) then
      local cache_key = util.make_cache_key("lua", candidate.path)
      local cached = util.get_cache(cache_key)
      if cached then
        return { root = candidate.path, packages = cached.packages }
      end

      local rock_paths = get_rocks_paths(candidate.path)
      if #rock_paths > 0 then
        local packages = scan_rocks(rock_paths)
        if #packages > 0 then
          table.sort(packages)
          util.set_cache(cache_key, { packages = packages })
          return { root = candidate.path, packages = packages }
        end
      end
    end
  end

  return nil
end

return M
