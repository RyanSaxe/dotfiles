-- obsidian.nvim  ── Obsidian vault integration for note-taking
-- Provides wiki-link completion, daily notes, templates, and navigation
-- Integrates with blink.cmp for @ completion of people notes

return {
  "obsidian-nvim/obsidian.nvim",
  enabled = true,
  version = "v3.13.0", -- Pinned to avoid buggy LSP-based link following in v3.14.0+
  lazy = true,
  -- Load when opening markdown files or when in the notes directory
  ft = "markdown",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  opts = {
    workspaces = {
      {
        name = "notes",
        path = "~/generic/notes",
      },
    },

    -- Link style configuration
    preferred_link_style = "wiki",

    -- Daily notes configuration
    -- Daily notes are stored in the daily/ folder with YYYY-MM-DD.md format
    daily_notes = {
      folder = "daily",
      date_format = "%Y-%m-%d",
      -- Template to use for new daily notes
      -- Will look for templates/daily.md
      template = "daily",
    },

    -- Templates configuration
    -- Templates are stored in the templates/ folder
    templates = {
      folder = "templates",
      date_format = "%Y-%m-%d",
      time_format = "%H:%M",
    },

    -- Completion configuration
    -- This enables @ completion for people notes in the people/ folder
    completion = {
      nvim_cmp = false, -- We're using blink.cmp instead
      blink = true, -- Enable blink.cmp integration (v3.13.0+)
      min_chars = 0, -- Start completing after 1 character
      create_new = false, -- Disable "create" in completions, use <leader>on instead
    },

    -- Note path and ID functions
    -- This ensures notes are created with proper naming
    note_id_func = function(title)
      -- If no title is provided, use timestamp
      if title == nil then
        return tostring(os.time())
      end
      -- Convert title to lowercase with hyphens (first-last format)
      return title:gsub(" ", "-"):gsub("[^A-Za-z0-9-]", ""):lower()
    end,

    -- Note path function
    -- Determines where notes are created based on type
    note_path_func = function(spec)
      -- For daily notes, use the daily/ folder (handled by daily_notes config)
      -- For regular notes, use the vault root
      local path = spec.dir / spec.id
      return path:with_suffix(".md")
    end,

    -- Wiki link handling
    -- Creates [[first-last]] style links
    wiki_links = {
      enabled = true,
      brackets = "[[",
    },

    -- Checkbox configuration
    -- The 'checkbox' table defines the order when cycling through states
    checkbox = {
      -- Order that checkboxes cycle through when toggled
      order = { " ", "x" },
    },

    -- UI configuration for checkbox visual representation
    ui = { enable = false },

    -- Follow link behavior
    follow_url_func = function(url)
      -- Open URLs in default browser
      vim.fn.jobstart({ "open", url })
    end,

    -- Picker configuration
    -- Use snacks picker (modern, integrated picker)
    picker = {
      name = "snacks.pick",
      note_mappings = {
        new = "<C-x>",
        insert_link = "<C-l>",
      },
      tag_mappings = {
        tag_note = "<C-x>",
        insert_tag = "<C-l>",
      },
    },

    -- Attachments configuration
    attachments = {
      img_folder = "assets",
    },
  },

  -- Keybindings for obsidian commands (using <leader>o prefix)
  keys = {
    -- Daily notes
    { "<leader>od", "<cmd>ObsidianToday<cr>", desc = "Open today's daily note" },
    { "<leader>oy", "<cmd>ObsidianYesterday<cr>", desc = "Open yesterday's daily note" },
    { "<leader>oD", "<cmd>ObsidianTomorrow<cr>", desc = "Open tomorrow's daily note" },

    -- Note creation and search
    {
      "<leader>on",
      function()
        require("custom.obsidian.create-note").prompt_and_create()
      end,
      desc = "Create new note (with directory picker)",
    },
    { "<leader>of", "<cmd>ObsidianQuickSwitch<cr>", desc = "Find note" },
    { "<leader>os", "<cmd>ObsidianSearch<cr>", desc = "Search in notes" },

    -- Navigation
    { "<leader>ob", "<cmd>ObsidianBacklinks<cr>", desc = "Show backlinks" },
    { "<leader>ol", "<cmd>ObsidianLinks<cr>", desc = "Show links in current note" },
    { "gf", "<cmd>ObsidianFollowLink<cr>", desc = "Follow link under cursor", ft = "markdown" },

    -- Templates
    { "<leader>oT", "<cmd>ObsidianTemplate<cr>", desc = "Insert template" },

    -- Tasks
    {
      "<leader>ot",
      function()
        require("custom.obsidian.tasks").open_picker()
      end,
      desc = "Show all incomplete tasks",
    },

    -- Date insertion
    -- Works in any file type to support TODO.local files (not just markdown)
    {
      "<leader>oi",
      function()
        require("custom.obsidian.insert-due").insert_due_date()
      end,
      desc = "Insert due date",
    },

    -- Utility
    { "<leader>ow", "<cmd>ObsidianWorkspace<cr>", desc = "Switch workspace" },
    { "<leader>ox", "<cmd>ObsidianToggleCheckbox<cr>", desc = "Toggle checkbox" },
  },

  config = function(_, opts)
    local obsidian = require("obsidian")
    obsidian.setup(opts)
  end,
}
