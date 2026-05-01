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

M.get_origin_repo = function()
  local remote = (vim.fn.systemlist({ "git", "remote", "get-url", "origin" })[1] or ""):gsub("%.git$", "")
  local owner, repo = remote:match("github%.com[:/](.-)/(.-)$")
  if owner and repo then
    return owner .. "/" .. repo
  end
  return nil
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

--- Fetch origin asynchronously, with optional specific refs and cached-ref fallback.
-- @param cb (optional) function(success:boolean, err:string|nil) run after fetch or fallback
-- @param refs (optional) table of strings, e.g. { "main", "feature/x" }
-- @param opts (optional) table:
--   - notify_success: boolean (default: true)
--   - use_cached_on_failure: boolean (default: false)
function M.fetch_origin(cb, refs, opts)
  opts = opts or {}
  local cmd = { "git", "fetch", "origin" }
  local stderr = {}

  if refs then
    for _, ref in ipairs(refs) do
      table.insert(cmd, ref)
    end
  end

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stderr = function(_, data)
      collect_output_lines(stderr, data)
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        local err = table.concat(stderr, "\n")

        if code == 0 then
          if opts.notify_success ~= false then
            vim.notify("✅ git fetch origin completed", vim.log.levels.INFO)
          end
          if cb then
            pcall(cb, true)
          end
        elseif opts.use_cached_on_failure then
          local msg = err ~= "" and err or string.format("git fetch origin failed (exit code %d)", code)
          vim.notify("Using cached git refs because fetch failed.\n" .. msg, vim.log.levels.WARN)
          if cb then
            pcall(cb, false, msg)
          end
        else
          local msg = err ~= "" and err or string.format("git fetch origin failed (exit code %d)", code)
          vim.notify(msg, vim.log.levels.ERROR)
        end
      end)
    end,
  })
end

function M.ref_exists(ref)
  if not ref or ref == "" then
    return false
  end

  vim.fn.system({ "git", "rev-parse", "--verify", "--quiet", ref })
  return vim.v.shell_error == 0
end

function M.resolve_branch_ref(branch)
  if not branch or branch == "" then
    return branch
  end

  if branch:match("^origin/") then
    if M.ref_exists(branch) then
      return branch
    end

    local local_branch = branch:gsub("^origin/", "")
    if M.ref_exists(local_branch) then
      return local_branch
    end

    return branch
  end

  local remote_branch = "origin/" .. branch
  if M.ref_exists(remote_branch) then
    return remote_branch
  end

  if M.ref_exists(branch) then
    return branch
  end

  return remote_branch
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
  local ref = M.resolve_branch_ref(branch)

  -- 1) figure out the path *relative* to the repo root
  local relpath = vim.fn.expand("%:.") -- e.g. "src/foo/bar.lua"
  -- 2) build and run the git-show command, silencing errors
  local cmd = string.format("git show %s:%s 2>/dev/null", vim.fn.shellescape(ref), vim.fn.shellescape(relpath))
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
