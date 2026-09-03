# perf

Synthetic-load performance harness for the navigation stack (PLAN.md §2).
This machine cannot reproduce the loaded machine's session/agent count, so
the harness manufactures the load and measures every hot path against it —
the before/after matrix for the performance phases, plus the pane-history
behavior scenarios that gate the Phase 1 hook rewrite.

## Run

```sh
uv run -q --script perf/harness.py                # full matrix + scenarios
uv run -q --script perf/harness.py --profile light  # 2x2, 5 runs — smoke
uv run -q --script perf/harness.py assert         # behavior scenarios only
uv run -q --script perf/harness.py metrics -n 8 -m 5 -k 12 -p 8 -r 20
```

Flags (env fallback in parens): `-n` sessions (`PERF_SESSIONS`, 8), `-m`
windows per session (`PERF_WINDOWS`, 5), `-k` synthetic agents
(`PERF_AGENTS`, 12), `-p` busy background processes (`PERF_BUSY`, 8), `-r`
runs per metric (`PERF_RUNS`, 20), `--churn` heartbeat-rewrite interval in
seconds (`PERF_CHURN_SECS`, 1; 0 disables), `--label`, `--scratch`,
`--keep`. `PERF_WORKMUX_DELAY` (seconds) makes the fake `workmux status`
as slow as the loaded machine's real one.

The suite exits nonzero when any behavior scenario fails. Results land in
`perf/results/<timestamp>-<label>.md` (+ raw samples as `.tsv`) and are
committed as evidence.

## Isolation

Everything runs on a throwaway tmux server: `TMUX_TMPDIR` points into the
scratch tree and the socket is `-L perf-<pid>`, so no resolution path can
reach the live server. HOME, `XDG_STATE_HOME`, and `XDG_CACHE_HOME` are a
scratch tree wired like the live one (symlinks into this repo mirroring
`tiers/core.yaml`), so the daemon under test — started through the repo's
own `bin/rail ensure-daemon` — reads and writes only scratch state. zsh
plugins are copied, not linked, because `fast-theme` writes into the
plugin tree on every interactive start.

PATH shims (`perf/shims/`) replace the externals:

- `workmux` — assembles `status --json` from the synthetic agent state
  files; `workmux churn <secs>` rewrites their `heartbeat_ts` in a loop
  (the fs.watch → per-tick poll degradation of diagnosis #6). Calls are
  counted.
- `vault` — fixed `tasks --json` with an overdue row, counted.
- `mascot-accents` — deterministic accents per identity, no uv, no
  network; the call count is Phase 4's zero-extractor-children gate.
- `tmux` — routes PATH-resolved calls to the perf socket. Scripts that
  prepend `/opt/homebrew/bin` bypass it but land on the perf server via
  the exported `$TMUX`; `TMUX_TMPDIR` fences whatever dodges both.
- `pkill` — swallows the theme publish step's `pkill -USR2 ghostty` so a
  render can't reload the driver's live terminal.

All synthetic agents stay `status: working` so the daemon can never send a
real ntfy phone ping (the launcher sources the repo `.env`, so the channel
cannot be cleared from the environment). Known residual: `sketchybar
--trigger` and `bat` resolve through the homebrew prepend inside `theme`
and the daemon, so renders fire a few no-op triggers at the live bar (it
re-reads its own unchanged state); bat rebuilds are detected via the
scratch cache mtime instead of a shim. Never point the harness at `theme
dark|light|toggle` — those flip the real macOS appearance.

Each report ends with an isolation section: real
`~/.local/state/dotfiles` mtime diff (the live rail daemon keeps writing
its own state; harness processes hold no path there), the live server's
session list before/after, and the scratch daemon's `HOME` from `ps -E`.

## Metrics

| metric                    | what is timed                                                                                                                                              |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| window-select cmd / drain | `select-window` round trip; then until the focus hooks converge `@TMUX_CURR_PANE`                                                                          |
| alt+L end-to-end          | `goto-pane.sh back` spawn until the client sits on the expected pane                                                                                       |
| element jump              | `rail element 1` against hints.tsv until the client lands on the hinted agent pane                                                                         |
| tab write → repaint       | tab-file write until `capture-pane` of the visible rail shows the new tab's marker (reviews and tasks measured separately — tasks includes the vault exec) |
| popup shell (warm/cold)   | pty-timed `TMUX_POPUP=1 zsh -ic exit`; cold removes the zcompdump first                                                                                    |
| prompt collector          | `dash zsh/prompt-segments.sh` inside a fixture git repo (package.json level)                                                                               |
| mascot sync (noop/flip)   | `theme mascot sync` with the mascot unchanged vs alternating identities; flips also report extractor calls and bat rebuilds                                |

## Behavior scenarios (`assert`)

The parity gate for Phase 1 — they must pass on the current hook
implementation before and after the rewrite: A→B→A dedupe; cross-session
jump leaves PREV=origin/CURR=target; alt+L round-trips; a killed previous
pane clears silently; rail panes never enter history; 10× alt+L spam
leaves history sane (and `@TMUX_HIST_LOCK` unset, ahead of Phase 1's
lock) and still round-trips.

## Known gaps

Two matrix rows from PLAN.md §2 are not automated yet: warm/cold `to`
(needs a fixture repo forest under the scratch HOME for `_to`'s scan to
walk) and full live-pty precmd timing (the collector row measures the
dominant subprocess cost only). Both are additive if the numbers are
ever needed.
