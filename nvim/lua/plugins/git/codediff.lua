-- codediff.nvim - VSCode-style side-by-side diffs with git integration
-- Replaces diffview.nvim with better git difftool/mergetool support
--
-- Usage:
--   :CodeDiff                     - Explorer showing git status (staged/unstaged)
--   :CodeDiff origin/main         - Compare working tree vs ref
--   :CodeDiff origin/main HEAD    - Compare two refs (for PR review)
--   :CodeDiff file HEAD           - Compare current buffer vs ref
--   :CodeDiff merge $MERGED       - Merge conflict resolution

-- Help popup content for codediff keybindings
local help_lines = {
  "╭─────────────────────────────────────────────╮",
  "│           CodeDiff Keybindings              │",
  "├─────────────────────────────────────────────┤",
  "│  Navigation                                 │",
  "│    ]c / [c     Next / previous hunk         │",
  "│    ]f / [f     Next / previous file         │",
  "│    <CR>        Open file (in explorer)      │",
  "│                                             │",
  "│  Actions                                    │",
  "│    do          Get change from other buffer │",
  "│    dp          Put change to other buffer   │",
  "│    -           Stage / unstage file         │",
  "│    S / U       Stage / unstage all          │",
  "│    X           Discard changes (restore)    │",
  "│    R           Refresh                      │",
  "│    i           Toggle list / tree view      │",
  "│                                             │",
  "│  Conflict Resolution                        │",
  "│    co          Accept current (ours)        │",
  "│    ci          Accept incoming (theirs)     │",
  "│    ca          Accept both                  │",
  "│    ]x / [x     Next / previous conflict     │",
  "│                                             │",
  "│  General                                    │",
  "│    q           Close codediff               │",
  "│    <leader>b   Toggle explorer visibility   │",
  "│    ?           Show this help               │",
  "╰─────────────────────────────────────────────╯",
}

-- Show help popup in a floating window
local function show_help()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  -- Calculate window size and position
  local width = 47 -- matches the box width
  local height = #help_lines
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "none", -- we have our own border in the content
  })

  -- Close on any key press
  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "?", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<CR>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })
end

return {
  "esmuellert/codediff.nvim",
  dependencies = { "MunifTanjim/nui.nvim", "folke/snacks.nvim" },
  cmd = { "CodeDiff" },
  keys = {
    -- File diff: current buffer against a ref
    {
      "<leader>gdf",
      function()
        require("custom.git.diff").pick_file_diff_commit()
      end,
      desc = "File Diff (pick commit)",
    },
    {
      "<leader>gdF",
      function()
        require("custom.git.diff").pick_file_diff_branch()
      end,
      desc = "File Diff (pick branch)",
    },
    -- All files diff: explorer showing all changes
    {
      "<leader>gda",
      function()
        require("custom.git.diff").pick_all_diff_commit()
      end,
      desc = "All Files Diff (pick commit)",
    },
    {
      "<leader>gdA",
      function()
        require("custom.git.diff").pick_all_diff_branch()
      end,
      desc = "All Files Diff (pick branch)",
    },
  },
  opts = {
    explorer = {
      position = "bottom", -- match previous diffview layout
      height = 10, -- match previous diffview height
      view_mode = "list", -- "list" or "tree"
    },
    diff = {
      original_position = "left", -- original (old) content on left
      disable_inlay_hints = true, -- inlay hints don't work well with diff highlighting
    },
    keymaps = {
      view = {
        quit = "q",
        next_hunk = "]c",
        prev_hunk = "[c",
      },
      explorer = {
        quit = "q",
        open = "<CR>",
        next_file = "j",
        prev_file = "k",
      },
      conflict = {
        accept_current = "co", -- ours
        accept_incoming = "ci", -- theirs
        accept_both = "ca",
        next_conflict = "]x",
        prev_conflict = "[x",
      },
    },
  },
  config = function(_, opts)
    require("codediff").setup(opts)

    -- Add ? keymap for help in codediff buffers
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "codediff", "codediff-explorer" },
      callback = function(ev)
        vim.keymap.set("n", "?", show_help, {
          buffer = ev.buf,
          desc = "Show CodeDiff help",
        })
      end,
    })

    -- Also trigger on vscode-diff:// buffers (virtual diff files)
    vim.api.nvim_create_autocmd("BufEnter", {
      pattern = "vscode-diff://*",
      callback = function(ev)
        vim.keymap.set("n", "?", show_help, {
          buffer = ev.buf,
          desc = "Show CodeDiff help",
        })
      end,
    })

    -- Disable inlay hints when LSP attaches to buffers in codediff tabs.
    -- The built-in disable_inlay_hints fires once at session creation, but:
    -- 1. LSP may attach later and re-enable hints
    -- 2. view.update() loads new buffers without disabling hints
    -- 3. LspAttach fires during bufload() BEFORE the buffer is in the window
    -- So we check if the current tab has a codediff session instead.
    vim.api.nvim_create_autocmd("LspAttach", {
      callback = function(ev)
        vim.schedule(function()
          local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
          if ok then
            local current_tab = vim.api.nvim_get_current_tabpage()
            if lifecycle.get_session(current_tab) then
              vim.lsp.inlay_hint.enable(false, { bufnr = ev.buf })
            end
          end
        end)
      end,
    })
  end,
}
