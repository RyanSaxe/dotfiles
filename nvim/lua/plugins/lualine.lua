-- spec started from lazyvim defaults and then modified
return {
  "nvim-lualine/lualine.nvim",
  event = "VeryLazy",
  init = function()
    -- Ensure no command line height gaps
    vim.opt.cmdheight = 0
    -- Force statusline to always show
    vim.opt.laststatus = 3
  end,
  opts = function(opts)
    -- Minimal fix to ensure lualine reaches edges without breaking LazyVim defaults
    opts.options = opts.options or {}

    -- Force lualine to fill terminal width completely
    opts.options.globalstatus = true

    -- PERF: we don't need this lualine require madness 🤷
    local lualine_require = require("lualine_require")
    lualine_require.require = require

    local icons = LazyVim.config.icons

    vim.o.laststatus = vim.g.lualine_laststatus

    local opts = {
      options = {
        theme = "auto",
        globalstatus = vim.o.laststatus == 3,
        component_separators = { left = "", right = "" },
        section_separators = { left = "", right = "" },
        -- disabled_filetypes = { statusline = { "dashboard", "alpha", "ministarter", "snacks_dashboard" } },
      },
      sections = {
        lualine_a = { 
          { "mode", separator = { left = "" }, right_padding = 2 }
        },
        lualine_b = { "branch" },
        lualine_c = {
          { LazyVim.lualine.pretty_path() },
          {
            function()
              return vim.bo.modified and "●" or ""
            end,
            color = { fg = "#e0af68" }, -- tokyonight yellow for unsaved indicator
          },
        },

        lualine_x = {
          -- LazyVim.lualine.root_dir(),
          {
            "diagnostics",
            symbols = {
              error = icons.diagnostics.Error,
              warn = icons.diagnostics.Warn,
              info = icons.diagnostics.Info,
              hint = icons.diagnostics.Hint,
            },
          },
        },
        lualine_y = {
          {
            "diff",
            symbols = {
              added = icons.git.added,
              modified = icons.git.modified,
              removed = icons.git.removed,
            },
            source = function()
              local mini_diff = require("mini.diff")
              local summary = mini_diff.get_buf_data(0).summary
              if summary then
                return {
                  added = summary.add,
                  modified = summary.change,
                  removed = summary.delete,
                }
              end
            end,
          },
        },
        lualine_z = {
          { "location", separator = { right = "" }, left_padding = 2 }
        },
      },
      extensions = { "neo-tree", "lazy", "fzf" },
    }

    -- do not add trouble symbols if aerial is enabled
    -- And allow it to be overriden for some buffer types (see autocmds)
    if vim.g.trouble_lualine and LazyVim.has("trouble.nvim") then
      local trouble = require("trouble")
      local symbols = trouble.statusline({
        mode = "symbols",
        groups = {},
        title = false,
        filter = { range = true },
        format = "{kind_icon}{symbol.name:Normal}",
        hl_group = "lualine_c_normal",
      })
      table.insert(opts.sections.lualine_c, {
        symbols and symbols.get,
        cond = function()
          return vim.b.trouble_lualine ~= false and symbols.has()
        end,
      })
    end

    return opts
  end,
}
