-- holding a version of the diff related code that was shared from a reddit post
-- this will either be deleted or integrated into the main git diff code
local M = {}

function M.Diff(spec)
  vim.cmd("vertical new")
  vim.cmd("setlocal bufhidden=wipe buftype=nofile nobuflisted noswapfile")
  local cmd = "++edit #"
  if #spec > 0 then
    cmd = "!git -C #:p:h:S show " .. spec .. ":./#:t:S"
  end
  vim.cmd("read " .. cmd)
  vim.cmd("norm! ggdd")
  vim.cmd("silent! g/fatal:/d")

  local alt = vim.fn.bufnr("#")
  local ft = vim.api.nvim_get_option_value("filetype", { buf = alt })
  vim.bo.filetype = ft

  vim.cmd("diffthis")
  vim.cmd("wincmd p")
  vim.cmd("diffthis")
end

-- Open diff of all files modified by a branch
function M.PRreview()
  local default_branch = vim.fn.trim(vim.fn.system("git rev-parse --abbrev-ref origin/HEAD | cut -c8-"))
  local merge_base =
    vim.fn.trim(vim.fn.system("git merge-base HEAD " .. default_branch .. " || echo " .. default_branch))
  local git_files = table.concat(vim.fn.systemlist("git diff --name-only --staged " .. merge_base), " ")
  vim.cmd("args " .. git_files .. " | tab all")
  vim.cmd('silent noautocmd tabdo lua require("custom.git.reddit").Diff("' .. merge_base .. '")')
end

return M
