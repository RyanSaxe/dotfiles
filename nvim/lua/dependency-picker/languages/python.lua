local util = require("dependency-picker.util")

local M = {}

M.name = "Python"
M.filetypes = { "python" }
M.requires_buffer_path = false
M.file_extensions = { "py", "pyw", "pyi" } -- Python source, Windows Python, type stubs
M.exclude_patterns = { "%.dist%-info$", "%.egg%-info$" }

---@return table|nil { root = string, packages = string[] }
function M.detect()
  local venv = vim.env.VIRTUAL_ENV
  if not venv then
    return nil
  end

  local cache_key = util.make_cache_key("python", venv)
  local cached = util.get_cache(cache_key)
  if cached then
    return { root = cached.packages[1], packages = vim.list_slice(cached.packages, 2) }
  end

  local raw = vim.fn.glob(venv .. "/lib/python*/site-packages", false, false)
  local site_packages = raw ~= "" and raw:match("([^\n]+)")
    or (function()
      local tbl = vim.fn.globpath(venv, "**/site-packages", false, true)
      return type(tbl) == "table" and #tbl > 0 and tbl[1]
    end)()

  if not site_packages then
    return nil
  end

  local filter = function(name)
    return not name:match("%.dist%-info$") and not name:match("%.egg%-info$") and name ~= "__pycache__"
  end

  local packages = util.scan_directories(site_packages, filter)
  if #packages > 0 then
    table.sort(packages)
    util.set_cache(cache_key, { packages = { site_packages, unpack(packages) } })
    return { root = site_packages, packages = packages }
  end

  return nil
end

---@return table|nil { root = string, packages = string[] }
function M.detect_stdlib()
  local venv = vim.env.VIRTUAL_ENV
  if not venv then
    return nil
  end

  local python_exe = venv .. "/bin/python"
  local cmd = string.format('%s -c "import sys; print(sys.prefix)"', python_exe)
  local sys_prefix = util.exec_command(cmd)
  if not sys_prefix then
    return nil
  end

  local raw = vim.fn.glob(sys_prefix .. "/lib/python*", false, false)
  local stdlib_dir = raw ~= "" and raw:match("([^\n]+)")
  if not stdlib_dir or not util.is_directory(stdlib_dir) then
    return nil
  end

  local cache_key = util.make_cache_key("python_stdlib", stdlib_dir)
  local cached = util.get_cache(cache_key)
  if cached then
    return { root = stdlib_dir, packages = cached.packages }
  end

  local handle = util.safe_scandir(stdlib_dir)
  if not handle then
    return nil
  end

  local packages = {}
  local seen = {}

  while true do
    local name, type = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end

    if not name:match("^%.") and name ~= "site-packages" and not name:match("%.dist%-info$") then
      if type == "directory" then
        if not seen[name] then
          seen[name] = true
          table.insert(packages, name)
        end
      elseif type == "file" and name:match("%.py$") then
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
