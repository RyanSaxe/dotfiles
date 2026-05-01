-- gh.lua  ── Custom GitHub actions for snacks.nvim
-- Adds custom actions to the GitHub picker action menu

local M = {}
local git_utils = require("custom.git.utils")

local function collect_output_lines(target, data)
  if not data then
    return
  end

  for _, line in ipairs(data) do
    if line and line ~= "" then
      table.insert(target, line)
    end
  end
end

local function open_checked_out_pr_in_codediff(item)
  local base_ref_name = item.baseRefName
  if not base_ref_name or base_ref_name == "" then
    vim.notify("Unable to open PR in CodeDiff because the PR base branch is unknown.", vim.log.levels.ERROR)
    return
  end

  git_utils.fetch_origin(function()
    local base = git_utils.resolve_branch_ref(base_ref_name)
    if not git_utils.ref_exists(base) then
      vim.notify("Unable to open PR in CodeDiff because the base ref is unavailable: " .. base, vim.log.levels.ERROR)
      return
    end

    vim.cmd("CodeDiff " .. vim.fn.fnameescape(base .. "..."))

    vim.g.current_pr = {
      repo = item.repo,
      number = item.number,
      base = item.baseRefName,
      head = item.headRefName,
    }

    vim.notify(string.format("Checked out and opened PR #%d in CodeDiff", item.number))
  end, { base_ref_name }, { notify_success = false, use_cached_on_failure = true })
end

local function checkout_pr_then_open_codediff(item)
  local stderr = {}
  local stdout = {}

  vim.notify(string.format("Checking out PR #%d...", item.number), vim.log.levels.INFO)
  vim.fn.jobstart({ "gh", "pr", "checkout", tostring(item.number) }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      collect_output_lines(stdout, data)
    end,
    on_stderr = function(_, data)
      collect_output_lines(stderr, data)
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code ~= 0 then
          local msg = table.concat(stderr, "\n")
          if msg == "" then
            msg = table.concat(stdout, "\n")
          end
          if msg == "" then
            msg = string.format("gh pr checkout failed (exit code %d)", code)
          end
          vim.notify(msg, vim.log.levels.ERROR)
          return
        end

        open_checked_out_pr_in_codediff(item)
      end)
    end,
  })
end

-- Define custom GitHub actions
M.custom_actions = {
  -- Open PR in CodeDiff
  open_in_codediff = {
    desc = "Open PR in CodeDiff",
    icon = "󰊢",
    type = "pr",
    priority = 150,
    action = function(item, _ctx)
      if not item then
        return
      end

      local current_repo = git_utils.get_origin_repo()
      if not current_repo then
        vim.notify("Unable to validate GitHub repo from origin remote.", vim.log.levels.ERROR)
        return
      end

      if current_repo ~= item.repo then
        vim.notify(
          string.format("Open PR in CodeDiff must run from %s, but this clone is %s.", item.repo, current_repo),
          vim.log.levels.ERROR
        )
        return
      end

      git_utils.confirm_stash_uncommitted_changes_before_op(
        string.format("Checking out PR #%d from %s.", item.number, item.repo),
        function()
          checkout_pr_then_open_codediff(item)
        end
      )
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
