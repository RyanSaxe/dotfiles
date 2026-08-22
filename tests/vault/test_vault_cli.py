"""Behavioral tests for the `vault` CLI, run against scratch vaults.

Every run gets its own VAULT_DIR, its own XDG_CONFIG_HOME holding a copy of
the shipped templates, and a PATH containing symlinks to exactly the tools
the case allows — that last one is how "ripgrep is missing" becomes a fact
rather than a mock. The rest of the environment is inherited: the script's
shebang is `uv run --script`, and uv resolves its interpreter through it.

Stdlib-only imports, like tests/theme: the type checker's environment has no
pytest; the built-in tmp_path fixture arrives by argument name.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from datetime import date, datetime, timedelta
from pathlib import Path

REPO = Path(__file__).parent.parent.parent
VAULT = REPO / "clis/vault/vault"
TEMPLATES = REPO / "clis/vault/templates"

# The due-date sigil the grammar uses, spelled once here too.
DUE = "📅"

# Enough of a PATH to run the script (env, uv), talk to git, and shell out to
# ripgrep. Anything absent from this list is absent from the run.
TOOLS = ("env", "uv", "sh", "git", "rg")


def toolbox(tmp_path: Path, *, tools: tuple[str, ...] = TOOLS) -> Path:
    bin_dir = tmp_path / "toolbox" / "-".join(tools)
    if bin_dir.is_dir():
        return bin_dir
    bin_dir.mkdir(parents=True)
    for name in tools:
        found = shutil.which(name)
        if found:
            (bin_dir / name).symlink_to(found)
    return bin_dir


def config_home(tmp_path: Path) -> Path:
    """A scratch $XDG_CONFIG_HOME holding the templates install.sh deploys."""
    config = tmp_path / "config"
    deployed = config / "vault" / "templates"
    if not deployed.exists():
        shutil.copytree(TEMPLATES, deployed)
    return config


def run_vault(
    tmp_path: Path,
    *args: str,
    vault: Path | None = None,
    cwd: Path | None = None,
    config: Path | None = None,
    tools: tuple[str, ...] = TOOLS,
) -> subprocess.CompletedProcess[str]:
    env = dict(os.environ)
    env["PATH"] = str(toolbox(tmp_path, tools=tools))
    env["XDG_CONFIG_HOME"] = str(config or config_home(tmp_path))
    if vault is None:
        env["VAULT_DIR"] = str(tmp_path / "vault")
    elif vault == Path():
        env.pop("VAULT_DIR", None)
    else:
        env["VAULT_DIR"] = str(vault)
    return subprocess.run(
        [str(VAULT), *args],
        capture_output=True,
        text=True,
        env=env,
        cwd=cwd or tmp_path,
        check=False,
    )


def make_vault(tmp_path: Path) -> Path:
    result = run_vault(tmp_path, "init")
    assert result.returncode == 0, result.stderr
    return (tmp_path / "vault").resolve()


def write_note(vault: Path, relative: str, text: str) -> None:
    path = vault / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def today() -> date:
    return datetime.now().astimezone().date()


def tasks_json(tmp_path: Path) -> list[dict]:
    result = run_vault(tmp_path, "tasks", "--json")
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def find(rows: list[dict], text: str) -> dict:
    matches = [row for row in rows if row["text"] == text]
    assert len(matches) == 1, f"{text!r} matched {len(matches)} rows"
    return matches[0]


def fixture_vault(tmp_path: Path) -> Path:
    """A vault covering every shape the parser has to get right."""
    vault = make_vault(tmp_path)
    write_note(
        vault,
        "projects/dotfiles/TODO.md",
        "# dotfiles\n"
        "\n"
        f"- [ ] Decide how the dashboard groups future work {DUE} {today() + timedelta(days=5)}\n"
        "\n"
        "## feat/github-attention-observer\n"
        "\n"
        f"- [ ] Verify the review rail at the narrowest width {DUE} {today() - timedelta(days=2)}\n"
        "- [x] Wire the tab routing\n",
    )
    write_note(
        vault,
        "people/rene-muller.md",
        "- [ ] a task above every heading\n"
        "\n"
        "# René Müller\n"
        "\n"
        "- [ ] ask about the naïve café façade\n"
        "\n"
        "```markdown\n"
        "- [ ] this one is a code sample\n"
        "# not a section either\n"
        "```\n"
        "\n"
        "- [ ] after the fence\n",
    )
    write_note(vault, ".obsidian/workspace.md", "- [ ] application state\n")
    return vault


# -------------------------------------------------------------------- tasks
def test_a_task_row_carries_the_whole_documented_schema(tmp_path: Path) -> None:
    fixture_vault(tmp_path)

    row = find(tasks_json(tmp_path), "Verify the review rail at the narrowest width")

    assert row == {
        "id": "projects/dotfiles/TODO.md:7",
        "text": "Verify the review rail at the narrowest width",
        "done": False,
        "due": (today() - timedelta(days=2)).isoformat(),
        "state": "overdue",
        "project": "dotfiles",
        "section": "feat/github-attention-observer",
        "file": "projects/dotfiles/TODO.md",
        "line": 7,
    }


def test_a_section_is_the_nearest_heading_and_null_above_the_first(
    tmp_path: Path,
) -> None:
    fixture_vault(tmp_path)
    rows = tasks_json(tmp_path)

    assert find(rows, "a task above every heading")["section"] is None
    assert find(rows, "ask about the naïve café façade")["section"] == "René Müller"
    assert find(rows, "Decide how the dashboard groups future work")["section"] == (
        "dotfiles"
    )


def test_a_project_is_the_projects_directory_and_null_elsewhere(
    tmp_path: Path,
) -> None:
    fixture_vault(tmp_path)
    rows = tasks_json(tmp_path)

    assert find(rows, "Wire the tab routing")["project"] == "dotfiles"
    assert find(rows, "ask about the naïve café façade")["project"] is None


def test_due_states_are_calendar_distances_from_today(tmp_path: Path) -> None:
    vault = make_vault(tmp_path)
    offsets = {
        "overdue": -1,
        "today": 0,
        "tomorrow": 1,
        "near": 2,
        "edge of near": 7,
        "later": 8,
    }
    lines = [
        f"- [ ] {name} {DUE} {today() + timedelta(days=offset)}"
        for name, offset in offsets.items()
    ]
    write_note(vault, "inbox.md", "\n".join([*lines, "- [ ] undated", ""]))

    states = {row["text"]: row["state"] for row in tasks_json(tmp_path)}

    assert states == {
        "overdue": "overdue",
        "today": "today",
        "tomorrow": "tomorrow",
        "near": "near",
        "edge of near": "near",
        "later": "later",
        "undated": "none",
    }


def test_fenced_code_and_hidden_directories_hold_no_tasks(tmp_path: Path) -> None:
    fixture_vault(tmp_path)

    texts = [row["text"] for row in tasks_json(tmp_path)]

    assert "this one is a code sample" not in texts
    assert "application state" not in texts
    # The heading inside the fence is not a section either.
    assert find(tasks_json(tmp_path), "after the fence")["section"] == "René Müller"


def test_tasks_render_as_a_tree_of_files_and_sections(tmp_path: Path) -> None:
    fixture_vault(tmp_path)

    result = run_vault(tmp_path, "tasks")

    assert result.returncode == 0, result.stderr
    assert "projects/dotfiles/TODO.md" in result.stdout
    assert "└── [x] Wire the tab routing" in result.stdout
    assert "overdue" in result.stdout
    # Not a terminal, so no escape sequences reach a pipe.
    assert "\033[" not in result.stdout


def test_a_fresh_vault_has_no_tasks(tmp_path: Path) -> None:
    make_vault(tmp_path)

    result = run_vault(tmp_path, "tasks")

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "no tasks"
    assert tasks_json(tmp_path) == []


# --------------------------------------------------------------------- init
def test_init_produces_a_vault_that_check_passes(tmp_path: Path) -> None:
    vault = make_vault(tmp_path)

    for name in ("assets", "daily", "people", "projects", "public", ".git"):
        assert (vault / name).is_dir(), name
    assert (vault / ".ignore").read_text() == "!*\n.git/\n"
    assert ".obsidian/" in (vault / ".gitignore").read_text()

    check = run_vault(tmp_path, "check")
    assert check.returncode == 0, check.stdout + check.stderr
    assert "fail" not in check.stdout


def test_init_refuses_a_directory_that_already_holds_content(
    tmp_path: Path,
) -> None:
    vault = tmp_path / "vault"
    vault.mkdir()
    (vault / "notes.md").write_text("# notes\n")

    result = run_vault(tmp_path, "init")

    assert result.returncode == 1
    assert "--in-place" in result.stderr
    assert not (vault / ".ignore").exists()


def test_init_in_place_adds_only_the_missing_pieces(tmp_path: Path) -> None:
    vault = tmp_path / "vault"
    (vault / "daily").mkdir(parents=True)
    existing = {
        vault / ".gitignore": "# hand written\n/*\n",
        vault / "inbox.md": "# my inbox\n\n- a thought\n",
        vault / "daily/2026-08-22.md": "# 2026-08-22\n",
    }
    for path, contents in existing.items():
        path.write_bytes(contents.encode())
    before = {path: path.read_bytes() for path in existing}

    result = run_vault(tmp_path, "init", "--in-place")

    assert result.returncode == 0, result.stderr
    for path, contents in before.items():
        assert path.read_bytes() == contents, path
    assert (vault / ".ignore").is_file()
    assert (vault / "people").is_dir()
    assert (vault / ".git").is_dir()
    # An unchanged file is never announced as created.
    assert ".gitignore" not in result.stdout


def test_init_takes_an_explicit_path_over_vault_dir(tmp_path: Path) -> None:
    elsewhere = tmp_path / "somewhere" / "else"

    result = run_vault(tmp_path, "init", str(elsewhere))

    assert result.returncode == 0, result.stderr
    assert (elsewhere / ".ignore").is_file()
    assert not (tmp_path / "vault").exists()


def test_init_is_idempotent(tmp_path: Path) -> None:
    make_vault(tmp_path)

    again = run_vault(tmp_path, "init", "--in-place")

    assert again.returncode == 0, again.stderr
    assert "already conforms" in again.stdout


# -------------------------------------------------------------------- check
def test_check_fails_when_the_ignore_file_is_gone(tmp_path: Path) -> None:
    vault = make_vault(tmp_path)
    (vault / ".ignore").unlink()

    result = run_vault(tmp_path, "check")

    assert result.returncode == 1
    assert "no .ignore" in result.stdout


def test_check_fails_when_the_ignore_file_hides_notes(tmp_path: Path) -> None:
    # The real failure this exists to catch: a plausible .ignore that forgets
    # to re-include gitignored files. It needs real ripgrep inside a real git
    # repository, because .gitignore is inert outside one.
    if shutil.which("rg") is None:
        return
    vault = make_vault(tmp_path)
    (vault / ".ignore").write_text(".git/\n")
    (vault / "projects" / "demo").mkdir(parents=True)
    (vault / "projects" / "demo" / "TODO.md").write_text("# demo\n")

    result = run_vault(tmp_path, "check")

    assert result.returncode == 1
    assert "invisible to Neovim" in result.stdout
    assert "projects/demo/TODO.md" in result.stdout


def test_check_fails_without_ripgrep(tmp_path: Path) -> None:
    make_vault(tmp_path)

    result = run_vault(tmp_path, "check", tools=("env", "uv", "sh", "git"))

    assert result.returncode == 1
    assert "ripgrep" in result.stdout


def test_check_fails_when_a_template_does_not_resolve(tmp_path: Path) -> None:
    make_vault(tmp_path)
    (config_home(tmp_path) / "vault/templates/daily.md").unlink()

    result = run_vault(tmp_path, "check")

    assert result.returncode == 1
    assert "daily.md" in result.stdout


def test_check_fails_when_no_templates_are_deployed(tmp_path: Path) -> None:
    make_vault(tmp_path)
    undeployed = tmp_path / "empty-config"
    undeployed.mkdir()

    result = run_vault(tmp_path, "check", config=undeployed)

    assert result.returncode == 1
    assert "template directory" in result.stdout


def test_check_warns_about_obsidian_directories_without_failing(
    tmp_path: Path,
) -> None:
    vault = make_vault(tmp_path)
    (vault / "projects" / ".obsidian").mkdir(parents=True)
    (vault.parent / ".obsidian").mkdir()

    result = run_vault(tmp_path, "check")

    assert result.returncode == 0, result.stdout + result.stderr
    assert "nested .obsidian/ under projects" in result.stdout
    assert "ancestor" in result.stdout


def test_check_warns_when_gitignore_forgets_obsidian(tmp_path: Path) -> None:
    vault = make_vault(tmp_path)
    (vault / ".gitignore").write_text("/*\n!/public/\n")

    result = run_vault(tmp_path, "check")

    assert result.returncode == 0, result.stdout + result.stderr
    assert ".obsidian/ missing from .gitignore" in result.stdout


# ---------------------------------------------------------------- vault dir
def test_unset_vault_dir_names_the_variable(tmp_path: Path) -> None:
    result = run_vault(tmp_path, "check", vault=Path())

    assert result.returncode == 1
    assert "VAULT_DIR" in result.stderr


def test_missing_vault_directory_is_named(tmp_path: Path) -> None:
    result = run_vault(tmp_path, "check", vault=tmp_path / "nowhere")

    assert result.returncode == 1
    assert "nowhere" in result.stderr
