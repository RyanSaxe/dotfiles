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
  "│    \\h / \\l     Hide left / right pane       │",
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

local review_nav_wait_ms = 2500
local review_nav_poll_ms = 25
local pending_review_nav = {}
local next_review_step
local prev_review_step

local function now_ms()
  local uv = vim.uv or vim.loop
  return uv.now()
end

local function valid_win(winid)
  return type(winid) == "number" and vim.api.nvim_win_is_valid(winid)
end

local function get_lifecycle_session(tabpage)
  local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
  if not ok then
    return nil, nil
  end
  return lifecycle, lifecycle.get_session(tabpage)
end

local function diff_result_ready(session)
  return type(session) == "table"
    and type(session.stored_diff_result) == "table"
    and type(session.stored_diff_result.changes) == "table"
end

local function add_path_candidate(candidates, git_root, path)
  if not path or path == "" then
    return
  end

  candidates[path] = true
  if git_root and not path:match("^/") then
    candidates[git_root .. "/" .. path] = true
  end
end

local function session_matches_selection(session, selection, git_root)
  if not selection or not selection.path then
    return true
  end

  local candidates = {}
  add_path_candidate(candidates, git_root, selection.path)
  add_path_candidate(candidates, git_root, selection.old_path)

  return candidates[session.original_path] == true or candidates[session.modified_path] == true
end

local function session_file_key(session)
  if not session then
    return ""
  end

  return table.concat({
    session.original_path or "",
    session.modified_path or "",
    session.original_revision or "",
    session.modified_revision or "",
  }, "\0")
end

local function explorer_selection_key(explorer)
  if not explorer then
    return ""
  end

  local selection = explorer.current_selection
  if selection then
    return table.concat({
      selection.group or "",
      selection.path or "",
      selection.old_path or "",
      selection.status or "",
      selection.commit_hash or "",
    }, "\0")
  end

  return table.concat({
    explorer.current_file_group or "",
    explorer.current_file_path or "",
    explorer.current_commit or "",
    explorer.current_file or "",
  }, "\0")
end

local function current_diff_side(session)
  local current_buf = vim.api.nvim_get_current_buf()
  if current_buf == session.original_bufnr then
    return "original"
  end
  if current_buf == session.modified_bufnr then
    return "modified"
  end
  if valid_win(session.modified_win) then
    return "modified"
  end
  return "original"
end

local function preferred_diff_window(session, side)
  local primary = side == "original" and session.original_win or session.modified_win
  local fallback = side == "original" and session.modified_win or session.original_win

  if valid_win(primary) then
    return primary
  end
  if valid_win(fallback) then
    return fallback
  end
  return nil
end

local function clamp_line(winid, line)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  return math.max(1, math.min(line_count, line))
end

local function focus_line(winid, line)
  if not valid_win(winid) then
    return false
  end

  vim.api.nvim_set_current_win(winid)
  pcall(vim.api.nvim_win_set_cursor, winid, { clamp_line(winid, line), 0 })
  vim.cmd("normal! zz")
  return true
end

local function focus_single_file_boundary(session, direction)
  local winid = preferred_diff_window(session, "modified")
  if not winid then
    return false
  end

  local line = 1
  if direction == "prev" then
    line = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(winid))
  end
  return focus_line(winid, line)
end

