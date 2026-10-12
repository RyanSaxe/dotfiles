# Backlog

- [ ] Improve the notification service (for example, replace ntfy with Pushover).
- [x] Make rail daemon startup singleton-safe after tmux or host restarts.

  - Launch paths: `rail ensure-daemon` can currently start from three paths at
    once: the enabled-state `if-shell` in `tmux/tmux.conf`, the global
    `session-created` hook, and the global `client-attached` hook.
  - Observed failure on 2026-09-14: creating the `dotfiles` session at 10:49:37
    produced three `ensure-daemon` shell processes, three
    `node .../tuis/rail/dist/daemon.mjs` processes, and three tmux control-mode
    clients. All three daemons survived and painted the same rail panes. The
    pidfile ended at PID 2621, so `rail status` reported one daemon even though
    PIDs 2619, 2620, and 2621 were live.
  - Root cause: `tuis/rail/src/daemon.ts` used `daemon.pid` as a lock with
    exclusive create, then let a contender unlink the file when its liveness
    check said the owner was stale. That stale-file recovery was not atomic
    with the check. During concurrent startup, a contender could remove a
    fresh pidfile, claim it, and continue running. The rail panes are
    intentionally `tail -f /dev/null`; the daemon paints directly to their
    ttys. Multiple daemons can therefore interleave terminal writes and make
    the rail flicker or appear corrupted.
  - Mascot symptom: the long block of private-use glyphs seen in
    `tmux capture-pane` is an intentional 18x8 Kitty mascot placeholder grid,
    not shell output. A terminal restart can lose the image overlay while the
    placeholders remain in tmux's text buffer, and competing painters make that
    recovery less reliable.
  - Fix: `bin/rail` now starts the daemon under `lockf` or `flock`, depending on
    which the host provides. The kernel holds the exclusive lock for the
    command's lifetime, and `daemon.pid` is status information only. The lock
    file stays in place so contenders always lock the same inode. Daemon code
    refuses to start without the launcher's lock marker.
  - Verified: the launcher test races 12 startup requests, then kills the
    owner and confirms a replacement starts with the stale pidfile. On the
    live tmux server, 12 concurrent `ensure-daemon` requests left one daemon,
    one control-mode client, and one rail pane in each of four windows.

- [ ] Find out why `luals-check` fails intermittently and passes on a re-run
      of the same tree.

  - Observed on 2026-09-22 on a branch whose diff is Markdown only, so no Lua
    file changed. `prek run --all-files` reported `luals --check (nvim)` as
    Failed once, and a `git rebase -x 'prek run --all-files'` over ten commits
    stopped at the second of them. Re-running the same command on the same
    tree passed both times, and `nvim -l ci/luals-check.lua` on the base
    commit printed `Diagnosis completed, no problems found`.
  - The nvim jobs in CI have not reproduced it.
  - Unknown: what the diagnostic said. Both failing runs discarded output, so
    the first step is a run that keeps it, such as
    `prek run --all-files luals-check 2>&1 | tee /tmp/luals.log`, repeated
    until one fails.
  - Worth fixing because people learn to re-run a gate that fails for no
    reason, and a real diagnostic gets skipped that way.

- [ ] Rail mouse support: `set -g mouse on` plus click-to-act on the rail.
      v1 got clickable window names free from tmux's status bar; the rail is a
      painted pane, so the daemon must publish a row map (same pattern as
      `hints.tsv`) and a `MouseDown1Pane` bind gated on `@rail` dispatches
      `rail click <row>` — consuming the click, since the default would focus
      the rail pane, which must never happen. Scope: agent rows jump, tab
      headers switch, window rows select. ~100-150 lines. The real dogfood
      question is how global mouse-on feels everywhere else (wheel copy-mode,
      right-click menu, click-to-focus).
