#!/usr/bin/env -S uv run -q --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["tiktoken"]
# ///
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from collections.abc import Callable, Iterable, Sequence
from dataclasses import dataclass, field
from pathlib import Path
from typing import Protocol

TOKEN_ENCODING = "o200k_base"


class TokenEncoding(Protocol):
    def encode(
        self, text: str, *, disallowed_special: tuple[str, ...] = ()
    ) -> list[int]: ...


_token_encoding: TokenEncoding | None = None


@dataclass
class Node:
    name: str
    is_dir: bool = True
    loc: int = 0
    tokens: int = 0
    added: int = 0
    deleted: int = 0
    binary: bool = False
    binary_count: int = 0
    children: dict[str, "Node"] = field(default_factory=dict)

    def child(self, name: str, *, is_dir: bool) -> "Node":
        if name not in self.children:
            self.children[name] = Node(name=name, is_dir=is_dir)
        return self.children[name]


@dataclass
class RenderRow:
    tree_prefix: str
    node: Node
    root: bool = False

    @property
    def plain_path(self) -> str:
        return f"{self.tree_prefix}{self.node.name}"


class Colors:
    def __init__(self, enabled: bool) -> None:
        self.enabled = enabled

    def paint(self, text: str, code: str) -> str:
        if not self.enabled:
            return text
        return f"\033[{code}m{text}\033[0m"

    def dim(self, text: str) -> str:
        return self.paint(text, "2")

    def bold(self, text: str) -> str:
        return self.paint(text, "1")

    def directory(self, text: str) -> str:
        return self.paint(text, "36")

    def size(self, text: str) -> str:
        return self.paint(text, "33")

    def add(self, text: str) -> str:
        return self.paint(text, "32")

    def delete(self, text: str) -> str:
        return self.paint(text, "31")

    def binary(self, text: str) -> str:
        return self.paint(text, "35")


def add_common_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "path", nargs="?", default=".", help="file or directory to summarize"
    )
    parser.add_argument("--depth", type=int, default=1, help="tree depth to display")
    parser.add_argument(
        "--color",
        choices=("auto", "always", "never"),
        default="auto",
        help="when to emit ANSI colors",
    )
    parser.add_argument("--no-color", action="store_true", help="disable ANSI colors")


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Show Git-visible repository size metrics as a tree."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    loc_parser = subparsers.add_parser(
        "loc", help="show text line counts or git diff line deltas"
    )
    add_common_arguments(loc_parser)
    loc_parser.add_argument(
        "--diff",
        nargs="?",
        const="HEAD",
        default=None,
        metavar="TARGET",
        help=(
            "show git diff +added/-deleted lines against TARGET; with no TARGET, "
            "defaults to HEAD"
        ),
    )

    tokens_parser = subparsers.add_parser(
        "tokens", help=f"show token counts using {TOKEN_ENCODING}"
    )
    add_common_arguments(tokens_parser)

    args = parser.parse_args(argv)
    if args.depth < 0:
        parser.error("--depth must be 0 or greater")
    if args.no_color:
        args.color = "never"
    return args


def color_enabled(mode: str) -> bool:
    if mode == "always":
        return True
    if mode == "never" or os.environ.get("NO_COLOR"):
        return False
    return sys.stdout.isatty()


def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def nearest_existing_parent(path: Path) -> Path:
    candidate = path if path.is_dir() else path.parent
    candidate = candidate.expanduser().resolve(strict=False)
    while not candidate.exists() and candidate != candidate.parent:
        candidate = candidate.parent
    return candidate


def git_root_for(path: Path) -> Path:
    start = nearest_existing_parent(path)
    result = run(["git", "-C", str(start), "rev-parse", "--show-toplevel"])
    if result.returncode != 0:
        raise SystemExit("repo_size must be run inside a git repository")
    return Path(result.stdout.strip()).resolve()


def rel_to_git_root(path: Path, git_root: Path) -> str:
    resolved = path.expanduser().resolve(strict=False)
    try:
        rel = resolved.relative_to(git_root)
    except ValueError:
        raise SystemExit(f"{path} is outside git root {git_root}") from None
    return "." if str(rel) == "." else rel.as_posix()


def display_root_name(path_arg: str) -> str:
    if path_arg in {"", "."}:
        return "."
    path = Path(path_arg).expanduser()
    return path.name or path_arg


