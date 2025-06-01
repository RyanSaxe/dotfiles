return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  init = function()
    vim.api.nvim_create_autocmd("User", {
      pattern = "VeryLazy",
      callback = function()
        -- Create some toggle mappings
        Snacks.toggle.option("spell", { name = "Spelling" }):map("<leader>ts")
        Snacks.toggle.diagnostics({ name = "Diagnostics" }):map("<leader>td")
        Snacks.toggle.inlay_hints():map("<leader>th")
        Snacks.toggle.dim():map("<leader>tz")

        -- Add Copilot toggle
        local copilot_exists = pcall(require, "copilot")
        if copilot_exists then
          Snacks.toggle({
            name = "Copilot Completion",
            color = {
              enabled = "azure",
              disabled = "orange",
            },
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
          }):map("<leader>tc")
        end
        --
      end,
    })
  end,
}
