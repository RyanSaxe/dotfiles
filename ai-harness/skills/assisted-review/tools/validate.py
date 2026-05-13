#!/usr/bin/env -S uv run -q --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml"]
# ///
"""Validate a review YAML file against the schema documented in
references/schema.md.

Exit 0 on success; non-zero with one error message per line on failure.
Usage: python validate.py [--require-current-anchors] <path-to-review.yaml>
"""

import argparse
import re
import sys
from pathlib import Path
from typing import Any

import yaml

VALID_SEVERITIES = {"info", "low", "medium", "high", "critical"}
VALID_STATUSES = {"open", "acknowledged", "resolved", "wontfix"}
VALID_EVENTS = {"COMMENT", "REQUEST_CHANGES", "APPROVE", "PENDING"}
VALID_TARGET_KINDS = {"local", "pr"}
VALID_AUTHORS = {"ai", "user"}
VALID_THREAD_TYPES = {"comment", "note"}
VALID_CONFIDENCES = {"low", "medium", "high"}
VALID_ANCHOR_STATUSES = {"current", "moved", "missing", "ambiguous"}
ID_PATTERN = re.compile(r"^rev-\d{3}$")


def _load_yaml(path: Path) -> tuple[dict[str, Any] | None, list[str]]:
    """Load a review file and return `(data, errors)`."""
    errors: list[str] = []

    try:
        data = yaml.safe_load(path.read_text())
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
            lines = source_path.read_text().split("\n")
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


def validate(path: Path, *, require_current_anchors: bool = False) -> list[str]:
    """Return a list of human-readable errors. Empty list = valid."""
    data, errors = _load_yaml(path)
    if data is None:
        return errors

    errors.extend(validate_schema(data))
    if require_current_anchors:
        errors.extend(validate_current_anchors(data))
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
            "Use this for freshly generated reviews; omit it when validating an active review "
            "that may legitimately contain moved or stale anchors."
        ),
    )
    parser.add_argument("path", type=Path, help="Path to the review YAML file.")
    args = parser.parse_args()

    errors = validate(args.path, require_current_anchors=args.require_current_anchors)

    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return 1

    print(f"ok: {args.path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
