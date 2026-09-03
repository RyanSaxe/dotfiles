#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Run Ruff with project defaults plus invariant personal checks.

This check lets Ruff perform its normal configuration discovery, including the
user-level fallback config when a project has no Ruff setup of its own. It then
runs a second explicit pass for rules that should be enforced regardless of a
project's selected rule set, and deduplicates diagnostics so the agent receives
one clear report.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Mapping, Sequence

ALWAYS_SELECT = (
    "F",
    "E9",
    "ARG",
    "T100",
    "TID252",
    "PLC0415",
    "E402",
    "B006",
    "B008",
    "B011",
    "B012",
    "B018",
    "B020",
    "B023",
    "B026",
    "B033",
    "B904",
    "BLE001",
    "TRY002",
    "RUF006",
    "RUF012",
    "RUF016",
    "RUF018",
)


@dataclass(frozen=True)
class _CommandResult:
    stdout: str
    stderr: str
    returncode: int


class _RuffInvocationError(Exception):
    def __init__(self, arguments: Sequence[str], result: _CommandResult) -> None:
        detail = result.stderr.strip() or result.stdout.strip() or "no output"
        super().__init__(f"`ruff {' '.join(arguments)}` exited with code {result.returncode}:\n{detail}")


@dataclass(frozen=True)
class _RuffDiagnostic:
    filename: str
    row: int
    column: int
    end_row: int
    end_column: int
    code: str
    message: str

    @property
    def key(self) -> tuple[str, int, int, int, int, str]:
        normalized = str(Path(self.filename).expanduser())
        return (
            normalized,
            self.row,
            self.column,
            self.end_row,
            self.end_column,
            self.code,
        )

    def concise(self) -> str:
        return f"{self.filename}:{self.row}:{self.column}: {self.code} {self.message}"


def main(argv: Sequence[str]) -> int:
    # Findings (including autofixes) exit 1 like the other check scripts;
    # 2 is reserved for a ruff invocation that could not run at all.
    try:
        report = _run_all_passes(list(argv) if argv else ["."])
    except _RuffInvocationError as error:
        sys.stdout.write(f"ruff failed to run; fix the invocation problem first:\n{error}\n")
        return 2
    if not report:
        return 0
    sys.stdout.write(report)
    return 1


def _run_all_passes(targets: list[str]) -> str:
    ruff = _ruff_command()
    env = _plain_output_env()

    fixed = _run(
        ruff,
        (
            "check",
            "--fix-only",
            "--show-fixes",
            "--ignore-noqa",
            "--force-exclude",
            "--unfixable",
            "F401",
            *targets,
        ),
        env=env,
    )
    formatted = _run(ruff, ("format", "--force-exclude", *targets), env=env)
    normal = _ruff_json(
        ruff,
        (
            "check",
            "--quiet",
            "--output-format",
            "json",
            "--ignore-noqa",
            "--force-exclude",
            *targets,
        ),
        env=env,
    )
    always = _ruff_json(
        ruff,
        (
            "check",
            "--quiet",
            "--output-format",
            "json",
            "--ignore-noqa",
            "--force-exclude",
            "--select",
            ",".join(ALWAYS_SELECT),
            "--config",
            "lint.per-file-ignores = {}",
            "--config",
            "lint.extend-per-file-ignores = {}",
            "--config",
            'lint.flake8-tidy-imports.ban-relative-imports = "all"',
            *targets,
        ),
        env=env,
    )

    return _report(fixed, formatted, diagnostics=_dedupe((*normal, *always)))


def _ruff_command() -> tuple[str, ...]:
    if shutil.which("ruff"):
        return ("ruff",)
    return ("uvx", "ruff")


def _plain_output_env() -> dict[str, str]:
    env = os.environ.copy()
    env["NO_COLOR"] = "1"
    env["CLICOLOR"] = "0"
    env.pop("FORCE_COLOR", None)
    env.pop("CLICOLOR_FORCE", None)
    return env


