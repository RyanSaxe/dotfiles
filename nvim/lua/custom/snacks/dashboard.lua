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
    name = "gengar",

    -- Set to true for shiny variant
    is_shiny = false,

    -- Optional form (e.g., "alola", "galar", "mega-x"), set to nil if not applicable
    form = nil,

    -- Force small sprite size (don't add -b flag even if sprite is small)
    -- This is useful if you prefer the smaller sprite aesthetic
    force_small = false,
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
    desc_source = "Comment", --"auto",

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

  -- Layout configuration
  layout = {
    -- Padding value for aligning recent files with pokemon display
    pokemon_padding = 4,
  },
}

-- Calculate pokemon selection and colors (only done once at startup)
-- This ensures the pokemon doesn't change on dashboard redraws
local pokemon_name, pokemon_shiny, pokemon_form, pokemon_colors

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

  -- Load color data for the selected pokemon
  -- This will auto-generate if not in database (async)
  pokemon_colors = visual_utils.ensure_pokemon_colors(pokemon_name, pokemon_shiny, pokemon_form, function()
    -- Callback: when generation completes, update the dashboard
    if Snacks and Snacks.dashboard and Snacks.dashboard.update then
      Snacks.dashboard.update()
    end
  end, CONFIG.colors.background_mode)

  if pokemon_colors then
    -- Apply colors to Snacks dashboard highlight groups
    -- Pass background_mode configuration, color source overrides, and adjustments
    visual_utils.apply_dashboard_colors(pokemon_colors, CONFIG.colors.background_mode, {
      title_source = CONFIG.colors.title_source,
      key_source = CONFIG.colors.key_source,
      desc_source = CONFIG.colors.desc_source,
      title_brighten = CONFIG.colors.title_brighten,
      key_brighten = CONFIG.colors.key_brighten,
      desc_brighten = CONFIG.colors.desc_brighten,
      title_dim = CONFIG.colors.title_dim,
      key_dim = CONFIG.colors.key_dim,
      desc_dim = CONFIG.colors.desc_dim,
    })
  end
end

-- Build the pokemon command to execute
-- Note: force_small will be used in future sprite positioning logic (see SPRITE_POSITIONING.md)
local POKEMON_CMD = visual_utils.build_pokemon_command(pokemon_name or "pikachu", pokemon_shiny or false, pokemon_form)

-- Global padding constant for pokemon alignment (access from CONFIG)
local POKEMON_PADDING = CONFIG.layout.pokemon_padding

-- Check if we should show recent project toggle based on context
local function recent_project_toggle()
  local in_git = Snacks.git.get_root() ~= nil
  local has_two_panes = utils.show_if_has_second_pane()
  -- if in git and has one pane, then we disable
  return not (in_git and not has_two_panes)
end

-- Create search keys section for project operations
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
local function get_recent_files()
  local out = {}
  local max_files = 5
  local recent_files = utils.recent_files_in_cwd(max_files)
  local n_files = #recent_files
  local pane = Snacks.git.get_root() and 2 or 1
  local final_padding = pane == 2 and max_files - n_files + POKEMON_PADDING or 2

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
      padding = pane == 2 and max_files + POKEMON_PADDING - 1 or 2,
      enabled = recent_project_toggle,
    }
  end
  if pane == 1 and utils.show_if_has_second_pane() then
    out[#out + 1] = {
      pane = 2,
      padding = n_files > 0 and n_files or 1,
    }
  end
  return out
end

-- Create all dashboard sections
function M.create_sections()
  -- Re-check for pokemon colors (in case async generation completed)
  if not pokemon_colors and pokemon_name then
    pokemon_colors = visual_utils.get_pokemon_colors(pokemon_name, pokemon_shiny, pokemon_form, false)
  end

  -- Re-apply pokemon colors when dashboard opens
  -- This ensures colors are correct even after colorscheme reloads or async generation
  if pokemon_colors then
    visual_utils.apply_dashboard_colors(pokemon_colors, CONFIG.colors.background_mode, {
      title_source = CONFIG.colors.title_source,
      key_source = CONFIG.colors.key_source,
      desc_source = CONFIG.colors.desc_source,
      title_brighten = CONFIG.colors.title_brighten,
      key_brighten = CONFIG.colors.key_brighten,
      desc_brighten = CONFIG.colors.desc_brighten,
      title_dim = CONFIG.colors.title_dim,
      key_dim = CONFIG.colors.key_dim,
      desc_dim = CONFIG.colors.desc_dim,
    })
  end

  local base_branch = git_utils.get_base_branch()
  local current_branch = git_utils.get_current_branch()
  local recent_files = get_recent_files()
  return {

    -- { pane = 1, padding = 2, indent = 0 },
    -- { pane = 2, padding = 2, enabled = utils.show_if_has_second_pane, indent = 0 },
    search_keys,
    {
      title = utils.create_aligned_title("Recent Files", utils.get_recent_file_time()),
      pane = Snacks.git.get_root() and 2 or 1,
      indent = 0,
      padding = 2,
      enabled = recent_project_toggle,
    },
    recent_files,
    {
      pane = 1,
      title = utils.create_aligned_title("Git", current_branch),
      indent = 0,
      padding = 2,
      enabled = Snacks.git.get_root() ~= nil,
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
      enabled = Snacks.git.get_root() ~= nil,
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
      enabled = Snacks.git.get_root() ~= nil,
    },
    {
      pane = 1,
      indent = 0,
      desc = "Search Un-Commited Changes",
      key = "u",
      action = function()
        Snacks.picker.git_status()
      end,
      enabled = Snacks.git.get_root() ~= nil,
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
      enabled = Snacks.git.get_root() ~= nil,
    },
    {
      pane = 1,
      indent = 0,
      -- 60 ticks is exactly the size of a line (width 60, indent = 0)
      title = "------------------------------------------------------------",
      padding = 1,
      enabled = Snacks.git.get_root() ~= nil,
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
      enabled = Snacks.git.get_root() ~= nil,
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
      enabled = Snacks.git.get_root() ~= nil,
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
      enabled = Snacks.git.get_root() ~= nil,
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
      enabled = Snacks.git.get_root() ~= nil,
    },
    -- hotkeys,
    globalkeys,
    -- if pokemon is being shown and there is no git operations, then the recent files move to the
    -- first pane, and the pokemon needs to be padded according to the number of lines in recent files
    {
      pane = 2,
      enabled = utils.show_if_has_second_pane,
      padding = 2,
    },
    {
      pane = 2,
      section = "terminal",
      -- Pokemon sprite display using configured pokemon from top of file
      cmd = POKEMON_CMD,
      ttl = math.huge, -- make the cache last forever so the 1 second pause is only the first time opening a project
      indent = 10, -- if your pokemon renders weird, adjust this number. Higher values push the pokemon right.
      -- 21 is the exact number of lines to make right and left bar aligned
      height = 21,
      enabled = utils.show_if_has_second_pane,
      padding = 0,
    },
    {
      pane = 2,
      title = utils.create_aligned_title("Startup", vim.fn.printf("%.1fms", require("lazy").stats().startuptime)),
      indent = 0,
      enabled = utils.show_if_has_second_pane,
    },
    {
      pane = 1,
      title = utils.create_aligned_title("Time", os.date("%H:%M")),
      indent = 0,
    },
  }
end

return M
