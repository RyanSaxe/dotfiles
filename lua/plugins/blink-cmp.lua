--- inspiration from https://www.youtube.com/watch?v=7HYBrw6EDEM to customize blink. Generally the main
--- part of the above video is to use ; as a trigger key for copilot and snippets because they are often
--- useful, but distracting to always see by default.
local trigger_text = ";"

local trigger_advanced = function()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local before_cursor = vim.api.nvim_get_current_line():sub(1, col)

  local matched = before_cursor:match(trigger_text .. ".*$")

  return matched
end

local trigger_only_advanced = function()
  local matched = trigger_advanced()
  return matched ~= nil
end

local trigger_only_normal = function()
  local matched = trigger_advanced()
  return matched == nil
end

-- TODO: implement the transform_items to properly remove the semicolon -- or honestly figure out another way

return {
  "saghen/blink.cmp",
  dependencies = { "rafamadriz/friendly-snippets", "giuxtaposition/blink-cmp-copilot" },
  version = "*",
  event = { "InsertEnter", "CmdlineEnter" },

  ---@module 'blink.cmp'
  ---@type blink.cmp.Config
  opts = {
    -- disable when in the typing practice game
    enabled = function()
      return not vim.tbl_contains({ "typr" }, vim.bo.filetype) and vim.bo.buftype ~= "prompt"
    end,
    cmdline = {
      enabled = true,
    },
    appearance = {
      use_nvim_cmp_as_default = false,
      nerd_font_variant = "mono",
    },
    completion = {

      ghost_text = { enabled = true },
      accept = { auto_brackets = { enabled = true } },
      documentation = {
        auto_show = true,
        auto_show_delay_ms = 50,
        update_delay_ms = 50,
        treesitter_highlighting = true,
        window = { border = "rounded" },
      },
      list = {
        selection = {
          preselect = true,
          auto_insert = false,
        },
      },
      menu = {
        border = "rounded",
        draw = {
          -- columns = {
          --   { "label", "label_description", gap = 1 },
          --   { "kind_icon", "kind" },
          -- },
          treesitter = { "lsp" },
        },
      },
    },

    -- My super-TAB configuration
    keymap = {
      preset = "super-tab",
      ["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
      ["<C-e>"] = { "hide", "fallback" },
      ["<S-Tab>"] = {
        function(cmp)
          return cmp.select_next()
        end,
        "snippet_forward",
        "fallback",
      },
      ["<S-BS>"] = {
        function(cmp)
          return cmp.select_prev()
        end,
        "snippet_backward",
        "fallback",
      },

      ["<Up>"] = { "select_prev", "fallback" },
      ["<Down>"] = { "select_next", "fallback" },
      ["<C-p>"] = { "select_prev", "fallback" },
      ["<C-n>"] = { "select_next", "fallback" },
      ["<C-up>"] = { "scroll_documentation_up", "fallback" },
      ["<C-down>"] = { "scroll_documentation_down", "fallback" },
    },

    -- Experimental signature help support
    signature = {
      enabled = true,
      window = { border = "rounded" },
    },

    sources = {
      default = { "lazydev", "lsp", "copilot", "path", "snippets", "buffer" },
      providers = {
        copilot = {
          name = "copilot",
          module = "blink-cmp-copilot",
          kind = "Copilot",
          score_offset = 200,
          async = true,
          should_show_items = trigger_only_advanced,
        },
        lazydev = {
          name = "LazyDev",
          module = "lazydev.integrations.blink",
          -- Make lazydev completions top priority (see `:h blink.cmp`)
          score_offset = 100,
          should_show_items = trigger_only_normal,
        },
        lsp = {
          min_keyword_length = 0, -- Number of characters to trigger provider
          score_offset = 10, -- Boost/penalize the score of the items
          should_show_items = trigger_only_normal,
          override = {
            -- allow a . to trigger autocomplete for faster lookup of imports
            get_trigger_characters = function(self)
              local trigger_characters = self:get_trigger_characters()
              vim.list_extend(trigger_characters, { "." })
              return trigger_characters
            end,
          },
        },
        path = {
          min_keyword_length = 0,
        },
        snippets = {
          should_show_items = trigger_only_advanced,
          min_keyword_length = 2,
        },
        buffer = {
          min_keyword_length = 3,
          max_items = 5,
          should_show_items = trigger_only_normal,
        },
      },
    },
  },
}
