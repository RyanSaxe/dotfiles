-- NOTE: this requires openjdk@17 to be installed
return {
  url = "https://gitlab.com/schrieveslaach/sonarlint.nvim",
  ft = { "python" },
  config = function()
    require("sonarlint").setup({
      server = {
        cmd = {
          "sonarlint-language-server",
          "-stdio",
          "-analyzers",
          vim.fn.expand("$MASON/share/sonarlint-analyzers/sonarpython.jar"),
        },
      },
      filetypes = {
        "python",
      },
      -- commented out to show how to customize rules globally
      -- TODO: figure out how to let this change per project and inherit real sonarqube profiles
      -- settings = {
      --   sonarlint = {
      --     rules = {
      --       ["typescript:S6019"] = { level = "on" },
      --       ["typescript:S6035"] = { level = "on" },
      --       ["typescript:S2933"] = { level = "on" },
      --       ["typescript:S1607"] = { level = "on" },
      --       ["typescript:S6079"] = { level = "on" },
      --     },
      --   },
      -- },
    })
  end,
}
