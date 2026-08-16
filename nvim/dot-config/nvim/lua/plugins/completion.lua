-- The completion contract: Tab drives the blink menu, S-Tab accepts
-- ghost text (copilot.lua owns that), vi-mode keys stay sacred.
-- mini.pairs is disabled on purpose — blink's auto_brackets on accept
-- is the only pairing.
return {
  { "nvim-mini/mini.pairs", enabled = false },

  -- LazyVim maps i_<c-k> to signature help on every LspAttach, and that
  -- buffer-local map would win over blink's menu-up. Blink's signature
  -- window already owns signature UI, so the LSP keymap goes.
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      local keys = opts.servers["*"].keys
      keys[#keys + 1] = { "<c-k>", false, mode = "i" }
    end,
  },

  {
    "saghen/blink.cmp",
    ---@module 'blink.cmp'
    ---@type blink.cmp.Config
    opts = {
      cmdline = { enabled = false },
      completion = {
        -- Ghost text belongs to copilot; blink never draws its own.
        ghost_text = { enabled = false },
        accept = { auto_brackets = { enabled = true } },
        documentation = {
          auto_show = true,
          auto_show_delay_ms = 50,
          update_delay_ms = 50,
          treesitter_highlighting = true,
          window = { border = "rounded" },
        },
        -- CR semantics depend on this pair: nothing preselected, and
        -- navigating the menu previews text into the buffer.
        list = { selection = { preselect = false, auto_insert = true } },
        menu = {
          border = "rounded",
          draw = {
            treesitter = { "lsp", "buffer" },
            columns = { { "label", "label_description", gap = 1 }, { "kind_icon", "kind" } },
          },
        },
      },

      keymap = {
        preset = nil,
        ["<CR>"] = { "accept", "fallback" },
        ["<S-CR>"] = { "accept", "select_and_accept", "fallback" },
        ["<C-e>"] = { "show_documentation", "hide_documentation" },
        ["<C-c>"] = { "hide", "fallback" },
        ["<C-k>"] = { "select_prev", "fallback" },
        ["<C-j>"] = { "select_next", "fallback" },
        -- Tab: menu -> snippet field -> literal tab. The literal-tab
        -- fallback is load-bearing: without it Tab dead-keys whenever
        -- the first two steps decline.
        ["<Tab>"] = {
          function(cmp)
            if cmp.is_visible() then
              return cmp.select_next()
            end
            return false
          end,
          "snippet_forward",
          function()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Tab>", true, false, true), "n", false)
            return true
          end,
        },
        -- S-Tab: accept copilot ghost text, else menu backwards —
        -- mirrors zsh where S-Tab accepts the autosuggestion.
        ["<S-Tab>"] = {
          function(cmp)
            if require("copilot.suggestion").is_visible() then
              require("copilot.suggestion").accept()
              return true
            end
            if cmp.is_visible() then
              return cmp.select_prev()
            end
            return false
          end,
        },
        ["<Up>"] = { "select_prev", "fallback" },
        ["<Down>"] = { "select_next", "fallback" },
        ["<C-p>"] = { "select_prev", "fallback" },
        ["<C-n>"] = { "select_next", "fallback" },
        ["<C-y>"] = { "accept", "select_and_accept", "fallback" },
        ["<C-b>"] = { "scroll_documentation_up", "fallback" },
        ["<C-f>"] = { "scroll_documentation_down", "fallback" },
      },

      signature = {
        enabled = true,
        window = { border = "rounded", show_documentation = true },
      },

      sources = {
        default = { "lsp", "path", "buffer" },
        providers = {
          buffer = {
            name = "Buffer",
            score_offset = 25,
            min_keyword_length = 2,
            max_items = 3,
          },
          lsp = {
            min_keyword_length = 0,
            score_offset = 90,
            override = {
              -- A '.' triggers completion for faster import lookup.
              get_trigger_characters = function(self)
                local trigger_characters = self:get_trigger_characters()
                vim.list_extend(trigger_characters, { "." })
                return trigger_characters
              end,
            },
          },
          path = { min_keyword_length = 0 },
          -- Snippet completions stay hidden until a snippet story exists.
          snippets = {
            should_show_items = function()
              return false
            end,
          },
        },
      },
    },
  },
}
