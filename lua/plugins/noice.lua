-- don't show documentation unless I ask for it

return {
  "folke/noice.nvim",
  opts = {
    lsp = {
      -- turn off the automatic popup when you type "(" or ","
      signature = { enabled = true, auto_open = { trigger = false } },
    },
    presets = {
      command_palette = true, -- position the cmdline and popupmenu together
      inc_rename = true, -- enables an input dialog for inc-rename.nvim
      lsp_doc_border = true, -- add a border to hover docs and signature help
    },
  },
}
