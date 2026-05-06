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
    for key in ("version", "generated_at", "target", "review"):
        if key not in data:
            errors.append(f"missing top-level key: {key}")

    if data.get("version") != 1:
        errors.append(f"version must be 1, got {data.get('version')!r}")

    target = data.get("target", {})
    if not isinstance(target, dict):
        errors.append("target must be a mapping")
    else:
        for key in ("repo_root", "commit"):
            if key not in target:
                errors.append(f"target.{key} is required")
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

    for required in ("summary", "comments"):
        if required not in review:
            errors.append(f"review.{required} is required")

    comments = review.get("comments", [])
    if not isinstance(comments, list):
        errors.append("review.comments must be a list")
        return errors

    seen_ids: set[str] = set()
    for i, c in enumerate(comments):
        prefix = f"comments[{i}]"
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

        for required in ("file", "severity", "category", "body", "status"):
            if required not in c:
                errors.append(f"{prefix}.{required} is required")

        sev = c.get("severity")
        if sev is not None and sev not in VALID_SEVERITIES:
            errors.append(
                f"{prefix}.severity must be one of {sorted(VALID_SEVERITIES)}, got {sev!r}"
            )

        status = c.get("status")
        if status is not None and status not in VALID_STATUSES:
            errors.append(
                f"{prefix}.status must be one of {sorted(VALID_STATUSES)}, got {status!r}"
            )

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
