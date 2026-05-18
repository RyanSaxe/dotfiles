#!/usr/bin/env -S uv run -q --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml"]
# ///
"""Validate a review YAML file against the schema documented in
references/schema.md.

Exit 0 on success; non-zero with one error message per line on failure.
Usage: python validate.py [--require-current-state] <path-to-review.yaml>
"""

import argparse
import re
import sys
from pathlib import Path
from typing import Any

import yaml
from yaml.nodes import MappingNode, Node, ScalarNode, SequenceNode

from review_state import current_head, current_repo_fingerprint

VALID_SEVERITIES = {"info", "low", "medium", "high", "critical"}
VALID_STATUSES = {"open", "acknowledged", "resolved", "wontfix"}
VALID_EVENTS = {"COMMENT", "REQUEST_CHANGES", "APPROVE", "PENDING"}
VALID_TARGET_KINDS = {"local", "pr"}
VALID_AUTHORS = {"ai", "user"}
VALID_THREAD_TYPES = {"comment", "note"}
VALID_CONFIDENCES = {"low", "medium", "high"}
VALID_ANCHOR_STATUSES = {"current", "moved", "missing", "ambiguous"}
ID_PATTERN = re.compile(r"^rev-\d{3}$")
FINGERPRINT_PATTERN = re.compile(r"^[0-9a-f]{64}$")
CANONICAL_BLOCK_KEYS = {"body", "anchor_text", "suggestion"}


def _load_yaml(path: Path) -> tuple[dict[str, Any] | None, list[str]]:
    """Load a review file and return `(data, errors)`."""
    errors: list[str] = []

    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as e:
        return None, [f"YAML parse error: {e}"]
    except OSError as e:
        return None, [f"file read error: {e}"]

    if not isinstance(data, dict):
        return None, ["root must be a mapping"]

    return data, errors


def line_range(thread: dict[str, Any]) -> tuple[int, int] | None:
    line = thread.get("line")
    start = thread.get("start_line") or line
    if not isinstance(start, int) or not isinstance(line, int):
        return None
    if start < 1 or line < start:
        return None
    return start, line


def text_for_range(lines: list[str], start: int, end: int) -> str:
    return "\n".join(lines[start - 1 : end])


