-- Dependency Picker: Smart dependency navigation for multiple languages
-- Supports: Neovim plugins, JavaScript/TypeScript, Python, Go, Rust, Ruby, Lua
--
-- Main features:
-- - Smart detection: auto-detects language and current package context
-- - Multi-detector handling: when multiple package ecosystems match your filetype,
--   shows a picker to choose (e.g., Lua files can be Lua packages or Neovim plugins)
-- - Language filtering: configure which languages to enable/disable
-- - Manual selection: choose language and package explicitly
-- - Dual modes: grep content or search files
--
-- Public API:
--   M.setup(opts)           - Configure the dependency picker
--   M.smart_search(mode)    - Auto-detect and search (mode: "grep" or "files")
--   M.manual_search(mode)   - Manual language/package selection (mode: "grep" or "files")
--
-- Configuration Example:
--   Call M.setup() with options table to configure behavior:
--
--   require("dependency-picker").setup({
--     -- Optional: Whitelist specific languages (case-insensitive)
--     -- Available: "neovim", "lua", "python", "javascript", "go", "rust", "ruby"
--     -- Default: nil (all languages enabled)
--     enabled_languages = nil,
--
--     -- Optional: Custom function to select which detector to use when multiple match
--     -- Receives: matching_detectors (array of {detector, result}), context {bufpath, filetype}
--     -- Returns: selected match from matching_detectors array, or nil to use first match
--     -- Default: returns first match
--     select_detector = function(matching_detectors, context)
--       -- Example: prefer Neovim detector if "nvim" is in the file path
--       if context.bufpath:match("nvim") then
--         for _, match in ipairs(matching_detectors) do
--           if match.detector.name == "Neovim" then
--             return match
--           end
--         end
--       end
--       -- Default: return first match
--       return matching_detectors[1]
--     end
--   })
--
-- How Multi-Detector Resolution Works:
--   When you're in a lua file and press <leader>ps:
--   1. Both "Lua" and "Neovim" detectors match the lua filetype
--   2. The select_detector function is called to choose which one to use
--   3. Proceeds automatically with the selected detector (no picker shown)
--   4. Then the package picker appears for your selected ecosystem

local util = require("dependency-picker.util")

local M = {}

-- Configuration storage
-- Defaults:
--   - All languages enabled (nil = no filtering)
--   - First matching detector is selected when multiple match
local config = {
  enabled_languages = nil,  -- nil = all enabled, or array like { "neovim", "lua", "python" }
  select_detector = nil,    -- nil = use default (first match), or custom function
}

-- Default detector selection logic: returns the first matching detector
local function default_select_detector(matching_detectors, context)
  return matching_detectors[1]
end

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

-- Setup function to configure dependency picker behavior
-- @param opts table Configuration options:
--   - enabled_languages: Array of language names to enable (whitelist)
--                        Example: { "neovim", "lua", "python" }
--                        Default: nil (all languages enabled)
--   - select_detector: Function to select which detector to use when multiple match
--                      Signature: function(matching_detectors, context) -> selected_match
--                      Parameters:
--                        - matching_detectors: array of { detector = detector_module, result = detect_result }
--                        - context: { bufpath = string, filetype = string }
--                      Returns: selected match from matching_detectors array
--                      Default: returns first match
function M.setup(opts)
  opts = opts or {}

  if opts.enabled_languages then
    -- Validate that it's a table
    if type(opts.enabled_languages) ~= "table" then
      vim.notify(
        "enabled_languages must be a table/array",
        vim.log.levels.ERROR,
        { title = "Dependency Picker" }
      )
      return
    end
    config.enabled_languages = opts.enabled_languages
  end

  if opts.select_detector then
    -- Validate that it's a function
    if type(opts.select_detector) ~= "function" then
      vim.notify(
        "select_detector must be a function",
        vim.log.levels.ERROR,
        { title = "Dependency Picker" }
      )
      return
    end
    config.select_detector = opts.select_detector
  end
end

