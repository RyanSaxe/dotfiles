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

return M
