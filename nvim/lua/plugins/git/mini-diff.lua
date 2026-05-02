-- mini.diff - Inline git hunks with overlay support
-- Keymaps use snacks.nvim pickers for commit/branch selection with diff previews
--
-- Keymaps:
--   <leader>gdo - Overlay diff: pick a branch (base branch highlighted)
--   <leader>gdO - Overlay diff: pick a commit (most recent first = HEAD)
--   <leader>gdq - Close any diff view (mini.diff overlay or codediff)

local git_utils = require("custom.git.utils")
local pickers = require("custom.git.pickers")

-- Track inlay hints state per buffer to restore on overlay close.
-- Inlay hints are disabled during overlay because their background color
-- overrides the diff highlight colors, making changes hard to see.
local inlay_hints_was_enabled = {}

-- Toggle overlay with inlay hints management
local function toggle_overlay_with_hints(buf_id)
  buf_id = buf_id or 0
  local mini_diff = require("mini.diff")
  local buf_data = mini_diff.get_buf_data(buf_id)
  if not buf_data then
    return
  end

  local actual_buf = buf_id == 0 and vim.api.nvim_get_current_buf() or buf_id

  if buf_data.overlay then
    -- Closing overlay: restore inlay hints if they were enabled before
    mini_diff.toggle_overlay(buf_id)
    if inlay_hints_was_enabled[actual_buf] then
      vim.lsp.inlay_hint.enable(true, { bufnr = actual_buf })
      inlay_hints_was_enabled[actual_buf] = nil
    end
  else
    -- Opening overlay: save and disable inlay hints
    local hints_enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = actual_buf })
    if hints_enabled then
      inlay_hints_was_enabled[actual_buf] = true
      vim.lsp.inlay_hint.enable(false, { bufnr = actual_buf })
    end
    mini_diff.toggle_overlay(buf_id)
  end
end

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
    toggle_overlay_with_hints(0)
  end
end

return {
  "nvim-mini/mini.diff",
  event = "VeryLazy",
  dependencies = { "folke/snacks.nvim" },
  keys = {
    -- gdo: Pick a branch for overlay (lowercase = branches)
    {
      "<leader>gdo",
      function()
        pickers.pick_branch(function(branch)
          open_overlay_for_ref(branch, true)
        end, {
          title = "Overlay: Select Branch",
        })
      end,
      desc = "Overlay Diff (pick branch)",
    },

    -- gdO: Pick a commit for overlay (uppercase = commits)
    {
      "<leader>gdO",
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

    -- gdq: Unified close for any diff view (mini.diff overlay or codediff)
    {
      "<leader>gdq",
      function()
        -- Try closing mini.diff overlay first
        local mini_diff = require("mini.diff")
        local buf_data = mini_diff.get_buf_data(0)
        if buf_data and buf_data.overlay then
          toggle_overlay_with_hints(0)
          return
        end

        -- Try closing codediff tab (check if current tab is a codediff session)
        local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
        if ok then
          local current_tab = vim.api.nvim_get_current_tabpage()
          if lifecycle.get_session(current_tab) then
            vim.cmd("tabclose")
          end
        end
      end,
      desc = "Close Diff View",
    },
  },
}
