from __future__ import annotations

import os
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BYOR_CONFIG = REPO / "config/byor/config.yml"
GUARD_SCRIPT = REPO / "config/byor/scripts/guard-commands.py"
LINTERS_SCRIPT = REPO / "config/byor/scripts/run-repo-linters.py"
SUPPRESSION_SCRIPT = REPO / "config/byor/scripts/check-suppression-reason.py"


def _clean_git_env() -> dict[str, str]:
    return {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}


def _run_guard(command: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["uv", "run", "--no-project", str(GUARD_SCRIPT)],
        input=command,
        capture_output=True,
        text=True,
        check=False,
        timeout=10,
    )


def test_byor_repo_linters_covers_shell_and_nix_extensions() -> None:
    text = BYOR_CONFIG.read_text(encoding="utf-8")
    for ext in ("- sh", "- bash", "- nix"):
        assert ext in text


def test_guard_commands_allows_macos_private_var_folders_and_blocks_real_paths(tmp_path: Path) -> None:
    var_target = Path("/var/folders/zz/demo/repo")
    assert _run_guard(f"git -C {var_target} reset --hard\n").returncode == 0
    assert _run_guard("rm -rf /private/var/folders/foo/bar\n").returncode == 0
    assert _run_guard(f"git -C {REPO} reset --hard\n").returncode == 1
    assert _run_guard(f"rm -rf {REPO}/config\n").returncode == 1
    assert _run_guard(f"rm -rf {tmp_path}/sub\n").returncode == 0


def test_suppression_reason_accepts_inline_reason_and_rejects_bare_or_one_word(tmp_path: Path) -> None:
    good_py = tmp_path / "good.py"
    good_py.write_text('x = "/tmp"  # noqa: S108 -- path allowlist\n', encoding="utf-8")
    good_ts = tmp_path / "good.ts"
    good_ts.write_text("// ast-grep-ignore: react.no-try-finally -- cleanup must run here\n", encoding="utf-8")

    ok = subprocess.run(
        ["uv", "run", "--no-project", str(SUPPRESSION_SCRIPT), str(good_py), str(good_ts)],
        cwd=tmp_path,
        env=_clean_git_env(),
        capture_output=True,
        text=True,
        check=False,
        timeout=10,
    )
    assert ok.returncode == 0, ok.stdout + ok.stderr

    for bad_line in (
        'x = "/tmp"  # noqa: S108\n',
        'x = "/tmp"  # noqa: S108 -- ok\n',
        "// ast-grep-ignore: react.no-try-finally\n",
        "// ast-grep-ignore: react.no-try-finally -- cleanup\n",
    ):
        bad_file = tmp_path / "bad.txt"
        bad_file.write_text(bad_line, encoding="utf-8")
        res = subprocess.run(
            ["uv", "run", "--no-project", str(SUPPRESSION_SCRIPT), str(bad_file)],
            cwd=tmp_path,
            env=_clean_git_env(),
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
        )
        assert res.returncode == 1, f"expected failure for {bad_line!r}"


def test_run_repo_linters_enforces_emmyrc_severity_on_single_lua_file(tmp_path: Path) -> None:
    (tmp_path / ".emmyrc.json").write_text(
        '{"diagnostics":{"enable":true,"severity":{"param-type-mismatch":"error","unused":"error"}}}\n',
        encoding="utf-8",
    )
    bad_lua = tmp_path / "bad.lua"
    bad_lua.write_text(
        '---@param x integer\nlocal function f(x)\n  return x\nend\nf("bad")\n',
        encoding="utf-8",
    )
    res = subprocess.run(
        ["uv", "run", "--no-project", str(LINTERS_SCRIPT), str(bad_lua)],
        cwd=tmp_path,
        capture_output=True,
        text=True,
        check=False,
        timeout=10,
    )
    assert res.returncode == 1
    assert "param-type-mismatch" in res.stdout
