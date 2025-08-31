# --- TokyoNight night palette (truecolor)
# Night: https://github.com/folke/tokyonight.nvim (approx)
C_FG='%{%F{#c0caf5}%}'
C_DIM='%{%F{#565f89}%}'
C_BLUE='%{%F{#7aa2f7}%}'
C_MAGENTA='%{%F{#bb9af7}%}'
C_CYAN='%{%F{#7dcfff}%}'
C_GREEN='%{%F{#9ece6a}%}'
C_YELLOW='%{%F{#ff9e64}%}' # this is actually orange, but its what I use in my syntax highlighting
C_RED='%{%F{#f7768e}%}'
RESET='%{%f%}'   # reset fg

function box_name {
  local box="${SHORT_HOST:-$HOST}"
  [[ -f ~/.box-name ]] && box="$(< ~/.box-name)"
  echo "${box:gs/%/%%}"
}

get_virtualenv_name() {
  local maxlen=${1:-0}
  local env=""

  if [[ -n "$CONDA_DEFAULT_ENV" ]]; then
    env="$CONDA_DEFAULT_ENV"
  elif [[ -n "$VIRTUAL_ENV" ]]; then
    local base="${VIRTUAL_ENV:t}"
    if [[ "$base" == ".venv" || "$base" == "venv" ]]; then
      env="${VIRTUAL_ENV:h:t}"
    else
      env="$base"
    fi
  fi

  # No limit or already short enough
  if (( maxlen <= 0 || ${#env} <= maxlen )); then
    echo "$env"
    return
  fi

  # Truncate
  if (( maxlen <= 3 )); then
    echo "${env:0:$maxlen}"
  else
    echo "${env:0:$((maxlen-3))}..."
  fi
}

# Formats the env name for the prompt, or a fallback if empty
virtualenv_info() {
  local env_name
  env_name="$(get_virtualenv_name "$1")"
  if [[ -n "$env_name" ]]; then
    echo "${C_DIM}(${env_name})${RESET}"
  else
    echo "○"
  fi
}

# taken from avit theme: https://github.com/0xTim/oh-my-zsh/blob/master/themes/avit.zsh-theme#L49C1-L78C1
# Determine the time since last commit. If branch is clean,
# use a neutral color, otherwise colors will vary according to time.
function _git_time_since_commit() {
  local commit_age=""
# Only proceed if there is actually a commit.
  if last_commit=$(git log --pretty=format:'%at' -1 2> /dev/null); then
    now=$(date +%s)
    seconds_since_last_commit=$((now-last_commit))

    # Totals
    minutes=$((seconds_since_last_commit / 60))
    hours=$((seconds_since_last_commit/3600))

    # Sub-hours and sub-minutes
    days=$((seconds_since_last_commit / 86400))
    sub_hours=$((hours % 24))
    sub_minutes=$((minutes % 60))

    if [ $hours -ge 24 ]; then
      commit_age="${days}d"
    elif [ $minutes -gt 60 ]; then
      commit_age="${sub_hours}h${sub_minutes}m"
    else
      commit_age="${minutes}m"
    fi

    echo "HEAD = $commit_age ago"
  fi
}

function strip_ansi() {
  # Remove ANSI escape codes from a string
  echo "$1" | sed -E 's/\x1B\[[0-9;]*[mK]//g'
}

function get_prefix() {
  # Get the prefix (user@host in cwd) if in a wide enough terminal
  local prefix
  if (( COLUMNS > 120 )); then
    prefix="${C_DIM}╭─%n${RESET} ${C_DIM}at${RESET} ${C_DIM}\$(box_name)${RESET} ${C_DIM}in ${RESET}"
  else
    prefix="${C_DIM}╭─${RESET}"
  fi
  print -P "$prefix"
}

function get_prefix_size() {
  # Get the size of the prefix (user@host in cwd)
  local prefix="$(get_prefix)"
  local expanded=$(print -P "$prefix")
  local clean=$(strip_ansi "$expanded")
  echo "${#clean}"
}

function prompt_padding() {
  if COLUMNS=$(tput cols) && (( COLUMNS < 80 )); then
    # If terminal is too narrow, no padding needed
    print -r -- "─"
    return
  fi
  local first_len=$(get_prefix_size)
  local venv_info=$(get_virtualenv_name first_len)
  if [[ -n "$venv_info" ]]; then
    venv_info="(${venv_info})"
  else
    venv_info="○"
  fi
  local venv_clean=$(strip_ansi "$venv_info")
  local venv_len=${#venv_info}

  # Calculate padding length that encorporates parens
  local pad=$(( first_len - venv_len - 2))

  if (( pad <= 0 )); then
    print -r -- "─"
    return
  fi

  local padding
  padding=${(l:$pad::─:)}   # zsh left-pad trick: empty string to width = pad using '─'
  print -r -- "$padding"
}

# --- Git prompt colors re-mapped to TokyoNight
ZSH_THEME_GIT_PROMPT_PREFIX=" ${C_DIM}on${RESET} ${C_MAGENTA}"
ZSH_THEME_GIT_PROMPT_SUFFIX=" ${RESET}"
ZSH_THEME_GIT_PROMPT_DIRTY=" ${C_RED}✘${RESET}"
ZSH_THEME_GIT_PROMPT_CLEAN=" ${C_GREEN}✔${RESET}"

PROMPT="\$(get_prefix)${C_CYAN}%~${RESET}\$(git_prompt_info)\$(if (( COLUMNS >= 80 )); then echo \"${C_DIM}\$(_git_time_since_commit)${RESET}\"; fi)
${C_DIM}╰\$(prompt_padding)\$(virtualenv_info) "

# Right-aligned time in dim color (only on wide screens)
RPROMPT="\$(if (( COLUMNS >= 80 )); then echo \"${C_DIM}%*${RESET}\"; fi)"

# Ensure prompt substitutions work (Oh My Zsh usually sets this, but just in case)
setopt prompt_subst

