# Backlog

- [ ] Improve the notification service (for example, replace ntfy with Pushover).
- [ ] Rail mouse support: `set -g mouse on` plus click-to-act on the rail.
      v1 got clickable window names free from tmux's status bar; the rail is a
      painted pane, so the daemon must publish a row map (same pattern as
      `hints.tsv`) and a `MouseDown1Pane` bind gated on `@rail` dispatches
      `rail click <row>` — consuming the click, since the default would focus
      the rail pane, which must never happen. Scope: agent rows jump, tab
      headers switch, window rows select. ~100-150 lines. The real dogfood
      question is how global mouse-on feels everywhere else (wheel copy-mode,
      right-click menu, click-to-focus).
