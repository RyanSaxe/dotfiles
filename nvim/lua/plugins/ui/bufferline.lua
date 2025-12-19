return {
  "akinsho/bufferline.nvim",
  lazy = false,
  priority = 1001, -- Load before snacks dashboard (priority 1000)
  enabled = true,
  keys = {
    {
      "<leader>tb",
      function()
        -- Toggle bufferline visibility while keeping the padding
        -- Store the original tabline function
        if not vim.g.bufferline_original_tabline then
          vim.g.bufferline_original_tabline = vim.o.tabline
        end

        if vim.g.bufferline_hidden then
          -- Restore bufferline
          vim.o.tabline = vim.g.bufferline_original_tabline
          vim.g.bufferline_hidden = false
        else
          -- Hide bufferline but keep the space (blank tabline)
          vim.o.tabline = " "
          vim.g.bufferline_hidden = true
        end
      end,
      desc = "Toggle Bufferline",
    },
  },
  opts = {
    options = {
      -- No numbers - pure text only
      numbers = "none",

      -- Slanted separators for tab appearance (active tab looks raised)
      separator_style = "slant",

      -- No indicator - just color changes
      indicator = {
        style = "none",
      },
      show_buffer_icons = false,
      -- Always show bufferline when in tmux to prevent layout shifts with tmux status bar
      -- Outside tmux, only show when there are multiple buffers (default behavior)
      always_show_bufferline = true, -- vim.env.TMUX ~= nil,
    },
  },
}
