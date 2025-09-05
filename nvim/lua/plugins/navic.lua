return {
  {
    "SmiteshP/nvim-navic",
    lazy = true,
    init = function()
      vim.g.navic_silence = true
    end,
    opts = {
      lsp = {
        auto_attach = true,
      },
      highlight = true,
      separator = " > ",
      depth_limit = 0, -- disable built-in depth limiting
      depth_limit_indicator = "..", -- show ".." when truncated
      safe_output = true,
      lazy_update_context = false,
      click = false,
      icons = {
        File = "",
        Module = "",
        Namespace = "",
        Package = "",
        Class = "",
        Method = "",
        Property = "",
        Field = "",
        Constructor = "",
        Enum = "",
        Interface = "",
        Function = "",
        Variable = "",
        Constant = "",
        String = "",
        Number = "",
        Boolean = "",
        Array = "",
        Object = "",
        Key = "",
        Null = "",
        EnumMember = "",
        Struct = "",
        Event = "",
        Operator = "",
        TypeParameter = "",
      },
      format_text = function(text)
        -- remove extra spaces around icons and text
        return text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
      end,
    },
  },
}