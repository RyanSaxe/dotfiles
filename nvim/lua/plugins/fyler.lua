return {
  "A7Lavinraj/fyler.nvim",
  priority = 1000,
  dependencies = { "nvim-mini/mini.icons" },
  branch = "stable",
  opts = {
    -- Keep the explorer open when selecting files
    close_on_select = false,
    -- Track current buffer location in the tree
    track_current_buffer = true,
    -- Disable git status symbols to reduce clutter
    -- Disable indentation guides for cleaner look
    indentscope = {
      enabled = false,
    },
    win = {
      -- Customize window options to make it look like a non-code buffer
      win_opts = {
        number = false, -- Disable line numbers
        relativenumber = false, -- Disable relative line numbers
        signcolumn = "no", -- Disable sign column
        cursorline = true, -- Keep cursor line highlight for navigation
      },
    },
  },
  keys = {
    -- Disable LazyVim default <leader>e binding (Snacks explorer)
    { "<leader>e", false },
    -- Open fyler in split
    {
      "<leader>e",
      function()
        require("fyler").toggle({
          kind = "split_right_most", -- (Optional) Use custom window layout
        })
      end,
      desc = "Open Fyler Explorer (Split)",
    },
    -- Open fyler in current buffer
    {
      "<leader>E",
      function()
        require("fyler").open({ kind = "float" })
      end,
      desc = "Open Fyler Explorer (Float)",
    },
  },
}
