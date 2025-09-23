# Git repository management and project navigation functions
# Functions for fuzzy finding and switching to git repositories

# Cache the CSV output of a function in ~/.cache/custom_scripts/<func>.csv
# Usage:
#   cache_csv [-f|--force] <function_name> [--] [args...]
# - The target function must print CSV to stdout.
# - If --force/-f is given, the function is re-run and the cache is overwritten.
# - Otherwise, the function only runs if the cache file doesn't exist (or is empty).
# - Returns (prints) the absolute path to the cached CSV file.
cache_csv() {
  emulate -L zsh -o pipefail

  # Parse flags
  local force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--force) force=1; shift ;;
      --) shift; break ;;
      -*) print -u2 "cache_csv: unknown flag: $1"; return 2 ;;
      *) break ;;
    esac
  done

  # Require the function name
  local fn="${1:-}"
  if [[ -z "$fn" ]]; then
    print -u2 "cache_csv: missing <function_name>"
    return 2
  fi
  shift

  # Validate function exists
  if ! typeset -f -- "$fn" >/dev/null; then
    print -u2 "cache_csv: '$fn' is not a defined function"
    return 2
  fi

  # Cache path
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/custom_scripts"
  local outfile="${cache_dir}/${fn}.csv"

  # Ensure directory exists
  mkdir -p "$cache_dir" || {
    print -u2 "cache_csv: failed to create cache dir: $cache_dir"
    return 1
  }

  # Decide whether to (re)generate
  if (( force )) || [[ ! -s "$outfile" ]]; then
    # Write atomically via temp file
    local tmp
    tmp="$(mktemp "${outfile}.XXXXXX")" || {
      print -u2 "cache_csv: failed to create temp file"
      return 1
    }

    # Call the function (with any extra args) and capture CSV
    if "$fn" "$@" >| "$tmp"; then
      mv -f -- "$tmp" "$outfile" || {
        print -u2 "cache_csv: failed to move temp file into place"
        rm -f -- "$tmp"
        return 1
      }
    else
      local rc=$?
      rm -f -- "$tmp"
      print -u2 "cache_csv: function '$fn' failed with exit code $rc"
      return $rc
    fi
  fi

  # Return the cached path
  print -r -- "$outfile"
}

# Internal function to generate repository data
# Finds all git repos and returns CSV data with last commit dates
_to() {
  # Directories to search
  search_dirs=("$HOME/work" "$HOME/Work" "$HOME/projects" "$HOME/Projects" "$HOME/generic")

  # Date formatting for Linux/macOS compatibility
  if date -d @0 "+%Y" >/dev/null 2>&1; then
    date_cmd() { date -d "@$1" "+%Y-%m-%d %H:%M"; }
  else
    date_cmd() { date -r "$1" "+%Y-%m-%d %H:%M"; }
  fi

  # Find all git repos using fd (fast directory search)
  repos=()
  for dir in "${search_dirs[@]}"; do
    [[ -d "$dir" ]] && repos+=($(fd .git -t d -H "$dir"))
  done

  repo_roots=($(printf "%s\n" "${repos[@]}" | sed 's|/\.git||' | sort -u))

  # Build table: repo_name,repo_path,date
  repo_table=()
  for repo in "${repo_roots[@]}"; do
    if [[ -d "$repo/.git" ]]; then
      last_commit=$(git -C "$repo" log -1 --format="%ct" 2>/dev/null)
      last_commit=${last_commit:-0}
      date_str=$(date_cmd "$last_commit")
      repo_name=$(basename "$repo")
      repo_table+=("${repo_name},${repo},${date_str}")
    fi
  done

  printf "%s\n" "${repo_table[@]}"
}

# Fuzzy find and cd into git repositories sorted by last commit date, then open tmux session
# INTERFACE: to [same exact arguments as 'tm']
to() {
  emulate -L zsh
  set -o pipefail

  local -a args=()
  local force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--force) force=1; shift ;;
      *) args+=("$1"); shift ;;
    esac
  done

  # Build cache file (with or without force)
  local cache_file
  if (( force )); then
    cache_file=$(cache_csv -f _to)
  else
    cache_file=$(cache_csv _to)
  fi

  # Use fzf to select repository
  local selected
  selected=$(
    sort -t, -k3,3r -- "$cache_file" \
    | column -t -s, \
    | fzf --prompt="Select repo: "
  )

  [[ -z "$selected" ]] && return 0

  # Extract repo path (2nd visible column after `column -t`)
  local repo
  repo=$(awk -v FS='[[:space:]]+' '{print $2}' <<<"$selected")
  [[ -z "$repo" ]] && return 0

  # Create tmux session in selected repository
  tm -n "$repo" "${args[@]}"
}
