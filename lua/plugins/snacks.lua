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
local enable_issues = true

local hotkeys = function()
  local output = {
    { pane = 1, desc = "Hot Keys", indent = 0, padding = 1 },
  }
  local keys = {
    { icon = " ", key = "f", title = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
    { icon = " ", key = "g", title = "Grep Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
    { icon = " ", key = "t", title = "Typing Practice", action = ":Typr" },
    { icon = " ", key = "v", title = "Vim Practice", action = ":VimBeGood" },
    {
      icon = " ",
      key = "c",
      title = "Config",
      action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})",
    },
    { icon = " ", key = "s", title = "Restore Session", section = "session" },
    { icon = "󰒲 ", key = "l", title = "Lazy", action = ":Lazy", enabled = package.loaded.lazy ~= nil },
    { icon = " ", key = "x", title = "Lazy Extras", action = ":LazyExtras", enabled = package.loaded.lazy ~= nil },

    { icon = " ", key = "q", title = "Quit", action = ":qa" },
  }
  for nkey, key in ipairs(keys) do
    if nkey == #keys then
      key.padding = 1
    else
      key.padding = 0
    end
    output[#output + 1] = {
      pane = 1,
      icon = key.icon .. " ",
      title = key.title,
      key = key.key,
      action = key.action,
      indent = 2,
      padding = key.padding,
      enabled = true,
    }
  end
  return output
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

          hotkeys,
          {
            pane = 2,
            desc = string.format("Repository Actions (%s)", current_branch:gsub("\n", "")),
            indent = 0,
            padding = 1,
          },
          {
            pane = 2,
            icon = " ",
            title = "Search Pull Requests",
            key = "p",
            action = function()
              Snacks.picker({
                finder = git_pickers.fetch_prs,
                format = git_pickers.format_pr_row,
                preview = git_pickers.preview_pr,
                confirm = function(picker, pr)
                  git_utils.confirm_stash_uncommitted_changes_before_op(
                    "Checking out PR #" .. pr.number .. ".",
                    function()
                      -- 4) Use `gh pr checkout <N> --force`
                      vim.fn.jobstart({ "gh", "pr", "checkout", pr.number, "--force" }, {
                        on_exit = function()
                          vim.schedule(function()
                            vim.notify("Checked out PR #" .. pr.number)
                            diff.fetch_and_diff(pr.baseRefName)
                          end)
                        end,
                      })
                    end
                  )
                end,
              })
            end,
          },
          -- TODO: change this to enable git and have an entirely different view when not in a git repository
          enable_issues
              and {
                pane = 2,
                icon = " ",
                title = "Search Issues",
                key = "i",
                action = function()
                  Snacks.picker({
                    finder = git_pickers.fetch_issues,
                    format = git_pickers.format_issue_row,
                    preview = git_pickers.preview_issue,
                  })
                end,
              }
            or nil,
          {
            pane = 2,
            icon = "",
            title = "Checkout Another Branch",
            key = "b",
            action = function()
              Snacks.picker.git_branches()
            end,
          },
          {
            pane = 2,
            icon = "",
            title = string.format("Search Diff (Hunks) vs %s", base_branch),
            -- desc = string.format("git diff %s...HEAD", get_base_branch()),
            key = "d",
            action = function()
              Snacks.picker({
                finder = git_pickers.custom_diff,
                format = "file",
                preview = "diff",
                base = base_branch,
                head = nil,
              })
              -- require("fzf-lua").git_diff({ ref = base_branch })
            end,
          },
          {
            pane = 2,
            icon = " ",
            title = "Search Uncommitted Changes",
            key = "s",
            action = function()
              Snacks.picker.git_status()
            end,
          },
          {
            pane = 2,
            icon = " ",
            title = "Search TODOs",
            key = "?",
            action = function()
              Snacks.picker.todo_comments({ keywords = { "TODO", "FIX", "FIXME", "HACK", "BUG" } })
            end,
          },
          {
            pane = 2,
            icon = " ",
            title = "Search Errors",
            key = "?",
            action = function()
              Snacks.picker.diagnostics()
            end,
          },
          {
            desc = "Recent Files",
            pane = 1,
            indent = 0,
            padding = 1,
          },
          function()
            local out = {}
            for i, rel in ipairs(recent_files_in_cwd(9)) do
              out[#out + 1] = {
                pane = 1, -- pick whatever pane you prefer
                icon = " ",
                indent = 2,
                title = normalize_path(rel),
                key = tostring(i), -- “press 1-9” hot-keys
                action = function()
                  vim.cmd("edit " .. rel)
                end,
                enabled = true,
              }
            end
            if #out == 0 then
              out[1] = {
                pane = 1,
                icon = " ",
                title = "No recent files in this directory",
                enabled = false,
              }
            end
            return out
          end,
        },
      },
    },
  },
}
