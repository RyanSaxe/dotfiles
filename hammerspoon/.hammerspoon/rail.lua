--- The agent rail: a full-bleed canvas column over Ghostty's reserved left
--- padding — this project's windows (enriched where agents live), then
--- every agent elsewhere. Display only; all interaction stays on tmux
--- binds. The rail-design artifact is the pixel target.
---
--- Design contract:
---   * Full-bleed: the canvas is the window's left slice (x, y, h = the
---     window's own; w = config.width). No margins, no floating card.
---   * Chip = place: the accent-filled chip marks the current window and
---     nothing else. Title color = state: mauve working, peach waiting,
---     green done. No bold anywhere.
---   * Windows in number order; agent windows grow a dim doing-line; the
---     dossier (+adds −dels) only under done agents. Elsewhere rows are
---     urgency-sorted, project-prefixed, uniformly dimmed (~55%; stale
---     ~38%). The mascot footer is reserved space.
---
--- Architecture rule (learned the hard way): NOTHING on the draw path may
--- block. All external reads (tmux, workmux, git) run in ONE async
--- collector task per tick that updates a cache; drawing only ever reads
--- memory. A stalled subprocess may stale the data — never a pixel, and
--- never Hammerspoon's main thread.
---
--- TODO(workmux-upstream): status --json does not export interrupted/
--- stale/sleeping (their issue #210 shapes the JSON for consumers). We
--- derive stale from updated_ts; a `halted` pane-freeze detector is a
--- planned later commit. If upstream exports these, consume theirs.

local M = {}

M.config = {
  width = 256, -- rail column width; ghostty's left padding = width + 20 gap
  tick_seconds = 1.0,
  app_name = "Ghostty",
  font = "Menlo",
  mascot_box = 116, -- reserved footer height
  dim_elsewhere = 0.55,
  dim_stale = 0.38,
  stale_after = 3600,
}

local state_dir = os.getenv("HOME") .. "/.local/state/dotfiles"
local generated = state_dir .. "/generated"
local flag_file = state_dir .. "/rail-on"

-- ---------------------------------------------------------------- colors
local colors, colors_mtime
local function load_colors()
  local path = generated .. "/hs-colors.lua"
  local attr = hs.fs.attributes(path)
  if not attr then
    return
  end
  if colors and attr.modification == colors_mtime then
    return
  end
  local ok, tbl = pcall(dofile, path)
  if ok and type(tbl) == "table" then
    colors = tbl
    colors_mtime = attr.modification
  end
end

local function col(key, alpha)
  return { hex = (colors and colors[key]) or "#888888", alpha = alpha or 1.0 }
end

-- ------------------------------------------------------- async collector
-- One /bin/sh child per tick gathers everything; its callback parses into
-- M.data. An in-flight guard plus a watchdog means a hung child skips
-- ticks instead of stacking, and is killed after 5s.
M.data = { session = nil, windows = {}, agents = {} }

--- ONE persistent streaming child instead of a task per poll: rapid
--- per-event spawns lose hs.task callbacks under bursts (observed), and a
--- single loop has no spawn latency at all. It emits window snapshots
--- every 250ms (~3ms of tmux work) and folds the agent snapshot in every
--- 20th cycle; instant agent changes arrive via the workmux state-file
--- watcher triggering a one-shot refresh.
local STREAM_SCRIPT = [[
export LANG=en_US.UTF-8 PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
i=0
while :; do
  S=$(tmux list-clients -F '#{client_activity} #{client_session}' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
  if [ -n "$S" ]; then
    echo "SESSION $S"
    tmux list-windows -t "$S" -F 'WINDOW #{window_index} #{window_active} #{window_name}' 2>/dev/null
    if [ $((i % 20)) -eq 0 ]; then
      printf 'AGENTS '
      workmux status --json 2>/dev/null | tr -d '\n'
      echo ""
    fi
    echo "END"
  fi
  i=$((i + 1))
  sleep 0.25
done
]]

local AGENTS_SCRIPT = [[
export LANG=en_US.UTF-8 PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
printf 'AGENTS '
workmux status --json 2>/dev/null | tr -d '\n'
echo ""
echo "END"
]]

--- Strip characters that churn without meaning (spinner glyph frames in
--- agent titles) so neither the display nor the change-signature flaps.
local function normalize_title(t)
  if not t then
    return nil
  end
  t = t:gsub("[^\32-\126]", ""):gsub("^%s+", ""):gsub("%s+$", "")
  return t ~= "" and t or nil
end

local draw -- forward declaration: parsers draw the moment data lands

local function apply_agents_json(json)
  local ok, data = pcall(hs.json.decode, json)
  if not (ok and type(data) == "table" and type(data.agents) == "table") then
    return
  end
  local now = os.time()
  local agents = {}
  for _, a in ipairs(data.agents) do
    local status = a.status ~= "-" and a.status or nil
    if a.updated_ts and (now - a.updated_ts) > M.config.stale_after then
      status = "stale"
    end
    agents[#agents + 1] = {
      session = a.session,
      window = a.window_name,
      name = a.worktree or a.window_name or "agent",
      status = status,
      elapsed = a.elapsed_secs,
      title = normalize_title(a.title),
      workdir = a.workdir,
      updated = a.updated_ts or 0,
      pane = a.pane_id,
    }
  end
  M.data.agents = agents
end

--- Parse one complete snapshot block (everything up to an END line).
local function apply_snapshot(block)
  local session
  local windows = {}
  for line in block:gmatch("[^\n]+") do
    local sess = line:match("^SESSION (.+)$")
    if sess then
      session = sess
    end
    local idx, active, name = line:match("^WINDOW (%d+) (%d) (.*)$")
    if idx then
      windows[#windows + 1] = { index = idx, active = active == "1", name = name }
    end
    local json = line:match("^AGENTS (.+)$")
    if json then
      apply_agents_json(json)
    end
  end
  if session then
    M.data.session = session
    M.data.windows = windows
  end
end

-- Stream plumbing: buffer chunks, act on each END-terminated block.
local stream_task
local stream_buffer = ""

local function on_stream(_, stdout)
  stream_buffer = stream_buffer .. (stdout or "")
  local acted = false
  while true do
    local head, rest = stream_buffer:match("^(.-)\nEND\n(.*)$")
    if not head then
      break
    end
    stream_buffer = rest
    pcall(apply_snapshot, head .. "\n")
    acted = true
  end
  if acted then
    pcall(draw)
  end
  return true -- keep streaming
end

local function ensure_stream()
  if stream_task and stream_task:isRunning() then
    return
  end
  stream_buffer = ""
  stream_task = hs.task.new("/bin/sh", function() end, on_stream, { "-c", STREAM_SCRIPT })
  stream_task:start()
end

local function stop_stream()
  if stream_task then
    pcall(function()
      stream_task:terminate()
    end)
    stream_task = nil
  end
end

--- One-shot agent refresh for instant status changes (workmux state-file
--- events); losses are harmless — the stream re-syncs agents within 5s.
local function refresh_agents()
  hs.task
    .new("/bin/sh", function(_, stdout)
      local json = (stdout or ""):match("AGENTS (.-)\nEND") or (stdout or ""):match("AGENTS (.+)")
      if json then
        pcall(apply_agents_json, json)
        pcall(draw)
      end
    end, { "-c", AGENTS_SCRIPT })
    :start()
end

-- ----------------------------------------------------------- dossier cache
-- Diff stats for done worktree agents, async with its own cadence: a
-- finished branch's diff is its review invitation.
-- TODO(workmux-upstream): PR number/checks need `gh`; revisit later.
local dossier = {} -- pane_id -> { text, at }
local function refresh_dossier(agent)
  local entry = dossier[agent.pane]
  if entry and (os.time() - entry.at) < 30 then
    return
  end
  dossier[agent.pane] = { text = entry and entry.text or "", at = os.time() }
  local script = string.format(
    'cd "%s" 2>/dev/null || exit 0; git diff --shortstat main...HEAD 2>/dev/null || git diff --shortstat master...HEAD 2>/dev/null',
    agent.workdir
  )
  hs.task
    .new("/bin/sh", function(_, stdout)
      local ins = (stdout or ""):match("(%d+) insertion") or "0"
      local del = (stdout or ""):match("(%d+) deletion") or "0"
      if dossier[agent.pane] then
        dossier[agent.pane].text = "+" .. ins .. " −" .. del
      end
    end, { "-c", script })
    :start()
end

-- ---------------------------------------------------------------- layout
local status_color = { working = "mauve", waiting = "peach", done = "green", stale = "dim" }
local elsewhere_rank = { waiting = 0, working = 1, done = 2, stale = 3 }

local function fmt_elapsed(secs)
  if not secs then
    return ""
  end
  if secs < 90 * 60 then
    return math.floor(secs / 60) .. "m"
  elseif secs < 36 * 3600 then
    return math.floor(secs / 3600) .. "h"
  end
  return math.floor(secs / 86400) .. "d"
end

local function styled(text, opts)
  return hs.styledtext.new(text, {
    font = { name = M.config.font, size = opts.size },
    color = opts.color,
    paragraphStyle = { lineBreakMode = "truncateTail", alignment = opts.align or "natural" },
  })
end

local function build_elements(session, windows, agents, height)
  local W = M.config.width
  local e = {}
  -- Full-bleed slab: a rounded strip under a square body so only the far
  -- left corners follow the macOS window curve — the right edge is square.
  -- Fill uses rail_bg (canvas rendering shifts hex lighter than terminals
  -- render the same value; rail_bg is compensated to READ as mantle).
  e[#e + 1] = {
    type = "rectangle",
    action = "fill",
    fillColor = col("rail_bg"),
    roundedRectRadii = { xRadius = 11, yRadius = 11 },
    frame = { x = 0, y = 0, w = 30, h = height },
  }
  e[#e + 1] = {
    type = "rectangle",
    action = "fill",
    fillColor = col("rail_bg"),
    frame = { x = 11, y = 0, w = W - 11, h = height },
  }

  local y = 14
  local function text_el(txt, frame)
    e[#e + 1] = { type = "text", text = txt, frame = frame }
  end

  text_el(styled(session, { size = 14, color = col("lavender") }), { x = 16, y = y, w = W - 32, h = 19 })
  y = y + 25
  e[#e + 1] =
    { type = "rectangle", action = "fill", fillColor = col("accent"), frame = { x = 14, y = y, w = W - 28, h = 2 } }
  y = y + 9

  local content_max = height - M.config.mascot_box - 18

  local function row(chip, active, title, title_color, elapsed, alpha, prefix)
    if y + 21 > content_max then
      return false
    end
    local x = 14
    if chip then
      e[#e + 1] = {
        type = "rectangle",
        action = "fill",
        fillColor = active and col("accent", alpha) or col("surface0", alpha),
        roundedRectRadii = { xRadius = 4, yRadius = 4 },
        frame = { x = x, y = y + 1, w = 19, h = 16 },
      }
      text_el(
        styled(chip, { size = 11, align = "center", color = active and col("base", alpha) or col("dim2", alpha) }),
        { x = x, y = y + 2, w = 19, h = 14 }
      )
      x = x + 28
    end
    local elapsed_w = elapsed ~= "" and 34 or 0
    local title_text
    if prefix then
      title_text = styled(prefix, { size = 12.5, color = col("dim", alpha) })
        .. styled(title, { size = 12.5, color = title_color })
    else
      title_text = styled(title, { size = 12.5, color = title_color })
    end
    text_el(title_text, { x = x, y = y, w = W - x - 14 - elapsed_w, h = 18 })
    if elapsed ~= "" then
      text_el(
        styled(elapsed, { size = 10.5, align = "right", color = col("dim", alpha) }),
        { x = W - 14 - elapsed_w, y = y + 2, w = elapsed_w, h = 15 }
      )
    end
    y = y + 22
    return true
  end

  local function sub(text, alpha, indent)
    if not text or text == "" or y + 17 > content_max then
      return
    end
    text_el(
      styled(text, { size = 10.5, color = col("dim", alpha) }),
      { x = indent, y = y, w = W - indent - 14, h = 15 }
    )
    y = y + 17
  end

  local by_window = {}
  local elsewhere = {}
  for _, a in ipairs(agents) do
    if a.session == session then
      by_window[a.window or ""] = a
    else
      elsewhere[#elsewhere + 1] = a
    end
  end

  for _, w in ipairs(windows) do
    local agent = by_window[w.name]
    local color
    if agent and agent.status and status_color[agent.status] then
      color = col(status_color[agent.status])
    else
      color = w.active and col("text") or col("dim2")
    end
    row(w.index, w.active, w.name, color, agent and fmt_elapsed(agent.elapsed) or "", 1.0)
    if agent then
      if agent.status == "done" and agent.workdir then
        refresh_dossier(agent)
        local d = dossier[agent.pane]
        sub(d and d.text or "", 1.0, 42)
      else
        sub(agent.title, 1.0, 42)
      end
    end
  end

  if #elsewhere > 0 and y + 26 < content_max then
    e[#e + 1] = {
      type = "rectangle",
      action = "fill",
      fillColor = col("surface0"),
      frame = { x = 16, y = y + 6, w = W - 32, h = 1 },
    }
    y = y + 16
    table.sort(elsewhere, function(a, b)
      local ra = elsewhere_rank[a.status or "stale"] or 3
      local rb = elsewhere_rank[b.status or "stale"] or 3
      if ra ~= rb then
        return ra < rb
      end
      return a.updated > b.updated
    end)
    local hidden = 0
    for _, a in ipairs(elsewhere) do
      local alpha = a.status == "stale" and M.config.dim_stale or M.config.dim_elsewhere
      local color = col(status_color[a.status or "stale"] or "dim", alpha)
      if row(nil, false, a.name, color, fmt_elapsed(a.elapsed), alpha, a.session .. "/") then
        if a.status == "done" and a.workdir then
          refresh_dossier(a)
          local d = dossier[a.pane]
          sub(d and d.text or "", alpha, 14)
        elseif a.status ~= "stale" then
          sub(a.title, alpha, 14)
        end
      else
        hidden = hidden + 1
      end
    end
    if hidden > 0 then
      sub("+" .. hidden .. " more", M.config.dim_elsewhere, 14)
    end
  end

  e[#e + 1] = {
    type = "rectangle",
    action = "stroke",
    strokeColor = col("surface1"),
    strokeWidth = 1,
    roundedRectRadii = { xRadius = 8, yRadius = 8 },
    frame = { x = 14, y = height - M.config.mascot_box - 8, w = W - 28, h = M.config.mascot_box },
  }
  return e
end

-- ------------------------------------------------------------- reconcile
local function focused_app_window()
  local window = hs.window.focusedWindow()
  local app = window and window:application()
  if app and app:name() == M.config.app_name then
    return window
  end
  return nil
end

local function enabled()
  return hs.fs.attributes(flag_file) ~= nil
end

local function signature(frame)
  local d = M.data
  local parts = {
    d.session or "",
    string.format("%.0f,%.0f,%.0f,%.0f", frame.x, frame.y, frame.w, frame.h),
    tostring(colors_mtime),
  }
  for _, w in ipairs(d.windows) do
    parts[#parts + 1] = w.index .. (w.active and "*" or "") .. w.name
  end
  for _, a in ipairs(d.agents) do
    local ds = dossier[a.pane]
    parts[#parts + 1] = table.concat(
      { a.session, a.name, a.status or "", fmt_elapsed(a.elapsed), a.title or "", ds and ds.text or "" },
      "^"
    )
  end
  return table.concat(parts, "|")
end

draw = function()
  load_colors()
  local window = focused_app_window()

  if not (window and enabled() and colors and M.data.session) then
    if M.drawn then
      M.canvas:hide()
      M.drawn = nil
    end
    return
  end

  local frame = window:frame()
  local sig = signature(frame)
  if sig == M.drawn then
    return
  end

  M.canvas:frame({ x = frame.x, y = frame.y, w = M.config.width, h = frame.h })
  M.canvas:replaceElements(build_elements(M.data.session, M.data.windows, M.data.agents, frame.h))
  M.canvas:show()
  M.drawn = sig
end

--- The tick is a safety net: keep the stream alive, redraw for frame
--- moves and elapsed-time updates the stream's change detection misses.
local function tick()
  if enabled() then
    ensure_stream()
  else
    stop_stream()
  end
  pcall(draw)
end

--- The mascot's home while the rail is up: centered in the reserved footer.
function M.mascot_anchor(ghostty_frame, mascot_size)
  if not (M.drawn and enabled()) then
    return nil
  end
  return {
    x = ghostty_frame.x + (M.config.width - mascot_size) / 2,
    y = ghostty_frame.y + ghostty_frame.h - M.config.mascot_box - 8 + (M.config.mascot_box - mascot_size) / 2,
  }
end

function M.start()
  M.canvas = hs.canvas.new({ x = 0, y = 0, w = M.config.width, h = 100 })
  M.canvas:level(hs.canvas.windowLevels.floating)
  M.canvas:behavior({ "canJoinAllSpaces", "transient" })
  M.canvas:clickActivating(false)

  M.ticker = hs.timer.doEvery(M.config.tick_seconds, function()
    pcall(tick)
  end)
  -- Theme renders and the rail-on flag land here; redraw promptly.
  M.path_watcher = hs.pathwatcher.new(state_dir, function()
    pcall(tick)
  end)
  M.path_watcher:start()
  -- workmux's agent hooks write a state file the moment an agent starts,
  -- waits, or finishes — the event triggers an instant one-shot refresh
  -- (data still comes from `workmux status --json`).
  local workmux_state = os.getenv("HOME") .. "/.local/state/workmux"
  if hs.fs.attributes(workmux_state) then
    M.agents_watcher = hs.pathwatcher.new(workmux_state, function()
      if enabled() then
        refresh_agents()
      end
    end)
    M.agents_watcher:start()
  end
  pcall(tick)
end

function M.stop()
  if M.ticker then
    M.ticker:stop()
  end
  if M.path_watcher then
    M.path_watcher:stop()
  end
  if M.agents_watcher then
    M.agents_watcher:stop()
  end
  stop_stream()
  if M.canvas then
    M.canvas:delete()
  end
  M.drawn = nil
end

return M
