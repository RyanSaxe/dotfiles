-- for integrating git workflows into neovim. Mostly for viewing diffs.
return {
  "sindrets/diffview.nvim",
  cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFocusFiles" },
  opts = {
    view = {
      default = {
        layout = "diff2_horizontal",
        disable_diagnostics = false,
      },
    },
    -- if you want to have the file panel on the bottom instead
    -- I recommend this if you prefer diff2_horizontal as the layout
    file_panel = {
      listing_style = "list", -- change to "tree" to get a file tree instead of a list
      tree_options = {
        flatten_dirs = true,
        folder_statuses = "only_folded",
      },
      win_config = {
        position = "bottom", -- move file tree here
        height = 10, -- adjust as needed
        win_opts = {},
      },
    },
  },
}
