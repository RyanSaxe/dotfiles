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

rex.action({
  name = "keys_cheatsheet",
  title = "Rex Keys",
  run = function(ctx)
    open_float("keys", { REX_DIR .. "/keys.zsh", ctx.client_id })
  end,
})

for i = 1, 9 do
  rex.bind("alt+" .. i, "client.tab.goto", { index = i })
end
rex.bind("alt+n", "client.tab.new")
rex.bind("alt+s", "session.switch")
rex.bind("alt+a", "client.sidebar.activity.toggle")
rex.bind("alt+g", "client.sidebar.toggle")
rex.bind("alt+c", "client.theme.change")
rex.bind("alt+/", "keys_cheatsheet")

-- Bindings match unshifted keys, so | is shift+\.
rex.bind(PREFIX .. "shift+\\", "pane.split.right")
rex.bind(PREFIX .. "-", "pane.split.down")
rex.bind(PREFIX .. "c", "client.tab.new")
rex.bind(PREFIX .. "s", "session.switch")
rex.bind(PREFIX .. "z", "pane.zoom")
rex.bind(PREFIX .. "x", "pane.close")
rex.bind(PREFIX .. "ctrl+space", "pane.send_key", { key = "ctrl+space" })
