local M = {}

---@class GitReviewContext
---@field root string
---@field repo string
---@field number integer
---@field base string
---@field head string?
---@field path string?

---@param message string
---@param level? integer
local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Git review" })
end

---@param callback fun()
local function schedule(callback)
  vim.schedule(callback)
end

---@param root string
---@param args string[]
---@return string?
local function git_output(root, args)
  local command = { "git" }
  vim.list_extend(command, args)
  local result = vim.system(command, { cwd = root, text = true }):wait()
  if result.code ~= 0 then
    return nil
  end

  local output = vim.trim(result.stdout or "")
  return output ~= "" and output or nil
end

---@param path string
---@return string
local function normalize(path)
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

---@return string?
local function current_git_root()
  local name = vim.api.nvim_buf_get_name(0)
  if name ~= "" and not name:match("^[%w+.-]+://") then
    local root = vim.fs.root(0, { ".git" })
    if root then
      return normalize(root)
    end
  end

  local cwd = vim.uv.cwd() or vim.fn.getcwd()
  local root = git_output(cwd, { "rev-parse", "--show-toplevel" })
  return root and normalize(root) or nil
end

---@param root string
---@return string?
local function remote_repo(root)
  local remote = git_output(root, { "remote", "get-url", "origin" })
  if not remote then
    return nil
  end

  remote = remote:gsub("%.git$", "")
  local repo = remote:match("github%.com[:/]([^/]+/[^/]+)$")
  return repo and repo:lower() or nil
end

---@param result vim.SystemCompleted
---@return string
local function command_error(result)
  local detail = vim.trim(result.stderr or "")
  if detail == "" then
    detail = vim.trim(result.stdout or "")
  end
  return detail ~= "" and detail or "unknown error"
end

