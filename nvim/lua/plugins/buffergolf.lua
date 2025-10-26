return {
  {
    -- "ryansaxe/keymash.nvim",
    dir = "~/projects/buffergolf.nvim",
    opts = {
      -- your override options here
    },
    config = function(_, opts)
      require("buffergolf").setup(opts)

      local group = vim.api.nvim_create_augroup("BufferGolfCopilotMute", { clear = true })
      vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
        group = group,
        callback = function(event)
          local buf = event.buf
          local ok, is_practice = pcall(vim.api.nvim_buf_get_var, buf, "buffergolf_practice")
          if ok and is_practice then
            vim.b[buf].copilot_enabled = false
          else
            pcall(vim.api.nvim_buf_del_var, buf, "copilot_enabled")
          end
        end,
      })
    end,
  },
}
