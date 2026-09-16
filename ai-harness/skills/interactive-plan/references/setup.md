# Check the environment

The helpers require Node 20 or newer and no installed npm packages. Check
`node --version` once per environment. If it is unavailable or too old, explain
the requirement and ask how the user wants to provide it.

Before the first session, run `node scripts/check.mjs` from the skill directory.
It checks writable session storage and a local HTTP endpoint. An optional path
checks another storage location; use that location for the session too.

Run the session helper through a long-running tool process. If the environment
cannot keep the helper or agent wait active, explain the limitation before
promising live feedback. See [session.md](session.md) for the review loop.
