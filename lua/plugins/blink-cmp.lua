-- autocomplete is a bit distracting as is, so customizing accordingly
return {
  "saghen/blink.cmp",
  ---@module 'blink.cmp'
  ---@type blink.cmp.Config
  opts = {
    completion = {
      documentation = {
        auto_show = true,
        -- only show docs if I stop typing and pause on the thing
        auto_show_delay_ms = 500,
      },
      -- menu = {
      --   auto_show = false,
      -- },
    },
    keymap = {
      preset = "super-tab",
    },
  },
}
