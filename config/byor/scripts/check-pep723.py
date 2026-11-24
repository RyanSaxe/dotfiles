#!/usr/bin/env python3
"""Ensure standalone executable Python scripts use PEP 723 with uv.

Checks `.py` files that begin with a `#!` shebang. Requires the first line to
be `#!/usr/bin/env -S uv run --script` and a `# /// script` metadata header so
standalone scripts stay reproducible across machines without global installs.
"""

from __future__ import annotations

import sys
from pathlib import Path

EXPECTED_SHEBANG = "#!/usr/bin/env -S uv run --script"
PEP723_START = "# /// script"
PEP723_END = "# ///"


def check_file(raw: str) -> str | None:
    path = Path(raw)
    if not path.is_file():
        return None
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return None
    if not lines or not lines[0].startswith("#!"):
        return None

    problems: list[str] = []
    if lines[0].strip() != EXPECTED_SHEBANG:
        problems.append(f"shebang is `{lines[0].strip()}` instead of `{EXPECTED_SHEBANG}`")

    header_window = [line.strip() for line in lines[1:40]]
    has_block = False
    if PEP723_START in header_window:
        start_idx = header_window.index(PEP723_START)
        has_block = PEP723_END in header_window[start_idx + 1 :]
    if not has_block:
        problems.append("missing `# /// script` ... `# ///` PEP 723 metadata block")

    if not problems:
        return None
    detail = "; ".join(problems)
    return (
        f"{raw}:1: standalone Python script {detail}. "
        f"Start executable scripts with `{EXPECTED_SHEBANG}` and a `# /// script` block "
        "declaring `requires-python` and `dependencies`."
    )


def main(argv: list[str]) -> int:
    findings = [msg for raw in argv if (msg := check_file(raw))]
    if findings:
        sys.stdout.write("\n".join(findings) + "\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
