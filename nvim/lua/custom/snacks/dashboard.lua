-- dashboard.lua  ── custom git dashboard configuration for Snacks.nvim
-- Contains all dashboard sections, keys, and layout logic

local utils = require("custom.snacks.utils")
local git_pickers = require("custom.git.pickers")
local git_utils = require("custom.git.utils")
local visual_utils = require("custom.visual.utils")

local M = {}

-- ══════════════════════════════════════════════════════════════════════════════
-- CONFIGURATION
-- Configure your dashboard appearance here. Changes require restarting Neovim.
-- ══════════════════════════════════════════════════════════════════════════════

local CONFIG = {
  -- Pokemon display configuration
  pokemon = {
    -- Set to nil to select a random pokemon from the database
    -- Otherwise, specify a pokemon name like "pikachu", "snorlax", "ho-oh", etc.
    name = "pichu",

    -- Set to true for shiny variant
    is_shiny = false,

    -- Optional form (e.g., "alola", "galar", "mega-x"), set to nil if not applicable
    form = nil,

    -- Force small sprite size (don't add -b flag even if sprite is small)
    -- This is useful if you prefer the smaller sprite aesthetic
    force_small = true,

    -- Position within the pokemon section: "top-left", "middle-middle", "bottom-right", etc.
    -- Valid positions: top-left, top-middle, top-right,
    --                  middle-left, middle-middle, middle-right,
    --                  bottom-left, bottom-middle, bottom-right
    -- Default: "middle-middle"
    position = "bottom-right",
  },

  -- Color generation configuration (for testing algorithm changes)
  generation = {
    -- Force regeneration of pokemon colors even if they exist in database
    -- Set to true when testing algorithm changes or new threshold values
    -- WARNING: This will regenerate colors on every dashboard open!
    force_regenerate = false,

    -- Colorfulness threshold for prominent color selection (default: 500, previous: 2000)
    -- Lower values favor frequency over saturation (more muted but common colors)
    -- Higher values favor vivid colors over frequency (more saturated but rare colors)
    -- Examples: 500 (balanced), 800 (moderately vivid), 1500 (very vivid), 2000 (original - very strict)
    colorfulness_threshold = 500,
  },

  -- Color theme configuration
  colors = {
    -- Background mode: "auto" (uses vim.o.background), "dark", or "light"
    -- Controls which color palette to use from pokemon color data
    background_mode = "dark",

    -- Color source overrides (applied to SnacksDashboard highlight groups)
    -- Each can be: 'auto' (from sprite), a highlight group name (e.g., 'Comment', 'Normal'), or a hex color (e.g., '#FF5733')
    -- Note: Highlight group names are case-sensitive!

    -- Title color (maps to prominent color from sprite, used for SnacksDashboardTitle)
    title_source = "auto",

    -- Key color (maps to bright color from sprite, used for SnacksDashboardKey)
    key_source = "auto",

    -- Description color (maps to dim color from sprite, used for SnacksDashboardDesc)
    desc_source = "auto",

    -- Color adjustments using tokyonight.util functions
    -- Applied after resolving the base color from source

    -- Brighten adjustments: {lightness_amount, saturation_amount}
    -- lightness_amount: increases lightness (default if omitted: 0.05)
    -- saturation_amount: increases saturation/vividness (default if omitted: 0.2)
    title_brighten = nil, -- e.g., {0.1, 0.3} to make prominent more vibrant
    key_brighten = nil, -- e.g., {0.05, 0.15} to boost key saturation
    desc_brighten = nil, -- e.g., {0, 0.1} to increase saturation only

    -- Dim adjustments: number (0-1)
    -- Blends color with background (0 = no change, 1 = full background color)
    title_dim = nil, -- e.g., 0.2 to dim prominent slightly
    key_dim = nil, -- e.g., 0.15 to reduce key contrast
    desc_dim = nil, -- e.g., 0.3 to make descriptions more subtle
  },
}

-- Calculate pokemon selection and colors (only done once at startup)
-- This ensures the pokemon doesn't change on dashboard redraws
local pokemon_name, pokemon_shiny, pokemon_form, pokemon_colors, color_sources, force_regenerate_active

-- Only calculate if we would show a pokemon (has two panes)
if utils.show_if_has_second_pane() then
  if CONFIG.pokemon.name == nil then
    -- Random selection from database
    pokemon_name, pokemon_shiny, pokemon_form = visual_utils.select_random_pokemon()
  else
    -- Use configured pokemon
    pokemon_name = CONFIG.pokemon.name
    pokemon_shiny = CONFIG.pokemon.is_shiny
    pokemon_form = CONFIG.pokemon.form
  end

  -- Build color sources config to pass through to generation
  -- This ensures regenerated colors use the same configuration
  color_sources = {
    title_source = CONFIG.colors.title_source,
    key_source = CONFIG.colors.key_source,
    desc_source = CONFIG.colors.desc_source,
    title_brighten = CONFIG.colors.title_brighten,
    key_brighten = CONFIG.colors.key_brighten,
    desc_brighten = CONFIG.colors.desc_brighten,
    title_dim = CONFIG.colors.title_dim,
    key_dim = CONFIG.colors.key_dim,
    desc_dim = CONFIG.colors.desc_dim,
  }

  -- Load color data for the selected pokemon
  -- This will auto-generate if not in database (async)
  pokemon_colors = visual_utils.ensure_pokemon_colors(
    pokemon_name,
    pokemon_shiny,
    pokemon_form,
    function()
      -- Callback: when generation completes, update the dashboard
      if Snacks and Snacks.dashboard and Snacks.dashboard.update then
        Snacks.dashboard.update()
      end
    end,
    CONFIG.colors.background_mode,
    CONFIG.generation, -- Pass generation config (force_regenerate, colorfulness_threshold)
    color_sources -- Pass color sources config for consistent application after generation
  )

  -- Track if force_regenerate is active to ensure colors are reloaded on every dashboard render
  -- This prevents stale cached colors from being re-applied after async regeneration completes
  force_regenerate_active = CONFIG.generation.force_regenerate

  if pokemon_colors then
    -- Apply colors to Snacks dashboard highlight groups
    -- Pass background_mode configuration, color source overrides, and adjustments
    visual_utils.apply_dashboard_colors(pokemon_colors, CONFIG.colors.background_mode, color_sources)
  end
end

-- Check if we should show recent project toggle based on context
local function recent_project_toggle()
  local in_git = Snacks.git.get_root() ~= nil
  local has_two_panes = utils.show_if_has_second_pane()
  -- if in git and has one pane, then we disable
  return not (in_git and not has_two_panes)
end

---Validate and normalize position string
---@param position string|nil Position string to validate
---@return string normalized Valid position string
local function validate_position(position)
  local valid_positions = {
    "top-left",
    "top-middle",
    "top-right",
    "middle-left",
    "middle-middle",
    "middle-right",
    "bottom-left",
    "bottom-middle",
    "bottom-right",
  }

  -- Default position
  if not position or position == "" then
    return "middle-middle"
  end

  -- Check if valid
  if vim.tbl_contains(valid_positions, position) then
    return position
  end

  -- Invalid, use default and warn
  vim.notify(string.format("Invalid pokemon position '%s', using 'middle-middle'", position), vim.log.levels.WARN)
  return "middle-middle"
end

-- Create search keys section for project operations
-- Returns sections and total height
---@return table sections Array of section configs
---@return number height Total height of this section
local function search_keys()
  local cwd = vim.fn.getcwd()
  local project = vim.fn.fnamemodify(cwd, ":t")
  local header = { pane = 1, title = utils.create_aligned_title("Project", project) }

  local keys = {
    { key = "/", desc = "Grep Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
    {
      desc = "Search Code TODOs",
      key = "x",
      action = function()
        Snacks.picker.todo_comments({ keywords = { "TODO", "FIX", "FIXME", "HACK", "BUG" } })
      end,
    },
    {
      desc = "Grep Dependencies",
      key = "s",
      action = function()
        -- TODO: this currently only works with python projects ... generalize to other languages
        vim.cmd("GrepVenvSelectPackage")
      end,
    },
    {
      desc = "Open TODO List",
      key = "t",
      action = function()
        Snacks.scratch.open({
          name = "TODO", -- this name makes it such that checkmate.nvim runs on this.
          ft = "markdown",
        })
      end,
    },
  }

  local find_file_base = { key = "f", desc = "Find File" }
  table.insert(
    keys,
    utils.different_key_if_condition(
      Snacks.git.get_root() ~= nil,
      find_file_base,
      { action = ":lua Snacks.dashboard.pick('git_files')" },
      { action = ":lua Snacks.dashboard.pick('files')" }
    )
  )

  return utils.create_pane(header, keys, 2)
end

-- Create global keys section for neovim operations
-- Returns sections and total height
---@return table sections Array of section configs
---@return number height Total height of this section
local function globalkeys()
  -- NOTE: consider the projects section that only shows up if not in a git repo
  local header = {
    pane = 1,
    title = utils.create_aligned_title(
      "Neovim",
      "v" .. vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch
    ),
  }
  local keys = {
    { key = "q", desc = "Quit", action = ":qa" },
    {
      key = "p",
      desc = "Find Project",
      action = function()
        return Snacks.picker.projects({
          confirm = function(picker, item)
            picker:close()
            vim.api.nvim_set_current_dir(item.file)
            Snacks.dashboard.update()
          end,
        })
      end,
    },
    {
      key = "l",
      desc = "Manage Lua Plugins",
      action = ":Lazy",
      enabled = package.loaded.lazy ~= nil,
    },
    { key = "r", desc = "Restore Session", section = "session" },
    {
      key = "c",
      desc = "Search Neovim Config",
      action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})",
    },
  }

  return utils.create_pane(header, keys, 2)
