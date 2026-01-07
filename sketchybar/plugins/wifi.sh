#!/usr/bin/env zsh
# WiFi status plugin - uses system_profiler for reliable SSID detection

source "$HOME/.config/sketchybar/colors.sh"

# Get WiFi interface name (usually en0 on Macs)
WIFI_INTERFACE=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')

if [[ -z "$WIFI_INTERFACE" ]]; then
  WIFI_INTERFACE="en0"
fi

# Check if WiFi is on
WIFI_POWER=$(networksetup -getairportpower "$WIFI_INTERFACE" 2> /dev/null | awk '{print $4}')

if [[ "$WIFI_POWER" == "Off" ]]; then
  ICON="󰤭"
  LABEL="Off"
  COLOR="$RED"
else
  # Get current network using system_profiler (more reliable than networksetup)
  # Extracts the SSID from "Current Network Information:" section
  SSID=$(system_profiler SPAirPortDataType 2> /dev/null | awk -F': ' '/Current Network Information:/{getline; gsub(/^[[:space:]]+|:$/, ""); print; exit}')

  if [[ -z "$SSID" ]]; then
    ICON="󰤯"
    LABEL="--"
    COLOR="$YELLOW"
  else
    ICON="󰤨"
    COLOR="$ICON_COLOR"

    # Truncate SSID if too long
    if [[ ${#SSID} -gt 12 ]]; then
      LABEL="${SSID:0:10}.."
    else
      LABEL="$SSID"
    fi
  fi
fi

sketchybar --set "$NAME" \
  icon="$ICON" \
  icon.color="$COLOR" \
  label="$LABEL"
