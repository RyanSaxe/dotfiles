-- snacks_dashboard.lua  ── custom git dashboard for Snacks.nvim
-- TODO: break out all the picker logic into a separate module and register them as pickers with commands/keymaps
-- extend snacks section for getting files to be a subset of this directory
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

local diff = require("functions.diff")
local git_pickers = require("pickers.git")
local enable_issues = true
--------------------------------------------------------------------------
-- ANSI helpers ---------------------------------------------------------
--------------------------------------------------------------------------
local ESC, RESET = string.char(27), string.char(27) .. "[0m"
local palette = {
  num = ESC .. "[38;5;81m", -- bright turquoise
  branch = ESC .. "[38;5;213m", -- soft magenta
  author = ESC .. "[38;5;179m", -- warm amber
  date = ESC .. "[38;5;117m", -- teal
  header = ESC .. "[38;5;146m", -- pastel blue for headers
}
local function colour(tok, txt)
  return palette[tok] .. txt .. RESET
end

--------------------------------------------------------------------------
-- Column sizing / helpers ---------------------------------------------
--------------------------------------------------------------------------
local NUM_W, BRANCH_W, AUTH_W, DATE_W = 6, 40, 16, 10
local SEP = "  " -- two‑space gutter

local function truncate(str, max)
  if vim.fn.strdisplaywidth(str) <= max then
    return str
  end
  return str:sub(1, max - 1) .. "…"
end
local function pad(str, width)
  local s = truncate(str, width)
  local pad_len = width - vim.fn.strdisplaywidth(s)
  return s .. string.rep(" ", pad_len)
end
local function fmt_date(iso)
  return iso and iso:sub(1, 10) or ""
end

--------------------------------------------------------------------------
-- Row builders ---------------------------------------------------------
--------------------------------------------------------------------------
local function pr_to_line(pr)
  local num = colour("num", pad("#" .. pr.number, NUM_W))
  local branch = colour("branch", pad(string.format("%s → %s", pr.headRefName, pr.baseRefName), BRANCH_W))
  local author = colour("author", pad(pr.author and pr.author.login or "", AUTH_W))
  local date = colour("date", pad(fmt_date(pr.updatedAt), DATE_W))
  local title = pr.title:gsub("\n", "  ")
  return table.concat({ num, branch, author, date, title }, "\t")
end

local function issue_to_line(is)
  local num = colour("num", pad("#" .. is.number, NUM_W))
  local author = colour("author", pad(is.author and is.author.login or "", AUTH_W))
  local date = colour("date", pad(fmt_date(is.updatedAt), DATE_W))
  local title = is.title:gsub("\n", "  ")
  return table.concat({ num, author, date, title }, "\t")
end

--------------------------------------------------------------------------
-- FZF window & picker opts --------------------------------------------
--------------------------------------------------------------------------
local function winopts()
  return {
    height = 0.85,
    width = 0.92,
    border = "rounded",
    row = 0.1,
    col = 0.5,
    preview = {
      layout = "vertical",
      vertical = "down:35%",
      border = "border",
      scrollbar = true,
    },
  }
end

local function picker_opts(prompt, preview_cmd)
  local fzf_opts = {
    ["--ansi"] = "",
    ["--delimiter"] = "\t",
    ["--layout"] = "reverse",
  }

  if preview_cmd and preview_cmd ~= "" then
    fzf_opts["--tabstop"] = "1"
    fzf_opts["--preview"] = preview_cmd
    fzf_opts["--preview-window"] = "bottom:35%:wrap"
  end

  return {
    prompt = prompt,
    winopts = winopts(),
    fzf_opts = fzf_opts,
  }
end

--------------------------------------------------------------------------
-- FZF runner -----------------------------------------------------------
--------------------------------------------------------------------------
local function run_fzf(lines, opts, on_select)
  local fzf = require("fzf-lua")
  opts.actions = {
    default = function(sel)
      if sel[1] then
        on_select(sel[1])
      end
    end,
  }
  fzf.fzf_exec(lines, opts)
end

--------------------------------------------------------------------------
-- Git utilities -------------------------------------------------------
--------------------------------------------------------------------------
local function get_base_branch()
  local lines = vim.fn.systemlist("git symbolic-ref --short refs/remotes/origin/HEAD")
  local remote_head = lines[1] or ""
  local default_branch = remote_head:match("^[^/]+/(.+)$") or "main"
  return "origin/" .. default_branch
end

local function has_uncommitted_changes()
  local result = vim.fn.system("git status --porcelain")
  return result and result:match("%S") ~= nil
end

