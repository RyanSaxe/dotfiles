# Run the review session

Resolve commands relative to the skill directory. Keep the session
directory's path in the conversation so that an interrupted turn can resume
it.

One hub process on a fixed local port serves every live session. `start`
spawns the hub when none is running, registers the session, records the wake
path from the environment the harness gives its shell commands, so that each
session has its own, prints `{sessionId, sessionDir, url, wake}` as JSON,
and exits:

```sh
node scripts/session.mjs start
```

The `wake` field identifies the harness and the recorded wake target. When
the harness cannot receive a wake event, `start` refuses, creates nothing and
prints the instruction to give the user. On Copilot the instruction is
`copilot --ui-server --resume <session id>` with Copilot's own session ID.
After the restart, run `start` again.
Every later command takes `--session-dir PATH`. Keep generated artifacts and
feedback outside the project's history. If a session already exists, inspect
its status and queued feedback instead of creating a replacement.
`start --session-dir PATH` resumes the session at the same URL and records the
wake path again. Later commands reconnect automatically when the hub exits or
restarts.

## Wake paths

| Harness     | `start` records                                                                                                                                | The hub's wake call                                                               |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| Claude Code | The inbox socket and token from `CLAUDE_CODE_MESSAGING_SOCKET` and `CLAUDE_CODE_MESSAGING_TOKEN`.                                              | Two JSON lines over the socket: the auth line, then a user message.               |
| Codex       | The thread id from `CODEX_THREAD_ID`.                                                                                                          | `codex queue --thread ID --message TEXT`                                          |
| Copilot     | The session id from `COPILOT_AGENT_SESSION_ID` and the port the Copilot process listens on, found by walking up from the helper's own process. | The SDK shipped inside the CLI resumes the session and sends with mode `enqueue`. |

Copilot listens only when started with `--ui-server`. Its embedded server
accepts any local client when `COPILOT_CONNECTION_TOKEN` is unset.

## Publishing

Write a complete artifact, publish it, and end the turn:

```sh
node scripts/session.mjs publish --session-dir PATH --file ARTIFACT.html --source DIR
```

`publish` stores the artifact as `<artifactId>.<revision>.html` in the
session's `artifacts/` directory, using the values embedded in the artifact.
It refuses a revision that already exists, so build in the temp directory.
`--source DIR` copies the directory used to build the artifact to
`src/<revision>/` in the session before publishing. The
`status.current.source` field contains that path. Keep old revisions so
feedback remains linked to what the user saw. To return to an older proposal,
use it as the baseline for a new revision.

On the first publication, open the URL in the operating system's default
browser (macOS `open`, Windows PowerShell `Start-Process`, Linux `xdg-open`,
with the URL quoted) and give the link in chat, with `hostUrl` beside it
when `start` printed one. If the launch fails, say so and keep the link
available. Do not open another tab on later revisions. The browser refreshes
the page when a revision lands and preserves the user's unsent draft.

Every question goes on a page. There is no question event, reply field or
reply notification, and none should be built.

## Resuming

If a turn is interrupted, the next turn runs `status` and reads any unread
event with `read` before doing anything else. Do not start a replacement
session. A failed request to the hub is not completion: check that the hub
is alive, retry the same session, and inspect the recorded owner before any
recovery. Never delete ownership files without reading them.

```sh
node scripts/session.mjs status --session-dir PATH
```

When the user says in words to stop, run `pause`. The page displays that the
agent stopped and that a message in the chat resumes the session. The hub
saves a submission to a paused session without waking the agent. `read`
returns the submission after `start --session-dir PATH` resumes the session:

```sh
node scripts/session.mjs pause --session-dir PATH --reason "asked to stop"
```

## Acceptance

An `accept-plan` event includes an explicit `mode`:

- `save`: acknowledge, complete, and report the durable plan path. Do not
  implement.
- `implement`: acknowledge, complete, and read the accepted plan from the
  returned path. Implement it under the project's instructions, isolation
  requirements, and existing permissions. Acceptance authorizes nothing
  else.

```sh
node scripts/session.mjs complete --session-dir PATH
```

`complete` returns `nextAction` and `planPath`. Do not infer implementation
permission from feedback, a recommendation, or an acknowledgement. Leave
accepted artifacts and the acceptance record unchanged. A later change
requires a new revision and a new review.

## Hub lifecycle and storage

A session is live from `start` until `complete`, `pause` or closure from the
bell panel. Closure completes the session and writes `dismissedAt`. The panel
offers the close action for every session except the one being read. The
closed session's page reloads read-only, so an open tab cannot send anything.
The hub sends no more wake events for a closed session. The current turn
finishes without interruption. To resume work, start a new session. After 15
minutes with no live session, the hub exits and removes its record. The next
`start` creates a fresh hub on the same port.
The timeout is an environment variable listed in [setup.md](setup.md).

The directory name under `sessions/` is not the session id in the URL.
`start` prints the directory name as `sessionDir`, and `connection.json`
inside it contains the session ID.

Under `$XDG_STATE_HOME/interactive-plan/`, the hub stores `hub/hub.json`
(pid, port, hosts, code version, start time, and a local secret used only to
register sessions) and `hub/hub.log`. Each session lives in `sessions/<id>/`
with `status.json`, `connection.json` (`sessionId`, hub `origin`, the agent
token, and the wake target, all private to the agent), `artifacts/`,
`feedback/`, `uploads/`, and `acceptance.json` after acceptance. Sessions
never share acknowledgements or submissions.

`uploads/` holds the images a reviewer attached to a note. The hub decides
each file's type from its leading bytes, takes PNG, JPEG, WebP and GIF, and
refuses anything else, so an extension cannot make a file something it is
not. It caps one request at 10MB and names the file itself, which is why a
caller never chooses a path. A note names an image by `id`, `path`, `type`
and `bytes` under `attachments`, and the submission's text repeats the path,
so an exported JSON file names the images it cannot carry. `read` hands the
agent those paths; the file is on disk and the agent opens it. Closing a
session takes its images with it.

`status.json` records `title`, `kind`, `revisions`, `progress`, `wake`, and
`paused` next to the stage. `pause` sets `paused` and leaves the stage as it
was. `stage` is `ready`, `updated`, `submitted`, `working`, or `complete`: a
submission moves it to `submitted`, `read` to `working`, `publish` to
`updated`, `complete` to `complete`. `wake` is `ok`, or `failed` with the
reason, after the last submission. The browser displays a failed wake and
prompts for a message in the chat. If an agent is already working, the event
has no effect. Responses derive `needsYou` as true when a published revision
waits for the reviewer. The browser bell counts `needsYou`. `publish` refuses
while a submission is unread.

When `start` finds a hub on older or newer code, it uses it and logs the
mismatch. The hub restarts on the newer code once no session is live.

To review from a phone, set `INTERACTIVE_PLAN_HOST` to the machine's
Tailscale address in the shell environment before the hub starts. `start`
then also prints `hostUrl`. A running hub continues to use the addresses it
started with.

If the hub is unavailable, the browser preserves the saved draft and offers a JSON
export. Treat an exported file as feedback, never as implementation
permission, and do not report it as acknowledged through the live protocol.
