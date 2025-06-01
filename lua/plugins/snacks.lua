local diff = require("functions.diff")
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
                  icon = " ",
                  title = "No open pull-requests ✨",
                  enabled = true,
                },
              }
            end

            local keybank = "123456789abcdefghijklmnopqrstuvwxyz"
            local entries = {}

            for idx, pr in ipairs(prs) do
              local key = keybank:sub(idx, idx) -- unique hot-key per PR

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
                indent = 0,
                ttl = 60, -- refresh every minute
                icon = " ",
                key = key,
                height = 1,
                padding = 1,
                title = ("#%d %s"):format(pr.number, ellipsis(pr.title, 48)),
                action = checkout_and_diff, -- when the user presses the key for this PR they get to review the diff
              })
            end

            return entries
          end,
          { section = "startup" },
        },
      },
    },
  },
}
