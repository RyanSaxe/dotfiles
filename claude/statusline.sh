#!/usr/bin/env bash

# Claude Code Status Line Script
# Matches the fino-time-custom zsh theme style with TokyoNight colors

# Read JSON input from stdin
input=$(cat)

# TokyoNight colors (dimmed for status line)
C_CYAN='\033[38;2;125;207;255m'    # #7dcfff
C_MAGENTA='\033[38;2;187;154;247m' # #bb9af7
C_GREEN='\033[38;2;158;206;106m'   # #9ece6a
C_RED='\033[38;2;247;118;142m'     # #f7768e
C_DIM='\033[38;2;86;95;137m'       # #565f89
C_YELLOW='\033[38;2;255;158;100m'  # #ff9e64
RESET='\033[0m'

# Extract data from JSON
model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"')
output_style=$(echo "$input" | jq -r '.output_style.name // "default"')
current_dir=$(echo "$input" | jq -r '.workspace.current_dir // ""')

# Get basename of current directory for display
if [[ -n "$current_dir" ]]; then
  dir_name=$(basename "$current_dir")
else
  dir_name="~"
fi

# Check for virtual environment
venv_info=""
if [[ -n "$VIRTUAL_ENV" ]]; then
  base="${VIRTUAL_ENV##*/}"
  if [[ "$base" == ".venv" || "$base" == "venv" ]]; then
    # Use parent directory name for generic venv names
    venv_info="($(basename "$(dirname "$VIRTUAL_ENV")"))"
  else
    venv_info="($base)"
  fi
elif [[ -n "$CONDA_DEFAULT_ENV" ]]; then
  venv_info="($CONDA_DEFAULT_ENV)"
fi

# Git status (simplified, avoiding locks)
git_info=""
if [[ -d "$current_dir/.git" ]] || git -C "$current_dir" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$current_dir" branch --show-current 2>/dev/null || echo "detached")
  if [[ -n "$branch" ]]; then
    # Check if working directory is clean (simplified)
    if git -C "$current_dir" diff-index --quiet HEAD -- 2>/dev/null; then
      git_status="✔"
      status_color="$C_GREEN"
    else
      git_status="✘"
      status_color="$C_RED"
    fi
    git_info=" ${C_DIM}on${RESET} ${C_MAGENTA}${branch}${RESET} ${status_color}${git_status}${RESET}"
  fi
fi

# Get current time
current_time=$(date '+%H:%M:%S')

# Build status line
status_line="${C_DIM}in ${RESET}"

# Directory (cyan like your theme)
status_line+="${C_CYAN}${dir_name}${RESET}"

# Git info if available
status_line+="${git_info}"

# Model and output style
status_line+=" ${C_DIM}with${RESET} ${C_YELLOW}${model_name}${RESET}"
if [[ "$output_style" != "default" ]]; then
  status_line+=" ${C_DIM}(${output_style})${RESET}"
fi


# # Virtual environment if available
# if [[ -n "$venv_info" ]]; then
#   status_line+=" ${C_DIM}${venv_info}${RESET} "
# fi

# Output simple left-aligned status line
printf "%b\n" "$status_line"
