# Shared AI agent shell helpers.

codex() {
  local first_arg="${1:-}"
  local notify_config='notify=["bash","-c","AI_AGENT_SOURCE=codex exec bash \"$HOME/.codex/hooks/notify.sh\" \"$1\"","ai-harness-codex-notify"]'
  local status_line_config='tui.status_line=["project-name","git-branch","model-with-reasoning","context-remaining","used-tokens","five-hour-limit","weekly-limit","task-progress"]'
  local status_line_color_config='tui.status_line_use_colors=true'

  case "$first_arg" in
    features | login | logout | update | completion | help | -h | --help | -V | --version)
      command codex "$@"
      ;;
    *)
      command codex \
        -c "$notify_config" \
        -c "$status_line_config" \
        -c "$status_line_color_config" \
        "$@"
      ;;
  esac
}