end

-- Get recent files for the dashboard
-- Returns sections and total height
---@return table sections Array of section configs
---@return number height Total height of this section
local function get_recent_files()
  local out = {}
  local max_files = 5
  local recent_files = utils.recent_files_in_cwd(max_files)
  local n_files = #recent_files
  local pane = Snacks.git.get_root() and 2 or 1
  local final_padding = 2 -- Standard padding at the end

  for i, rel in ipairs(recent_files) do
    out[#out + 1] = {
      pane = pane,
      indent = 0,
      padding = (i == n_files) and final_padding or 0,
      desc = utils.normalize_path(rel),
      key = tostring(i),
      action = function()
        vim.cmd("edit " .. rel)
      end,
      enabled = recent_project_toggle,
    }
  end
  if #out == 0 then
    out[1] = {
      pane = pane,
      indent = 0,
      padding = final_padding,
      enabled = recent_project_toggle,
    }
  end

  -- Calculate height: files + final_padding
  -- Note: The "Recent Files" title is added separately in create_sections()
  -- If files exist: n_files + final_padding
  -- If no files: 1 (empty entry) + final_padding
  local entries_height = n_files > 0 and n_files or 1
  local height = entries_height + final_padding

  return out, height
end

---Calculate horizontal positioning for sprite
---@param sprite_width number Width of sprite in characters
---@param pane_width number Total available width in pane
---@param position string Position string (e.g., "top-middle", "middle-left")
---@return number indent Spaces to indent from left edge
local function calculate_horizontal_position(sprite_width, pane_width, position)
  -- Extract horizontal component from position string
  local horizontal = position:match("-(.+)$")

  -- Validate position
  if not horizontal or not vim.tbl_contains({ "left", "middle", "right" }, horizontal) then
    vim.notify(string.format("Invalid position '%s', using middle", position), vim.log.levels.WARN)
    horizontal = "middle"
  end

  local indent = 0

  if horizontal == "left" then
    -- Small indent from left edge for margin
    indent = 2
  elseif horizontal == "middle" then
    -- Center horizontally
    local available_space = pane_width - sprite_width
    indent = math.floor(available_space / 2)
  elseif horizontal == "right" then
    -- Align to right edge with small margin
    local available_space = pane_width - sprite_width
    indent = available_space - 2 -- -2 for small margin
  end

  -- Ensure indent is non-negative
  indent = math.max(0, indent)

  -- Handle overflow: if sprite is wider than pane, just left-align
  if sprite_width > pane_width then
    vim.notify(
      string.format("Pokemon sprite (width %d) is wider than pane (width %d), left-aligning", sprite_width, pane_width),
      vim.log.levels.WARN
    )
    indent = 0
  end

  return indent
