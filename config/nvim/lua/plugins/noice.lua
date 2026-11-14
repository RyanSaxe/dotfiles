-- noice renders LSP hover itself, so `K` never reaches Neovim's own float
-- and `winborder` (config/options.lua) does not apply to it. Its stock hover
-- view already pads the text two columns; it just draws no frame around it,
-- which is the one float in the config that had none.
--
-- The file name and size Neovim prints on every save and every open, such
-- as `"init.lua" 62L, 1991B`, are skipped. LazyVim already drops the word
-- "written". The route goes first because noice uses the first that matches.
return {
  "folke/noice.nvim",
  ---@param opts table
  opts = function(_, opts)
    opts.views = vim.tbl_deep_extend("force", opts.views or {}, {
      hover = {
        border = { style = "rounded" },
      },
    })
    opts.routes = opts.routes or {}
    table.insert(opts.routes, 1, {
      filter = { event = "msg_show", find = "%d+L, %d+B" },
      opts = { skip = true },
    })
  end,
}
