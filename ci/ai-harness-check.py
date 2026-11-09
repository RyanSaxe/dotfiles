#!/usr/bin/env -S uv run -q --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///

"""Validate the authored AI harness without invoking an agent CLI."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import TypeAlias

import tomllib

REPO_ROOT = Path(__file__).resolve().parent.parent
HARNESS_ROOT = REPO_ROOT / "ai-harness"
JsonValue: TypeAlias = (
    str | int | float | bool | None | list["JsonValue"] | dict[str, "JsonValue"]
)
SKILL_VALIDATOR = (
    "uvx",
    "--from",
    "skills-ref==0.1.1",
    "agentskills",
    "validate",
)


class HarnessError(Exception):
    """A violated AI harness ownership or structure contract."""


def read_json(path: Path) -> dict[str, JsonValue]:
    value = json.loads(path.read_text())
    if not isinstance(value, dict) or not all(isinstance(key, str) for key in value):
        raise HarnessError(f"{path.relative_to(REPO_ROOT)} must contain a JSON object")
    return value


def require_string(mapping: dict[str, JsonValue], key: str, path: Path) -> str:
    value = mapping.get(key)
    if not isinstance(value, str) or not value.strip():
        raise HarnessError(
            f"{path.relative_to(REPO_ROOT)} requires a non-empty {key!r}"
        )
    return value


def validate_manifests() -> None:
    for path in (
        HARNESS_ROOT / ".claude-plugin/plugin.json",
        HARNESS_ROOT / "plugin.json",
    ):
        manifest = read_json(path)
        if require_string(manifest, "name", path) != "dotfiles":
            raise HarnessError(
                f"{path.relative_to(REPO_ROOT)} must use plugin name 'dotfiles'"
            )

        for field in ("agents", "hooks", "mcpServers", "lspServers", "skills"):
            raw_paths = manifest.get(field)
            if raw_paths is None or isinstance(raw_paths, dict):
                continue
            paths = [raw_paths] if isinstance(raw_paths, str) else raw_paths
            if not isinstance(paths, list) or not all(
                isinstance(item, str) for item in paths
            ):
                raise HarnessError(
                    f"{path.relative_to(REPO_ROOT)} has invalid {field!r} paths"
                )
            for relative_path in paths:
                candidate = HARNESS_ROOT / relative_path
                if not candidate.exists():
                    raise HarnessError(
                        f"{path.relative_to(REPO_ROOT)} references missing {relative_path!r}"
                    )


def validate_skills() -> None:
    skill_dirs = sorted(
        path for path in (HARNESS_ROOT / "skills").iterdir() if path.is_dir()
    )

    for skill_dir in skill_dirs:
        command = (*SKILL_VALIDATOR, str(skill_dir))
        result = subprocess.run(command, capture_output=True, check=False, text=True)
        if result.returncode:
            details = result.stderr.strip() or result.stdout.strip()
            raise HarnessError(f"{skill_dir.relative_to(REPO_ROOT)}: {details}")


def validate_settings() -> None:
    claude = read_json(HARNESS_ROOT / "claude/settings.json")
    copilot = read_json(HARNESS_ROOT / "copilot/settings.json")

    for name, settings in (("claude", claude), ("copilot", copilot)):
        status_line = settings.get("statusLine")
        if not isinstance(status_line, dict):
            raise HarnessError(f"{name} settings require a statusLine object")
        if status_line.get("type") != "command":
            raise HarnessError(f"{name} statusLine must be a command")
        command = status_line.get("command")
        if not isinstance(command, str) or not command.endswith("statusline.js"):
            raise HarnessError(f"{name} statusLine must invoke statusline.js")

    codex_path = HARNESS_ROOT / "codex/managed_config.toml"
    tomllib.loads(codex_path.read_text())


def validate_statusline() -> None:
    statusline = HARNESS_ROOT / "statusline.js"
    if not statusline.is_file() or not statusline.stat().st_mode & 0o111:
        raise HarnessError(f"{statusline.relative_to(REPO_ROOT)} must be executable")

    node = shutil.which("node")
    if node is None:
        raise HarnessError("node is required to execute the shared status line")
    payloads = (
        {
            "workspace": {"current_dir": "/tmp/project"},
            "model": {"display_name": "Opus"},
            "effortLevel": "xhigh",
            "context_window": {"used_percentage": 25},
        },
        {
            "cwd": "/tmp/project",
            "model": {"id": "Opus"},
            "effort": {"level": "xhigh"},
            "context_window": {"current_context_used_percentage": 25},
        },
    )
    with tempfile.TemporaryDirectory() as state_home:
        outputs = []
        for payload in payloads:
            result = subprocess.run(
                [node, str(statusline)],
                input=json.dumps(payload),
                capture_output=True,
                check=False,
                text=True,
                env={**os.environ, "XDG_STATE_HOME": state_home},
            )
            if result.returncode:
                raise HarnessError(
                    f"statusline failed its fixture: {result.stderr.strip()}"
                )
            outputs.append(re.sub(r"\x1b\[[0-9;]*m", "", result.stdout).strip())

    if outputs[0] != outputs[1]:
        raise HarnessError(
            "Claude and Copilot payloads produced different status lines: "
            f"{outputs[0]!r} != {outputs[1]!r}"
        )
    if not all(value in outputs[0] for value in ("project", "Opus xhigh", "75% left")):
        raise HarnessError(f"statusline omitted expected context: {outputs[0]!r}")


# The curl stub writes each form field to the descriptor the check reads. The
# ioreg and security stubs stand in for the Mac's input idle time and the
# login keychain, so the check never reads real keys or sends a push.
NOTIFY_STUBS = {
    "curl": """#!/usr/bin/env zsh
