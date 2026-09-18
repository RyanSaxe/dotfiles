# Check the environment

The helper needs Node 20 or newer, `git` on the PATH, and a current directory
inside a git work tree. It installs nothing; the browser loads its renderers
from pinned CDN URLs, so the person reading the session needs a connection.

Before the first session in an environment, run the check from the skill
directory:

```sh
node scripts/check.mjs
```

It reports the Node version, the git version, the repository root, and the
session storage it will use, and it fails with the reason when one is missing.
An optional path argument checks a different storage location; use that same
location for the session.

`gh` is not required. Pull request refs are fetched with `git fetch origin
pull/N/head`, which works wherever the remote is reachable.

Run the helper through a long-running tool process. If the environment cannot
keep a process and an agent turn alive together, say so before promising a live
session. See [session.md](session.md) for the loop.
