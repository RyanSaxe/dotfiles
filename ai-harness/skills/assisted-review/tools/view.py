#!/usr/bin/env -S uv run -q --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["ruamel.yaml", "pyyaml"]
# ///
"""Self-daemonizing HTTP server for the assisted-review viewer.

Cooperative singleton — only one instance runs at a time per machine.
Survives the launching agent's exit (Claude Code, Codex CLI, etc.) by
double-forking + setsid. Persists in `~/.cache/assisted-review/viewer.json`.

CLI:
  python view.py --ensure --open --review-path <path>
      Idempotent. Daemonize if not running, then open browser to deep link.

  python view.py --foreground
      Run in the foreground (no daemonize), logs to stderr. Ctrl-C stops.

  python view.py --stop
      Send SIGTERM to the running daemon and clean up the state file.

  python view.py --status
      Print whether a daemon is running. Exit 0 if yes, 1 if no.

See ../references/viewer-usage.md for the full lifecycle and API surface.
"""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import json
import os
import re
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
import webbrowser
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

from review_state import current_head, current_repo_fingerprint

# YAML: prefer ruamel.yaml for round-trip formatting preservation, fall
# back to pyyaml if ruamel isn't available. PEP 723 deps declare both.
try:
    from ruamel.yaml import YAML  # type: ignore[import-not-found]

    def _new_ruamel_yaml() -> YAML:
        yaml = YAML()
        yaml.preserve_quotes = True
        yaml.indent(mapping=2, sequence=4, offset=2)
        return yaml

    def yaml_load(text: str) -> Any:
        return _new_ruamel_yaml().load(text)

    def yaml_dump(data: Any) -> str:
        from io import StringIO

        buf = StringIO()
        _new_ruamel_yaml().dump(data, buf)
        return buf.getvalue()

    YAML_BACKEND = "ruamel"
except ImportError:
    import yaml as _pyyaml

    def yaml_load(text: str) -> Any:
        return _pyyaml.safe_load(text)

    def yaml_dump(data: Any) -> str:
        return _pyyaml.safe_dump(data, sort_keys=False, allow_unicode=True)

    YAML_BACKEND = "pyyaml"

# === Constants ====================================================

REVIEWS_DIR = Path.home() / ".reviews"
CACHE_DIR = Path.home() / ".cache" / "assisted-review"
STATE_FILE = CACHE_DIR / "viewer.json"
ENSURE_LOCK_FILE = CACHE_DIR / ".ensure.lock"
WEBAPP_DIR = Path(__file__).parent / "webapp"
SERVICE_SIGNATURE = "assisted-review-viewer"
VIEWER_API_VERSION = 4
DEFAULT_PORT_START = 51234
PORT_TRY_LIMIT = 10
GIT_TIMEOUT_SECONDS = 10

VALID_EVENTS = {"COMMENT", "REQUEST_CHANGES", "APPROVE", "PENDING"}
COMMENT_THREAD_TYPE = "comment"
NOTE_THREAD_TYPE = "note"

# === State file helpers ===========================================


def read_state() -> dict[str, Any] | None:
    if not STATE_FILE.exists():
        return None
    try:
        return json.loads(STATE_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def write_state(state: dict[str, Any]) -> None:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2))


def remove_state() -> None:
    try:
        STATE_FILE.unlink()
    except FileNotFoundError:
        pass


def is_pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def viewer_ping_payload(url: str) -> dict[str, Any] | None:
    """Return the viewer ping payload, or None if the URL is not a live viewer."""
    try:
        with urllib.request.urlopen(f"{url}/api/ping", timeout=1) as resp:
            payload = json.loads(resp.read())
            return payload if isinstance(payload, dict) else None
    except (OSError, json.JSONDecodeError, urllib.error.URLError):
        return None


def is_current_viewer(payload: dict[str, Any] | None) -> bool:
    """Confirm a live viewer speaks the backend/webapp contract this client expects."""
    return (
        payload is not None
        and payload.get("service") == SERVICE_SIGNATURE
        and payload.get("api_version") == VIEWER_API_VERSION
    )


def stop_pid(pid: int) -> None:
    try:
        os.kill(pid, signal.SIGTERM)
    except (OSError, TypeError):
        return
    for _ in range(20):
        if not is_pid_alive(pid):
            break
        time.sleep(0.05)


def detect_running_daemon() -> dict[str, Any] | None:
    """Return state dict for a verified-live viewer, or None."""
    state = read_state()
    if state is None:
        return None
    if not is_pid_alive(state.get("pid", 0)):
        remove_state()
        return None
    payload = viewer_ping_payload(state.get("url", ""))
    if not is_current_viewer(payload):
        if payload and payload.get("service") == SERVICE_SIGNATURE:
            stop_pid(state.get("pid", 0))
        remove_state()
        return None
    return state


# === Daemonization ================================================


def daemonize() -> None:
    """Standard double-fork to detach from controlling terminal."""
    if os.fork() > 0:
        os._exit(0)

    os.setsid()

    if os.fork() > 0:
        os._exit(0)

    os.chdir("/")
    sys.stdout.flush()
    sys.stderr.flush()
    devnull = os.open(os.devnull, os.O_RDWR)
    os.dup2(devnull, 0)
    os.dup2(devnull, 1)
    os.dup2(devnull, 2)
    os.close(devnull)


def find_free_port(start: int = DEFAULT_PORT_START) -> int:
    for offset in range(PORT_TRY_LIMIT):
        port = start + offset
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.bind(("127.0.0.1", port))
                return port
            except OSError:
                continue
    raise RuntimeError(f"no free port in {start}..{start + PORT_TRY_LIMIT - 1}")


# === Inbox / review file walking ==================================

# `key` = filename without `.review.yaml` extension.
# `slug` = parent directory under ~/.reviews/.
# Together they uniquely identify a review.

_SLUG_KEY_PATTERN = re.compile(r"^[A-Za-z0-9_.\-]+$")


def is_safe_id(s: str) -> bool:
    return bool(_SLUG_KEY_PATTERN.match(s))


def review_path(slug: str, key: str) -> Path | None:
    """Return the path for a review, or None if slug/key are invalid or absent."""
    if not is_safe_id(slug) or not is_safe_id(key):
        return None
    candidate = REVIEWS_DIR / slug / f"{key}.review.yaml"
    try:
        candidate.resolve().relative_to(REVIEWS_DIR.resolve())
    except ValueError:
        return None
    return candidate


