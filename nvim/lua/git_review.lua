local M = {}

---@class GitReviewContext
---@field root string
---@field repo string
---@field number integer
---@field base string
---@field head string?
---@field path string?

---@type table<integer, GitReviewContext>
local tab_contexts = {}
---@type table<string, GitReviewContext>
local root_contexts = {}
---@type table<integer, string>
local pending_paths = {}
---@type table<integer, boolean>
local pending_discovery = {}

local did_setup = false

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
---@param callback fun(context: GitReviewContext?)
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
        if not quiet then
          local subject = number and (" PR #" .. tostring(number)) or " current branch"
          notify("Could not resolve" .. subject .. ": " .. command_error(result), vim.log.levels.ERROR)
        end
        callback()
        return
      end

      local ok, data = pcall(vim.json.decode, result.stdout or "")
      if not ok or type(data) ~= "table" then
        if not quiet then
          notify("Could not parse the GitHub PR details", vim.log.levels.ERROR)
        end
        callback()
        return
      end

      local actual_number = tonumber(data.number or number)
      local base = type(data.baseRefName) == "string" and data.baseRefName or nil
      if not actual_number or not base or base == "" then
        if not quiet then
          notify("The GitHub PR did not include a base branch", vim.log.levels.ERROR)
        end
        callback()
        return
      end

      callback({
        root = normalize(root),
        repo = repo,
        number = actual_number,
        base = base,
        head = type(data.headRefName) == "string" and data.headRefName or nil,
      })
    end)
  end)
end

---@param root string
---@param branch string
---@param callback fun(path: string?, error: string?)
local function find_worktree(root, branch, callback)
  ---@param result vim.SystemCompleted
  vim.system({ "git", "worktree", "list", "--porcelain" }, { cwd = root, text = true }, function(result)
    schedule(function()
      if result.code ~= 0 then
        callback(nil, command_error(result))
        return
      end

      local current_path ---@type string?
      local found ---@type string?
      for line in (result.stdout or ""):gmatch("[^\r\n]+") do
        local path = line:match("^worktree (.+)$")
        if path then
          current_path = path
        elseif line == "branch refs/heads/" .. branch then
          found = current_path
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

  local branch = "pr-" .. tostring(context.number)
  local command = {
    "workmux",
    "add",
    "--pr",
    tostring(context.number),
    "--session",
    "--open-if-exists",
    "--name",
    branch,
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
      find_worktree(root, branch, function(path, worktree_error)
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
    root_contexts[context.root] = vim.deepcopy(context)
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

    local branch = "pr-" .. tostring(number)
    local current_branch = git_output(root, { "branch", "--show-current" })
    if current_branch == branch then
      context.root = root
      open_codediff(context)
      return
    end

    ---@param path string?
    find_worktree(root, branch, function(path)
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

---@param tabpage integer
local function install_codediff_keymap(tabpage)
  local lifecycle = require("codediff.ui.lifecycle")
  lifecycle.set_tab_keymap(tabpage, "n", "<localleader>c", function()
    M.open_snacks(tabpage)
  end, { desc = "Open PR diff in Snacks" })
end

---@param tabpage integer
---@param context GitReviewContext
local function attach_context(tabpage, context)
  local attached = vim.deepcopy(context)
  attached.path = pending_paths[tabpage] or session_path(tabpage) or attached.path
  tab_contexts[tabpage] = attached
  pending_paths[tabpage] = nil
  install_codediff_keymap(tabpage)
end

---@param tabpage integer
---@param root string
local function discover_context(tabpage, root)
  if pending_discovery[tabpage] then
    return
  end
  pending_discovery[tabpage] = true

  local repo = remote_repo(root)
  if not repo then
    pending_discovery[tabpage] = nil
    return
  end

  ---@param context GitReviewContext?
  fetch_pr_context(root, repo, nil, true, function(context)
    pending_discovery[tabpage] = nil
    local lifecycle = require("codediff.ui.lifecycle")
    local session = lifecycle.get_session(tabpage)
    if not session or session.git_root == nil or normalize(session.git_root) ~= root or not context then
      return
    end

    root_contexts[root] = context
    attach_context(tabpage, context)
  end)
end

---@param event vim.api.keyset.create_autocmd.callback_args
local function on_codediff_open(event)
  local data = event.data
  local tabpage = data and data.tabpage
  if type(tabpage) ~= "number" then
    return
  end

  local lifecycle = require("codediff.ui.lifecycle")
  local session = lifecycle.get_session(tabpage)
  if not session or not session.git_root then
    return
  end

  local root = normalize(session.git_root)
  local context = root_contexts[root]
  if context then
    attach_context(tabpage, context)
  else
    discover_context(tabpage, root)
  end
end

---@param event vim.api.keyset.create_autocmd.callback_args
local function on_codediff_file_select(event)
  local data = event.data
  local tabpage = data and data.tabpage
  local path = data and data.path
  if type(tabpage) ~= "number" or type(path) ~= "string" or path == "" then
    return
  end

  local context = tab_contexts[tabpage]
  if context then
    context.path = path
    install_codediff_keymap(tabpage)
  else
    pending_paths[tabpage] = path
  end
end

---@param event vim.api.keyset.create_autocmd.callback_args
local function on_codediff_close(event)
  local data = event.data
  local tabpage = data and data.tabpage
  if type(tabpage) ~= "number" then
    return
  end

  local context = tab_contexts[tabpage]
  tab_contexts[tabpage] = nil
  pending_paths[tabpage] = nil
  pending_discovery[tabpage] = nil
  if context and root_contexts[context.root] and root_contexts[context.root].number == context.number then
    root_contexts[context.root] = nil
  end
end

---@param tabpage integer
function M.open_snacks(tabpage)
  local context = tab_contexts[tabpage]
  if not context then
    notify("This CodeDiff view is not associated with a pull request", vim.log.levels.WARN)
    return
  end

  local opts = {
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

function M.setup()
  if did_setup then
    return
  end
  did_setup = true

  local actions = require("snacks.gh.actions")
  actions.actions.open_in_codediff = {
    desc = "Open in CodeDiff",
    title = "Open PR #{number} in CodeDiff",
    priority = 150,
    type = "pr",
    ---@param item snacks.picker.gh.Item
    action = function(item)
      M.open_in_codediff(item)
    end,
  }

  local group = vim.api.nvim_create_augroup("git_review_surfaces", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffOpen",
    callback = on_codediff_open,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffFileSelect",
    callback = on_codediff_file_select,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffClose",
    callback = on_codediff_close,
  })
end

return M
