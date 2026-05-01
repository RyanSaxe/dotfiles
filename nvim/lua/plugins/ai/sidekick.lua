-- Sidekick.nvim configuration
-- Provides Next Edit Suggestions (NES) from Copilot and neutral AI CLI integration.

return {
  "folke/sidekick.nvim",
  -- WORKAROUND: Prevent tmux backend from discovering external sessions
  --
  -- Problem: Setting mux.enabled = false only prevents CREATING new sessions in tmux,
  -- but sidekick still REGISTERS tmux as a backend and DISCOVERS existing sessions.
  --
  -- In session/init.lua:124-131, the setup function registers tmux if executable,
  -- without checking Config.cli.mux.enabled. This causes sidekick to find Claude
  -- sessions running in other tmux windows and show a picker to select between them.
  --
  -- What we want: Each Neovim instance should only see its own Claude terminal,
  -- never discover or attach to sessions from other tmux windows.
  --
  -- This workaround hooks into the Session module setup to prevent tmux/zellij
  -- from ever being registered, ensuring Session.sessions() only queries the
  -- "terminal" backend.
  --
  -- Ideally, sidekick should respect mux.enabled for both creation AND discovery,
  -- but until that's fixed upstream, this workaround is necessary.
  config = function(_, opts)
    -- Override Session.register to block tmux/zellij registration
    -- This must run before sidekick's setup, so we do it in config before calling setup
    local Session = require("sidekick.cli.session")
    local original_register = Session.register
    Session.register = function(name, backend)
      -- Only allow terminal backend, block tmux/zellij
      -- this is because I often have a bunch of claude code sessions NOT managed by sidekick
      -- and I don't want sidekick to try to attach to them
      if name ~= "tmux" and name ~= "zellij" then
        original_register(name, backend)
      end
    end

    -- Now call the default sidekick setup
    require("sidekick").setup(opts)
  end,
  opts = {
    nes = {
      -- Keep NES out of prose/note-taking buffers. The Copilot LSP is configured
      -- separately with the same filetype exclusions.
      enabled = function(buf)
        local ft = vim.bo[buf].filetype
        return ft ~= "markdown" and ft ~= "text" and ft ~= "typr"
      end,
      debounce = 100, -- ms to wait after typing stops before requesting suggestions
      diff = {
        inline = "words", -- Show word-level granularity in diffs
      },
    },

    -- AI CLI Terminal Integration
    cli = {
      -- Automatically check/reload unmodified buffers when AI tools edit files on disk.
      -- Git/mini.diff remains the rollback surface for agent edits.
      watch = true,

      -- Terminal window configuration
      win = {
        layout = "right", -- Open terminal on the right side
        split = {
          width = 60, -- Terminal width in columns
          height = 10, -- Terminal height (for horizontal splits)
        },
      },

      -- Session persistence via tmux (DISABLED)
      -- if I want to restore a session, I can use /resume with Claude Code
      -- and I would rather have all default sessions be their own unique terminal
      mux = {
        enabled = false,
        -- backend = "tmux",
      },

      -- Keep the Sidekick picker focused on installed CLIs you actually use.
      tools = {
        claude = {
          cmd = { "claude" },
        },
        codex = {
          cmd = { "codex" },
        },
        copilot = {
          cmd = { "copilot", "--banner" },
        },
      },

      -- Custom prompts for common workflows
      -- Use with <leader>aP to select a prompt
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
    -- NES in normal mode: Shift-Tab for consistency (Tab = normal completions, Shift-Tab = AI suggestions)
    -- Insert mode NES is handled in blink-cmp.lua's Shift-Tab handler
    { "<S-Tab>", LazyVim.cmp.map({ "ai_nes" }, "<S-Tab>"), mode = { "n" }, expr = true, desc = "Next Edit Suggestion" },

    -- AI leader key group
    { "<leader>a", "", desc = "+ai", mode = { "n", "v" } },

    -- Neutral AI CLI toggle/selectors
    {
      "<leader>ai",
      function() require("sidekick.cli").select({ filter = { installed = true } }) end,
      desc = "Select AI CLI",
    },
    {
      "<leader>ac",
      function() require("sidekick.cli").toggle({ name = "claude", focus = true }) end,
      desc = "Toggle Claude CLI",
    },
    {
      "<leader>ax",
      function() require("sidekick.cli").toggle({ name = "codex", focus = true }) end,
      desc = "Toggle Codex CLI",
    },
    {
      "<leader>ap",
      function() require("sidekick.cli").toggle({ name = "copilot", focus = true }) end,
      mode = { "n", "x" },
      desc = "Toggle Copilot CLI",
    },

    -- Detach/close CLI session
    {
      "<leader>ad",
      function() require("sidekick.cli").close() end,
      desc = "Detach a CLI Session",
    },

    -- Send context to the active Sidekick CLI
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
      "<leader>aP",
      function() require("sidekick.cli").prompt() end,
      mode = { "n", "x" },
      desc = "Sidekick Select Prompt",
    },
  },
}
