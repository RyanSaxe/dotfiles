local M = {}

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

function M.fetch_and_diff(base_ref)
  local effective_ref = base_ref
  -- if no base_ref is given, find the default branch from origin/HEAD
  if not effective_ref or effective_ref == "" then
    local lines = vim.fn.systemlist("git symbolic-ref --short refs/remotes/origin/HEAD")
    local remote_head = lines[1] or ""
    local default_branch = remote_head:match("^[^/]+/(.+)$") or "main"
    effective_ref = default_branch
  end

  local base = ("origin/%s"):format(effective_ref)
  -- NOTE: effective_ref : effective_ref will actually update the local ref to match the remote ref
  vim.fn.jobstart({ "git", "fetch", "origin", effective_ref, ":", effective_ref }, {
    detach = false,
    on_exit = function()
      vim.schedule(function()
        -- could do DiffviewOpen base.."..HEAD",
        -- but that will miss any unstaged files and not show diagnostics in the diffview
        vim.cmd(("DiffviewOpen %s"):format(base))
      end)
    end,
  })
end

function M.toggle_diffview(base_ref)
  if M.is_diffview_open() then
    vim.cmd("DiffviewClose")
  else
    M.fetch_and_diff(base_ref)
  end
end

return M
