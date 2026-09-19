# Backlog

- [ ] Improve the notification service (for example, replace ntfy with Pushover).
- [ ] Make rail daemon startup singleton-safe after tmux or host restarts.

  - Launch paths: `rail ensure-daemon` can currently start from three paths at
    once: the enabled-state `if-shell` in `tmux/tmux.conf`, the global
    `session-created` hook, and the global `client-attached` hook.
  - Observed failure on 2026-09-14: creating the `dotfiles` session at 10:49:37
    produced three `ensure-daemon` shell processes, three
    `node .../tuis/rail/dist/daemon.mjs` processes, and three tmux control-mode
    clients. All three daemons survived and painted the same rail panes. The
    pidfile ended at PID 2621, so `rail status` reported one daemon even though
    PIDs 2619, 2620, and 2621 were live.
  - Root cause: `tuis/rail/src/daemon.ts` uses `daemon.pid` as a lock with
    exclusive create, then lets a contender unlink the file when its liveness
    check says the owner is stale. That stale-file recovery is not atomic with
    the check. During concurrent startup, one contender can remove another
    contender's fresh pidfile, claim it, and continue running. The rail panes
    are intentionally `tail -f /dev/null`; the daemon paints directly to their
    ttys. Multiple daemons can therefore interleave cursor-control and
    Kitty-graphics writes and make the rail flicker or appear corrupted.
  - Mascot symptom: the long block of private-use glyphs seen in
    `tmux capture-pane` is an intentional 18x8 Kitty mascot placeholder grid,
    not shell output. A terminal restart can lose the image overlay while the
    placeholders remain in tmux's text buffer, and competing painters make that
    recovery less reliable.
  - Fix: use a kernel-held process-lifetime lock on a dedicated lock file. The
    daemon should hold the exclusive lock until exit, leave `daemon.pid` as
    status information only, and never let a contender delete the live lock.
    The operating system should release the lock after a crash or reboot. Keep
    the tmux hooks safe to race, and optionally reduce redundant startup
    triggers after the ownership fix is in place.
  - Acceptance examples: several concurrent `ensure-daemon` calls leave
    exactly one daemon and one control-mode client; killing the daemon does not
    strand startup behind stale state; `rail status` agrees with the process
    table; every enabled window has one rail pane after a restart; and the rail
    repaints cleanly when Ghostty or tmux is restarted.

- [ ] Rail mouse support: `set -g mouse on` plus click-to-act on the rail.
      v1 got clickable window names free from tmux's status bar; the rail is a
      painted pane, so the daemon must publish a row map (same pattern as
      `hints.tsv`) and a `MouseDown1Pane` bind gated on `@rail` dispatches
      `rail click <row>` — consuming the click, since the default would focus
      the rail pane, which must never happen. Scope: agent rows jump, tab
      headers switch, window rows select. ~100-150 lines. The real dogfood
      question is how global mouse-on feels everywhere else (wheel copy-mode,
      right-click menu, click-to-focus).