local function focus_review_boundary(tabpage, direction)
  local _, session = get_lifecycle_session(tabpage)
  if not diff_result_ready(session) then
    return false
  end

  local changes = session.stored_diff_result.changes
  if #changes == 0 then
    return focus_single_file_boundary(session, direction)
  end

  local side = current_diff_side(session)
  local change_index = direction == "prev" and #changes or 1
  local change = changes[change_index]
  local range = side == "original" and change.original or change.modified
  local winid = preferred_diff_window(session, side)
  if not winid or not range then
    return false
  end

  local target_line = math.max(1, range.start_line or 1)
  if focus_line(winid, target_line) then
    vim.api.nvim_echo({ { string.format("Hunk %d of %d", change_index, #changes), "None" } }, false, {})
    return true
  end
  return false
end

local function wait_for_review_ready(tabpage, selection, previous_file_key, on_ready)
  local token = {}
  local deadline = now_ms() + review_nav_wait_ms
  pending_review_nav[tabpage] = token

  local function poll()
    if pending_review_nav[tabpage] ~= token then
      return
    end
    if not vim.api.nvim_tabpage_is_valid(tabpage) then
      pending_review_nav[tabpage] = nil
      return
    end

    local lifecycle, session = get_lifecycle_session(tabpage)
    local explorer = lifecycle and lifecycle.get_explorer(tabpage) or nil
    local git_root = explorer and explorer.git_root or (session and session.git_root or nil)
    local file_changed = not previous_file_key or session_file_key(session) ~= previous_file_key

    if diff_result_ready(session) and file_changed and session_matches_selection(session, selection, git_root) then
      pending_review_nav[tabpage] = nil
      if vim.api.nvim_get_current_tabpage() == tabpage then
        on_ready()
      end
      return
    end

    if now_ms() >= deadline then
      pending_review_nav[tabpage] = nil
      vim.notify("CodeDiff navigation timed out waiting for the diff to update", vim.log.levels.WARN)
      return
    end

    vim.defer_fn(poll, review_nav_poll_ms)
  end

  vim.defer_fn(poll, review_nav_poll_ms)
end

local function navigate_file_and_focus(direction)
  local tabpage = vim.api.nvim_get_current_tabpage()
  local lifecycle, session = get_lifecycle_session(tabpage)
  if not lifecycle or not session then
    return false
  end

  local navigation = require("codediff.ui.view.navigation")
  local explorer = lifecycle.get_explorer(tabpage)
  local before_selection_key = explorer_selection_key(explorer)
  local before_file_key = session_file_key(session)

  if direction == "prev" then
    navigation.prev_file()
  else
    navigation.next_file()
  end

  local after_selection_key = explorer_selection_key(explorer)
  local tracks_explorer_selection = explorer
    and (explorer.status_result ~= nil or explorer.current_selection ~= nil or explorer.current_file_path ~= nil)
  if tracks_explorer_selection and after_selection_key == before_selection_key then
    return false
  end

  local selection = explorer and explorer.current_selection and vim.deepcopy(explorer.current_selection) or nil
  wait_for_review_ready(tabpage, selection, before_file_key, function()
    focus_review_boundary(tabpage, direction)
  end)

  return true
end

local function review_step_when_ready(direction)
  local tabpage = vim.api.nvim_get_current_tabpage()
  wait_for_review_ready(tabpage, nil, nil, function()
    if direction == "prev" then
      prev_review_step()
    else
      next_review_step()
    end
  end)
end

local function collapse_diff_side(side)
  return function()
    local tabpage = vim.api.nvim_get_current_tabpage()
    local _, session = get_lifecycle_session(tabpage)
    if not session then
      return
    end

    if session.layout == "inline" or session.original_win == session.modified_win then
      vim.notify("CodeDiff has only one visible diff pane", vim.log.levels.WARN)
      return
    end
    if not valid_win(session.original_win) or not valid_win(session.modified_win) then
      vim.notify("CodeDiff side-by-side panes are not both available", vim.log.levels.WARN)
      return
    end

    local original_col = vim.api.nvim_win_get_position(session.original_win)[2]
    local modified_col = vim.api.nvim_win_get_position(session.modified_win)[2]
    local left_win = original_col <= modified_col and session.original_win or session.modified_win
    local right_win = left_win == session.original_win and session.modified_win or session.original_win
    local hide_win = side == "left" and left_win or right_win
    local show_win = side == "left" and right_win or left_win
    local available_width = vim.api.nvim_win_get_width(left_win) + vim.api.nvim_win_get_width(right_win)
    local hidden_width = 1
    local visible_width = math.max(1, available_width - hidden_width)

    vim.api.nvim_set_current_win(show_win)

    local previous_winminwidth = vim.o.winminwidth
    local previous_winwidth = vim.o.winwidth
    vim.o.winminwidth = 1
    vim.o.winwidth = 1

    pcall(vim.api.nvim_win_set_width, show_win, visible_width)
    pcall(vim.api.nvim_win_set_width, hide_win, hidden_width)
    pcall(vim.api.nvim_win_set_width, show_win, visible_width)

    vim.o.winwidth = previous_winwidth
    vim.o.winminwidth = previous_winminwidth
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

next_review_step = function()
  local tabpage = vim.api.nvim_get_current_tabpage()
  local _, session = get_lifecycle_session(tabpage)
  if not session then
    return
  end
  if not diff_result_ready(session) then
    review_step_when_ready("next")
    return
  end

  local changes = session.stored_diff_result.changes
  if #changes == 0 then
    navigate_file_and_focus("next")
    return
  end

  local navigation = require("codediff.ui.view.navigation")
  if not navigation.next_hunk() then
    navigate_file_and_focus("next")
  end
end

prev_review_step = function()
  local tabpage = vim.api.nvim_get_current_tabpage()
  local _, session = get_lifecycle_session(tabpage)
  if not session then
    return
  end
  if not diff_result_ready(session) then
    review_step_when_ready("prev")
    return
  end

  local changes = session.stored_diff_result.changes
  if #changes == 0 then
    navigate_file_and_focus("prev")
    return
  end

  local navigation = require("codediff.ui.view.navigation")
  if navigation.prev_hunk() then
    return
  end

  navigate_file_and_focus("prev")
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
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.shrink_width, collapse_diff_side("left"), {
      desc = "Hide left CodeDiff pane",
    })
  end

  if keymaps.grow_width then
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.grow_width, collapse_diff_side("right"), {
      desc = "Hide right CodeDiff pane",
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
