-- Sidekick.nvim configuration
-- Provides Next Edit Suggestions (NES) from Copilot and Claude Code CLI integration
-- This overrides the LazyVim extras config to use Claude exclusively

return {
  "folke/sidekick.nvim",
  opts = {
    -- Next Edit Suggestions (NES) configuration
    nes = {
      enabled = true,
      debounce = 100, -- ms to wait after typing stops before requesting suggestions
      -- Diff visualization settings
      diff = {
        inline = "words", -- Show word-level granularity in diffs
      },
    },

    -- AI CLI Terminal Integration
    cli = {
      watch = true, -- Automatically reload files when modified by AI tools

      -- Terminal window configuration
      win = {
        layout = "right", -- Open terminal on right side (good for wide monitors)
        split = {
          width = 80, -- Terminal width in columns
          height = 20, -- Terminal height (for horizontal splits)
        },
      },

      -- Session persistence via tmux (DISABLED - Claude Code has native session management)
      mux = {
        enabled = false, -- Claude Code already handles sessions with --resume
        backend = "tmux",
      },

      -- CLI Tools configuration - CLAUDE ONLY
      -- This overrides the default 10+ tools (aider, copilot, gemini, grok, etc.)
      tools = {
        claude = {
          cmd = { "claude" }, -- Uses the installed Claude CLI at /opt/homebrew/bin/claude
          -- Claude Code has native session management, no special flags needed
        },
        -- All other tools (aider, amazon_q, codex, copilot, crush, cursor, gemini, grok, opencode, qwen) are removed
        -- Only Claude will appear in the tool selection menu
      },

      -- Custom prompts for common workflows
      -- Use with <leader>ap to select a prompt
      prompts = {
        -- Existing prompts from LazyVim extras (these are good!)
        changes = "Can you review my changes?",
        diagnostics = "Can you help me fix the diagnostics in {file}?\n{diagnostics}",
        diagnostics_all = "Can you help me fix these diagnostics?\n{diagnostics_all}",
        document = "Add documentation to {function|line}",
        explain = "Explain {this}",
        fix = "Can you fix {this}?",
        optimize = "How can {this} be optimized?",
        review = "Can you review {file} for any issues or improvements?",
        tests = "Can you write tests for {this}?",

        -- Additional custom prompts for your workflow
        refactor = "Refactor {this} to be more maintainable and follow best practices",
        security = "Review {file} for security vulnerabilities and potential issues",
        performance = "Analyze {this} for performance bottlenecks and suggest optimizations",
        simplify = "Simplify {this} - make it more readable and easier to understand",

        -- Context-only prompts (just send context without a specific question)
        buffers = "{buffers}",
        file = "{file}",
        line = "{line}",
        position = "{position}",
        quickfix = "{quickfix}",
        selection = "{selection}",
        ["function"] = "{function}",
        class = "{class}",
      },

      -- Preferred picker for file/buffer selection
      picker = "snacks", -- Uses Snacks.nvim picker (you have snacks_picker enabled)
    },

    -- Copilot LSP status tracking
    copilot = {
      status = {
        enabled = true,
        level = vim.log.levels.WARN, -- Only show warnings/errors, not info
      },
    },

    -- Debug mode (set to true for troubleshooting)
    debug = false,
  },

  -- Keybindings - these match the LazyVim extras defaults
  -- stylua: ignore
  keys = {
    -- NES navigation in normal mode (Tab already handled in blink-cmp.lua for insert mode)
    { "<tab>", LazyVim.cmp.map({ "ai_nes" }, "<tab>"), mode = { "n" }, expr = true, desc = "Next Edit Suggestion" },

    -- AI leader key group
    { "<leader>a", "", desc = "+ai", mode = { "n", "v" } },

    -- Toggle Claude CLI terminal
    {
      "<c-.>",
      function() require("sidekick.cli").toggle() end,
      desc = "Sidekick Toggle",
      mode = { "n", "t", "i", "x" },
    },
    {
      "<leader>aa",
      function() require("sidekick.cli").toggle() end,
      desc = "Sidekick Toggle CLI",
    },

    -- Select CLI tool (will only show Claude since other tools are removed)
    {
      "<leader>as",
      function() require("sidekick.cli").select() end,
      desc = "Select CLI",
    },

    -- Detach/close CLI session
    {
      "<leader>ad",
      function() require("sidekick.cli").close() end,
      desc = "Detach a CLI Session",
    },

    -- Send context to Claude
    {
      "<leader>at",
      function() require("sidekick.cli").send({ msg = "{this}" }) end,
      mode = { "x", "n" },
      desc = "Send This",
    },
    {
      "<leader>af",
      function() require("sidekick.cli").send({ msg = "{file}" }) end,
      desc = "Send File",
    },
    {
      "<leader>av",
      function() require("sidekick.cli").send({ msg = "{selection}" }) end,
      mode = { "x" },
      desc = "Send Visual Selection",
    },

    -- Prompt library
    {
      "<leader>ap",
      function() require("sidekick.cli").prompt() end,
      mode = { "n", "x" },
      desc = "Sidekick Select Prompt",
    },

    -- Direct Claude toggle (same as <C-.> but with mnemonic <leader>ac for "AI Claude")
    {
      "<leader>ac",
      function() require("sidekick.cli").toggle({ name = "claude", focus = true }) end,
      desc = "Sidekick Toggle Claude",
    },

    -- Toggle NES on/off (useful for debugging or when it's distracting)
    {
      "<leader>uN",
      function()
        Snacks.toggle({
          name = "Sidekick NES",
          get = function()
            return require("sidekick.nes").enabled
          end,
          set = function(state)
            require("sidekick.nes").enable(state)
          end,
        })()
      end,
      desc = "Toggle Sidekick NES",
    },
  },
}
