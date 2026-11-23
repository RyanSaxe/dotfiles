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
rex.bind("alt+h", "client.navigate.back")
rex.bind("alt+l", "client.navigate.forward")
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

-- Bindings match unshifted keys, so | is shift+\.
rex.bind(PREFIX .. "shift+\\", "pane.split.right")
rex.bind(PREFIX .. "-", "pane.split.down")
rex.bind(PREFIX .. "c", "client.tab.new")
rex.bind(PREFIX .. "s", "session.switch")
rex.bind(PREFIX .. "z", "pane.zoom")
rex.bind(PREFIX .. "x", "pane.close")
rex.bind(PREFIX .. "[", "copy_mode")
rex.bind(PREFIX .. "ctrl+space", "pane.send_key", { key = "ctrl+space" })
