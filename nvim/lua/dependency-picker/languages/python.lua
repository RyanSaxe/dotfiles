-- Python detector
-- Detects packages in the active virtual environment's site-packages
-- Requires VIRTUAL_ENV environment variable to be set

local util = require("dependency-picker.util")

local M = {}

-- Language metadata
M.name = "Python"
M.filetypes = { "python" }
M.requires_buffer_path = false
-- File extension for single-file modules (e.g., os.py, sys.py)
-- Used to resolve both directory packages and single-file modules
M.file_extension = ".py"
-- Exclusion patterns for filtering out metadata directories when resolving paths
M.exclude_patterns = { "%.dist%-info$", "%.egg%-info$" }

-- Detect Python packages in the active virtual environment
-- Filters out metadata directories (dist-info, egg-info, __pycache__)
---@return table|nil { root = string, packages = string[] }
function M.detect()
  local venv = vim.env.VIRTUAL_ENV
  if not venv or venv == "" then
    return nil
  end

  -- Check cache first
  local cache_key = util.make_cache_key("python", venv)
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

-- Find the system Python's stdlib directory
-- Tries following symlinks first (fast), falls back to querying Python (reliable)
-- @param venv string The VIRTUAL_ENV path
-- @return string|nil The stdlib directory path (e.g., /usr/lib/python3.11/)
local function find_system_stdlib_dir(venv)
  -- Strategy 1: Follow symlinks from venv's python executable
  -- Most venvs use symlinks: venv/bin/python -> /usr/bin/python3.11
  local python_bin = venv .. "/bin/python"
  -- Use fs_lstat (not fs_stat) to detect if it's a symlink
  -- fs_stat follows symlinks, fs_lstat gives info about the link itself
  local ok, stat = pcall(vim.loop.fs_lstat, python_bin)

  if ok and stat and stat.type == "link" then
    -- Follow the symlink to find the real Python executable
    local real_python = vim.loop.fs_realpath(python_bin)
    if real_python then
      -- Real Python is typically at: /usr/bin/python3.11
      -- Stdlib is at: /usr/lib/python3.11/
      -- Extract version from executable name (e.g., python3.11 -> 3.11)
      local version = real_python:match("python(%d+%.%d+)")
      if version then
        -- Construct potential stdlib paths based on common installation patterns
        local python_base = vim.fn.fnamemodify(real_python, ":h:h") -- /usr/bin/python -> /usr
        local candidates = {
          python_base .. "/lib/python" .. version, -- Linux: /usr/lib/python3.11
          python_base .. "/lib64/python" .. version, -- Some Linux distros use lib64
        }

        -- Check each candidate to see if it exists and contains stdlib modules
        for _, candidate in ipairs(candidates) do
          if util.is_directory(candidate) then
            -- Verify it looks like a stdlib directory (should contain os.py or os/ directory)
            if util.exists(candidate .. "/os.py") or util.is_directory(candidate .. "/os") then
              return candidate
            end
          end
        end
      end
    end
  end

  -- Strategy 2: Query Python for its prefix
  -- This is more reliable but requires executing Python
  local python_exe = venv .. "/bin/python"
  local cmd = string.format('%s -c "import sys; print(sys.prefix)"', python_exe)
  local sys_prefix = util.exec_command(cmd)

  if sys_prefix then
    -- Find the lib/pythonX.Y directory under sys.prefix
    local lib_pattern = sys_prefix .. "/lib/python*"
    local raw = vim.fn.glob(lib_pattern, false, false)

    if raw ~= "" then
      local stdlib_dir = raw:match("([^\n]+)")
      if util.is_directory(stdlib_dir) then
        return stdlib_dir
      end
    end
  end

  return nil
end

-- Detect Python standard library modules
-- Finds the system Python installation and scans for stdlib .py files
---@return table|nil { root = string, packages = string[] }
function M.detect_stdlib()
  local venv = vim.env.VIRTUAL_ENV
  if not venv or venv == "" then
    return nil
  end

  -- Find the system Python's stdlib directory
  local stdlib_dir = find_system_stdlib_dir(venv)
  if not stdlib_dir then
    return nil
  end

  -- Check cache
  local cache_key = util.make_cache_key("python_stdlib", stdlib_dir)
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
