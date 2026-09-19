#!/usr/bin/env -S uv run -q --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Task state for a Markdown vault, and the contract the vault itself keeps.

    vault tasks [--json]
    vault task add <text> [--due DATE] [--branch]
    vault task done <ID>
    vault task due <ID> <DATE>
    vault init [path] [--in-place]
    vault check

The vault is $VAULT_DIR (or the path given to `init`). Its shape is an
allowlist: `.gitignore` keeps everything local except `public/`, and `.ignore`
puts the gitignored notes back in ripgrep's view — without it, note search,
quick-switch, backlinks, and tags silently return nothing.

A task is a `- [ ]` list item in any note. Its section is the nearest heading
above it and its project is the `projects/<name>/` directory holding the file.
Identity is `<vault-relative-path>:<line>`, recomputed on every read: no
index, no cache, no identifier written into the Markdown. Every write goes
through here, so nothing else has to know the grammar — `add` resolves the
project from the current directory's git remote, and dates are read here in
every spelling a person is likely to type. A task due today turns overdue when
this machine's clock passes $VAULT_OVERDUE_AFTER, 15:00 by default.

Exit codes: 0 success, 1 a failed check or a bad request.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from itertools import groupby
from pathlib import Path, PurePosixPath

COLOR = False  # set from --color in main()

VAULT_DIR_UNSET = (
    "VAULT_DIR is not set — export VAULT_DIR=<path to your vault> "
    "(the dotfiles' zshenv sets it)"
)

# The allowlist. A blocklist that misses a new directory publishes its
# contents; an allowlist that misses one leaves it local, which is the
# survivable direction. Only public/ ever leaves the machine.
GITIGNORE = """/*
!/.gitignore
!/.ignore
!/public/
.obsidian/
"""

# ripgrep honors .ignore above every .gitignore, including nested ones.
# obsidian.nvim builds a fixed `rg --no-config` command with no --no-ignore
# and no escape hatch, so this file is the only thing that keeps a gitignored
# vault visible to note search.
IGNORE = """!*
.git/
"""

# git scopes every command to one repository through the environment. A vault
# command can run from inside another repository's hook, where GIT_DIR already
# points elsewhere — `git init <vault>` would then re-initialize that
# repository and leave the vault without one.
GIT_SCOPE_VARS = (
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_COMMON_DIR",
    "GIT_OBJECT_DIRECTORY",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    "GIT_NAMESPACE",
)

# The task grammar. Any Markdown bullet reads as a task; writes always use
# "-". A due date is the calendar emoji and an ISO date, and nothing else in
# the line is given meaning — a section is whatever heading sits above it.
DUE_SIGIL = "📅"
TASK_RE = re.compile(r"^(?P<indent>\s*)[-*+] \[(?P<mark>[ xX])\](?P<text> .*)?$")
HEADING_RE = re.compile(r"^(?P<hashes>#{1,6})\s+(?P<text>.*?)\s*$")
FENCE_RE = re.compile(r"^\s*(`{3,}|~{3,})")
DUE_RE = re.compile(rf"\s*{DUE_SIGIL}\s*(\d{{4}}-\d{{2}}-\d{{2}})")
DAILY_NOTE_RE = re.compile(r"^daily/(\d{4}-\d{2}-\d{2})\.md$")
ISO_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
RELATIVE_RE = re.compile(r"^(\d+)d$")
WEEKDAYS = (
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
    "sunday",
)
DATE_FORMS = "today, tmr, a weekday (fri or friday), 3d, or YYYY-MM-DD"

# A due date names a day, and the day is the person's to spend: a task due
# today reads `today` until the afternoon and `overdue` after it. The line
# sits at 15:00 unless $VAULT_OVERDUE_AFTER moves it.
OVERDUE_AFTER_VAR = "VAULT_OVERDUE_AFTER"
DEFAULT_OVERDUE_AFTER = time(15, 0)
CUTOFF_RE = re.compile(r"^(\d{1,2}):(\d{2})$")
CUTOFF_FORM = f"HH:MM on a 24-hour clock (the default is {DEFAULT_OVERDUE_AFTER:%H:%M})"

VAULT_DIRS = ("assets", "daily", "meetings", "people", "projects", "public")
VAULT_FILES = {".gitignore": GITIGNORE, ".ignore": IGNORE}

