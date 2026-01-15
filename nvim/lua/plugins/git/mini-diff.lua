-- mini.diff - Inline git hunks with overlay support
-- Keymaps use snacks.nvim pickers for commit/branch selection with diff previews
--
-- Overlay keymaps:
--   gdo - Overlay diff: pick a commit (most recent first = HEAD)
--   gdO - Overlay diff: pick a branch (base branch highlighted)

local git_utils = require("custom.git.utils")
local pickers = require("custom.git.pickers")

-- Open diff overlay comparing current buffer against a ref
local function open_overlay_for_ref(ref, is_branch)
  local mini_diff = require("mini.diff")

  -- Get the reference text
  local ref_text
  if is_branch then
    ref_text = git_utils.get_buffer_text_on_branch(ref)
  else
    -- ref is a commit hash, use git show
    local relpath = vim.fn.expand("%:.")
    local cmd = string.format("git show %s:%s 2>/dev/null", vim.fn.shellescape(ref), vim.fn.shellescape(relpath))
    local lines = vim.fn.systemlist(cmd)
    if vim.v.shell_error ~= 0 then
      ref_text = ""
    else
      ref_text = table.concat(lines, "\n")
    end
  end

  mini_diff.set_ref_text(0, ref_text)

  -- Toggle on the overlay if not already on
  local buf_data = mini_diff.get_buf_data(0)
  if buf_data and not buf_data.overlay then
    mini_diff.toggle_overlay(0)
  end
end

return {
  "nvim-mini/mini.diff",
  event = "VeryLazy",
  dependencies = { "folke/snacks.nvim" },
  keys = {
    -- gdo: Pick a commit for overlay (lowercase = commits)
    {
      "<leader>gdo",
      function()
        pickers.pick_commit(function(commit)
          open_overlay_for_ref(commit, false)
        end, {
          title = "Overlay: Select Commit",
          current_file = true, -- Only show commits that touched this file
        })
      end,
      desc = "Overlay Diff (pick commit)",
    },

    -- gdO: Pick a branch for overlay (uppercase = branches)
    {
      "<leader>gdO",
      function()
        pickers.pick_branch(function(branch)
          open_overlay_for_ref(branch, true)
        end, {
          title = "Overlay: Select Branch",
        })
      end,
      desc = "Overlay Diff (pick branch)",
    },
  },
}
