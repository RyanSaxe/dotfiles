-- noice renders LSP hover itself, so `K` never reaches Neovim's own float
-- and `winborder` (config/options.lua) does not apply to it. Its stock hover
-- view already pads the text two columns; it just draws no frame around it,
-- which is the one float in the config that had none.
return {
  "folke/noice.nvim",
  opts = {
    views = {
      hover = {
        border = { style = "rounded" },
      },
    },
  },
}
