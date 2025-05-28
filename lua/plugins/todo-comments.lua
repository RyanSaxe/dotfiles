-- enable TODOs to still work when people are assigned to them
return {
  "folke/todo-comments.nvim",
  opts = {
    highlight = {
      pattern = { [[.*<(KEYWORDS)\s*:]], [[.*<(KEYWORDS)\s*\(.*\)\s*:]] },
    },
  },
}
