# Viewer Usage

**When to read this:** when troubleshooting the viewer daemon, when explaining the URL structure, or when extending `view.py`.

## What it is

`tools/view.py` is a self-daemonizing local HTTP server that serves a vanilla-JS web app at `http://localhost:<port>`. It walks `~/.reviews/` to discover all reviews on the machine and presents them as a **single, persistent inbox** that survives across `/assisted-review` runs and across coding-agent sessions.

The viewer is harness-agnostic — it's launched the same way from Claude Code, Codex CLI, Copilot CLI, or any other Agent Skills runtime, via a normal shell `python` invocation.

## Lifecycle

The viewer is a **cooperative singleton**: only one instance ever runs.

```text
~/.cache/assisted-review/viewer.json  ← state file: pid, port, url, started_at
```

When the daemon starts cleanly, it writes this file. When it shuts down cleanly (SIGTERM, `--stop`), it deletes the file. A stale state file (process dead) is detected and removed by the next launch.

The daemon **persists past the launching agent's exit** — it's `os.fork()`+`os.setsid()`'d into its own session. You can close Claude / Codex and the browser tab keeps working. Dies on:

- Machine reboot
- `uv run --script view.py --stop`
- `kill <pid>` from `viewer.json`

## CLI

```text
uv run --script tools/view.py --ensure --open --review-path <path-to-yaml>
```

Idempotent. Used by `/assisted-review` at the end of step 7. Behavior:

- If a live daemon is detected (state file exists, pid alive, `/api/ping` responds) → opens the deep-link in the user's default browser, exits 0.
- Otherwise → daemonizes a fresh server, waits up to 5s for the state file to appear, opens the browser, exits 0.

```text
uv run --script tools/view.py --foreground
```

Same as the default but does **not** daemonize. Useful for debugging — logs go to stderr, Ctrl-C stops cleanly.

```text
uv run --script tools/view.py --stop
```

Reads the state file, sends SIGTERM to the pid, removes the state file. Exits 0 even if no daemon was running (idempotent).

```text
uv run --script tools/view.py --status
```

Prints whether a daemon is running and at what URL. Exit 0 if running, 1 if not.

## URL structure

The web app uses path-based routing (HTML5 history API):

| URL                                     | View                                |
| --------------------------------------- | ----------------------------------- |
| `/`                                     | Inbox — all reviews on the machine  |
| `/r/<repo-slug>`                        | All reviews for one repo            |
| `/r/<repo-slug>/<sha-timestamp>`        | Single review (overview + threads)  |
| `/r/<repo-slug>/<sha-timestamp>/<file>` | File view within a review           |

`<sha-timestamp>` is the YAML filename without `.review.yaml`. URLs are bookmarkable.

## API Surface

The web app talks to the daemon via these JSON endpoints:

- `GET /api/ping` — liveness check.
- `GET /api/reviews` — inbox metadata.
- `GET /api/review/<slug>/<key>` — full review YAML parsed to JSON.
- `PUT /api/review/<slug>/<key>` — write review YAML back to disk.
- `DELETE /api/review/<slug>/<key>` — delete a review file.
- `GET /api/source?file=<path>&review=<slug/key>` — read source file contents.
- `GET /api/diff/<slug>/<key>?base=<ref>&file=<path>` — compute live Git diff
  stats and hunks from `target.repo_root`; `base` and `file` are optional.
- `GET /api/refs/<slug>/<key>` — list convenient branch/ref suggestions for
  the diff base selector.
- `POST /api/refresh/<slug>/<key>` — reload files, refresh obvious anchors,
  and update the review fingerprint.
- `POST /api/submit/<slug>/<key>` — invoke `submit.py`; body is
  `{"mode": "all" | "comment", "commentId"?: "rev-001"}`. Full review
  submission sends only comment threads; note threads remain local.

All filesystem access is restricted to `~/.reviews/` (for review files) and the `target.repo_root` declared in the review (for source files). The server refuses to read paths outside those scopes.

## Diff Context

Diff context is live viewer state, not review content. The review YAML may store `target.base_ref`, but it never stores generated patches, hunk lists, or file stats. The viewer resolves the base ref at render time, compares it to the current repo filesystem state, and exposes the result as file-tree `+x/-y` counts, source-view hunk markers, and unified-diff inspection mode.

## Staleness

A review is **stale** when `target.fingerprint` no longer matches the current folder state. If a review has no fingerprint, the viewer falls back to comparing `target.commit` with current HEAD. The user can open stale reviews and click Refresh to reload files and update obvious anchors.

Refresh only moves a thread when its `anchor_text` appears exactly once in the same file. Missing or ambiguous anchors stay at their old line and show an indicator.

## Failure modes

- **Stale state file (process crashed):** next `--ensure` detects the dead pid, removes the file, daemonizes a new instance.
- **PID reuse (rare):** state file points at a pid that was reused by an unrelated process. `--ensure` confirms the pid is _our_ viewer by hitting `/api/ping`; if it returns the wrong service signature, the state file is treated as stale.
- **Port in use:** the server tries `51234` first, increments on `EADDRINUSE`, gives up after 10 attempts. The chosen port is recorded in the state file.
- **Concurrent launches:** two `--ensure` calls at the same instant both spawn daemons. The second one's daemon detects the live state file on its way up and exits cleanly. Worst case: a second pid briefly exists. Self-resolves.
