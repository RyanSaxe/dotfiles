-- Python detector
-- Detects packages in the active virtual environment's site-packages
-- Requires VIRTUAL_ENV environment variable to be set

local util = require("dependency-picker.util")

local M = {}

-- Language metadata
M.name = "Python"
M.filetypes = { "python" }
M.requires_buffer_path = false

-- Detect Python packages in the active virtual environment
-- Filters out metadata directories (dist-info, egg-info, __pycache__)
---@return table|nil { root = string, packages = string[] }
function M.detect()
  local venv = vim.env.VIRTUAL_ENV
  if not venv or venv == "" then
    return nil
  end

  -- Check cache first
  local cache_key = "python:" .. venv
  local cached = util.get_cache(cache_key)
  if cached then
    -- First item is root, rest are packages
    return { root = cached.packages[1], packages = vim.list_slice(cached.packages, 2) }
  end

  -- Find site-packages using fast glob first, fallback to recursive
  local raw = vim.fn.glob(venv .. "/lib/python*/site-packages", false, false)
  local site_packages
  if raw ~= "" then
    -- Pick first match from the string
    site_packages = raw:match("([^\n]+)")
  else
    -- Fallback: recursive search (slower but more reliable)
    local tbl = vim.fn.globpath(venv, "**/site-packages", false, true)
    if type(tbl) == "table" and #tbl > 0 then
      site_packages = tbl[1]
    end
  end

  if not site_packages or site_packages == "" then
    return nil
  end

  -- Scan site-packages for actual package directories
  -- Filter function excludes metadata and cache directories
  local filter = function(name)
    return not name:match("%.dist%-info$")
      and not name:match("%.egg%-info$")
      and name ~= "__pycache__"
  end

  local packages = util.scan_directories(site_packages, filter)

  if #packages > 0 then
    table.sort(packages)
    -- Store root as first element for cache
    util.set_cache(cache_key, { packages = { site_packages, unpack(packages) } })
    return { root = site_packages, packages = packages }
  end

  return nil
end

return M
