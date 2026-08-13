--- Floating pokemon mascot, pinned above the bottom-right corner of the
--- focused Ghostty window.
---
--- Why Hammerspoon: the mascot must sit ABOVE terminal content (visible
--- inside neovim or any TUI), stay put through pane/tab/layout changes, and
--- never flicker. A canvas floating over the window is the only layer that
--- has all three properties; in-terminal approaches are either behind the
--- cells (ghostty background-image) or anchored to panes (herdr overlays).
---
--- Auto-update: a pathwatcher on the theme state directory swaps the sprite
--- the moment `theme pokemon <name>` writes new state. No polling, no
--- reloads. The state file is the entire interface to the theme system.

local M = {}

M.config = {
  -- Canvas size in points; the cached image is 2x pixels for retina.
  size = 96,
  -- Distance from the window's bottom-right corner, in points.
  padding = 14,
  app_name = "Ghostty",
}

local state_dir = os.getenv("HOME") .. "/.local/state/dotfiles"
local cache_dir = os.getenv("HOME") .. "/.cache/dotfiles/pokemon"

--- Read the active pokemon from theme state: name plus shininess, or nil.
local function current_pokemon()
  local file = io.open(state_dir .. "/accents.conf", "r")
  if not file then
    return nil
  end
  local name, shiny
  for line in file:lines() do
    name = line:match("^pokemon=(.+)$") or name
    shiny = line:match("^shiny=1$") and true or shiny
  end
  file:close()
  return name, shiny
end

--- Load the normalized mascot image for a pokemon, or nil if not cached.
local function mascot_image(name, shiny)
  local base = shiny and (name .. "-shiny") or name
  return hs.image.imageFromPath(cache_dir .. "/" .. base .. "-mascot.png")
end

--- Move the canvas to the bottom-right corner of the given window.
local function reposition(window)
  local frame = window:frame()
  M.canvas:topLeft({
    x = frame.x + frame.w - M.config.size - M.config.padding,
    y = frame.y + frame.h - M.config.size - M.config.padding,
  })
end

--- Show the mascot over a window, or hide it when there is nothing to show.
local function refresh(window)
  local name, shiny = current_pokemon()
  local image = name and mascot_image(name, shiny)
  if not (window and image) then
    M.canvas:hide()
    return
  end
  M.canvas[1].image = image
  reposition(window)
  M.canvas:show()
end

--- The focused window of the configured app, or nil.
local function focused_app_window()
  local window = hs.window.focusedWindow()
  if window and window:application():name() == M.config.app_name then
    return window
  end
  return nil
end

function M.start()
  M.canvas = hs.canvas.new({ x = 0, y = 0, w = M.config.size, h = M.config.size })
  M.canvas[1] = { type = "image", imageScaling = "scaleToFit" }
  -- Float above normal windows; never steal clicks or focus.
  M.canvas:level(hs.canvas.windowLevels.floating)
  M.canvas:behavior({ "canJoinAllSpaces", "transient" })
  M.canvas:clickActivating(false)

  -- Follow the focused Ghostty window; hide when Ghostty loses focus so the
  -- mascot never floats over unrelated apps. Every event re-queries focus
  -- AND re-checks shortly after: macOS delivers same-app window-switch
  -- events late or out of order, so a single immediate refresh can act on
  -- stale focus. The delayed pass self-heals those races.
  local function refresh_soon()
    refresh(focused_app_window())
    M.refresh_timer = hs.timer.doAfter(0.25, function()
      refresh(focused_app_window())
    end)
  end

  M.window_filter = hs.window.filter.new(M.config.app_name)
  M.window_filter:subscribe({
    hs.window.filter.windowFocused,
    hs.window.filter.windowMoved, -- fires on both move and resize
    hs.window.filter.windowUnfocused,
    hs.window.filter.windowCreated,
    hs.window.filter.windowDestroyed,
  }, refresh_soon)

  -- Swap the sprite the moment the theme writes new state.
  M.path_watcher = hs.pathwatcher.new(state_dir, function()
    refresh(focused_app_window())
  end)
  M.path_watcher:start()

  refresh(focused_app_window())
end

function M.stop()
  if M.path_watcher then
    M.path_watcher:stop()
  end
  if M.window_filter then
    M.window_filter:unsubscribeAll()
  end
  if M.canvas then
    M.canvas:delete()
  end
end

return M