---@param root string
---@param repo string
---@param number integer?
---@param quiet boolean
---@param callback fun(context: GitReviewContext?, error_message: string?)
local function fetch_pr_context(root, repo, number, quiet, callback)
  local args = { "gh", "pr", "view" }
  if number then
    args[#args + 1] = tostring(number)
  end
  vim.list_extend(args, { "--repo", repo, "--json", "number,baseRefName,headRefName" })

  ---@param result vim.SystemCompleted
  vim.system(args, { cwd = root, text = true }, function(result)
    schedule(function()
      if result.code ~= 0 then
        local detail = command_error(result)
        if not quiet then
          local subject = number and (" PR #" .. tostring(number)) or " current branch"
          notify("Could not resolve" .. subject .. ": " .. detail, vim.log.levels.ERROR)
        end
        callback(nil, detail)
        return
      end

      local ok, data = pcall(vim.json.decode, result.stdout or "")
      if not ok or type(data) ~= "table" then
        local detail = "invalid GitHub response"
        if not quiet then
          notify("Could not parse the GitHub PR details", vim.log.levels.ERROR)
        end
        callback(nil, detail)
        return
      end

      local actual_number = tonumber(data.number or number)
      local base = type(data.baseRefName) == "string" and data.baseRefName or nil
      if not actual_number or not base or base == "" then
        local detail = "the GitHub PR did not include a base branch"
        if not quiet then
          notify("The GitHub PR did not include a base branch", vim.log.levels.ERROR)
        end
        callback(nil, detail)
        return
      end

      callback({
        root = normalize(root),
        repo = repo,
        number = actual_number,
        base = base,
        head = type(data.headRefName) == "string" and data.headRefName or nil,
      }, nil)
    end)
  end)
end

---@param root string
---@param name string
---@param callback fun(path: string?, error: string?)
local function find_worktree(root, name, callback)
  ---@param result vim.SystemCompleted
  vim.system({ "git", "worktree", "list", "--porcelain" }, { cwd = root, text = true }, function(result)
    schedule(function()
      if result.code ~= 0 then
        callback(nil, command_error(result))
        return
      end

      local found ---@type string?
      for line in (result.stdout or ""):gmatch("[^\r\n]+") do
        local path = line:match("^worktree (.+)$")
        if path and vim.fs.basename(path) == name then
          found = path
          break
        end
      end

      callback(found and normalize(found) or nil)
    end)
  end)
end

---@param root string
---@param base string
---@param callback fun(ref: string)
local function ensure_base_ref(root, base, callback)
  local ref = "origin/" .. base
  if git_output(root, { "rev-parse", "--verify", "--quiet", ref }) then
    callback(ref)
    return
  end

  ---@param result vim.SystemCompleted
  vim.system({ "git", "fetch", "origin", base }, { cwd = root, text = true }, function(result)
    schedule(function()
      if result.code ~= 0 then
        notify("Could not fetch the PR base branch " .. base .. ": " .. command_error(result), vim.log.levels.ERROR)
        return
      end
      if not git_output(root, { "rev-parse", "--verify", "--quiet", ref }) then
        notify("The PR base branch is unavailable: " .. ref, vim.log.levels.ERROR)
        return
      end
      callback(ref)
    end)
  end)
end

---@param repo string
---@param number integer
---@return string
local function workmux_target(repo, number)
  local project = repo:match("/([^/]+)$") or repo ---@type string
  local slug = project:lower():gsub("[^a-z0-9]+", "-"):gsub("^-+", ""):gsub("%-+$", "") ---@type string
  return slug .. "-pr-" .. tostring(number)
end

---@param root string
---@param context GitReviewContext
---@param callback fun(path: string?)
local function create_worktree(root, context, callback)
  if vim.fn.executable("workmux") == 0 then
    notify("workmux is required to open a PR from the main checkout", vim.log.levels.ERROR)
    callback()
    return
  end

  local name = "pr-" .. tostring(context.number)
  local command = {
    "workmux",
    "add",
    "--pr",
    tostring(context.number),
    "--session",
    "--open-if-exists",
    "--name",
    name,
    "--target-name",
    workmux_target(context.repo, context.number),
    "--background",
    "--no-pane-cmds",
  }

  ---@param result vim.SystemCompleted
  vim.system(command, { cwd = root, text = true }, function(result)
    schedule(function()
      ---@param path string?
      ---@param worktree_error string?
      find_worktree(root, name, function(path, worktree_error)
        if path then
          callback(path)
          return
        end

        local detail = worktree_error or (result.code ~= 0 and command_error(result)) or "worktree was not created"
        notify("Could not create the PR worktree: " .. detail, vim.log.levels.ERROR)
        callback()
      end)
    end)
  end)
end

---@param context GitReviewContext
local function open_codediff(context)
  ---@param ref string
  ensure_base_ref(context.root, context.base, function(ref)
    local ok, error_message = pcall(function()
      vim.cmd({
        cmd = "CodeDiff",
        args = { "--repo", context.root, ref .. "..." },
      })
    end)
    if not ok then
      notify("Could not open CodeDiff: " .. tostring(error_message), vim.log.levels.ERROR)
    end
  end)
end

---@param item snacks.picker.gh.Item
function M.open_in_codediff(item)
  if not item or item.type ~= "pr" then
    return
  end

  local root = current_git_root()
  if not root then
    notify("Open the PR from inside a Git repository", vim.log.levels.ERROR)
    return
  end

  local repo = item.repo
  if not repo then
    notify("The PR has no repository information", vim.log.levels.ERROR)
    return
  end

  local actual_repo = remote_repo(root)
  if not actual_repo then
    notify("The current checkout has no GitHub origin remote", vim.log.levels.ERROR)
    return
  end
  if actual_repo ~= repo:lower() then
    notify(
      ("Current checkout is %s, but PR #%s belongs to %s"):format(actual_repo, item.number, repo),
      vim.log.levels.ERROR
    )
    return
  end

  local number = tonumber(item.number)
  if not number then
    notify("The PR number is invalid", vim.log.levels.ERROR)
    return
  end

  ---@param context GitReviewContext?
  fetch_pr_context(root, repo, number, false, function(context)
    if not context then
      return
    end

    local worktree_name = "pr-" .. tostring(number)
    local current_branch = git_output(root, { "branch", "--show-current" })
    if current_branch == worktree_name then
      context.root = root
      open_codediff(context)
      return
    end

    ---@param path string?
    find_worktree(root, worktree_name, function(path)
      if path then
        context.root = path
        open_codediff(context)
        return
      end

      ---@param worktree string?
      create_worktree(root, context, function(worktree)
        if not worktree then
          return
        end
        context.root = worktree
        open_codediff(context)
      end)
    end)
  end)
end

---@param tabpage integer
---@return string?
local function session_root(tabpage)
  local lifecycle = require("codediff.ui.lifecycle")
  local session = lifecycle.get_session(tabpage)
  return session and session.git_root and normalize(session.git_root) or nil
end

---@param tabpage integer
---@return string?
local function session_path(tabpage)
  local lifecycle = require("codediff.ui.lifecycle")
  local original, modified = lifecycle.get_paths(tabpage)
  if modified and modified.relative ~= "" then
    return modified.relative
  end
  if original and original.relative ~= "" then
    return original.relative
  end
end

---@param root string
---@return integer?
local function worktree_pr_number(root)
  local branch = git_output(root, { "branch", "--show-current" })
  local number = branch and branch:match("pr%-(%d+)$")
  return number and tonumber(number) or nil
end

---@param context GitReviewContext
local function open_snacks_for_context(context)
  local opts = {
    cwd = context.root,
    show_delay = 0,
    repo = context.repo,
    pr = context.number,
    group = false,
    title = ("PR #%d · %s"):format(context.number, context.path or "all files"),
  }
  if context.path then
    opts.pattern = context.path .. ":"
  end
  Snacks.picker.gh_diff(opts)
end

---@param tabpage integer
function M.open_snacks(tabpage)
  local root = session_root(tabpage)
  if not root then
    notify("This CodeDiff view is not associated with a pull request", vim.log.levels.WARN)
    return
  end

  local repo = remote_repo(root)
  if not repo then
    notify("This CodeDiff view is not associated with a GitHub repository", vim.log.levels.WARN)
    return
  end

  local number = worktree_pr_number(root)
  ---@param context GitReviewContext?
  fetch_pr_context(root, repo, number, true, function(context)
    if not context then
      notify("This CodeDiff view is not associated with a pull request", vim.log.levels.WARN)
      return
    end

    context.root = root
    context.path = session_path(tabpage)
    open_snacks_for_context(context)
  end)
end

function M.setup()
  local actions = require("snacks.gh.actions")
  actions.actions.open_in_codediff = {
    desc = "Open in CodeDiff",
    icon = "󰦓 ",
    title = "Open PR #{number} in CodeDiff",
    priority = 150,
    type = "pr",
    ---@param item snacks.picker.gh.Item
    action = function(item)
      M.open_in_codediff(item)
    end,
  }
end

return M
