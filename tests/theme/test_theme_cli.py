"""Behavioral tests for the `theme` CLI, run against a scratch HOME.

Stub executables cover everything that would otherwise touch the live
machine: osascript (macOS appearance), bat (theme cache rebuild), pkill
(ghostty reload signal), and mascot-accents (network extraction).
Stdlib-only imports, like
test_mascot_accents.py: the type checker's environment has no pytest;
the built-in tmp_path fixture arrives by argument name.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path
from xml.etree import ElementTree

REPO = Path(__file__).parent.parent.parent
THEME = REPO / "theme/bin/theme"

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
    for name in ("bat", "osascript", "pkill"):
        stub = stubs / name
        stub.write_text("#!/bin/sh\nexit 0\n")
        stub.chmod(0o755)
    return tmp_path


def make_config(tmp_path: Path) -> Path:
    dst = tmp_path / "theme-config"
    shutil.copytree(
        REPO / "theme", dst, ignore=shutil.ignore_patterns("bin", "__pycache__")
    )
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


def test_project_mappings_survive_metacharacter_names(tmp_path: Path) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)
    stub_mascot_accents(home, MASCOT_ACCENTS_OK)
    names = ("a&b", "odd|proj", "dot.name")

    for name in names:
        project = home / name
        project.mkdir()
        first = run_theme(home, config, "mascot", "project", "pokemon:mew", cwd=project)
        assert first.returncode == 0, first.stderr
        remap = run_theme(
            home, config, "mascot", "project", "pokemon:ditto", cwd=project
        )
        assert remap.returncode == 0, remap.stderr

    mappings = (state_dir(home) / "mascot.conf").read_text().splitlines()
    assert sorted(mappings) == sorted(f"{name}=pokemon:ditto" for name in names)


def test_unmapping_removes_only_the_named_project(tmp_path: Path) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)
    stub_mascot_accents(home, MASCOT_ACCENTS_OK)
    state_dir(home).mkdir(parents=True)
    (state_dir(home) / "mascot.conf").write_text(
        "a&b=pokemon:mew\nother=pokemon:eevee\n"
    )
    project = home / "a&b"
    project.mkdir()

    result = run_theme(home, config, "mascot", "project", "none", cwd=project)

    assert result.returncode == 0, result.stderr
    assert (state_dir(home) / "mascot.conf").read_text() == "other=pokemon:eevee\n"


def test_failed_extraction_persists_no_project_mapping(tmp_path: Path) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)
    stub_mascot_accents(home, MASCOT_ACCENTS_FAIL)
    project = home / "proj"
    project.mkdir()

    result = run_theme(home, config, "mascot", "project", "pokemon:badmon", cwd=project)

    assert result.returncode == 1
    assert not (state_dir(home) / "mascot.conf").exists()


def test_failed_extraction_leaves_tracked_default_untouched(tmp_path: Path) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)
    stub_mascot_accents(home, MASCOT_ACCENTS_FAIL)
    tracked = config / "mascot.conf"
    before = tracked.read_text()

    result = run_theme(home, config, "mascot", "default", "pokemon:badmon")

    assert result.returncode == 1
    assert tracked.read_text() == before


def test_successful_mapping_persists_and_extracts(tmp_path: Path) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)
    stub_mascot_accents(home, MASCOT_ACCENTS_OK)
    project = home / "proj"
    project.mkdir()

    result = run_theme(home, config, "mascot", "project", "pokemon:mew", cwd=project)

    assert result.returncode == 0, result.stderr
    assert (state_dir(home) / "mascot.conf").read_text() == "proj=pokemon:mew\n"
    assert "mascot=pokemon:mew" in (state_dir(home) / "accents.conf").read_text()


def test_corrupt_mode_file_falls_back_to_dark_with_a_warning(
    tmp_path: Path,
) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)
    state_dir(home).mkdir(parents=True)
    (state_dir(home) / "inner-mode").write_text("banana\n")

    result = run_theme(home, config, "apply")

    assert result.returncode == 0, result.stderr
    assert "inner-mode" in result.stderr and "banana" in result.stderr
    assert "inner=dark" in result.stdout


def test_render_survives_blank_and_comment_lines_in_conf_files(
    tmp_path: Path,
) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)
    tokens = config / "tokens.conf"
    tokens.write_text(tokens.read_text() + "\n\n# trailing comment\n")

    result = run_theme(home, config, "apply")

    assert result.returncode == 0, result.stderr
    rendered = state_dir(home) / "generated/tmux-colors.conf"
    assert "{{" not in rendered.read_text()


def test_bat_theme_is_generated_as_valid_xml(tmp_path: Path) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)

    result = run_theme(home, config, "apply")

    assert result.returncode == 0, result.stderr
    rendered = state_dir(home) / "generated/Dotfiles.tmTheme"
    contents = rendered.read_text()
    assert "{{" not in contents
    ElementTree.fromstring(contents)


def test_fsh_theme_is_generated_and_tracks_inner_mode(tmp_path: Path) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)

    dark_result = run_theme(home, config, "apply")

    assert dark_result.returncode == 0, dark_result.stderr
    rendered = state_dir(home) / "generated/fast-syntax-highlighting.ini"
    dark_contents = rendered.read_text()
    assert "{{" not in dark_contents
    assert "[command-point]" in dark_contents
    assert "reserved-word" in dark_contents
    dark_mauve = next(
        line.split("=", 1)[1]
        for line in (config / "palettes/mocha.conf").read_text().splitlines()
        if line.startswith("mauve=")
    )
    assert f"reserved-word    = {dark_mauve}" in dark_contents

    light_result = run_theme(home, config, "inner", "light")

    assert light_result.returncode == 0, light_result.stderr
    light_contents = rendered.read_text()
    assert light_contents != dark_contents
    assert "reserved-word" in light_contents
    light_mauve = next(
        line.split("=", 1)[1]
        for line in (config / "palettes/latte.conf").read_text().splitlines()
        if line.startswith("mauve=")
    )
    assert f"reserved-word    = {light_mauve}" in light_contents


def test_accent_override_reaches_rendered_output(tmp_path: Path) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)
    stub_mascot_accents(home, MASCOT_ACCENTS_OK)

    result = run_theme(home, config, "mascot", "pokemon:mew")

    assert result.returncode == 0, result.stderr
    rendered = (state_dir(home) / "generated/tmux-colors.conf").read_text()
    assert 'set -g @accent "#ffcc00"' in rendered


def test_mode_persists_only_after_a_successful_render(tmp_path: Path) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)
    ok = run_theme(home, config, "inner", "dark")
    assert ok.returncode == 0, ok.stderr
    template = config / "templates/frame.glsl.tmpl"
    template.write_text(template.read_text() + "{{typo_token}}\n")

    result = run_theme(home, config, "inner", "light")

    assert result.returncode == 1
    assert (state_dir(home) / "inner-mode").read_text() == "dark\n"


def test_failed_render_names_the_token_and_leaves_no_temp_files(
    tmp_path: Path,
) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)
    template = config / "templates/frame.glsl.tmpl"
    template.write_text(template.read_text() + "{{typo_token}}\n")

    result = run_theme(home, config, "apply")

    assert result.returncode == 1
    assert "{{typo_token}}" in result.stderr
    leftovers = [p.name for p in state_dir(home).iterdir() if ".render" in p.name]
    assert leftovers == []
