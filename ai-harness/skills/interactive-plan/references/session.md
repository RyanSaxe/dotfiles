# Run the review session

Resolve commands relative to the skill directory. Keep the session
directory's path in the conversation so that an interrupted turn can resume
it.

One hub process on a fixed local port serves every live session. `start`
spawns the hub when none is running, registers the session, records the
wake path from the environment the harness gives its shell commands, so
that each session has its own, prints `{sessionId, sessionDir, url, wake}` as JSON, and exits:

```sh
node scripts/session.mjs start
```

`wake` names the harness and what was recorded. When the harness cannot be
woken, `start` refuses, creates nothing, and prints the instruction to
give the user; on Copilot it is `copilot --ui-server --resume <session id>`
with Copilot's own session id filled in. After the restart, run `start`
again. Every later command takes `--session-dir PATH`. Keep generated artifacts and feedback
outside the project's history. If a session already exists, inspect its
status and queued feedback instead of creating a replacement;
`start --session-dir PATH` resumes it at the same URL and records the wake
path again. Commands reattach on their own when the hub has exited or
restarted.

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
node scripts/session.mjs publish --session-dir PATH --file ARTIFACT.html
```

`publish` stores the artifact as `<artifactId>.<revision>.html` in the
session's `artifacts/` directory, using the values embedded in the
artifact, and refuses a revision that already exists, so build somewhere
else, such as `src/out/`. Keep old revisions so that feedback stays
attached to what the user saw; to return to an older proposal, use it as
the baseline for a new revision.

On the first publication, open the URL in the operating system's default
browser (macOS `open`, Windows PowerShell `Start-Process`, Linux `xdg-open`,
with the URL quoted) and give the link in chat, with `hostUrl` beside it
when `start` printed one. If the launch fails, say so and keep the link
available. Do not open another tab on later revisions:
the page refreshes itself when a revision lands and keeps the user's unsent
draft.

The pages carry every question. There is no question event, reply field or
reply notification, and none should be built.

## Resuming

If a turn is interrupted, the next turn runs `status` and reads any unread
event with `read` before doing anything else; do not start a replacement
session. A failed request to the hub is not completion: check that the hub
is alive, retry the same session, and inspect the recorded owner before any
recovery. Never delete ownership files without reading them.

```sh
node scripts/session.mjs status --session-dir PATH
```

When the user says in words to stop, run `pause`; the page says that the
agent stopped and that a message in the chat resumes the session. The hub
saves a submission to a paused session without waking anyone, and `read`
returns it once `start --session-dir PATH` has resumed the session:

```sh
node scripts/session.mjs pause --session-dir PATH --reason "asked to stop"
```

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

A session is live from `start` until `complete` or `pause`. After 15
minutes with no live session, the hub exits and removes its record; the
next `start` spawns a fresh one on the same port. The timeout is an
environment variable listed in [setup.md](setup.md).

The directory name under `sessions/` is not the session id in the URL;
`start` prints it as `sessionDir`, and `connection.json` inside it holds
the session id.

Under `$XDG_STATE_HOME/interactive-plan/`, the hub keeps `hub/hub.json`
(pid, port, hosts, code version, start time, and a local secret used only to
register sessions) and `hub/hub.log`. Each session lives in `sessions/<id>/`
with `status.json`, `connection.json` (`sessionId`, hub `origin`, the agent
token, and the wake target, all private to the agent), `artifacts/`,
`feedback/`, and `acceptance.json` after acceptance. Sessions never share
acknowledgements or submissions.

`status.json` records `title`, `kind`, `revisions`, `progress`, `wake`, and
`paused` next to the stage; `pause` sets `paused` and leaves the stage as
it was. `stage` is `ready`, `updated`, `submitted`,
`working`, or `complete`: a submission moves it to `submitted`, `read` to
`working`, `publish` to `updated`, `complete` to `complete`. `wake` is
`ok`, or `failed` with the reason, after the last submission; the browser
shows a failed wake and asks for a message in the chat; an agent that is
already working changes nothing on seeing it. `needsYou` is
derived in responses and is true when a published revision is waiting on
the reviewer, which is what the browser's bell counts. `publish` refuses while a submission is unread.

When `start` finds a hub on older or newer code, it uses it and logs the
mismatch; the hub restarts on the newer code once no session is live.

To review from a phone, set `INTERACTIVE_PLAN_HOST` to the machine's
Tailscale address in the shell environment before the hub starts; `start`
then also prints `hostUrl`. A hub that is already running keeps the
addresses it started with.

If the hub is unavailable, the page keeps the saved draft and offers a JSON
export. Treat an exported file as feedback, never as implementation
permission, and do not report it as acknowledged through the live protocol.
