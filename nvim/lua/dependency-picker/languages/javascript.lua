-- JavaScript/TypeScript detector
-- Detects local node_modules based on nearest package.json
-- Handles scoped packages (@org/package) and caches results

local util = require("dependency-picker.util")

local M = {}

-- Language metadata
M.name = "JavaScript"
-- Includes React/Vue/Svelte - they all use node_modules
M.filetypes = { "javascript", "typescript", "javascriptreact", "typescriptreact", "json" }
M.requires_buffer_path = true

-- Detect local node_modules packages
-- Requires buffer_path to find nearest package.json
---@param buffer_path string Current buffer path
---@return table|nil { root = string, packages = string[] }
function M.detect(buffer_path)
  -- Find nearest package.json by walking up the directory tree
  local project_root = util.find_marker_upward({ "package.json" }, vim.fn.fnamemodify(buffer_path, ":h"))
  if not project_root then
    return nil
  end

  local node_modules = project_root .. "/node_modules"
  local stat = util.safe_stat(node_modules)
  if not stat or stat.type ~= "directory" then
    return nil
  end

  -- Check cache first (node_modules can be huge)
  local cache_key = "javascript:" .. node_modules
  local cached = util.get_cache(cache_key)
  if cached then
    return { root = node_modules, packages = cached.packages }
  end

  -- Scan node_modules for packages
  local handle = util.safe_scandir(node_modules)
  if not handle then
    return nil
  end

  local packages = {}
  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end

    if type == "directory" then
      -- Handle scoped packages (@org/package)
      if name:match("^@") then
        local scope_path = node_modules .. "/" .. name
        local scope_handle = util.safe_scandir(scope_path)
        if scope_handle then
          while true do
            local scope_pkg, scope_type = vim.loop.fs_scandir_next(scope_handle)
            if not scope_pkg then
              break
            end
            if scope_type == "directory" and not scope_pkg:match("^%.") then
              table.insert(packages, name .. "/" .. scope_pkg)
            end
          end
        end
      elseif not name:match("^%.") then
        -- Regular package (not hidden)
        table.insert(packages, name)
      end
    end
  end

  if #packages > 0 then
    table.sort(packages)
    util.set_cache(cache_key, { packages = packages })
    return { root = node_modules, packages = packages }
  end

  return nil
end

return M
