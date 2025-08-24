local M = {}

local fns = require("custom.git.picker_fns")
local utils = require("custom.git.utils")

-- mirror the default layout from Snacks but have the preview window wrap text
local default_layout_with_wrap = {
  layout = {
    box = "horizontal",
    width = 0.8,
    min_width = 120,
    height = 0.8,
    {
      box = "vertical",
      border = "rounded",
      title = "{title} {live} {flags}",
      { win = "input", height = 1, border = "bottom" },
      { win = "list", border = "none" },
    },
    {
      win = "preview",
      title = "{preview}",
      border = "rounded",
      width = 0.5,
      on_win = function(win)
        vim.api.nvim_set_option_value("wrap", true, { scope = "local", win = win.win })
        -- TODO: figure out why this does not work for removing line numbers
        vim.api.nvim_set_option_value("number", false, { scope = "local", win = win.win })
        vim.api.nvim_set_option_value("relativenumber", false, { scope = "local", win = win.win })
      end,
    },
  },
}

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
    layout = default_layout_with_wrap,
  })
end

M.notification_picker = function()
  Snacks.picker({
    finder = fns.fetch_notifications,
    format = fns.format_notification_row,
    layout = {
      layout = {
        box = "vertical", -- stack children top→bottom
        border = "rounded",
        height = 0.8,
        width = 0.8,
        {
          win = "input",
          height = 1,
          border = "bottom",
        },
        {
          win = "list",
        },
      },
    },
    confirm = function(picker, item)
      picker:close()
      local url = vim.fn.system({
        "gh",
        "api",
        -- get the comment URL if it exists, otherwise use the API URL
        item.comment_url ~= "" and item.comment_url or item.api_url,
        "--jq",
        ".html_url",
      })
      url = vim.trim(url) -- remove trailing newline
      if url == "" then
        vim.notify("Failed to fetch URL for notification: " .. item.title, vim.log.levels.ERROR)
        return
      end
      vim.ui.open(url)
    end,
  })
end

M.pr_picker = function()
  Snacks.picker({
    layout = default_layout_with_wrap,
    win = {
      input = {
        keys = {
          ["<S-CR>"] = { "browse", desc = "Open PR in browser", mode = { "n", "i" } },
        },
      },
      list = {
        keys = {
          ["<S-CR>"] = { "browse", desc = "Open PR in browser", mode = { "n", "i" } },
        },
      },
    },
    actions = {
      browse = function(picker, pr)
        picker:close()
        -- open the browser for the selected PR using gh cli
        vim.fn.jobstart({ "gh", "pr", "view", pr.number, "--web" })
      end,
    },
    finder = fns.fetch_prs,
    format = fns.format_pr_row,
    preview = fns.preview_pr,
    confirm = function(picker, pr)
      picker:close()
      vim.notify("Checking out PR #" .. pr.number .. " and opening in DiffView.")
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
