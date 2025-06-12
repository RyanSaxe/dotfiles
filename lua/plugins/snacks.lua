-- snacks_dashboard.lua  ── custom git dashboard for Snacks.nvim

-- some random utilities the dahsboard needs that I'll probably not reuse

---@param max integer|nil
---@return string[]
local function recent_files_in_cwd(max)
  max = max or 10
  local cwd = vim.loop.cwd()
  local list = {}
  for _, abs in ipairs(vim.v.oldfiles) do
    if vim.startswith(abs, cwd) and vim.fn.filereadable(abs) == 1 then
      table.insert(list, vim.fn.fnamemodify(abs, ":.")) -- relative path
      if #list == max then
        break
      end
    end
  end
  return list
end

-- Normalize and format file paths for prettier display
---@param path string Path to normalize
---@param max_length? number Maximum display length (default: 40)
---@return string Normalized and formatted path
local function normalize_path(path, max_length)
  max_length = max_length or 40
  local normalized = vim.fs.normalize(path)

  if #normalized <= max_length then
    return normalized
  end

  -- Keep filename and truncate from the middle
  local parts = vim.split(normalized, "/")
  local filename = parts[#parts]

  if #filename >= max_length - 3 then
    return "..." .. filename:sub(-(max_length - 3))
  end

  -- Build path keeping filename and as much directory structure as possible
  local result = filename
  for i = #parts - 1, 1, -1 do
    local candidate = parts[i] .. "/" .. result
    if #candidate > max_length - 3 then
      return "..." .. result
    end
    result = candidate
  end

  return result
end

local diff = require("custom.git.diff")
local git_pickers = require("custom.git.pickers")
local git_utils = require("custom.git.utils")
local git_reddit = require("custom.git.reddit")
local enable_issues = true
local Snacks = require("snacks")

local create_pane = function(header, specs)
  local pane = header.pane
  header.padding = header.padding or 1
  header.indent = header.indent or 0

  local output = { header }
  for i, spec in ipairs(specs) do
    -- set padding on the spec itself
    spec.padding = (i == #specs) and 1 or 0

    -- start with defaults
    local row = {
      pane = pane,
      indent = 2,
    }
    -- copy all spec fields in
    for k, v in pairs(spec) do
      row[k] = v
    end

    table.insert(output, row)
  end

  return output -- ← you must return it!
end

local different_key_if_condition = function(condition, base_spec, git_spec, non_git_spec)
  if condition then
    return vim.tbl_deep_extend("force", {}, base_spec, git_spec)
  else
    return vim.tbl_deep_extend("force", {}, base_spec, non_git_spec)
  end
end
local search_keys = function()
  local cwd = vim.fn.getcwd()
  local project = vim.fn.fnamemodify(cwd, ":t")
  local header = { pane = 1, title = "Search Project", desc = " (" .. project .. ")" }

  local keys = {
    { icon = " ", key = "/", desc = "Grep Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
    {
      icon = " ",
      desc = "Search TODOs",
      key = "x",
      action = function()
        Snacks.picker.todo_comments({ keywords = { "TODO", "FIX", "FIXME", "HACK", "BUG" } })
      end,
    },
  }

  local find_file_base = { icon = " ", key = "f", desc = "Find File" }
  table.insert(
    keys,
    different_key_if_condition(
      Snacks.git.get_root() ~= nil,
      find_file_base,
      { action = ":lua Snacks.dashboard.pick('git_files')" },
      { action = ":lua Snacks.dashboard.pick('files')" }
    )
  )

  return create_pane(header, keys)
end
local hotkeys = function()
  local header = { pane = 1, title = "Convenient Commands" }

  local keys = {

    {
      icon = "󰒲 ",
      key = "l",
      desc = "Lazy",
      action = ":Lazy",
      enabled = package.loaded.lazy ~= nil,
    },
    -- I dont use lazy extras much anymore, but leaving it here to easily enable it if needed
    {
      icon = " ",
      key = "x",
      desc = "Lazy Extras",
      action = ":LazyExtras",
      enabled = false, -- package.loaded.lazy ~= nil,
    },
    { icon = " ", key = "q", desc = "Quit", action = ":qa" },
    { icon = " ", key = "r", desc = "Restore Session", section = "session" },
  }

  return create_pane(header, keys)
end

local globalkeys = function()
  -- NOTE: consider the projects section that only shows up if not in a git repo
  local header = { pane = 1, title = "Global Commands" }
  local keys = {
    {
      icon = " ",
      key = "c",
      desc = "Search Config",
      action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})",
    },
    {
      action = function()
        Snacks.scratch.select()
      end,
      icon = " ",
      key = "s",
      desc = "Select Scratch File",
    },
    { icon = " ", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
  }

  return create_pane(header, keys)
end

local base_branch = git_utils.get_base_branch()
local current_branch = vim.fn.system("git rev-parse --abbrev-ref HEAD")
return {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    dependencies = { "ibhagwan/fzf-lua", "folke/todo-comments.nvim" },
    opts = {
      dashboard = {
        sections = {

          search_keys,
          {
            pane = 2,
            title = "Git Operations",
            desc = string.format(" (%s)", current_branch:gsub("\n", "")),
            indent = 0,
            padding = 1,
            enabled = Snacks.git.get_root() ~= nil,
          },
          {
            pane = 2,
            icon = " ",
            desc = "Checkout Another Branch",
            key = "b",
            action = function()
              Snacks.picker.git_branches()
            end,
            enabled = Snacks.git.get_root() ~= nil,
            indent = 2,
          },
          {
            pane = 2,
            icon = " ",
            desc = string.format("Search Diff (Hunks) vs %s", base_branch),
            -- desc = string.format("git diff %s", get_base_branch()),
            key = "d",
            indent = 2,
            action = function()
              git_pickers.diff_picker(base_branch)
            end,
            enabled = Snacks.git.get_root() ~= nil,
          },
          {
            pane = 2,
            icon = " ",
            indent = 2,
            desc = "Find Un-Commited Changes",
            padding = 5,
            key = "u",
            action = function()
              Snacks.picker.git_status()
            end,
            enabled = Snacks.git.get_root() ~= nil,
          },

          {
            pane = 1,
            title = "Search Github",
            indent = 0,
            padding = 1,
            enabled = Snacks.git.get_root() ~= nil,
          },
          {
            pane = 1,
            icon = " ",
            desc = "Search Pull Requests",
            indent = 2,
            key = "p",
            action = function()
              vim.notify("Fetching open PRs from GitHub...")
              vim.defer_fn(git_pickers.pr_picker, 100)
            end,
            enabled = Snacks.git.get_root() ~= nil,
          },
          {
            pane = 1,
            icon = " ",
            desc = "Search Issues",
            key = "i",
            indent = 2,
            action = function()
              vim.notify("Fetching open issues from GitHub...")
              vim.defer_fn(git_pickers.issue_picker, 100)
            end,
            enabled = Snacks.git.get_root() ~= nil,
          },
          {
            pane = 1,
            icon = " ",
            desc = "Open Repo in Browser",
            padding = 1,
            key = "o",
            indent = 2,
            action = function()
              Snacks.gitbrowse()
            end,
            enabled = Snacks.git.get_root() ~= nil and enable_issues,
          },
          hotkeys,
          globalkeys,
          {
            title = "Recent Project Files",
            pane = 1,
            indent = 0,
            padding = 1,
          },
          function()
            local out = {}
            local recent_files = recent_files_in_cwd(3)
            for i, rel in ipairs(recent_files) do
              out[#out + 1] = {
                pane = 1, -- pick whatever pane you prefer
                icon = "󰈙 ",
                indent = 2,
                padding = (i == #recent_files) and 1 or 0,
                desc = normalize_path(rel),
                key = tostring(i), -- “press 1-9” hot-keys
                action = function()
                  vim.cmd("edit " .. rel)
                end,
                enabled = true,
              }
            end
            if #out == 0 then
              out[1] = {
                pane = 2,
                icon = " ",
                desc = "No recent files in this directory",
                padding = 1,
                enabled = false,
              }
            end
            return out
          end,
          {
            pane = 2,
            section = "terminal",
            cmd = "pokemon-colorscripts -n snorlax -s --no-title; sleep 0.01",
            indent = 10,
            height = 20,
          },
        },
      },
    },
  },
}
