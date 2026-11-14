-- The browser preview on <leader>cp, in place of the markdown extra's
-- markdown-preview.nvim. live-preview.nvim's server is Neovim's own Lua, so
-- there's no prebuilt binary, and the page updates as you type.
return {
  { "iamcco/markdown-preview.nvim", enabled = false },
  {
    "brianhuster/live-preview.nvim",
    cmd = "LivePreview",
    keys = {
      {
        "<leader>cp",
        function()
          vim.cmd.LivePreview(require("livepreview").is_running() and "close" or "start")
        end,
        ft = "markdown",
        desc = "Markdown Preview",
      },
    },
  },
}
