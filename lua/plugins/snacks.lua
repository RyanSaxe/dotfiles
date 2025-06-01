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
                "10",
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
                -- 1. Make the PR branch local and switch to it.
                vim.fn.jobstart({ "gh", "pr", "checkout", tostring(pr.number) }, {
                  detach = false,
                  on_exit = function()
                    -- 2. Once checkout is done, open a focused two-pane diff:
                    --    <base>..HEAD     ← two-dot syntax = “changes on HEAD relative to base”
                    vim.schedule(function()
                      --  ensure we reference the up-to-date remote tracking branch
                      local base = ("origin/%s"):format(pr.baseRefName or "develop")
                      vim.cmd(("DiffviewOpen %s..HEAD"):format(base))
                    end)
                  end,
                })
              end

              table.insert(entries, {
                pane = 2,
                -- section = "terminal",
                indent = 0,
                ttl = 60, -- refresh every minute
                icon = " ",
                key = key,
                height = 1,
                padding = 1,
                title = ("#%d %s"):format(pr.number, ellipsis(pr.title, 48)),
                -- cmd = ("gh pr checkout %d"):format(pr.number), -- what runs when *selected*
                action = checkout_and_diff, -- what runs on hot-key
              })
            end

            return entries
          end,
          { section = "startup" },
        },
      },
    },
    init = function()
      vim.api.nvim_create_autocmd("User", {
        pattern = "VeryLazy",
        callback = function()
          -- Setup some globals for debugging (lazy-loaded)
          _G.dd = function(...)
            Snacks.debug.inspect(...)
          end
          _G.bt = function()
            Snacks.debug.backtrace()
          end
          vim.print = _G.dd -- Override print to use snacks for `:=` command

          -- Create some toggle mappings
          Snacks.toggle.option("spell", { name = "Spelling" }):map("<leader>ts")
          Snacks.toggle.diagnostics():map("<leader>td")
          Snacks.toggle.inlay_hints():map("<leader>th")
          Snacks.toggle.dim():map("<leader>tz")

          -- Add Copilot toggle
          local copilot_exists = pcall(require, "copilot")
          if copilot_exists then
            Snacks.toggle({
              name = "Copilot Completion",
              color = {
                enabled = "azure",
                disabled = "orange",
              },
              get = function()
                return not require("copilot.client").is_disabled()
              end,
              set = function(state)
                if state then
                  require("copilot.command").enable()
                else
                  require("copilot.command").disable()
                end
              end,
            }):map("<leader>tc")
          end
          --
        end,
      })
    end,
  },
}
