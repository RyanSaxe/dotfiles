# Codex's managed hooks, by their path under /etc/codex. Codex trusts the
# hooks in requirements.toml without a review in /hooks. The hook script
# stays in the checkout, so an edit applies without a switch.
repo: {
  "requirements.toml" = ../ai-harness/codex/requirements.toml;
  "hooks/notify-pushover.zsh" = "${repo}/ai-harness/tools/notify-pushover.zsh";
}
