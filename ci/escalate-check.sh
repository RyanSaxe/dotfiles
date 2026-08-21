#!/bin/sh
# The idle_prompt escalation hook must flip working→waiting and nothing
# else. Runs the real script against stub tmux/workmux binaries so no
# tmux server or state dir is involved.
set -eu

script="$(dirname "$0")/../workmux/dot-local/bin/workmux-escalate-idle"
stubs="$(mktemp -d)"
trap 'rm -rf "$stubs"' EXIT

# tmux stub answers show-options with the canned status format; workmux
# stub records what it was asked to do.
cat >"$stubs/tmux" <<'EOF'
#!/bin/sh
printf '%s' "$STUB_STATUS_OPTION"
EOF
cat >"$stubs/workmux" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$STUB_CALLS"
EOF
chmod +x "$stubs/tmux" "$stubs/workmux"

check() {
  : >"$stubs/calls"
  # zsh -f: zshenv rebuilds PATH and would shadow the stubs.
  STUB_STATUS_OPTION="$1" STUB_CALLS="$stubs/calls" \
    PATH="$stubs:$PATH" TMUX_PANE=%1 zsh -f "$script"
  actual="$(cat "$stubs/calls")"
  if [ "$actual" != "$2" ]; then
    echo "escalate-check: status option '$1': expected '$2', got '$actual'" >&2
    exit 1
  fi
}

check '#[fg=#{@status_working}]●#[fg=default]' 'set-window-status waiting'
check '#[fg=#{@status_waiting}]●#[fg=default]' ''
check '#[fg=#{@status_done}]✓#[fg=default]' ''
check '' ''

echo "escalate hook ok"