def walk_reviews() -> list[tuple[str, str, Path]]:
    """List (slug, key, path) for every review on disk."""
    if not REVIEWS_DIR.exists():
        return []
    out: list[tuple[str, str, Path]] = []
    for slug_dir in sorted(REVIEWS_DIR.iterdir()):
        if not slug_dir.is_dir() or slug_dir.name.startswith("."):
            continue
        for review_file in sorted(slug_dir.glob("*.review.yaml")):
            key = review_file.name.removesuffix(".review.yaml")
            out.append((slug_dir.name, key, review_file))
    return out


# === Staleness =====================================================


def is_stale(target_commit: str, repo_root: str) -> bool:
    head = current_head(repo_root)
    if head is None:
        return False
    return head != target_commit


def review_is_stale(target: dict[str, Any]) -> bool:
    repo_root = target.get("repo_root", "")
    if not repo_root:
        return False

    fingerprint = target.get("fingerprint")
    if fingerprint:
        current = current_repo_fingerprint(repo_root)
        return current is not None and current != fingerprint

    target_commit = target.get("commit", "")
    return is_stale(target_commit, repo_root) if target_commit else False


def list_repo_files(repo_root: str, include_ignored: bool = False) -> list[str]:
    """Return git-visible files, optionally including ignored untracked files."""
    try:
        visible = subprocess.run(
            [
                "git",
                "-C",
                repo_root,
                "ls-files",
                "--cached",
                "--others",
                "--exclude-standard",
            ],
            capture_output=True,
            text=True,
            check=True,
            timeout=5,
        )
        files = {line for line in visible.stdout.splitlines() if line.strip()}
        if include_ignored:
            ignored = subprocess.run(
                [
                    "git",
                    "-C",
                    repo_root,
                    "ls-files",
                    "--others",
                    "--ignored",
                    "--exclude-standard",
                ],
                capture_output=True,
                text=True,
                check=True,
                timeout=5,
            )
            files.update(line for line in ignored.stdout.splitlines() if line.strip())
        return sorted(files)
    except (
        subprocess.CalledProcessError,
        subprocess.TimeoutExpired,
        FileNotFoundError,
    ):
        return []


# === Live diff access ==============================================


def git_text(
    repo_root: str,
    args: list[str],
    *,
    timeout: int = GIT_TIMEOUT_SECONDS,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", repo_root, *args],
        capture_output=True,
        text=True,
        check=False,
        timeout=timeout,
    )


def git_bytes(
    repo_root: str,
    args: list[str],
    *,
    timeout: int = GIT_TIMEOUT_SECONDS,
) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        ["git", "-C", repo_root, *args],
        capture_output=True,
        check=False,
        timeout=timeout,
    )


def resolve_commit(repo_root: str, ref: str) -> str | None:
    ref = ref.strip()
    if not ref:
        return None
    try:
        proc = git_text(repo_root, ["rev-parse", "--verify", f"{ref}^{{commit}}"])
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None
    if proc.returncode != 0:
        return None
    return proc.stdout.strip() or None


def current_branch(repo_root: str) -> str | None:
    try:
        proc = git_text(repo_root, ["rev-parse", "--abbrev-ref", "HEAD"], timeout=2)
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None
    if proc.returncode != 0:
        return None
    branch = proc.stdout.strip()
    return branch if branch and branch != "HEAD" else None


