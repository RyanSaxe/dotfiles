# By hand

One-time steps that switches cannot automate. Run these once per machine after
[Setup](setup.md).

## Chrome, on a Mac

1. Load the theme: open `chrome://extensions`, enable Developer mode, click
   **Load unpacked**, and select `~/.config/theme/chrome` (`Cmd-Shift-G` lets
   you type the path).
2. Open `chrome://settings/onStartup` and choose **Continue where you left
   off**. Chrome loads themes only at startup, so `theme` restarts Chrome on
   light/dark switches; this setting restores your windows and tabs.

## The agents

Sign each agent into its account:

| Agent           | Sign in with          | Scope      |
| --------------- | --------------------- | ---------- |
| Codex           | `codex login`         | every host |
| Copilot CLI     | `copilot login`       | every host |
| Claude Code     | `/login` in `claude`  | `personal` |
| pi              | `/login` in `pi`      | `personal` |
| Antigravity CLI | `/login` in `agy`     | `personal` |

Restart any `pi` session running during the first `home-switch` so it loads
`pair`'s extension.
