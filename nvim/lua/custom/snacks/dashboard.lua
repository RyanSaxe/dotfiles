-- dashboard.lua  ── custom git dashboard configuration for Snacks.nvim
-- Contains all dashboard sections, keys, and layout logic

local utils = require("custom.snacks.utils")
local git_pickers = require("custom.git.pickers")
local git_utils = require("custom.git.utils")

local M = {}

-- Global padding constant for snorlax alignment
local SNORLAX_PADDING = 4

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
  local final_padding = pane == 2 and max_files - n_files + SNORLAX_PADDING or 2

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
      padding = pane == 2 and max_files + SNORLAX_PADDING - 1 or 2,
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
    -- if snorlax is being shown and there is no git operations, then the recent files move to the
    -- first pane, and snorlax needs to be padded according to the number of lines in recent files
    {
      pane = 2,
      enabled = utils.show_if_has_second_pane,
      padding = 2,
    },
    {
      pane = 2,
      section = "terminal",
      -- the commented out command below will have an animated ascii aquarium
      -- cmd = 'curl "http://asciiquarium.live?cols=$(tput cols)&rows=$(tput lines)"',
      -- NOTE: for some reason, sleep 10 makes it never flicker, but also only causes a 1 second pause
      cmd = "pokemon-colorscripts -n snorlax -s --no-title; sleep 0.01",
      ttl = math.huge, -- make the cache last forever so the 1 second pause is only the first time opening a project
      indent = 22,
      -- 21 is the exact number of lines to make right and left bar aligned
      height = 21,
      enabled = utils.show_if_has_second_pane,
      padding = 0, --SNORLAX_PADDING - 1,
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