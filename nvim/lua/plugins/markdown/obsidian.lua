-- obsidian.nvim  ── Obsidian vault integration for note-taking
-- Provides wiki-link completion, daily notes, templates, and navigation.

return {
  "obsidian-nvim/obsidian.nvim",
  enabled = true,
  version = "v3.16.2",
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

    legacy_commands = false,

    -- Keep links Obsidian-compatible while preferring the shortest readable path.
    link = {
      style = "wiki",
      format = "shortest",
      auto_update = false,
    },

    -- Daily notes configuration
    -- Daily notes are stored in the daily/ folder with YYYY-MM-DD.md format
    daily_notes = {
      enabled = true,
      folder = "daily",
      date_format = "%Y-%m-%d",
      -- Template to use for new daily notes
      -- Will look for templates/daily.md
      template = "daily",
    },

    -- Templates configuration
    -- Templates are stored in the templates/ folder
    templates = {
      enabled = true,
      folder = "templates",
      date_format = "%Y-%m-%d",
      time_format = "%H:%M",
    },

    -- Completion configuration
    completion = {
      nvim_cmp = false, -- We're using blink.cmp instead
      blink = true, -- Enable blink.cmp integration (v3.13.0+)
      min_chars = 1,
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
      local path = spec.dir / spec.id
      return path:with_suffix(".md")
    end,

    -- Checkbox configuration
    -- The 'checkbox' table defines the order when cycling through states
    checkbox = {
      -- Order that checkboxes cycle through when toggled
      order = { " ", "x" },
    },

    -- UI configuration for checkbox visual representation
    ui = { enable = false },

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
      folder = "assets",
      confirm_img_paste = true,
    },
  },

  -- Keybindings for obsidian commands (using <leader>o prefix)
  keys = {
    -- Daily notes
    { "<leader>od", "<cmd>Obsidian today<cr>", desc = "Open today's daily note" },
    { "<leader>oy", "<cmd>Obsidian today -1<cr>", desc = "Open yesterday's daily note" },
    { "<leader>oD", "<cmd>Obsidian today 1<cr>", desc = "Open tomorrow's daily note" },

    -- Note creation and search
    {
      "<leader>on",
      function()
        require("custom.obsidian.create-note").prompt_and_create()
      end,
      desc = "Create new note (with directory picker)",
    },
    { "<leader>of", "<cmd>Obsidian quick_switch<cr>", desc = "Find note" },
    { "<leader>os", "<cmd>Obsidian search<cr>", desc = "Search in notes" },
    { "<leader>og", "<cmd>Obsidian tags<cr>", desc = "Search tags" },

    -- Navigation
    { "<leader>ob", "<cmd>Obsidian backlinks<cr>", desc = "Show backlinks" },
    { "<leader>ol", "<cmd>Obsidian links<cr>", desc = "Show links in current note" },
    { "<leader>oo", "<cmd>Obsidian open<cr>", desc = "Open current note in Obsidian" },
    { "<leader>op", "<cmd>Obsidian paste_img<cr>", desc = "Paste image into note" },
    -- v3.16+ configures includeexpr, so keep native gf behavior.

    -- Templates
    { "<leader>oT", "<cmd>Obsidian template<cr>", desc = "Insert template" },

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
      "<leader>om",
      function()
        require("custom.obsidian.meeting").insert_meeting()
      end,
      desc = "Insert meeting heading",
      ft = "markdown",
    },
    {
      "<leader>oi",
      function()
        require("custom.obsidian.insert-due").insert_due_date()
      end,
      desc = "Insert due date",
    },

    -- Utility
    { "<leader>ow", "<cmd>Obsidian workspace<cr>", desc = "Switch workspace" },
    { "<leader>ox", "<cmd>Obsidian toggle_checkbox<cr>", desc = "Toggle checkbox" },
    { "<leader>oc", "<cmd>Obsidian check<cr>", desc = "Check vault" },
    { "<leader>oC", "<cmd>checkhealth obsidian custom.markdown render-markdown<cr>", desc = "Check markdown health" },
  },

  config = function(_, opts)
    local obsidian = require("obsidian")
    obsidian.setup(opts)

    vim.api.nvim_create_user_command("ObsidianMeeting", function()
      require("custom.obsidian.meeting").insert_meeting()
    end, { desc = "Insert a daily-note meeting heading" })
  end,
}
