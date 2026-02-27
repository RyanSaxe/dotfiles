#!/usr/bin/env bash
# Detect built-in display notch height and configure git filter for aerospace.toml.
# Run once per machine (called from install.sh).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
CACHE_FILE="$HOME/.cache/aerospace-notch-inset"

# Detect top inset of built-in display (notch height in points)
detect_notch_inset() {
  # Only macOS has notched displays
  [[ "$(uname)" == "Darwin" ]] || {
    echo "0"
    return
  }

  cat << 'SWIFT' | swift - 2> /dev/null || echo "0"
import AppKit
let screen = NSScreen.screens.first {
  $0.localizedName.lowercased().contains("built-in")
}
guard let s = screen else { print("0"); exit(0) }
let inset = s.frame.size.height - s.visibleFrame.size.height - s.visibleFrame.origin.y
print(Int(inset))
SWIFT
}

# Cache the notch inset
mkdir -p "$(dirname "$CACHE_FILE")"
INSET=$(detect_notch_inset)
echo "$INSET" > "$CACHE_FILE"

# Register the git smudge/clean filter (per-clone setting)
git -C "$DOTFILES_DIR" config filter.aerospace-notch.smudge 'aerospace/notch-filter.sh smudge'
git -C "$DOTFILES_DIR" config filter.aerospace-notch.clean 'aerospace/notch-filter.sh clean'

# Re-smudge the config so the working copy has the right value.
# Must clear the index entry first, otherwise git considers the file up-to-date
# and skips the smudge filter.
git -C "$DOTFILES_DIR" rm --cached aerospace/aerospace.toml 2> /dev/null || true
git -C "$DOTFILES_DIR" checkout HEAD -- aerospace/aerospace.toml 2> /dev/null || true

if [[ "$INSET" -gt 0 ]]; then
  echo "Notch detected (${INSET}px). Aerospace outer.top adjusted for built-in display."
else
  echo "No notch detected. Aerospace outer.top unchanged."
fi
