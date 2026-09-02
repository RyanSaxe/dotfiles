# Performance and cleanup

## Assignment

This branch is an investigation and planning task. Do not begin implementing
fixes just because you find an obvious slow command or stale file. First read
the relevant code, reproduce the reported behavior, trace the complete paths,
and produce a clear implementation plan for review.

The primary goal is seamless navigation. Every jump should feel immediate, and
the UI should follow the move as quickly as the system allows. This includes
tmux, Rail, SketchyBar, Aerospace, shell popups, Workmux, and any Neovim path
that participates in navigation or review workflows.

The user reports that `Alt+O` recently took about eight seconds before the
popup showed its details. They also report lag in `Alt+R`, `Alt+Shift+R`, other
window and pane navigation, and the Starship prompt itself. Treat the eight
second report as the highest-priority reproduction target, not as an
established root cause.

The secondary goal is general cleanup:

- delete stale and unused code after proving that it is unused;
- remove rigid or misleading tests and replace them with tests of real
  behavior where needed;
- decouple systems where the current coupling adds latency or cognitive load;
- simplify the implementation without changing useful functionality or making
  the user experience slower.

## What the planning pass must deliver

Stop after producing the plan. The plan should contain:

1. A map of every important navigation path. For each key or external trigger,
   show the binding, scripts and processes it starts, state files or hooks it
   touches, and the first point at which the user sees the new state.
2. A reproducible performance matrix covering warm and cold cases. Measure
   key-to-popup, key-to-first-frame, key-to-correct-rows, direct pane/window
   switching, Rail tab changes, shell prompt redraw, and any SketchyBar or
   Aerospace handoff. Report multiple runs with p50 and p95 where practical.
3. A diagnosis table that separates confirmed causes, likely contributors,
   ruled-out causes, and unknowns. Include the measurement method and
   confidence for each conclusion.
4. A proposed architecture and implementation sequence. Explain which work
   belongs on the input path, which work can happen asynchronously, and what
   state or ownership boundaries will change.
5. A cleanup inventory grouped by safe deletion, deletion requiring a
   replacement, and code that should be preserved. Include references to call
   sites or other evidence rather than judging from file size alone.
6. A test and verification plan that checks both behavior and the actual
   interactive experience. Include rollback points and the smallest useful
   acceptance criteria for each phase.
7. A short list of decisions that require the driver's approval before
   implementation, especially changes to visible behavior, persistence,
   navigation semantics, or the role of Rail.

Do not submit a plan that says only "profile everything" or "rewrite Rail."
Name the paths, measurements, boundaries, proposed changes, risks, and order of
work. If evidence does not support a conclusion, say what experiment would
resolve it.

## Highest-priority investigation: navigation latency

The first priority is the time from an input event to a visible, correct UI
state. Do not optimize only the time spent rendering rows. A popup that exists
quickly but remains blank is a separate result from a popup that takes seconds
to be created.

Trace these paths independently:

- tmux direct window selection such as `Alt+1`;
- pane movement and the history-based `Alt+L` path;
- `Alt+O` and `Alt+S` session or repository popups;
- Rail tab changes such as `Alt+R` and `Alt+T`;
- Rail dashboards such as `Alt+Shift+R` and `Alt+Shift+T`;
- Rail agent jumps and numbered element actions;
- Workmux dashboard and worktree actions;
- SketchyBar triggers and Aerospace bindings that focus or move terminals;
- Neovim review and CodeDiff transitions when they are part of a jump.

Current code gives these concrete investigation leads:

- [tmux/tmux.conf](tmux/tmux.conf) installs synchronous `after-select-pane`,
  `session-window-changed`, and `client-session-changed` hooks. They run
  `track-pane.sh` in the tmux command path. The tracker starts more tmux
  commands, so direct window selection can still encounter hook work through
  `session-window-changed`.
- `Alt+L` runs `go-back-pane.sh`, and `goto-pane.sh` performs more selection,
  history updates, and theme or mascot synchronization. Trace the full chain,
  including hooks that fire because those scripts select panes.
- `Alt+O` launches `zsh -ic to` inside a tmux popup. The current [zsh
  startup](zsh/zshrc) loads completion, fzf-tab, autosuggestions,
  fast-syntax-highlighting, fzf bindings, theme state, and Starship before
  `to` can run. V1 had a minimal popup shell path in commit `aa44729`; verify
  what it did and what v2 removed.
- Lowercase Rail keys write tab state in the background, but the daemon notices
  state changes on its polling and wake-up path. Measure the time to state
  change, daemon observation, first repaint, and correct content separately.
