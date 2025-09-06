#!/usr/bin/env bash

# Claude Code Utility Functions
# Provides detection and management of Claude instances in tmux

# Function to check if a tmux pane is running Claude
# Usage: is_claude_pane "/dev/ttys014"
is_claude_pane() {
    local tty="$1"
    # Check for claude process on the specified TTY (headerless output)
    ps -t "$(basename "$tty")" -o comm= 2>/dev/null | grep -qx 'claude'
}

# Function to get all Claude panes with details
# Returns: location|tty|title|bell_flag|pane_id
get_claude_panes() {
    tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}|#{pane_tty}|#{pane_title}|#{window_bell_flag}|#{pane_id}' | \
    while IFS='|' read -r location tty title bell pane_id; do
        if is_claude_pane "$tty"; then
            echo "${location}|${tty}|${title}|${bell}|${pane_id}"
        fi
    done
}

# Note: File-based unread tracking removed - using tmux bells only

# Function to format Claude pane for fzf display
# Usage: format_claude_pane "session:window.pane" "title" "bell_flag" [pane_id]
format_claude_pane() {
    local location="$1"
    local title="$2"
    local bell="$3"
    local pane_id="$4"

    local status_icon
    local status_color

    if [[ "$bell" == "1" ]]; then
        # Needs attention (orange) - tmux bell detected
        status_icon="🔔"
        status_color="\033[38;2;255;158;100m"  # TokyoNight orange
    else
        # Running normally (green)
        status_icon="✓ "
        status_color="\033[38;2;158;206;106m"  # TokyoNight green
    fi

    local reset="\033[0m"
    local dim="\033[38;2;86;95;137m"      # TokyoNight dim

    # Format: [colored icon] session:window.pane - title
    printf "%b%s%b %-20s %b%s%b\n" "$status_color" "$status_icon" "$reset" "$location" "$dim" "$title" "$reset"
}

# Function to count Claude instances by status
count_claude_instances() {
    local total=0
    local attention=0
    
    while IFS='|' read -r location tty title bell pane_id; do
        ((total++))
        if [[ "$bell" == "1" ]]; then
            ((attention++))
        fi
    done < <(get_claude_panes)
    
    echo "Total: $total, Needing attention: $attention"
}

# Function to switch to a specific Claude pane
# Usage: switch_to_claude_pane "session:window.pane"
switch_to_claude_pane() {
    local target_location="$1"
    
    if [[ -z "$target_location" ]]; then
        echo "Error: No target location provided"
        return 1
    fi
    
    # Parse session and window.pane
    local session="${target_location%%:*}"
    local window_pane="${target_location#*:}"
    local window="${window_pane%%.*}"
    local pane="${window_pane#*.}"
    
    # Switch to the target
    if tmux switch-client -t "$session" 2>/dev/null || tmux attach-session -t "$session"; then
        tmux select-window -t "$session:$window"
        tmux select-pane -t "$session:$window.$pane"
        return 0
    else
        echo "Error: Could not switch to $target_location"
        return 1
    fi
}

# Resolve various identifiers to a tmux pane_id (e.g., %12)
# Accepts: pane_id (e.g., %12), session:win.pane, or /dev/tty*
# If empty and inside tmux, uses current pane
resolve_pane_id() {
    local input="$1"

    if [[ -z "$input" && -n "$TMUX" ]]; then
        tmux display -p '#{pane_id}'
        return
    fi

    # Already a pane id
    if [[ "$input" == %* ]]; then
        tmux list-panes -a -F '#{pane_id}' | grep -qx "$input" && { echo "$input"; return; }
        return 1
    fi

    # session:window.pane form
    if [[ "$input" == *:*.* ]]; then
        tmux display -p -t "$input" '#{pane_id}' 2>/dev/null && return 0
        return 1
    fi

    # TTY form
    if [[ "$input" == /dev/* ]]; then
        tmux list-panes -a -F '#{pane_tty} #{pane_id}' \
          | awk -v tty="$input" '$1==tty {print $2; found=1} END{exit !found}'
        return $?
    fi

    return 1
}
