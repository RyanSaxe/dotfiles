-- utility functions to help with some git operations

local M = {}

M.get_username = function()
  local username = vim.fn.system("gh api user -q .login")
  return username and username:match("^%s*(.-)%s*$") or ""
end

M.get_base_branch = function()
  local lines = vim.fn.systemlist("git symbolic-ref --short refs/remotes/origin/HEAD")
  local remote_head = lines[1] or ""
  local default_branch = remote_head:match("^[^/]+/(.+)$") or "main"
  return default_branch
end

M.get_current_branch = function()
  local lines = vim.fn.systemlist("git rev-parse --abbrev-ref HEAD")
  return lines[1] or ""
end

M.checkout_branch = function(branch)
  if not branch or branch == "" then
    vim.notify("⚠️  No branch specified for checkout.", vim.log.levels.WARN)
    return
  end

  local cmd = { "git", "checkout", branch }
  M.confirm_stash_uncommitted_changes_before_op("Checking out branch '" .. branch .. "'.", function()
    vim.fn.system(cmd)
  end)
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

--- Fetch origin asynchronously, with optional specific refs and notifications.
-- @param refs (optional) table of strings, e.g. { "main", "feature/x" }
-- @param cb (optional) function to run after a successful fetch
function M.fetch_origin(cb, refs)
  local cmd = { "git", "fetch", "origin" }
  if refs then
    for _, ref in ipairs(refs) do
      table.insert(cmd, ref)
    end
  end

  -- local label = refs and ("🔄 Fetching origin " .. table.concat(refs, ", ")) or "🔄 Fetching origin (all branches)"
  -- vim.notify(label, vim.log.levels.INFO)
  -- vim.notify(vim.inspect(cmd), vim.log.levels.DEBUG)
  --
  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stderr = function(_, data)
      if data and #data > 0 then
        vim.schedule(function()
          vim.notify(table.concat(data, "\n"), vim.log.levels.WARN)
        end)
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 then
          vim.notify("✅ git fetch origin completed", vim.log.levels.INFO)
          if cb then
            pcall(cb)
          end
        else
          vim.notify(string.format("❌ git fetch origin failed (exit code %d)", code), vim.log.levels.ERROR)
        end
      end)
    end,
  })
end

-- Return the current buffer's file content as it was at local HEAD~N
function M.get_buffer_text_at_head(n)
  -- n = 0 → HEAD, n = 1 → HEAD~1, etc.
  n = tonumber(n) or 0
  if n < 0 then
    n = 0
  end

  -- Path relative to the repo root (same as your other fn)
  local relpath = vim.fn.expand("%:.")

  -- Build the revspec
  local rev = (n == 0) and "HEAD" or string.format("HEAD~%d", n)

  -- Show file at that rev; silence errors
  local cmd = string.format("git show %s:%s 2>/dev/null", vim.fn.shellescape(rev), vim.fn.shellescape(relpath))
  local lines = vim.fn.systemlist(cmd)

  -- If git failed (e.g., file didn’t exist then), return empty
  if vim.v.shell_error ~= 0 then
    return ""
  end

  return table.concat(lines, "\n")
end
--- Get the text of the current buffer's file as it exists on `branch`.
-- Returns an empty string if the file doesn’t exist there.
function M.get_buffer_text_on_branch(branch)
  -- 1) figure out the path *relative* to the repo root
  local relpath = vim.fn.expand("%:.") -- e.g. "src/foo/bar.lua"
  -- 2) build and run the git-show command, silencing errors
  local cmd =
    string.format("git show origin/%s:%s 2>/dev/null", vim.fn.shellescape(branch), vim.fn.shellescape(relpath))
  local lines = vim.fn.systemlist(cmd)
  -- 3) if git failed (file not present), systemlist still returns {}, but
  --    vim.v.shell_error will be non-zero
  if vim.v.shell_error ~= 0 then
    return ""
  end
  -- 4) join lines back into one string
  return table.concat(lines, "\n")
end

return M
