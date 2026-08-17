-- Pickers respect gitignore but never hide dotfiles: dotfile-heavy
-- trees are daily terrain here and default hiding buries them.
return {
  "folke/snacks.nvim",
  opts = {
    picker = {
      -- No backdrop: dimming everything behind the picker drags the
      -- chrome down with it, and chrome reads as broken when it dims.
      layout = { backdrop = false },
      sources = {
        files = { hidden = true },
        grep = { hidden = true },
        explorer = { hidden = true },
      },
    },
  },
}
