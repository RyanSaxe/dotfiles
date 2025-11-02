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

-- Detect Python standard library modules
-- Scans the parent directory of site-packages for stdlib .py files
---@return table|nil { root = string, packages = string[] }
function M.detect_stdlib()
  local venv = vim.env.VIRTUAL_ENV
  if not venv or venv == "" then
    return nil
  end

  -- Find site-packages first
  local raw = vim.fn.glob(venv .. "/lib/python*/site-packages", false, false)
  local site_packages
  if raw ~= "" then
    site_packages = raw:match("([^\n]+)")
  else
    local tbl = vim.fn.globpath(venv, "**/site-packages", false, true)
    if type(tbl) == "table" and #tbl > 0 then
      site_packages = tbl[1]
    end
  end

  if not site_packages or site_packages == "" then
    return nil
  end

  -- Parent directory contains stdlib modules
  local stdlib_dir = vim.fn.fnamemodify(site_packages, ":h")
  local stat = util.safe_stat(stdlib_dir)
  if not stat or stat.type ~= "directory" then
    return nil
  end

  -- Check cache
  local cache_key = "python_stdlib:" .. stdlib_dir
  local cached = util.get_cache(cache_key)
  if cached then
    return { root = stdlib_dir, packages = cached.packages }
  end

  -- Scan for stdlib modules (both .py files and directories)
  local handle = util.safe_scandir(stdlib_dir)
  if not handle then
    return {}
  end

  local packages = {}
  local seen = {}

  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end

    -- Skip hidden, site-packages, and metadata
    if not name:match("^%.") and name ~= "site-packages" and not name:match("%.dist%-info$") then
      if type == "directory" then
        -- Directory modules (e.g., json/, email/)
        if not seen[name] then
          seen[name] = true
          table.insert(packages, name)
        end
      elseif type == "file" and name:match("%.py$") then
        -- Single-file modules (e.g., os.py, sys.py)
        local module_name = name:match("^(.+)%.py$")
        if module_name and not seen[module_name] then
          seen[module_name] = true
          table.insert(packages, module_name)
        end
      end
    end
  end

  if #packages > 0 then
    table.sort(packages)
    util.set_cache(cache_key, { packages = packages })
    return { root = stdlib_dir, packages = packages }
  end

  return nil
end

return M
