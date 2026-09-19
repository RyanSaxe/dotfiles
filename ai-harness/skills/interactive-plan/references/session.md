# Run the review session

Resolve commands relative to the skill directory. Keep the session
directory's path in the conversation so that an interrupted turn can resume
it.

One hub process on a fixed local port serves every live session. `start`
spawns the hub when none is running, registers the session, prints
`{sessionId, sessionDir, url}` as JSON, and exits:

```sh
node scripts/session.mjs start
```

Every later command takes `--session-dir PATH`. Keep generated artifacts
and feedback outside the project's history. If a session already exists,
inspect its status and queued feedback instead of creating a replacement;
`start --session-dir PATH` resumes it at the same URL. Commands reattach on
their own when the hub has exited or restarted.

Write a complete artifact, then publish it and wait:

```sh
node scripts/session.mjs publish --session-dir PATH --file ARTIFACT.html
node scripts/session.mjs wait --session-dir PATH --timeout 55
```

`publish` stores the artifact as `<artifactId>.<revision>.html` in the
session's `artifacts/` directory, using the values embedded in the
artifact, and refuses a revision that already exists, so build somewhere
else, such as `src/out/`. When you check a revision with browser
automation, a sandboxed prototype embed captures as a blank iframe; check it
through Open full size or by serving its file directly.

On the first publication, open the URL in the operating system's default
browser (macOS `open`, Windows PowerShell `Start-Process`, Linux `xdg-open`,
with the URL quoted) and give the link in chat. If the launch fails, say so
and keep the link available. Do not open another tab on later revisions:
the page refreshes itself when a revision lands and keeps the user's unsent
draft.

Keep the agent turn waiting. The loop is `wait`, read the event, `ack`,
`progress`, publish when a revision is due, `wait` again. Every turn ends
with a `wait` in flight or with `complete`. A timeout returns
`{"waiting": true}` and is not completion: call `wait` again. A side
question does not end the session: answer it, then call `wait` again in the
same turn. An interrupted or rejected `wait` means the user wants
attention, not that the review is cancelled: answer, then wait again. The
helper saves feedback but cannot wake an ended turn, and the user cannot
see that polling stopped. If the user says in words to stop, say in the
reply that polling has stopped.

Publishing is not completion either. A revision published in reply to
feedback returns to `wait`. Only `complete`, after an acknowledged
acceptance, ends the session.

If a tool call or a turn is interrupted, the next turn resumes the same
session before doing anything else: read `status`, take the next unread
event with `wait`, acknowledge only events you have read, and return to the
loop. Do not start a replacement session.

```sh
node scripts/session.mjs status --session-dir PATH
```

A failed request to the hub is not completion. Check that the hub is alive,
retry the same session, and inspect the recorded owner before any
recovery. Never delete ownership files without reading them.

When an event arrives, read its `payload`, including the intent and the
source revision, then acknowledge the event ID:

```sh
node scripts/session.mjs ack --session-dir PATH --id SUBMISSION_ID
```

A saved receipt is not an acknowledgement. Do not acknowledge feedback you
have not read.

Right after `ack`, before any other work, declare the steps the revision
will take, then name each one as you begin it and mark it as it finishes:

```sh
node scripts/session.mjs progress --session-dir PATH --steps "Update Agreed|Write: Progress|Write: Submit"
node scripts/session.mjs progress --session-dir PATH --start "Write: Progress|Write: Submit"
node scripts/session.mjs progress --session-dir PATH --done "Write: Submit"
```

Steps are a set, not a sequence. The reviewer's working card shows every
step with its state, with the hub's own steps around them: reading the
feedback, working out the steps, checking and polishing, publishing.
Declare only the work between reading and checking; a declared "check" or
"publish" step would show twice. `--steps` takes one to twelve titles
split on `|`, unique and at most 80 characters; declaring again replaces
the list. `--start` names the steps you begin, split on `|`, and `--done`
marks one finished; an unknown title is an error. Both need an
acknowledged round (409 before `ack`), and `publish` clears the list.
Every `progress` call counts as a check-in, so an agent that reports its
steps stays live.

If the next revision depends on the user, put a question or decision on the
page next to the affected proposal. The user answers through feedback or in
the conversation. There is no question event, reply field, or reply
notification, and none should be built.

Publish each revision under a new revision identifier. Keep old snapshots
so that feedback stays attached to what the user saw. To return to an older
proposal, use it as the baseline for a new revision and reconsider the
later decisions explicitly; do not delete later history.

## Acceptance

An `accept-plan` event carries an explicit `mode`:

- `save`: acknowledge, complete, and report the durable plan path. Do not
  implement.
- `implement`: acknowledge, complete, and read the accepted plan from the
  returned path. Implement it under the project's instructions, isolation
  requirements, and existing permissions; acceptance authorizes nothing
  else.

```sh
node scripts/session.mjs complete --session-dir PATH
```

`complete` returns `nextAction` and `planPath`. Do not infer implementation
permission from feedback, a recommendation, or an acknowledgement. Leave
accepted artifacts and the acceptance record as they are; later changes
reopen review on a new revision.

## The hub

A session is live from `start` until `complete`. Every agent request
stamps `agentSeenAt`. After 15 minutes without one, the session is reported
as `disconnected` and leaves the browser's session list, while its pages
still serve. After 15 minutes with no live session, the hub exits and
removes its record; the next `start` spawns a fresh one on the same port.
Both timeouts are environment variables listed in [setup.md](setup.md).

Under `$XDG_STATE_HOME/interactive-plan/`, the hub keeps `hub/hub.json`
(pid, port, hosts, code version, start time, and a local secret used only to
register sessions) and `hub/hub.log`. Each session lives in `sessions/<id>/`
with `status.json`, `connection.json` (`sessionId`, hub `origin`, and the
agent token, private to the agent), `artifacts/`, `feedback/`, and
`acceptance.json` after acceptance. Sessions never share acknowledgements
or submissions.

`status.json` records `title`, `kind`, `revisions`, `progress`, and
`agentSeenAt` next to the stage. `stage` is `ready`, `updated`,
`submitted`, `working`, or `complete`: a submission moves it to
`submitted`, `ack` to `working`, `publish` to `updated`, `complete` to
`complete`. `disconnected` and `needsYou` are derived in responses;
`needsYou` is true when a published revision is waiting on the reviewer
(stage `ready` or `updated`), which is what the browser's bell counts.
`wait` returns the next unread event without acknowledging it; `ack` is
idempotent; `publish` refuses while a submission is unread.

When `start` finds a hub on older or newer code, it uses it and logs the
mismatch; the hub restarts on the newer code once no session is live.

To review from a phone, set `INTERACTIVE_PLAN_HOST` to the machine's
Tailscale address before the hub starts; `start` then also prints
`hostUrl`.

If the hub is unavailable, the page keeps the saved draft and offers a JSON
export. Treat an exported file as feedback, never as implementation
permission, and do not report it as acknowledged through the live protocol.
