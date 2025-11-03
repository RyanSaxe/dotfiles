-- Dependency Picker: Smart dependency navigation for multiple languages
-- Supports: Neovim plugins, JavaScript/TypeScript, Python, Go, Rust, Ruby, Lua
--
-- Main features:
-- - Smart detection: auto-detects language and current package context
-- - Manual selection: choose language and package explicitly
-- - Dual modes: grep content or search files
--
-- Public API:
--   M.smart_search(mode)    - Auto-detect and search (mode: "grep" or "files")
--   M.manual_search(mode)   - Manual language/package selection (mode: "grep" or "files")

local util = require("dependency-picker.util")

local M = {}

-- ============================================================================
-- DETECTOR REGISTRY
-- Auto-loads all language detectors from languages/ directory
-- ============================================================================

local detectors = {}

-- Auto-load all language detectors
-- Each detector exports: { name, filetypes, detect, requires_buffer_path }
local function load_detectors()
  local languages_dir = vim.fn.stdpath("config") .. "/lua/dependency-picker/languages"
  local lang_files = vim.fn.glob(languages_dir .. "/*.lua", false, true)

  for _, file in ipairs(lang_files) do
    local lang_name = vim.fn.fnamemodify(file, ":t:r") -- Extract filename without extension
    local module_name = "dependency-picker.languages." .. lang_name

    -- Load the language detector module
    local ok, lang_module = pcall(require, module_name)
    if ok and lang_module then
      table.insert(detectors, lang_module)
    else
      vim.notify(
        string.format("Failed to load language detector: %s", lang_name),
        vim.log.levels.WARN,
        { title = "Dependency Picker" }
      )
    end
  end
end

-- Initialize detectors on module load
load_detectors()

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Show package picker and then grep or search files in selected package
---@param lang_name string Language name for display
---@param root string Root path of dependencies
---@param packages string[] List of package names
---@param mode string "grep" or "files"
---@param detector table|nil Optional language detector module (for versioning functions)
local function show_package_picker(lang_name, root, packages, mode, detector)
  if #packages == 0 then
    vim.notify("No packages found", vim.log.levels.WARN, { title = lang_name })
    return
  end

  require("snacks").picker.select(packages, {
    prompt = string.format("[%s] Select Package (%s)", lang_name, mode),
  }, function(selected_package)
    if not selected_package then
      return
    end

    -- Resolve the actual versioned directory name or single-file module
    -- Package names are displayed without versions (e.g., "rails", "serde")
    -- but actual directories include versions (e.g., "rails-7.0.0", "serde-1.0.0")
    -- Use language-specific resolution if available
    local resolve_fn = detector and detector.resolve_directory
    local file_extension = detector and detector.file_extension
    local actual_path = util.resolve_package_dir(root, selected_package, resolve_fn, file_extension)
    if not actual_path then
      vim.notify(
        string.format("Could not find directory or file for package: %s", selected_package),
        vim.log.levels.ERROR,
        { title = lang_name }
      )
      return
    end

    local pkg_path = root .. "/" .. actual_path

    -- Check if it's a file or directory
    -- For single-file modules (e.g., os.py, base64.rb), open directly in editor
    local is_directory = vim.fn.isdirectory(pkg_path) == 1
    if not is_directory then
      -- Single-file module: open directly
      vim.cmd.edit(pkg_path)
      return
    end

    if mode == "files" then
      -- File search mode
      require("snacks").picker.files({
        title = string.format("[%s] %s - Files", lang_name, selected_package),
        dirs = { pkg_path },
        hidden = true, -- Show hidden files
        ignored = true, -- Don't respect .gitignore
        follow = true, -- Follow symlinks (common in Python packages)
      })
    else
      -- Grep mode (default)
      require("snacks").picker.grep({
        title = string.format("[%s] %s - Grep", lang_name, selected_package),
        dirs = { pkg_path },
        ignored = true, -- Don't respect .gitignore
      })
    end
  end)
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Smart search: auto-detect language and current package context
-- If already inside a dependency, search it directly
-- Otherwise, show package picker for current language
---@param mode string "grep" or "files"
function M.smart_search(mode)
  mode = mode or "grep"

  local bufpath = vim.api.nvim_buf_get_name(0)
  local filetype = vim.bo.filetype

  -- Try each detector for current filetype
  for _, detector in ipairs(detectors) do
    -- Check if filetype matches
    if vim.tbl_contains(detector.filetypes, filetype) then
      -- Run detector
      local result = detector.requires_buffer_path and detector.detect(bufpath) or detector.detect()

      if result then
        -- Check if we're already inside a dependency
        -- Use language-specific version stripping if available
        local strip_fn = detector.strip_version
        local pkg_name = util.extract_package_name(bufpath, result.root, strip_fn)
        if pkg_name and vim.tbl_contains(result.packages, pkg_name) then
          -- Resolve the actual versioned directory name
          -- Use language-specific resolution if available
          local resolve_fn = detector.resolve_directory
          local actual_dir = util.resolve_package_dir(result.root, pkg_name, resolve_fn)
          if not actual_dir then
            vim.notify(
              string.format("Could not find directory for package: %s", pkg_name),
              vim.log.levels.ERROR,
              { title = detector.name }
            )
            return
          end

          -- Search directly in this package
          local pkg_path = result.root .. "/" .. actual_dir

          if mode == "files" then
            require("snacks").picker.files({
              title = string.format("[%s] %s - Files", detector.name, pkg_name),
              dirs = { pkg_path },
              hidden = true,
              ignored = true,
              follow = true,
            })
          else
            require("snacks").picker.grep({
              title = string.format("[%s] %s - Grep", detector.name, pkg_name),
              dirs = { pkg_path },
              ignored = true,
            })
          end
          return
        end

        -- Not inside a package, show picker
        show_package_picker(detector.name, result.root, result.packages, mode, detector)
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

