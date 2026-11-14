-- The one status line, at the bottom, on the buffer's background. It holds
-- only what is global: the focused file's branch and its repository's state
-- on the left, and the state dot and mode capital on the right. Each split's
-- own facts are in its winbar.
local M = {}

---@param group string
---@param text string
---@return string
local function paint(group, text)
  return "%#" .. group .. "#" .. text
end

---@param s string
---@return string
local function esc(s)
  return (s:gsub("%%", "%%%%"))
end

-- Each mode's letter, and the group for what you're doing in it.
---@type table<string, [string, string]>
local MODES = {
  n = { "N", "ThemeStlMove" },
  no = { "O", "ThemeStlMove" }, -- an operator waiting for its motion
  i = { "I", "ThemeStlSend" },
  R = { "R", "ThemeStlSend" },
  t = { "T", "ThemeStlWait" }, -- a terminal stands out in the command line's color
  ni = { "N", "ThemeStlSend" }, -- one Normal command from Insert, via Ctrl-O
  v = { "V", "ThemeStlSelect" },
  V = { "L", "ThemeStlSelect" },
  ["\22"] = { "B", "ThemeStlSelect" },
  s = { "S", "ThemeStlSelect" },
  S = { "S", "ThemeStlSelect" },
  ["\19"] = { "S", "ThemeStlSelect" },
  c = { ":", "ThemeStlWait" },
}

---@return string letter, string group
local function mode()
  local m = vim.api.nvim_get_mode().mode
  local hit = MODES[m:sub(1, 2)] or MODES[m:sub(1, 1)] or MODES.n
  return hit[1], hit[2]
end

---@class theme.RepoState
---@field branch string the branch's name, or the commit's short hash when detached
---@field detached boolean
---@field upstream boolean whether the branch has ever been pushed
---@field ahead integer
---@field behind integer
---@field changed integer paths staged, changed or untracked
---@field stash integer
---@field operation? string a rebase, merge, cherry-pick, revert or bisect in progress

-- Each repository's state, by its root folder. The status line shows the
-- focused file's own repository, so files from two repositories each show
-- theirs. git runs off the UI thread, and a render only reads this table.
---@type table<string, theme.RepoState>
local states = {}

-- The repository's git folder: `.git` itself, or for a worktree the folder
-- its `.git` file points to. That's where git keeps an operation's state.
---@param root string
---@return string?
local function git_dir(root)
  local dot_git = root .. "/.git"
  local stat = vim.uv.fs_stat(dot_git)
  if stat and stat.type == "directory" then
    return dot_git
  end
  local file = io.open(dot_git)
  if not file then
    return nil
  end
  local pointer = file:read("*l") or ""
  file:close()
  local dir = pointer:match("^gitdir: (.+)$")
  if dir and not dir:match("^/") then
    dir = root .. "/" .. dir
  end
  return dir
end

---@param path string
---@return integer?
local function read_number(path)
  local file = io.open(path)
  if not file then
    return nil
  end
  local n = tonumber(file:read("*l"))
  file:close()
  return n
end

-- What git is in the middle of, with its step for a rebase, as `git status`
-- itself words it. A rebase also names the branch it is rebasing, which a
-- detached HEAD would otherwise hide.
---@param root string
---@return string? operation, string? branch
local function operation(root)
  local dir = git_dir(root)
  if not dir then
    return nil
  end
  for _, rebase in ipairs({ { "rebase-merge", "msgnum", "end" }, { "rebase-apply", "next", "last" } }) do
    local folder = dir .. "/" .. rebase[1]
    if vim.uv.fs_stat(folder) then
      local step, total = read_number(folder .. "/" .. rebase[2]), read_number(folder .. "/" .. rebase[3])
      local head = io.open(folder .. "/head-name")
      local branch = head and (head:read("*l") or ""):match("^refs/heads/(.+)$")
      if head then
        head:close()
      end
      return step and total and ("rebasing %d/%d"):format(step, total) or "rebasing", branch
    end
  end
  for _, marker in ipairs({
    { "MERGE_HEAD", "merging" },
    { "CHERRY_PICK_HEAD", "cherry-picking" },
    { "REVERT_HEAD", "reverting" },
    { "BISECT_LOG", "bisecting" },
  }) do
    if vim.uv.fs_stat(dir .. "/" .. marker[1]) then
      return marker[2]
    end
  end
  return nil
