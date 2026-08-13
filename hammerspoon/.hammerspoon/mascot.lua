--- Floating pokemon mascot, pinned above the bottom-right corner of the
--- focused Ghostty window.
---
--- Why Hammerspoon: the mascot must sit ABOVE terminal content (visible
--- inside neovim or any TUI), stay put through pane/tab/layout changes, and
--- never flicker. A canvas floating over the window is the only layer with
--- all three properties.
---
--- Why a reconcile tick instead of window events: macOS delivers same-app
--- window-switch events to the accessibility API late, out of order, or not
--- at all, so event-driven tracking visibly loses the window. A 0.4s tick
--- that diffs desired state against drawn state and acts only on change is
--- simpler and never wrong for more than a beat. The sprite itself swaps
--- instantly via a pathwatcher on the theme state directory.

local M = {}

M.config = {
  -- Canvas size in points; the cached image is 2x pixels for retina.
  size = 96,
  -- Distance from the window's bottom-right corner, in points.
  padding = 14,
  app_name = "Ghostty",
  -- Reconcile cadence. Movement is corrected within this interval.
  tick_seconds = 0.4,
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

--- The focused window of the configured app, or nil. Guarded: macOS can
--- briefly return windows with no application during switches, and an error
--- here would kill the reconcile timer permanently.
local function focused_app_window()
  local window = hs.window.focusedWindow()
  local app = window and window:application()
  if app and app:name() == M.config.app_name then
    return window
  end
  return nil
end

--- Reconcile the canvas with reality; cheap no-op when nothing changed.
local function reconcile()
  local window = focused_app_window()
  local name, shiny = current_pokemon()

  if not (window and name) then
    if M.drawn then
      M.canvas:hide()
      M.drawn = nil
    end
    return
  end

  local frame = window:frame()
  local sprite = (shiny and (name .. "-shiny") or name) .. "-mascot.png"
  local signature = string.format("%s|%d|%.0f|%.0f|%.0f|%.0f", sprite, window:id(), frame.x, frame.y, frame.w, frame.h)
  if signature == M.drawn then
    return
  end

  if M.drawn_sprite ~= sprite then
    local image = hs.image.imageFromPath(cache_dir .. "/" .. sprite)
    if not image then
      return
    end
    M.canvas[1].image = image
    M.drawn_sprite = sprite
  end
  M.canvas:topLeft({
    x = frame.x + frame.w - M.config.size - M.config.padding,
    y = frame.y + frame.h - M.config.size - M.config.padding,
  })
  M.canvas:show()
  M.drawn = signature
end

function M.start()
  M.canvas = hs.canvas.new({ x = 0, y = 0, w = M.config.size, h = M.config.size })
  M.canvas[1] = { type = "image", imageScaling = "scaleToFit" }
  -- Float above normal windows; never steal clicks or focus.
  M.canvas:level(hs.canvas.windowLevels.floating)
  M.canvas:behavior({ "canJoinAllSpaces", "transient" })
  M.canvas:clickActivating(false)

  -- pcall so no transient OS hiccup can ever kill the timer.
  M.ticker = hs.timer.doEvery(M.config.tick_seconds, function()
    pcall(reconcile)
  end)
  -- Theme switches should not wait for the next tick.
  M.path_watcher = hs.pathwatcher.new(state_dir, reconcile)
  M.path_watcher:start()
  reconcile()
end

function M.stop()
  if M.ticker then
    M.ticker:stop()
  end
  if M.path_watcher then
    M.path_watcher:stop()
  end
  if M.canvas then
    M.canvas:delete()
  end
  M.drawn = nil
  M.drawn_sprite = nil
end

return M
