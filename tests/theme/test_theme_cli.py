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

# Counts invocations and gives each mascot a distinct accent, so tests can
# both assert extraction counts (the warm-flip contract: zero spawns) and
# see a flip actually land in rendered output.
MASCOT_ACCENTS_COUNTING = """#!/bin/sh
echo "$1" >>"$HOME/mascot-accents.calls"
case "$1" in
pokemon:mew) accent=ffcc00 ;;
*) accent=00ccff ;;
esac
printf 'mascot=%s\\nsprite=/dev/null\\n' "$1"
printf 'accent_dark=#%s\\nnotify_dark=#aa66ff\\n' "$accent"
printf 'accent_light=#997700\\nnotify_light=#7744aa\\n'
"""

# Simulates a later jump landing while this extraction is still running:
# the superseded guard gets overwritten mid-sync.
MASCOT_ACCENTS_SUPERSEDING = """#!/bin/sh
printf 'pokemon:later\\n' >"$XDG_STATE_HOME/dotfiles/.mascot-requested"
printf 'mascot=%s\\nsprite=/dev/null\\n' "$1"
printf 'accent_dark=#ffcc00\\nnotify_dark=#aa66ff\\n'
printf 'accent_light=#997700\\nnotify_light=#7744aa\\n'
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


def map_projects(home: Path) -> None:
    state_dir(home).mkdir(parents=True, exist_ok=True)
    (state_dir(home) / "mascot.conf").write_text(
        "proja=pokemon:mew\nprojb=pokemon:ditto\n"
    )


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


def test_failed_extraction_leaves_the_default_untouched(tmp_path: Path) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)
    stub_mascot_accents(home, MASCOT_ACCENTS_FAIL)
    default_conf = state_dir(home) / "mascot-default.conf"

    result = run_theme(home, config, "mascot", "default", "pokemon:badmon")

    assert result.returncode == 1
    assert not default_conf.exists()


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
    (state_dir(home) / "mode").write_text("banana\n")

    result = run_theme(home, config, "apply")

    assert result.returncode == 0, result.stderr
    assert "banana" in result.stderr and "not dark|light" in result.stderr
    assert "mode=dark" in result.stdout


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


def test_fsh_theme_is_generated_and_tracks_mode(tmp_path: Path) -> None:
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

    light_result = run_theme(home, config, "light")

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
    project = tmp_path / "proj"
    project.mkdir()

    result = run_theme(home, config, "mascot", "project", "pokemon:mew", cwd=project)

    assert result.returncode == 0, result.stderr
    rendered = (state_dir(home) / "generated/tmux-colors.conf").read_text()
    assert 'set -g @accent "#ffcc00"' in rendered


def test_default_change_keeps_the_mapped_accent_on_screen(tmp_path: Path) -> None:
    # The visible accent follows the CURRENT session's effective mascot:
    # changing the fallback while a mapped project is active must update
    # the tracked default (and its state mirror for the rail) without
    # repainting anything with the new mascot's accent.
    home, config = make_home(tmp_path), make_config(tmp_path)
    stub_mascot_accents(home, MASCOT_ACCENTS_OK)
    project = tmp_path / "proj"
    project.mkdir()
    mapped = run_theme(home, config, "mascot", "project", "pokemon:mew", cwd=project)
    assert mapped.returncode == 0, mapped.stderr

    result = run_theme(home, config, "mascot", "default", "pokemon:ditto", cwd=project)

    assert result.returncode == 0, result.stderr
    default_conf = state_dir(home) / "mascot-default.conf"
    assert default_conf.read_text() == "default=pokemon:ditto\n"
    assert "mascot=pokemon:mew" in (state_dir(home) / "accents.conf").read_text()


def test_clear_projects_reverts_everyone_to_the_default(tmp_path: Path) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)
    stub_mascot_accents(home, MASCOT_ACCENTS_OK)
    project = tmp_path / "proj"
    project.mkdir()
    assert run_theme(home, config, "mascot", "default", "pokemon:ditto").returncode == 0
    assert (
        run_theme(home, config, "mascot", "project", "pokemon:mew", cwd=project)
    ).returncode == 0

    result = run_theme(home, config, "mascot", "clear-projects", cwd=project)

    assert result.returncode == 0, result.stderr
    assert (state_dir(home) / "mascot.conf").read_text() == ""
    assert "mascot=pokemon:ditto" in (state_dir(home) / "accents.conf").read_text()


def test_bare_mascot_form_is_gone(tmp_path: Path) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)

    result = run_theme(home, config, "mascot", "pokemon:mew")

    assert result.returncode == 1
    assert "usage" in result.stderr


def test_mode_persists_only_after_a_successful_render(tmp_path: Path) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)
    ok = run_theme(home, config, "dark")
    assert ok.returncode == 0, ok.stderr
    template = config / "templates/frame.glsl.tmpl"
    template.write_text(template.read_text() + "{{typo_token}}\n")

    result = run_theme(home, config, "light")

    assert result.returncode == 1
    assert (state_dir(home) / "mode").read_text() == "dark\n"


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
    builds = list((state_dir(home) / "cache/theme").glob(".build.*"))
    assert builds == []


def test_warm_sync_spawns_no_extractor(tmp_path: Path) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)
    stub_mascot_accents(home, MASCOT_ACCENTS_COUNTING)
    map_projects(home)
    calls = home / "mascot-accents.calls"
    for project in ("proja", "projb"):
        cold = run_theme(home, config, "mascot", "sync", project)
        assert cold.returncode == 0, cold.stderr
    assert calls.read_text().splitlines() == ["pokemon:mew", "pokemon:ditto"]

    warm = run_theme(home, config, "mascot", "sync", "proja")

    assert warm.returncode == 0, warm.stderr
    assert calls.read_text().splitlines() == ["pokemon:mew", "pokemon:ditto"]
    assert "mascot=pokemon:mew" in (state_dir(home) / "accents.conf").read_text()


def test_fsh_ini_mtime_survives_a_warm_mascot_flip(tmp_path: Path) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)
    stub_mascot_accents(home, MASCOT_ACCENTS_COUNTING)
    map_projects(home)
    for project in ("proja", "projb"):
        cold = run_theme(home, config, "mascot", "sync", project)
        assert cold.returncode == 0, cold.stderr
    ini = state_dir(home) / "generated/fast-syntax-highlighting.ini"
    tmux = state_dir(home) / "generated/tmux-colors.conf"
    ini_before = ini.stat().st_mtime_ns
    tmux_before = tmux.stat().st_mtime_ns

    warm = run_theme(home, config, "mascot", "sync", "proja")

    assert warm.returncode == 0, warm.stderr
    # The flip landed (accent-varying file republished with mew's accent)...
    assert tmux.stat().st_mtime_ns != tmux_before
    assert 'set -g @accent "#ffcc00"' in tmux.read_text()
    # ...without touching the accent-independent ini, so shells stay quiet.
    assert ini.stat().st_mtime_ns == ini_before


def test_render_input_change_invalidates_cached_entries(tmp_path: Path) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)
    stub_mascot_accents(home, MASCOT_ACCENTS_COUNTING)
    map_projects(home)
    calls = home / "mascot-accents.calls"
    for project in ("proja", "projb"):
        cold = run_theme(home, config, "mascot", "sync", project)
        assert cold.returncode == 0, cold.stderr
    template = config / "templates/tmux-colors.conf.tmpl"
    template.write_text(template.read_text() + 'set -g @stamp-probe "{{accent}}"\n')

    result = run_theme(home, config, "mascot", "sync", "proja")

    assert result.returncode == 0, result.stderr
    rendered = (state_dir(home) / "generated/tmux-colors.conf").read_text()
    assert 'set -g @stamp-probe "#ffcc00"' in rendered
    # The accents cache is stamped separately: a render-input edit must not
    # re-run the extractor.
    assert calls.read_text().splitlines() == ["pokemon:mew", "pokemon:ditto"]


def test_extractor_edit_invalidates_cached_renders(tmp_path: Path) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)
    stub_mascot_accents(home, MASCOT_ACCENTS_COUNTING)
    map_projects(home)
    calls = home / "mascot-accents.calls"
    for project in ("proja", "projb"):
        cold = run_theme(home, config, "mascot", "sync", project)
        assert cold.returncode == 0, cold.stderr
    # An extractor edit that changes its output: both stamps move, so the
    # banked mew render (old accent) must never be flipped in again.
    stub_mascot_accents(home, MASCOT_ACCENTS_COUNTING.replace("ffcc00", "123456"))

    result = run_theme(home, config, "mascot", "sync", "proja")

    assert result.returncode == 0, result.stderr
    assert calls.read_text().splitlines() == [
        "pokemon:mew",
        "pokemon:ditto",
        "pokemon:mew",
    ]
    rendered = (state_dir(home) / "generated/tmux-colors.conf").read_text()
    assert 'set -g @accent "#123456"' in rendered
    assert "#ffcc00" not in rendered


def test_apply_does_not_bank_live_accents_into_the_cache(tmp_path: Path) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)
    stub_mascot_accents(home, MASCOT_ACCENTS_COUNTING)
    map_projects(home)
    calls = home / "mascot-accents.calls"
    cold = run_theme(home, config, "mascot", "sync", "proja")
    assert cold.returncode == 0, cold.stderr
    stub_mascot_accents(home, MASCOT_ACCENTS_COUNTING.replace("ffcc00", "123456"))

    applied = run_theme(home, config, "apply")

    assert applied.returncode == 0, applied.stderr
    # apply renders offline against live accents.conf without laundering it
    # into the cache as if the edited extractor had produced it.
    assert calls.read_text().splitlines() == ["pokemon:mew"]
    banked = list((state_dir(home) / "cache/theme").glob("accents-*/*.conf"))
    assert banked == []
    # The unpoisoned cache re-extracts on the next visit and lands the
    # edited extractor's accent.
    for project in ("projb", "proja"):
        sync = run_theme(home, config, "mascot", "sync", project)
        assert sync.returncode == 0, sync.stderr
    assert calls.read_text().splitlines() == [
        "pokemon:mew",
        "pokemon:ditto",
        "pokemon:mew",
    ]
    rendered = (state_dir(home) / "generated/tmux-colors.conf").read_text()
    assert 'set -g @accent "#123456"' in rendered


def test_cold_sync_that_extracted_rebuilds_a_complete_entry(tmp_path: Path) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)
    stub_mascot_accents(home, MASCOT_ACCENTS_COUNTING)
    map_projects(home)
    calls = home / "mascot-accents.calls"
    cold = run_theme(home, config, "mascot", "sync", "proja")
    assert cold.returncode == 0, cold.stderr
    # Rebuild mew's entry from accents the extractor never produced: drop
    # the extraction cache, hand-edit live accents, and force-render.
    for banked in (state_dir(home) / "cache/theme").glob("accents-*"):
        shutil.rmtree(banked)
    accents = state_dir(home) / "accents.conf"
    accents.write_text(accents.read_text().replace("ffcc00", "999999"))
    doctored = run_theme(home, config, "apply")
    assert doctored.returncode == 0, doctored.stderr

    flip_away = run_theme(home, config, "mascot", "sync", "projb")
    assert flip_away.returncode == 0, flip_away.stderr
    result = run_theme(home, config, "mascot", "sync", "proja")

    assert result.returncode == 0, result.stderr
    # The sync just re-extracted mew, so the doctored .complete entry was
    # rebuilt against the fresh accents, not flipped in.
    assert calls.read_text().splitlines() == [
        "pokemon:mew",
        "pokemon:ditto",
        "pokemon:mew",
    ]
    rendered = (state_dir(home) / "generated/tmux-colors.conf").read_text()
    assert 'set -g @accent "#ffcc00"' in rendered
    assert "#999999" not in rendered


def test_superseded_sync_leaves_the_flip_to_the_later_jump(tmp_path: Path) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)
    stub_mascot_accents(home, MASCOT_ACCENTS_SUPERSEDING)
    map_projects(home)

    result = run_theme(home, config, "mascot", "sync", "proja")

    assert result.returncode == 0, result.stderr
    # The later jump owns the flip: nothing was installed or published...
    assert not (state_dir(home) / "accents.conf").exists()
    assert not (state_dir(home) / "generated").exists()
    # ...but the render is banked, so the next visit to proja is warm.
    entries = list(
        (state_dir(home) / "cache/theme").glob("render-*/dark-pokemon-mew/.complete")
    )
    assert entries


def test_republish_preserves_unchanged_file_mtimes(tmp_path: Path) -> None:
    home, config = make_home(tmp_path), make_config(tmp_path)
    first = run_theme(home, config, "apply")
    assert first.returncode == 0, first.stderr
    generated = state_dir(home) / "generated"
    before = {p.name: p.stat().st_mtime_ns for p in generated.iterdir()}

    again = run_theme(home, config, "apply")

    assert again.returncode == 0, again.stderr
    after = {p.name: p.stat().st_mtime_ns for p in generated.iterdir()}
    assert after == before
