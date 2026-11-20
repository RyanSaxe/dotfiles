-- Rex configuration: Rex's own default keys, the tmux keys from
-- tmux/tmux.conf bound to the Rex actions that do the same thing, and popups
-- for `ws` and copy mode. Font and padding are app settings, not Lua.
--
-- Rex's Dark Mode and Light Mode themes come from theme/apps/terminal.nix,
-- written to Rex's preferences by modules/home/rex.nix.
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

-- Opens command in a float, starting in cwd when it isn't nil.
--
-- When a float's command exits, Rex 0.1.0-preview.18 focuses the last pane
-- of the tab instead of the one the focus was on. So the command ends by
-- running close_float, which closes the float the way that focuses the right
-- pane. Once Rex focuses the right pane on its own, delete close_float and
-- run command as it is.
local function open_float(label, command, cwd)
  local closing = { "/bin/sh", "-c", '"$@"; rex --autostart=false do close_float', "float" }
  for _, arg in ipairs(command) do
    table.insert(closing, arg)
  end
  local _, err = rex.session.new_layer({
    bounds = { 0.08, 0.08, 0.84, 0.84 },
    focus = true,
    layout = rex.layout.block({ flavor = SHELL, label = label, options = { command = closing, cwd = cwd } }),
  })
  if err ~= nil then
    error(err, 0)
  end
end

-- The programs that use Ctrl-H/J/K/L and Ctrl-B/F/U/D themselves, from the
-- is_vim test in tmux.conf. fzf is one so those keys move its selection.
local EDITORS = { nvim = true, vim = true, vi = true, view = true, vimdiff = true, fzf = true }

-- The floating layer that holds the block and the block's label, or nil when
-- the block isn't in a float.
local function float_of(block_id)
  local view = rex.session.view({})
  for _, window in ipairs(view and view.windows or {}) do
    for _, layer in ipairs(window.layers) do
      for _, block in ipairs(layer.kind == "floating" and layer.blocks or {}) do
        if block.block_id == block_id then
          return layer.layer_id, block.label or ""
        end
      end
    end
  end
end

local function in_float(block_id)
  return float_of(block_id) ~= nil
end

-- Closing a float with close_layer focuses the pane the focus was on before
-- it opened, or the one a popup went to while it was open.
rex.action({
  name = "close_float",
  title = "Close This Float",
  run = function(ctx)
    local layer = float_of(ctx.block_id)
    if layer ~= nil then
      rex.session.close_layer({ layer_id = layer })
    end
  end,
})

-- Those keys go to an editor in any pane, and to any program in a float, as
-- they did in a tmux popup. A float's program can sit behind a shell, so its
-- name isn't a reliable test there.
local function program_takes_keys(block_id)
  local process = rex.block.call(TERMINAL, "process", { block_id = block_id })
  local foreground = process and process.foreground
  return foreground ~= nil and EDITORS[foreground.name] == true or in_float(block_id)
end

-- Focuses a pane in any session. The server focuses it first, so the app
-- lands on it when it switches session. Returns false for a closed pane.
local function go_to(ctx, pane)
  local found = rex.session.describe_block({ session_id = pane.session_id, block_id = pane.block_id })
  if not found then
    return false
  end
  rex.session.focus_block({ session_id = pane.session_id, block_id = pane.block_id })
  if pane.session_id ~= ctx.session_id then
    rex.client.queue("session.select", { session_id = pane.session_id, window_id = found.block.window_id })
  end
  return true
end

local function window_of(ctx)
  local found = rex.session.describe_block({ session_id = ctx.session_id, block_id = ctx.block_id })
  return found and found.block.window_id
end

-- A time Rex reports, such as 2026-11-18T09:58:24.535263-05:00, as text that
-- sorts in time order. Rex writes only the fraction digits a time needs, so
-- the fraction is padded.
local function sortable(time)
  local second, fraction = time:match("^(%d+%-%d+%-%d+T%d+:%d+:%d+)%.?(%d*)")
  return second .. "." .. (fraction .. "000000000"):sub(1, 9)
end

-- The pane going back to a tab lands on: its focused pane, or its first
-- tiled pane when a float, such as a popup, has the focus.
local function landing(window)
  for _, layer in ipairs(window.layers or {}) do
    if layer.kind == "tiled" and #(layer.blocks or {}) > 0 then
      for _, block in ipairs(layer.blocks) do
        if block.block_id == window.focused_block_id then
          return block.block_id
        end
      end
      return layer.blocks[1].block_id
    end
  end
end

-- Rex keeps no focus history, but an app asks the server for a pane's size
-- each time it shows the pane, and the pane's size method keeps when each
-- app last asked. So the tabs the app that ran ctx showed, newest first, are
-- the tabs you were on, however you moved between them. Each comes with the
-- pane going back to it lands on, and when the app last showed it.
local function shown_tabs(ctx)
  local tabs = {}
  for _, session in ipairs(rex.call("session.list").sessions) do
    local id = session.session_id
    local shown = {}
    local list = rex.session.list_blocks({ session_id = id })
    for _, block in ipairs(list and list.blocks or {}) do
      local size = block.creator_name == TERMINAL
        and rex.block.call(TERMINAL, "size", { session_id = id, block_id = block.block_id })
      for _, request in ipairs(size and size.desired or {}) do
        local time = sortable(request.updated_at)
        if (ctx.client_id == nil or request.client_id == ctx.client_id) and time > (shown[block.window_id] or "") then
          shown[block.window_id] = time
        end
      end
    end
    local view = rex.session.view({ session_id = id })
    for _, window in ipairs(view and view.windows or {}) do
      local pane = landing(window)
      if pane and shown[window.window_id] then
        table.insert(
          tabs,
          { session_id = id, window_id = window.window_id, block_id = pane, shown = shown[window.window_id] }
        )
      end
    end
  end
  table.sort(tabs, function(a, b)
    return a.shown > b.shown
  end)
  return tabs
