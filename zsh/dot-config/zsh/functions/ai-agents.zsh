# Shared AI agent shell helpers.

typeset -g AI_HARNESS_ROOT="${AI_HARNESS_ROOT:-$HOME/.config/ai-harness}"

claude() {
  local arg
  for arg in "$@"; do
    case "$arg" in
    --plugin-dir | --plugin-dir=* | --settings | --settings=* | plugin | plugins | mcp | doctor | help | --help | --version)
      command claude "$@"
      return
      ;;
    esac
  done
  command claude \
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
  local shell_env_config="shell_environment_policy.set={ UV_CACHE_DIR = \"$HOME/.cache/uv\", UV_TOOL_BIN_DIR = \"$HOME/.local/bin\", UV_TOOL_DIR = \"$HOME/.local/share/uv/tools\", UV_PYTHON_INSTALL_DIR = \"$HOME/.local/share/uv/python\", UV_SYSTEM_CERTS = \"true\" }"
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
      -c "$shell_env_config" \
      "$@"
    ;;
  esac
}