end

---Calculate vertical positioning for sprite within fixed-height section
---@param sprite_height number Height of sprite in lines
---@param section_height number Total height of pokemon section (fixed, matches pane 1)
---@param position string Position string (e.g., "top-middle", "middle-left")
---@return number padding_top Lines of padding before sprite
---@return number padding_bottom Lines of padding after sprite
local function calculate_vertical_position(sprite_height, section_height, position)
  -- Extract vertical component from position string
  local vertical = position:match("^([^-]+)")

  -- Validate position
  if not vertical or not vim.tbl_contains({ "top", "middle", "bottom" }, vertical) then
    vim.notify(string.format("Invalid position '%s', using middle", position), vim.log.levels.WARN)
    vertical = "middle"
  end

  -- Calculate available space around sprite
  local available_space = section_height - sprite_height

  -- Handle overflow: if sprite is taller than section, allocate all to sprite
  if available_space < 0 then
    vim.notify(
      string.format(
        "Pokemon sprite (height %d) is taller than section (height %d), no padding",
        sprite_height,
        section_height
      ),
      vim.log.levels.WARN
    )
    return 0, 0
  end

  local padding_top = 0
  local padding_bottom = 0

  if vertical == "top" then
    -- No padding at top, all padding at bottom
    padding_top = 0
    padding_bottom = available_space
  elseif vertical == "middle" then
    -- Center vertically, split padding evenly
    padding_top = math.floor(available_space / 2)
    padding_bottom = available_space - padding_top
  elseif vertical == "bottom" then
    -- All padding at top, no padding at bottom
    padding_top = available_space
    padding_bottom = 0
  end

  return padding_top, padding_bottom
