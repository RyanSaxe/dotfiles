# Run the review session

Resolve commands relative to the skill directory. Keep the explicit session
directory in the conversation so an interrupted turn can resume it.

One hub process on a fixed local port serves every live session. `start`
spawns the hub when none is running, registers the session, prints
`{sessionId, sessionDir, url}` as JSON, and exits:

```sh
node scripts/session.mjs start
```

Every later command takes `--session-dir PATH`. Keep generated artifacts and
feedback outside project history. If a session already exists, inspect its
status and queued feedback instead of creating a replacement;
`start --session-dir PATH` resumes it at the same URL. Commands reattach on
their own when the hub has exited or restarted.

Write a complete artifact, then publish it and wait:

```sh
node scripts/session.mjs publish --session-dir PATH --file ARTIFACT.html
node scripts/session.mjs wait --session-dir PATH --timeout 55
```

`publish` copies the file into the session's `artifacts/` directory under
its own name and refuses a name that already exists there, so build
elsewhere, such as `src/out/`. When checking a revision with browser
automation, a sandboxed prototype embed captures as a blank iframe; check
it through Open full size or by serving its file directly.

On the first publication, open the URL in the operating system's default
browser (macOS `open`, Windows PowerShell `Start-Process`, Linux `xdg-open`,
with the URL quoted) and give the link in chat. Report a failed launch and
keep the link available. Do not open another tab on later revisions: the page
refreshes itself when a revision lands and keeps the user's unsent draft.

Keep the agent turn waiting. The loop is `wait`, read the event, `ack`,
publish when a revision is due, `wait` again; every turn ends with a `wait`
in flight or with `complete`. A timeout returns `{"waiting": true}` and is
not completion: call `wait` again. A side question does not end the session:
answer it, then call `wait` again in the same turn. An interrupted or
rejected `wait` is the user asking for attention, not cancelling the review:
answer, then wait again. The helper saves feedback but cannot wake an ended
turn, and the user cannot see that polling stopped. If the user says in
words to stop, say in the reply that polling has stopped.

Publishing is not completion either. A revision published in reply to
feedback returns to `wait`; only `complete`, after an acknowledged
acceptance, ends the session.

If a tool call or a turn is interrupted, the next turn resumes the same
session before doing anything else: read `status`, take the next unread
event with `wait`, acknowledge only events you have read, and return to the
loop. Do not start a replacement session.

A failed request to the hub is not completion: check that the hub is alive,
retry the same session, and inspect the recorded owner before any recovery.
Never delete ownership files blindly.

When an event arrives, read its `payload`, including intent and source
revision, then acknowledge the event ID:

```sh
node scripts/session.mjs ack --session-dir PATH --id SUBMISSION_ID
```

A saved receipt is not an acknowledgement; do not acknowledge unread
feedback. If progress depends on the user, put a question or decision on the
page beside the affected proposal. The user answers through feedback or in the
conversation; there is no question event, reply field, or reply notification,
and none should be built.

Publish each revision under a new revision identifier. Preserve old snapshots
so feedback stays attached to what the user saw. To return to an older
proposal, use it as the baseline for a new revision and reconsider later
decisions explicitly; do not delete later history.

## Acceptance

An `accept-plan` event carries an explicit `mode`:

- `save`: acknowledge, complete, and report the durable plan path. Do not
  implement.
- `implement`: acknowledge, complete, and read the accepted plan from the
  returned path. Implement it under the project's instructions, isolation
  requirements, and existing permissions; acceptance authorizes nothing else.

```sh
node scripts/session.mjs complete --session-dir PATH
```

`complete` returns `nextAction` and `planPath`. Do not infer implementation
permission from feedback, a recommendation, or an acknowledgement. Leave
accepted artifacts and the acceptance record intact; later changes reopen
review on a new revision.

## The hub

A session is live from `start` until `complete`. Every agent request stamps
`agentSeenAt`; after 15 minutes without one the session is reported as
`disconnected` and leaves the browser's session list, while its pages still
serve. After 15 minutes with no live session the hub exits and removes its
record; the next `start` spawns a fresh one on the same port. Both timeouts
are environment variables listed in [setup.md](setup.md).

Under `$XDG_STATE_HOME/interactive-plan/`, the hub keeps `hub/hub.json`
(pid, port, hosts, code version, start time, and a local secret used only to
register sessions) and `hub/hub.log`. Each session lives in `sessions/<id>/`
with `status.json`, `connection.json` (`sessionId`, hub `origin`, and the
agent token, private to the agent), `artifacts/`, `feedback/`, and
`acceptance.json` after acceptance. Sessions never share acknowledgements or
submissions.

`status.json` records `title`, `kind`, `revisions`, and `agentSeenAt` beside
the stage. `stage` is `ready`, `updated`, `submitted`, `working`, or
`complete`; `disconnected` and `needsYou` are derived in responses. `wait`
returns the next unread event without acknowledging it; `ack` is idempotent;
`publish` waits only for unread feedback.

When `start` finds a hub on older or newer code it uses it and logs the
mismatch; the hub restarts on the newer code once no session is live.

To review from a phone, set `INTERACTIVE_PLAN_HOST` to the machine's Tailscale
address before the hub starts; `start` then also prints `hostUrl`.

If the hub is unavailable, the page keeps the saved draft and offers a JSON
export. Treat an exported file as feedback, never as implementation
permission, and do not report it as acknowledged through the live protocol.