def is_binary(path: Path) -> bool:
    try:
        with path.open("rb") as handle:
            return b"\0" in handle.read(4096)
    except OSError:
        return True


def read_text_bytes(path: Path) -> bytes:
    try:
        return path.read_bytes()
    except OSError:
        return b""


def count_lines(path: Path) -> int:
    data = read_text_bytes(path)
    if not data:
        return 0
    lines = data.count(b"\n")
    return lines if data.endswith(b"\n") else lines + 1


def get_token_encoding() -> TokenEncoding:
    global _token_encoding
    if _token_encoding is None:
        import tiktoken

        _token_encoding = tiktoken.get_encoding(TOKEN_ENCODING)
    return _token_encoding


def count_tokens(path: Path) -> int:
    data = read_text_bytes(path)
    if not data:
        return 0
    encoding = get_token_encoding()
    text = data.decode("utf-8", errors="replace")
    return len(encoding.encode(text, disallowed_special=()))


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

    files = []
    for raw in result.stdout.split("\0"):
        if not raw:
            continue
        candidate = git_root / raw
        if candidate.is_file() and not is_binary(candidate):
            files.append(candidate)
    return files


def path_context(path_arg: str) -> tuple[Path, str, str, Path]:
    target = Path(path_arg).expanduser()
    git_root = git_root_for(target)
    pathspec = rel_to_git_root(target, git_root)
    root_name = display_root_name(path_arg)
    base = (git_root / pathspec).resolve(strict=False) if pathspec != "." else git_root
    return git_root, pathspec, root_name, base


def add_loc(root: Node, parts: Iterable[str], loc: int) -> None:
    root.loc += loc
    node = root
    parts_list = list(parts)
    for index, part in enumerate(parts_list):
        node = node.child(part, is_dir=index < len(parts_list) - 1)
        node.loc += loc


def add_tokens(root: Node, parts: Iterable[str], tokens: int) -> None:
    root.tokens += tokens
    node = root
    parts_list = list(parts)
    for index, part in enumerate(parts_list):
        node = node.child(part, is_dir=index < len(parts_list) - 1)
        node.tokens += tokens


def build_loc_tree(path_arg: str) -> Node:
    git_root, pathspec, root_name, base = path_context(path_arg)
    target = Path(path_arg).expanduser()
    root = Node(name=root_name, is_dir=not target.is_file())

    for file in git_visible_files(git_root, pathspec):
        try:
            rel_parts = file.resolve().relative_to(base).parts
        except ValueError:
            continue
        add_loc(root, rel_parts, count_lines(file))
    return root


def build_token_tree(path_arg: str) -> Node:
    git_root, pathspec, root_name, base = path_context(path_arg)
    target = Path(path_arg).expanduser()
    root = Node(name=root_name, is_dir=not target.is_file())

    for file in git_visible_files(git_root, pathspec):
        try:
            rel_parts = file.resolve().relative_to(base).parts
        except ValueError:
            continue
        add_tokens(root, rel_parts, count_tokens(file))
    return root


def git_diff_numstat(git_root: Path, target: str, pathspec: str) -> str:
    cmd = [
        "git",
        "-C",
        str(git_root),
        "-c",
        "core.quotePath=false",
        "diff",
        "--numstat",
        target,
        "--",
        pathspec,
    ]
    result = run(cmd)
    if result.returncode != 0:
        raise SystemExit(result.stderr.strip() or "git diff failed")
    return result.stdout


def simplify_numstat_path(path: str) -> str:
    while " => " in path:
        match = re.search(r"\{([^{}]*?) => ([^{}]*?)\}", path)
        if match:
            path = f"{path[: match.start()]}{match.group(2)}{path[match.end() :]}"
            continue
        path = path.split(" => ", 1)[1]
    return path


def add_diff(
    root: Node, parts: Iterable[str], added: int, deleted: int, *, binary: bool
) -> None:
    if binary:
        root.binary_count += 1
    else:
        root.added += added
        root.deleted += deleted

    node = root
    parts_list = list(parts)
    for index, part in enumerate(parts_list):
        is_dir = index < len(parts_list) - 1
        node = node.child(part, is_dir=is_dir)
        if binary:
            node.binary_count += 1
            if not is_dir:
                node.binary = True
        else:
            node.added += added
            node.deleted += deleted


