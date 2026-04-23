-- gh.lua  ── Custom GitHub actions for snacks.nvim
-- Adds custom actions to the GitHub picker action menu

local M = {}
local git_utils = require("custom.git.utils")

-- Define custom GitHub actions
M.custom_actions = {
  -- Open PR in CodeDiff
  open_in_codediff = {
    desc = "Open PR in CodeDiff",
    icon = "󰊢",
    type = "pr",
    priority = 150,
    action = function(item, ctx)
      -- Show notification immediately (before blocking operation)
      vim.notify("Fetching latest refs...", vim.log.levels.INFO)

      git_utils.fetch_origin(function()
        -- Open in codediff with two refs (ref-to-ref comparison, no working tree)
        local base = git_utils.resolve_branch_ref(item.baseRefName)
        local head = git_utils.resolve_branch_ref(item.headRefName)

        if not git_utils.ref_exists(base) or not git_utils.ref_exists(head) then
          vim.notify(
            "Unable to open PR in CodeDiff because the required refs are not available locally.",
            vim.log.levels.ERROR
          )
          return
        end

        vim.cmd(string.format("CodeDiff %s %s", base, head))

        -- Store PR context for potential future use
        vim.g.current_pr = {
          repo = item.repo,
          number = item.number,
          base = item.baseRefName,
          head = item.headRefName,
        }

        vim.notify(string.format("Opened PR #%d in CodeDiff", item.number))
      end, { item.baseRefName, item.headRefName }, { notify_success = false, use_cached_on_failure = true })
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
