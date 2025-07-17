-- this is still very experimental, but trying to make things simpler and not have too many results show up

return {
  "saghen/blink.cmp",
  dependencies = {
    "rafamadriz/friendly-snippets",
    "Kaiser-Yang/blink-cmp-dictionary",
    dependencies = { "nvim-lua/plenary.nvim" },
  }, -- "giuxtaposition/blink-cmp-copilot" },
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
      enabled = false,
    },
    appearance = {
      use_nvim_cmp_as_default = false,
      nerd_font_variant = "mono",
    },
    completion = {
      -- uncommenting below will allow completions to fire way more generically
      -- trigger = {
      --   show_on_blocked_trigger_characters = {},
      --   show_on_x_blocked_trigger_characters = {},
      -- },
      ghost_text = { enabled = false },
      accept = { auto_brackets = { enabled = true } },
      documentation = {
        auto_show = false,
        auto_show_delay_ms = 50,
        update_delay_ms = 50,
        treesitter_highlighting = true,
        window = { border = "rounded" },
      },
      list = {
        selection = {
          preselect = false,
          auto_insert = true,
        },
      },
      menu = {
        border = "rounded",
        draw = {
          treesitter = { "lsp", "buffer", "copilot", "lazydev" },
          columns = { { "label", "label_description", gap = 1 }, { "kind_icon", "kind" } },
        },
      },
    },

    -- My super-TAB configuration
    keymap = {
      preset = nil, -- disable the preset
      ["<CR>"] = { "accept", "fallback" },
      ["<S-CR>"] = { "accept", "select_and_accept", "fallback" },
      ["<S-space>"] = { "show", "show_documentation", "hide_documentation" },
      ["<C-e>"] = { "hide", "fallback" },
      ["<S-BS>"] = {
        function(cmp)
          return cmp.select_prev()
        end,
        "snippet_backward",
        "fallback",
      },
      ["<Tab>"] = {
        function(cmp)
          return cmp.select_next()
        end,
        "snippet_forward",
        "fallback",
      },

      ["<Up>"] = { "select_prev", "fallback" },
      ["<Down>"] = { "select_next", "fallback" },
      ["<C-p>"] = { "select_prev", "fallback" },
      ["<C-n>"] = { "select_next", "fallback" },
      ["<C-y>"] = { "accept", "select_and_accept", "fallback" },
      ["<C-up>"] = { "scroll_documentation_up", "fallback" },
      ["<C-down>"] = { "scroll_documentation_down", "fallback" },
    },

    -- Experimental signature help support
    signature = {
      enabled = true,
      window = { border = "rounded", show_documentation = true },
    },

    sources = {
      -- buffer is removed to avoid random words that arent symbols getting introduced.
      -- copilot is removed since that is always set to ghost text with tab completion
      default = function()
        -- base set of sources everywhere
        local result = { "lsp", "path" }
        -- only load dictionary for markdown
        if vim.bo.filetype == "markdown" then
          table.insert(result, "dictionary")
          table.insert(result, "buffer")
        end
        return result
      end,
      providers = {
        dictionary = {
          module = "blink-cmp-dictionary",
          name = "Dict",
          -- Make sure this is at least 2.
          -- 3 is recommended
          min_keyword_length = 3,
          opts = {
            dictionary_directories = { vim.fn.expand("~/.config/nvim/dictionaries") },
          },
        },
        -- copilot = {
        --   name = "copilot",
        --   module = "blink-cmp-copilot",
        --   kind = "Copilot",
        --   score_offset = 200,
        --   async = true,
        -- },
        -- lazydev = {
        --   name = "LazyDev",
        --   module = "lazydev.integrations.blink",
        --   -- Make lazydev completions top priority (see `:h blink.cmp`)
        --   score_offset = 100,
        -- },
        lsp = {
          min_keyword_length = 0, -- Number of characters to trigger provider
          score_offset = 10, -- Boost/penalize the score of the items
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
        -- TODO: learn more about snippets and best way to use -- the defaults from lazyvim are distracting at least for python
        snippets = {
          -- disables snippets. Not sure why I cant disable these by deleting the block.
          should_show_items = function()
            return false
          end,
          min_keyword_length = 2,
          score_offset = 0,
        },
        -- buffer = {
        --   min_keyword_length = 3,
        --   max_items = 5,
        --   score_offset = 11,
        -- },
      },
    },
  },
}
