"""Behavioral tests for SketchyBar's generated-theme convergence hook."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

REPO = Path(__file__).parent.parent.parent
SYNC = REPO / "sketchybar/plugins/theme-sync.sh"


def test_theme_event_refreshes_with_unchanged_colors_mtime(tmp_path: Path) -> None:
    home = tmp_path
    stub = home / "stubbin/sketchybar"
    stub.parent.mkdir()
    stub.write_text('#!/bin/sh\nprintf \'%s\\n\' "$*" >> "$SKETCHYBAR_LOG"\n')
    stub.chmod(0o755)

    colors = home / ".config/sketchybar/colors.sh"
    colors.parent.mkdir(parents=True)
    colors.write_text(
        'source "$XDG_STATE_HOME/dotfiles/generated/sketchybar-colors.sh"\n'
    )
    generated = home / "state/dotfiles/generated/sketchybar-colors.sh"
    generated.parent.mkdir(parents=True)
    generated.write_text(
        'export BAR_COLOR="0xff111111"\n'
        'export BORDER_COLOR="0xff222222"\n'
        'export ICON_COLOR="0xff333333"\n'
        'export LABEL_COLOR="0xff444444"\n'
    )
    log = home / "sketchybar.log"
    env = {
        **os.environ,
        "HOME": str(home),
        "XDG_STATE_HOME": str(home / "state"),
        "PATH": f"{home / 'stubbin'}:/usr/bin:/bin",
        "SKETCHYBAR_LOG": str(log),
        "SENDER": "",
    }

    startup = subprocess.run(
        ["zsh", str(SYNC)],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )
    assert startup.returncode == 0, startup.stderr
    assert "--bar color=0xff111111 border_color=0xff222222" in log.read_text()
    assert "--trigger mascot_colors_changed" in log.read_text()

    log.write_text("")
    unchanged = subprocess.run(
        ["zsh", str(SYNC)],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )
    assert unchanged.returncode == 0, unchanged.stderr
    assert log.read_text() == ""

    event_env = {**env, "SENDER": "theme_changed"}
    event = subprocess.run(
        ["zsh", str(SYNC)],
        capture_output=True,
        text=True,
        env=event_env,
        check=False,
    )
    assert event.returncode == 0, event.stderr
    assert "--bar color=0xff111111 border_color=0xff222222" in log.read_text()
    assert "--trigger mascot_colors_changed" in log.read_text()