-- Manual search: explicit language and package selection
-- Always shows language picker first, then package picker
---@param mode string "grep" or "files"
function M.manual_search(mode)
  mode = mode or "grep"

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
        detector = detector, -- Store detector for versioning functions
      }
    end
  end

  if #available == 0 then
    vim.notify("No dependencies detected for any language", vim.log.levels.WARN, { title = "Dependency Picker" })
    return
  end

  -- Show language picker
  require("snacks").picker.select(available, {
    prompt = string.format("Select Language (%s)", mode),
  }, function(selected_lang)
    if not selected_lang then
      return
    end

    local data = lang_data[selected_lang]
    show_package_picker(data.name, data.root, data.packages, mode, data.detector)
  end)
end

-- ============================================================================
-- STDLIB SEARCH API
-- Search standard library modules instead of project dependencies
-- ============================================================================

-- Smart stdlib search: auto-detect language and search stdlib
---@param mode string "grep" or "files"
function M.smart_search_stdlib(mode)
  mode = mode or "grep"

  local filetype = vim.bo.filetype

  -- Try each detector for current filetype
  for _, detector in ipairs(detectors) do
    if vim.tbl_contains(detector.filetypes, filetype) and detector.detect_stdlib then
      -- Run stdlib detector
      local result = detector.detect_stdlib()

      if result and #result.packages > 0 then
        show_package_picker(detector.name .. " stdlib", result.root, result.packages, mode, detector)
        return
      end
    end
  end

  -- No stdlib detector matched
  vim.notify(
    string.format("No stdlib detector available for filetype: %s", filetype),
    vim.log.levels.WARN,
    { title = "Dependency Picker" }
  )
end

-- Manual stdlib search: explicit language selection
---@param mode string "grep" or "files"
function M.manual_search_stdlib(mode)
  mode = mode or "grep"

  -- Collect available stdlib detectors with results
  local available = {}
  local lang_data = {}

  for _, detector in ipairs(detectors) do
    if detector.detect_stdlib then
      local result = detector.detect_stdlib()
      if result and #result.packages > 0 then
        local lang_display = string.format("%s stdlib (%d modules)", detector.name, #result.packages)
        table.insert(available, lang_display)
        lang_data[lang_display] = {
          name = detector.name .. " stdlib",
          root = result.root,
          packages = result.packages,
          detector = detector,
        }
      end
    end
  end

  if #available == 0 then
    vim.notify("No stdlib detected for any language", vim.log.levels.WARN, { title = "Dependency Picker" })
    return
  end

  -- Show language picker
  require("snacks").picker.select(available, {
    prompt = string.format("Select Stdlib (%s)", mode),
  }, function(selected_lang)
    if not selected_lang then
      return
    end

    local data = lang_data[selected_lang]
    show_package_picker(data.name, data.root, data.packages, mode, data.detector)
  end)
end

-- Backward compatibility: keep original function names
-- These just call the new unified smart_search function
function M.smart_grep()
  M.smart_search("grep")
end

function M.smart_files()
  M.smart_search("files")
end

-- Export for testing/debugging
M._detectors = detectors
M._util = util

return M
