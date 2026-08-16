"""Behavioral tests for the `theme` CLI, run against a scratch HOME.

Stub executables cover everything that would otherwise touch the live
machine: osascript (macOS appearance), pkill (ghostty reload signal), and
mascot-accents (network extraction). The config setup drops the bat
template so publish never invokes bat. Stdlib-only imports, like
test_mascot_accents.py: the type checker's environment has no pytest;
the built-in tmp_path fixture arrives by argument name.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

REPO = Path(__file__).parent.parent.parent
THEME = REPO / "theme/dot-local/bin/theme"

MASCOT_ACCENTS_OK = """#!/bin/sh
printf 'mascot=%s\\n' "$1"
printf 'sprite=/dev/null\\n'
printf 'accent_dark=#ffcc00\\nnotify_dark=#aa66ff\\n'
printf 'accent_light=#997700\\nnotify_light=#7744aa\\n'
"""

MASCOT_ACCENTS_FAIL = """#!/bin/sh
echo "error: cannot fetch '$1'" >&2
exit 1
"""


def make_home(tmp_path: Path) -> Path:
    stubs = tmp_path / "stubbin"
    stubs.mkdir()
    for name in ("osascript", "pkill"):
        stub = stubs / name
        stub.write_text("#!/bin/sh\nexit 0\n")
        stub.chmod(0o755)
    return tmp_path


def make_config(tmp_path: Path) -> Path:
    dst = tmp_path / "theme-config"
    shutil.copytree(REPO / "theme/dot-config", dst)
    (dst / "theme/templates/Dotfiles.tmTheme.tmpl").unlink()
    return dst


def stub_mascot_accents(home: Path, script: str) -> None:
    stub = home / "stubbin/mascot-accents"
    stub.write_text(script)
    stub.chmod(0o755)


def run_theme(
    home: Path, config: Path, *args: str, cwd: Path | None = None
) -> subprocess.CompletedProcess[str]:
    env = {
        "HOME": str(home),
        "XDG_STATE_HOME": str(home / "state"),
        "THEME_CONFIG": str(config),
        "PATH": f"{home / 'stubbin'}:/usr/bin:/bin",
    }
    return subprocess.run(
        [str(THEME), *args],
        capture_output=True,
        text=True,
        env=env,
        cwd=cwd or home,
        check=False,
    )


def state_dir(home: Path) -> Path:
    return home / "state/dotfiles"


def test_render_survives_blank_and_comment_lines_in_conf_files(
    tmp_path: Path,
) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)
    tokens = config / "theme/tokens.conf"
    tokens.write_text(tokens.read_text() + "\n\n# trailing comment\n")

    result = run_theme(home, config, "apply")

    assert result.returncode == 0, result.stderr
    rendered = state_dir(home) / "generated/tmux-colors.conf"
    assert "{{" not in rendered.read_text()
