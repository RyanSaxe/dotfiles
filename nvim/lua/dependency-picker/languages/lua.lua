-- Lua/Luarocks detector
-- Detects luarocks packages from local lua_modules or ~/.luarocks
-- Scans both share/lua and lib/lua directories

local util = require("dependency-picker.util")

local M = {}

-- Language metadata
-- Note: We exclude "vim" filetype here because Neovim detector already handles it
-- This is specifically for standalone Lua projects using Luarocks
M.name = "Lua"
M.filetypes = { "lua" }
M.requires_buffer_path = true

-- Find luarocks share/lib paths for a given base directory
-- Returns list of directories to scan for rocks
---@param base_path string Base luarocks path (e.g., ~/.luarocks or ./lua_modules)
---@return string[] List of paths to scan
local function get_rocks_paths(base_path)
  local paths = {}

  -- Try common Lua version patterns
  -- Examples: share/lua/5.1, share/lua/5.4, lib/lua/5.1, etc.
  local share_pattern = base_path .. "/share/lua/*"
  local lib_pattern = base_path .. "/lib/lua/*"

  -- Glob for share paths
  local share_glob = vim.fn.glob(share_pattern, false, true)
  if type(share_glob) == "table" then
    for _, path in ipairs(share_glob) do
      table.insert(paths, path)
    end
  end

  -- Glob for lib paths
  local lib_glob = vim.fn.glob(lib_pattern, false, true)
  if type(lib_glob) == "table" then
    for _, path in ipairs(lib_glob) do
      table.insert(paths, path)
    end
  end

  return paths
end

-- Scan multiple rock paths and collect unique package names
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

-- Detect Luarocks packages from local lua_modules or user .luarocks
---@param buffer_path string Current buffer path
---@return table|nil { root = string, packages = string[] }
function M.detect(buffer_path)
  local candidates = {}

  -- Check for local lua_modules first (project-specific)
  local project_root = util.find_marker_upward({ "lua_modules" }, vim.fn.fnamemodify(buffer_path, ":h"))
  if project_root then
    local lua_modules = project_root .. "/lua_modules"
    table.insert(candidates, { name = "local", path = lua_modules })
  end

  -- Check user luarocks directory
  local luarocks_home = vim.env.HOME .. "/.luarocks"
  table.insert(candidates, { name = "user", path = luarocks_home })

  -- Try each candidate
  for _, candidate in ipairs(candidates) do
    local stat = util.safe_stat(candidate.path)
    if stat and stat.type == "directory" then
      -- Check cache first
      local cache_key = "lua:" .. candidate.path
      local cached = util.get_cache(cache_key)
      if cached then
        return { root = candidate.path, packages = cached.packages }
      end

      -- Get all rock paths (share and lib directories)
      local rock_paths = get_rocks_paths(candidate.path)
      if #rock_paths > 0 then
        -- Scan all paths and deduplicate
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
