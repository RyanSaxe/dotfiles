-- Hammerspoon: the theme system's macOS limb. Exactly two jobs:
--   1. reload this config whenever its files change
--   2. keep the terminal theme in step with macOS appearance
--      (including the ghostty reload push, which only a watcher with a
--      controlled environment can deliver)
-- Anything beyond those jobs is deliberately out of scope — this file
-- should stay boring. The pokemon mascot lives in the terminal rail
-- (tuis/rail), not here.

-- Enable the `hs` CLI (used for manual poking and by scripts).
hs.ipc.cliInstall()

-- 1. Auto-reload: editing any .lua file applies itself. ~/.hammerspoon
-- holds stow SYMLINKS — file events fire at the TARGET (the repo), never
-- on the symlink — so the watcher must watch the resolved directory.
-- Only reload for .lua so stray temp files can't cause reload loops.
-- NOTE: watchers must be GLOBAL — top-level locals in init.lua get garbage
-- collected after the chunk runs, silently killing the watcher.
local function reload_on_lua(paths)
  for _, path in ipairs(paths) do
    if path:sub(-4) == ".lua" then
      hs.reload()
      return
    end
  end
end
local config_dir = os.getenv("HOME") .. "/.hammerspoon/"
config_watcher = hs.pathwatcher.new(config_dir, reload_on_lua)
config_watcher:start()
local real_init = hs.fs.pathToAbsolute(config_dir .. "init.lua")
if real_init then
  target_watcher = hs.pathwatcher.new(real_init:match("(.*/)"), reload_on_lua)
  target_watcher:start()
end

-- 1b. Ghostty shader reload: ghostty cannot watch files, so this is the one
-- consumer that needs a push — and it lives HERE, in the single watcher
-- with a controlled environment, never in the theme script (which runs
-- from arbitrary contexts). SIGUSR2 = ghostty's config-reload signal
-- (1.2+; other signals would crash it). Debounced: one render touches
-- several files and one reload covers them all.
local ghostty_reload_timer = nil
generated_watcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.local/state/dotfiles/generated/", function()
  if ghostty_reload_timer then
    ghostty_reload_timer:stop()
  end
  ghostty_reload_timer = hs.timer.doAfter(0.3, function()
    hs.task.new("/usr/bin/pkill", nil, { "-USR2", "-x", "ghostty" }):start()
  end)
end)
generated_watcher:start()

-- 2. Appearance sync: macOS appearance is the master light/dark switch.
-- When it flips by ANY path (System Settings, sunset schedule, or the
-- `theme` command itself), re-render the terminal theme to match. The tiny
-- delay lets the OS finish writing the new appearance before we read it.
local function sync_theme_to_appearance()
  hs.timer.doAfter(0.2, function()
    local mode = (hs.host.interfaceStyle() == "Dark") and "dark" or "light"
    -- `apply <mode>` renders WITHOUT setting OS appearance: a follower
    -- must never set the thing it reacts to (feedback race with toggle).
    hs.task.new(os.getenv("HOME") .. "/.local/bin/theme", nil, { "apply", mode }):start()
  end)
end

appearance_watcher = hs.distributednotifications.new(sync_theme_to_appearance, "AppleInterfaceThemeChangedNotification")
appearance_watcher:start()

-- Enforce the invariant at startup too, so a theme/OS disagreement can't
-- survive a reboot or a hammerspoon reload.
sync_theme_to_appearance()