end

-- The tab shown last before this one, among those `wanted` accepts.
local function tab_before(ctx, wanted)
  local here = window_of(ctx)
  for _, tab in ipairs(shown_tabs(ctx)) do
    if tab.window_id ~= here and wanted(tab) then
      return tab
    end
  end
end

-- The panes of a tab are shown together, so the app's requests can't tell a
-- move inside a tab. Ctrl-H/J/K/L and splits note theirs here, by tab: the
-- pane the move left, and when. os.date has whole seconds, so a move counts
-- from the end of its second. The notes live in the server's Lua state, so a
-- config reload forgets them.
local moves = {}

local function note_move(ctx)
  local window = window_of(ctx)
  if window then
    moves[window] = { block_id = ctx.block_id, at = os.date("%Y-%m-%dT%H:%M:%S") .. ".999999999" }
  end
end

-- Moves inside a tab that Alt-L should come back from run through this
-- action, which notes the pane the move starts from and then runs the Rex
-- action.
rex.action({
  name = "move",
  title = "Move and Note the Pane",
  args = { action = "string", args = "object?" },
  run = function(ctx, args)
    note_move(ctx)
    rex.client.queue(args.action, args.args)
  end,
})

-- Alt-L goes back to the pane a move inside this tab left, unless the app
-- showed another tab since then, and otherwise to the tab it showed last.
rex.action({
  name = "last_pane",
  title = "Last Pane",
  run = function(ctx)
    local before = tab_before(ctx, function()
      return true
    end)
    local move = moves[window_of(ctx)]
    if
      move
      and move.block_id ~= ctx.block_id
      and (before == nil or move.at > before.shown)
      and go_to(ctx, { session_id = ctx.session_id, block_id = move.block_id })
    then
      note_move(ctx)
    elseif before then
      go_to(ctx, before)
    end
  end,
})

rex.action({
  name = "last_tab",
  title = "Last Tab",
  run = function(ctx)
    local before = tab_before(ctx, function(tab)
      return tab.session_id == ctx.session_id
    end)
    if before then
      go_to(ctx, before)
    end
  end,
})

rex.action({
  name = "last_session",
  title = "Last Session",
  run = function(ctx)
    local before = tab_before(ctx, function(tab)
      return tab.session_id ~= ctx.session_id
    end)
    if before then
      go_to(ctx, before)
    end
  end,
})

-- `ws pick` switches the app itself, so it gets the client to switch. A
-- popup starts in the folder of the pane it opens from, which is what makes
-- a popup's project the one you're in. A ws key pressed in a ws popup
-- replaces that popup instead of stacking another over it, and the new one
-- starts in the folder the old one was in.
rex.action({
  name = "ws_pick",
  title = "Pick with ws",
  args = { name = "string" },
  run = function(ctx, args)
    local label = "ws " .. args.name
    local command = { "ws", "pick", args.name, "--client", ctx.client_id }
    local process = rex.block.call(TERMINAL, "process", { block_id = ctx.block_id })
    local cwd = process and process.foreground and process.foreground.cwd
    local layer, shown = float_of(ctx.block_id)
    open_float(label, command, cwd)
    if layer ~= nil and shown:sub(1, 3) == "ws " then
      rex.session.close_layer({ layer_id = layer })
    end
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
    note_move(ctx)
    rex.session.focus_direction({ direction = direction })
    return true
  end)
end

for key, scroll in pairs({ b = "page_up", u = "page_up", f = "page_down", d = "page_down" }) do
  rex.bind("ctrl+" .. key, "scroll_or_send", { key = "ctrl+" .. key, scroll = "client.scroll." .. scroll })
end

for i = 1, 9 do
  rex.bind("alt+" .. i, "client.tab.goto", { index = i })
end
rex.bind("alt+n", "client.tab.new")
rex.bind("alt+shift+s", "session.switch")
rex.bind("alt+l", "last_pane")
rex.bind("alt+g", "client.sidebar.toggle")
rex.bind("alt+shift+c", "client.theme.change")
rex.bind("alt+/", "ws_pick", { name = "keys" })

for key, name in pairs({
  o = "go",
  s = "sessions",
  w = "worktrees",
  r = "reviews",
  t = "tasks",
  a = "agents",
  c = "theme",
}) do
  rex.bind("alt+" .. key, "ws_pick", { name = name })
end

-- Bindings match unshifted keys, so | is shift+\ and L is shift+l.
rex.bind(PREFIX .. "shift+\\", "move", { action = "pane.split.right" })
rex.bind(PREFIX .. "-", "move", { action = "pane.split.down" })
rex.bind(PREFIX .. "c", "client.tab.new")
rex.bind(PREFIX .. "s", "session.switch")
rex.bind(PREFIX .. "z", "pane.zoom")
rex.bind(PREFIX .. "x", "pane.close")
rex.bind(PREFIX .. "[", "copy_mode")
rex.bind(PREFIX .. "l", "last_tab")
rex.bind(PREFIX .. "shift+l", "last_session")
rex.bind(PREFIX .. "ctrl+space", "pane.send_key", { key = "ctrl+space" })
