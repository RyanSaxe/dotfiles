-- this is still very experimental, but trying to make things simpler and not have too many results show up

-- Filetypes where we want buffer and dictionary completions (prose writing)
local prose_filetypes = { "markdown", "text", "gitcommit", "mail", "plaintex" }

local function is_prose_filetype()
  return vim.tbl_contains(prose_filetypes, vim.bo.filetype)
end

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

    -- Keybinding convention: Tab = normal completions, Shift-Tab = ghost text / AI suggestions
    keymap = {
      preset = nil, -- disable the preset
      ["<CR>"] = { "accept", "fallback" },
      ["<S-CR>"] = { "accept", "select_and_accept", "fallback" },
      ["<C-K>"] = { "show_documentation", "hide_documentation" }, -- toggle docs (like S-K for code)
      ["<C-c>"] = { "hide", "fallback" },
      -- set navigation to Ctrl-j/k for standardization across plugins
      ["<C-k>"] = { "select_prev", "fallback" },
      ["<C-j>"] = { "select_next", "fallback" },
      -- Tab: Normal completions (blink menu -> snippets -> literal tab)
      -- Ghost text (Copilot, NES) is handled by Shift-Tab for consistency across tools
      ["<Tab>"] = {
        function(cmp)
          -- Navigate blink-cmp menu if it's open
          if cmp.is_visible() then
            return cmp.select_next()
          end
          -- Continue to snippet_forward
          return false
        end,
        "snippet_forward", -- Jump to next snippet field if in snippet
        -- Insert literal tab character when nothing else applies
        -- Without this explicit insertion, Tab becomes disabled when all conditions fail
        function()
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Tab>", true, false, true), "n", false)
          return true
        end,
      },

      -- Shift-Tab: Accept ghost text and AI suggestions (Copilot -> NES -> menu backwards)
      -- This maintains consistency with Zsh where Shift-Tab accepts autosuggestions
      ["<S-Tab>"] = {
        function(cmp)
          -- 1. Accept Copilot inline suggestion (ghost text) if visible
          if require("copilot.suggestion").is_visible() then
            require("copilot.suggestion").accept()
            return true
          end

          -- 2. Apply NES (sidekick) multi-line edit suggestion if available
          local ok, sidekick = pcall(require, "sidekick")
          if ok and sidekick.nes_jump_or_apply() then
            return true
          end

          -- 3. Navigate blink-cmp menu backwards as fallback
          if cmp.is_visible() then
            return cmp.select_prev()
          end

          return false
        end,
      },

      -- Standard navigation keys
      ["<Up>"] = { "select_prev", "fallback" },
      ["<Down>"] = { "select_next", "fallback" },
      ["<C-p>"] = { "select_prev", "fallback" },
      ["<C-n>"] = { "select_next", "fallback" },
      ["<C-y>"] = { "accept", "select_and_accept", "fallback" },
      ["<C-b>"] = { "scroll_documentation_up", "fallback" },
      ["<C-f>"] = { "scroll_documentation_down", "fallback" },
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
        -- TODO: need to make snippets something I like and then re-add it
        local result = { "lsp", "path", "buffer" }
        -- add dictionary for prose filetypes (markdown, gitcommit, etc.)
        if is_prose_filetype() then
          table.insert(result, "dictionary")
          -- obsidian sources are auto-added by obsidian.nvim when blink = true
        end
        return result
      end,
      providers = {
        dictionary = {
          module = "blink-cmp-dictionary",
          name = "Dict",
          score_offset = 20, -- lower priority than buffer (25) and lsp (90)
          -- Make sure this is at least 2.
          -- 3 is recommended
          min_keyword_length = 3,
          max_items = 3,
          opts = {
            -- Base dictionary for word completions (large word list)
            dictionary_directories = { vim.fn.expand("~/.config/nvim/dictionaries") },
            -- Harper user dictionary (custom words added via code actions)
            -- This ensures words you add to Harper also appear in completions
            dictionary_files = { vim.fn.expand("~/.config/harper-ls/dictionary.txt") },
            -- WordNet definitions are auto-enabled when 'wn' command is available
            -- Install via: brew install wordnet (macOS) or apt install wordnet (Linux)
          },
        },
        buffer = {
          name = "Buffer",
          score_offset = 25, -- higher than dictionary, lower than lsp
          min_keyword_length = 2,
          max_items = 3,
        },
        -- Obsidian providers (obsidian, obsidian_new, obsidian_tags) are
        -- automatically registered by obsidian.nvim when completion.blink = true
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
          score_offset = 90, -- highest priority - code symbols first
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
        -- Disable the snippets source (friendly-snippets).
        -- NOTE: LSP servers can still send snippet-style completions (e.g., function
        -- signatures with placeholders). To filter those, add transform_items to the
        -- lsp provider that filters out CompletionItemKind.Snippet.
        snippets = {
          should_show_items = function()
            return false
          end,
          min_keyword_length = 2,
          score_offset = 0,
        },
      },
    },
  },
}
