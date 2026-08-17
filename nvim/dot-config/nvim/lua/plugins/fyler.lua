-- Fyler on trial, alongside the snacks explorer rather than replacing
-- it: <leader>e stays the tree you know, <leader>o opens this one on the
-- same right edge and the same width, so the comparison is fair.
--
-- Why it is worth trying at all: fyler opens a REAL split, so
-- theme.surfaces paints it on the outer layer with no plugin-specific
-- code — snacks builds its sidebar from floats inside a box and asserts
-- its own winhighlight last, which is why snacks had to be carved out
-- wholesale. Fyler also edits the tree as a buffer, the way mini.files
-- does, so if it sticks it replaces both.
return {
  "FylerOrg/fyler.nvim",
  dependencies = { "nvim-mini/mini.icons" },
  cmd = "Fyler",
  keys = {
    { "<leader>o", "<cmd>Fyler<cr>", desc = "Fyler (tree, right)" },
  },
  ---@module 'fyler'
  opts = {
    kind = "split_right_most",
    -- 40 columns: the snacks explorer's width, so the A/B is like for like.
    kind_presets = {
      split_right_most = { width = 40 },
    },
    follow_current_file = true,
    extensions = {
      git = { enabled = true },
    },
  },
}