def build_diff_tree(path_arg: str, target: str) -> Node:
    path = Path(path_arg).expanduser()
    git_root = git_root_for(path)
    pathspec = rel_to_git_root(path, git_root)
    root = Node(name=display_root_name(path_arg), is_dir=True)
    selected = Path(pathspec) if pathspec != "." else Path(".")

    for line in git_diff_numstat(git_root, target, pathspec).splitlines():
        fields = line.split("\t", 2)
        if len(fields) != 3:
            continue
        added_raw, deleted_raw, raw_path = fields
        changed_path = Path(simplify_numstat_path(raw_path))
        try:
            rel_path = (
                changed_path.relative_to(selected)
                if selected != Path(".")
                else changed_path
            )
        except ValueError:
            continue
        binary = added_raw == "-" or deleted_raw == "-"
        add_diff(
            root,
            rel_path.parts,
            0 if binary else int(added_raw),
            0 if binary else int(deleted_raw),
            binary=binary,
        )
    return root


def sorted_children(node: Node) -> list[Node]:
    return sorted(
        node.children.values(), key=lambda child: (not child.is_dir, child.name.lower())
    )


def humanize(value: int) -> str:
    absolute = abs(value)
    for scale, suffix in ((1_000_000_000, "b"), (1_000_000, "m"), (1_000, "k")):
        if absolute >= scale:
            return f"{value / scale:.1f}{suffix}"
    return str(value)


def format_loc(node: Node, colors: Colors) -> str:
    return colors.size(humanize(node.loc))


def format_tokens(node: Node, colors: Colors) -> str:
    return colors.size(humanize(node.tokens))


def binary_marker(colors: Colors) -> str:
    return colors.binary("(binary)")


def format_diff(node: Node, colors: Colors) -> str:
    if node.added == 0 and node.deleted == 0 and node.binary_count:
        return binary_marker(colors)

    added = colors.add(f"+{humanize(node.added)}")
    deleted = colors.delete(f"-{humanize(node.deleted)}")
    metric = f"{added}/{deleted}"
    if node.binary_count:
        return f"{metric} {binary_marker(colors)}"
    return metric


def format_name(node: Node, colors: Colors, *, root: bool) -> str:
    name = colors.directory(node.name) if node.is_dir else node.name
    return colors.bold(name) if root else name


def visible_rows(root: Node, depth: int) -> list[RenderRow]:
    rows = [RenderRow(tree_prefix="", node=root, root=True)]

    def visit(node: Node, prefix: str, level: int) -> None:
        if level >= depth:
            return
        children = sorted_children(node)
        for index, child in enumerate(children):
            is_last = index == len(children) - 1
            connector = "└── " if is_last else "├── "
            next_prefix = "    " if is_last else "│   "
            rows.append(RenderRow(tree_prefix=prefix + connector, node=child))
            visit(child, prefix + next_prefix, level + 1)

    visit(root, "", 0)
    return rows


MetricFormatter = Callable[[Node, Colors], str]


def render_tree(root: Node, *, depth: int, mode: str, colors: Colors) -> str:
    metrics: dict[str, tuple[MetricFormatter, str]] = {
        "diff": (format_diff, "DIFF"),
        "loc": (format_loc, "TOTAL"),
        "tokens": (format_tokens, "TOKENS"),
    }
    metric, metric_header = metrics[mode]
    rows = visible_rows(root, depth)
    path_width = max(len("PATH"), *(len(row.plain_path) for row in rows))
    gap = "  "
    lines = [
        f"{colors.bold('PATH'.ljust(path_width))}{gap}{colors.bold(metric_header)}",
    ]

    for row in rows:
        tree_prefix = colors.dim(row.tree_prefix) if row.tree_prefix else ""
        path = f"{tree_prefix}{format_name(row.node, colors, root=row.root)}"
        padding = " " * (path_width - len(row.plain_path))
        lines.append(f"{path}{padding}{gap}{metric(row.node, colors)}")

    return "\n".join(lines)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    colors = Colors(color_enabled(args.color))
    if args.command == "tokens":
        root = build_token_tree(args.path)
        mode = "tokens"
    elif args.diff is None:
        root = build_loc_tree(args.path)
        mode = "loc"
    else:
        root = build_diff_tree(args.path, args.diff)
        mode = "diff"
    print(render_tree(root, depth=args.depth, mode=mode, colors=colors))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
