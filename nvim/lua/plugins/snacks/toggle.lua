-- LazyVim comes with lots of toggles accessible via <leader>u (for ui)
-- I wanted to create a keybind that was very specific to things I personally toggle often
-- so I have this specific config to place those uncer <leader>t (for toggle)
return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  opts = {
    words = {
      enabled = false,
    },
  },
  init = function()
    vim.api.nvim_create_autocmd("User", {
      pattern = "VeryLazy",
      callback = function()
        -- Create some toggle mappings
        Snacks.toggle.option("spell", { name = "Spelling" }):map("<leader>ts")
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
