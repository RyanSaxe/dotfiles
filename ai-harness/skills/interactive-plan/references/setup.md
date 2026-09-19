# Check the environment

The helpers require Node 20 or newer and no installed npm packages. Check
`node --version` once per environment. If Node is unavailable or too old,
explain the requirement and ask how the user wants to provide it.

Before the first session, run `node scripts/check.mjs` from the skill
directory. It checks that session storage is writable, that a local HTTP
endpoint works, and what holds the hub port: `free`, `hub` (with the running
hub's code version and live session count), or `busy` (another program owns
the port). An optional path argument checks a different storage location;
if you pass one, use that location for the session too.

Environment variables, all optional:

| Variable                        | Default | Meaning                                                                 |
| ------------------------------- | ------- | ----------------------------------------------------------------------- |
| `INTERACTIVE_PLAN_PORT`         | 4747    | The hub's fixed port on 127.0.0.1. `0` asks the OS for a port (tests).  |
| `INTERACTIVE_PLAN_HOST`         | unset   | An extra address to bind, such as a Tailscale IP, to review on a phone. |
| `INTERACTIVE_PLAN_IDLE_SECONDS` | 900     | Time with no live session after which the hub exits.                    |

Browser routes are unauthenticated, which is why the extra bind is opt in.
Agent routes require the per-session bearer token on every interface.
