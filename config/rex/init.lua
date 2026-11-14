-- Rex configuration: Rex's own default keys, the tmux keys from
-- tmux/tmux.conf bound to the Rex actions that do the same thing, and popups
-- for `ws` and copy mode. Font and padding are app settings, not Lua.
--
-- Rex's Dark Mode and Light Mode themes are Catppuccin Mocha and Latte,
-- imported in the app from https://github.com/catppuccin/ghostty.
--
-- The app handles no keys while an action that a key started is running, so
-- every action here returns at once and waits on nothing it starts.
--
-- These tmux keys stay unbound on purpose: Alt-Q, Alt-Comma, Alt-Period,
-- Alt-Shift-R, Alt-Shift-T, and prefix r, comma and $.

local SHELL = "com.superlogical.terminal.shell"
local TERMINAL = "com.superlogical.terminal"
-- ~/.config/rex links to this directory, so the scripts sit beside this file.
local REX_DIR = debug.getinfo(1, "S").source:match("^@?(.*)/")
local PREFIX = "ctrl+space>"

local function open_float(label, command)
  local _, err = rex.session.new_layer({
    bounds = { 0.08, 0.08, 0.84, 0.84 },
    focus = true,
    layout = rex.layout.block({ flavor = SHELL, label = label, options = { command = command } }),
  })
  if err ~= nil then
    error(err, 0)
  end
end

-- The programs that use Ctrl-H/J/K/L and Ctrl-B/F/U/D themselves, from the
-- is_vim test in tmux.conf. fzf is one so those keys move its selection.
local EDITORS = { nvim = true, vim = true, vi = true, view = true, vimdiff = true, fzf = true }

local function in_float(block_id)
  local view = rex.session.view({})
  for _, window in ipairs(view and view.windows or {}) do
    for _, layer in ipairs(window.layers) do
      for _, block in ipairs(layer.kind == "floating" and layer.blocks or {}) do
        if block.block_id == block_id then
          return true
        end
      end
    end
  end
  return false
end

-- Those keys go to an editor in any pane, and to any program in a float, as
-- they did in a tmux popup. A float's program can sit behind a shell, so its
-- name isn't a reliable test there.
local function program_takes_keys(block_id)
  local process = rex.block.call(TERMINAL, "process", { block_id = block_id })
  local foreground = process and process.foreground
  return foreground ~= nil and EDITORS[foreground.name] == true or in_float(block_id)
end

-- Rex keeps no focus history yet, so Alt-L and prefix l and L read this list
-- of the 50 panes that moves last started from, newest first. It lives in
-- the server's Lua state and starts empty when the config reloads.
local history = {}

local function remember(ctx)
  for i = #history, 1, -1 do
    if history[i].block_id == ctx.block_id then
      table.remove(history, i)
    end
  end
  table.insert(history, 1, { session_id = ctx.session_id, block_id = ctx.block_id })
  history[51] = nil
end

-- Focuses a pane in any session. The server focuses it first, so the app
-- lands on it when it switches session. Returns false for a closed pane.
local function go_to(ctx, pane)
  local found = rex.session.describe_block({ session_id = pane.session_id, block_id = pane.block_id })
  if not found then
    return false
  end
  rex.session.focus_block({ session_id = pane.session_id, block_id = pane.block_id })
  remember(ctx)
  if pane.session_id ~= ctx.session_id then
    rex.client.queue("session.select", { session_id = pane.session_id, window_id = found.block.window_id })
  end
  return true
end

-- Goes back to the newest remembered pane that `wanted` accepts.
local function back(ctx, wanted)
  local i = 1
  while history[i] do
    local pane = history[i]
    if pane.block_id == ctx.block_id or not wanted(pane) then
      i = i + 1
    elseif go_to(ctx, pane) then
      return
    else
      table.remove(history, i)
    end
  end
end

local function windows_of_blocks(session_id)
  local windows = {}
  local list = rex.session.list_blocks({ session_id = session_id })
  for _, block in ipairs(list and list.blocks or {}) do
    windows[block.block_id] = block.window_id
  end
  return windows
end

-- Moves that Alt-L should come back from run through this action, which
-- notes the pane the move starts from and then runs the Rex action.
rex.action({
  name = "move",
  title = "Move and Remember the Pane",
  args = { action = "string", args = "object?" },
  run = function(ctx, args)
    remember(ctx)
    rex.client.queue(args.action, args.args)
  end,
})

rex.action({
  name = "last_pane",
  title = "Last Pane",
  run = function(ctx)
    back(ctx, function()
      return true
    end)
  end,
})

rex.action({
  name = "last_tab",
  title = "Last Tab",
  run = function(ctx)
    local windows = windows_of_blocks(ctx.session_id)
    back(ctx, function(pane)
      return windows[pane.block_id] ~= nil and windows[pane.block_id] ~= windows[ctx.block_id]
    end)
  end,
})

