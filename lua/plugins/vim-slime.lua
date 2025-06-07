return {
  -- slime (REPL integration)
  {
    "jpalardy/vim-slime",
    keys = {
      { "<leader>pc", "<cmd>SlimeConfig", desc = "Slime Config" },
      { "<leader>p<cr>", "<Plug>SlimeSendCell<BAR>/^# %%<CR>", desc = "Slime Send Cell" },
      { "<leader>ps", "<Plug>SlimeSendMotion", desc = "Slime Send Motion" },
      { "<leader>pl", "<Plug>SlimeSendLine", desc = "Slime Send Line" },
      { "<leader>pp", "<Plug>SlimeSendRegion", desc = "Slime Send Region" },
    },
    init = function()
      vim.g.slime_target = "neovim"
      vim.g.slime_no_mappings = true
      vim.g.slime_get_jobid = function()
        -- iterate over all buffers to find the first terminal with a valid job
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_get_option_value("buftype", { buf = bufnr }) == "terminal" then
            local chan = vim.api.nvim_get_option_value("channel", { buf = bufnr })
            if chan and chan > 0 then
              return chan
            end
          end
        end
        return nil
      end
    end,
    config = function()
      vim.g.slime_cell_delimiter = "# %%"
      vim.g.slime_bracketed_paste = 1
      -- vim.g.slime_python_ipython = 1
    end,
  },
}
