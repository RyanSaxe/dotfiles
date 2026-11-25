"""Behavioral tests for ai-harness/tools/notify-pushover.zsh.

Each test runs in a scratch HOME with stub curl, ioreg and security binaries so
nothing touches Pushover, the macOS keychain or real secrets.
"""

from __future__ import annotations

import itertools
import json
import os
import subprocess
import time
from pathlib import Path

REPO = Path(__file__).parent.parent.parent
SCRIPT = REPO / "ai-harness/tools/notify-pushover.zsh"
_RUN_SEQ = itertools.count(1)


def run_hook(
    tmp_path: Path,
    *,
    agent: str,
    payload: dict[str, object],
    idle_seconds: int = 90,
    extra_env: dict[str, str] | None = None,
    secrets: dict[str, str] | None = None,
    keychain: dict[str, str] | None = None,
) -> tuple[subprocess.CompletedProcess[str], dict[str, str] | None]:
    run_dir = tmp_path / f"run-{next(_RUN_SEQ)}"
    home = run_dir / "home"
    home.mkdir(parents=True)
    if secrets is not None:
        sops_dir = home / ".config/sops-nix/secrets"
        sops_dir.mkdir(parents=True, exist_ok=True)
        for name, value in secrets.items():
            (sops_dir / name).write_text(value)

    stubs = run_dir / "bin"
    stubs.mkdir()
    curl_out = run_dir / "curl.json"

    (stubs / "curl").write_text(
        "#!/bin/sh\n"
        f'out="{curl_out}"\n'
        "while [ $# -gt 0 ]; do\n"
        '  if [ "$1" = "--form-string" ]; then\n'
        "    shift\n"
        "    k=${1%%=*}\n"
        "    v=${1#*=}\n"
        '    jq -n --arg k "$k" --arg v "$v" \'{($k): $v}\' >> "$out.parts"\n'
        "  fi\n"
        "  shift\n"
        "done\n"
        'jq -s "add" "$out.parts" > "$out.tmp" && rm -f "$out.parts" && mv "$out.tmp" "$out"\n'
    )
    (stubs / "curl").chmod(0o755)

    (stubs / "ioreg").write_text(f"#!/bin/sh\necho '    \"HIDIdleTime\" = {idle_seconds * 1_000_000_000}'\n")
    (stubs / "ioreg").chmod(0o755)

    kc_dir = run_dir / "keychain"
    kc_dir.mkdir()
    for account, value in (keychain or {}).items():
        (kc_dir / account).write_text(value)
    (stubs / "security").write_text(
        "#!/bin/sh\n"
        'acct=""\n'
        "while [ $# -gt 0 ]; do\n"
        '  if [ "$1" = "-a" ]; then shift; acct="$1"; fi\n'
        "  shift\n"
        "done\n"
        f'[ -r "{kc_dir}/$acct" ] && cat "{kc_dir}/$acct" || exit 44\n'
    )
    (stubs / "security").chmod(0o755)

    env = {
        "PATH": f"{stubs}:{os.environ['PATH']}",
        "HOME": str(home),
        "PUSHOVER_USER": "testuser",
        "PUSHOVER_TOKEN": "testtoken",
    }
    if extra_env:
        env.update(extra_env)

    # -f skips /etc/zshenv so nix-darwin's set-environment doesn't prepend
    # /usr/sbin ahead of the test stubs on PATH.
    proc = subprocess.run(
        ["zsh", "-f", str(SCRIPT), agent],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        env=env,
        check=True,
        timeout=10,
    )
    # curl runs detached in the background; wait briefly for its log file.
    deadline = time.monotonic() + 2.0
    while not curl_out.exists() and time.monotonic() < deadline:
        time.sleep(0.02)
    sent = json.loads(curl_out.read_text()) if curl_out.exists() else None
    return proc, sent


