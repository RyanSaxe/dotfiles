-- Every session and terminal pane, for Rex.Snapshot in rex.go: what each
-- pane runs, in which folder and tab, the status its program reports, when
-- each app last showed an agent's pane, and whether going to its tab or its
-- session lands on it. The server answers a script about a session only
-- once the script has attached to it.
local TERMINAL = "com.superlogical.terminal"

local function landing_block(window)
  for _, layer in ipairs(window.layers or {}) do
    if layer.kind == "tiled" and #(layer.blocks or {}) > 0 then
      local first = layer.blocks[1].block_id
      for _, block in ipairs(layer.blocks) do
        if block.block_id == window.focused_block_id then
          return block.block_id
        end
      end
      return first
    end
  end
  return nil
end

-- Each tab's name when someone named it, and the pane going to the tab
-- lands on: its focused pane, or its first tiled pane when a float, such as
-- a popup, has the focus. A tab nobody named has a label made from its ID.
local function tabs(view)
  local names, lands = {}, {}
  for _, window in ipairs(view and view.windows or {}) do
    local id = window.window_id
    if window.label ~= "Window " .. string.sub(id, -8) then
      names[id] = window.label
    end
    lands[id] = landing_block(window)
  end
  return names, lands
end

---@return string? state, string? app, string? updated
local function pane_status(at)
  local status = rex.block.call(TERMINAL, "program_status", at)
  local state, app, updated ---@type string?, string?, string?
  for _, record in ipairs(status and status.records or {}) do
    -- A record with no id is the program itself, and the others its parts.
    if record.id == nil or record.id == "" then
      state, app, updated = record.state, record.app, record.updated_at
    end
  end
  return state, app, updated
end

local function pane_shown(at)
  -- An app asks for a pane's size each time it shows the pane.
  local size = rex.block.call(TERMINAL, "size", at)
  local shown = {}
  for _, request in ipairs(size and size.desired or {}) do
    table.insert(shown, request.updated_at)
  end
  return shown
end

local function build_pane(session, view, names, lands, block)
  local id = session.session_id
  local at = { session_id = id, block_id = block.block_id }
  local tab = block.window_id
  local pane = {
    session = id,
    label = session.label,
    id = block.block_id,
    tab = tab,
    tab_name = names[tab],
    focused = tab ~= nil and lands[tab] == block.block_id,
  }
  pane.visible = view ~= nil and tab ~= nil and tab == view.active_window_id
  pane.landing = pane.focused and pane.visible
  local process = rex.block.call(TERMINAL, "process", at)
  local foreground = process and process.foreground
  if foreground then
    pane.program, pane.folder = foreground.name, foreground.cwd
  end
  pane.status, pane.app, pane.updated = pane_status(at)
  if pane.status then
    pane.shown = pane_shown(at)
  end
  local title = rex.block.call(TERMINAL, "title", at)
  pane.title = title and title.title
  return pane
end

local function collect_session(snapshot, session)
  local id = session.session_id
  rex.session.attach({ session_id = id })
  table.insert(snapshot.sessions, { id = id, label = session.label })
  local view = rex.session.view({ session_id = id })
  local names, lands = tabs(view)
  local list = rex.session.list_blocks({ session_id = id })
  for _, block in ipairs(list and list.blocks or {}) do
    if block.creator_name == TERMINAL then
      table.insert(snapshot.panes, build_pane(session, view, names, lands, block))
    end
  end
end

local snapshot = { sessions = {}, panes = {} }
for _, session in ipairs(rex.call("session.list").sessions) do
  collect_session(snapshot, session)
end
return snapshot
