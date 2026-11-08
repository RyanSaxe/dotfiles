-- Rex configuration: Rex's own default keys, plus the tmux keys from
-- tmux/tmux.conf bound to the Rex actions that do the same thing. Font and
-- padding are app settings, not Lua.
--
-- Rex's Dark Mode and Light Mode themes are Catppuccin Mocha and Latte,
-- imported in the app from https://github.com/catppuccin/ghostty.
--
-- The app handles no keys while an action that a key started is running, so
-- every action here returns at once and waits on nothing it starts.
--
-- These tmux keys stay unbound on purpose: Alt-Q, Alt-K, Alt-Comma,
-- Alt-Period, Alt-Shift-R, Alt-Shift-T, and prefix r, comma and $.

local SHELL = "com.superlogical.terminal.shell"
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

rex.action({
  name = "keys_cheatsheet",
  title = "Rex Keys",
  run = function(ctx)
    open_float("keys", { REX_DIR .. "/keys.zsh", ctx.client_id })
  end,
})

for i = 1, 9 do
  rex.bind("alt+" .. i, "move", { action = "client.tab.goto", args = { index = i } })
end
rex.bind("alt+n", "move", { action = "client.tab.new" })
rex.bind("alt+s", "move", { action = "session.switch" })
rex.bind("alt+l", "last_pane")
rex.bind("alt+a", "client.sidebar.activity.toggle")
rex.bind("alt+g", "client.sidebar.toggle")
rex.bind("alt+c", "client.theme.change")
rex.bind("alt+/", "keys_cheatsheet")

-- Bindings match unshifted keys, so | is shift+\ and L is shift+l.
rex.bind(PREFIX .. "shift+\\", "move", { action = "pane.split.right" })
rex.bind(PREFIX .. "-", "move", { action = "pane.split.down" })
rex.bind(PREFIX .. "c", "move", { action = "client.tab.new" })
rex.bind(PREFIX .. "s", "move", { action = "session.switch" })
rex.bind(PREFIX .. "z", "pane.zoom")
rex.bind(PREFIX .. "x", "pane.close")
rex.bind(PREFIX .. "l", "last_tab")
rex.bind(PREFIX .. "shift+l", "last_session")
rex.bind(PREFIX .. "ctrl+space", "pane.send_key", { key = "ctrl+space" })
