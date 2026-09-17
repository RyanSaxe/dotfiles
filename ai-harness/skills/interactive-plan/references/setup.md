# Check the environment

The helpers require Node 20 or newer and no installed npm packages. Check
`node --version` once per environment. If it is unavailable or too old, explain
the requirement and ask how the user wants to provide it.

Before the first session, run `node scripts/check.mjs` from the skill directory.
It checks writable session storage, a local HTTP endpoint, and the hub port:
`free`, `hub` (with the running hub's code version and live session count), or
`busy` (another program owns the port). An optional path checks another storage
location; use that location for the session too.

Environment variables, all optional:

| Variable                              | Default | Meaning                                                                 |
| ------------------------------------- | ------- | ----------------------------------------------------------------------- |
| `INTERACTIVE_PLAN_PORT`               | 4747    | The hub's fixed port on 127.0.0.1. `0` asks the OS for a port (tests).  |
| `INTERACTIVE_PLAN_HOST`               | unset   | An extra address to bind, such as a Tailscale IP, to review on a phone. |
| `INTERACTIVE_PLAN_DISCONNECT_SECONDS` | 900     | Agent silence after which a session is reported disconnected.           |
| `INTERACTIVE_PLAN_IDLE_SECONDS`       | 900     | Time with no live session after which the hub exits.                    |

Browser routes are unauthenticated, which is why the extra bind is opt in.
Agent routes require the per-session bearer token on every interface.