-- Filter detectors based on enabled_languages config
-- Returns a new list containing only enabled detectors
-- Performs case-insensitive matching
-- @param detector_list table List of detector modules
-- @return table Filtered list of detectors
local function filter_enabled_detectors(detector_list)
  -- If no whitelist configured, return all detectors
  if not config.enabled_languages or #config.enabled_languages == 0 then
    return detector_list
  end

  -- Normalize enabled_languages to lowercase for case-insensitive matching
  local normalized_enabled = {}
  for _, lang in ipairs(config.enabled_languages) do
    table.insert(normalized_enabled, lang:lower())
  end

  -- Filter based on whitelist (case-insensitive)
  local filtered = {}
  for _, detector in ipairs(detector_list) do
    if vim.tbl_contains(normalized_enabled, detector.name:lower()) then
      table.insert(filtered, detector)
    end
  end

  return filtered
end

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Open a picker (files or grep) for the given package
---@param mode string "files" or "grep"
---@param lang_name string Language/detector name
---@param pkg_name string Package name
---@param pkg_path string Path to the package directory
local function open_picker(mode, lang_name, pkg_name, pkg_path)
  if mode == "files" then
    require("snacks").picker.files({
      title = string.format("[%s] %s - Files", lang_name, pkg_name),
      dirs = { pkg_path },
      hidden = true,
      ignored = true,
      follow = true,
    })
  else
    require("snacks").picker.grep({
      title = string.format("[%s] %s - Grep", lang_name, pkg_name),
      dirs = { pkg_path },
      ignored = true,
    })
  end
end

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

    -- Basic validation
    if not selected_package or selected_package == "" then
      vim.notify("Invalid package name", vim.log.levels.ERROR, { title = lang_name })
      return
    end

    -- Resolve the actual versioned directory name or single-file module
    -- Package names are displayed without versions (e.g., "rails", "serde")
    -- but actual directories include versions (e.g., "rails-7.0.0", "serde-1.0.0")
    -- Use language-specific resolution if available
    local resolve_fn = detector and detector.resolve_directory
    local file_extension = detector and detector.file_extension
    local exclude_patterns = detector and detector.exclude_patterns
    local actual_path = util.resolve_package_dir(root, selected_package, resolve_fn, file_extension, exclude_patterns)
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

    open_picker(mode, lang_name, selected_package, pkg_path)
  end)
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Smart search: auto-detect language and current package context
-- If already inside a dependency, search it directly
-- Otherwise, show package picker for current language
-- When multiple detectors match the filetype, shows a picker to choose
---@param mode string "grep" or "files"
function M.smart_search(mode)
  mode = mode or "grep"

  local bufpath = vim.api.nvim_buf_get_name(0)
  local filetype = vim.bo.filetype

  -- Filter detectors based on enabled_languages configuration
  local enabled_detectors = filter_enabled_detectors(detectors)

  -- Collect ALL matching detectors for this filetype
  -- This allows us to handle ambiguous cases (e.g., lua files could be Lua or Neovim packages)
  local matching_detectors = {}

  for _, detector in ipairs(enabled_detectors) do
    -- Check if filetype matches
    if vim.tbl_contains(detector.filetypes, filetype) then
      -- Run detector to see if packages are available
      local result = detector.requires_buffer_path and detector.detect(bufpath) or detector.detect()

      if result then
        table.insert(matching_detectors, {
          detector = detector,
          result = result,
        })
      end
    end
  end

  -- Handle results based on number of matches
  if #matching_detectors == 0 then
    -- No detector matched
    vim.notify(
      string.format("No dependency detector available for filetype: %s", filetype),
      vim.log.levels.WARN,
      { title = "Dependency Picker" }
    )
    return
  end

  -- Select which detector to use (using configured selection logic or default)
  local select_fn = config.select_detector or default_select_detector
  local context = {
    bufpath = bufpath,
    filetype = filetype,
  }
  local selected_match = select_fn(matching_detectors, context)

  if not selected_match then
    -- Selection function returned nil, use first match as fallback
    selected_match = matching_detectors[1]
  end

  local detector = selected_match.detector
  local result = selected_match.result

  -- Check if we're already inside a dependency
  local strip_fn = detector.strip_version
  local pkg_name = util.extract_package_name(bufpath, result.root, strip_fn)
  if pkg_name and vim.tbl_contains(result.packages, pkg_name) then
    -- Resolve the actual versioned directory name
    local resolve_fn = detector.resolve_directory
    local exclude_patterns = detector.exclude_patterns
    local actual_dir = util.resolve_package_dir(result.root, pkg_name, resolve_fn, nil, exclude_patterns)
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
    open_picker(mode, detector.name, pkg_name, pkg_path)
    return
  end

  -- Not inside a package, show package picker
  show_package_picker(detector.name, result.root, result.packages, mode, detector)
