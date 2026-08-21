#!/bin/sh
# Keybind cheatsheet (alt+/): every chord across tmux, aerospace, ghostty,
# and zsh, fuzzy-searchable. keys.tsv is the curated source of truth,
# drift-checked against the configs by ci/keycheck.py in prek/CI.
set -eu

KEYS="$HOME/.config/tmux/keys.tsv"

tail -n +2 "$KEYS" |
  awk -F'\t' '{ printf "%-10s  %-24s  %s\n", $1, $2, $3 }' |
  fzf \
    --prompt='keys> ' \
    --layout=reverse \
    --info=hidden \
    --no-sort \
    --bind 'enter:abort' \
    --header 'esc closes · type to filter' || true
