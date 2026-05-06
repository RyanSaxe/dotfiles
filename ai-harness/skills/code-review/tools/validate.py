#!/usr/bin/env -S uv run -q --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml"]
# ///
"""Validate a review YAML file against the schema documented in
references/schema.md.

Exit 0 on success; non-zero with one error message per line on failure.
Usage: python validate.py <path-to-review.yaml>
"""

import re
import sys
from pathlib import Path

import yaml

VALID_SEVERITIES = {"info", "low", "medium", "high", "critical"}
VALID_STATUSES = {"open", "acknowledged", "resolved", "wontfix"}
VALID_EVENTS = {"COMMENT", "REQUEST_CHANGES", "APPROVE", "PENDING"}
VALID_TARGET_KINDS = {"local", "pr"}
VALID_AUTHORS = {"ai", "user"}
VALID_CONFIDENCES = {"low", "medium", "high"}
VALID_ANCHOR_STATUSES = {"current", "moved", "missing", "ambiguous"}
ID_PATTERN = re.compile(r"^rev-\d{3}$")


def validate(path: Path) -> list[str]:
    """Return a list of human-readable errors. Empty list = valid."""
    errors: list[str] = []

    try:
        data = yaml.safe_load(path.read_text())
    except yaml.YAMLError as e:
        return [f"YAML parse error: {e}"]
    except OSError as e:
        return [f"file read error: {e}"]

    if not isinstance(data, dict):
        return ["root must be a mapping"]

    # Top-level required keys
    for key in ("generated_at", "target", "review"):
        if key not in data:
            errors.append(f"missing top-level key: {key}")

    target = data.get("target", {})
    if not isinstance(target, dict):
        errors.append("target must be a mapping")
    else:
        for key in ("kind", "repo_root"):
            if key not in target:
                errors.append(f"target.{key} is required")
        kind = target.get("kind")
        if kind is not None and kind not in VALID_TARGET_KINDS:
            errors.append(
                f"target.kind must be one of {sorted(VALID_TARGET_KINDS)}, got {kind!r}"
            )
        # owner/repo are required when pr_number is set — they power the
        # topbar PR link in the viewer. Without them the link can't be
        # built and we'd be back to the rev-001 bug.
        if target.get("pr_number") is not None:
            for key in ("owner", "repo"):
                if not target.get(key):
                    errors.append(
                        f"target.{key} is required when target.pr_number is set"
                    )

    review = data.get("review", {})
    if not isinstance(review, dict):
        errors.append("review must be a mapping")
        return errors

    event = review.get("event")
    if event not in VALID_EVENTS:
        errors.append(
            f"review.event must be one of {sorted(VALID_EVENTS)}, got {event!r}"
        )

    for required in ("summary", "threads"):
        if required not in review:
            errors.append(f"review.{required} is required")

    threads = review.get("threads", [])
    if not isinstance(threads, list):
        errors.append("review.threads must be a list")
        return errors

    seen_ids: set[str] = set()
    for i, c in enumerate(threads):
        prefix = f"threads[{i}]"
        if not isinstance(c, dict):
            errors.append(f"{prefix} must be a mapping")
            continue

        cid = c.get("id")
        if cid is None:
            errors.append(f"{prefix}.id is required")
        elif not ID_PATTERN.match(cid):
            errors.append(f"{prefix}.id must match rev-NNN (zero-padded), got {cid!r}")
        elif cid in seen_ids:
            errors.append(f"{prefix}.id duplicate: {cid!r}")
        else:
            seen_ids.add(cid)

        for required in (
            "author",
            "file",
            "severity",
            "category",
            "confidence",
            "body",
            "status",
            "anchor_text",
            "anchor_status",
        ):
            if required not in c:
                errors.append(f"{prefix}.{required} is required")

        author = c.get("author")
        if author is not None and author not in VALID_AUTHORS:
            errors.append(
                f"{prefix}.author must be one of {sorted(VALID_AUTHORS)}, got {author!r}"
            )

        sev = c.get("severity")
        if sev is not None and sev not in VALID_SEVERITIES:
            errors.append(
                f"{prefix}.severity must be one of {sorted(VALID_SEVERITIES)}, got {sev!r}"
            )

        confidence = c.get("confidence")
        if confidence is not None and confidence not in VALID_CONFIDENCES:
            errors.append(
                f"{prefix}.confidence must be one of {sorted(VALID_CONFIDENCES)}, got {confidence!r}"
            )

        status = c.get("status")
        if status is not None and status not in VALID_STATUSES:
            errors.append(
                f"{prefix}.status must be one of {sorted(VALID_STATUSES)}, got {status!r}"
            )

        anchor_status = c.get("anchor_status")
        if anchor_status is not None and anchor_status not in VALID_ANCHOR_STATUSES:
            errors.append(
                f"{prefix}.anchor_status must be one of {sorted(VALID_ANCHOR_STATUSES)}, got {anchor_status!r}"
            )

        if "anchor_text" in c and not isinstance(c["anchor_text"], str):
            errors.append(
                f"{prefix}.anchor_text must be a string, got {type(c['anchor_text']).__name__}"
            )

        replies = c.get("replies", [])
        if replies is None:
            replies = []
        if not isinstance(replies, list):
            errors.append(f"{prefix}.replies must be a list when set")
        else:
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

        # Line targeting
        line = c.get("line")
        start = c.get("start_line")
        if line is None:
            errors.append(f"{prefix}.line is required")
        elif not isinstance(line, int) or line < 1:
            errors.append(f"{prefix}.line must be a positive integer, got {line!r}")
        if start is not None:
            if not isinstance(start, int) or start < 1:
                errors.append(
                    f"{prefix}.start_line must be a positive integer, got {start!r}"
                )
            elif isinstance(line, int) and start > line:
                errors.append(f"{prefix}.start_line ({start}) must be <= line ({line})")

    return errors


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <path-to-review.yaml>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    errors = validate(path)

    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return 1

    print(f"ok: {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
