# Run the review session

Resolve commands relative to the skill directory. Keep the explicit session
directory in the conversation so an interrupted turn can resume it.

Run the helper through a long-running tool process:

```sh
node scripts/session.mjs start
```

Keep the returned session directory and URL in the active conversation. Every
subsequent command requires `--session-dir PATH`. Do not use a shared current-
session file. Keep generated artifacts and feedback outside project history.

If a session already exists, inspect its status and queued feedback rather than
creating a replacement. Resume its helper with `start --session-dir PATH`.
A live owner prevents a second writer. After an abnormal shutdown, inspect the
old owner before using `--recover-lock`; do not delete ownership files blindly.

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
each revision or poll.

Keep the agent turn waiting. A timeout is not
completion; wait again. A side question does not end the session: answer it,
then resume the same wait. The helper saves feedback but cannot awaken an ended
agent turn. If the conversation is interrupted, the next turn must resume the
explicit session and read its queue.

When an event arrives, read its `payload`, including intent and source revision,
then acknowledge the event ID:

```sh
node scripts/session.mjs ack --session-dir PATH --id SUBMISSION_ID
```

A saved receipt is not an agent acknowledgement. Do not acknowledge unread
feedback. Combine it with the conversation, revisit affected decisions, and
either revise the proposal or ask a focused clarification.

```sh
node scripts/session.mjs question --session-dir PATH --text "QUESTION"
```

The browser offers a dedicated reply field. Continue waiting for its event.
The user can also answer in the agent conversation; resolve that question with
`working --session-dir PATH` before proceeding so late browser replies cannot
replace the answer. Do not create a separate chat transport.

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

Leave accepted artifacts and the acceptance record intact when the helper stops.
For later changes, reopen review on a new revision; old acceptance does not
approve modified content.

## Session operations and limitations

The helper uses an OS-assigned loopback port and a unique durable session
directory. Resume with the directory, not an old port. `connection.json` is
private to the agent; the browser needs only the session identity. Different
sessions cannot share acknowledgements or submissions.

`wait` returns the next unread event and does not acknowledge it. `ack` is
idempotent. A question receives an ID; browser replies must name that still-open
question. Resolving it in conversation with `working` invalidates late replies.
Publication requires pending feedback to be read and the question resolved.

The final acceptance dialog has explicit save and implement actions. There is
no defaulted checkbox or implicit implementation mode. The helper persists the
mode and returns it after `complete`; only the active agent can act on it.

The helper runs in the foreground of its long-running tool process. A normal
SIGTERM/SIGINT closes it and releases ownership without removing artifacts.
After an abnormal shutdown, `start --recover-lock --session-dir PATH` requires
both a dead recorded process and an unreachable old endpoint. Inspect uncertain
ownership manually; do not start concurrent recovery commands.

If the helper is unavailable, the page preserves saved draft notes and offers
JSON export. Ask the user for the exported file and treat its contents as
feedback, not as implementation permission. Do not claim it was acknowledged by
the live protocol when it was read through that fallback.
