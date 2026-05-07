#!/usr/bin/env -S uv run -q --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml"]
# ///
"""Submit a review YAML to GitHub via `gh api`.

Modes:
  uv run --script submit.py <path>                      — send full review
  uv run --script submit.py <path> --thread-id rev-001  — send a single thread
  uv run --script submit.py <path> --dry-run            — print the payload, don't POST

On success (non-dry-run), prints the API response's `html_url` to stdout.
The viewer is responsible for rewriting the local YAML afterward (removing
the sent thread, or archiving the whole file).

Exits non-zero with the gh error printed verbatim on failure; the local
YAML is left untouched.
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

import yaml

SKIP_STATUSES = {"resolved", "wontfix"}
SENDABLE_ANCHOR_STATUSES = {"current", "moved"}


def parse_remote_url(url: str) -> tuple[str, str] | None:
    """Extract (owner, repo) from a git remote URL. Supports SSH and HTTPS."""
    # git@github.com:owner/repo.git  OR  https://github.com/owner/repo.git
    m = re.match(
        r"(?:git@github\.com:|https://github\.com/)([^/]+)/([^/]+?)(?:\.git)?/?$", url
    )
    if not m:
        return None
    return m.group(1), m.group(2)


def resolve_owner_repo(repo_root: str, remote_name: str | None) -> tuple[str, str]:
    """Resolve owner/repo from `gh repo view` (works without parsing remotes)."""
    result = subprocess.run(
        [
            "gh",
            "repo",
            "view",
            "--json",
            "owner,name",
            "-q",
            '.owner.login + "/" + .name',
        ],
        cwd=repo_root,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode == 0 and result.stdout.strip():
        owner, repo = result.stdout.strip().split("/", 1)
        return owner, repo

    # Fallback: parse the remote URL directly.
    remote_arg = remote_name or "origin"
    result = subprocess.run(
        ["git", "-C", repo_root, "remote", "get-url", remote_arg],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"could not resolve owner/repo: {result.stderr.strip()}")

    parsed = parse_remote_url(result.stdout.strip())
    if parsed is None:
        raise RuntimeError(f"unrecognized remote URL: {result.stdout.strip()!r}")
    return parsed


def target_owner_repo(target: dict[str, Any]) -> tuple[str, str]:
    owner = target.get("owner")
    repo = target.get("repo")
    if isinstance(owner, str) and owner and isinstance(repo, str) and repo:
        return owner, repo
    return resolve_owner_repo(target["repo_root"], target.get("remote"))


def has_suggestion(thread: dict[str, Any]) -> bool:
    return "suggestion" in thread


def submission_block_reason(thread: dict[str, Any]) -> str | None:
    status = thread.get("status", "open")
    if status in SKIP_STATUSES:
        return f"status is {status!r}"

    anchor_status = thread.get("anchor_status", "current")
    if anchor_status not in SENDABLE_ANCHOR_STATUSES:
        return f"anchor_status is {anchor_status!r}"

    return None


def build_thread_payload(c: dict[str, Any]) -> dict[str, Any]:
    """Map a review YAML thread to the GitHub Reviews API per-comment shape."""
    body = c["body"].rstrip()
    if has_suggestion(c):
        suggestion = c["suggestion"].rstrip("\n")
        body = f"{body}\n\n```suggestion\n{suggestion}\n```"

    payload: dict[str, Any] = {
        "path": c["file"],
        "body": body,
        "side": "RIGHT",
    }
    if c.get("start_line") and c.get("start_line") != c.get("line"):
        payload["start_line"] = c["start_line"]
        payload["start_side"] = "RIGHT"
    payload["line"] = c["line"]
    return payload


def build_review_payload(
    review_data: dict[str, Any],
    only_thread_id: str | None,
) -> dict[str, Any]:
    """Build the full POST body for /pulls/{n}/reviews."""
    target = review_data["target"]
    review = review_data["review"]
    threads = review["threads"]

    if only_thread_id is not None:
        threads = [c for c in threads if c["id"] == only_thread_id]
        if not threads:
            raise RuntimeError(f"thread id {only_thread_id!r} not found in review")
        reason = submission_block_reason(threads[0])
        if reason is not None:
            raise RuntimeError(
                f"thread id {only_thread_id!r} is not submittable: {reason}"
            )
    else:
        threads = [c for c in threads if c.get("status") not in SKIP_STATUSES]
        if not threads:
            raise RuntimeError("nothing to send — every thread is resolved or wontfix")
        blocked = [
            (c["id"], reason)
            for c in threads
            if (reason := submission_block_reason(c)) is not None
        ]
        if blocked:
            details = ", ".join(
                f"{thread_id} ({reason})" for thread_id, reason in blocked
            )
            raise RuntimeError(f"cannot send review with stale threads: {details}")

    return {
        "commit_id": target["commit"],
        "event": review["event"],
        "body": review.get("summary", "").rstrip(),
        "comments": [build_thread_payload(c) for c in threads],
    }


def submit(
    path: Path, only_thread_id: str | None, dry_run: bool = False
) -> dict[str, Any]:
    data = yaml.safe_load(path.read_text())
    target = data["target"]

    pr_number = target.get("pr_number")
    if not pr_number and not dry_run:
        raise RuntimeError(
            "target.pr_number is not set — review is local-only, nothing to submit"
        )

    payload = build_review_payload(data, only_thread_id)

    if dry_run:
        # Skip owner/repo lookup (may not be a real repo) — just emit the payload.
        return {
            "_dry_run": True,
            "pr_number": pr_number,
            "payload": payload,
        }

    owner, repo = target_owner_repo(target)
    api_path = f"repos/{owner}/{repo}/pulls/{pr_number}/reviews"
    result = subprocess.run(
        ["gh", "api", api_path, "-X", "POST", "--input", "-"],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        check=False,
    )

    if result.returncode != 0:
        raise RuntimeError(
            f"gh api failed:\n{result.stderr.strip()}\n{result.stdout.strip()}"
        )

    return json.loads(result.stdout)


def main() -> int:
    parser = argparse.ArgumentParser(description="Submit a review YAML to GitHub.")
    parser.add_argument("path", type=Path, help="Path to the review YAML file.")
    parser.add_argument(
        "--comment-id",
        default=None,
        help="Deprecated alias for --thread-id.",
    )
    parser.add_argument(
        "--thread-id",
        default=None,
        help="If set, send only this thread instead of the full review.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the JSON payload that would be POSTed and exit, without calling gh.",
    )
    args = parser.parse_args()

    try:
        thread_id = args.thread_id or args.comment_id
        response = submit(args.path, thread_id, dry_run=args.dry_run)
    except (RuntimeError, FileNotFoundError, KeyError) as e:
        print(f"submit failed: {e}", file=sys.stderr)
        return 1

    if args.dry_run:
        print(json.dumps(response, indent=2))
    else:
        print(response.get("html_url", json.dumps(response, indent=2)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
