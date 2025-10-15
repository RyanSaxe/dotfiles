# Virtual environment auto-activation functions
# Automatically activates .venv by walking up to the nearest git root

# Cache for directory -> venv path mapping (performance optimization)
typeset -gA _VENV_CACHE  # dir -> venv path (or empty)

# Auto-activate virtual environments based on directory
_auto_activate_venv() {
  local start="$PWD" dir="$PWD" venv=""
  # Cache hit?
  if [[ -n "${_VENV_CACHE[$start]-}" ]]; then
    venv="${_VENV_CACHE[$start]}"
  else
    # Walk up until we hit a git boundary ('.git') or the filesystem root.
    while [[ "$dir" != "/" ]]; do
      [[ -d "$dir/.venv" ]] && { venv="$dir/.venv"; break; }
      # Stop scanning above the repo root
      [[ -e "$dir/.git" ]] && break
      dir="${dir:h}"
    done
    _VENV_CACHE[$start]="$venv"
  fi

  if [[ -n "$venv" ]]; then
    # Only source if it's a different venv than the active one
    if [[ "$VIRTUAL_ENV" != "$venv" ]]; then
      source "$venv/bin/activate"
    fi
  fi
}

# Initialize virtual environment auto-activation
venv_init() {
  autoload -U add-zsh-hook
  add-zsh-hook chpwd _auto_activate_venv
  _auto_activate_venv
}