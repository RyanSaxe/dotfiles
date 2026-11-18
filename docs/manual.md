# By hand

The switches set up almost everything. These steps they can't do, so each
computer needs them once, after [setup](setup.md).

## Chrome, on a Mac

1. Load the theme. In `chrome://extensions`, turn on Developer mode, click
   Load unpacked and choose `~/.config/theme/chrome`. In the file picker,
   Cmd-Shift-G lets you type the path.
2. In `chrome://settings/onStartup`, choose "Continue where you left off".
   Chrome reads its theme only when it starts, so `theme` quits Chrome and
   opens it again whenever the mode changes between light and dark. With
   this setting Chrome reopens your windows and tabs.

## The agents

Sign each agent in to its account:

| Agent       | Sign in with                    |
| ----------- | ------------------------------- |
| Claude Code | `/login` inside `claude`        |
| Codex       | `codex login`                   |
| pi          | `/login` inside `pi`            |
| Copilot CLI | `copilot login`                 |

Claude Code is only on computers that use Claude, and pi and Copilot CLI
only on computers with the `personal` role. Restart any pi that was running
during the first home switch, so it loads pair's extension.