def validate_target(data: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    target = data.get("target", {})
    if not isinstance(target, dict):
        return ["target must be a mapping"]

    for key in ("kind", "repo_root"):
        if key not in target:
            errors.append(f"target.{key} is required")

    kind = target.get("kind")
    if kind is not None and kind not in VALID_TARGET_KINDS:
        errors.append(
            f"target.kind must be one of {sorted(VALID_TARGET_KINDS)}, got {kind!r}"
        )

    # owner/repo are required when pr_number is set: they power the
    # topbar PR link in the viewer.
    if target.get("pr_number") is not None:
        for key in ("owner", "repo"):
            if not target.get(key):
                errors.append(f"target.{key} is required when target.pr_number is set")

    fingerprint = target.get("fingerprint")
    if fingerprint is not None:
        if not isinstance(fingerprint, str):
            errors.append(
                f"target.fingerprint must be a 64-character lowercase SHA-256 hex string, got {type(fingerprint).__name__}"
            )
        elif not FINGERPRINT_PATTERN.match(fingerprint):
            errors.append(
                "target.fingerprint must be a 64-character lowercase SHA-256 hex string"
            )

    return errors


def validate_review_header(review: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    event = review.get("event")
    if event not in VALID_EVENTS:
        errors.append(
            f"review.event must be one of {sorted(VALID_EVENTS)}, got {event!r}"
        )

    for required in ("summary", "note", "threads"):
        if required not in review:
            errors.append(f"review.{required} is required")

    if "summary" in review:
        errors.extend(validate_overview_block(review, "summary"))
    if "note" in review:
        errors.extend(validate_overview_block(review, "note"))

    return errors


def validate_overview_block(review: dict[str, Any], key: str) -> list[str]:
    errors: list[str] = []
    block = review.get(key)
    prefix = f"review.{key}"
    if not isinstance(block, dict):
        return [f"{prefix} must be a mapping"]

    author = block.get("author")
    if author not in VALID_AUTHORS:
        errors.append(
            f"{prefix}.author must be one of {sorted(VALID_AUTHORS)}, got {author!r}"
        )

    if not isinstance(block.get("body"), str):
        errors.append(f"{prefix}.body must be a string")

    replies = block.get("replies")
    if not isinstance(replies, list):
        errors.append(f"{prefix}.replies must be a list")
    else:
        errors.extend(validate_replies(block, prefix))

    return errors


def validate_thread_id(
    thread: dict[str, Any], prefix: str, seen_ids: set[str]
) -> list[str]:
    cid = thread.get("id")
    if cid is None:
        return [f"{prefix}.id is required"]
    if not ID_PATTERN.match(cid):
        return [f"{prefix}.id must match rev-NNN (zero-padded), got {cid!r}"]
    if cid in seen_ids:
        return [f"{prefix}.id duplicate: {cid!r}"]

    seen_ids.add(cid)
    return []


def validate_required_thread_fields(thread: dict[str, Any], prefix: str) -> list[str]:
    errors: list[str] = []
    for required in (
        "author",
        "type",
        "file",
        "severity",
        "category",
        "confidence",
        "body",
        "status",
        "anchor_text",
        "anchor_status",
    ):
        if required not in thread:
            errors.append(f"{prefix}.{required} is required")
    return errors


def validate_enum_fields(thread: dict[str, Any], prefix: str) -> list[str]:
    errors: list[str] = []
    enum_fields = (
        ("author", VALID_AUTHORS),
        ("type", VALID_THREAD_TYPES),
        ("severity", VALID_SEVERITIES),
        ("confidence", VALID_CONFIDENCES),
        ("status", VALID_STATUSES),
        ("anchor_status", VALID_ANCHOR_STATUSES),
    )
    for field, valid_values in enum_fields:
        value = thread.get(field)
        if value is not None and value not in valid_values:
            errors.append(
                f"{prefix}.{field} must be one of {sorted(valid_values)}, got {value!r}"
            )
    return errors


def validate_replies(thread: dict[str, Any], prefix: str) -> list[str]:
    replies = thread.get("replies", [])
    if replies is None:
        replies = []
    if not isinstance(replies, list):
        return [f"{prefix}.replies must be a list when set"]

    errors: list[str] = []
    for j, reply in enumerate(replies):
        reply_prefix = f"{prefix}.replies[{j}]"
        if not isinstance(reply, dict):
            errors.append(f"{reply_prefix} must be a mapping")
            continue

        reply_author = reply.get("author")
        if reply_author not in VALID_AUTHORS:
            errors.append(
                f"{reply_prefix}.author must be one of {sorted(VALID_AUTHORS)}, got {reply_author!r}"
            )
        if not isinstance(reply.get("body"), str):
            errors.append(f"{reply_prefix}.body must be a string")

    return errors


def validate_line_target(thread: dict[str, Any], prefix: str) -> list[str]:
    errors: list[str] = []
    line = thread.get("line")
    start = thread.get("start_line")
    if line is None:
        errors.append(f"{prefix}.line is required")
    elif not isinstance(line, int) or line < 1:
        errors.append(f"{prefix}.line must be a positive integer, got {line!r}")

    if start is None:
        return errors

    if not isinstance(start, int) or start < 1:
        errors.append(f"{prefix}.start_line must be a positive integer, got {start!r}")
    elif isinstance(line, int) and start > line:
        errors.append(f"{prefix}.start_line ({start}) must be <= line ({line})")

    return errors


def validate_thread(
    thread: dict[str, Any], prefix: str, seen_ids: set[str]
) -> list[str]:
    errors = validate_thread_id(thread, prefix, seen_ids)
    errors.extend(validate_required_thread_fields(thread, prefix))
    errors.extend(validate_enum_fields(thread, prefix))
    errors.extend(validate_replies(thread, prefix))
    errors.extend(validate_line_target(thread, prefix))

    if "anchor_text" in thread and not isinstance(thread["anchor_text"], str):
        errors.append(
            f"{prefix}.anchor_text must be a string, got {type(thread['anchor_text']).__name__}"
        )
    if thread.get("type") == "note" and "suggestion" in thread:
        errors.append(f"{prefix}.suggestion is not allowed when type is 'note'")

    return errors


def validate_schema(data: dict[str, Any]) -> list[str]:
    """Return schema errors. Empty list means valid."""
    errors: list[str] = []

    for key in ("generated_at", "target", "review"):
        if key not in data:
            errors.append(f"missing top-level key: {key}")

    errors.extend(validate_target(data))

    review = data.get("review", {})
    if not isinstance(review, dict):
        errors.append("review must be a mapping")
        return errors

    errors.extend(validate_review_header(review))

    threads = review.get("threads", [])
    if not isinstance(threads, list):
        errors.append("review.threads must be a list")
        return errors

    seen_ids: set[str] = set()
    for i, thread in enumerate(threads):
        prefix = f"threads[{i}]"
        if not isinstance(thread, dict):
            errors.append(f"{prefix} must be a mapping")
            continue
        errors.extend(validate_thread(thread, prefix, seen_ids))

    return errors


def validate_current_anchors(data: dict[str, Any]) -> list[str]:
    """Return errors for anchors that do not match the current filesystem state."""
    target = data.get("target", {})
    if not isinstance(target, dict):
        return ["target must be a mapping before anchors can be checked"]

    repo_root = target.get("repo_root")
    if not isinstance(repo_root, str) or not repo_root:
        return ["target.repo_root must be set before anchors can be checked"]

    repo_root_path = Path(repo_root).resolve()
    review = data.get("review", {})
    if not isinstance(review, dict):
        return ["review must be a mapping before anchors can be checked"]

    threads = review.get("threads", [])
    if not isinstance(threads, list):
        return ["review.threads must be a list before anchors can be checked"]

    errors: list[str] = []
    for i, thread in enumerate(threads):
        prefix = f"threads[{i}]"
        if not isinstance(thread, dict):
            continue

        rel_file = thread.get("file")
        anchor_text = thread.get("anchor_text")
        current_range = line_range(thread)
        if (
            not isinstance(rel_file, str)
            or not isinstance(anchor_text, str)
            or current_range is None
        ):
            continue

        if thread.get("anchor_status") != "current":
            errors.append(
                f"{prefix}.anchor_status must be 'current' when current anchors are required"
            )

        source_path = (repo_root_path / rel_file).resolve()
        try:
            source_path.relative_to(repo_root_path)
        except ValueError:
            errors.append(
                f"{prefix}.file points outside target.repo_root: {rel_file!r}"
            )
            continue

        try:
            lines = source_path.read_text(encoding="utf-8").split("\n")
        except (OSError, UnicodeDecodeError) as e:
            errors.append(f"{prefix}.file cannot be read for anchor check: {e}")
            continue

        start, end = current_range
        if end > len(lines):
            errors.append(
                f"{prefix}.line range {start}-{end} exceeds {rel_file} length {len(lines)}"
            )
            continue

        actual = text_for_range(lines, start, end)
        if actual != anchor_text:
            errors.append(
                f"{prefix}.anchor_text does not match current source at {rel_file}:{start}-{end}"
            )

    return errors


def validate_current_fingerprint(data: dict[str, Any]) -> list[str]:
    """Return errors when target.fingerprint does not match current repo state."""
    target = data.get("target", {})
    if not isinstance(target, dict):
        return ["target must be a mapping before fingerprint can be checked"]

    repo_root = target.get("repo_root")
    if not isinstance(repo_root, str) or not repo_root:
        return ["target.repo_root must be set before fingerprint can be checked"]

    fingerprint = target.get("fingerprint")
    if not isinstance(fingerprint, str) or not FINGERPRINT_PATTERN.match(fingerprint):
        return [
            "target.fingerprint must be set to a 64-character lowercase SHA-256 hex string when current fingerprint is required"
        ]

    current = current_repo_fingerprint(repo_root)
    if current is None:
        return [
            "target.fingerprint could not be checked because repo state could not be fingerprinted"
        ]
    if current != fingerprint:
        return [
            f"target.fingerprint does not match current repo state: expected {current}, got {fingerprint}"
        ]
    return []


def validate_current_commit(data: dict[str, Any]) -> list[str]:
    """Return errors when target.commit is present but not current HEAD."""
    target = data.get("target", {})
    if not isinstance(target, dict):
        return ["target must be a mapping before commit can be checked"]

    repo_root = target.get("repo_root")
    if not isinstance(repo_root, str) or not repo_root:
        return ["target.repo_root must be set before commit can be checked"]

    commit = target.get("commit")
    if commit is None:
        return []
    if not isinstance(commit, str) or not commit:
        return ["target.commit must be a non-empty string when set"]

    head = current_head(repo_root)
    if head is None:
        return [
            "target.commit could not be checked because current HEAD could not be resolved"
        ]
    if commit != head and not head.startswith(commit):
        return [
            f"target.commit does not match current HEAD: expected {head}, got {commit}"
        ]
    return []


def format_node_path(path: tuple[str | int, ...]) -> str:
    out = ""
    for part in path:
        if isinstance(part, int):
            out += f"[{part}]"
        elif out:
            out += f".{part}"
        else:
            out = part
    return out


def canonical_block_header(line: str, key: str) -> bool:
    return re.match(rf"^\s*{re.escape(key)}:\s*\|-\s*(?:#.*)?$", line) is not None


def visit_yaml_nodes(
    node: Node,
    path: tuple[str | int, ...],
) -> list[tuple[tuple[str | int, ...], str, Node]]:
    out: list[tuple[tuple[str | int, ...], str, Node]] = []
    if isinstance(node, MappingNode):
        for key_node, value_node in node.value:
            key = key_node.value if isinstance(key_node, ScalarNode) else ""
            next_path = (*path, key)
            if key in CANONICAL_BLOCK_KEYS:
                out.append((next_path, key, value_node))
            out.extend(visit_yaml_nodes(value_node, next_path))
    elif isinstance(node, SequenceNode):
        for i, item in enumerate(node.value):
            out.extend(visit_yaml_nodes(item, (*path, i)))
    return out


def validate_canonical_yaml(path: Path) -> list[str]:
    """Return errors for review text that does not use the canonical YAML subset."""
    try:
        text = path.read_text(encoding="utf-8")
        root = yaml.compose(text)
    except yaml.YAMLError as e:
        return [f"YAML parse error: {e}"]
    except OSError as e:
        return [f"file read error: {e}"]

    if root is None:
        return ["root must be a mapping"]

    lines = text.splitlines()
    errors: list[str] = []
    for scalar_path, key, value_node in visit_yaml_nodes(root, ()):
        prefix = format_node_path(scalar_path)
        if not isinstance(value_node, ScalarNode):
            errors.append(f"{prefix} must be a literal block scalar using `|-`")
            continue
        if value_node.style != "|":
            errors.append(f"{prefix} must use a literal block scalar using `|-`")
            continue
        line = lines[value_node.start_mark.line]
        if not canonical_block_header(line, key):
            errors.append(
                f"{prefix} must use strip chomping style `|-`, not `{line.strip()}`"
            )

    return errors


def validate(
    path: Path,
    *,
    require_current_anchors: bool = False,
    require_current_fingerprint: bool = False,
    require_current_state: bool = False,
    require_canonical_yaml: bool = False,
) -> list[str]:
    """Return a list of human-readable errors. Empty list = valid."""
    data, errors = _load_yaml(path)
    if data is None:
        return errors

    errors.extend(validate_schema(data))
    if require_canonical_yaml or require_current_state:
        errors.extend(validate_canonical_yaml(path))
    if require_current_anchors or require_current_state:
        errors.extend(validate_current_anchors(data))
    if require_current_fingerprint or require_current_state:
        errors.extend(validate_current_fingerprint(data))
    if require_current_state:
        errors.extend(validate_current_commit(data))
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate an assisted-review YAML file."
    )
    parser.add_argument(
        "--require-current-anchors",
        action="store_true",
        help=(
            "Require every thread's anchor_text to exactly match the current source lines. "
            "Use --require-current-state for freshly generated reviews; this narrower "
            "flag is useful when canonical YAML or fingerprint checks are intentionally separate."
        ),
    )
    parser.add_argument(
        "--require-current-fingerprint",
        action="store_true",
        help="Require target.fingerprint to match the current repo state.",
    )
    parser.add_argument(
        "--require-canonical-yaml",
        action="store_true",
        help="Require multiline review text fields to use literal block scalars with strip chomping (`|-`).",
    )
    parser.add_argument(
        "--require-current-state",
        action="store_true",
        help=(
            "Fresh-review strict mode: require canonical YAML, current anchors, "
            "current fingerprint, and target.commit matching current HEAD."
        ),
    )
    parser.add_argument("path", type=Path, help="Path to the review YAML file.")
    args = parser.parse_args()

    errors = validate(
        args.path,
        require_current_anchors=args.require_current_anchors,
        require_current_fingerprint=args.require_current_fingerprint,
        require_current_state=args.require_current_state,
        require_canonical_yaml=args.require_canonical_yaml,
    )

    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return 1

    print(f"ok: {args.path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
