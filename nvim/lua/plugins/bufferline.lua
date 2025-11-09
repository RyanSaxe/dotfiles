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

      -- Invisible separators
      separator_style = "thin",

      -- No indicator - just color changes
      indicator = {
        style = "none",
      },
      diagnostics = false,
      show_buffer_icons = false,
      color_icons = false,
      show_buffer_close_icons = true,
      show_close_icon = true,

      -- Don't always show - this prevents showing on dashboard when it's the only buffer
      always_show_bufferline = false,

      max_name_length = 18,
      tab_size = 18,

      -- LazyVim defaults remain for functionality:
      -- - Offsets for Neo-tree and Snacks
      -- - Buffer delete with Snacks.bufdelete()
      -- - Keybindings: <leader>bp (pin), <S-h>/<S-l> (navigate), [B]/]B (move)
    },
  },
}