end

-- Manual search: explicit language and package selection
-- Always shows language picker first, then package picker
---@param mode string "grep" or "files"
function M.manual_search(mode)
  mode = mode or "grep"

  local bufpath = vim.api.nvim_buf_get_name(0)

  -- Filter detectors based on enabled_languages configuration
  local enabled_detectors = filter_enabled_detectors(detectors)

  -- LAZY LOADING: Collect all available languages without calling detect()
  -- This avoids the performance penalty of calling all detect() functions upfront
  local available = {}
  local detector_map = {} -- Map language name to detector

  for _, detector in ipairs(enabled_detectors) do
    table.insert(available, detector.name)
    detector_map[detector.name] = detector
  end

  if #available == 0 then
    vim.notify("No language detectors available", vim.log.levels.WARN, { title = "Dependency Picker" })
    return
  end

  -- Show language picker immediately (no detect() calls yet)
  require("snacks").picker.select(available, {
    prompt = string.format("Select Language (%s)", mode),
  }, function(selected_lang)
    if not selected_lang then
      return
    end

    local detector = detector_map[selected_lang]
    if not detector then
      vim.notify("Language detector not found", vim.log.levels.ERROR)
      return
    end

    -- NOW call detect() only for the selected language
    local result = detector.requires_buffer_path and detector.detect(bufpath) or detector.detect()

    if not result or #result.packages == 0 then
      vim.notify(
        string.format("No %s packages detected", detector.name),
        vim.log.levels.WARN,
        { title = "Dependency Picker" }
      )
      return
    end

    -- Show package picker with the detected packages
    show_package_picker(detector.name, result.root, result.packages, mode, detector)
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

  local bufpath = vim.api.nvim_buf_get_name(0)
  local filetype = vim.bo.filetype

  -- Filter detectors based on enabled_languages configuration
  local enabled_detectors = filter_enabled_detectors(detectors)

  -- Collect ALL matching stdlib detectors for this filetype
  local matching_detectors = {}

  for _, detector in ipairs(enabled_detectors) do
    if vim.tbl_contains(detector.filetypes, filetype) and detector.detect_stdlib then
      -- Run stdlib detector
      local result = detector.detect_stdlib()

      if result and #result.packages > 0 then
        table.insert(matching_detectors, {
          detector = detector,
          result = result,
        })
      end
    end
  end

  -- Handle results based on number of matches
  if #matching_detectors == 0 then
    -- No stdlib detector matched
    vim.notify(
      string.format("No stdlib detector available for filetype: %s", filetype),
      vim.log.levels.WARN,
      { title = "Dependency Picker" }
    )
    return
  end

  -- Select which detector to use (using configured selection logic or default)
  local select_fn = config.select_detector or default_select_detector
  local context = {
    bufpath = bufpath,
    filetype = filetype,
  }
  local selected_match = select_fn(matching_detectors, context)

  if not selected_match then
    -- Selection function returned nil, use first match as fallback
    selected_match = matching_detectors[1]
  end

  local detector = selected_match.detector
  local result = selected_match.result

  show_package_picker(detector.name .. " stdlib", result.root, result.packages, mode, detector)
end

-- Manual stdlib search: explicit language selection
---@param mode string "grep" or "files"
function M.manual_search_stdlib(mode)
  mode = mode or "grep"

  -- Filter detectors based on enabled_languages configuration
  local enabled_detectors = filter_enabled_detectors(detectors)

  -- Collect available stdlib detectors with results
  local available = {}
  local lang_data = {}

  for _, detector in ipairs(enabled_detectors) do
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
