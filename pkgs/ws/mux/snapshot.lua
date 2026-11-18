-- Every session and terminal pane, for Rex.Snapshot in rex.go: what each
-- pane runs, in which folder, the status its program reports, when each app
-- last showed an agent's pane, and whether going to its session lands on
-- it. The server answers a script about a session only once the script has
-- attached to it.
local TERMINAL = "com.superlogical.terminal"

-- The pane going to a session lands on: the focused pane of its active tab,
-- or the tab's first tiled pane when a float, such as a popup, has the focus.
local function landing(view)
  for _, window in ipairs(view and view.windows or {}) do
    if window.window_id == view.active_window_id then
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
  end
end

local snapshot = { sessions = {}, panes = {} }
for _, session in ipairs(rex.call("session.list").sessions) do
  local id = session.session_id
  rex.session.attach({ session_id = id })
  table.insert(snapshot.sessions, { id = id, label = session.label })
  local lands = landing(rex.session.view({ session_id = id }))
  local list = rex.session.list_blocks({ session_id = id })
  for _, block in ipairs(list and list.blocks or {}) do
    if block.creator_name == TERMINAL then
      local at = { session_id = id, block_id = block.block_id }
      local pane = {
        session = id,
        label = session.label,
        id = block.block_id,
        landing = block.block_id == lands,
        agent = block.label == "agent",
      }
      local process = rex.block.call(TERMINAL, "process", at)
      local foreground = process and process.foreground
      if foreground then
        pane.program, pane.folder = foreground.name, foreground.cwd
      end
      local status = rex.block.call(TERMINAL, "program_status", at)
      for _, record in ipairs(status and status.records or {}) do
        -- A record with no id is the program itself, and the others its parts.
        if record.id == nil or record.id == "" then
          pane.status, pane.app, pane.updated = record.state, record.app, record.updated_at
        end
      end
      if pane.status then
        -- An app asks for a pane's size each time it shows the pane.
        local size = rex.block.call(TERMINAL, "size", at)
        pane.shown = {}
        for _, request in ipairs(size and size.desired or {}) do
          table.insert(pane.shown, request.updated_at)
        end
      end
      local title = rex.block.call(TERMINAL, "title", at)
      pane.title = title and title.title
      table.insert(snapshot.panes, pane)
    end
  end
end
return snapshot
