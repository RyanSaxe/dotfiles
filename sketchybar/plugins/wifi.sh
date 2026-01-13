#!/usr/bin/env zsh
# WiFi status plugin - uses ipconfig getsummary for reliable SSID detection
# The ipconfig method works without requiring location permissions on macOS Sonoma+
# See: https://github.com/FelixKratz/SketchyBar/issues/407

source "$HOME/.config/sketchybar/colors.sh"

# Get ipconfig summary - if WiFi is off, this returns minimal/no data
IPCONFIG_OUTPUT=$(/usr/sbin/ipconfig getsummary en0 2>&1)

# Get SSID from the output
SSID=$(echo "$IPCONFIG_OUTPUT" | awk -F' : ' '/ SSID/ { print $2 }')

# Check if WiFi interface is active (look for RouterARPVerified or similar active indicators)
WIFI_ACTIVE=$(echo "$IPCONFIG_OUTPUT" | grep -c "SSID")

if [[ "$WIFI_ACTIVE" -eq 0 && "$IPCONFIG_OUTPUT" != *"SSID"* ]]; then
  # WiFi is off - no SSID field in output at all
  ICON="󰖪"
  COLOR="$RED"
  LABEL=""
elif [[ -z "$SSID" ]]; then
  # WiFi on but not connected to any network
  ICON="󰤯"
  COLOR="$YELLOW"
  LABEL=""
else
  # Connected - show network name
  ICON="󰖩"
  COLOR="$ICON_COLOR"
  LABEL="$SSID"
fi

sketchybar --set "$NAME" \
  icon="$ICON" \
  icon.color="$COLOR" \
  label.color="$LABEL_COLOR" \
  label="$LABEL" \
  label.drawing=$([[ -n "$LABEL" ]] && echo "on" || echo "off")