# Templates ship next to this script and deploy to
# $XDG_CONFIG_HOME/vault/templates. Every template but daily.md opens with a
# `type:`/`dir:` header that the Neovim note-creation layer strips before
# handing the body to obsidian.nvim; daily.md carries no header because
# obsidian.nvim reads it verbatim as the daily-note template.
FALLBACK_TEMPLATES = ("daily.md",)


# ---------------------------------------------------------------------- git
def git_env() -> dict[str, str]:
    return {
        name: value for name, value in os.environ.items() if name not in GIT_SCOPE_VARS
    }


def git(cwd: Path, *args: str) -> str | None:
    result = subprocess.run(
        ["git", "-C", str(cwd), *args],
        check=False,
        text=True,
        capture_output=True,
        env=git_env(),
    )
    return result.stdout.strip() if result.returncode == 0 else None


def remote_basename(url: str) -> str:
    name = url.rstrip("/").rsplit("/", 1)[-1].rsplit(":", 1)[-1]
    return name.removesuffix(".git")


def git_project(cwd: Path) -> str:
    """A task's project: the basename of the repository's remote.

    Two remotes whose basenames collide would share one project directory.
    Saying so needs a remembered mapping from remote to directory, and this
    CLI keeps no state at all, so nothing here can name the other remote.
    """
    if git(cwd, "rev-parse", "--show-toplevel") is None:
        raise SystemExit(
            f"not a git repository: {cwd} — a task's project is its remote's basename"
        )
    url = git(cwd, "remote", "get-url", "origin")
    if url is None:
        remotes = (git(cwd, "remote") or "").split()
        if not remotes:
            raise SystemExit(
                f"no git remote in {cwd} — a task's project is its remote's basename"
            )
        if len(remotes) > 1:
            raise SystemExit(
                f"several remotes in {cwd} and no origin: {', '.join(remotes)}"
            )
        url = git(cwd, "remote", "get-url", remotes[0])
    name = remote_basename(url or "")
    if not name:
        raise SystemExit(f"no project name in the git remote: {url}")
    return name


def git_branch(cwd: Path) -> str:
    branch = git(cwd, "rev-parse", "--abbrev-ref", "HEAD")
    if not branch or branch == "HEAD":
        raise SystemExit(f"no branch checked out in {cwd} — --branch names a heading")
    return branch


# -------------------------------------------------------------- vault paths
def vault_target(path_arg: str | None) -> Path:
    """The vault a command acts on. May not exist yet — `init` creates it."""
    if path_arg:
        return Path(path_arg).expanduser().resolve()
    raw = os.environ.get("VAULT_DIR")
    if not raw:
        raise SystemExit(VAULT_DIR_UNSET)
    # Physical, so a vault reached through a symlinked ancestor (/var on
    # macOS) compares equal to the same vault reached directly.
    return Path(raw).expanduser().resolve()


def existing_vault() -> Path:
    vault = vault_target(None)
    if not vault.is_dir():
        raise SystemExit(f"VAULT_DIR points at a missing directory: {vault}")
    return vault


def markdown_files(root: Path) -> list[Path]:
    """Every note under `root`, in a stable order.

    Hidden directories are skipped: .git/ and .obsidian/ hold no notes, and
    ripgrep skips them too, so `check` can compare the two walks directly.
    """
    found: list[Path] = []
    for directory, subdirs, names in os.walk(root):
        subdirs[:] = sorted(name for name in subdirs if not name.startswith("."))
        for name in sorted(names):
            if name.endswith(".md") and not name.startswith("."):
                found.append(Path(directory) / name)
    return found


# --------------------------------------------------------- markdown grammar
@dataclass
class Heading:
    index: int  # 0-based line index
    level: int
    text: str


@dataclass
class Entry:
    index: int
    text: str
    done: bool
    due: date | None


@dataclass
class Outline:
    headings: list[Heading]
    entries: list[Entry]


def read_lines(path: Path) -> list[str] | None:
    """A note's lines, or None when the file is not text this can read."""
    try:
        return path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError):
        return None


def split_due(text: str) -> tuple[str, date | None]:
    match = DUE_RE.search(text)
    if not match:
        return text, None
    try:
        due = date.fromisoformat(match.group(1))
    except ValueError:
        return text, None  # an impossible date stays part of the text
    return (text[: match.start()] + text[match.end() :]).strip(), due