end

---@param porcelain string `git status --porcelain=v2 --branch --show-stash`
---@return theme.RepoState
local function parse(porcelain)
  ---@type theme.RepoState
  local state = { branch = "", detached = false, upstream = false, ahead = 0, behind = 0, changed = 0, stash = 0 }
  local oid = ""
  for line in porcelain:gmatch("[^\n]+") do
    local key, value = line:match("^# (%S+) (.*)$")
    if key == "branch.oid" then
      oid = value
    elseif key == "branch.head" then
      state.branch = value
    elseif key == "branch.upstream" then
      state.upstream = true
    elseif key == "branch.ab" then
      local ahead, behind = value:match("^%+(%d+) %-(%d+)$")
      state.ahead, state.behind = tonumber(ahead) or 0, tonumber(behind) or 0
    elseif key == "stash" then
      state.stash = tonumber(value) or 0
    elseif not key then
      state.changed = state.changed + 1
    end
  end
  if state.branch == "(detached)" then
    state.detached = true
    state.branch = oid:sub(1, 7)
  end
  return state
end

-- The branch, then only what's unusual about the repository, all in the
-- branch's gray. As in the prompt, only the branch name takes a color, and
-- only when something needs you: peach when there are commits to pull, and
-- yellow mid-operation or on a detached HEAD. Red stays for errors.
---@param state theme.RepoState
---@return string
local function describe(state)
  local name = "ThemeStlBranch"
  if state.operation or state.detached then
    name = "ThemeStlAttention"
  elseif state.behind > 0 then
    name = "ThemeStlBehind"
  end
  local parts = { paint(name, esc(state.branch)) }
  local function add(text)
    parts[#parts + 1] = paint("ThemeStlBranch", text)
  end
  if state.operation then
    add(state.operation)
  end
  if state.ahead > 0 then
    add("⇡" .. state.ahead)
  end
  if state.behind > 0 then
    add("⇣" .. state.behind)
  end
  if state.changed > 0 then
    add("~" .. state.changed)
  end
  if state.stash > 0 then
    add("$" .. state.stash)
  end
  if not state.upstream and not state.detached then
    add("unpushed")
  end
  return table.concat(parts, " ")
end

---@return string
function M.render()
  local letter, group = mode()
  -- The dot breathes red while a macro records, and wears the mode's
  -- color otherwise.
  local dot = require("theme.pulse").frame() or group
  local root = vim.fs.root(0, ".git")
  local state = root and states[root]
  local left = state and (" " .. describe(state)) or ""
  return left .. "%=" .. paint(dot, "●") .. " " .. paint(group, letter) .. " "
end

---@type table<string, true>
local running = {}
---@type table<string, true>
local again = {}

-- Reads one repository's state again. A request while git is still running
-- for that repository runs once more when it finishes, so none is lost.
---@param root string
local function refresh(root)
  if running[root] then
    again[root] = true
    return
  end
  running[root] = true
  vim.system(
    { "git", "-C", root, "--no-optional-locks", "status", "--porcelain=v2", "--branch", "--show-stash" },
    { text = true },
    ---@param out vim.SystemCompleted
    function(out)
      vim.schedule(function()
        running[root] = nil
        if out.code == 0 then
          local state = parse(out.stdout or "")
          local rebasing_branch
          state.operation, rebasing_branch = operation(root)
          state.branch = rebasing_branch or state.branch
          states[root] = state
        else
          states[root] = nil
        end
        vim.cmd.redrawstatus()
        if again[root] then
          again[root] = nil
          refresh(root)
        end
      end)
    end
  )
end

---@param buf integer
local function refresh_buf(buf)
  local root = vim.fs.root(buf, ".git")
  if root then
    refresh(root)
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("theme_statusline", { clear = true })
  -- Entering a file reads its repository, so a commit or checkout made
  -- elsewhere shows as soon as you move to one of its files.
  vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained", "BufWritePost", "ShellCmdPost" }, {
    group = group,
    callback = function(ev)
      refresh_buf(ev.buf)
    end,
  })
  -- A git command run in a terminal inside Neovim, read for the file you
  -- return to.
  vim.api.nvim_create_autocmd("TermClose", {
    group = group,
    callback = function()
      vim.schedule(function()
        refresh_buf(vim.api.nvim_get_current_buf())
      end)
    end,
  })
  refresh_buf(0)
end

return M
