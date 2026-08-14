--- The agent rail: a canvas panel in Ghostty's reserved left padding that
--- shows this project's windows (enriched where agents live) and every
--- agent elsewhere. Display only — all interaction stays on tmux binds.
---
--- Design contract (the rail-design artifact is the pixel target):
---   * Chip = place: the accent-filled number chip marks the current
---     window and nothing else; chips are never status surfaces.
---   * Title color = state: mauve working, peach waiting, green done.
---     Regular weight everywhere.
---   * Windows keep number order; agent windows grow a dim doing-line
---     (the agent's live pane title). The dossier line (+adds −dels)
---     appears only under done agents.
---   * Below the hairline: other projects' agents, urgency-sorted
---     (waiting, working, done, stale), dim project/ prefix, uniformly
---     dimmed to ~55% (stale sinks to ~38%). No glyphs — one encoding.
---   * The mascot footer is reserved space; rows never enter it.
---
--- Data: `tmux list-windows` + `workmux status --json` (their documented,
--- versioned scripting surface — never their raw state files), polled on
--- the same reconcile-tick pattern as the mascot.
---
--- TODO(workmux-upstream): status --json does not yet export interrupted/
--- stale/sleeping (workmux computes them internally; see their issue
--- #210). We derive stale locally from updated_ts, and a `halted`
--- detector (pane-content hash) is planned as a later, separate commit.
--- If upstream exports these states, consume theirs and delete ours.

local M = {}

M.config = {
  width = 218, -- rail panel width in points; ghostty's left padding is width + 2*margin + gap
  margin = 8, -- gap between the panel and the window edges
  tick_seconds = 1.0,
  app_name = "Ghostty",
  font = "Menlo",
  mascot_box = 116, -- reserved footer height (mascot sprite + breathing room)
  dim_elsewhere = 0.55,
  dim_stale = 0.38,
  stale_after = 3600, -- seconds without a status update before an agent fades
}

local state_dir = os.getenv("HOME") .. "/.local/state/dotfiles"
local generated = state_dir .. "/generated"
local flag_file = state_dir .. "/rail-on"

-- Hammerspoon runs with a bare PATH, so binaries are resolved explicitly.
local function which(candidates)
  for _, path in ipairs(candidates) do
    if hs.fs.attributes(path) then
      return path
    end
  end
end
local TMUX = which({ "/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux" })
local WORKMUX = which({ "/opt/homebrew/bin/workmux", "/usr/local/bin/workmux" })

local function sh(cmd)
  -- Hammerspoon's environment is bare: no homebrew PATH, and no LANG —
  -- and without a UTF-8 locale tmux sanitizes the control characters
  -- workmux uses as field separators into literal underscores, breaking
  -- its parser. Every subprocess gets both.
  local f = io.popen('LANG=en_US.UTF-8 PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" ' .. cmd .. " 2>/dev/null")
  if not f then
    return ""
  end
  local out = f:read("*a")
  f:close()
  return out
end

-- ---------------------------------------------------------------- colors
-- The palette is a rendered theme artifact; re-read when it changes so
-- mode and pokemon switches recolor the rail within a tick.
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

-- ------------------------------------------------------------------ data
local function enabled()
  return hs.fs.attributes(flag_file) ~= nil
end

--- The session the user is looking at: the most recently active client.
local function current_session()
  local best_time, best
  for line in sh(TMUX .. ' list-clients -F "#{client_activity} #{client_session}"'):gmatch("[^\n]+") do
    local act, sess = line:match("^(%d+) (.+)$")
    if act and (not best_time or tonumber(act) > best_time) then
      best_time, best = tonumber(act), sess
    end
  end
  return best
end

local function list_windows(session)
  local windows = {}
  local cmd = TMUX .. ' list-windows -t "' .. session .. '" -F "#{window_index}\t#{window_active}\t#{window_name}"'
  for line in sh(cmd):gmatch("[^\n]+") do
    local idx, active, name = line:match("^(%d+)\t(%d)\t(.*)$")
    if idx then
      windows[#windows + 1] = { index = idx, active = active == "1", name = name }
    end
  end
  return windows
end

--- Agents from workmux's documented JSON surface, normalized. Stale is
--- derived here (TODO(workmux-upstream): drop when the JSON exports it).
local function list_agents()
  if not WORKMUX then
    return {}
  end
  local ok, data = pcall(hs.json.decode, sh(WORKMUX .. " status --json"))
  if not ok or type(data) ~= "table" or type(data.agents) ~= "table" then
    return {}
  end
  local now = os.time()
  local agents = {}
  for _, a in ipairs(data.agents) do
    local status = a.status
    if status == "-" then
      status = nil
    end
    if a.updated_ts and (now - a.updated_ts) > M.config.stale_after then
      status = "stale"
    end
    agents[#agents + 1] = {
      session = a.session,
      window = a.window_name,
      name = a.worktree or a.window_name or "agent",
      status = status,
      elapsed = a.elapsed_secs,
      title = a.title,
      workdir = a.workdir,
      updated = a.updated_ts or 0,
      pane = a.pane_id,
    }
  end
  return agents
end

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

-- ----------------------------------------------------------- dossier cache
-- Diff stats for done agents, computed asynchronously and cached: a
-- finished branch's diff vs the main branch is its review invitation.
-- Only worktree agents qualify (their branch IS the deliverable).
-- TODO(workmux-upstream): PR number + checks want `gh` and a slower
-- cadence; revisit when the rail is stable or upstream exports PR state.
local dossier = {} -- pane_id -> { text = "+A −D", at = epoch }
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
      local ins = stdout:match("(%d+) insertion") or "0"
      local del = stdout:match("(%d+) deletion") or "0"
      if dossier[agent.pane] then
        dossier[agent.pane].text = "+" .. ins .. " −" .. del
      end
    end, { "-c", script })
    :start()
end

-- ---------------------------------------------------------------- layout
local status_color = { working = "mauve", waiting = "peach", done = "green", stale = "dim" }
local elsewhere_rank = { waiting = 0, working = 1, done = 2, stale = 3 }

local function styled(text, opts)
  return hs.styledtext.new(text, {
    font = { name = M.config.font, size = opts.size },
    color = opts.color,
    paragraphStyle = { lineBreakMode = "truncateTail", alignment = opts.align or "natural" },
  })
end

--- Build the full element list for the canvas from gathered data.
local function build_elements(session, windows, agents, height)
  local W = M.config.width
  local e = {}
  e[#e + 1] = {
    type = "rectangle",
    action = "fill",
    fillColor = col("mantle"),
    roundedRectRadii = { xRadius = 10, yRadius = 10 },
  }

  local y = 13
  local function text_el(txt, frame)
    e[#e + 1] = { type = "text", text = txt, frame = frame }
  end

  -- header: project name, accent underline (H1)
  text_el(styled(session, { size = 13.5, color = col("lavender") }), { x = 14, y = y, w = W - 28, h = 18 })
  y = y + 24
  e[#e + 1] =
    { type = "rectangle", action = "fill", fillColor = col("accent"), frame = { x = 12, y = y, w = W - 24, h = 2 } }
  y = y + 8

  local content_max = height - M.config.mascot_box - 16

  local function row(lead_chip, active, title, title_color, elapsed, alpha, prefix)
    if y + 20 > content_max then
      return false
    end
    local x = 12
    if lead_chip then
      e[#e + 1] = {
        type = "rectangle",
        action = "fill",
        fillColor = active and col("accent", alpha) or col("surface0", alpha),
        roundedRectRadii = { xRadius = 4, yRadius = 4 },
        frame = { x = x, y = y + 1, w = 17, h = 15 },
      }
      text_el(
        styled(
          lead_chip,
          { size = 10.5, align = "center", color = active and col("base", alpha) or col("dim2", alpha) }
        ),
        { x = x, y = y + 2, w = 17, h = 13 }
      )
      x = x + 26
    end
    local elapsed_w = elapsed ~= "" and 30 or 0
    local title_text
    if prefix then
      title_text = styled(prefix, { size = 12.5, color = col("dim", alpha) })
        .. styled(title, { size = 12.5, color = title_color })
    else
      title_text = styled(title, { size = 12.5, color = title_color })
    end
    text_el(title_text, { x = x, y = y, w = W - x - 12 - elapsed_w, h = 17 })
    if elapsed ~= "" then
      text_el(
        styled(elapsed, { size = 10.5, align = "right", color = col("dim", alpha) }),
        { x = W - 12 - elapsed_w, y = y + 2, w = elapsed_w, h = 14 }
      )
    end
    y = y + 21
    return true
  end

  local function sub(text, alpha, indent)
    if text == "" or y + 16 > content_max then
      return
    end
    text_el(
      styled(text, { size = 10.5, color = col("dim", alpha) }),
      { x = indent, y = y, w = W - indent - 12, h = 14 }
    )
    y = y + 16
  end

  -- index agents by session+window for the join
  local by_window = {}
  local elsewhere = {}
  for _, a in ipairs(agents) do
    if a.session == session then
      by_window[a.window or ""] = a
    else
      elsewhere[#elsewhere + 1] = a
    end
  end

  -- section one: this project's windows, number order, enriched by agents
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
        sub(d and d.text or "", 1.0, 38)
      elseif agent.title and agent.title ~= "" then
        sub(agent.title, 1.0, 38)
      end
    end
  end

  -- hairline, then elsewhere: urgency-sorted, uniformly dimmed
  if #elsewhere > 0 and y + 24 < content_max then
    e[#e + 1] = {
      type = "rectangle",
      action = "fill",
      fillColor = col("surface0"),
      frame = { x = 14, y = y + 5, w = W - 28, h = 1 },
    }
    y = y + 14
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
          sub(d and d.text or "", alpha, 12)
        elseif a.status ~= "stale" and a.title and a.title ~= "" then
          sub(a.title, alpha, 12)
        end
      else
        hidden = hidden + 1
      end
    end
    if hidden > 0 then
      y = math.min(y, content_max - 16)
      sub("+" .. hidden .. " more", M.config.dim_elsewhere, 12)
    end
  end

  -- mascot footer frame: reserved space, rows above never enter it
  e[#e + 1] = {
    type = "rectangle",
    action = "stroke",
    strokeColor = col("surface1"),
    strokeWidth = 1,
    roundedRectRadii = { xRadius = 8, yRadius = 8 },
    frame = { x = 12, y = height - M.config.mascot_box - 4, w = W - 24, h = M.config.mascot_box },
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

--- Cheap serialization of everything that affects pixels; redraw only on change.
local function signature(session, windows, agents, frame)
  local parts =
    { session or "", string.format("%.0f,%.0f,%.0f,%.0f", frame.x, frame.y, frame.w, frame.h), tostring(colors_mtime) }
  for _, w in ipairs(windows) do
    parts[#parts + 1] = w.index .. (w.active and "*" or "") .. w.name
  end
  for _, a in ipairs(agents) do
    local d = dossier[a.pane]
    parts[#parts + 1] = table.concat(
      { a.session, a.name, a.status or "", fmt_elapsed(a.elapsed), a.title or "", d and d.text or "" },
      "^"
    )
  end
  return table.concat(parts, "|")
end

local function reconcile()
  load_colors()
  local window = focused_app_window()

  if not (window and enabled() and colors and TMUX) then
    if M.drawn then
      M.canvas:hide()
      M.drawn = nil
    end
    return
  end

  local session = current_session()
  if not session then
    if M.drawn then
      M.canvas:hide()
      M.drawn = nil
    end
    return
  end

  local windows = list_windows(session)
  local agents = list_agents()
  local frame = window:frame()
  local sig = signature(session, windows, agents, frame)
  if sig == M.drawn then
    return
  end

  local height = frame.h - 2 * M.config.margin
  M.canvas:frame({
    x = frame.x + M.config.margin,
    y = frame.y + M.config.margin,
    w = M.config.width,
    h = height,
  })
  M.canvas:replaceElements(build_elements(session, windows, agents, height))
  M.canvas:show()
  M.drawn = sig
end

--- Where the mascot should sit when the rail is up: centered in the
--- reserved footer. mascot.lua consults this before its own default.
function M.mascot_anchor(ghostty_frame, mascot_size)
  if not (M.drawn and enabled()) then
    return nil
  end
  local height = ghostty_frame.h - 2 * M.config.margin
  return {
    x = ghostty_frame.x + M.config.margin + (M.config.width - mascot_size) / 2,
    y = ghostty_frame.y + M.config.margin + height - M.config.mascot_box - 4 + (M.config.mascot_box - mascot_size) / 2,
  }
end

function M.start()
  M.canvas = hs.canvas.new({ x = 0, y = 0, w = M.config.width, h = 100 })
  M.canvas:level(hs.canvas.windowLevels.floating)
  M.canvas:behavior({ "canJoinAllSpaces", "transient" })
  M.canvas:clickActivating(false)

  -- pcall so no transient OS or subprocess hiccup can kill the timer.
  M.ticker = hs.timer.doEvery(M.config.tick_seconds, function()
    pcall(reconcile)
  end)
  -- Toggle flag and theme renders should not wait for the next tick.
  M.path_watcher = hs.pathwatcher.new(state_dir, function()
    pcall(reconcile)
  end)
  M.path_watcher:start()
  pcall(reconcile)
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
end

return M
