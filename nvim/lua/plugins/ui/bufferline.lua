return {
  "akinsho/bufferline.nvim",
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
          vim.notify("Bufferline shown", vim.log.levels.INFO)
        else
          -- Hide bufferline but keep the space (blank tabline)
          vim.o.tabline = " "
          vim.g.bufferline_hidden = true
          vim.notify("Bufferline hidden", vim.log.levels.INFO)
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
      always_show_bufferline = false,
    },
  },
}