while (($#)); do
  [[ $1 == --form-string ]] && print -r -u $STUB_FD -- $2
  shift
done
""",
    "ioreg": """#!/bin/sh
echo "    |   \\"HIDIdleTime\\" = $STUB_IDLE_NS"
""",
    "security": "#!/bin/sh\nexit 44\n",
}


def send_notify_event(
    agent: str, event: dict[str, JsonValue], env: dict[str, str]
) -> dict[str, str]:
    zsh = shutil.which("zsh")
    if zsh is None or shutil.which("jq") is None:
        raise HarnessError("zsh and jq are required to run notify-pushover.zsh")

    read_fd, write_fd = os.pipe()
    with subprocess.Popen(
        [zsh, "-f", str(HARNESS_ROOT / "tools/notify-pushover.zsh"), agent],
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env={**env, "STUB_FD": str(write_fd)},
        pass_fds=(write_fd,),
        text=True,
    ) as process:
        os.close(write_fd)
        process.communicate(json.dumps(event))
    # curl runs in the background after the script exits. Reading to the end
    # of the pipe waits for it, because curl holds the write end open too.
    with os.fdopen(read_fd, encoding="utf-8") as fields:
        return dict(line.split("=", 1) for line in fields.read().splitlines())


def validate_notify_pushover() -> None:
    def push(title: str, message: str) -> dict[str, str]:
        return {"token": "T", "user": "U", "title": title, "message": message}

    stop: dict[str, JsonValue] = {
        "hook_event_name": "Stop",
        "stop_hook_active": False,
        "last_assistant_message": "Tests pass.\nPR opened.",
    }
    permission_prompt: dict[str, JsonValue] = {
        "hook_event_name": "Notification",
        "notification_type": "permission_prompt",
        "message": "Claude needs your permission to use Bash",
    }
    failure: dict[str, JsonValue] = {
        "hook_event_name": "StopFailure",
        "error": "rate_limit",
        "error_details": "429 Too Many Requests",
    }
    no_keys = {"PUSHOVER_USER": "", "PUSHOVER_TOKEN": ""}
    recent_input = {"STUB_IDLE_NS": str(5 * 10**9)}
    cases: tuple[
        tuple[str, str, dict[str, JsonValue], dict[str, str], dict[str, str]], ...
    ] = (
        (
            "finished turn",
            "Claude Code",
            stop,
            {},
            push("project · Claude Code done", "Tests pass. PR opened."),
        ),
        (
            "permission prompt",
            "Claude Code",
            permission_prompt,
            {},
            push(
                "project · Claude Code needs you",
                "Claude needs your permission to use Bash",
            ),
        ),
        (
            "failed turn",
            "Claude Code",
            failure,
            {},
            push("project · Claude Code failed: rate_limit", "429 Too Many Requests"),
        ),
        (
            "turn another Stop hook continued",
            "Claude Code",
            {**stop, "stop_hook_active": True},
            {},
            {},
        ),
        ("input 5 seconds ago", "Claude Code", stop, recent_input, {}),
        ("no keys", "Claude Code", stop, no_keys, {}),
    )

    with tempfile.TemporaryDirectory() as scratch:
        stubs = Path(scratch) / "bin"
        stubs.mkdir()
        for name, body in NOTIFY_STUBS.items():
            (stubs / name).write_text(body)
            (stubs / name).chmod(0o755)
        project = Path(scratch) / "project"
        project.mkdir()
        env = {
            "PATH": f"{stubs}:{os.environ['PATH']}",
            "HOME": scratch,
            "GIT_CEILING_DIRECTORIES": scratch,
            "PUSHOVER_USER": "U",
            "PUSHOVER_TOKEN": "T",
            "STUB_IDLE_NS": str(120 * 10**9),
        }

        for label, agent, event, overrides, expected in cases:
            sent = send_notify_event(
                agent, {**event, "cwd": str(project)}, {**env, **overrides}
            )
            if sent != expected:
                raise HarnessError(
                    f"notify-pushover {label}: expected {expected!r}, sent {sent!r}"
                )


def main() -> int:
    checks = (
        validate_manifests,
        validate_skills,
        validate_settings,
        validate_statusline,
        validate_notify_pushover,
    )
    try:
        for check in checks:
            check()
    except (HarnessError, json.JSONDecodeError, tomllib.TOMLDecodeError) as error:
        print(f"ai-harness-check: {error}", file=sys.stderr)
        return 1

    print(f"ai-harness-check: ok ({len(checks)} contracts)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
