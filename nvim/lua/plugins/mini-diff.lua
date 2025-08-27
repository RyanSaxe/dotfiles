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

local function open_diff_overlay(base_branch, n)
  local current_branch = git_utils.get_current_branch()
  git_utils.fetch_origin(function()
    local mini_diff = require("mini.diff")
    local local_ref_text
    if base_branch == "HEAD" then
      local_ref_text = git_utils.get_buffer_text_at_head(n)
    else
      local_ref_text = git_utils.get_buffer_text_on_branch(base_branch)
    end
    mini_diff.set_ref_text(0, local_ref_text)
    -- toggle on the overlay if it is not already on
    local overlay_on = mini_diff.get_buf_data(0).overlay
    if not overlay_on then
      mini_diff.toggle_overlay(0)
    end
  end, { base_branch, current_branch }) -- we also fetch current in case review a PR that got updated
end

return {
  "echasnovski/mini.diff",
  event = "VeryLazy",
  dependencies = { "folke/snacks.nvim" },
  keys = {
    -- <leader>go can be used to toggle on/off whatever ref text is set, which other commands change
    -- { "<leader>go", false }, -- disable default mapping in lazyvim
    {
      "<leader>gdo",
      function()
        open_diff_overlay("HEAD", 0)
      end,
      desc = "Overlay Diff to HEAD",
    },
    {
      "<leader>gdO",
      function()
        vim.ui.input({ prompt = "How Many Commits Back Would You Like to Compare? : " }, function(input)
          local n = tonumber(input)
          if n then
            open_diff_overlay("HEAD", n)
          else
            vim.notify("Invalid number: " .. tostring(input), vim.log.levels.WARN)
          end
        end)
      end,
      desc = "Overlay Diff to HEAD~N",
    },
    {
      "<leader>gro",
      function()
        local base_branch = git_utils.get_base_branch()
        open_diff_overlay(base_branch)
      end,
      desc = "Overlay Review to Base Branch",
    },
    {
      "<leader>grO",
      function()
        Snacks.picker.git_branches({
          prompt = "Base branch",
          confirm = function(picker, item)
            vim.notify(item)
            picker:close()
            if item then
              open_diff_overlay(item.branch or item.commit)
            else
              vim.notify("No branch selected", vim.log.levels.WARN)
            end
          end,
        })
      end,
      desc = "Overlay Review to Selected Branch",
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
