# Claude Notifications Redesign — Summary

Date: 2025-09-06

## Overview

Replaced unreliable tmux bell-based indicators with a simple, explicit file-based unread state for Claude panes. Integrated a hardened `tc` picker, utility helpers, and optional hooks from Claude Code and tmux.

## What Changed

- tmux
  - Removed all bell-related options and orange bell styling.
  - Restored `prefix + c` for new-window; kept `Alt+c` to open Claude picker.
  - Added focus hook to mark notifications as read on pane focus:
    - `set-hook -g pane-focus-in 'run-shell "bash ~/.claude/notify/mark-read.sh #{pane_tty}"'`
- zsh (`tc`)
  - Sources Claude utils, validates required functions, checks `fzf`.
  - If a single Claude pane exists, jumps directly.
  - Robust `fzf` parsing using a hidden tab-delimited column (ANSI-safe).
- Claude utils
  - `format_claude_pane()` now shows 🔔 if `~/.claude/notify/unread/<pane_id>` exists (file-based unread), otherwise ✓.
  - Added `resolve_pane_id` (accepts `%id`, `session:win.pane`, or `/dev/tty*`).
  - Hardened `is_claude_pane` using headerless `ps`.
- New scripts (under `~/.claude/notify`)
  - `mark-unread.sh [<pane_ref>] [message]`: create unread flag file.
  - `mark-read.sh [<pane_ref>]`: remove unread flag file.
  - `from-hook.sh`: Claude Code notifications hook sink; reads JSON from stdin and calls `mark-unread.sh` (targets a single pane when `CLAUDE_PANE_TTY` is set).

## Finalize (one-time)

Run these locally (scripts aren’t executable yet):

```sh
chmod +x ~/.claude/notify/*.sh
tmux source-file ~/.config/tmux/tmux.conf
```

Optional: set Claude Code “Notifications Hook” command to:

```sh
bash ~/.claude/notify/from-hook.sh
```

## How It Works

- Unread state is stored as files: `~/.claude/notify/unread/<pane_id>`.
- The `tc` picker reads this state and displays 🔔 when a pane has unread.
- `from-hook.sh` marks unread on notifications; tmux focus hook clears unread on focus.

## Usage Cheatsheet

- Open picker: `Alt+c` (or run `tc`).
- Manually mark unread:
  - Current pane: `~/.claude/notify/mark-unread.sh` (inside tmux)
  - Specific: `~/.claude/notify/mark-unread.sh %12` or `... mark-unread.sh my:1.0` or `... mark-unread.sh /dev/ttys012`.
- Manually mark read: same forms with `mark-read.sh`.

## File Map (key parts)

- `tmux/tmux.conf`: removed bell settings; added focus hook; keybindings.
- `zsh/.zshrc`: hardened `tc()`; ANSI-safe parsing; single-result fast path.
- `claude/claude-utils.sh`: unread detection; `resolve_pane_id`; improved process checks.
- `claude/notify/mark-unread.sh`: create unread flags.
- `claude/notify/mark-read.sh`: clear unread flags.
- `claude/notify/from-hook.sh`: Claude Code notifications hook sink.

## Open Questions / TODO

- Claude model in `claude/settings.json` is set to `"opusplan"`. Verify the exact expected key/value for your client and update if needed.
- Branch name is `cluade` (typo) — consider renaming to `claude`.
- If Claude Code can expose a specific pane or TTY for the current session, we can refine `from-hook.sh` to target one pane deterministically (currently supports `CLAUDE_PANE_TTY`).
- Consider adding lightweight logging (e.g., `~/.claude/notify/log`) if you want an audit trail of notifications.

## Quick Validation

1) Open a Claude pane; run:

```sh
~/.claude/notify/mark-unread.sh
tc  # should show 🔔 for that pane
```

2) Focus that pane in tmux; the 🔔 should clear on the next `tc` invocation (hook marks read on focus).

3) If you configure the Claude Code hook, trigger a notification and confirm that panes show 🔔.

