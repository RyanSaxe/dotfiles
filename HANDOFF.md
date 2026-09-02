# Handoff: residual navigation lag on this machine

Delete this file when the investigation lands. You are running on the
machine that still lags after the performance rewrite. The other machine
(where the rewrite was built) measures: popup shells 12-14ms, alt+L
~50ms, window-select drain 8ms, tab repaint 55ms — flat at 80 windows
with 16 churning agents (`perf/results/`). Here, the user reports
alt+C and alt+O still take multiple seconds, and alt+L improved but
lags. Faster-but-still-slow means part of the rewrite took effect and
something local did not, or something machine-specific remains.

## Rules

Never experiment on the live tmux server — scratch `tmux -L` sockets
with explicit `-f` only. Live server access is passive reads plus the
one sanctioned action: restarting the rail daemon. Shell files here are
live via symlinks; any edit must be atomic and `sh -n`/`zsh -n` clean.
`prek run --files <changed>` before any commit.

## Step 0 — verify the deployment actually took (most likely culprit)

Each check: command → expected. Any mismatch likely IS the bug.

1. `git -C ~/generic/dotfiles log --oneline -1` → `d9a60e6` or later.
2. `ls -l ~/.config/tmux ~/.config/zsh ~/.zshrc ~/.zshenv ~/.local/bin/rail ~/.local/bin/theme`
   → ALL symlinks into THIS checkout. A copy, or a link into a different
   clone, means the pull changed nothing the live system reads.
3. `ls ~/generic/dotfiles/tuis/rail/dist/` → five `.mjs` bundles.
   Missing → `install.sh` never built them → `(cd tuis/rail && npm install && npm run build)`.
4. `pgrep -fl 'rail.*daemon\.(ts|mjs)'` → EXACTLY ONE process, ending
   `dist/daemon.mjs`. A `daemon.ts`/tsx process is the OLD polling
   daemon still alive (it hammers the server 4x/s and runs workmux
   ~450ms inline — would explain global sluggishness). Kill every match,
   then `rail ensure-daemon`, re-check.
5. `tmux show-hooks -g | grep -A2 'after-select-pane\[0\]'` → an
   `if-shell -F` format hook setting @TMUX_PREV/CURR_PANE. A `run-shell
...track-pane.sh` hook means the live config was never re-sourced:
   `tmux source-file ~/.config/tmux/tmux.conf`.
6. `script -q /dev/null env TMUX_POPUP=1 zsh -ic exit` timed (3 runs) →
   under ~100ms. Slow means the minimal-rc dispatch is not live (see 2).

## Step 1 — the alt+C suspect (uv on the popup critical path)

`theme-picker` runs `mascot-accents --providers` BEFORE its first fzf
frame, and `mascot-accents` is `uv run --script` Python with a pillow
dependency. On a machine with a cold uv cache that is seconds, on every
single alt+C. Check:

    time mascot-accents --providers        # expect <100ms warm

If it is seconds: run it twice (uv env warms once), re-time. If warm is
still slow, or you judge a Python spawn per keypress wrong on principle,
the fix is caching the provider list (it changes only when the extractor
changes) — e.g. a `--providers` cache next to the theme cache keyed on
the extractor's cksum, or shipping the list as a static file the picker
reads. Implement behind the theme test suite (`tests/theme/`).

## Step 2 — measure, do not guess

1. `uv run -q --script perf/harness.py --profile light all` → all 7
   scenarios PASS and metrics near the committed after-numbers. The
   harness is isolated; if SCRATCH numbers are fast but the LIVE server
   feels slow, the code is fine and something else loads this machine.
2. Live-server pressure (passive): time 10x
   `tmux display-message -p ok` → p50 under ~10ms. Tens of ms+ means the
   live server is busy: find what (step 3), do not tune code first.
3. Popup body vs popup frame: time `zsh -ic exit` with TMUX_POPUP=1
   (shell cost) vs pressing alt+O (frame + shell + `to`). If the shell
   is fast but the popup is slow, suspect `to`'s repo cache
   (`~/.cache/custom_scripts/_to.csv` — missing/cold means a full
   ~/worktrees scan) or server pressure delaying popup creation.
4. Daemon self-report: `kill -USR2 $(cat ~/.local/state/dotfiles/rail/daemon.pid)`
   then read the tail of `~/.local/state/dotfiles/rail-logs/daemon.log`:
   per-refresh spans (snapshot/workmux/vault ms), reason counts, and
   `slow refresh` lines say exactly where time goes. Also time
   `workmux status --json` (historically ~450ms here — poller keeps it
   off the hot path, but verify it is not erroring in a loop).

## Step 3 — machine-local suspects, in likelihood order

- Old daemon alive (step 0.4) or BOTH daemons alive.
- Stale live hooks (step 0.5).
- uv cold cache: alt+C (step 1), and first mascot flip per project.
- Another process loading the tmux server: check
  `ps aux | grep -i tmux`, sketchybar plugins, and whether dozens of
  agent shells are respawning (their zshenv brew cache warms on first
  spawn each).
- `_to.csv` cache missing → alt+O pick path rescans; the scan dirs
  include `~/worktrees`, which is large here.
- Filesystem pressure: many live agents doing IO inflate every fork —
  compare scratch-harness numbers against live-feel to separate "code"
  from "machine load".

## Deliverable

A short report committed nowhere — post it to the driver: for each
check above, expected vs measured; the identified cause(s); fixes
applied (with tests + prek green) or proposed with evidence. If a code
fix generalizes (like the alt+C provider cache), commit it to this
branch with the usual gates so both machines benefit.