def daily_note_date(relative: str) -> date | None:
    """Infer a due date from a daily note's canonical filename."""
    match = DAILY_NOTE_RE.fullmatch(relative)
    if not match:
        return None
    try:
        return date.fromisoformat(match.group(1))
    except ValueError:
        return None


def outline(lines: list[str]) -> Outline:
    """Headings and tasks in line order, blind to anything inside a fence.

    Notes quote Markdown — this plan does it a dozen times — so a fenced
    `- [ ]` is a code sample, not a task, and a fenced `#` is not a section.
    """
    headings: list[Heading] = []
    entries: list[Entry] = []
    fence = ""
    for index, line in enumerate(lines):
        fenced = FENCE_RE.match(line)
        if fenced:
            marker = fenced.group(1)
            if not fence:
                fence = marker
            elif marker[0] == fence[0]:
                fence = ""
            continue
        if fence:
            continue
        heading = HEADING_RE.match(line)
        if heading and heading.group("text"):
            headings.append(
                Heading(index, len(heading.group("hashes")), heading.group("text"))
            )
            continue
        task = TASK_RE.match(line)
        if task:
            text, due = split_due((task.group("text") or "").strip())
            entries.append(Entry(index, text, task.group("mark") != " ", due))
    return Outline(headings, entries)


# -------------------------------------------------------------------- dates
def parse_date(value: str, today: date) -> date:
    """Every spelling of a due date, resolved once so no consumer repeats it.

    A weekday counts today as its own next occurrence: asked for `fri` on a
    Friday, a person means today.
    """
    text = value.strip().lower()
    if text == "today":
        return today
    if text in ("tmr", "tomorrow"):
        return today + timedelta(days=1)
    ahead = RELATIVE_RE.match(text)
    if ahead:
        return today + timedelta(days=int(ahead.group(1)))
    if len(text) >= 3:
        for weekday, name in enumerate(WEEKDAYS):
            if name.startswith(text):
                return today + timedelta(days=(weekday - today.weekday()) % 7)
    if ISO_RE.match(text):
        try:
            return date.fromisoformat(text)
        except ValueError:
            pass
    raise SystemExit(f"cannot read {value!r} as a date — use {DATE_FORMS}")


# -------------------------------------------------------------------- tasks
def local_today() -> date:
    """Today on this machine's clock."""
    return datetime.now().astimezone().date()


def overdue_cutoff() -> time:
    """The time a task due today turns overdue, from $VAULT_OVERDUE_AFTER.

    Unreadable settings are refused rather than replaced by the default: a
    person who spelled the hour wrong wants the hour they meant, and a
    silent 15:00 would look like the setting worked.
    """
    raw = os.environ.get(OVERDUE_AFTER_VAR, "").strip()
    if not raw:
        return DEFAULT_OVERDUE_AFTER
    written = CUTOFF_RE.match(raw)
    if written:
        try:
            return time(int(written.group(1)), int(written.group(2)))
        except ValueError:
            pass
    raise SystemExit(f"cannot read {raw!r} as {OVERDUE_AFTER_VAR} — use {CUTOFF_FORM}")


def local_past_cutoff() -> bool:
    """Whether this machine's clock has passed today's cutoff."""
    return datetime.now().astimezone().time() >= overdue_cutoff()


def due_state(due: date | None, today: date, past_cutoff: bool) -> str:
    if due is None:
        return "none"
    days = (due - today).days
    if days < 0:
        return "overdue"
    if days == 0:
        return "overdue" if past_cutoff else "today"
    if days == 1:
        return "tomorrow"
    return "near" if days <= 7 else "later"


@dataclass
class Task:
    file: str  # vault-relative
    line: int  # 1-based
    text: str
    done: bool
    due: date | None
    section: str | None
    project: str | None

    @property
    def id(self) -> str:
        return f"{self.file}:{self.line}"

    def row(self, today: date, past_cutoff: bool) -> dict[str, object]:
        return {
            "id": self.id,
            "text": self.text,
            "done": self.done,
            "due": self.due.isoformat() if self.due else None,
            "state": due_state(self.due, today, past_cutoff),
            "project": self.project,
            "section": self.section,
            "file": self.file,
            "line": self.line,
        }


def project_of(relative: str) -> str | None:
    parts = PurePosixPath(relative).parts
    return parts[1] if len(parts) > 2 and parts[0] == "projects" else None