end

-- Create git sections for git operations
-- Returns sections and total height (returns 0 height if not in git repo)
---@param base_branch string Base branch name
---@param current_branch string Current branch name
---@return table sections Array of git section configs
---@return number height Total height of git sections (0 if not in git)
local function create_git_sections(base_branch, current_branch)
  local in_git = Snacks.git.get_root() ~= nil

  -- If not in git repo, return empty sections with 0 height
  if not in_git then
    return {}, 0
  end

  local sections = {
    {
      pane = 1,
      title = utils.create_aligned_title("Git", current_branch),
      indent = 0,
      padding = 2,
      enabled = in_git,
    },
    {
      pane = 1,
      desc = "Checkout Another Branch",
      key = "b",
      action = function()
        Snacks.picker.git_branches({
          all = true,
          confirm = function(picker, item)
            picker:close()
            git_utils.checkout_branch(item.branch)
            Snacks.dashboard.update()
          end,
        })
      end,
      enabled = in_git,
      indent = 0,
    },
    {
      pane = 1,
      desc = string.format("Search Diff vs %s", base_branch),
      key = "d",
      indent = 0,
      action = function()
        git_pickers.diff_picker(base_branch)
      end,
      enabled = in_git,
    },
    {
      pane = 1,
      indent = 0,
      desc = "Search Un-Commited Changes",
      key = "u",
      action = function()
        Snacks.picker.git_status()
      end,
      enabled = in_git,
    },
    {
      pane = 1,
      desc = "Open LazyGit UI",
      key = "g",
      indent = 0,
      action = function()
        Snacks.lazygit({ cwd = LazyVim.root.git() })
      end,
      padding = 1,
      enabled = in_git,
    },
    {
      pane = 1,
      indent = 0,
      -- 60 ticks is exactly the size of a line (width 60, indent = 0)
      title = "------------------------------------------------------------",
      padding = 1,
      enabled = in_git,
    },
    {
      pane = 1,
      desc = "Search Recent Notifications",
      key = "N",
      indent = 0,
      action = function()
        vim.notify("Fetching Notifications from GitHub...")
        vim.defer_fn(git_pickers.notification_picker, 100)
      end,
      enabled = in_git,
    },
    {
      pane = 1,
      desc = "Search Pull Requests",
      indent = 0,
      key = "P",
      action = function()
        vim.notify("Fetching open PRs from GitHub...")
        vim.defer_fn(git_pickers.pr_picker, 100)
      end,
      enabled = in_git,
    },
    {
      pane = 1,
      desc = "Search Issues",
      key = "I",
      indent = 0,
      action = function()
        vim.notify("Fetching open issues from GitHub...")
        vim.defer_fn(git_pickers.issue_picker, 100)
      end,
      enabled = in_git,
    },
    {
      pane = 1,
      desc = "Open Repo in GitHub",
      padding = 2,
      key = "B",
      indent = 0,
      action = function()
        Snacks.gitbrowse()
      end,
      enabled = in_git,
    },
  }

  -- Calculate height:
  -- 1 (Git title) + 2 (title padding) +
  -- 4 (branch, diff, uncommitted, lazygit) + 1 (lazygit padding) +
  -- 1 (separator) + 1 (separator padding) +
  -- 4 (notifications, PRs, issues, browse) + 2 (browse padding)
  local height = 1 + 2 + 4 + 1 + 1 + 1 + 4 + 2

  return sections, height
end

