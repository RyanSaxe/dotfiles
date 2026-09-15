# Check the environment

Check once at the first session in an environment, or when a capability fails.
Do not make setup a questionnaire or repeat it for each artifact.

## Required runtime

Run `node --version`. The helpers require Node 20 or newer and no installed npm
packages. If Node is missing or too old, offer installation help using the user's
existing version manager or an official installer appropriate to their OS.
Check current official instructions before installing. Explain the proposed
change and respect installation permissions; do not silently install a toolchain.

After Node is available, run:

```sh
node scripts/check.mjs
```

An optional positional path checks an alternative storage directory. Use that
same location for the session if default storage is unavailable. The check
creates and removes a temporary child directory, exercises file writes and
renames, and requests a local HTTP endpoint. It does not prove cross-platform
support, browser access, or the agent's ability to remain active while waiting.

Run `start` through a long-running tool process. If the environment cannot keep
the helper or agent wait alive, explain the limitation before promising live
feedback. Resume the explicit session on the next turn; a helper cannot wake
an ended agent turn.

## Browser and rendering

Use the browser tools already available in the agent environment. If none are
available, offer help setting up a suitable tool or ask the user to review the
page manually. Planning does not require installing a particular browser tool.
State when you have not verified the rendered UI.

The shared frame loads pinned code, math, diagram, and chart libraries on demand
from CDNs. Check needed renderers in the actual browser, not just by testing
network access from the terminal. A blocked CDN leaves source content available.
If that fallback cannot communicate a choice adequately, use self-contained
HTML/SVG or discuss the missing capability before proceeding.

Target modern desktop browsers on macOS, Windows, and Linux. Detect capabilities
rather than browser names. Mobile and remote access are outside this local
workflow. Report the actual OS/browser combinations verified.

Notifications enable automatically when browser permission is already granted,
unless explicitly disabled in Settings. First-time permission requires the user
to click Enable notifications. Enabling applies only to later events, not the
current review or a backlog. Focus and viewing do not suppress notifications;
repeated polling does not repeat an alert.

Keep the tab and helper open; browser polling can be delayed. New localhost ports
may require permission again. Browser or OS settings can still suppress delivery.
Verify actual notification delivery when possible and report gaps. Notifications
do not wake an ended agent turn or change the waiting protocol.

## Authoring checks

Use the project's available HTML/CSS/JS formatter and JavaScript linter on the
source files, including custom interactions. Offer setup help when those tools
are absent; do not add project dependencies merely to format temporary plans.
The shared sources are formatted with Prettier and their JavaScript is linted
with Oxlint in the development repository. Generated HTML still needs browser
review. Formatting is not HTML validation, accessibility testing, or proof that
an interaction works.
