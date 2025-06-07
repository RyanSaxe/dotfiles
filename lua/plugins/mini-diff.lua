local git_utils = require("custom.git.utils")
-- gdo : Git Diff Overlay to base branch
-- gdO : Git Diff Overlay to branch of your choice (pass HEAD for normal git diff)
-- gds : Git Diff Split to base branch
-- gdS : Git Diff Split to branch of your choice (pass HEAD for normal git diff)
-- gdv : Git Diff View all files to base branch -- opens diffview
-- gdV : Git Diff View all files to branch of your choice (pass HEAD for normal git diff) -- opens diffview
-- gdC : make a comment on github for the whole file
-- gdc :
--   visual mode: make a comment on github for the selected lines
--   normal mode: make a comment on github for the line the cursor is on

local function open_diff_overlay(base_branch)
  local current_branch = git_utils.get_current_branch()
  git_utils.fetch_origin(function()
    local mini_diff = require("mini.diff")
    local local_ref_text = git_utils.get_buffer_text_on_branch(base_branch)
    mini_diff.set_ref_text(0, local_ref_text)
    mini_diff.toggle_overlay(0)
  end, { base_branch, current_branch }) -- we also fetch current in case review a PR that got updated
end

return {
  "echasnovski/mini.diff",
  event = "VeryLazy",
  dependencies = { "folke/snacks.nvim" },
  keys = {
    { "<leader>go", false }, -- disable default mapping in lazyvim
    {
      "<leader>gdo",
      function()
        local base_branch = git_utils.get_base_branch()
        open_diff_overlay(base_branch)
      end,
      desc = "Overlay Diff to Base Branch",
    },
    {
      "<leader>gdO",
      function()
        Snacks.picker.git_branches({
          prompt = "Base branch (HEAD for normal git diff): ",
          confirm = function(picker, item)
            picker:close()
            if item then
              open_diff_overlay(item.branch or item.commit)
            else
              vim.notify("No branch selected", vim.log.levels.WARN)
            end
          end,
        })
      end,
      desc = "Overlay Diff to Branch",
    },
  },
  -- opts = {
  --   view = {
  --     -- Visualization style. Possible values are 'sign' and 'number'.
  --     -- Default: 'number' if line numbers are enabled, 'sign' otherwise.
  --     style = vim.go.number and "number" or "sign",
  --
  --     -- Signs used for hunks with 'sign' view
  --     signs = { add = "▒", change = "▒", delete = "▒" },
  --
  --     -- Priority of used visualization extmarks
  --     priority = 199,
  --   },
  -- },
}
