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
  if not util.is_directory(node_modules) then
    return nil
  end

  -- Check cache first (node_modules can be huge)
  local cache_key = util.make_cache_key("javascript", node_modules)
  local cached = util.get_cache(cache_key)
  if cached then
    return { root = node_modules, packages = cached.packages }
  end

  -- Scan node_modules for packages, including scoped packages (@org/package)
  local packages = util.scan_packages_with_scope(node_modules, "^@", nil)

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
-- For now, stdlib detection is disabled for JavaScript/Node
---@return table|nil { root = string, packages = string[] }
function M.detect_stdlib()
  -- Not implemented - Node.js stdlib is built into the runtime
  -- Would need to either:
  -- 1. Find Node.js source installation (complex, varies by install method)
  -- 2. Use @types/node TypeScript definitions (if installed)
  -- 3. Clone/download Node.js source from GitHub
  return nil
end

return M
