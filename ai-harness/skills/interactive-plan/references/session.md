# Run the review session

Resolve commands relative to the skill directory. Keep the explicit session
directory in the conversation so an interrupted turn can resume it.

One hub process on a fixed local port serves every live session. `start`
spawns the hub when none is running, registers the session, prints
`{sessionId, sessionDir, url}` as JSON, and exits:

```sh
node scripts/session.mjs start
```

Keep the returned session directory and URL in the active conversation. Every
subsequent command requires `--session-dir PATH`. Do not use a shared current-
session file. Keep generated artifacts and feedback outside project history.

If a session already exists, inspect its status and queued feedback rather than
creating a replacement. `start --session-dir PATH` resumes it and prints the
same URL. Helper commands reattach on their own when the hub has exited or
restarted; nothing needs recovering by hand.

Write a complete artifact, then publish it:

```sh
node scripts/session.mjs publish --session-dir PATH --file ARTIFACT.html
node scripts/session.mjs wait --session-dir PATH --timeout 55
```

On the first publication, open the returned URL in the operating system's default
browser and also present the link in chat. Use the environment's browser-opening
tool or the platform mechanism: macOS `open`, Windows PowerShell `Start-Process`,
or Linux `xdg-open`. Pass the URL as a quoted argument. Report a failed launch
and keep the link available. Do not hard-code a browser or open another tab on
each revision or poll. The page in the browser refreshes itself when a new
revision lands and keeps the user's unsent draft.

Keep the agent turn waiting. A timeout is not completion; wait again. A side
question does not end the session: answer it, then resume the same wait. The
helper saves feedback but cannot awaken an ended agent turn. If the
conversation is interrupted, the next turn must resume the explicit session and
read its queue.

When an event arrives, read its `payload`, including intent and source revision,
then acknowledge the event ID:

```sh
node scripts/session.mjs ack --session-dir PATH --id SUBMISSION_ID
```

A saved receipt is not an agent acknowledgement. Do not acknowledge unread
feedback. Combine it with the conversation and revisit affected decisions. If
progress depends on user input, put a question component beside the affected
proposal and state what feedback is needed. The user answers through
contextual or overall feedback, the question's answer field, or in the agent
conversation. Do not create question events, reply fields, or reply
notifications.

Publish each revision under a new revision identifier. Preserve old snapshots
and attach feedback to what the user actually saw. If asked to return to an older
proposal, use it as the baseline for a new revision and explicitly reconsider
later decisions. Do not delete later history or build a branch manager.

## Honor the acceptance choice

An `accept-plan` event must explicitly contain `mode`:

- `save`: acknowledge, complete planning, and return the durable plan path.
  Do not begin implementation.
- `implement`: acknowledge, complete planning, and read the accepted plan from
  the returned path. Continue implementation under the project's instructions,
  isolation requirements, and existing permissions. This does not authorize
  unrelated actions or remove a need for approval of restricted operations.

```sh
node scripts/session.mjs complete --session-dir PATH
```

Check the returned `nextAction` and `planPath`. Do not infer execution permission
from a feedback message, a recommendation, an acknowledgement, or mere plan
acceptance without the explicit mode. The helper never executes plan content.

Leave accepted artifacts and the acceptance record intact. For later changes,
reopen review on a new revision; old acceptance does not approve modified
content.

## Sessions, the hub, and their limits

A session is live from `start` until `complete`. Every agent request stamps
`agentSeenAt`; after 15 minutes without one the session is reported as
`disconnected` and leaves the browser's session list, while its pages still
serve. After 15 minutes with no live session the hub exits and removes its
record; the next `start` spawns a fresh one on the same port. Both timeouts
are set by environment variables listed in [setup.md](setup.md).

The hub keeps `hub/hub.json` (pid, port, hosts, code version, start time, and
a local secret used only to register sessions) and `hub/hub.log` under
`$XDG_STATE_HOME/interactive-plan/`. Sessions live under `sessions/<id>/` with
`status.json`, `connection.json` (`sessionId`, hub `origin`, and the agent
token), `artifacts/`, `feedback/`, and `acceptance.json` after acceptance.
`connection.json` is private to the agent; the browser needs only the session
identity. Different sessions cannot share acknowledgements or submissions.

When `start` finds a hub running older or newer code it uses it as is and
logs the mismatch; the hub restarts on the newer code only when no session is
live.

`status.json` records `title`, `kind`, `revisions`, and `agentSeenAt` next to
the stage. `stage` is `ready`, `updated`, `submitted`, `working`, or
`complete`; `disconnected` and `needsYou` are derived in responses, never
stored.

`wait` returns the next unread event and does not acknowledge it. `ack` is
idempotent. Publication waits only for unread feedback and the normal artifact
lifecycle. The final acceptance dialog has explicit save and implement
actions; the helper persists the mode and returns it after `complete`.

To review from a phone, set `INTERACTIVE_PLAN_HOST` to the machine's Tailscale
address before the hub starts; `start` then also prints `hostUrl`. The agent
side is unchanged.

If the hub is unavailable, the page preserves saved draft notes and offers
JSON export. Ask the user for the exported file and treat its contents as
feedback, not as implementation permission. Do not claim it was acknowledged by
the live protocol when it was read through that fallback.
