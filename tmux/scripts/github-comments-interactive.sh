#!/usr/bin/env bash
set -euo pipefail

# Interactive script for the code-review tmux pane
# Displays GitHub comment thread count and launches Neovim picker on Enter
#
# This script runs in the foreground in the code-review session.
# The actual GitHub checking is done by github-comments-daemon.sh which
# writes the count to ~/.cache/github-comments-count
#
# Bell behavior: A background watcher process monitors the timestamp file
# and rings the bell when it changes AND count > 0. This works even when
# Neovim is open in the foreground because the watcher runs independently.
#
# Usage: Run this script in a tmux pane (typically auto-started by tmux.conf)

# Cache files written by the daemon
CACHE_FILE="$HOME/.cache/github-comments-count"
TIMESTAMP_FILE="$HOME/.cache/github-comments-timestamp"

# Colors for terminal output (TokyoNight-inspired)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
DIM='\033[0;90m'
RESET='\033[0m'

# Function to get current count from cache
get_count() {
  if [[ -f "$CACHE_FILE" ]]; then
    cat "$CACHE_FILE" 2> /dev/null || echo "0"
  else
    echo "0"
  fi
}

# Function to get timestamp of last daemon check
get_timestamp() {
  if [[ -f "$TIMESTAMP_FILE" ]]; then
    cat "$TIMESTAMP_FILE" 2> /dev/null || echo ""
  else
    echo ""
  fi
}

# Function to ring bell (triggers tmux bell detection)
ring_bell() {
  printf '\007'
}

# Background bell watcher - runs independently of main loop
# Monitors timestamp file and rings bell when it changes AND count > 0
# This allows bells to ring even when Neovim is open in the foreground
start_bell_watcher() {
  (
    local last_ts=""
    while true; do
      sleep 5 # Check every 5 seconds

      local current_ts
      current_ts=$(get_timestamp)
      local current_count
      current_count=$(get_count)

      # Ring bell if timestamp changed and count > 0
      if [[ -n "$current_ts" ]] && [[ "$current_ts" != "$last_ts" ]]; then
        if [[ "$current_count" =~ ^[0-9]+$ ]] && [[ "$current_count" -gt 0 ]]; then
          ring_bell
        fi
        last_ts="$current_ts"
      fi
    done
  ) &
  BELL_WATCHER_PID=$!
}

# Cleanup function to kill background watcher
cleanup() {
  if [[ -n "${BELL_WATCHER_PID:-}" ]]; then
    kill "$BELL_WATCHER_PID" 2> /dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# Start the background bell watcher
start_bell_watcher

# Function to display current status
show_status() {
  clear

  echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${DIM}  GitHub Code Review${RESET}"
  echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""

  # Read count from cache file
  local count
  count=$(get_count)

  # Display status based on count
  if [[ "$count" == "?" ]] || [[ "$count" == "0" ]]; then
    if [[ ! -f "$CACHE_FILE" ]]; then
      echo -e "  ${YELLOW}⏳ Waiting for first check...${RESET}"
      echo -e "  ${DIM}(daemon checks every 15 minutes)${RESET}"
    else
      echo -e "  ${GREEN}✅ No GitHub threads need attention${RESET}"
    fi
  elif [[ "$count" -gt 0 ]] 2> /dev/null; then
    echo -e "  ${RED}📬 $count GitHub thread(s) need attention${RESET}"
  fi

  echo ""
  echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
  echo -e "  Press ${YELLOW}Enter${RESET} to open GitHub Comments picker"
  echo -e "  Press ${YELLOW}r${RESET} to refresh status"
  echo -e "  Press ${YELLOW}q${RESET} to quit"
  echo ""
}

# Main loop
while :; do
  show_status

  # Read single character with timeout (refresh display every 30 seconds)
  if read -rsn1 -t 30 key; then
    case "$key" in
      "") # Enter key
        # Open Neovim with the GitHub Comments picker
        nvim -c "lua require('custom.git.review_threads').picker()"
        ;;
      "r" | "R")
        # Refresh - just loop again to redisplay
        continue
        ;;
      "q" | "Q")
        # Kill the entire session so it can be auto-recreated on next tmux reload
        # This is better than leaving an empty shell in the session
        echo "Killing code-review session..."
        tmux kill-session -t code-review
        exit 0
        ;;
      *)
        # Any other key - ignore and refresh
        continue
        ;;
    esac
  fi
  # Timeout reached - just refresh the display
done