local function confirm_with_uncommitted_changes(message, callback)
  if has_uncommitted_changes() then
    local prompt = table.concat({
      "⚠️  Uncommitted Changes Detected",
      "",
      message,
      "",
      "If you continue, `git stash` will be executed.",
      "Do you want to continue?",
    }, "\n")

    -- `vim.fn.confirm()` returns 1 for “Yes”, 2 for “No”
    local choice = vim.fn.confirm(prompt, "&Yes\n&No", 2) -- default = “No”
    if choice == 1 then
      -- Run `git stash` in the current directory
      vim.fn.system("git stash")
      if vim.v.shell_error ~= 0 then
        vim.notify("⚠️  Git stash failed – aborting.", vim.log.levels.ERROR)
        return
      end

      callback()
    end
  else
    callback()
  end
end

--------------------------------------------------------------------------
-- Pull‑request picker --------------------------------------------------
--------------------------------------------------------------------------
local function pick_pr()
  local ok, raw = pcall(vim.fn.system, {
    "gh",
    "pr",
    "list",
    "-L",
    "100",
    "--json",
    "number,title,headRefName,baseRefName,author,updatedAt",
  })
  if not ok or raw == "" then
    return vim.notify("gh pr list failed", vim.log.levels.ERROR)
  end

  local prs = vim.json.decode(raw)
  if #prs == 0 then
    return vim.notify("No open PRs", vim.log.levels.INFO)
  end

  local lines, lookup = {}, {}
  for _, pr in ipairs(prs) do
    local line = pr_to_line(pr)
    table.insert(lines, line)
    lookup["#" .. pr.number] = pr
  end

  -- (Your existing picker_opts + run_fzf logic goes here)
  local opts =
    picker_opts("PR❯ ", "echo {1} | sed 's/#//' | xargs -I {} gh pr diff {} --name-only --color always | head -n 200")

  run_fzf(lines, opts, function(selected)
    local num = selected:match("#(%d+)")
    if not num then
      return
    end
    local pr = lookup["#" .. num]
    if not pr then
      return
    end

    confirm_with_uncommitted_changes("Checking out PR #" .. num .. ".", function()
      -- 4) Use `gh pr checkout <N> --force`
      vim.fn.jobstart({ "gh", "pr", "checkout", num, "--force" }, {
        on_exit = function()
          vim.schedule(function()
            vim.notify("Checked out PR #" .. num)

            -- 5) Now open Diffview using EXACT (baseRefName, headRefName)
            --     → Our my_diff.fetch_and_diff expects two args:
            --        (pr.baseRefName, pr.headRefName)
            diff.fetch_and_diff(pr.baseRefName, pr.headRefName)
          end)
        end,
      })
    end)
  end)
end

--------------------------------------------------------------------------
-- Issue picker ---------------------------------------------------------
--------------------------------------------------------------------------
local function pick_issue()
  if not enable_issues then
    return vim.notify("Issues picker is disabled", vim.log.levels.INFO)
  end
  local ok, raw = pcall(vim.fn.system, {
    "gh",
    "issue",
    "list",
    "-L",
    "100",
    "--json",
    "number,title,updatedAt,author",
  })
  if not ok then
    return vim.notify("gh issue list failed", vim.log.levels.ERROR)
  end
  local issues = vim.json.decode(raw)
  if #issues == 0 then
    return vim.notify("No open issues", vim.log.levels.INFO)
  end

  local lines, lookup = {}, {}
  for _, is in ipairs(issues) do
    local line = issue_to_line(is)
    table.insert(lines, line)
    lookup["#" .. is.number] = is
  end

  local opts = picker_opts(
    "Issue❯ ",
    "" -- no preview for issues
  )

  run_fzf(lines, opts, function(selected)
    local num = selected:match("#(%d+)")
    if not num then
      return
    end
    local is = lookup["#" .. num]
    if not is then
      return
    end
    vim.fn.jobstart({ "gh", "issue", "view", num, "--web" }, { detach = true })
  end)
end

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

local base_branch = get_base_branch()
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
            title = "Git",
            desc = string.format("(%s)", current_branch:gsub("\n", "")),
            indent = 0,
            padding = 1,
          },
          {
            pane = 2,
            icon = " ",
            title = "Search Pull Requests",
            key = "p",
            action = pick_pr,
          },
          -- TODO: change this to enable git and have an entirely different view when not in a git repository
          enable_issues
              and {
                pane = 2,
                icon = " ",
                title = "Search Issues",
                key = "i",
                action = pick_issue,
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
                head = "HEAD",
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
