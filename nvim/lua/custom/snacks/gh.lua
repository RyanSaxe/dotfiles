-- gh.lua  ── Custom GitHub actions for snacks.nvim
-- Adds custom actions to the GitHub picker action menu

local M = {}

-- Define custom GitHub actions
M.custom_actions = {
  -- Open PR in Diffview
  open_in_diffview = {
    desc = "Open PR in Diffview",
    icon = "󰊢",
    type = "pr",
    priority = 150,
    action = function(item, ctx)
      -- Show notification immediately (before blocking operation)
      vim.notify("Fetching latest refs...", vim.log.levels.INFO)

      -- Fetch asynchronously so UI stays responsive
      vim.system({ "git", "fetch", "origin" }, {}, function(result)
        -- Schedule UI updates on main thread
        vim.schedule(function()
          if result.code ~= 0 then
            vim.notify("Failed to fetch: " .. result.stderr, vim.log.levels.ERROR)
            return
          end

          -- Build the diff range using remote refs: origin/base...origin/head
          -- This works even if the PR branch isn't checked out locally
          local diff_range = string.format("origin/%s...origin/%s", item.baseRefName, item.headRefName)

          -- Open in diffview
          vim.cmd("DiffviewOpen " .. diff_range)

          -- Store PR context for potential future use
          vim.g.current_pr = {
            repo = item.repo,
            number = item.number,
            base = item.baseRefName,
            head = item.headRefName,
          }

          vim.notify(string.format("Opened PR #%d in Diffview", item.number))
        end)
      end)
    end,
  },
}

-- Register custom actions with snacks
function M.register()
  local gh_actions = require("snacks.gh.actions")
  for name, action in pairs(M.custom_actions) do
    gh_actions.actions[name] = action
  end
end

return M
