# Shared AI agent shell helpers.

typeset -g AI_HARNESS_ROOT="${AI_HARNESS_ROOT:-$HOME/.config/ai-harness}"

# TMUX is unset so the binary's hardcoded chalk-level cap
# (`if (process.env.TMUX && level > 2) level = 2`) doesn't fire; this keeps
# truecolor bg rendering inside tmux. Tracking issue:
# https://github.com/anthropics/claude-code/issues/36785
claude() {
  local arg
  for arg in "$@"; do
    case "$arg" in
    --plugin-dir | --plugin-dir=* | --settings | --settings=* | plugin | plugins | mcp | doctor | help | --help | --version)
      env -u TMUX claude "$@"
      return
      ;;
    esac
  done
  env -u TMUX claude \
    --plugin-dir "$AI_HARNESS_ROOT" \
    --settings "$AI_HARNESS_ROOT/claude/settings.json" \
    "$@"
}

copilot() {
  local arg
  for arg in "$@"; do
    case "$arg" in
    --plugin-dir | --plugin-dir=* | plugin | plugins | help | --help | --version)
      command copilot "$@"
      return
      ;;
    esac
  done
  command copilot --plugin-dir "$AI_HARNESS_ROOT" "$@"
}

codex() {
  local first_arg="${1:-}"

  case "$first_arg" in
  agents | login | logout | mcp | plugin | mcp-server | app-server | remote-control | app | completion | update | doctor | sandbox | debug | apply | a | migrate-rollouts | cloud | exec-server | features | help | -h | --help | -V | --version)
    command codex "$@"
    ;;
  *)
    local arg
    for arg in "$@"; do
      case "$arg" in
      -c* | --config* | --enable* | --disable* | \
        --search* | --profile* | --no-daemon* | \
        -a | --ask-for-approval* | -s | --sandbox* | \
        --dangerously-bypass-approvals-and-sandbox* | --yolo*)
        print -u2 "codex: $arg is blocked here to keep this launch on the shared daemon; use managed config or --model instead"
        return 2
        ;;
      esac
    done
    command codex "$@"
    ;;
  esac
}
