-- disable the gutter signs since we get that from mini.diff
-- we just need gitsigns for nicer blames and connected mode in sonarlint
return {
  "lewis6991/gitsigns.nvim",
  event = "VeryLazy",
  opts = {
    signcolumn = false, -- disable the sign column since we use mini.diff
    numhl = false, -- disable number highlighting since we use mini.diff
  },
}