- Uppercase Rail dashboard keys launch the [Rail
  launcher](tuis/rail/bin/rail), which invokes `npx tsx` and starts a fresh
  Node process. Review and task dashboards therefore have cold-start work even
  when their cached data is already available.
- The [Rail daemon](tuis/rail/src/daemon.ts) combines tmux snapshots,
  self-healing, Workmux data, task data, attention state, notifications, theme
  state, mascot rendering, and TTY writes in one recurring loop. Determine
  whether that shared loop delays navigation or only updates the display after
  navigation has already completed.

The current tree has one Rail daemon and low sampled CPU usage, so do not assume
that a duplicate daemon or a runaway CPU loop explains the report. Also do not
assume that low CPU rules out latency. Queueing, synchronous subprocesses,
filesystem waits, terminal redraws, and process startup can all make input
feel slow without high sustained CPU.

## Prompt-specific investigation

The Starship prompt needs its own trace. Separate these timings:

1. The command's exit and shell readiness.
2. Zsh `precmd` hooks before Starship renders.
3. `prompt-segments.sh` itself.
4. Any `git`, `starship module package`, theme, plugin, or filesystem work.
5. The final Starship expansion and terminal repaint.

The current prompt path is not a pure Starship render:

- `_prompt_segments` runs on every prompt from [zsh/zshrc](zsh/zshrc).
- [zsh/prompt-segments.sh](zsh/prompt-segments.sh) starts several Git
  commands, creates a temporary directory, and probes package manifests by
  running `starship module package` for every directory level between the
  current directory and the repository root.
- `_theme_refresh` checks generated theme files on every prompt and can reload
  fast-syntax-highlighting when mtimes change.
- A fresh shell also loads `compinit`, three Zsh plugins, fzf initialization,
  theme setup, and `starship init zsh` before showing its first prompt.

During the initial audit, the standalone prompt collector took roughly 0.5 to
1.5 seconds in repeated local runs. The shell-start measurement was not clean
because the restricted audit environment rejected a fast-syntax-highlighting
cache write. Reproduce this on the real machine before assigning blame to
Starship or to the sandbox artifact.

The plan should decide whether prompt facts need to be computed on every
prompt, whether package and Git facts can be cached or invalidated by directory
and repository changes, and whether popup shells need a minimal startup mode.
Do not remove visible prompt information without calling out that behavior
change and getting approval.

## Cleanup and design review

Review the authored code as a system, not as a contest to reduce line count.
Prioritize code that is both hard to reason about and involved in a hot path.
The following areas deserve explicit review:

- synchronous tmux hooks and the scripts they trigger;
- Rail daemon ownership, polling, self-healing, and TTY rendering;
- the shell and `npx tsx` launchers for popups and dashboards;
- Rail review, task, worktree, and GitHub attention boundaries;
- the Neovim CodeDiff and Snacks review bridge;
- tests that assert implementation details or exact layouts without protecting
  user-visible behavior;
- stale compatibility aliases, dead entrypoints, duplicate state ownership,
  and code paths that no caller reaches.

Do not delete a test merely because it is inconvenient to update. Classify each
candidate as a valuable contract test, a brittle implementation test, a
duplicate, or a test for behavior that no longer exists. Keep coverage for
navigation timing, state transitions, failure handling, and visible output.

Likewise, do not treat `install.sh` or any large file as a hot-path problem just
because it is large. Establish whether its complexity affects startup or
navigation before including it in the first implementation phase.

## Existing evidence

Use these facts as starting points, not as substitutes for reproducing the
current report:

- The branch starts at commit `a6e6529`, after the recent Neovim review-bridge
  simplification.
- At branch creation, the checkout was clean and matched
  `origin/v2-getting-ready` exactly.
- The Rail suite passed 153 tests and Rail typechecking passed during the
  audit. Those checks cover many state and rendering rules but do not establish
  interactive startup or navigation latency.
- A direct `track-pane.sh` run was roughly 70ms in the earlier audit, while
  `workmux status --json` was roughly 450ms. These are isolated measurements,
  not proof of the eight-second `Alt+O` path.
- `vault tasks --json` was roughly 60ms in the current environment. Measure it
  again under the user's real task volume before making task loading a primary
  suspect.
- The earlier audit found no duplicate Rail daemon and no obvious retry storm.

## Expected handoff

End with a plan that a second agent can implement in reviewable phases. Each
phase should name the files or subsystem, the behavior it preserves, the
latency or coupling problem it addresses, the evidence required before moving
on, and the rollback or containment strategy.

The first phase should make the system measurable and restore a trustworthy
latency baseline. Later phases can simplify or rebuild the parts that the
measurements show are responsible. Do not start broad cleanup until the hot
paths and user-visible contracts are understood.
