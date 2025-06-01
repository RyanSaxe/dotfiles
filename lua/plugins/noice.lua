-- don't show documentation unless I ask for it

return {
  "folke/noice.nvim",
  opts = {
    lsp = {
      -- turn off the automatic popup when you type "(" or ","
      signature = { enabled = true, auto_open = { trigger = false } },
      -- this doesnt seem to work
      presets = {
        bottom_search = true, -- use a classic bottom cmdline for search
        command_palette = true, -- position the cmdline and popupmenu together
        long_message_to_split = true, -- long messages will be sent to a split
        inc_rename = false, -- enables an input dialog for inc-rename.nvim
        lsp_doc_border = true, -- add a border to hover docs and signature help
      },
    },
  },
}
