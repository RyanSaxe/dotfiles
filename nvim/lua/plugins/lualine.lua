return {
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    -- Minimal fix to ensure lualine reaches edges without breaking LazyVim defaults
    opts.options = opts.options or {}

    -- Force lualine to fill terminal width completely
    opts.options.globalstatus = true

    return opts
  end,
  init = function()
    -- Ensure no command line height gaps
    vim.opt.cmdheight = 0
    -- Force statusline to always show
    vim.opt.laststatus = 3
  end,
}
