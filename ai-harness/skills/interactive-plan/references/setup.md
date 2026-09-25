# Check the environment

The helpers require Node 20 or newer and no installed npm packages. `start`
checks what a session needs and refuses with the reason: Node too old, the
hub port taken by another program, storage it cannot write, or a sandbox
that blocks the hub. If Node is unavailable or too old, explain the
requirement and ask how the user wants to provide it.

When `start` or another command fails, run `node scripts/check.mjs` from the
skill directory. It checks each part on its own: that session storage is
writable, that a local HTTP endpoint works and which process owns the hub
port. It reports the port as `free`, `hub` (with the running hub's code
version and live session count) or `busy` (another program owns it). An
optional path argument checks a different storage location. If you pass one,
use that location for the session too.

It also reports `components`: the path the builder reads for the user's own
components, `$XDG_CONFIG_HOME/interactive-plan/components` with `~/.config`
as the fallback, whether that directory exists, and what it and the skill
hold. The builder skips it when it does not exist. The component index
states when to write there.

The hub needs a writable state directory and a listener on loopback. If the
sandbox blocks either operation, allow the skill's scripts. Do not switch to
a different state directory. A session under a temp directory is invisible
to other sessions and to the hub on the fixed port.

- Codex: the sandbox blocks both operations. The first helper failure
  identifies the sandbox, then the helper runs again with approval. The
  approval reviewer may grant that retry without a prompt. Run
  `node scripts/check.mjs --codex-rules` once outside the sandbox. It writes
  `~/.codex/rules/interactive-plan.rules`,
  a file of the skill's own with allow rules for `node` and the skill's
  three scripts. A command that matches one runs outside the sandbox on the
  first try with nothing to approve. Codex reads the file when it starts, so
  the current session still fails once on each helper command until Codex
  restarts. The check reports whether the file is present.
- Claude Code: nothing in auto mode. Otherwise allow the helper's `node`
  command in the permission settings.
- Copilot: nothing beyond the allow flags the session already needs.

Environment variables, all optional:

| Variable                        | Default | Meaning                                                                 |
| ------------------------------- | ------- | ----------------------------------------------------------------------- |
| `INTERACTIVE_PLAN_PORT`         | 4747    | The hub's fixed port on 127.0.0.1. `0` asks the OS for a port (tests).  |
| `INTERACTIVE_PLAN_HOST`         | unset   | An extra address to bind, such as a Tailscale IP, to review on a phone. |
| `INTERACTIVE_PLAN_IDLE_SECONDS` | 900     | Time with no live session after which the hub exits.                    |

Browser routes are unauthenticated, which is why the extra bind is opt in.
Agent routes require the per-session bearer token on every interface.

## When something fails

### Waking

`start` records how the hub wakes this agent, from the environment the
harness gives its shell commands. When it finds no wake path, it refuses,
creates nothing, and prints the instruction to give the user.

| Harness     | `start` records                                                                                                                            | The hub's wake call                                                               |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------- |
| Claude Code | The inbox socket and token from `CLAUDE_CODE_MESSAGING_SOCKET` and `CLAUDE_CODE_MESSAGING_TOKEN`.                                          | Two JSON lines over the socket: the auth line, then a user message.               |
| Codex       | The thread ID from `CODEX_THREAD_ID`.                                                                                                      | `codex queue --thread ID --message TEXT`                                          |
| Copilot     | The session ID from `COPILOT_AGENT_SESSION_ID` and the port the Copilot process listens on, found by walking up from the helper's process. | The SDK shipped inside the CLI resumes the session and sends with mode `enqueue`. |

Copilot listens only when started with `--ui-server`, so its refusal names
`copilot --ui-server --resume <session id>`. Its embedded server accepts any
local client when `COPILOT_CONNECTION_TOKEN` is unset. After a submission,
`status` reports the last wake under `wake.last`, with `ok` and, when it
failed, the `reason`. The browser then asks the reader to send a message in
chat.

### The hub

One hub process serves every live session. `start` spawns it when none is
running. A session is live from `start` until `complete`, `pause` or
closure from the browser. With no live session for
`INTERACTIVE_PLAN_IDLE_SECONDS`, the hub exits and the next `start` creates
a new one on the same port. When `start` finds a hub running other code, it
uses that hub and logs the mismatch, and the hub restarts on the newer code
once no session is live. A running hub keeps the addresses it started with,
so `INTERACTIVE_PLAN_HOST` takes effect only on a new hub.

### Storage

Everything lives under `$XDG_STATE_HOME/interactive-plan/`, or
`~/.local/state/interactive-plan/`:

- `hub/hub.json` holds the pid, port, hosts, code version and the local
  secret that registers sessions. `hub/hub.log` is the hub's log.
- `sessions/<dir>/status.json` holds the stage (`ready`, `updated`,
  `submitted`, `working` or `complete`), `pageRound` while a revision's pages
  are arriving, `paused` and `wake`. `status` prints it.
- `sessions/<dir>/connection.json` holds the session ID, the hub's origin,
  the agent token and the wake target. The directory name is not the
  session ID.
- The same directory holds `feedback/`, `uploads/` with the reviewer's
  images, `pages/<revision>/` with the published page records,
  `src/<revision>/<page-id>/` with each page's source, `artifacts/` with the
  built revisions, and `acceptance.json` after acceptance.