def file_tasks(relative: str, lines: list[str]) -> list[Task]:
    document = outline(lines)
    project = project_of(relative)
    default_due = daily_note_date(relative)
    headings, cursor = document.headings, 0
    section: str | None = None
    tasks: list[Task] = []
    for entry in document.entries:
        while cursor < len(headings) and headings[cursor].index < entry.index:
            section = headings[cursor].text
            cursor += 1
        tasks.append(
            Task(
                relative,
                entry.index + 1,
                entry.text,
                entry.done,
                entry.due or default_due,
                section,
                project,
            )
        )
    return tasks


def vault_tasks(vault: Path) -> list[Task]:
    tasks: list[Task] = []
    for path in markdown_files(vault):
        lines = read_lines(path)
        if lines is not None:
            tasks.extend(file_tasks(path.relative_to(vault).as_posix(), lines))
    return tasks


def command_tasks(as_json: bool) -> int:
    vault = existing_vault()
    today = local_today()
    past_cutoff = local_past_cutoff()
    tasks = vault_tasks(vault)
    if as_json:
        rows = [task.row(today, past_cutoff) for task in tasks]
        print(json.dumps(rows, ensure_ascii=False, indent=2))
        return 0
    print(render_tasks(tasks, today, past_cutoff) if tasks else "no tasks")
    return 0


# ------------------------------------------------------------- task writing
def read_keepends(path: Path) -> list[str]:
    # Line endings are kept so rewriting one line leaves every other byte of
    # the note exactly as its author left it.
    with path.open(encoding="utf-8", newline="") as handle:
        return handle.read().splitlines(keepends=True)


