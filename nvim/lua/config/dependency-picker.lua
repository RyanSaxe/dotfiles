-- Generic dependency picker for multiple languages
-- Supports: Neovim plugins, JavaScript/Node.js, Python, Go, Rust

local M = {}

-- Cache for dependency roots and package lists
-- Structure: { [lang_name .. ":" .. root_path] = { packages = {...}, timestamp = ... } }
local cache = {}
local CACHE_TTL = 300 -- 5 minutes in seconds

---Utility: Find a file by searching upward from start_path
---@param markers string[] List of marker files to search for (e.g., {"package.json", "go.mod"})
---@param start_path string Starting directory path
---@return string|nil path The directory containing the first found marker, or nil
local function find_marker_upward(markers, start_path)
  local current = start_path
  local root = vim.loop.os_homedir() or "/"

  while current and current ~= root do
    for _, marker in ipairs(markers) do
      local marker_path = current .. "/" .. marker
      if vim.loop.fs_stat(marker_path) then
        return current
      end
    end

    -- Move up one directory
    local parent = vim.fn.fnamemodify(current, ":h")
    if parent == current then
      break
    end
    current = parent
  end

  return nil
end

---Utility: Check if a path is within another path
---@param path string The path to check
---@param parent string The potential parent path
---@return boolean
local function is_path_within(path, parent)
  if not path or not parent then
    return false
  end
  -- Normalize paths and check prefix
  local normalized_path = vim.fn.resolve(path)
  local normalized_parent = vim.fn.resolve(parent)
  return normalized_path:sub(1, #normalized_parent + 1) == normalized_parent .. "/"
end

---Utility: Extract package name from a path within a dependency root
---@param path string Full path to current file
---@param dep_root string Dependency root path (e.g., site-packages, node_modules)
---@return string|nil package_name First directory component after dep_root
local function extract_package_name(path, dep_root)
  if not is_path_within(path, dep_root) then
    return nil
  end

  local rel = path:sub(#dep_root + 2) -- Strip dep_root + "/"
  local pkg = rel:match("^([^/]+)")
  return pkg
end

---Utility: Get cached data or nil if expired/missing
---@param key string Cache key
---@return table|nil
local function get_cache(key)
  local cached = cache[key]
  if not cached then
    return nil
  end

  local age = os.time() - cached.timestamp
  if age > CACHE_TTL then
    cache[key] = nil
    return nil
  end

  return cached
end

---Utility: Set cached data with current timestamp
---@param key string Cache key
---@param data table Data to cache (must include 'packages' field)
local function set_cache(key, data)
  cache[key] = {
    packages = data.packages,
    timestamp = os.time(),
  }
end

-- ============================================================================
-- LANGUAGE DETECTORS
-- Each detector returns: { root = string, packages = string[] } or nil
-- ============================================================================

---Detector: Neovim plugins (lazy.nvim, packer.nvim, vim-plug)
---@return table|nil { root = string, packages = string[] }
local function detect_neovim()
  local data_path = vim.fn.stdpath("data")
  local candidates = {
    { name = "lazy.nvim", path = data_path .. "/lazy" },
    { name = "packer.nvim", path = data_path .. "/site/pack/packer/start" },
    { name = "vim-plug", path = data_path .. "/plugged" },
  }

  -- Find first existing plugin directory
  for _, candidate in ipairs(candidates) do
    local stat = vim.loop.fs_stat(candidate.path)
    if stat and stat.type == "directory" then
      -- Get list of plugins (directories only, no hidden files)
      local handle = vim.loop.fs_scandir(candidate.path)
      if not handle then
        goto continue
      end

      local packages = {}
      while true do
        local name, type = vim.loop.fs_scandir_next(handle)
        if not name then
          break
        end
        -- Include only directories, exclude hidden files/dirs
        if type == "directory" and not name:match("^%.") then
          table.insert(packages, name)
        end
      end

      if #packages > 0 then
        table.sort(packages)
        return { root = candidate.path, packages = packages }
      end
    end
    ::continue::
  end

  return nil
end

---Detector: JavaScript/TypeScript (local node_modules only)
---@param buffer_path string Current buffer path
---@return table|nil { root = string, packages = string[] }
local function detect_javascript(buffer_path)
  -- Find nearest package.json
  local project_root = find_marker_upward({ "package.json" }, vim.fn.fnamemodify(buffer_path, ":h"))
  if not project_root then
    return nil
  end

  local node_modules = project_root .. "/node_modules"
  local stat = vim.loop.fs_stat(node_modules)
  if not stat or stat.type ~= "directory" then
    return nil
  end

  -- Check cache first
  local cache_key = "javascript:" .. node_modules
  local cached = get_cache(cache_key)
  if cached then
    return { root = node_modules, packages = cached.packages }
  end

  -- Scan node_modules
  local handle = vim.loop.fs_scandir(node_modules)
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
        local scope_handle = vim.loop.fs_scandir(scope_path)
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
        -- Regular package
        table.insert(packages, name)
      end
    end
  end

  if #packages > 0 then
    table.sort(packages)
    set_cache(cache_key, { packages = packages })
    return { root = node_modules, packages = packages }
  end

  return nil
end

---Detector: Python (virtual environment site-packages)
---@return table|nil { root = string, packages = string[] }
local function detect_python()
  local venv = vim.env.VIRTUAL_ENV
  if not venv or venv == "" then
    return nil
  end

  -- Check cache first
  local cache_key = "python:" .. venv
  local cached = get_cache(cache_key)
  if cached then
    return { root = cached.packages[1], packages = vim.list_slice(cached.packages, 2) } -- First item is root
  end

  -- Find site-packages (fast glob first, fallback to recursive)
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

  -- Scan site-packages
  local handle = vim.loop.fs_scandir(site_packages)
  if not handle then
    return nil
  end

  local packages = {}
  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end

    -- Include only directories, exclude metadata and cache
    if
      type == "directory"
      and not name:match("^%.")
      and not name:match("%.dist%-info$")
      and not name:match("%.egg%-info$")
      and name ~= "__pycache__"
    then
      table.insert(packages, name)
    end
  end

  if #packages > 0 then
    table.sort(packages)
    -- Store root as first element for cache
    set_cache(cache_key, { packages = { site_packages, unpack(packages) } })
    return { root = site_packages, packages = packages }
  end

  return nil
end

---Detector: Go modules (GOMODCACHE)
---@return table|nil { root = string, packages = string[] }
local function detect_go()
  -- Get GOMODCACHE from environment
  local modcache = vim.fn.system("go env GOMODCACHE 2>/dev/null"):gsub("%s+", "")
  if modcache == "" or vim.v.shell_error ~= 0 then
    return nil
  end

  local stat = vim.loop.fs_stat(modcache)
  if not stat or stat.type ~= "directory" then
    return nil
  end

  -- Check cache
  local cache_key = "go:" .. modcache
  local cached = get_cache(cache_key)
  if cached then
    return { root = modcache, packages = cached.packages }
  end

  -- Collect top-level module paths (can be slow for large caches)
  -- We'll just scan one level deep to get domains (github.com, golang.org, etc.)
  local handle = vim.loop.fs_scandir(modcache)
  if not handle then
    return nil
  end

  local packages = {}
  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end
    if type == "directory" and not name:match("^%.") then
      -- Add domain-level entries (this is a simplified view)
      table.insert(packages, name)
    end
  end

  if #packages > 0 then
    table.sort(packages)
    set_cache(cache_key, { packages = packages })
    return { root = modcache, packages = packages }
  end

  return nil
end

---Detector: Rust (Cargo registry)
---@return table|nil { root = string, packages = string[] }
local function detect_rust()
  local cargo_home = vim.env.CARGO_HOME or (vim.env.HOME .. "/.cargo")
  local registry_src = cargo_home .. "/registry/src"

  local stat = vim.loop.fs_stat(registry_src)
  if not stat or stat.type ~= "directory" then
    return nil
  end

  -- Check cache
  local cache_key = "rust:" .. registry_src
  local cached = get_cache(cache_key)
  if cached then
    return { root = cached.packages[1], packages = vim.list_slice(cached.packages, 2) } -- First item is actual src path
  end

  -- Find the registry hash directory (usually only one)
  local handle = vim.loop.fs_scandir(registry_src)
  if not handle then
    return nil
  end

  local hash_dir
  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end
    if type == "directory" then
      hash_dir = registry_src .. "/" .. name
      break
    end
  end

  if not hash_dir then
    return nil
  end

  -- Scan crates in hash directory
  local crates_handle = vim.loop.fs_scandir(hash_dir)
  if not crates_handle then
    return nil
  end

  local packages = {}
  while true do
    local name, type = vim.loop.fs_scandir_next(crates_handle)
    if not name then
      break
    end
    -- Crate directories are named: cratename-version
    if type == "directory" and not name:match("^%.") then
      -- Extract just the crate name (strip version)
      local crate_name = name:match("^(.-)%-[%d%.]+")
      if crate_name and not vim.tbl_contains(packages, crate_name) then
        table.insert(packages, crate_name)
      end
    end
  end

  if #packages > 0 then
    table.sort(packages)
    -- Store hash_dir as first element
    set_cache(cache_key, { packages = { hash_dir, unpack(packages) } })
    return { root = hash_dir, packages = packages }
  end

  return nil
end

-- ============================================================================
-- DETECTOR REGISTRY
-- ============================================================================

-- Language detector registry
-- Each entry: { name, filetypes, detect_fn, requires_buffer_path }
local detectors = {
  {
    name = "Neovim",
    filetypes = { "lua", "vim" },
    detect = detect_neovim,
    requires_buffer_path = false,
  },
  {
    name = "JavaScript",
    filetypes = { "javascript", "typescript", "javascriptreact", "typescriptreact", "json" },
    detect = detect_javascript,
    requires_buffer_path = true,
  },
  {
    name = "Python",
    filetypes = { "python" },
    detect = detect_python,
    requires_buffer_path = false,
  },
  {
    name = "Go",
    filetypes = { "go" },
    detect = detect_go,
    requires_buffer_path = false,
  },
  {
    name = "Rust",
    filetypes = { "rust" },
    detect = detect_rust,
    requires_buffer_path = false,
  },
}

-- ============================================================================
-- MAIN LOGIC
-- ============================================================================

---Auto-detect language and grep dependencies (smart mode)
---If already inside a dependency, grep that package directly
---Otherwise, show package picker
function M.smart_grep()
  local bufpath = vim.api.nvim_buf_get_name(0)
  local filetype = vim.bo.filetype

  -- Try each detector
  for _, detector in ipairs(detectors) do
    -- Check if filetype matches
    local ft_match = vim.tbl_contains(detector.filetypes, filetype)
    if ft_match then
      -- Run detector
      local result = detector.requires_buffer_path and detector.detect(bufpath) or detector.detect()
      if result then
        -- Check if we're already inside a dependency
        local pkg_name = extract_package_name(bufpath, result.root)
        if pkg_name and vim.tbl_contains(result.packages, pkg_name) then
          -- Grep directly in this package
          local pkg_path = result.root .. "/" .. pkg_name
          require("snacks").picker.grep({
            title = string.format("[%s] %s - Grep", detector.name, pkg_name),
            dirs = { pkg_path },
            ignored = true,
          })
          return
        end

        -- Not inside a package, show picker
        M.show_package_picker(detector.name, result.root, result.packages)
        return
      end
    end
  end

  -- No detector matched
  vim.notify(
    string.format("No dependency detector available for filetype: %s", filetype),
    vim.log.levels.WARN,
    { title = "Dependency Picker" }
  )
end

---Auto-detect language and search files in dependencies (smart mode)
---If already inside a dependency, search files in that package directly
---Otherwise, show package picker
function M.smart_files()
  local bufpath = vim.api.nvim_buf_get_name(0)
  local filetype = vim.bo.filetype

  -- Try each detector
  for _, detector in ipairs(detectors) do
    -- Check if filetype matches
    local ft_match = vim.tbl_contains(detector.filetypes, filetype)
    if ft_match then
      -- Run detector
      local result = detector.requires_buffer_path and detector.detect(bufpath) or detector.detect()
      if result then
        -- Check if we're already inside a dependency
        local pkg_name = extract_package_name(bufpath, result.root)
        if pkg_name and vim.tbl_contains(result.packages, pkg_name) then
          -- Search files directly in this package
          local pkg_path = result.root .. "/" .. pkg_name
          require("snacks").picker.files({
            title = string.format("[%s] %s - Files", detector.name, pkg_name),
            dirs = { pkg_path }, -- Use dirs (like grep) instead of cwd
            hidden = true,
            follow = true, -- Follow symlinks (common in Python packages)
          })
          return
        end

        -- Not inside a package, show picker
        M.show_package_picker(detector.name, result.root, result.packages, "files")
        return
      end
    end
  end

  -- No detector matched
  vim.notify(
    string.format("No dependency detector available for filetype: %s", filetype),
    vim.log.levels.WARN,
    { title = "Dependency Picker" }
  )
end

---Show package picker and grep selected package
---@param lang_name string Language name for display
---@param root string Root path of dependencies
---@param packages string[] List of package names
---@param search_mode string "grep" or "files" (default: "grep")
function M.show_package_picker(lang_name, root, packages, search_mode)
  search_mode = search_mode or "grep"

  if #packages == 0 then
    vim.notify("No packages found", vim.log.levels.WARN, { title = lang_name })
    return
  end

  require("snacks").picker.select(packages, {
    prompt = string.format("[%s] Select Package (%s)", lang_name, search_mode),
  }, function(selected_package)
    if not selected_package then
      return
    end
    local pkg_path = root .. "/" .. selected_package

    if search_mode == "files" then
      -- File picker mode
      require("snacks").picker.files({
        title = string.format("[%s] %s - Files", lang_name, selected_package),
        cwd = pkg_path,
        hidden = true,
        follow = true, -- Follow symlinks (common in Python packages)
      })
    else
      -- Grep mode (default)
      require("snacks").picker.grep({
        title = string.format("[%s] %s - Grep", lang_name, selected_package),
        dirs = { pkg_path },
        ignored = true,
      })
    end
  end)
end

---Manual language selection mode
---Always shows language picker first, then package picker
---@param search_mode string "grep" or "files" (default: "grep")
function M.manual_grep(search_mode)
  search_mode = search_mode or "grep"
  local bufpath = vim.api.nvim_buf_get_name(0)

  -- Collect available detectors with results
  local available = {}
  local lang_data = {} -- Map language display string to data
  for _, detector in ipairs(detectors) do
    local result = detector.requires_buffer_path and detector.detect(bufpath) or detector.detect()
    if result and #result.packages > 0 then
      local lang_display = string.format("%s (%d packages)", detector.name, #result.packages)
      table.insert(available, lang_display)
      lang_data[lang_display] = {
        name = detector.name,
        root = result.root,
        packages = result.packages,
      }
    end
  end

  if #available == 0 then
    vim.notify("No dependencies detected for any language", vim.log.levels.WARN, { title = "Dependency Picker" })
    return
  end

  -- Show language picker
  require("snacks").picker.select(available, {
    prompt = string.format("Select Language (%s)", search_mode),
  }, function(selected_lang)
    if not selected_lang then
      return
    end
    local data = lang_data[selected_lang]
    M.show_package_picker(data.name, data.root, data.packages, search_mode)
  end)
end

return M
