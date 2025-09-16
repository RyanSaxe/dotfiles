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
transcript_path=$(echo "$input" | jq -r '.transcript_path // ""')

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

# Extract context length from most recent transcript entry (matches ccstatusline approach)
# This correctly handles /clear and /compress commands by using the latest usage data
token_info=""
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
  context_tokens=0

  # Read transcript in reverse to find most recent assistant message with usage data
  # Using tac for reverse reading, falling back to tail -r on macOS if needed
  if command -v tac >/dev/null 2>&1; then
    reverse_cmd="tac"
  else
    reverse_cmd="tail -r"
  fi

  # Find the most recent assistant message with usage data (not sidechain)
  while IFS= read -r line; do
    if [[ -n "$line" ]] && echo "$line" | jq -e . >/dev/null 2>&1; then
      # Check if this is an assistant message with usage data and not a sidechain
      is_assistant=$(echo "$line" | jq -r '.type // ""')
      is_sidechain=$(echo "$line" | jq -r '.isSidechain // false')
      has_usage=$(echo "$line" | jq -e '.message.usage' >/dev/null 2>&1 && echo "true" || echo "false")

      if [[ "$is_assistant" == "assistant" && "$is_sidechain" == "false" && "$has_usage" == "true" ]]; then
        # Extract all token types from the most recent main chain assistant message
        input_tokens=$(echo "$line" | jq -r '.message.usage.input_tokens // 0')
        output_tokens=$(echo "$line" | jq -r '.message.usage.output_tokens // 0')
        cache_read_tokens=$(echo "$line" | jq -r '.message.usage.cache_read_input_tokens // 0')
        cache_creation_tokens=$(echo "$line" | jq -r '.message.usage.cache_creation_input_tokens // 0')

        # Context length = input + cache tokens (these count toward the 200k limit)
        context_tokens=$((input_tokens + cache_read_tokens + cache_creation_tokens))

        # Total tokens for potential future use (all token types)
        total_tokens=$((input_tokens + output_tokens + cache_read_tokens + cache_creation_tokens))

        # Found what we need, stop processing
        break
      fi
    fi
  done < <($reverse_cmd "$transcript_path" 2>/dev/null)

  # Display context info if we have data
  if [[ $context_tokens -gt 0 ]]; then
    percentage=$((context_tokens * 100 / 200000))

    # Format context tokens for display (k for thousands, M for millions)
    if [[ $context_tokens -ge 1000000 ]]; then
      token_display="$(echo "scale=1; $context_tokens / 1000000" | bc -l)M"
    elif [[ $context_tokens -ge 1000 ]]; then
      token_display="$(echo "scale=1; $context_tokens / 1000" | bc -l)k"
    else
      token_display="$context_tokens"
    fi

    # Choose color based on percentage of 200k limit
    if [[ $percentage -lt 33 ]]; then
      percent_color="$C_GREEN"
    elif [[ $percentage -lt 66 ]]; then
      percent_color="$C_YELLOW"
    else
      percent_color="$C_RED"
    fi

    token_info=" ${C_DIM}[${RESET}${C_DIM}${token_display}/200k${RESET} ${percent_color}(${percentage}%)${RESET}${C_DIM}]${RESET}"
  fi
fi

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

# Token usage info
status_line+="${token_info}"

# Output simple left-aligned status line
printf "%b\n" "$status_line"