def write_lines(path: Path, lines: list[str]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        handle.write("".join(lines))


@dataclass
class Location:
    path: Path
    relative: str
    number: int  # 1-based
    lines: list[str]  # line endings included
    content: str  # the task line, without its ending
    ending: str
    done: bool
    mark_at: int  # where the checkbox character sits in `content`

    @property
    def id(self) -> str:
        return f"{self.relative}:{self.number}"

    def rewrite(self, content: str) -> None:
        self.lines[self.number - 1] = content + self.ending
        write_lines(self.path, self.lines)
        print(f"{self.id}  {content.strip()}")


def resolve_id(vault: Path, task_id: str) -> Location:
    """Find the line an id names, and prove it is still a task."""
    relative, _, number = task_id.rpartition(":")
    if not relative or not number.isdigit():
        raise SystemExit(f"{task_id!r} is not a task id — expected <path>:<line>")
    path = (vault / relative).resolve()
    if not path.is_relative_to(vault) or not path.is_file():
        raise SystemExit(f"no such note in the vault: {relative}")

    lines = read_keepends(path)
    index = int(number) - 1
    stripped = [line.rstrip("\r\n") for line in lines]
    # Ids move whenever a file above them changes, and the whole design
    # recomputes rather than remembers them. Re-parse before writing so a
    # stale id fails loudly instead of editing whatever now sits there.
    entry = next(
        (item for item in outline(stripped).entries if item.index == index), None
    )
    if entry is None:
        raise SystemExit(
            f"{task_id} is not a task line — ids move when a file changes; "
            "re-run `vault tasks` for current ones"
        )
    match = TASK_RE.match(stripped[index])
    assert match is not None  # outline() matched the same line
    return Location(
        path=path,
        relative=relative,
        number=index + 1,
        lines=lines,
        content=stripped[index],
        ending=lines[index][len(stripped[index]) :],
        done=entry.done,
        mark_at=match.start("mark"),
    )


def section_bounds(
    document: Outline, total: int, heading: Heading | None
) -> tuple[int, int]:
    """The lines a task belongs among: under a heading, or above the first
    `##` when the task has no heading of its own."""
    if heading is None:
        first = document.headings[0] if document.headings else None
        start = first.index + 1 if first and first.level == 1 else 0
        end = next((item.index for item in document.headings if item.level >= 2), total)
        return start, max(start, end)
    end = next(
        (
            item.index
            for item in document.headings
            if item.index > heading.index and item.level <= heading.level
        ),
        total,
    )
    return heading.index + 1, end


def insert_task(
    lines: list[str], heading: str | None, entry: str
) -> tuple[list[str], int]:
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    document = outline([line.rstrip("\r\n") for line in lines])

    target: Heading | None = None
    if heading is not None:
        target = next(
            (item for item in document.headings if item.text == heading), None
        )
        if target is None:
            if lines and lines[-1].strip():
                lines.append("\n")
            lines.append(f"## {heading}\n")
            target = Heading(len(lines) - 1, 2, heading)
            document = Outline([*document.headings, target], document.entries)

    start, end = section_bounds(document, len(lines), target)
    point = end
    while point > start and not lines[point - 1].strip():
        point -= 1
    block = [entry + "\n"]
    if point > 0 and HEADING_RE.match(lines[point - 1].rstrip("\r\n")):
        block.insert(0, "\n")
    lines[point:point] = block
    return lines, point + len(block)


def task_line(text: str, due: date | None) -> str:
    entry = f"- [ ] {text}"
    return entry if due is None else f"{entry} {DUE_SIGIL} {due.isoformat()}"


def command_add(vault: Path, text: str, due_value: str | None, branch: bool) -> int:
    text = " ".join(text.split())
    if not text:
        raise SystemExit("a task needs some text")
    due = parse_date(due_value, local_today()) if due_value else None
    cwd = Path.cwd()
    project = git_project(cwd)
    heading = git_branch(cwd) if branch else None

    path = vault / "projects" / project / "TODO.md"
    if path.exists():
        lines = read_keepends(path)
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        lines = [f"# {project}\n"]

    entry = task_line(text, due)
    lines, number = insert_task(lines, heading, entry)
    write_lines(path, lines)
    print(f"{path.relative_to(vault).as_posix()}:{number}  {entry}")
    return 0


def command_done(vault: Path, task_id: str) -> int:
    location = resolve_id(vault, task_id)
    if location.done:
        print(f"already done: {location.id}")
        return 0
    content = location.content
    location.rewrite(
        content[: location.mark_at] + "x" + content[location.mark_at + 1 :]
    )
    return 0


def command_due(vault: Path, task_id: str, value: str) -> int:
    due = parse_date(value, local_today())
    location = resolve_id(vault, task_id)
    undated = DUE_RE.sub("", location.content).rstrip()
    location.rewrite(f"{undated} {DUE_SIGIL} {due.isoformat()}")
    return 0


# --------------------------------------------------------------------- init
def templates_dir() -> Path:
    config = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(config) / "vault" / "templates"


def shipped_templates() -> tuple[str, ...]:
    """Template names this installation expects to find deployed."""
    local = Path(__file__).resolve().parent / "templates"
    if not local.is_dir():
        return FALLBACK_TEMPLATES
    return tuple(sorted(path.name for path in local.glob("*.md")))


def command_init(path_arg: str | None, in_place: bool) -> int:
    vault = vault_target(path_arg)
    if vault.exists() and not in_place and any(vault.iterdir()):
        raise SystemExit(
            f"{vault} exists and is not empty — "
            "use `vault init --in-place` to add only what is missing"
        )

    created: list[str] = []
    vault.mkdir(parents=True, exist_ok=True)
    for name in VAULT_DIRS:
        directory = vault / name
        if not directory.exists():
            directory.mkdir()
            created.append(f"{name}/")
    for name, contents in VAULT_FILES.items():
        note = vault / name
        if not note.exists():
            note.write_text(contents, encoding="utf-8")
            created.append(name)
    if not (vault / ".git").exists():
        # init never clones: a personal repository URL has no place in the
        # dotfiles. install.sh asks for one when a human is driving.
        result = subprocess.run(
            ["git", "init", "-q", str(vault)],
            check=False,
            capture_output=True,
            env=git_env(),
        )
        if result.returncode != 0:
            raise SystemExit(f"git init failed in {vault}")
        created.append(".git/")

    if not created:
        print(f"{vault} already conforms")
        return 0
    print(f"vault {vault}")
    for name in created:
        print(f"  create {name}")
    return 0


# -------------------------------------------------------------------- check
@dataclass
class Finding:
    level: str  # "ok", "warn", or "fail"
    message: str
    detail: str = ""


def ripgrep_notes(vault: Path) -> set[str] | None:
    """What obsidian.nvim's search can see, asked the way it asks."""
    result = subprocess.run(
        ["rg", "--no-config", "--type=md", "--files"],
        cwd=vault,
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode > 1:  # 1 is "no matches", not a failure
        return None
    return {line for line in result.stdout.splitlines() if line.endswith(".md")}


def check_ignore(vault: Path) -> Finding:
    if not (vault / ".ignore").is_file():
        return Finding(
            "fail",
            "no .ignore",
            "ripgrep then skips every gitignored note and the vault looks "
            "empty to Neovim; `vault init --in-place` writes it",
        )
    visible = ripgrep_notes(vault)
    if visible is None:
        return Finding("fail", "ripgrep failed to list the vault")
    walked = {path.relative_to(vault).as_posix() for path in markdown_files(vault)}
    hidden = sorted(walked - visible)
    if hidden:
        sample = ", ".join(hidden[:3])
        if len(hidden) > 3:
            sample += f", and {len(hidden) - 3} more"
        return Finding(
            "fail",
            f".ignore leaves {len(hidden)} note(s) invisible to Neovim",
            sample,
        )
    return Finding("ok", f".ignore re-includes {len(walked)} note(s)")


def check_templates() -> Finding:
    directory = templates_dir()
    if not directory.is_dir():
        return Finding(
            "fail",
            f"no template directory: {directory}",
            "re-run install.sh to deploy it",
        )
    missing = [name for name in shipped_templates() if not (directory / name).exists()]
    if missing:
        return Finding(
            "fail",
            f"template path does not resolve: {', '.join(missing)}",
            f"expected under {directory}",
        )
    return Finding("ok", f"templates resolve under {directory}")


def check_obsidian(vault: Path) -> list[Finding]:
    findings: list[Finding] = []
    ancestors = [parent for parent in vault.parents if (parent / ".obsidian").is_dir()]
    if ancestors:
        findings.append(
            Finding(
                "warn",
                f".obsidian/ in an ancestor of the vault: {ancestors[0]}",
                "obsidian.nvim walks upward for it; the workspace is strict, "
                "but other tools are not",
            )
        )

    gitignore = vault / ".gitignore"
    if not gitignore.is_file():
        findings.append(
            Finding("warn", "no .gitignore", "every note is a commit candidate")
        )
    elif ".obsidian/" not in gitignore.read_text(encoding="utf-8").split():
        findings.append(
            Finding(
                "warn",
                ".obsidian/ missing from .gitignore",
                "the Obsidian application writes a versioned schema there",
            )
        )

    nested: list[str] = []
    for directory, subdirs, _ in os.walk(vault):
        if ".git" in subdirs:
            subdirs.remove(".git")
        if ".obsidian" in subdirs:
            subdirs.remove(".obsidian")
            if Path(directory) != vault:
                nested.append(Path(directory).relative_to(vault).as_posix())
    if nested:
        findings.append(
            Finding(
                "warn",
                f"nested .obsidian/ under {', '.join(sorted(nested))}",
                "only the vault root should ever hold one",
            )
        )
    return findings


def command_check() -> int:
    vault = existing_vault()
    findings = [Finding("ok", f"vault {vault}")]
    if shutil.which("rg") is None:
        findings.append(
            Finding(
                "fail",
                "ripgrep (rg) is not on PATH",
                "note search, quick-switch, backlinks, and tags all shell out to it",
            )
        )
    else:
        findings.append(check_ignore(vault))
    findings.append(check_templates())
    findings.extend(check_obsidian(vault))

    for finding in findings:
        print(render_finding(finding))
    return 1 if any(finding.level == "fail" for finding in findings) else 0


# ---------------------------------------------------------------- rendering
def paint(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if COLOR and code and text else text


LEVEL_COLORS = {"ok": "32", "warn": "33", "fail": "31"}

# The rail's due-state palette, in the terminal's approximation of it: overdue
# red, today and tomorrow peach, near-term mauve.
STATE_COLORS = {
    "overdue": "31",
    "today": "33",
    "tomorrow": "33",
    "near": "35",
    "later": "2",
}


@dataclass
class Row:
    prefix: str
    label: str
    metric: str = ""
    state: str = ""
    done: bool = False
    kind: str = "task"


def task_rows(
    tasks: list[Task], indent: str, last: bool, today: date, past_cutoff: bool
) -> list[Row]:
    rows = []
    for position, task in enumerate(tasks):
        final = last and position == len(tasks) - 1
        state = due_state(task.due, today, past_cutoff)
        rows.append(
            Row(
                prefix=indent + ("└── " if final else "├── "),
                label=f"[{'x' if task.done else ' '}] {task.text}",
                metric="" if task.due is None else f"{state} {task.due.isoformat()}",
                state=state,
                done=task.done,
            )
        )
    return rows


def render_tasks(tasks: list[Task], today: date, past_cutoff: bool) -> str:
    """One tree per file, one branch per section, in document order."""
    rows: list[Row] = []
    for file, in_file in groupby(tasks, key=lambda task: task.file):
        rows.append(Row("", file, kind="file"))
        sections = [
            (section, list(items))
            for section, items in groupby(in_file, key=lambda task: task.section)
        ]
        for position, (section, items) in enumerate(sections):
            last = position == len(sections) - 1
            if section is None:
                rows.extend(task_rows(items, "", last, today, past_cutoff))
                continue
            rows.append(Row("└── " if last else "├── ", section, kind="section"))
            rows.extend(
                task_rows(items, "    " if last else "│   ", True, today, past_cutoff)
            )

    width = max(len("TASK"), *(len(row.prefix + row.label) for row in rows))
    lines = [f"{paint('1', 'TASK'.ljust(width))}  {paint('1', 'DUE')}"]
    for row in rows:
        if row.kind == "file":
            label = paint("36", row.label)
        elif row.kind == "section":
            label = paint("1", row.label)
        else:
            label = paint("2", row.label) if row.done else row.label
        padding = " " * (width - len(row.prefix) - len(row.label))
        metric = (
            paint(STATE_COLORS.get(row.state, ""), row.metric) if row.metric else ""
        )
        lines.append(f"{paint('2', row.prefix)}{label}{padding}  {metric}".rstrip())
    return "\n".join(lines)


def render_finding(finding: Finding) -> str:
    label = paint(LEVEL_COLORS[finding.level], f"{finding.level:<4}")
    line = f"{label}  {finding.message}"
    return f"{line}\n      {paint('2', finding.detail)}" if finding.detail else line


# --------------------------------------------------------------------- main
def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    subparsers = parser.add_subparsers(dest="command", required=True)

    tasks = subparsers.add_parser("tasks", help="every task in the vault")
    tasks.add_argument("--json", action="store_true", help="one row per task")
    tasks.add_argument(
        "--color",
        choices=("auto", "always", "never"),
        default="auto",
        help="ANSI color use",
    )

    task = subparsers.add_parser("task", help="add or change one task")
    task_commands = task.add_subparsers(dest="task_command", required=True)

    add = task_commands.add_parser("add", help="add a task to this project")
    add.add_argument("text", help="the task, without the checkbox or the date")
    add.add_argument("--due", metavar="DATE", help=f"one of: {DATE_FORMS}")
    add.add_argument(
        "--branch",
        action="store_true",
        help="file it under a heading named for the current branch",
    )

    done = task_commands.add_parser("done", help="complete a task")
    done.add_argument("id", metavar="ID", help="<path>:<line>, from `vault tasks`")

    due = task_commands.add_parser("due", help="reschedule a task")
    due.add_argument("id", metavar="ID", help="<path>:<line>, from `vault tasks`")
    due.add_argument("date", metavar="DATE", help=f"one of: {DATE_FORMS}")

    init = subparsers.add_parser("init", help="create a conforming vault")
    init.add_argument(
        "path", nargs="?", help="where to create it (default: $VAULT_DIR)"
    )
    init.add_argument(
        "--in-place",
        action="store_true",
        help="add only what is missing from an existing directory",
    )

    check = subparsers.add_parser("check", help="validate $VAULT_DIR")
    check.add_argument(
        "--color",
        choices=("auto", "always", "never"),
        default="auto",
        help="ANSI color use",
    )
    return parser.parse_args(argv)


def main() -> int:
    args = parse_args()
    global COLOR
    color = getattr(args, "color", "never")
    COLOR = color == "always" or (
        color == "auto" and sys.stdout.isatty() and not os.environ.get("NO_COLOR")
    )
    if args.command == "tasks":
        return command_tasks(args.json)
    if args.command == "task":
        vault = existing_vault()
        if args.task_command == "add":
            return command_add(vault, args.text, args.due, args.branch)
        if args.task_command == "done":
            return command_done(vault, args.id)
        return command_due(vault, args.id, args.date)
    if args.command == "init":
        return command_init(args.path, args.in_place)
    return command_check()


if __name__ == "__main__":
    sys.exit(main())
