#!/usr/bin/env -S uv run -q --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["tiktoken"]
# ///
"""Git-visible repository size as a tree: lines, LLM tokens, or diff churn.

    repo-size loc [path] [--depth N]
    repo-size tokens [path] [--depth N]
    repo-size diff [path] [--against REV] [--depth N]

Files are what git sees (tracked plus untracked-unignored). Binary files are
skipped in loc/tokens and shown as "(binary)" in diff mode.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

TOKEN_ENCODING = "o200k_base"
COLOR = False  # set from --color in main()


@dataclass
class Node:
    name: str
    is_dir: bool = True
    value: int = 0  # line count, token count, or diff-added lines
    deleted: int = 0  # diff mode only
    binary: bool = False
    binary_count: int = 0
    children: dict[str, Node] = field(default_factory=dict)

    def child(self, name: str, *, is_dir: bool) -> Node:
        if name not in self.children:
            self.children[name] = Node(name=name, is_dir=is_dir)
        return self.children[name]

    def add(
        self,
        parts: tuple[str, ...],
        value: int,
        deleted: int = 0,
        *,
        binary: bool = False,
    ) -> None:
        node = self
        for depth, part in enumerate((self.name, *parts)):
            if depth:
                node = node.child(part, is_dir=depth < len(parts))
            if binary:
                node.binary_count += 1
                node.binary = not node.is_dir
            else:
                node.value += value
                node.deleted += deleted


# ------------------------------------------------------------------- git
def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, check=False, text=True, capture_output=True)


def git_root_for(path: Path) -> Path:
    start = path if path.is_dir() else path.parent
    result = run(["git", "-C", str(start), "rev-parse", "--show-toplevel"])
    if result.returncode != 0:
        raise SystemExit("repo-size must be run inside a git repository")
    return Path(result.stdout.strip()).resolve()


def is_binary(path: Path) -> bool:
    try:
        with path.open("rb") as handle:
            return b"\0" in handle.read(4096)
    except OSError:
        return True


def git_visible_files(git_root: Path, pathspec: str) -> list[Path]:
    result = run(
        [
            "git",
            "-C",
            str(git_root),
            "ls-files",
            "-co",
            "--exclude-standard",
            "-z",
            "--",
            pathspec,
        ]
    )
    if result.returncode != 0:
        raise SystemExit(result.stderr.strip() or "git ls-files failed")
    files = [git_root / raw for raw in result.stdout.split("\0") if raw]
    return [f for f in files if f.is_file() and not is_binary(f)]


# ---------------------------------------------------------------- counting
def count_lines(path: Path) -> int:
    try:
        data = path.read_bytes()
    except OSError:
        return 0
    if not data:
        return 0
    return data.count(b"\n") + (0 if data.endswith(b"\n") else 1)


def make_token_counter():
    import tiktoken

    encoding = tiktoken.get_encoding(TOKEN_ENCODING)

    def count(path: Path) -> int:
        try:
            text = path.read_bytes().decode("utf-8", errors="replace")
        except OSError:
            return 0
        return len(encoding.encode(text, disallowed_special=()))

    return count


# ------------------------------------------------------------------ trees
@dataclass
class Target:
    git_root: Path
    pathspec: str  # git pathspec relative to the root, "." for the whole repo
    base: Path  # filesystem base that tree paths are shown relative to
    root_name: str


def resolve_target(path_arg: str) -> Target:
    path = Path(path_arg).expanduser()
    git_root = git_root_for(path)
    resolved = path.resolve()
    try:
        rel = resolved.relative_to(git_root)
    except ValueError:
        raise SystemExit(f"{path_arg} is outside git root {git_root}") from None
    pathspec = "." if str(rel) == "." else rel.as_posix()
    name = "." if path_arg in {"", "."} else (path.name or path_arg)
    return Target(git_root, pathspec, resolved, name)


def build_count_tree(target: Target, count) -> Node:
    root = Node(name=target.root_name, is_dir=target.base.is_dir())
    for file in git_visible_files(target.git_root, target.pathspec):
        try:
            parts = file.resolve().relative_to(target.base).parts
        except ValueError:
            continue
        root.add(parts, count(file))
    return root


def simplify_rename(path: str) -> str:
    # numstat renders renames as "dir/{old => new}/file" or "old => new".
    while " => " in path:
        match = re.search(r"\{[^{}]*? => ([^{}]*?)\}", path)
        if match:
            path = f"{path[: match.start()]}{match.group(1)}{path[match.end() :]}"
        else:
            path = path.split(" => ", 1)[1]
    return path


def build_diff_tree(target: Target, against: str) -> Node:
    result = run(
        [
            "git",
            "-C",
            str(target.git_root),
            "-c",
            "core.quotePath=false",
            "diff",
            "--numstat",
        ]
        + [against, "--", target.pathspec]
    )
    if result.returncode != 0:
        raise SystemExit(result.stderr.strip() or "git diff failed")

    root = Node(name=target.root_name, is_dir=True)
    selected = Path(target.pathspec)
    for line in result.stdout.splitlines():
        fields = line.split("\t", 2)
        if len(fields) != 3:
            continue
        added, deleted, raw_path = fields
        changed = Path(simplify_rename(raw_path))
        try:
            rel = changed.relative_to(selected) if target.pathspec != "." else changed
        except ValueError:
            continue
        if added == "-" or deleted == "-":
            root.add(rel.parts, 0, binary=True)
        else:
            root.add(rel.parts, int(added), int(deleted))
    return root


# -------------------------------------------------------------- rendering
def paint(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if COLOR else text


def humanize(value: int) -> str:
    for scale, suffix in ((1_000_000_000, "b"), (1_000_000, "m"), (1_000, "k")):
        if abs(value) >= scale:
            return f"{value / scale:.1f}{suffix}"
    return str(value)


def format_metric(node: Node, mode: str) -> str:
    if mode != "diff":
        return paint("33", humanize(node.value))
    marker = paint("35", "(binary)")
    if node.value == 0 and node.deleted == 0 and node.binary_count:
        return marker
    metric = f"{paint('32', f'+{humanize(node.value)}')}/{paint('31', f'-{humanize(node.deleted)}')}"
    return f"{metric} {marker}" if node.binary_count else metric


def render(root: Node, *, depth: int, mode: str) -> str:
    header = {"loc": "TOTAL", "tokens": "TOKENS", "diff": "DIFF"}[mode]
    rows: list[tuple[str, Node, bool]] = [("", root, True)]

    def visit(node: Node, prefix: str, level: int) -> None:
        if level >= depth:
            return
        children = sorted(
            node.children.values(), key=lambda c: (not c.is_dir, c.name.lower())
        )
        for index, child in enumerate(children):
            last = index == len(children) - 1
            rows.append((prefix + ("└── " if last else "├── "), child, False))
            visit(child, prefix + ("    " if last else "│   "), level + 1)

    visit(root, "", 0)
    width = max(len("PATH"), *(len(f"{p}{n.name}") for p, n, _ in rows))
    lines = [f"{paint('1', 'PATH'.ljust(width))}  {paint('1', header)}"]
    for prefix, node, is_root in rows:
        name = paint("36", node.name) if node.is_dir else node.name
        name = paint("1", name) if is_root else name
        padding = " " * (width - len(prefix) - len(node.name))
        lines.append(
            f"{paint('2', prefix)}{name}{padding}  {format_metric(node, mode)}"
        )
    return "\n".join(lines)


# ------------------------------------------------------------------- main
def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    subparsers = parser.add_subparsers(dest="command", required=True)
    for name, help_text in (
        ("loc", "text line counts"),
        ("tokens", f"LLM token counts ({TOKEN_ENCODING})"),
        ("diff", "added/deleted lines against a git revision"),
    ):
        sub = subparsers.add_parser(name, help=help_text)
        sub.add_argument(
            "path", nargs="?", default=".", help="file or directory to summarize"
        )
        sub.add_argument("--depth", type=int, default=1, help="tree depth to display")
        sub.add_argument(
            "--color",
            choices=("auto", "always", "never"),
            default="auto",
            help="ANSI color use",
        )
        if name == "diff":
            sub.add_argument(
                "--against", default="HEAD", metavar="REV", help="diff base revision"
            )
    return parser.parse_args(argv)


def main() -> int:
    args = parse_args()
    global COLOR
    COLOR = args.color == "always" or (
        args.color == "auto" and sys.stdout.isatty() and not os.environ.get("NO_COLOR")
    )
    target = resolve_target(args.path)
    if args.command == "diff":
        root = build_diff_tree(target, args.against)
    else:
        count = count_lines if args.command == "loc" else make_token_counter()
        root = build_count_tree(target, count)
    print(render(root, depth=args.depth, mode=args.command))
    return 0


if __name__ == "__main__":
    sys.exit(main())
