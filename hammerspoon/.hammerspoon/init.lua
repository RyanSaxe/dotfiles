-- Hammerspoon: the theme system's macOS limb. Exactly three jobs:
--   1. the pokemon mascot (mascot.lua)
--   2. reload this config whenever its files change
--   3. keep the terminal theme in step with macOS appearance
-- Anything beyond those three jobs is deliberately out of scope —
-- this file should stay boring.

-- Enable the `hs` CLI (used for manual poking and by scripts).
hs.ipc.cliInstall()

require("mascot").start()

-- 2. Auto-reload: editing any .lua file in ~/.hammerspoon applies itself.
-- The watcher hands us the list of changed paths; only reload for .lua so
-- stray editor swap/temp files can't cause reload loops.
-- NOTE: watchers must be GLOBAL — top-level locals in init.lua get garbage
-- collected after the chunk runs, silently killing the watcher.
config_watcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", function(paths)
  for _, path in ipairs(paths) do
    if path:sub(-4) == ".lua" then
      hs.reload()
      return
    end
  end
end)
config_watcher:start()

-- 3. Appearance sync: macOS appearance is the master light/dark switch.
-- When it flips by ANY path (System Settings, sunset schedule, or the
-- `theme` command itself once Phase 3 wires toggle -> osascript), re-render
-- the terminal theme to match. The tiny delay lets the OS finish writing
-- the new appearance before we read it.
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
