-- Shows a pane for Rex.Focus in rex.go: focuses it, which makes its tab the
-- session's active one, then has the app switch to the session and that tab,
-- since the app keeps showing its own tab when the server makes another one
-- active. The server answers a script about a session only once the script
-- has attached to it.
local at = { session_id = rex.args.session_id, block_id = rex.args.block_id }
rex.session.attach({ session_id = at.session_id })
local found = assert(rex.session.describe_block(at))
assert(rex.session.focus_block(at))
rex.client.queue("session.select", { session_id = at.session_id, window_id = found.block.window_id })
