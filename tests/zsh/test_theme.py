"""Behavioral tests for theme/theme.sh, run against a scratch HOME.

Each run gets its own HOME with both modes rendered and a stub sketchybar
that records its calls, so nothing touches the real bar, apps or theme.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).parent.parent.parent
SCRIPT = REPO / "theme/theme.sh"


def current_mode() -> str:
    # theme.sh follows macOS's appearance there, and keeps the last mode
    # elsewhere.
    if sys.platform != "darwin":
        return "dark"
    style = subprocess.run(
        ["/usr/bin/defaults", "read", "-g", "AppleInterfaceStyle"],
        capture_output=True,
        text=True,
    )
    return "dark" if "Dark" in style.stdout else "light"


def run_theme(tmp_path: Path, sender: str) -> list[str]:
    home = tmp_path / "home"
    theme_dir = home / ".config/theme"
    for mode in ("dark", "light"):
        (theme_dir / mode).mkdir(parents=True)
    (theme_dir / "mode").write_text(current_mode() + "\n")
    calls = tmp_path / "sketchybar-calls"
    stubs = tmp_path / "bin"
    stubs.mkdir()
    # sketchybar records its calls. tmux and pkill do nothing, so a run that
    # goes past the check can't reach a real tmux server or Ghostty.
    for name, body in (("sketchybar", f'echo "$*" >> {calls}'), ("tmux", "exit 1"), ("pkill", "exit 0")):
        stub = stubs / name
        stub.write_text(f"#!/bin/sh\n{body}\n")
        stub.chmod(0o755)
    env = {
        "PATH": f"{stubs}:{os.environ['PATH']}",
        "HOME": str(home),
        "SKETCHYBAR": str(stubs / "sketchybar"),
        "TMUX_TMPDIR": str(tmp_path / "tmux"),
        "SENDER": sender,
    }
    subprocess.run(["zsh", str(SCRIPT)], env=env, check=True, timeout=30)
    return calls.read_text().splitlines() if calls.exists() else []


def test_sketchybars_run_leaves_an_applied_mode_alone(tmp_path: Path) -> None:
    # The run that changed the appearance already reloaded sketchybar, and a
    # second reload at the same time scrambles the bar's order.
    assert run_theme(tmp_path, sender="appearance_change") == []