def _run(
    command: Sequence[str],
    arguments: Sequence[str],
    *,
    env: Mapping[str, str],
) -> _CommandResult:
    completed = subprocess.run(
        [*command, *arguments],
        check=False,
        capture_output=True,
        text=True,
        env=dict(env),
    )
    return _CommandResult(
        stdout=completed.stdout,
        stderr=completed.stderr,
        returncode=completed.returncode,
    )


def _ruff_json(
    command: Sequence[str],
    arguments: Sequence[str],
    *,
    env: Mapping[str, str],
) -> tuple[_RuffDiagnostic, ...]:
    result = _run(command, arguments, env=env)
    payload = _json_list(result.stdout)
    # `ruff check` exits 0 when clean and 1 with valid JSON when it finds
    # violations; anything else (bad config, old ruff) is a crash that must not
    # silently pass the gate.
    if result.returncode not in (0, 1) or payload is None:
        raise _RuffInvocationError(arguments, result)
    diagnostics: list[_RuffDiagnostic] = []
    for item in payload:
        diagnostic = _diagnostic_from_json(item)
        if diagnostic is not None:
            diagnostics.append(diagnostic)
    return tuple(diagnostics)


def _json_list(text: str) -> list[object] | None:
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, list):
        return None
    return payload


def _diagnostic_from_json(item: object) -> _RuffDiagnostic | None:
    if not isinstance(item, dict):
        return None
    filename = item.get("filename")
    code = item.get("code")
    message = item.get("message")
    location = item.get("location")
    end_location = item.get("end_location")
    if not (
        isinstance(filename, str) and isinstance(code, str) and isinstance(message, str) and isinstance(location, dict)
    ):
        return None
    if not isinstance(end_location, dict):
        end_location = location
    return _RuffDiagnostic(
        filename=filename,
        row=_int_value(location.get("row")),
        column=_int_value(location.get("column")),
        end_row=_int_value(end_location.get("row")),
        end_column=_int_value(end_location.get("column")),
        code=code,
        message=message,
    )


def _int_value(value: object) -> int:
    if isinstance(value, int):
        return value
    return 0


def _dedupe(diagnostics: Sequence[_RuffDiagnostic]) -> tuple[_RuffDiagnostic, ...]:
    seen: set[tuple[str, int, int, int, int, str]] = set()
    unique: list[_RuffDiagnostic] = []
    for diagnostic in diagnostics:
        if diagnostic.key in seen:
            continue
        seen.add(diagnostic.key)
        unique.append(diagnostic)
    return tuple(unique)


def _report(
    fixed: _CommandResult,
    formatted: _CommandResult,
    *,
    diagnostics: Sequence[_RuffDiagnostic],
) -> str:
    parts: list[str] = []
    errors = _pass_errors(fixed=fixed, formatted=formatted)
    if errors:
        parts.append(f"ruff failed to run; fix the invocation problem first:\n{errors}\n")
    fixed_output = _combined_output(fixed).strip()
    if fixed.returncode == 0 and fixed_output:
        parts.append(f"Autofixed by ruff (no action needed):\n{fixed_output}\n")
    formatted_output = _combined_output(formatted)
    if formatted.returncode == 0 and "reformatted" in formatted_output:
        parts.append("ruff format reformatted the file(s).\n")
    if diagnostics:
        rendered = "\n".join(diagnostic.concise() for diagnostic in diagnostics)
        parts.append(f"Remaining ruff issues to fix:\n{rendered}\n")
    return "".join(parts)


def _pass_errors(*, fixed: _CommandResult, formatted: _CommandResult) -> str:
    labeled = (("ruff check --fix-only", fixed), ("ruff format", formatted))
    return "\n".join(
        f"`{label}` exited with code {result.returncode}:\n{_combined_output(result).strip() or 'no output'}"
        for label, result in labeled
        if result.returncode != 0
    )


def _combined_output(result: _CommandResult) -> str:
    return result.stdout + result.stderr


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