---Create pokemon section with fixed height matching other pane
---@param target_height number Total height this section must occupy
---@return table sections Pokemon section configuration
local function create_pokemon_section(target_height)
  -- Validate position configuration
  local position = validate_position(CONFIG.pokemon.position)

  -- Detect sprite dimensions using two-pass auto-sizing
  local sprite_width, sprite_height, use_big =
    visual_utils.detect_sprite_dimensions_auto(pokemon_name, pokemon_shiny, pokemon_form, CONFIG.pokemon.force_small)

  if not sprite_width or not sprite_height then
    -- Dimension detection failed, return empty section with target height
    vim.notify("Failed to detect pokemon sprite dimensions, using empty section", vim.log.levels.WARN)
    return {
      {
        pane = 2,
        padding = target_height,
        enabled = utils.show_if_has_second_pane,
      },
    }
  end

  -- Get pane width from Snacks configuration (respects user customizations)
  local pane_width = Snacks.config.dashboard.width or 60

  -- Calculate horizontal position (indent)
  local indent = calculate_horizontal_position(sprite_width, pane_width, position)

  -- Calculate vertical position within fixed-height section
  -- Note: We need to account for the startup time line (1 line) at the bottom
  -- So the actual available height for pokemon positioning is target_height - 1
  local pokemon_section_height = target_height - 1
  local padding_top, padding_bottom = calculate_vertical_position(sprite_height, pokemon_section_height, position)

  -- Build pokemon command with correct -b flag
  local pokemon_cmd = visual_utils.build_pokemon_command(pokemon_name, pokemon_shiny, pokemon_form, use_big)

  return {
    -- Top padding section (if any)
    {
      pane = 2,
      padding = padding_top,
      enabled = utils.show_if_has_second_pane,
    },
    -- Pokemon sprite terminal section
    {
      pane = 2,
      section = "terminal",
      cmd = pokemon_cmd,
      ttl = math.huge, -- Cache forever so the 1 second pause is only the first time
      indent = indent,
      height = sprite_height,
      enabled = utils.show_if_has_second_pane,
    },
    -- Bottom padding section (if any)
    {
      pane = 2,
      padding = padding_bottom,
      enabled = utils.show_if_has_second_pane,
    },
    -- Startup time (appears after pokemon)
    {
      pane = 2,
      title = utils.create_aligned_title("Startup", vim.fn.printf("%.1fms", require("lazy").stats().startuptime)),
      indent = 0,
      enabled = utils.show_if_has_second_pane,
    },
  }
end

-- Create all dashboard sections
function M.create_sections()
  -- Re-check for pokemon colors (in case async generation completed)
  -- Always reload when force_regenerate is active to pick up newly regenerated colors
  if (not pokemon_colors or force_regenerate_active) and pokemon_name then
    -- Reload the pokemon-colors module to pick up any newly generated colors
    -- This is important when force_regenerate=true and colors are being regenerated
    package.loaded["custom.visual.pokemon-colors"] = nil
    pokemon_colors = visual_utils.get_pokemon_colors(pokemon_name, pokemon_shiny, pokemon_form, false)
  end

  -- Re-apply pokemon colors when dashboard opens
  -- This ensures colors are correct even after colorscheme reloads or async generation
  if pokemon_colors then
    visual_utils.apply_dashboard_colors(pokemon_colors, CONFIG.colors.background_mode, color_sources)
  end

  -- Get base branch for git sections
  local base_branch = git_utils.get_base_branch()
  local current_branch = git_utils.get_current_branch()
  local in_git = Snacks.git.get_root() ~= nil

  -- Build pane 1 sections and track heights
  local pane1_height = 0

  -- Search keys section
  local search_sections, search_height = search_keys()
  pane1_height = pane1_height + search_height

  -- Recent files section (with title)
  local files_sections, files_height = get_recent_files()
  -- Add the "Recent Files" title height (1 line + 2 padding)
  local recent_files_title_height = 1 + 2
  pane1_height = pane1_height + recent_files_title_height + files_height

  -- Git sections (only if in git repo)
  local git_sections, git_height = create_git_sections(base_branch, current_branch)
  pane1_height = pane1_height + git_height

  -- Global keys section
  local global_sections, global_height = globalkeys()
  pane1_height = pane1_height + global_height

  -- Time section (1 line)
  pane1_height = pane1_height + 1

  -- Create pokemon section with matching height
  local pokemon_sections = create_pokemon_section(pane1_height)

  -- Combine all sections into the final dashboard layout
  return {
    search_sections,
    {
      title = utils.create_aligned_title("Recent Files", utils.get_recent_file_time()),
      pane = in_git and 2 or 1,
      indent = 0,
      padding = 2,
      enabled = recent_project_toggle,
    },
    files_sections,
    git_sections,
    global_sections,
    pokemon_sections,
    {
      pane = 1,
      title = utils.create_aligned_title("Time", os.date("%H:%M")),
      indent = 0,
    },
  }
end

return M