def default_base_candidates(repo_root: str, target: dict[str, Any]) -> list[str]:
    candidates: list[str] = []
    for key in ("base_ref", "base_branch"):
        value = target.get(key)
        if isinstance(value, str) and value.strip():
            candidates.append(value.strip())

    try:
        proc = git_text(
            repo_root,
            ["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"],
            timeout=2,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            candidates.append(proc.stdout.strip())
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass

    candidates.extend(
        [
            "origin/main",
            "origin/master",
            "main",
            "master",
            "HEAD",
        ]
    )
    branch = current_branch(repo_root)
    return [c for c in dict.fromkeys(candidates) if c and c != branch]


def default_base_ref(repo_root: str, target: dict[str, Any]) -> str:
    for candidate in default_base_candidates(repo_root, target):
        if resolve_commit(repo_root, candidate):
            return candidate
    return "HEAD"


def resolve_diff_base(
    repo_root: str,
    target: dict[str, Any],
    requested_base: str | None = None,
) -> dict[str, Any]:
    base_ref = (requested_base or target.get("base_ref") or "").strip()
    if not base_ref:
        base_ref = default_base_ref(repo_root, target)

    base_commit = resolve_commit(repo_root, base_ref)
    if not base_commit:
        raise RuntimeError(f"could not resolve base ref: {base_ref}")

    head_commit = resolve_commit(repo_root, "HEAD")
    comparison_base = base_commit
    if head_commit:
        try:
            merge_base = git_text(repo_root, ["merge-base", base_commit, head_commit])
            if merge_base.returncode == 0 and merge_base.stdout.strip():
                comparison_base = merge_base.stdout.strip()
        except (subprocess.TimeoutExpired, FileNotFoundError):
            comparison_base = base_commit

    return {
        "base_ref": base_ref,
        "base_commit": base_commit,
        "comparison_base": comparison_base,
        "head_commit": head_commit,
    }


def parse_name_status_z(raw: bytes) -> dict[str, dict[str, Any]]:
    tokens = [
        token.decode("utf-8", errors="surrogateescape")
        for token in raw.split(b"\0")
        if token
    ]
    out: dict[str, dict[str, Any]] = {}
    i = 0
    while i < len(tokens):
        status = tokens[i]
        code = status[:1]
        i += 1
        if code in {"R", "C"} and i + 1 < len(tokens):
            old_path = tokens[i]
            new_path = tokens[i + 1]
            i += 2
            out[new_path] = {
                "status": code,
                "status_raw": status,
                "old_path": old_path,
            }
        elif i < len(tokens):
            path = tokens[i]
            i += 1
            out[path] = {"status": code, "status_raw": status}
    return out


def parse_numstat_z(raw: bytes) -> dict[str, dict[str, int | None]]:
    tokens = [
        token.decode("utf-8", errors="surrogateescape")
        for token in raw.split(b"\0")
        if token
    ]
    out: dict[str, dict[str, int | None]] = {}
    i = 0
    while i < len(tokens):
        parts = tokens[i].split("\t", 2)
        i += 1
        if len(parts) != 3:
            continue
        added_raw, deleted_raw, path = parts
        if not path and i + 1 < len(tokens):
            # Rename/copy records encode the path fields as separate NUL tokens.
            i += 1
            path = tokens[i]
            i += 1
        additions = None if added_raw == "-" else int(added_raw or "0")
        deletions = None if deleted_raw == "-" else int(deleted_raw or "0")
        out[path] = {"additions": additions, "deletions": deletions}
    return out


def diff_pathspecs(
    repo_root: str, comparison_base: str, rel_file: str | None
) -> list[str]:
    if not rel_file:
        return []

    try:
        status_proc = git_bytes(
            repo_root,
            [
                "diff",
                "--name-status",
                "-z",
                "--find-renames",
                comparison_base,
                "--",
            ],
            timeout=10,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return [rel_file]

    if status_proc.returncode not in {0, 1}:
        return [rel_file]

    status = parse_name_status_z(status_proc.stdout).get(rel_file)
    old_path = status.get("old_path") if status else None
    if isinstance(old_path, str) and old_path and old_path != rel_file:
        return [old_path, rel_file]
    return [rel_file]


def unquote_diff_path(path: str) -> str:
    if path == "/dev/null":
        return path
    if path.startswith("a/") or path.startswith("b/"):
        return path[2:]
    return path


_HUNK_RE = re.compile(
    r"^@@ -(?P<old_start>\d+)(?:,(?P<old_lines>\d+))? "
    r"\+(?P<new_start>\d+)(?:,(?P<new_lines>\d+))? @@(?P<section>.*)$"
)


def finalize_hunk(hunk: dict[str, Any] | None) -> None:
    if not hunk:
        return
    changed = sorted(hunk.pop("_changed_new_lines", set()))
    hunk["changed_new_lines"] = changed
    if changed:
        hunk["anchor_line"] = changed[0]
    elif hunk["new_lines"] > 0:
        hunk["anchor_line"] = hunk["new_start"]
    else:
        hunk["anchor_line"] = None


def parse_unified_diff(raw: str) -> dict[str, dict[str, Any]]:
    files: dict[str, dict[str, Any]] = {}
    current: dict[str, Any] | None = None
    current_hunk: dict[str, Any] | None = None
    old_line = 0
    new_line = 0

    for line in raw.splitlines():
        if line.startswith("diff --git "):
            finalize_hunk(current_hunk)
            current_hunk = None
            current = {"file": "", "old_path": None, "hunks": []}
            old_line = 0
            new_line = 0
            continue

        if current is None:
            continue

        if line.startswith("--- "):
            path = unquote_diff_path(line[4:].split("\t", 1)[0])
            if path != "/dev/null":
                current["old_path"] = path
                if not current["file"]:
                    current["file"] = path
            continue

        if line.startswith("+++ "):
            path = unquote_diff_path(line[4:].split("\t", 1)[0])
            if path != "/dev/null":
                current["file"] = path
            elif current.get("old_path"):
                current["file"] = current["old_path"]
            if current["file"]:
                files[current["file"]] = current
            continue

        match = _HUNK_RE.match(line)
        if match:
            finalize_hunk(current_hunk)
            old_start = int(match.group("old_start"))
            new_start = int(match.group("new_start"))
            old_lines = int(match.group("old_lines") or "1")
            new_lines = int(match.group("new_lines") or "1")
            current_hunk = {
                "old_start": old_start,
                "old_lines": old_lines,
                "new_start": new_start,
                "new_lines": new_lines,
                "section": match.group("section").strip(),
                "header": line,
                "deletion_count": 0,
                "lines": [],
                "_changed_new_lines": set(),
            }
            current["hunks"].append(current_hunk)
            old_line = old_start
            new_line = new_start
            continue

        if current_hunk is None:
            continue

        if line.startswith("\\"):
            current_hunk["lines"].append(
                {"kind": "meta", "old_line": None, "new_line": None, "text": line}
            )
            continue

        marker = line[:1]
        text = line[1:] if marker in {" ", "+", "-"} else line
        if marker == "+":
            current_hunk["lines"].append(
                {
                    "kind": "add",
                    "old_line": None,
                    "new_line": new_line,
                    "text": text,
                }
            )
            current_hunk["_changed_new_lines"].add(new_line)
            new_line += 1
        elif marker == "-":
            current_hunk["lines"].append(
                {
                    "kind": "del",
                    "old_line": old_line,
                    "new_line": None,
                    "text": text,
                }
            )
            current_hunk["deletion_count"] += 1
            old_line += 1
        else:
            current_hunk["lines"].append(
                {
                    "kind": "context",
                    "old_line": old_line,
                    "new_line": new_line,
                    "text": text,
                }
            )
            old_line += 1
            new_line += 1

    finalize_hunk(current_hunk)
    return files


def untracked_files(repo_root: str) -> list[str]:
    try:
        proc = git_text(
            repo_root,
            ["ls-files", "--others", "--exclude-standard"],
            timeout=5,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return []
    if proc.returncode != 0:
        return []
    return [line for line in proc.stdout.splitlines() if line.strip()]


def synthesize_untracked_patch(repo_root: str, rel_file: str) -> dict[str, Any]:
    path = (Path(repo_root) / rel_file).resolve()
    try:
        text = path.read_text()
    except (OSError, UnicodeDecodeError):
        return {
            "file": rel_file,
            "old_path": None,
            "hunks": [],
            "binary": True,
        }

    lines = text.splitlines()
    hunk_lines = [
        {"kind": "add", "old_line": None, "new_line": i, "text": line}
        for i, line in enumerate(lines, start=1)
    ]
    hunks: list[dict[str, Any]] = []
    if lines:
        hunks.append(
            {
                "old_start": 0,
                "old_lines": 0,
                "new_start": 1,
                "new_lines": len(lines),
                "section": "",
                "header": f"@@ -0,0 +1,{len(lines)} @@",
                "deletion_count": 0,
                "changed_new_lines": list(range(1, len(lines) + 1)),
                "anchor_line": 1,
                "lines": hunk_lines,
            }
        )
    return {
        "file": rel_file,
        "old_path": None,
        "hunks": hunks,
        "binary": False,
    }


def hunk_summary(hunks: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {
            "old_start": h["old_start"],
            "old_lines": h["old_lines"],
            "new_start": h["new_start"],
            "new_lines": h["new_lines"],
            "section": h.get("section", ""),
            "header": h["header"],
            "deletion_count": h.get("deletion_count", 0),
            "changed_new_lines": h.get("changed_new_lines", []),
            "anchor_line": h.get("anchor_line"),
        }
        for h in hunks
    ]


def compute_diff(
    repo_root: str,
    target: dict[str, Any],
    requested_base: str | None = None,
    rel_file: str | None = None,
) -> dict[str, Any]:
    base = resolve_diff_base(repo_root, target, requested_base)
    pathspecs = diff_pathspecs(repo_root, base["comparison_base"], rel_file)
    diff_args = [
        "diff",
        "--no-color",
        "--no-ext-diff",
        "--find-renames",
        base["comparison_base"],
        "--",
        *pathspecs,
    ]

    try:
        raw_diff_proc = git_text(repo_root, diff_args, timeout=20)
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        raise RuntimeError(f"could not compute diff: {e}") from e
    if raw_diff_proc.returncode not in {0, 1}:
        raise RuntimeError(raw_diff_proc.stderr.strip() or "git diff failed")

    patches = parse_unified_diff(raw_diff_proc.stdout)

    status_args = [
        "diff",
        "--name-status",
        "-z",
        "--find-renames",
        base["comparison_base"],
        "--",
        *pathspecs,
    ]
    numstat_args = [
        "diff",
        "--numstat",
        "-z",
        "--find-renames",
        base["comparison_base"],
        "--",
        *pathspecs,
    ]

    try:
        statuses = parse_name_status_z(git_bytes(repo_root, status_args).stdout)
        stats = parse_numstat_z(git_bytes(repo_root, numstat_args).stdout)
    except (subprocess.TimeoutExpired, FileNotFoundError):
        statuses = {}
        stats = {}

    files: dict[str, dict[str, Any]] = {}
    for path, status in statuses.items():
        files[path] = {
            "file": path,
            "status": status.get("status") or "M",
            "status_raw": status.get("status_raw"),
            "old_path": status.get("old_path"),
            "additions": 0,
            "deletions": 0,
            "binary": False,
            "hunks": [],
        }
    for path, stat in stats.items():
        files.setdefault(
            path,
            {
                "file": path,
                "status": "M",
                "status_raw": "M",
                "old_path": None,
                "additions": 0,
                "deletions": 0,
                "binary": False,
                "hunks": [],
            },
        )
        files[path]["additions"] = stat["additions"]
        files[path]["deletions"] = stat["deletions"]
        files[path]["binary"] = stat["additions"] is None or stat["deletions"] is None
    for path, patch in patches.items():
        files.setdefault(
            path,
            {
                "file": path,
                "status": "M",
                "status_raw": "M",
                "old_path": patch.get("old_path"),
                "additions": 0,
                "deletions": 0,
                "binary": False,
                "hunks": [],
            },
        )
        files[path]["hunks"] = patch.get("hunks", [])
        files[path]["old_path"] = files[path].get("old_path") or patch.get("old_path")

    for path in untracked_files(repo_root):
        if rel_file and path != rel_file:
            continue
        if path in files:
            continue
        patch = synthesize_untracked_patch(repo_root, path)
        line_count = sum(1 for h in patch.get("hunks", []) for _ in h.get("lines", []))
        files[path] = {
            "file": path,
            "status": "A",
            "status_raw": "A",
            "old_path": None,
            "additions": line_count,
            "deletions": 0,
            "binary": patch.get("binary", False),
            "hunks": patch.get("hunks", []),
        }

    payload_files = []
    for path in sorted(files):
        item = files[path]
        hunks = item.get("hunks") or []
        payload_files.append(
            {
                **item,
                "hunks": hunks if rel_file else hunk_summary(hunks),
                "hunk_count": len(hunks),
            }
        )

    return {
        **base,
        "files": payload_files,
        "file_count": len(payload_files),
        "additions": sum(f["additions"] or 0 for f in payload_files),
        "deletions": sum(f["deletions"] or 0 for f in payload_files),
    }


def diff_for_review(
    path: Path,
    requested_base: str | None = None,
    rel_file: str | None = None,
) -> dict[str, Any]:
    data = yaml_load(path.read_text())
    target = data.get("target") or {}
    if not isinstance(target, dict):
        raise RuntimeError("review target is not a mapping")
    repo_root = target.get("repo_root")
    if not isinstance(repo_root, str) or not repo_root:
        raise RuntimeError("review has no target.repo_root")
    return compute_diff(repo_root, target, requested_base, rel_file)


def refs_for_review(path: Path) -> dict[str, Any]:
    data = yaml_load(path.read_text())
    target = data.get("target") or {}
    if not isinstance(target, dict):
        raise RuntimeError("review target is not a mapping")
    repo_root = target.get("repo_root")
    if not isinstance(repo_root, str) or not repo_root:
        raise RuntimeError("review has no target.repo_root")

    refs = ["HEAD", "HEAD~1", "HEAD~2", "HEAD~3"]
    try:
        proc = git_text(
            repo_root,
            [
                "for-each-ref",
                "--format=%(refname:short)",
                "refs/heads",
                "refs/remotes",
            ],
            timeout=5,
        )
        if proc.returncode == 0:
            refs.extend(
                line.strip()
                for line in proc.stdout.splitlines()
                if line.strip() and not line.endswith("/HEAD")
            )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass

    base_ref = (target.get("base_ref") or "").strip() or default_base_ref(
        repo_root, target
    )
    return {
        "base_ref": base_ref,
        "refs": list(dict.fromkeys(refs)),
    }


def refresh_status_for_review(path: Path) -> dict[str, Any]:
    """Return whether a review's target differs from the current repo state."""
    data = yaml_load(path.read_text())
    target = data.get("target") or {}
    if not isinstance(target, dict):
        return {
            "ok": False,
            "needs_refresh": False,
            "reason": "review target is not a mapping",
        }

    repo_root = target.get("repo_root", "")
    if not repo_root:
        return {
            "ok": False,
            "needs_refresh": False,
            "reason": "review has no target.repo_root",
        }

    fingerprint = target.get("fingerprint")
    if fingerprint:
        current = current_repo_fingerprint(repo_root)
        return {
            "ok": current is not None,
            "needs_refresh": current is not None and current != fingerprint,
            "mode": "fingerprint",
            "reason": "" if current is not None else "could not fingerprint repo",
        }

    target_commit = target.get("commit", "")
    head = current_head(repo_root) if target_commit else None
    return {
        "ok": bool(target_commit and head),
        "needs_refresh": bool(target_commit and head and head != target_commit),
        "mode": "commit",
        "reason": "" if target_commit else "review has no target fingerprint or commit",
    }


def thread_type(thread: dict[str, Any]) -> str:
    value = thread.get("type")
    return value if isinstance(value, str) and value else COMMENT_THREAD_TYPE


def overview_body(review: dict[str, Any], key: str) -> str:
    value = review.get(key)
    if isinstance(value, dict):
        body = value.get("body")
        return body if isinstance(body, str) else ""
    if isinstance(value, str):
        return value
    return ""


def overview_replies(review: dict[str, Any], key: str) -> list[dict[str, Any]]:
    value = review.get(key)
    if not isinstance(value, dict):
        return []
    replies = value.get("replies")
    return replies if isinstance(replies, list) else []


def remaining_threads_after_full_submit(
    threads: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    return [thread for thread in threads if thread_type(thread) != COMMENT_THREAD_TYPE]


# === Inbox metadata ===============================================


def review_to_inbox_entry(slug: str, key: str, path: Path) -> dict[str, Any]:
    try:
        data = yaml_load(path.read_text())
    except Exception:
        return {
            "slug": slug,
            "key": key,
            "error": "parse failure",
            "size": path.stat().st_size,
            "modified": path.stat().st_mtime,
        }

    target = data.get("target", {}) or {}
    review = data.get("review", {}) or {}
    threads = review.get("threads", []) or []

    severity_counts: dict[str, int] = {
        "critical": 0,
        "high": 0,
        "medium": 0,
        "low": 0,
        "info": 0,
    }
    status_counts: dict[str, int] = {
        "open": 0,
        "acknowledged": 0,
        "resolved": 0,
        "wontfix": 0,
    }
    has_user_reply = False
    has_unanswered_user = False
    comment_count = 0
    note_count = 0
    for c in threads:
        if thread_type(c) == NOTE_THREAD_TYPE:
            note_count += 1
        else:
            comment_count += 1
            sev = c.get("severity")
            if sev in severity_counts:
                severity_counts[sev] += 1
        st = c.get("status")
        if st in status_counts:
            status_counts[st] += 1
        replies = c.get("replies") or []
        if any(
            (r.get("author") == "user" and (r.get("body") or "").strip())
            for r in replies
        ):
            has_user_reply = True
        last_author = replies[-1].get("author") if replies else None
        if last_author == "user" or (c.get("author") == "user" and not replies):
            has_unanswered_user = True

    for key_name in ("summary", "note"):
        replies = overview_replies(review, key_name)
        if any(
            (r.get("author") == "user" and (r.get("body") or "").strip())
            for r in replies
        ):
            has_user_reply = True
        if replies and replies[-1].get("author") == "user":
            has_unanswered_user = True

    repo_root = target.get("repo_root", "")
    target_commit = target.get("commit", "")
    stale = review_is_stale(target) if isinstance(target, dict) else False

    return {
        "slug": slug,
        "key": key,
        "repo_name": Path(repo_root).name if repo_root else slug,
        "branch": target.get("branch"),
        "short_sha": target_commit[:7] if target_commit else "",
        "target_kind": target.get("kind"),
        "pr_number": target.get("pr_number"),
        "thread_count": len(threads),
        "comment_count": comment_count,
        "note_count": note_count,
        "severity_counts": severity_counts,
        "status_counts": status_counts,
        "has_user_reply": has_user_reply,
        "has_unanswered_user": has_unanswered_user,
        "stale": stale,
        "generated_at": data.get("generated_at"),
        "modified": path.stat().st_mtime,
        "summary": overview_body(review, "summary").strip(),
    }


# === Source-file access (sandboxed to declared repo_root) =========


def safe_read_source(slug: str, key: str, file_arg: str) -> tuple[int, str]:
    path = review_path(slug, key)
    if path is None or not path.exists():
        return 404, "review not found"
    try:
        data = yaml_load(path.read_text())
    except Exception:
        return 500, "review parse error"

    repo_root = (data.get("target") or {}).get("repo_root")
    if not repo_root:
        return 400, "review has no target.repo_root"

    repo_root_p = Path(repo_root).resolve()
    requested = (repo_root_p / file_arg).resolve()
    try:
        requested.relative_to(repo_root_p)
    except ValueError:
        return 403, "path escapes repo_root"

    if not requested.exists() or not requested.is_file():
        return 404, "file not found"
    try:
        return 200, requested.read_text()
    except (OSError, UnicodeDecodeError):
        return 415, "not a readable text file"


# === Anchor refresh ================================================


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


def anchor_text_variants(anchor_text: str) -> list[str]:
    variants = [anchor_text]
    if anchor_text.endswith("\n"):
        chomped = anchor_text[:-1]
        if chomped not in variants:
            variants.append(chomped)
    return variants


def find_anchor_occurrences(
    lines: list[str], anchor_text: str
) -> list[tuple[int, int]]:
    if anchor_text == "":
        return []
    anchor_lines = anchor_text.split("\n")
    if not anchor_lines:
        return []
    width = len(anchor_lines)
    occurrences: list[tuple[int, int]] = []
    for idx in range(0, len(lines) - width + 1):
        if lines[idx : idx + width] == anchor_lines:
            start = idx + 1
            occurrences.append((start, start + width - 1))
    return occurrences


def refresh_thread_anchor(repo_root: Path, thread: dict[str, Any]) -> str:
    rel_file = thread.get("file")
    anchor_text = thread.get("anchor_text")
    current_range = line_range(thread)
    if not isinstance(rel_file, str) or not isinstance(anchor_text, str):
        thread["anchor_status"] = "missing"
        return "missing"

    source_path = (repo_root / rel_file).resolve()
    try:
        source_path.relative_to(repo_root)
        lines = source_path.read_text().split("\n")
    except (OSError, UnicodeDecodeError, ValueError):
        thread["anchor_status"] = "missing"
        return "missing"

    for search_text in anchor_text_variants(anchor_text):
        if current_range is not None:
            start, end = current_range
            if end <= len(lines) and text_for_range(lines, start, end) == search_text:
                thread["anchor_status"] = "current"
                return "current"

        occurrences = find_anchor_occurrences(lines, search_text)
        if len(occurrences) == 1:
            start, end = occurrences[0]
            if end == start:
                thread.pop("start_line", None)
            else:
                thread["start_line"] = start
            thread["line"] = end
            thread["anchor_status"] = "moved"
            return "moved"
        if len(occurrences) > 1:
            thread["anchor_status"] = "ambiguous"
            return "ambiguous"

    thread["anchor_status"] = "missing"
    return "missing"


def refresh_review_file(path: Path) -> dict[str, Any]:
    data = yaml_load(path.read_text())
    target = data.get("target") or {}
    repo_root = target.get("repo_root")
    if not repo_root:
        raise RuntimeError("review has no target.repo_root")

    repo_root_p = Path(repo_root).resolve()
    threads = (data.get("review") or {}).get("threads") or []
    counts = {"current": 0, "moved": 0, "missing": 0, "ambiguous": 0}
    for thread in threads:
        if not isinstance(thread, dict):
            continue
        status = refresh_thread_anchor(repo_root_p, thread)
        counts[status] += 1

    fingerprint = current_repo_fingerprint(repo_root)
    if fingerprint:
        target["fingerprint"] = fingerprint
    if target.get("commit") is None:
        head = current_head(repo_root)
        if head:
            target["commit"] = head

    path.write_text(yaml_dump(data))
    return {"ok": True, "counts": counts, "review": data}


# === HTTP request handler =========================================


def request_path(raw_path: str) -> str:
    """Return the URL path without query parameters for route matching."""
    return urllib.parse.urlparse(raw_path).path


class ViewerHandler(BaseHTTPRequestHandler):
    server_version = "assisted-review-viewer/1.0"

    def log_message(self, *_args: Any) -> None:
        # Quiet logs in daemon mode; --foreground users see the request lines.
        if getattr(self.server, "verbose", False):
            super().log_message(*_args)

    # --- helpers ---

    def _json(self, status: int, payload: Any) -> None:
        # ruamel.yaml parses YAML timestamps to its own TimeStamp class which
        # isn't JSON-serializable; same for any datetime-like / Decimal value.
        body = json.dumps(payload, default=_json_fallback).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _text(self, status: int, body: str, content_type: str = "text/plain") -> None:
        encoded = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", f"{content_type}; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(encoded)

    def _read_body(self) -> bytes:
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length else b""

    # --- routing ---

    def do_GET(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/api/ping":
            self._json(
                200,
                {
                    "ok": True,
                    "service": SERVICE_SIGNATURE,
                    "api_version": VIEWER_API_VERSION,
                    "yaml": YAML_BACKEND,
                },
            )
            return

        if path == "/api/reviews":
            entries = [review_to_inbox_entry(s, k, p) for s, k, p in walk_reviews()]
            self._json(200, {"reviews": entries})
            return

        m = re.match(r"^/api/review/([^/]+)/([^/]+)$", path)
        if m:
            slug, key = m.group(1), m.group(2)
            rp = review_path(slug, key)
            if rp is None or not rp.exists():
                self._json(404, {"error": "not found"})
                return
            try:
                data = yaml_load(rp.read_text())
                # Compute staleness and surface it on the response so the
                # client can render a topbar badge without a second request.
                target = data.get("target") or {}
                data["_stale"] = (
                    review_is_stale(target) if isinstance(target, dict) else False
                )
                self._json(200, data)
            except Exception as e:
                self._json(500, {"error": f"parse error: {e}"})
            return

        m = re.match(r"^/api/tree/([^/]+)/([^/]+)$", path)
        if m:
            slug, key = m.group(1), m.group(2)
            rp = review_path(slug, key)
            if rp is None or not rp.exists():
                self._json(404, {"error": "not found"})
                return
            try:
                data = yaml_load(rp.read_text())
                repo_root = (data.get("target") or {}).get("repo_root")
            except Exception as e:
                self._json(500, {"error": f"parse error: {e}"})
                return
            if not repo_root:
                self._json(400, {"error": "review has no target.repo_root"})
                return
            qs = urllib.parse.parse_qs(parsed.query)
            include_ignored = (qs.get("include_ignored") or ["0"])[0] == "1"
            self._json(
                200,
                {
                    "files": list_repo_files(
                        repo_root, include_ignored=include_ignored
                    ),
                    "include_ignored": include_ignored,
                },
            )
            return

        m = re.match(r"^/api/refresh-status/([^/]+)/([^/]+)$", path)
        if m:
            slug, key = m.group(1), m.group(2)
            rp = review_path(slug, key)
            if rp is None or not rp.exists():
                self._json(404, {"error": "not found"})
                return
            try:
                self._json(200, refresh_status_for_review(rp))
            except Exception as e:
                self._json(500, {"error": f"refresh status failed: {e}"})
            return

        m = re.match(r"^/api/diff/([^/]+)/([^/]+)$", path)
        if m:
            slug, key = m.group(1), m.group(2)
            rp = review_path(slug, key)
            if rp is None or not rp.exists():
                self._json(404, {"error": "not found"})
                return
            qs = urllib.parse.parse_qs(parsed.query)
            base_ref = (qs.get("base") or [""])[0] or None
            file_arg = (qs.get("file") or [""])[0] or None
            try:
                self._json(200, diff_for_review(rp, base_ref, file_arg))
            except RuntimeError as e:
                self._json(400, {"error": str(e)})
            except Exception as e:
                self._json(500, {"error": f"diff failed: {e}"})
            return

        m = re.match(r"^/api/refs/([^/]+)/([^/]+)$", path)
        if m:
            slug, key = m.group(1), m.group(2)
            rp = review_path(slug, key)
            if rp is None or not rp.exists():
                self._json(404, {"error": "not found"})
                return
            try:
                self._json(200, refs_for_review(rp))
            except RuntimeError as e:
                self._json(400, {"error": str(e)})
            except Exception as e:
                self._json(500, {"error": f"refs failed: {e}"})
            return

        if path == "/api/source":
            qs = urllib.parse.parse_qs(parsed.query)
            file_arg = (qs.get("file") or [""])[0]
            review_arg = (qs.get("review") or [""])[0]
            if "/" not in review_arg:
                self._json(400, {"error": "review query must be <slug>/<key>"})
                return
            slug, key = review_arg.split("/", 1)
            status, body = safe_read_source(slug, key, file_arg)
            if status == 200:
                self._text(200, body)
            else:
                self._json(status, {"error": body})
            return

        # Static webapp + history-API fallback for client-side routes
        self._serve_static(path)

    def do_PUT(self) -> None:
        path = request_path(self.path)
        m = re.match(r"^/api/review/([^/]+)/([^/]+)$", path)
        if not m:
            self._json(404, {"error": f"unknown PUT endpoint: {path}"})
            return
        slug, key = m.group(1), m.group(2)
        rp = review_path(slug, key)
        if rp is None:
            self._json(400, {"error": "invalid slug/key"})
            return

        try:
            data = json.loads(self._read_body())
        except json.JSONDecodeError:
            self._json(400, {"error": "invalid JSON"})
            return

        # Strip ephemeral underscore-prefixed keys the server or client
        # annotated onto the in-memory object (e.g. _stale, _slug, _key).
        if isinstance(data, dict):
            data = {k: v for k, v in data.items() if not k.startswith("_")}

        try:
            rp.parent.mkdir(parents=True, exist_ok=True)
            rp.write_text(yaml_dump(data))
        except OSError as e:
            self._json(500, {"error": f"write failed: {e}"})
            return
        self._json(200, {"ok": True})

    def do_DELETE(self) -> None:
        path = request_path(self.path)
        m = re.match(r"^/api/review/([^/]+)/([^/]+)$", path)
        if not m:
            self._json(404, {"error": f"unknown DELETE endpoint: {path}"})
            return
        slug, key = m.group(1), m.group(2)
        rp = review_path(slug, key)
        if rp is None or not rp.exists():
            self._json(404, {"error": "not found"})
            return
        try:
            rp.unlink()
        except OSError as e:
            self._json(500, {"error": f"delete failed: {e}"})
            return
        self._json(200, {"ok": True})

    def do_POST(self) -> None:
        path = request_path(self.path)
        m = re.match(r"^/api/refresh/([^/]+)/([^/]+)$", path)
        if m:
            slug, key = m.group(1), m.group(2)
            rp = review_path(slug, key)
            if rp is None or not rp.exists():
                self._json(404, {"error": "not found"})
                return
            try:
                payload = refresh_review_file(rp)
            except Exception as e:
                self._json(500, {"error": f"refresh failed: {e}"})
                return
            self._json(200, payload)
            return

        m = re.match(r"^/api/submit/([^/]+)/([^/]+)$", path)
        if not m:
            self._json(404, {"error": f"unknown POST endpoint: {path}"})
            return
        slug, key = m.group(1), m.group(2)
        rp = review_path(slug, key)
        if rp is None or not rp.exists():
            self._json(404, {"error": "not found"})
            return

        try:
            req = json.loads(self._read_body())
        except json.JSONDecodeError:
            self._json(400, {"error": "invalid JSON"})
            return

        mode = req.get("mode")
        comment_id = req.get("commentId") or req.get("threadId")
        if mode not in ("all", "comment"):
            self._json(400, {"error": "mode must be 'all' or 'comment'"})
            return
        if mode == "comment" and not comment_id:
            self._json(400, {"error": "commentId required when mode='comment'"})
            return

        submit_script = Path(__file__).parent / "submit.py"
        # uv run --script ensures submit.py's PEP 723 deps are resolved
        # without depending on the env that's running view.py.
        cmd = ["uv", "run", "-q", "--script", str(submit_script), str(rp)]
        if mode == "comment":
            cmd += ["--thread-id", comment_id]

        # 90s is well above a normal `gh api` POST and well under any
        # reasonable user patience for a stuck spinner. start_new_session
        # puts the child in its own process group so we can SIGKILL the
        # whole group on timeout — otherwise `uv` would die but `gh` (its
        # grandchild) would be reparented to init and keep going,
        # eventually posting the review behind the user's back and
        # silently double-submitting on retry.
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
        try:
            stdout, stderr = proc.communicate(timeout=90)
        except subprocess.TimeoutExpired:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
            self._json(
                504,
                {
                    "error": "submit timed out after 90s — check GitHub before retrying",
                    "detail": "local YAML left untouched",
                },
            )
            return
        if proc.returncode != 0:
            self._json(502, {"error": "submit failed", "detail": stderr.strip()})
            return

        # On success, mutate the local YAML.
        archived = False
        remaining_threads = 0
        try:
            data = yaml_load(rp.read_text())
            if mode == "comment":
                data["review"]["threads"] = [
                    c for c in data["review"]["threads"] if c.get("id") != comment_id
                ]
                remaining_threads = len(data["review"]["threads"])
                rp.write_text(yaml_dump(data))
            else:
                data["review"]["threads"] = remaining_threads_after_full_submit(
                    data["review"]["threads"]
                )
                if data["review"]["threads"]:
                    remaining_threads = len(data["review"]["threads"])
                    rp.write_text(yaml_dump(data))
                else:
                    # Archive the whole file under ~/.reviews/.archive/<slug>/...
                    archive_dir = REVIEWS_DIR / ".archive" / slug
                    archive_dir.mkdir(parents=True, exist_ok=True)
                    rp.rename(archive_dir / rp.name)
                    archived = True
        except Exception as e:
            self._json(
                207,
                {
                    "ok": True,
                    "warning": f"submit succeeded but local update failed: {e}",
                },
            )
            return

        self._json(
            200,
            {
                "ok": True,
                "url": stdout.strip(),
                "archived": archived,
                "remaining_threads": remaining_threads,
            },
        )

    # --- static + SPA fallback ---

    def _serve_static(self, path: str) -> None:
        # API routes already handled above. SPA routes (`/`, `/r/...`)
        # always serve index.html. For anything else, look up a file in
        # webapp/ and 404 if missing — falling back to index.html for
        # arbitrary paths masks legitimate 404s on missing static assets
        # (favicon, stale bundle URLs, typo'd hrefs) by handing the
        # browser HTML where it expected CSS/JS/binary.
        if path == "/" or path.startswith("/r/"):
            self._send_file(WEBAPP_DIR / "index.html", "text/html")
            return

        # Strip leading slash, prevent path escape.
        rel = path.lstrip("/")
        candidate = (WEBAPP_DIR / rel).resolve()
        try:
            candidate.relative_to(WEBAPP_DIR.resolve())
        except ValueError:
            self._json(403, {"error": "path escape"})
            return

        if not candidate.exists() or not candidate.is_file():
            self._text(404, "not found")
            return

        ct = guess_content_type(candidate)
        self._send_file(candidate, ct)

    def _send_file(self, path: Path, content_type: str) -> None:
        try:
            data = path.read_bytes()
        except OSError:
            self._text(404, "not found")
            return
        self.send_response(200)
        self.send_header(
            "Content-Type",
            f"{content_type}; charset=utf-8"
            if content_type.startswith("text/") or content_type.endswith("javascript")
            else content_type,
        )
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)


def _json_fallback(value: Any) -> Any:
    """Make ruamel.yaml TimeStamp / Decimal / etc. JSON-serializable."""
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return str(value)


def guess_content_type(path: Path) -> str:
    return {
        ".html": "text/html",
        ".js": "application/javascript",
        ".css": "text/css",
        ".json": "application/json",
        ".svg": "image/svg+xml",
        ".png": "image/png",
        ".ico": "image/x-icon",
    }.get(path.suffix, "application/octet-stream")


# === Server lifecycle =============================================


def run_server(port: int, verbose: bool = False) -> None:
    server = ThreadingHTTPServer(("127.0.0.1", port), ViewerHandler)
    server.verbose = verbose  # type: ignore[attr-defined]

    def shutdown(*_args: Any) -> None:
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    try:
        server.serve_forever()
    finally:
        remove_state()


def deep_link(state: dict[str, Any], review_path_arg: Path | None) -> str:
    base = state["url"]
    if not review_path_arg:
        return base
    slug = review_path_arg.parent.name
    key = review_path_arg.name.removesuffix(".review.yaml")
    return f"{base}/r/{slug}/{key}"


# === CLI commands =================================================


def cmd_status() -> int:
    state = detect_running_daemon()
    if state is None:
        print("not running")
        return 1
    print(f"running · pid {state['pid']} · {state['url']}")
    return 0


def cmd_stop() -> int:
    state = read_state()
    if state is None:
        print("not running")
        return 0
    pid = state.get("pid")
    if pid and is_pid_alive(pid):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        # Give it a moment to clean up the state file itself.
        for _ in range(20):
            if not is_pid_alive(pid):
                break
            time.sleep(0.1)
    remove_state()
    print(f"stopped pid {pid}")
    return 0


def cmd_foreground(open_browser: bool, review_path_arg: Path | None) -> int:
    if detect_running_daemon() is not None:
        print(
            "daemon already running; --stop it first or omit --foreground",
            file=sys.stderr,
        )
        return 1
    port = find_free_port()
    url = f"http://127.0.0.1:{port}"
    state = {
        "pid": os.getpid(),
        "port": port,
        "url": url,
        "started_at": datetime.now(timezone.utc).isoformat(),
        "service": SERVICE_SIGNATURE,
        "api_version": VIEWER_API_VERSION,
    }
    write_state(state)
    print(f"viewer · pid {os.getpid()} · {url}", file=sys.stderr)

    if open_browser:
        webbrowser.open(deep_link(state, review_path_arg))

    run_server(port, verbose=True)
    return 0


@contextlib.contextmanager
def ensure_lock():
    """Serialize the detect→fork→write_state critical section in cmd_ensure.

    Without this, two parallel `view.py --ensure` invocations both find
    no daemon, both fork, both bind a port, both clobber the state file
    — leaving one daemon orphaned. The lock is process-level (fcntl) so
    any other Python invoking cmd_ensure on the same machine waits.
    """
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    fd = os.open(ENSURE_LOCK_FILE, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        # flock is released on close — explicit unlock keeps the order
        # obvious when reading the code.
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def cmd_ensure(open_browser: bool, review_path_arg: Path | None) -> int:
    # Lock held through the detect → fork → wait-for-state-file window.
    # A concurrent `view.py --ensure` blocks here until the first
    # invocation's daemon has either written its state file or timed
    # out, at which point the second invocation's detect_running_daemon
    # finds the first daemon and returns without spawning a duplicate.
    with ensure_lock():
        existing = detect_running_daemon()
        if existing is not None:
            if open_browser:
                webbrowser.open(deep_link(existing, review_path_arg))
            print(existing["url"])
            return 0

        # Spawn a daemonized child. Parent waits for the state file to
        # appear, then prints URL and (optionally) opens the browser.
        pid = os.fork()
        if pid > 0:
            # Parent — wait for daemon to write the state file.
            for _ in range(50):
                time.sleep(0.1)
                state = detect_running_daemon()
                if state is not None:
                    if open_browser:
                        webbrowser.open(deep_link(state, review_path_arg))
                    print(state["url"])
                    return 0
            print("daemon did not start within 5s", file=sys.stderr)
            return 1

        # Child branch — escape via os._exit so the `with` cleanup never
        # runs in this process; otherwise the daemon's flock release
        # would race the parent's release on the shared OFD.
        try:
            daemonize()
            port = find_free_port()
            state = {
                "pid": os.getpid(),
                "port": port,
                "url": f"http://127.0.0.1:{port}",
                "started_at": datetime.now(timezone.utc).isoformat(),
                "service": SERVICE_SIGNATURE,
                "api_version": VIEWER_API_VERSION,
            }
            write_state(state)
            run_server(port, verbose=False)
        except Exception:
            remove_state()
            os._exit(1)
        os._exit(0)


# === Entry point ==================================================


def main() -> int:
    parser = argparse.ArgumentParser(description="Assisted-review viewer daemon.")
    parser.add_argument(
        "--ensure", action="store_true", help="Ensure a daemon is running."
    )
    parser.add_argument(
        "--open", action="store_true", help="Open browser after ensuring."
    )
    parser.add_argument(
        "--review-path",
        type=Path,
        default=None,
        help="Path to a review YAML to deep-link to when opening the browser.",
    )
    parser.add_argument("--stop", action="store_true", help="Stop the running daemon.")
    parser.add_argument("--status", action="store_true", help="Print daemon status.")
    parser.add_argument(
        "--foreground", action="store_true", help="Run in foreground; do not daemonize."
    )
    args = parser.parse_args()

    if args.stop:
        return cmd_stop()
    if args.status:
        return cmd_status()
    if args.foreground:
        return cmd_foreground(args.open, args.review_path)
    if args.ensure:
        return cmd_ensure(args.open, args.review_path)

    parser.print_help(sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
