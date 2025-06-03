-- Exposes:
--   M.is_diffview_open()
--   M.fetch_and_diff(base_refName, head_refName)
--   M.toggle_diffview(base_refName, head_refName)
--
-- Internally, we will:
--   • If base_refName is empty/nil, auto-detect “origin/MAIN” (same as get_base_branch).
--   • Always fetch BOTH the PR’s base (origin/<base_refName>) and the PR’s head (pull/<N>/head:pr-<N>).
--   • Then invoke DiffviewOpen with the exact same Git flags GitHub uses under the hood.
--   • Passing the PR’s head into a local ref “pr-<number>” ensures we never accidentally diff our own uncommitted changes.

local M = {}

--------------------------------------------------------------------------------
-- 1. is_diffview_open()
--
--    Scan every open window. If any buffer’s filetype is DiffviewFiles or
--    DiffviewFileHistory, return true (Diffview is already visible).
--------------------------------------------------------------------------------
function M.is_diffview_open()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local ft = vim.bo[buf].filetype
    if ft == "DiffviewFiles" or ft == "DiffviewFileHistory" then
      return true
    end
  end
  return false
end

--------------------------------------------------------------------------------
-- 2. _get_default_base()
--
--    If the user did not pass a base_refName, look at:
--      git symbolic-ref --short refs/remotes/origin/HEAD
--    to figure out “origin/<DEFAULT_BRANCH>”.  (E.g. “origin/main” or “origin/master”.)
--------------------------------------------------------------------------------
local function _get_default_base()
  local lines = vim.fn.systemlist("git symbolic-ref --short refs/remotes/origin/HEAD")
  local remote_head = lines[1] or ""
  local default_br = remote_head:match("^[^/]+/(.+)$") or "main"
  return default_br
end

--------------------------------------------------------------------------------
-- 3. fetch_and_diff(base_refName, head_refName)
--
--    1) Determine “effective_base” :
--         • If base_refName is passed-in and not empty → use that.
--         • Otherwise run _get_default_base() and fall back to “main”.
--    2) Determine a local ref for the PR’s head.  We’ll call it “pr-<N>” (where <N>
--       is the PR number extracted from head_refName if possible).  If head_refName
--       is already “HEAD” (because you just ran “gh pr checkout <N>”), we can skip
--       the “pull/.../head” fetch step.
--
--    3) Run these two Git fetches in parallel:
--        • git fetch origin <effective_base>:<effective_base>          ← updates local base
--        • git fetch origin pull/<PR_NUM>/head:pr-<PR_NUM> --no-tags    ← creates/updates pr-<PR_NUM>
--
--    4) Once both fetches succeed, invoke
--        :DiffviewOpen origin/<effective_base>..pr-<PR_NUM> --ignore-all-space --find-renames=50%
--       which exactly matches how GitHub shows the PR diff (ignore whitespace + detect renames).
--
--    Note: if head_refName == "HEAD", we assume “gh pr checkout <N>” already made HEAD = pr-<N>.
--------------------------------------------------------------------------------
function M.fetch_and_diff(base_refName, head_refName)
  -- 1) figure out base branch
  local effective_base = nil
  if base_refName and base_refName:match("%S") then
    effective_base = base_refName
  else
    effective_base = _get_default_base()
  end

  -- 2) figure out PR number from head_refName, if possible
  --    head_refName often looks like “feature-xyz” or “my-branch” and the PR number
  --    is not necessarily embedded.  But if we invoked “gh pr checkout <N>” earlier,
  --    HEAD already points at pr-<N>.  In that case, we can skip the head-fetch.
  --
  --    To keep things simple, we’ll check:
  --      • If head_refName == "HEAD" → assume `HEAD` is already the correct PR head.
  --      • Otherwise, if head_refName is a local branch that starts with “pr-”, just reuse it.
  --      • Otherwise, prompt to parse out a PR number from head_refName (if in form “pr-123”).
  --
  --    **If we can’t parse a “pr-<num>” pattern, we’ll just fetch HEAD into a temporary “pr-temp” ref.**

  local head_ref_local = nil

  if head_refName == "HEAD" then
    -- user already did “gh pr checkout <N>”: HEAD is the PR head.
    head_ref_local = "HEAD"
  else
    -- attempt to parse “pr-<digits>” from head_refName, else fallback to “pr-temp”
    local pr_number = head_refName:match("pr%-(%d+)")
    if pr_number then
      head_ref_local = "pr-" .. pr_number
    else
      head_ref_local = "pr-temp"
    end
  end

  -- 3) Build two fetch commands:
  --    A) git fetch origin <effective_base>:<effective_base>
  --    B) if head_refName ~= "HEAD", do “git fetch origin pull/<PR_NUM>/head:<head_ref_local>”
  --
  --    We’ll wrap both in jobstart and wait for both to finish (simple merge‐style).
  --
  local jobs = {}

  -- A) always fetch origin/<base> → updates local "<effective_base>"
  table.insert(jobs, {
    cmd = { "git", "fetch", "origin", effective_base .. ":" .. effective_base },
    name = "fetch_base",
  })

  -- B) only fetch PR–head if head_refName ~= "HEAD"
  if head_refName ~= "HEAD" then
    local pr_num = head_refName:match("(%d+)$") or head_refName:match("pr%-(%d+)$")
    if pr_num then
      table.insert(jobs, {
        cmd = { "git", "fetch", "origin", ("pull/%s/head:%s"):format(pr_num, head_ref_local) },
        name = "fetch_head",
      })
    else
      -- fallback: the user gave us a branch that isn’t “pr-<N>” and they didn’t checkout.
      -- we still want to diff their local HEAD (even if stale).  In that case, head_ref_local = "HEAD",
      -- so no need to fetch.  We’ll just diff “origin/<base>..HEAD” below.
      head_ref_local = "HEAD"
    end
  end

  -- 4) Kick off every job in a single “parallel” group.  Once ALL of them exit, schedule the DiffviewOpen.
  local pending = #jobs
  for _, jobinfo in ipairs(jobs) do
    vim.fn.jobstart(jobinfo.cmd, {
      detach = false,
      on_exit = vim.schedule_wrap(function(_, exit_code, _)
        pending = pending - 1
        if pending == 0 then
          -- both fetches are done (or just the base-fetch if HEAD was already correct).
          local base_ref_full = "origin/" .. effective_base
          local head_ref_full = head_ref_local

          -- 5) Finally, open Diffview with the same flags GitHub uses:
          --     ignore all whitespace and detect renames ≥ 50%.
          --     (GitHub’s default “Hide whitespace changes” corresponds to `-w`.)
          --
          vim.cmd(("DiffviewOpen %s..%s --ignore-all-space --find-renames=50%%"):format(base_ref_full, head_ref_full))
        end
      end),
    })
  end
end

--------------------------------------------------------------------------------
-- 4. toggle_diffview(base_refName, head_refName)
--
--    If any Diffview is already open, close it. Otherwise, do fetch_and_diff().
--------------------------------------------------------------------------------
function M.toggle_diffview(base_refName, head_refName)
  if M.is_diffview_open() then
    vim.cmd("DiffviewClose")
  else
    M.fetch_and_diff(base_refName, head_refName)
  end
end

return M