rex.action({
  name = "last_session",
  title = "Last Session",
  run = function(ctx)
    back(ctx, function(pane)
      return pane.session_id ~= ctx.session_id
    end)
  end,
})

-- The first terminal whose program reports it is blocked on you, else the
-- first that finished, across every session.
rex.action({
  name = "focus_agent",
  title = "Focus the Agent That Needs You",
  run = function(ctx)
    local done
    for _, session in ipairs(rex.call("session.list").sessions) do
      local list = rex.session.list_blocks({ session_id = session.session_id })
      for _, block in ipairs(list and list.blocks or {}) do
        local pane = { session_id = session.session_id, block_id = block.block_id }
        local status = block.creator_name == TERMINAL and rex.block.call(TERMINAL, "program_status", pane)
        for _, record in ipairs(status and status.records or {}) do
          if record.state == "blocked" then
            go_to(ctx, pane)
            return
          end
          if record.state == "done" and not done then
            done = pane
          end
        end
      end
    end
    if done then
      go_to(ctx, done)
    end
  end,
})

-- `ws pick` switches the app itself, so it gets the client to switch.
rex.action({
  name = "ws_pick",
  title = "Pick with ws",
  args = { name = "string" },
  run = function(ctx, args)
    remember(ctx)
    open_float("ws " .. args.name, { "ws", "pick", args.name, "--client", ctx.client_id, "--from", ctx.block_id })
  end,
})

-- Shows the pane's text in read-only Neovim to select and copy, as tmux's
-- copy mode does.
rex.action({
  name = "copy_mode",
  title = "Copy Mode",
  run = function(ctx)
    open_float("copy", {
      "zsh",
      "-c",
      'rex capture -s "$1" -b "$2" --trim | nvim -R -S "$3" -',
      "copy-mode",
      ctx.session_id,
      ctx.block_id,
      REX_DIR .. "/copy-mode.lua",
    })
  end,
})

-- An action binding never passes its key on, so this one sends the key to an
-- editor itself.
rex.action({
  name = "scroll_or_send",
  title = "Scroll, or Send the Key to an Editor",
  args = { key = "string", scroll = "string" },
  repeats = true,
  run = function(ctx, args)
    if program_takes_keys(ctx.block_id) then
      rex.client.queue("pane.send_key", { key = args.key })
    else
      rex.client.queue(args.scroll)
    end
  end,
})

-- Ctrl-H/J/K/L cross Neovim windows and Rex panes as one grid. A function
-- that returns false passes the key on to Neovim, which runs `rex focus` at
-- its edge (rex/nvim.lua). A key function can't queue app actions, so it
-- moves focus on the server, as `rex focus` does.
for key, direction in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
  rex.bind("ctrl+" .. key, function(ctx)
    if program_takes_keys(ctx.block_id) then
      return false
    end
    remember(ctx)
    rex.session.focus_direction({ direction = direction })
    return true
  end)
end

for key, scroll in pairs({ b = "page_up", u = "page_up", f = "page_down", d = "page_down" }) do
  rex.bind("ctrl+" .. key, "scroll_or_send", { key = "ctrl+" .. key, scroll = "client.scroll." .. scroll })
end

for i = 1, 9 do
  rex.bind("alt+" .. i, "move", { action = "client.tab.goto", args = { index = i } })
end
rex.bind("alt+n", "move", { action = "client.tab.new" })
rex.bind("alt+s", "move", { action = "session.switch" })
rex.bind("alt+l", "last_pane")
rex.bind("alt+shift+a", "focus_agent")
rex.bind("alt+g", "client.sidebar.toggle")
rex.bind("alt+shift+c", "client.theme.change")
rex.bind("alt+/", "ws_pick", { name = "keys" })

for key, name in pairs({ o = "go", w = "worktrees", r = "reviews", t = "tasks", a = "agents", c = "theme" }) do
  rex.bind("alt+" .. key, "ws_pick", { name = name })
end

-- Bindings match unshifted keys, so | is shift+\ and L is shift+l.
rex.bind(PREFIX .. "shift+\\", "move", { action = "pane.split.right" })
rex.bind(PREFIX .. "-", "move", { action = "pane.split.down" })
rex.bind(PREFIX .. "c", "move", { action = "client.tab.new" })
rex.bind(PREFIX .. "s", "move", { action = "session.switch" })
rex.bind(PREFIX .. "z", "pane.zoom")
rex.bind(PREFIX .. "x", "pane.close")
rex.bind(PREFIX .. "[", "copy_mode")
rex.bind(PREFIX .. "l", "last_tab")
rex.bind(PREFIX .. "shift+l", "last_session")
rex.bind(PREFIX .. "ctrl+space", "pane.send_key", { key = "ctrl+space" })