def test_empty_strings_fall_back_across_hook_events(tmp_path: Path) -> None:
    proj = tmp_path / "my-app"
    proj.mkdir()

    _, perm = run_hook(
        tmp_path,
        agent="Codex",
        payload={
            "hook_event_name": "PermissionRequest",
            "cwd": str(proj),
            "tool_name": "shell",
            "tool_input": {"description": "", "command": "git push origin main"},
        },
    )
    assert perm is not None
    assert perm["title"] == "my-app · Codex wants permission"
    assert perm["message"] == "git push origin main"

    _, notif = run_hook(
        tmp_path,
        agent="Claude Code",
        payload={"hook_event_name": "Notification", "cwd": str(proj), "title": "", "message": ""},
    )
    assert notif is not None
    assert notif["title"] == "my-app · Claude Code needs you"
    assert notif["message"] == "(no message)"

    _, fail = run_hook(
        tmp_path,
        agent="Claude Code",
        payload={"hook_event_name": "StopFailure", "cwd": str(proj), "last_assistant_message": "Rate limited"},
    )
    assert fail is not None
    assert fail["title"] == "my-app · Claude Code failed"
    assert fail["message"] == "Rate limited"


def test_antigravity_transcript_handles_long_runs_and_malformed_lines(tmp_path: Path) -> None:
    proj = tmp_path / "my-app"
    proj.mkdir()
    transcript = tmp_path / "transcript.jsonl"
    lines = [
        json.dumps({"type": "PLANNER_RESPONSE", "content": "Finished fixing\r\nthe race."}),
        json.dumps({"type": "PLANNER_RESPONSE", "content": "   \n\t "}),
        json.dumps({"type": "PLANNER_RESPONSE", "content": ["non-string", "ignored"]}),
        *{json.dumps({"type": "TOOL_CALL", "step": i}) for i in range(60)},
        '{"type": "TOOL_CALL", "truncated": ',
    ]
    transcript.write_text("\n".join(lines) + "\n")

    proc, sent = run_hook(
        tmp_path,
        agent="Antigravity",
        payload={
            "hookEventName": "Stop",
            "terminationReason": "stop",
            "workspacePaths": [str(proj)],
            "transcriptPath": str(transcript),
        },
    )
    assert proc.stdout == "{}\n"
    assert sent is not None
    assert sent["title"] == "my-app · Antigravity done"
    assert sent["message"] == "Finished fixing the race."


def test_title_limit_blank_messages_and_root_cwd(tmp_path: Path) -> None:
    _, sent = run_hook(
        tmp_path,
        agent="Claude Code",
        payload={
            "hook_event_name": "Notification",
            "cwd": "/",
            "title": "T" * 300,
            "message": "\n\r\n   \t ",
        },
    )
    assert sent is not None
    assert len(sent["title"]) == 250
    assert sent["title"].startswith("Claude Code T")
    assert sent["message"] == "(no message)"


def test_empty_sops_files_fall_back_to_keychain_and_invalid_idle_stays_gated(tmp_path: Path) -> None:
    proj = tmp_path / "my-app"
    proj.mkdir()
    keychain_creds = {"user": "kc-user", "token": "kc-secret"}

    _, sent = run_hook(
        tmp_path,
        agent="Codex",
        payload={"hook_event_name": "Stop", "cwd": str(proj), "last_assistant_message": "Done"},
        idle_seconds=90,
        extra_env={"PUSHOVER_USER": "", "PUSHOVER_TOKEN": ""},
        secrets={"pushover-user": "", "pushover-token": ""},
        keychain=keychain_creds,
    )
    assert sent is not None
    assert sent["user"] == keychain_creds["user"]
    assert sent["token"] == keychain_creds["token"]

    _, suppressed = run_hook(
        tmp_path,
        agent="Codex",
        payload={"hook_event_name": "Stop", "cwd": str(proj), "last_assistant_message": "Done"},
        idle_seconds=0,
        extra_env={"PUSHOVER_IDLE": "abc"},
    )
    assert suppressed is None
