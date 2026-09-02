# Performance and cleanup: implementation plan

## Context

Navigation on the loaded machine (many tmux sessions + agents) lags by seconds:
Alt+O once took ~8s to show content; Alt+1/Alt+L/Alt+R and the prompt all drag.
This branch's job (TASK.md) was to trace every navigation path, diagnose, and
produce an implementation plan. The investigation (three full code traces plus
live-system verification and local measurements) found no single culprit —
instead, nearly every keypress does synchronous subprocess work through the
single-threaded tmux server, and six independent mechanisms all scale with
session/agent count and compound under load. The fix is not a rewrite: it is
removing everything from the input path, making the Rail daemon event-driven,
and pre-rendering the theme cascade. Most changes delete code.

**Verification model** (approved): this machine cannot reproduce the load, so a
synthetic-load harness on an isolated `tmux -L` socket establishes the matrix;
the expectation is that fixes pulled onto the loaded machine resolve the report.

## Decisions already approved by the driver

1. Synthetic load harness here; no dedicated measurement campaign on the other machine.
2. Rail daemon becomes **event-driven via a tmux control-mode client** (not tuned polling).
3. **Minimal popup shell** for Alt+O/Alt+S/Alt+C (v1 precedent, commit `aa44729`).
4. Theme/mascot: **pre-render per (mode, mascot), publish-by-copy flip** at jump time.
5. Prompt: **git facts stay fresh** (consolidated), **package walk cached** per directory.
6. bat/delta tmTheme caret pinned to a palette role → **no bat rebuild on mascot flips**.
7. Vim detection: format + pane-option based; accepted residual = hand-typed `| fzf` pipelines lose C-j/C-k (arrows still work).
8. goto-pane mid-jump race messages collapse to one generic message (pre-validation messages stay exact).

---

## 1. Navigation path map

State legend: `HIST` = `@TMUX_CURR_PANE`/`@TMUX_PREV_PANE` global options; `RAIL-STATE` = `$XDG_STATE_HOME/dotfiles/rail/{tab,page,enabled,hints.tsv}`; `GEN` = `$XDG_STATE_HOME/dotfiles/generated/`.

