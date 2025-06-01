local diff = require("functions.diff")
local enable_issues = false -- a second request slows things down, so disable by default
return {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      dashboard = {
        sections = {
          -- { section = "header" }, -- this is disabled to make formatting much nicer
          { section = "keys", title = "Hot Keys", indent = 2, padding = 1 },
          { icon = " ", title = "Recent Files", section = "recent_files", indent = 2, padding = 1 },
          { icon = " ", title = "Projects", section = "projects", indent = 2, padding = 1 },
          {
            pane = 2,
            icon = " ",
            desc = "Browse Repo",
            key = "b",
            padding = 1,
            action = function()
              Snacks.gitbrowse()
            end,
          },
          {
            pane = 2,
            -- Only show this pane when we’re inside a Git repo *and* `gh` is available.
            function()
              local in_git = Snacks.git.get_root() ~= nil
              local has_gh = vim.fn.executable("gh") == 1
              if not (in_git and has_gh and enable_issues) then
                return {}
              end

              -- Utility: truncate with ellipsis (“…”)
              local function ellipsis(str, max_len)
                if vim.fn.strdisplaywidth(str) <= max_len then
                  return str
                end
                return str:sub(1, max_len - 1) .. "…"
              end

              -- Helper: fetch open issues for the current repo, returns Lua table
              local function get_open_issues()
                local ok, json = pcall(vim.fn.system, {
                  "gh",
                  "issue",
                  "list",
                  "-L",
                  "9", -- limit to 9 entries so our keybank fits
                  "--state",
                  "open",
                  "--json",
                  "number,title", -- only pull number + title
                })
                if not ok then
                  return {}
                end
                return vim.json.decode(json)
              end

              -- Build one dashboard-entry per issue
              local issues = get_open_issues()
              if #issues == 0 then
                return {
                  {
                    pane = 2,
                    indent = 0,
                    icon = " ",
                    title = "No open issues ✨",
                    padding = 1,
                    enabled = true,
                  },
                }
              end

              local keybank = "123456789abcdefghijklmnopqrstuvwxyz"
              local entries = {
                {
                  pane = 2,
                  indent = 0,
                  padding = 1,
                  icon = " ",
                  title = "Recent Issues: Open in Browser",
                  enabled = true,
                },
              }

              for idx, issue in ipairs(issues) do
                local key = keybank:sub(idx, idx) -- unique hot-key per issue

                local is_last = (idx == #issues)
                local padding_amount = is_last and 1 or 0
                -- Action → open issue in browser
                local function open_in_browser()
                  vim.fn.jobstart({ "gh", "issue", "view", tostring(issue.number), "--web" }, {
                    detach = true,
                  })
                end

                table.insert(entries, {
                  pane = 2,
                  indent = 3,
                  ttl = 60, -- refresh every minute
                  icon = "#" .. tostring(issue.number),
                  key = "i" .. tostring(key),
                  height = 1,
                  padding = padding_amount,
                  title = ("%s"):format(ellipsis(issue.title, 40)),
                  action = open_in_browser, -- opens the issue in the browser
                })
              end

              return entries
            end,
          },
          -- ─── Pull-request browser ──────────────────────────────────────────────────
          function()
            -- Only show this pane when we’re inside a Git repo *and* gh is available.
            local in_git = Snacks.git.get_root() ~= nil
            local has_gh = vim.fn.executable("gh") == 1
            if not (in_git and has_gh) then
              return {}
            end

            -- Utility: truncate with ellipsis (“…”)
            local function ellipsis(str, max_len)
              if vim.fn.strdisplaywidth(str) <= max_len then
                return str
              end
              return str:sub(1, max_len - 1) .. "…"
            end

            -- Helper: fetch open PRs for the current repo, returns Lua table
            local function get_open_prs()
              local ok, json = pcall(vim.fn.system, {
                "gh",
                "pr",
                "list",
                "-L",
                "9", -- this will get the numbers on dashboard 1-9
                "--state",
                "open",
                "--json",
                "number,title,headRefName,baseRefName",
              })
              if not ok then
                return {}
              end
              return vim.json.decode(json)
            end

            -- Build one dashboard-entry per PR
            local prs = get_open_prs()
            if #prs == 0 then
              return { -- graceful fallback
                {
                  pane = 2,
                  indent = 0,
                  padding = 1,
                  icon = " ",
                  title = "No open pull-requests ✨",
                  enabled = true,
                },
              }
            end

            local keybank = "123456789abcdefghijklmnopqrstuvwxyz"
            local entries = {
              {
                pane = 2,
                indent = 0,
                padding = 1,
                icon = " ",
                title = "Recent Pull-Requests: Checkout and Review the Diff!",
                enabled = true,
              },
            }

            for idx, pr in ipairs(prs) do
              local key = keybank:sub(idx, idx) -- unique hot-key per PR
              local is_last = (idx == #prs)
              local padding_amount = is_last and 1 or 0
              -- Action → checkout PR branch then open Diffview
              local function checkout_and_diff()
                -- NOTE: we do force here to guarantee that we have the exact version of the code in the PR
                --       because that is what this dashboard is for. This means that you should be careful.
                vim.fn.jobstart({ "gh", "pr", "checkout", tostring(pr.number), "--force" }, {
                  detach = false,
                  on_exit = function()
                    vim.schedule(function()
                      vim.notify("Checked out PR #" .. pr.number .. " (" .. pr.headRefName .. ")")
                      diff.fetch_and_diff(pr.baseRefName)
                    end)
                  end,
                })
              end

              table.insert(entries, {
                pane = 2,
                indent = 3,
                ttl = 60, -- refresh every minute
                icon = "#" .. tostring(pr.number),
                key = "p" .. tostring(key),
                height = 1,
                padding = padding_amount,
                title = ("%s"):format(ellipsis(pr.headRefName, 40)),
                action = checkout_and_diff, -- when the user presses the key for this PR they get to review the diff
              })
            end

            return entries
          end,
          {
            icon = " ",
            title = "Git Status\n",
            cmd = [[
git diff-index --quiet HEAD -- && \
git status || \
git --no-pager diff --color --stat=50,20,5 -B -M -C
]],
            height = 10,
            section = "terminal",
            padding = 1,
            ttl = 5, -- refresh every 5 seconds
            pane = 2,
            indent = 0,
          },
        },
      },
    },
  },
}
