-- obsidian.nvim  ── Obsidian vault integration for note-taking
-- Provides wiki-link completion, daily notes, templates, and navigation
-- Integrates with blink.cmp for @ completion of people notes

return {
  "epwalsh/obsidian.nvim",
  enabled = true,
  version = "*",
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

    -- Daily notes configuration
    -- Daily notes are stored in the daily/ folder with YYYY-MM-DD.md format
    daily_notes = {
      folder = "daily",
      date_format = "%Y-%m-%d",
      -- Template to use for new daily notes (optional)
      -- Will look for templates/daily.md
      template = nil,
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
      min_chars = 1, -- Start completing after 1 character
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

    -- Disable some features we don't need
    ui = {
      enable = true, -- Enable UI improvements for markdown
      checkboxes = {
        -- Use standard markdown checkboxes
        [" "] = { char = "󰄱", hl_group = "ObsidianTodo" },
        ["x"] = { char = "", hl_group = "ObsidianDone" },
        [">"] = { char = "", hl_group = "ObsidianRightArrow" },
        ["~"] = { char = "󰰱", hl_group = "ObsidianTilde" },
      },
    },

    -- Follow link behavior
    follow_url_func = function(url)
      -- Open URLs in default browser
      vim.fn.jobstart({ "open", url })
    end,

    -- Picker configuration
    -- Use fzf-lua for pickers (consistent with rest of config)
    picker = {
      name = "fzf-lua",
      mappings = {
        new = "<C-x>",
        insert_link = "<C-l>",
      },
    },

    -- Attachments configuration
    attachments = {
      img_folder = "assets",
    },
  },

  -- Keybindings for obsidian commands
  keys = {
    -- Daily notes
    { "<leader>nd", "<cmd>ObsidianToday<cr>", desc = "Open today's daily note" },
    { "<leader>ny", "<cmd>ObsidianYesterday<cr>", desc = "Open yesterday's daily note" },
    { "<leader>nD", "<cmd>ObsidianTomorrow<cr>", desc = "Open tomorrow's daily note" },

    -- Note creation and search
    { "<leader>nn", "<cmd>ObsidianNew<cr>", desc = "Create new note" },
    { "<leader>nf", "<cmd>ObsidianQuickSwitch<cr>", desc = "Find note" },
    { "<leader>ns", "<cmd>ObsidianSearch<cr>", desc = "Search in notes" },

    -- Navigation
    { "<leader>nb", "<cmd>ObsidianBacklinks<cr>", desc = "Show backlinks" },
    { "<leader>nl", "<cmd>ObsidianLinks<cr>", desc = "Show links in current note" },
    { "gf", "<cmd>ObsidianFollowLink<cr>", desc = "Follow link under cursor", ft = "markdown" },

    -- Templates
    { "<leader>nt", "<cmd>ObsidianTemplate<cr>", desc = "Insert template" },

    -- Utility
    { "<leader>nw", "<cmd>ObsidianWorkspace<cr>", desc = "Switch workspace" },
    { "<leader>nx", "<cmd>ObsidianToggleCheckbox<cr>", desc = "Toggle checkbox" },
  },

  config = function(_, opts)
    local obsidian = require("obsidian")
    obsidian.setup(opts)

    -- The @ people completion is handled by a custom blink.cmp source
    -- See: nvim/lua/custom/completion/obsidian-people.lua
    -- Integration: nvim/lua/plugins/blink-cmp.lua
  end,
}
