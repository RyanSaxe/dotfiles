# Shared AI agent shell helpers.

codex() {
  local first_arg="${1:-}"
  local notify_config='notify=["bash","-c","AI_AGENT_SOURCE=codex exec bash \"$HOME/.codex/hooks/notify.sh\" \"$1\"","ai-harness-codex-notify"]'
  local shell_env_config="shell_environment_policy.set={ UV_CACHE_DIR = \"$HOME/.cache/uv\", UV_TOOL_BIN_DIR = \"$HOME/.local/bin\", UV_TOOL_DIR = \"$HOME/.local/share/uv/tools\", UV_PYTHON_INSTALL_DIR = \"$HOME/.local/share/uv/python\", UV_SYSTEM_CERTS = \"true\" }"
  local status_line_config='tui.status_line=["project-name","git-branch","model-with-reasoning","context-remaining","used-tokens","five-hour-limit","weekly-limit","task-progress"]'
  local status_line_color_config='tui.status_line_use_colors=true'
  local profile_args=(--profile dotfiles)
  local arg

  for arg in "$@"; do
    case "$arg" in
      --profile | -p | --profile=*)
        profile_args=()
        break
        ;;
    esac
  done

  case "$first_arg" in
    features | login | logout | update | completion | help | -h | --help | -V | --version)
      command codex "$@"
      ;;
    *)
      command codex \
        "${profile_args[@]}" \
        -c "$notify_config" \
        -c "$shell_env_config" \
        -c "$status_line_config" \
        -c "$status_line_color_config" \
        "$@"
      ;;
  esac
}
