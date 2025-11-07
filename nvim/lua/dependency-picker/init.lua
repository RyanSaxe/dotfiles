-- Dependency Picker: Smart dependency navigation for multiple languages
-- Supports: Neovim, Lua, Python, JavaScript/TypeScript, Go, Rust, Ruby
--
-- Public API:
--   M.setup(opts)                - Configure behavior (see README.md)
--   M.smart_search(mode)         - Auto-detect and search (mode: "grep" or "files")
--   M.manual_search(mode)        - Manual selection (mode: "grep" or "files")
--   M.smart_search_stdlib(mode)  - Auto-detect stdlib search
--   M.manual_search_stdlib(mode) - Manual stdlib search

local util = require("dependency-picker.util")

local M = {}

local config = {
  enabled_languages = nil,
  select_detector = nil,
}

local function default_select_detector(matching_detectors, context)
  return matching_detectors[1]
end

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

---@param opts table Configuration options (see README.md)
---  - enabled_languages: string[]? Whitelist of languages (default: nil = all)
---  - select_detector: function? Custom detector selection logic
function M.setup(opts)
  opts = opts or {}

  if opts.enabled_languages then
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

---@param detector_list table[] List of detector modules
---@return table[] Filtered list of detectors
local function filter_enabled_detectors(detector_list)
  if not config.enabled_languages or #config.enabled_languages == 0 then
    return detector_list
  end

  local normalized_enabled = {}
  for _, lang in ipairs(config.enabled_languages) do
    table.insert(normalized_enabled, lang:lower())
  end

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

local function load_detectors()
  local languages_dir = vim.fn.stdpath("config") .. "/lua/dependency-picker/languages"
  local lang_files = vim.fn.glob(languages_dir .. "/*.lua", false, true)

  for _, file in ipairs(lang_files) do
    local lang_name = vim.fn.fnamemodify(file, ":t:r")
    local module_name = "dependency-picker.languages." .. lang_name

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

load_detectors()

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

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

    -- Single-file modules (e.g., os.py, base64.rb) are opened directly
    local is_directory = vim.fn.isdirectory(pkg_path) == 1
    if not is_directory then
      vim.cmd.edit(pkg_path)
      return
    end

    open_picker(mode, lang_name, selected_package, pkg_path)
  end)
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

---@param mode string "grep" or "files"
function M.smart_search(mode)
  mode = mode or "grep"

  local bufpath = vim.api.nvim_buf_get_name(0)
  local filetype = vim.bo.filetype

  local enabled_detectors = filter_enabled_detectors(detectors)

  -- Collect ALL matching detectors (handles ambiguous cases like lua files)
  local matching_detectors = {}

  for _, detector in ipairs(enabled_detectors) do
    if vim.tbl_contains(detector.filetypes, filetype) then
      local result = detector.requires_buffer_path and detector.detect(bufpath) or detector.detect()

      if result then
        table.insert(matching_detectors, {
          detector = detector,
          result = result,
        })
      end
    end
  end

  if #matching_detectors == 0 then
    vim.notify(
      string.format("No dependency detector available for filetype: %s", filetype),
      vim.log.levels.WARN,
      { title = "Dependency Picker" }
    )
    return
  end

  local select_fn = config.select_detector or default_select_detector
  local context = {
    bufpath = bufpath,
    filetype = filetype,
  }
  local selected_match = select_fn(matching_detectors, context)

  if not selected_match then
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

    local pkg_path = result.root .. "/" .. actual_dir
    open_picker(mode, detector.name, pkg_name, pkg_path)
    return
  end

  show_package_picker(detector.name, result.root, result.packages, mode, detector)
end

---@param mode string "grep" or "files"
function M.manual_search(mode)
  mode = mode or "grep"

  local bufpath = vim.api.nvim_buf_get_name(0)

  local enabled_detectors = filter_enabled_detectors(detectors)

  -- LAZY LOADING: Collect languages without calling detect() upfront
  local available = {}
  local detector_map = {}

  for _, detector in ipairs(enabled_detectors) do
    table.insert(available, detector.name)
    detector_map[detector.name] = detector
  end

  if #available == 0 then
    vim.notify("No language detectors available", vim.log.levels.WARN, { title = "Dependency Picker" })
    return
  end

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

    show_package_picker(detector.name, result.root, result.packages, mode, detector)
  end)
end

-- ============================================================================
-- STDLIB SEARCH API
-- ============================================================================

---@param mode string "grep" or "files"
function M.smart_search_stdlib(mode)
  mode = mode or "grep"

  local bufpath = vim.api.nvim_buf_get_name(0)
  local filetype = vim.bo.filetype

  local enabled_detectors = filter_enabled_detectors(detectors)

  local matching_detectors = {}

  for _, detector in ipairs(enabled_detectors) do
    if vim.tbl_contains(detector.filetypes, filetype) and detector.detect_stdlib then
      local result = detector.detect_stdlib()

      if result and #result.packages > 0 then
        table.insert(matching_detectors, {
          detector = detector,
          result = result,
        })
      end
    end
  end

  if #matching_detectors == 0 then
    vim.notify(
      string.format("No stdlib detector available for filetype: %s", filetype),
      vim.log.levels.WARN,
      { title = "Dependency Picker" }
    )
    return
  end

  local select_fn = config.select_detector or default_select_detector
  local context = {
    bufpath = bufpath,
    filetype = filetype,
  }
  local selected_match = select_fn(matching_detectors, context)

  if not selected_match then
    selected_match = matching_detectors[1]
  end

  local detector = selected_match.detector
  local result = selected_match.result

  show_package_picker(detector.name .. " stdlib", result.root, result.packages, mode, detector)
end

---@param mode string "grep" or "files"
function M.manual_search_stdlib(mode)
  mode = mode or "grep"

  local enabled_detectors = filter_enabled_detectors(detectors)

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
