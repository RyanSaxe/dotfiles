# Shared AI agent shell helpers.

codex() {
  local first_arg="${1:-}"
  local notify_config='notify=["bash","-c","AI_AGENT_SOURCE=codex exec bash \"$HOME/.codex/hooks/notify.sh\" \"$1\"","ai-harness-codex-notify"]'

  case "$first_arg" in
    features | login | logout | update | completion | help | -h | --help | -V | --version)
      command codex "$@"
      ;;
    *)
      command codex --enable codex_hooks -c "$notify_config" "$@"
      ;;
  esac
}
