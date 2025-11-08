return {
  "akinsho/bufferline.nvim",
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

      always_show_bufferline = true,

      max_name_length = 18,
      tab_size = 18,

      -- LazyVim defaults remain for functionality:
      -- - Offsets for Neo-tree and Snacks
      -- - Buffer delete with Snacks.bufdelete()
      -- - Keybindings: <leader>bp (pin), <S-h>/<S-l> (navigate), [B]/]B (move)
    },
  },
}

