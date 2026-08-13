# Auto-activate and auto-deactivate Python virtualenvs.
# Walks up from $PWD to the nearest .venv, stopping at the repo boundary.
# No caching: the walk is a few stat calls and a stale cache was the v1 bug.

_venv_find() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.venv" ]]; then
      print -r -- "$dir/.venv"
      return
    fi
    # Stop at the repo root; a venv above it belongs to someone else.
    [[ -e "$dir/.git" ]] && return
    dir="${dir:h}"
  done
}

_auto_venv() {
  local venv
  venv="$(_venv_find)"
  if [[ -n "$venv" ]]; then
    # Re-source when switching projects, and also when the venv was inherited
    # through `exec zsh` (VIRTUAL_ENV survives but the deactivate fn does not).
    if [[ "$VIRTUAL_ENV" != "$venv" ]] || ! whence -w deactivate > /dev/null; then
      source "$venv/bin/activate"
      typeset -g _VENV_AUTO_ACTIVATED=1
    fi
  elif [[ -n "$VIRTUAL_ENV" && -n "$_VENV_AUTO_ACTIVATED" ]]; then
    # We activated it, so leaving the project deactivates it. Manually
    # activated venvs are left alone.
    whence -w deactivate > /dev/null && deactivate
    typeset -g _VENV_AUTO_ACTIVATED=
  fi
}

venv_init() {
  # Venv state is derived from location, never inherited. A new shell can
  # be born with another project's .venv/bin on PATH — tmux captures the
  # spawning shell's env at window creation, even with VIRTUAL_ENV unset —
  # and there is no deactivate to undo it. Scrub every trace, then let the
  # walk re-activate whatever actually belongs to this directory.
  path=("${(@)path:#*/.venv/bin}")
  [[ -n "$VIRTUAL_ENV" ]] && path=("${(@)path:#$VIRTUAL_ENV/bin}")
  unset VIRTUAL_ENV VIRTUAL_ENV_PROMPT
  autoload -U add-zsh-hook
  add-zsh-hook chpwd _auto_venv
  _auto_venv
}
