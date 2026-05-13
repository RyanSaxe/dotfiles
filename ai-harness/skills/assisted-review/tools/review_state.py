"""Shared Git state helpers for assisted-review tools."""

from __future__ import annotations

import hashlib
import subprocess
import time
from pathlib import Path

HEAD_CACHE_TTL_SECONDS = 60

_head_cache: dict[str, tuple[str, float]] = {}


def current_head(repo_root: str | Path) -> str | None:
    """Return the current HEAD commit SHA for a Git repo, if available."""
    repo_root_s = str(repo_root)
    now = time.time()
    cached = _head_cache.get(repo_root_s)
    if cached and now - cached[1] < HEAD_CACHE_TTL_SECONDS:
        return cached[0]

    try:
        result = subprocess.run(
            ["git", "-C", repo_root_s, "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
            timeout=2,
        )
    except (
        subprocess.CalledProcessError,
        subprocess.TimeoutExpired,
        FileNotFoundError,
    ):
        return None

    sha = result.stdout.strip()
    _head_cache[repo_root_s] = (sha, now)
    return sha


def current_repo_fingerprint(repo_root: str | Path) -> str | None:
    """Return a fingerprint for the current checked-out folder state."""
    repo_root_s = str(repo_root)
    h = hashlib.sha256()
    try:
        head = subprocess.run(
            ["git", "-C", repo_root_s, "rev-parse", "HEAD"],
            capture_output=True,
            check=False,
            timeout=2,
        )
        h.update(b"HEAD\0")
        h.update(head.stdout.strip() if head.returncode == 0 else b"")

        diff = subprocess.run(
            ["git", "-C", repo_root_s, "diff", "HEAD", "--binary"],
            capture_output=True,
            check=False,
            timeout=10,
        )
        h.update(b"\0DIFF\0")
        h.update(diff.stdout)

        untracked = subprocess.run(
            [
                "git",
                "-C",
                repo_root_s,
                "ls-files",
                "--others",
                "--exclude-standard",
                "-z",
            ],
            capture_output=True,
            check=False,
            timeout=5,
        )
        h.update(b"\0UNTRACKED\0")
        if untracked.returncode == 0:
            repo_root_p = Path(repo_root_s).resolve()
            for raw in sorted(p for p in untracked.stdout.split(b"\0") if p):
                rel = raw.decode("utf-8", errors="surrogateescape")
                path = (repo_root_p / rel).resolve()
                try:
                    path.relative_to(repo_root_p)
                    h.update(raw)
                    h.update(b"\0")
                    h.update(path.read_bytes())
                except (OSError, ValueError):
                    h.update(b"<unreadable>")
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None
    return h.hexdigest()