| Trigger                      | Binding                                                      | Chain today (blocking work in **bold**)                                                                                                                                                                                                                                                                                                                                  | First visible state                                                |
| ---------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------ |
| Alt+1..9                     | tmux.conf:151-159 `select-window`                            | fires `session-window-changed` → **run-shell track-pane.sh** (1 sh + 6 tmux round trips, HIST) + workmux's own pane-focus-in hook (background)                                                                                                                                                                                                                           | after the hook drains                                              |
| Alt+L                        | tmux.conf:136 **run-shell** → go-back-pane.sh → goto-pane.sh | **~29 serialized tmux round trips, ~55-70 processes**: scripts' 11 commands + track-pane.sh ×3 (client-session-changed, session-window-changed, after-select-pane) + compensating run-shell (goto-pane.sh:66); then background `theme mascot sync` → full cascade (row below)                                                                                            | after the whole chain drains                                       |
| C-h/j/k/l                    | tmux.conf:76-79 **if-shell ps**                              | **fork sh+ps+grep walking the entire process table** (tmux.conf:74-75), else-branch select-pane → **track-pane.sh**, rail bounce (tmux.conf:142) re-fires it once more                                                                                                                                                                                                   | after ps + hooks                                                   |
| C-b/f/u/d                    | tmux.conf:84-87                                              | same **ps walk** per keypress                                                                                                                                                                                                                                                                                                                                            | same                                                               |
| Wheel on inactive pane       | tmux.conf:104 select-pane                                    | **track-pane.sh** per event                                                                                                                                                                                                                                                                                                                                              | —                                                                  |
| Alt+O / Alt+S / Alt+C        | tmux.conf:164-170 popup `zsh -ic to\|ts\|theme-picker`       | popup frame instant, interior blank through **full interactive rc**: compinit (no -C), 7 fn files, 3 plugins, `fzf --zsh`, `fast-theme -q` (rm + 63 appends + zcompile every start, zshrc:114), starship init ×2; then `to` cache-miss rescans **995 dirs, ~160 procs** (git-repos.zsh:79-132); post-pick: switch-client → **track-pane.sh** + background mascot cascade | fzf's first frame (blank until then; rows complete at first frame) |
| Alt+Space then digit         | tmux.conf:215-232 **run-shell** (no -b) → `rail element N`   | **npx tsx cold start (~1s: daemon.ts:503)** to read hints.tsv → goto-pane chain — all while the tmux command queue is held                                                                                                                                                                                                                                               | after Node + jump                                                  |
| Alt+R/T/A (lowercase)        | tmux.conf:174,180,186 `run-shell -b rail tab X`              | bin/rail: symlink walk + `.env` source + 2 file writes (RAIL-STATE); daemon notices via fs.watch → **lost-wake bug** (daemon.ts:477-487,570-575): a write landing mid-tick is dropped → up to 2 slow ticks; any tab write also forces `vault tasks --json` next tick                                                                                                     | rail repaint                                                       |
| Alt+, / Alt+.                | tmux.conf:205-206 `rail page`                                | writes `page`, which is **not in the daemon's wake list** → waits out the full sleep                                                                                                                                                                                                                                                                                     | rail repaint                                                       |
| Alt+Shift+R/T/A              | tmux.conf:175,181,187 popup                                  | **npx tsx transpiles ~4000 lines** before main(); tasks dashboard additionally awaits `vault tasks --json` before first frame (review-dashboard.ts:613)                                                                                                                                                                                                                  | dashboard first frame                                              |
| Aerospace / SketchyBar jump  | aerospace.toml:158 → `rail jump-attention`                   | **npx tsx cold start** → goto-pane chain                                                                                                                                                                                                                                                                                                                                 | after Node + jump                                                  |
| Prompt                       | zshrc precmds                                                | `_theme_refresh` (2 zstat; on mtime change: full fast-theme cycle) → `_prompt_segments` → dash prompt-segments.sh: **5 git spawns, per-prompt tempdir mkdir/rm, (N+1)-level `starship module package` walk** → starship ×2 (PROMPT + empty RPROMPT), ×2 more per vi-mode flip (starship's own zle-keymap-select wrapper calls reset-prompt)                              | prompt paint                                                       |
| Cross-project jump aftermath | goto-pane.sh:69, tmux.zsh:38                                 | background but lands ~0.5-3s later: `mascot-accents` (uv+Python+Pillow, pokeapi-capable) → **full 13-template render (~45 procs)** → `bat cache --build` (1-3s) → `pkill -USR2 ghostty` + sketchybar trigger → GEN mtimes move → daemon re-sources tmux colors + full rail repaint → **every open shell runs the fast-theme cycle at next precmd**                       | jank wave post-jump                                                |
| Rail daemon (recurring)      | daemon.ts loop                                               | every 250ms: `list-panes -a` (17 fields, O(panes)) + `list-clients`; workmux status every 5s **or every tick under agent-state churn** (watch fires on heartbeat rewrites, daemon.ts:536-546); vault every 5s/60s; self-heal every tick (its select-pane **re-fires the user's hooks**); blocking full-frame TTY writes per changed rail pane                            | —                                                                  |
| Nvim review/CodeDiff         | via dashboards/element jumps                                 | entry latency is the npx cold start (fixed in Phase 3); the bridge itself was simplified in the three commits before this branch and shows no hot-path involvement                                                                                                                                                                                                       | —                                                                  |

Not on any hot path (verified live): status line (`status off`, no `#()` formats), gh/GitHub attention (launchd-owned, 300s, daemon reads cached state.json only), install.sh.

## 2. Performance matrix

### Baseline measured (this machine — warm, light load: 2 sessions / 10 panes / 1-2 agents)

| Measurement                        | Value                                | Method                                      |
| ---------------------------------- | ------------------------------------ | ------------------------------------------- |
| tmux client round trip             | ~3.5ms                               | 10× display-message / list-panes -a         |
| track-pane.sh (6 round trips)      | ~25ms                                | timed direct run (audit)                    |
| Full interactive zsh start         | ~65-85ms warm, ~250ms first-run      | 5× pty-wrapped `zsh -ic exit`               |
| prompt-segments.sh                 | ~10ms warm                           | 3× timed dash run                           |
| `npx tsx --version` (no transpile) | ~170ms                               | 3× timed; +transpile ≈ 1s per daemon.ts:503 |
| `node -e ""`                       | ~29ms                                | timed                                       |
| `to` cache-miss rescan             | ~0.4s warm (53 repos, 995 dirs)      | timed walk + per-repo git                   |
| `workmux status --json`            | 39ms here / ~450ms on loaded machine | timed; audit note                           |
| `vault tasks --json`               | ~44-60ms                             | timed                                       |

These numbers are the floor. The report's magnitude comes from load: every round trip, fork, and FS touch inflates under agent process pressure, and the blocking chains multiply them.

### Harness (built in Phase 0, committed as `perf/`)

- Isolated socket `tmux -L perf` with the repo config; `XDG_STATE_HOME`/`XDG_CACHE_HOME` pointed at a scratch dir so rail state, workmux agent files, and theme output never touch the live system (hard rule: no lifecycle experiments on the live server).
- Load synthesis, parameterized: N sessions × M windows (target 8×5), K synthetic workmux agent JSON files with a churn loop rewriting heartbeats, P background busy processes to simulate agent CPU/process-table pressure.
- Metrics, ≥20 runs each, report p50/p95, warm and cold (cold = rm `_to.csv`, `.zcompdump`, theme cache):
  1. Window-select command drain: `time tmux -L perf select-window` (command returns when the queue, including hooks, drains — exactly the blocking cost).
  2. Alt+L end-to-end: timed go-back invocation + correct-pane assertion.
  3. Popup key-to-first-frame: pty-timed `TMUX_POPUP=1 zsh -ic exit` plus timed `to` with warm/cold cache.
  4. Element jump end-to-end: timed `rail element 1` against fixture hints.tsv + landing assertion.
  5. State-write → repaint: timestamp the tab write; daemon telemetry (Phase 0) logs the paint.
  6. Prompt: timed collector + `EPOCHREALTIME` around precmd in a live pty shell.
  7. Warm/cold `theme mascot sync` wall time + child-process count.
- The harness also runs the behavioral assertions listed per phase (history correctness, hook parity, etc.).

### Acceptance targets (loaded harness profile, p95)

| Path                             | Baseline expectation under load | Target after                      |
| -------------------------------- | ------------------------------- | --------------------------------- |
| Window select drain              | tens to hundreds of ms          | **< 10ms**                        |
| Alt+L end-to-end                 | 100ms-seconds                   | **< 50ms**                        |
| Popup blank time (warm)          | 300ms-seconds                   | **< 150ms**                       |
| Element jump                     | ~1-2s                           | **< 100ms**                       |
| Tab write → repaint              | 250ms-1s+ (lost wake)           | **< 150ms**                       |
| Prompt collector (warm, in-repo) | 40-80ms                         | **< 30ms**                        |
| Warm mascot flip                 | 2-5s cascade                    | **< 150ms, zero uv/bat children** |
| Steady-state daemon tmux polls   | 4/s                             | **0.5/s**                         |
| workmux execs under churn        | up to 4/s                       | **≤ 1 per 5s**                    |

## 3. Diagnosis table

| #   | Finding                                                                                                                               | Class                                                                                      | Method                                                                                      | Confidence |
| --- | ------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------- | ---------- |
| 1   | All three nav hooks run track-pane.sh via blocking run-shell; one Alt+L = ~29 serialized round trips before the key retires           | **Confirmed cause**                                                                        | code (tmux.conf:133-136, scripts) + man-verified run-shell semantics + live `show-hooks -g` | High       |
| 2   | Alt+O pays the full interactive rc; v1's minimal popup shell (aa44729) is not an ancestor of HEAD — v2 kept only the TMUX_POPUP guard | **Confirmed cause**                                                                        | git archaeology + zshrc read + pty timing                                                   | High       |
| 3   | `to` cache-miss rescan (995 dirs, ~160 procs) rides the popup path and re-runs after every pick                                       | **Confirmed contributor** to the 8s                                                        | timed; cold multi-second plausible, exact 8s split unknown                                  | Med-high   |
| 4   | Element jumps/dashboards block on `npx tsx` cold start (~1s)                                                                          | **Confirmed cause**                                                                        | in-repo comment + measured boot floor                                                       | High       |
| 5   | Daemon lost-wake bug + page not in wake list + tab→vault coupling                                                                     | **Confirmed cause** (rail latency)                                                         | code (daemon.ts:477-487, 570-575; bin/rail:142)                                             | High       |
| 6   | Agent-state churn degrades the 5s workmux poll to per-tick (~450ms each on the loaded machine), dilating all tick-counted cadences    | **Confirmed mechanism**, magnitude to verify via telemetry                                 | code + live state-file timestamps                                                           | Med-high   |
| 7   | Cross-project jump triggers full theme cascade incl. uv/Python, 13 templates, bat cache build, per-shell fast-theme hitch             | **Confirmed cause** (post-jump jank)                                                       | code (theme:474-518, zshrc:107-131)                                                         | High       |
| 8   | Prompt spawns ~20 procs; starship execs 2-4× per prompt (empty RPROMPT + vi-mode reset-prompt via starship's wrapper)                 | **Confirmed contributor**                                                                  | code + `starship init zsh --print-full-init` + timing                                       | High       |
| 9   | ps full-process-table walk per C-hjkl/C-bfud keypress                                                                                 | **Confirmed contributor** (scales with agent count)                                        | code (tmux.conf:74-75)                                                                      | High       |
| 10  | tmux server single-threaded queue contention multiplies 1-9 under load                                                                | **Likely amplifier**                                                                       | architecture; harness quantifies                                                            | Med        |
| 11  | Duplicate rail daemon / retry storm / runaway CPU loop                                                                                | **Ruled out**                                                                              | live ps + serial awaited loop + audit                                                       | High       |
| 12  | Status-line periodic shell, network on prompt path                                                                                    | **Ruled out** (status off, no #(); only a dormant FSH curl behind a cache-existence check) | live verification                                                                           | High       |
| 13  | Whether same-session switch-client fires client-session-changed                                                                       | **Unknown** (moot once hooks are native)                                                   | harness experiment if ever needed                                                           | —          |
| 14  | Exact per-cause split of the 8s on the loaded machine                                                                                 | **Unknown**                                                                                | Phase 0 telemetry + pulled fixes answer it                                                  | —          |

## 4. Architecture and implementation sequence

Boundary principles: **zero synchronous subprocess work on any keypress path**; the daemon is event-driven and never competes with input; one owner per state file; theme output is a cache lookup, not a render. Each phase is independently landable and revertible; `prek run --all-files` and `npm test` (rail) stay green at every phase boundary.

### Phase 0 — Measurability (no behavior change)

Files: `tuis/rail/src/telemetry.ts` (new, ~60 lines), `daemon.ts` (wire spans into the existing tick), `bin/rail` (LOG_FILE path), `perf/` (new harness).

- Telemetry: per-tick duration + per-source latency + paint counts, 256-sample ring buffer, SIGUSR2 dumps JSON to the log; refreshes >250ms log inline with breakdown.
- Move the log to `$XDG_STATE_HOME/dotfiles/rail-logs/` — **out of the watched STATE_DIR** (today every stderr write re-fires the daemon's own watcher) — with a 1MB boot-time rotation.
- Micro-fixes that are pure hygiene: single `loadReviewSnapshot()` per tick (currently daemon.ts:394 and 405), `maxBuffer: 8MB` + timeout on `workmux status --json` (silent-overflow fix), remove the unused `acknowledgedPaneIds` import, ntfy 60s cooldown after failure (429 storm in the live log).
- Build the harness; record the baseline matrix (the "before" numbers).
  Evidence gate: harness runs green; baseline table committed to `perf/`. Rollback: revert.

### Phase 1 — The keypress path (tmux layer)

Files: `tmux/tmux.conf`, `tmux/scripts/goto-pane.sh`, `tuis/rail/bin/rail`, `nvim/lua/config/autocmds.lua`; deletes `tmux/scripts/track-pane.sh`, `tmux/scripts/go-back-pane.sh`.

**1a. Native pane history.** Replace the three blocking hooks with in-server format work (no shell, no round trips): `set-hook` blocks guarded by `if -F` on `#{@TMUX_HIST_LOCK}` / `#{@rail}` / `#{pane_floating}` / self-move, doing `set -gF @TMUX_PREV_PANE '#{@TMUX_CURR_PANE}'; set -gF @TMUX_CURR_PANE '#{pane_id}'`. Dead-pane validation moves to a `pane-exited` cleanup hook (append after the existing reap hook) plus jump-time validation that already exists. The rail bounce hook (tmux.conf:142) is unchanged and still appended last.

**1b. goto-pane rewrite.** Absorb go-back-pane.sh as `goto-pane.sh back` (Alt+L becomes `run-shell -b`). Jump = 4 tmux invocations total: origin capture, target validation, one chained `set @TMUX_HIST_LOCK 1 \; switch-client \; select-window \; select-pane`, one chained history write + lock clear (with an EXIT trap clearing the lock). The lock makes hook firing during the jump a no-op, so the compensating run-shell (goto-pane.sh:66) is deleted. Approved contract change: three mid-jump race messages collapse to one; pre-validation messages stay byte-identical. `theme mascot sync` stays backgrounded (cheap after Phase 4). CLI shape (`<session> <window> <pane> [quiet|strict]`) is preserved for `tab-element.ts` and `jump-attention.ts`.

**1c. Element jumps without Node.** Move the dead-but-correct `bin/rail jump` awk logic into the `element` case: agents tab resolves hints.tsv in shell and execs goto-pane.sh (semantics from tab-element.ts preserved: tab normalization, digit validation, silent display-message miss); reviews/tasks tabs fall through to the Node path (dist after Phase 3). All 18 `tab`-table bindings get `-b`. Delete the unreachable `jump` case afterward.

**1d. Vim detection without ps** (approved, incl. the residual corner): `is_vim` becomes a format OR of (a) `#{m/r:...}` on `#{pane_current_command}`, (b) `@is_vim` pane option set/unset by nvim autocmds (VimEnter/VimResume via async `vim.system`, VimLeavePre/VimSuspend awaited; guarded by `vim.env.TMUX_PANE`; honored only when the foreground command isn't a plain shell so a crashed nvim can't wedge navigation), (c) `@is_fzf` set by wrapped fzf widgets in zshrc. Bindings switch to `if-shell -F`. Rollback for this item alone: restore the ps string (one variable).

Behavior preserved: identical navigation, history semantics, rail bounce, jump messages (minus the approved collapse). Evidence gate (harness): A→B→A dedupe; cross-session jump leaves PREV=origin/CURR=target; Alt+L round-trips; killed-prev clears silently; rail panes never enter history; 10× Alt+L spam leaves lock unset and history sane; vim-detection parity matrix (nvim fg / behind git commit / suspended / crashed; Ctrl-R fzf; fzf-tab); window-select drain and Alt+L targets hit. Config-parse smoke on a scratch server before live reload. Rollback: revert restores the scripts; the `set-hook -gu` preamble means a live reload fully swaps implementations.

### Phase 2 — Popup shell + the per-shell theme hitch

Files: `zsh/zshrc.minimal` (new), `zsh/zshrc` (two independent hunks).

- **Popup dispatch** at the top of zshrc, before the scrubber: `TMUX_POPUP=1` sources `zshrc.minimal` and returns. Minimal rc = `functions/tmux.zsh` + `functions/git-repos.zsh` + generated `shell-colors.zsh` (required: `FZF_DEFAULT_OPTS` styles the popup **and** its explicit scheme suppresses fzf's terminal-theme autodetection, whose mode-2031 probe otherwise leaks literal `?997;2n` into queries) + `PROMPT='$ '`. No compinit, no plugins, no starship, no fast-theme, no venv. Keep `zsh -ic` in the bindings: interactive job control gives `to`'s background rescan and the mascot sync their own process group so popup teardown doesn't kill them (documented v1 regression). Covers Alt+O, Alt+S, Alt+C, prefix o/s.
- **fast-theme decoupling** (zshrc:107-131): split `_theme_refresh` so a `shell-colors.zsh` mtime change only re-sources it + resets the fzf-tab zstyle, and only a `fast-syntax-highlighting.ini` change runs `fast-theme`. The ini is accent-independent (verified: no accent placeholders), so mascot flips stop hitching every open shell immediately — before Phase 4 even lands.
  Evidence gate: pty-timed popup start < 150ms warm; Alt+O/Alt+S/Alt+C full manual matrix (pick new/existing session, cancel, `to -f`); mascot flip with 3 shells open hitches none. Rollback: each hunk reverts independently.

### Phase 3 — Rail: cold-start elimination, then the control-mode rebuild

Files: `tuis/rail/{package.json, bin/rail, src/daemon.ts, src/data.ts, src/control.ts (new), src/scheduler.ts (new), src/pollers.ts (new), src/sprite.ts, src/review-dashboard.ts}`, `install.sh`, `tmux/tmux.conf`, `bin/attention`.

**3a. Build pipeline.** esbuild (already vendored; add as explicit devDependency) bundles each entrypoint to `dist/*.mjs` (zero runtime deps — trivial single-file bundles); `bin/rail` runs `node dist/…` with an mtime-checked `ensure_built` (a `find -newer dist/.stamp` probe, ~5ms) so edit-and-press keeps working; `install.sh` appends `npm run build`. Restructure `bin/rail` fast paths: `tab/page/on/off/toggle/status` skip the symlink walk and `.env` entirely; `.env` sourcing moves into `ensure_daemon` (its only consumer). Update both `daemon.ts`-greps in the liveness checks (bin/rail:70, daemon.ts:495) to a transition-safe pattern. Same swap in `bin/attention`. Tasks dashboard renders a loading frame instead of awaiting vault before first paint. Escape hatch: `RAIL_RUN=tsx` env flips back to `npx tsx`. Tests keep running via tsx; add a `--health` build smoke.

**3b. Control-mode client (landed dark).** New `src/control.ts`: spawn `tmux -C attach-session -f no-output,no-detach-on-destroy` (flags verified on tmux 3.7c), line-parser separating `%begin/%end/%error` blocks from notifications, FIFO command correlation, reconnect backoff ladder (100ms→2s), sustained has-session failure (10s) → clean exit with pidfile removal (today's contract, so ensure-daemon revives it with the next server). Events are **wake signals**; `list-panes -a` (sent over the control socket, saving an exec on the hot path) remains the source of truth — full event-sourcing rejected: events don't carry the 17 render fields and can't see pane-level changes in non-attached sessions. Mutations (self-heal) stay on the exec path so a wedged control client can never block healing. Filter self from `list-clients` via `#{client_control_mode}`; derive `sessionAttached` from filtered client rows (the control client would otherwise pollute `#{session_attached}`).

**3c. Scheduler rewrite.** Delete the `sleep`/`wakeLoop` pair. New `makeRefreshScheduler` (dirty-flag + coalesce 25ms + min-interval 50ms, single-flight with post-run recheck — a signal can land at any instant and is never dropped). `refreshAndRender()` = today's tick body reading from caches. Per-source wall-clock pollers: workmux 5s with a 1s trigger-floor and **content-compare** on the parsed agent tuple (heartbeat churn stops causing execs _and_ renders); vault 5s-on-tasks-tab/60s-otherwise, triggered only when switching **to** tasks; ioreg 5s; attention via fs.watch on its state dir; a 2s reconcile backstop replaces TICK_MS (10s when disabled+clientless). Wake sources: control notifications (curated list incl. `%session-window-changed`, `%layout-change`, `%unlinked-window-*`), STATE_DIR watch now including `page`, theme watch, poller change callbacks. `RAIL_NO_CONTROL=1` escape hatch keeps the exec-snapshot fallback path selectable.

**3d. Guard rails + supervision.** `sprite.ts` opens ttys `O_WRONLY|O_NONBLOCK|O_NOCTTY`; EAGAIN/partial → retry next refresh (a blocked pty can no longer stall every rail). Rendering stays full-frame-per-bucket (writes only happen on change; row-diffing complicates the pushed/sprite invariants for little gain — harness will confirm). Supervision: `session-created` and `client-attached` hooks poke `rail ensure-daemon` with `-b` (idempotent, ~10ms when alive); launchd KeepAlive rejected as disproportionate.

Behavior preserved: all rail visuals, tab semantics, self-heal invariants (attached-session heal latency improves to ~20ms; non-attached worst case 2s — today's idle cadence), notification behavior. Evidence gate: all 153 existing tests green untouched (they cover pure modules and survive by design — data.ts fixtures extend additively); new unit tests for control parser (chunk-split lines, block correlation, reconnect), scheduler (no dropped signal across interleavings), pollers (churn floor, single-flight), wake decoupling (tab→reviews doesn't touch vault); harness: tab-write→repaint, element jump, steady-state poll rate, workmux exec rate under churn targets from §2. Rollback: 3a via `RAIL_RUN=tsx`; 3b/3c one revert (state files and bin/rail interface unchanged).

### Phase 4 — Theme pre-render

Files: `theme/bin/theme`, `theme/templates/Dotfiles.tmTheme.tmpl`, `tests/theme/test_theme_cli.py`, `tuis/rail/src/mascot.ts`.

- **Pointer = publish-by-copy, not a symlink flip** (decision made during design): `generated/` stays a flat real dir; a warm flip `cmp`s each cached file and `mv`s only changed ones (~10 small files). Rationale: the rail daemon's `fs.watch` and nvim's `fs_event` are inode-pinned — a directory-symlink retarget silently breaks both; copy-publish keeps **every existing consumer working with zero code changes** and preserves the mtime discipline (unchanged files keep mtimes, so the fsh ini and frame.glsl don't fire watchers on mascot flips).
- Cache: `$XDG_STATE_HOME/dotfiles/cache/theme/render-<rstamp>/<mode>-<key>/` (+`.complete`), `accents-<astamp>/<key>.conf`; stamps = cksum over templates/tokens/palettes (and the accents script), so edits invalidate; stale stamp dirs pruned after cold builds; `rm -rf` of the cache is always safe.
- `theme mascot sync` fast path: resolve → unchanged exits (as today) → cached: copy accents into place + publish + gated notifications (`pkill -USR2 ghostty` only when a shader/theme file actually changed; sketchybar trigger; tmux + rail + nvim + shells all converge via existing watchers — no new notification plumbing) → uncached: extraction + render into the cache in the background, flip afterward, superseded-by-later-jump guard. Warm flip budget: ~45 trivial procs, <150ms, **zero uv/python/bat children**. `apply/dark/light/toggle/mascot` route through the same render-into-entry + publish primitives; optionally pre-warm the opposite mode after a flip.
- **bat** (approved): pin the tmTheme caret to a palette role → tmTheme is mode-only → mascot flips never rebuild bat's cache or touch codex.
- Rail daemon's duplicate `mascot-accents` spawner (`src/mascot.ts:84-99`) reads the accents cache first; theme script remains sole writer.
- Delete orphaned `generated/jewelbox-dark|light` (no template, no consumer).
  Evidence gate: extended pytest suite (warm sync spawns zero `mascot-accents` — stub counts; fsh-ini mtime survives a flip; stamp change forces re-render; superseded sync doesn't flip; publish preserves unchanged mtimes); harness warm-flip target; visuals verified live per surface (tmux colors, rail, ghostty, prompt accent) after a real cross-project jump. Rollback: revert `theme/bin/theme` + delete cache dir; consumers were never touched.

### Phase 5 — Prompt diet + startup shavings

Files: `zsh/prompt-segments.sh`, `zsh/zshrc`, `zsh/zshenv`.

- Git: 5 spawns → 3 (`git status --porcelain=v2 --branch` for branch/ahead-behind/dirty; `rev-parse --show-toplevel --show-prefix --short HEAD`; `log -1 --format=%cr`), sequential capture, per-prompt tempdir deleted. All displayed segments byte-identical (parity fixtures below).
- Package walk: manifest-presence probe per level is free `[ -f ]` checks; only levels **with** manifests do work — cached in `~/.cache/dotfiles/pkg-versions.tsv` keyed on batched manifest mtimes; miss = one `starship module package`. Manifest list pinned to starship's docs with a drift-risk comment.
- Starship execs halved: `RPROMPT=''` after init (template has no right_format — the default init execs starship per render to print nothing); fix the wrong "spawns nothing" comment (zshrc:146-153). Vi-mode flips drop from 4 execs to 1.
- Startup: `compinit -C` when the dump is <24h old; `brew shellenv` output cached keyed on brew binary mtime (off **every** zsh, including each agent Bash call); scrubber gets a free dead-socket test + O(1) `display-message -t $TMUX_PANE` check instead of `list-panes -a` when TMUX_PANE is set.
  Evidence gate: **byte-parity harness** — old vs new collector across fixture repos (clean/dirty/ahead/behind/both/detached/no-upstream/no-commit/subdir/package-level/venv/outside-repo) diffed on emitted name/value lines; timed collector target; `zsh -ic exit` and `zsh -c exit` before/after. Rollback: one file each.

### Phase 6 — Cleanup execution + docs truth pass

Files: `tuis/rail/bin/rail`, `tuis/rail/src/tabs.ts`, `tuis/rail/README.md`, stale comments touched by earlier phases.

- Execute remaining safe-deletes from §5; rewrite README claims to match the new reality (cadences, hints are digits via alt+space, status-bar wording, command inventory, stabilization 60s); re-run the full harness matrix and commit the after-table to `perf/`.
- Final acceptance: pull the branch on the loaded machine; the report's paths (Alt+O, Alt+R, Alt+Shift+R, window/pane nav, prompt) get a subjective re-check plus a SIGUSR2 telemetry dump to attribute anything still slow.

## 5. Cleanup inventory

### Safe delete (evidence: zero callers/bindings, verified by grep + binding sweep)

- `tmux/scripts/track-pane.sh`, `tmux/scripts/go-back-pane.sh` (Phase 1 replaces; goto-pane.sh keeps path + CLI).
- `bin/rail jump` case (no binding invokes it; logic recycled into `element` first) and `review-dashboard` alias (bin/rail:191-194).
- `src/tabs.ts:59` `saveRailTab` (tab file written only by shell); `daemon.ts:26` unused import.
- `generated/jewelbox-dark|light` orphans; stale `attention-events.json` state file (no repo reference).

### Delete/change requiring replacement (replacement named)

- Blocking hooks + compensating run-shell → native hooks + jump-time writes (Phase 1).
- npx/tsx entrypoints → dist bundles + `RAIL_RUN=tsx` hatch (Phase 3a).
- `sleep`/`wakeLoop` → scheduler (Phase 3c). Log location/rotation, ntfy backoff, workmux maxBuffer → Phase 0.
- Full-render-on-sync → cache + publish (Phase 4). README drift → Phase 6.

### Keep (looks duplicated, is intentional)

- Rail-window reaping in both `reap-rail-window.sh` and selfHeal (instant path + backstop, documented); `kill_rail_panes` in `rail off` likewise.
- Dual daemon-liveness checks (different processes need each; both updated in lockstep for dist).
- `bin/attention`'s own `.env` sourcing (launchd has no other env source).
- The workmux `pane-focus-in` window hook: **tool-owned, untouched** (its no-op `$()` kill is noise-level after Phase 1; optional upstream report, out of scope).
- The nvim CodeDiff/Snacks review bridge: recently simplified, not on a hot path; revisit only if Phase 0 telemetry implicates it.
- install.sh: not hot-path (config-time only); only touched to add the rail build step.

**Tests:** all 153 rail tests are contract tests over pure modules and survive; none deleted. `tests/theme` extends. New tests are listed per phase. No test is removed anywhere in this plan; brittle-test review found the suite already avoids implementation pinning (the closest, `tabcheck.test.ts`, usefully pins the tab→action mapping the shell dispatch mirrors).

## 6. Test and verification plan

- Per phase: targeted `prek run --files …` while iterating, `prek run --all-files` + `nvim -l ci/luals-check.lua` (Phase 1d lua) + rail `npm test` before each phase lands.
- Harness (perf/) runs the behavioral assertions and the latency matrix after Phases 0, 1, 2, 3, 4; results committed alongside so before/after is reviewable. All lifecycle experiments on `tmux -L perf` sockets only — never the live server; live verification is limited to config reload + using the real interface.
- Real-interface checks per phase (the thing tests can't prove): actually jump around with Alt+1/L/O/S/Space-digit, flip projects and watch the mascot/colors land, open dashboards, use C-hjkl inside real nvim and Ctrl-R fzf, watch the rail follow tab/page keys.
- Rollback points: every phase is one revertible commit-group; `RAIL_RUN=tsx` and `RAIL_NO_CONTROL=1` allow live A/B without reverting; Phase 1's hook preamble (`set-hook -gu`) makes a config reload a complete implementation swap in either direction.
- Final acceptance: the loaded machine pulls the branch; the original complaints re-checked, telemetry dump reviewed.

## 7. Approvals record and residual risks

All seven driver decisions listed at the top are approved (this conversation). No visible prompt information is removed; no navigation semantics change. Remaining known residuals, accepted: vim-detect `| fzf` pipeline corner (arrows work; ps one-liner is the documented rollback); mid-jump race message collapse; package version staleness only if a manifest changes without an mtime bump; new completions visible up to 24h late under `compinit -C`; first-ever visit to a new project renders its theme in the background (mascot lands a beat late, once per project).
