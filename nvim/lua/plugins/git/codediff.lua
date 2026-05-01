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
  "│    <Tab>       Next hunk, else next file    │",
  "│    <S-Tab>     Prev hunk, else prev file    │",
  "│    ]h / [h     Next / previous hunk         │",
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
  "│    \\t          Toggle inline / side-by-side │",
  "│    \\=          Equalize layout              │",
  "│    \\h / \\l     Shrink / grow width          │",
  "│    \\j / \\k     Shrink / grow height         │",
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
  local width = 0
  for _, line in ipairs(help_lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
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

local function equalize_layout()
  local ok, layout = pcall(require, "codediff.ui.layout")
  if ok then
    layout.arrange(vim.api.nvim_get_current_tabpage())
  end
end

local function resize_window(width_delta, height_delta)
  return function()
    local win = vim.api.nvim_get_current_win()
    if not vim.api.nvim_win_is_valid(win) then
      return
    end

    if width_delta then
      local width = math.max(20, vim.api.nvim_win_get_width(win) + width_delta)
      pcall(vim.api.nvim_win_set_width, win, width)
    end

    if height_delta then
      local height = math.max(5, vim.api.nvim_win_get_height(win) + height_delta)
      pcall(vim.api.nvim_win_set_height, win, height)
    end
  end
end

local function next_review_step()
  local navigation = require("codediff.ui.view.navigation")
  if not navigation.next_hunk() then
    navigation.next_file()
  end
end

local function prev_review_step()
  local lifecycle = require("codediff.ui.lifecycle")
  local navigation = require("codediff.ui.view.navigation")

  if navigation.prev_hunk() then
    return
  end

  if not navigation.prev_file() then
    return
  end

  local session = lifecycle.get_session(vim.api.nvim_get_current_tabpage())
  if not session or not session.modified_bufnr or not session.modified_win then
    return
  end
  if not vim.api.nvim_buf_is_valid(session.modified_bufnr) or not vim.api.nvim_win_is_valid(session.modified_win) then
    return
  end

  vim.api.nvim_set_current_win(session.modified_win)
  local last_line = vim.api.nvim_buf_line_count(session.modified_bufnr)
  pcall(vim.api.nvim_win_set_cursor, session.modified_win, { last_line, 0 })
  navigation.prev_hunk()
end

local function setup_custom_keymaps(tabpage, keymaps)
  local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
  if not ok or not lifecycle.get_session(tabpage) then
    return
  end

  if keymaps.help_popup then
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.help_popup, show_help, {
      desc = "Show CodeDiff help",
    })
  end

  if keymaps.next_review_step then
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.next_review_step, next_review_step, {
      desc = "Next hunk, else next file",
    })
  end

  if keymaps.prev_review_step then
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.prev_review_step, prev_review_step, {
      desc = "Previous hunk, else previous file",
    })
  end

  if keymaps.equalize_layout then
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.equalize_layout, equalize_layout, {
      desc = "Equalize CodeDiff layout",
    })
  end

  if keymaps.shrink_width then
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.shrink_width, resize_window(-10, nil), {
      desc = "Shrink current CodeDiff window width",
    })
  end

  if keymaps.grow_width then
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.grow_width, resize_window(10, nil), {
      desc = "Grow current CodeDiff window width",
    })
  end

  if keymaps.shrink_height then
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.shrink_height, resize_window(nil, -5), {
      desc = "Shrink current CodeDiff window height",
    })
  end

  if keymaps.grow_height then
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.grow_height, resize_window(nil, 5), {
      desc = "Grow current CodeDiff window height",
    })
  end
end

local function ensure_custom_reapply(tabpage, keymaps)
  local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
  if not ok then
    return
  end

  local session = lifecycle.get_session(tabpage)
  if not session or session.custom_keymaps_wrapped then
    return
  end

  local original_reapply = session.reapply_keymaps
  session.reapply_keymaps = function()
    if original_reapply then
      original_reapply()
    end
    setup_custom_keymaps(tabpage, keymaps)
  end
  session.custom_keymaps_wrapped = true
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
        require("custom.git.diff").pick_file_diff_branch()
      end,
      desc = "File Diff (pick branch)",
    },
    {
      "<leader>gdF",
      function()
        require("custom.git.diff").pick_file_diff_commit()
      end,
      desc = "File Diff (pick commit)",
    },
    -- All files diff: explorer showing all changes
    {
      "<leader>gda",
      function()
        require("custom.git.diff").pick_all_diff_branch()
      end,
      desc = "All Files Diff (pick branch)",
    },
    {
      "<leader>gdA",
      function()
        require("custom.git.diff").pick_all_diff_commit()
      end,
      desc = "All Files Diff (pick commit)",
    },
  },
  opts = {
    explorer = {
      position = "bottom", -- match previous diffview layout
      height = 10, -- match previous diffview height
      view_mode = "list", -- "list" or "tree"
      focus_on_select = true,
    },
    diff = {
      original_position = "left", -- original (old) content on left
      disable_inlay_hints = true, -- inlay hints don't work well with diff highlighting
      cycle_next_hunk = false,
      cycle_next_file = false,
      jump_to_first_change = true,
    },
    keymaps = {
      view = {
        quit = "q",
        next_hunk = "]h",
        prev_hunk = "[h",
        next_file = "]f",
        prev_file = "[f",
        toggle_layout = "<localleader>t",
        equalize_layout = "<localleader>=",
        shrink_width = "<localleader>h",
        grow_width = "<localleader>l",
        shrink_height = "<localleader>j",
        grow_height = "<localleader>k",
        next_review_step = "<Tab>",
        prev_review_step = "<S-Tab>",
        help_popup = "?",
      },
      explorer = {
        select = "<CR>",
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
    local augroup = vim.api.nvim_create_augroup("custom-codediff", { clear = true })

    vim.api.nvim_create_autocmd("BufEnter", {
      group = augroup,
      callback = function()
        local tabpage = vim.api.nvim_get_current_tabpage()
        vim.schedule(function()
          ensure_custom_reapply(tabpage, opts.keymaps.view)
          setup_custom_keymaps(tabpage, opts.keymaps.view)
        end)
      end,
    })

    -- Disable inlay hints when LSP attaches to buffers in codediff tabs.
    -- The built-in disable_inlay_hints fires once at session creation, but:
    -- 1. LSP may attach later and re-enable hints
    -- 2. view.update() loads new buffers without disabling hints
    -- 3. LspAttach fires during bufload() BEFORE the buffer is in the window
    -- So we check if the current tab has a codediff session instead.
    vim.api.nvim_create_autocmd("LspAttach", {
      group = augroup,
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
