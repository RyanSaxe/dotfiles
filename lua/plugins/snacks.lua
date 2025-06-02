-- snacks_dashboard.lua  ── custom git dashboard for Snacks.nvim
--

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
      "This might cause you to lose work.",
      "Do you want to continue?",
    }, "\n")

    -- `vim.fn.confirm()` returns 1 for the first button, 2 for the second, etc.
    local choice = vim.fn.confirm(prompt, "&Yes\n&No", 2) -- default = “No”
    if choice == 1 then
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
  if not ok then
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
      vim.fn.jobstart({ "gh", "pr", "checkout", num, "--force" }, {
        on_exit = function()
          vim.schedule(function()
            vim.notify("Checked out PR #" .. num)
            diff.fetch_and_diff(pr.baseRefName)
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

--------------------------------------------------------------------------
-- Snacks plugin spec ---------------------------------------------------
--------------------------------------------------------------------------

local hotkeys = function()
  local output = {
    { pane = 1, title = "Hot Keys", indent = 0, padding = 1 },
  }
  local keys = {
    { key = "f", desc = "Find File", action = "fzf-lua.files", icon = "" },
  }
  for _, key in ipairs(keys) do
    output[#output + 1] = {
      pane = 1,
      icon = key.icon .. " ",
      desc = key.desc,
      key = key.key,
      action = key.action,
      indent = 2,
      padding = 0,
      enabled = true,
    }
  end
  return output
end
return {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    dependencies = { "ibhagwan/fzf-lua" },
    opts = {
      dashboard = {
        sections = {
          -- { icon = " ", section = "keys", title = "Hot Keys", indent = 2, padding = 1 },
          -- the below should exist in panel 2, but only if not in a git project
          -- { icon = " ", title = "Projects", section = "projects", indent = 2, padding = 1 },
          hotkeys,
          {
            pane = 2,
            icon = " ",
            title = "Browse Repository Online",
            key = "o",
            padding = 1,
            action = function()
              Snacks.gitbrowse()
            end,
          },

          {
            pane = 2,
            icon = " ",
            title = "Search Pull Requests:",
            desc = " Select to Review the Diff",
            key = "r",
            padding = 1,
            action = pick_pr,
          },
          enable_issues and {
            pane = 2,
            icon = " ",
            title = "Search Issues:",
            desc = " Select to View in Browser",
            key = "i",
            padding = 1,
            action = pick_issue,
          } or nil,
          {
            pane = 2,
            icon = "",
            title = "Git Branches:",
            desc = " Select to Checkout",
            key = "b",
            padding = 1,
            action = function()
              require("fzf-lua").git_branches({
                actions = {
                  ["default"] = function(selected)
                    if selected[1] then
                      local branch = selected[1]:match("[%*%s]*(.-)%s*$")
                      confirm_with_uncommitted_changes("Switching to branch '" .. branch .. "'.", function()
                        vim.fn.jobstart({ "git", "checkout", branch }, {
                          on_exit = function()
                            vim.schedule(function()
                              vim.notify("Switched to branch '" .. branch .. "'")
                            end)
                          end,
                        })
                      end)
                    end
                  end,
                },
              })
            end,
          },
          {
            pane = 2,
            icon = "",
            title = "Git Diff vs Base:",
            desc = " Select to Open File",
            key = "d",
            padding = 1,
            action = function()
              local base_branch = get_base_branch()
              require("fzf-lua").git_diff({ ref = base_branch })
            end,
          },
          {
            icon = "",
            title = "Git Status\n",
            section = "terminal",
            pane = 2,
            indent = 0,
            height = 10,
            padding = 1,
            ttl = 5,
            cmd = [[git diff-index --quiet HEAD -- && git status || git --no-pager diff --color --stat=50,20,5 -B -M -C]],
          },
          {
            title = "Recent Files",
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
