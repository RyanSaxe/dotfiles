#!/usr/bin/env -S uv run -q --script
# /// script
# requires-python = ">=3.11"
# ///
"""Drift check for the keybind cheatsheet (alt+/).

Every chord bound in tmux.conf (root alt layer, agent table, prefix
popups) and aerospace.toml must have a row in keys.tsv, so the popup can
never silently fall behind the configs. The TSV may hold extra rows
(ghostty, zsh, esc) — the check is config -> TSV only.
"""

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TMUX_CONF = REPO / "tmux/.config/tmux/tmux.conf"
AEROSPACE_TOML = REPO / "aerospace/.config/aerospace/aerospace.toml"
KEYS_TSV = REPO / "tmux/.config/tmux/keys.tsv"

KEY_WORDS = {"slash": "/", "comma": ",", "period": ".", "semicolon": ";"}


def normalize_key(key: str) -> str:
    key = key.strip("'\"").lower()
    return KEY_WORDS.get(key, {"escape": "esc"}.get(key, key))


def expand_tsv_chord(chord: str) -> set[str]:
    """One TSV cell covers several chords: 'h/j/k/l' alternates the final
    key, '1-9' spans the digit range, spaces separate sequence steps."""
    parts: list[list[str]] = []
    for part in chord.split(" "):
        prefix, _, last = part.rpartition("+")
        base = f"{prefix}+" if prefix else ""
        if last == "1-9":
            parts.append([f"{base}{d}" for d in "123456789"])
        elif "/" in last and last != "/":
            parts.append([f"{base}{k}" for k in last.split("/")])
        else:
            parts.append([part])
    chords: set[str] = {""}
    for options in parts:
        chords = {f"{c} {o}".strip() for c in chords for o in options}
    return chords


def tmux_chords(conf: str) -> set[str]:
    chords: set[str] = set()
    for m in re.finditer(r"^bind-key -n '?(M|C)-([^ ']+)'? ", conf, re.MULTILINE):
        mod = "alt" if m.group(1) == "M" else "ctrl"
        chords.add(f"{mod}+{normalize_key(m.group(2))}")
    for m in re.finditer(r"^bind-key -T agent (\S+) ", conf, re.MULTILINE):
        key = normalize_key(m.group(1).removeprefix("M-"))
        chords.add(f"alt+a {key}")
    for m in re.finditer(r"^bind-key ([a-z0-9]) ", conf, re.MULTILINE):
        chords.add(f"prefix {m.group(1)}")
    return chords


def aerospace_chords(toml: str) -> set[str]:
    chords: set[str] = set()
    binding = False
    for line in toml.splitlines():
        if line.startswith("["):
            binding = line.strip() == "[mode.main.binding]"
            continue
        if not binding:
            continue
        m = re.match(r"^([a-z0-9-]+) *=", line)
        if not m:
            continue
        *mods, key = m.group(1).split("-")
        ordered = [mod for mod in ("cmd", "alt", "shift", "ctrl") if mod in mods]
        chords.add("+".join(ordered) + "+" + normalize_key(key))
    return chords


def main() -> int:
    covered: set[str] = set()
    for line in KEYS_TSV.read_text().splitlines()[1:]:
        _, chord, _ = line.split("\t", 2)
        covered |= expand_tsv_chord(chord)
    bound = tmux_chords(TMUX_CONF.read_text()) | aerospace_chords(
        AEROSPACE_TOML.read_text()
    )
    missing = sorted(bound - covered)
    for chord in missing:
        print(f"keycheck: '{chord}' is bound but missing from keys.tsv")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
