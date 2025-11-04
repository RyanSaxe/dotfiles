local util = require("dependency-picker.util")

local M = {}

---@param root string node_modules directory path
---@return string[] List of packages including scoped packages
local function scan_packages_with_scope(root)
  local handle = util.safe_scandir(root)
  if not handle then
    return {}
  end

  local packages = {}

  while true do
    local name, type = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end

    if type == "directory" and not name:match("^%.") then
      if name:match("^@") then
        local scope_path = root .. "/" .. name
        local scope_handle = util.safe_scandir(scope_path)
        if scope_handle then
          while true do
            local scope_pkg, scope_type = vim.uv.fs_scandir_next(scope_handle)
            if not scope_pkg then
              break
            end

            if scope_type == "directory" and not scope_pkg:match("^%.") then
              local full_name = name .. "/" .. scope_pkg
              table.insert(packages, full_name)
            end
          end
        end
      else
        table.insert(packages, name)
      end
    end
  end

  return packages
end

M.name = "JavaScript"
M.filetypes = { "javascript", "typescript", "javascriptreact", "typescriptreact", "json" }
M.requires_buffer_path = true

---@param buffer_path string Current buffer path
---@return table|nil { root = string, packages = string[] }
function M.detect(buffer_path)
  local project_root = util.find_marker_upward({ "package.json" }, vim.fn.fnamemodify(buffer_path, ":h"))
  if not project_root then
    return nil
  end

  local node_modules = project_root .. "/node_modules"
  if not util.is_directory(node_modules) then
    return nil
  end

  local cache_key = util.make_cache_key("javascript", node_modules)
  local cached = util.get_cache(cache_key)
  if cached then
    return { root = node_modules, packages = cached.packages }
  end

  local packages = scan_packages_with_scope(node_modules)
  if #packages > 0 then
    table.sort(packages)
    util.set_cache(cache_key, { packages = packages })
    return { root = node_modules, packages = packages }
  end

  return nil
end

-- Detect JavaScript/Node.js standard library (NOT IMPLEMENTED)
-- TODO: Implement Node.js stdlib support
-- Would require finding Node.js installation source or TypeScript definitions
---@return table|nil { root = string, packages = string[] }
function M.detect_stdlib()
  return nil
end

return M
