local M = {}

local fns = require("custom.git.picker_fns")
local utils = require("custom.git.utils")

M.issue_picker = function()
  Snacks.picker({
    finder = fns.fetch_issues,
    format = fns.format_issue_row,
    preview = fns.preview_issue,
    confirm = function(picker, item)
      picker:close()
      -- open the browser for the selected issue using gh cli
      vim.fn.jobstart({ "gh", "issue", "view", item.number, "--web" })
    end,
  })
end

-- TODO: <S-CR> should open in browser
M.pr_picker = function()
  Snacks.picker({
    finder = fns.fetch_prs,
    format = fns.format_pr_row,
    preview = fns.preview_pr,
    confirm = function(picker, pr)
      picker:close()
      utils.confirm_stash_uncommitted_changes_before_op("Checking out PR #" .. pr.number .. ".", function()
        -- 4) Use `gh pr checkout <N> --force`
        vim.fn.jobstart({ "gh", "pr", "checkout", pr.number, "--force" }, {
          on_exit = function()
            vim.schedule(function()
              vim.notify("Checked out PR #" .. pr.number)
              require("custom.git.diff").fetch_and_diff(pr.baseRefName)
            end)
          end,
        })
      end)
    end,
  })
end

M.diff_picker = function(base_branch, head)
  Snacks.picker({
    finder = fns.custom_diff,
    format = "file",
    preview = "diff",
    base = base_branch,
    head = head,
  })
end

return M
