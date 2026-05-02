-- LazyVim comes with lots of toggles accessible via <leader>u (for ui)
-- I wanted to create a keybind that was very specific to things I personally toggle often
-- so I have this specific config to place those uncer <leader>t (for toggle)
return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  keys = {
    { "<leader>un", false },
    {
      "<leader>Un",
      function()
        Snacks.notifier.hide()
      end,
      desc = "Dismiss All Notifications",
    },
  },
  opts = function(_, opts)
    opts.words = opts.words or {}
    opts.words.enabled = false
    opts.toggle = opts.toggle or {}
    opts.toggle.which_key = false
    opts.toggle.map = function(mode, lhs, rhs, map_opts)
      lhs = lhs:gsub("^<leader>u", "<leader>U")
      LazyVim.safe_keymap_set(mode, lhs, rhs, map_opts)
    end
  end,
  init = function()
    vim.api.nvim_create_autocmd("User", {
      pattern = "VeryLazy",
      callback = function()
        -- Harper grammar/spell toggle (replaces Vim's built-in spell)
        -- Toggles the harper_ls LSP client for the current buffer
        -- Works on ANY filetype, not just prose files where Harper auto-attaches
        Snacks.toggle({
          name = "Harper Grammar",
          get = function()
            local clients = vim.lsp.get_clients({ name = "harper_ls", bufnr = 0 })
            return #clients > 0
          end,
          set = function(state)
            local bufnr = vim.api.nvim_get_current_buf()
            if state then
              -- Start Harper for this buffer, bypassing filetype restrictions
              -- Get the default config from lspconfig and start manually
              local harper = require("lspconfig").harper_ls
              local config = harper.config_def.default_config
              vim.lsp.start({
                name = "harper_ls",
                cmd = config.cmd,
                root_dir = vim.fn.getcwd(),
                single_file_support = true,
              }, { bufnr = bufnr })
            else
              -- Detach Harper from this buffer only
              local clients = vim.lsp.get_clients({ name = "harper_ls", bufnr = bufnr })
              for _, client in ipairs(clients) do
                client:detach(bufnr)
              end
            end
          end,
        }):map("<leader>tg")

        Snacks.toggle({
          name = "Treesitter Context",
          get = function()
            return require("treesitter-context").enabled()
          end,
          set = function(state)
            if state then
              require("treesitter-context").enable()
            else
              require("treesitter-context").disable()
            end
          end,
        }):map("<leader>ts")

        Snacks.toggle.diagnostics({ name = "Diagnostics" }):map("<leader>td")
        Snacks.toggle.inlay_hints():map("<leader>th")
        Snacks.toggle.option("wrap", { name = "Line Wrap" }):map("<leader>tw")

        -- Buffer-local Copilot toggle (remembers state per buffer for the session)
        -- Uses CopilotBuffer from plugins/completion/copilot.lua
        if _G.CopilotBuffer then
          Snacks.toggle({
            name = "Copilot (Buffer)",
            get = function()
              return _G.CopilotBuffer.get_state()
            end,
            set = function(state)
              _G.CopilotBuffer.set_state(nil, state)
            end,
          }):map("<leader>tc")
        end

        -- Global Copilot toggle (enables/disables for entire session)
        local copilot_exists = pcall(require, "copilot")
        if copilot_exists then
          Snacks.toggle({
            name = "Copilot (Global)",
            get = function()
              return not require("copilot.client").is_disabled()
            end,
            set = function(state)
              if state then
                require("copilot.command").enable()
              else
                require("copilot.command").disable()
              end
            end,
          }):map("<leader>tC")
        end
        --
      end,
    })
  end,
}
