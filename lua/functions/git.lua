-- utility functions to help with some git operations

local M = {}

M.get_base_branch = function()
  local lines = vim.fn.systemlist("git symbolic-ref --short refs/remotes/origin/HEAD")
  local remote_head = lines[1] or ""
  local default_branch = remote_head:match("^[^/]+/(.+)$") or "main"
  return "origin/" .. default_branch
end

M.has_uncommitted_changes = function()
  local result = vim.fn.system("git status --porcelain")
  return result and result:match("%S") ~= nil
end

M.confirm_stash_uncommitted_changes_before_op = function(message, callback)
  if M.has_uncommitted_changes() then
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

return M
