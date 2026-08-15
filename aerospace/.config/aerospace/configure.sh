#!/bin/sh
# Detect the built-in display's notch inset and wire up the git filter
# that keeps aerospace.toml's outer.top correct per machine. Run once per
# machine (install.sh mac tier calls it); safe to re-run.
set -eu

SCRIPT_PATH="$(readlink -f "$0")"
REPO_ROOT="${SCRIPT_PATH%/aerospace/.config/aerospace/configure.sh}"
TOML_PATH="aerospace/.config/aerospace/aerospace.toml"
CACHE_FILE="$HOME/.cache/aerospace-notch-inset"

# Top inset of the built-in display in points (0 when notchless).
detect_notch_inset() {
  swift - 2>/dev/null <<'SWIFT' || echo 0
import AppKit
let screen = NSScreen.screens.first {
  $0.localizedName.lowercased().contains("built-in")
}
guard let s = screen else { print("0"); exit(0) }
let inset = s.frame.size.height - s.visibleFrame.size.height - s.visibleFrame.origin.y
print(Int(inset))
SWIFT
}

mkdir -p "$(dirname "$CACHE_FILE")"
INSET="$(detect_notch_inset)"
printf '%s\n' "$INSET" >"$CACHE_FILE"

# Register the smudge/clean filter (per-clone setting; paths repo-relative).
git -C "$REPO_ROOT" config filter.aerospace-notch.smudge \
  'aerospace/.config/aerospace/notch-filter.sh smudge'
git -C "$REPO_ROOT" config filter.aerospace-notch.clean \
  'aerospace/.config/aerospace/notch-filter.sh clean'

# Re-smudge the working copy. The index entry must be cleared first or git
# considers the file up-to-date and skips the filter.
git -C "$REPO_ROOT" rm --cached "$TOML_PATH" >/dev/null 2>&1 || true
git -C "$REPO_ROOT" checkout HEAD -- "$TOML_PATH" 2>/dev/null || true

if [ "$INSET" -gt 0 ]; then
  echo "aerospace: notch inset ${INSET}pt; built-in outer.top adjusted"
else
  echo "aerospace: no notch detected; outer.top unchanged"
fi
