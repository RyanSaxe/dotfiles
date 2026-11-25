from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[2]
WEB_RULES_DIR = REPO / "config/byor/packages/web"


def _clean_git_env(extra: dict[str, str] | None = None) -> dict[str, str]:
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    if extra:
        env.update(extra)
    return env


def _write_fixtures(root: Path, fixtures: dict[str, str]) -> list[Path]:
    paths: list[Path] = []
    for rel, content in fixtures.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        paths.append(path)
    return paths


def _scan_with_ast_grep(root: Path, files: list[Path] | None = None) -> list[dict[str, Any]]:
    ast_grep = shutil.which("ast-grep") or shutil.which("sg")
    assert ast_grep is not None, "ast-grep must be installed to test BYOR web rules"
    sgconfig = root / "sgconfig.yml"
    sgconfig.write_text(f"ruleDirs:\n  - {WEB_RULES_DIR}\n", encoding="utf-8")
    cmd = [ast_grep, "scan", "--config", str(sgconfig), "--json=compact", "--include-metadata", "--color", "never"]
    if files is not None:
        cmd.extend(str(path) for path in files)
    res = subprocess.run(cmd, cwd=root, capture_output=True, text=True, check=False, timeout=15)
    assert res.stdout.strip().startswith("["), f"ast-grep failed (exit {res.returncode}): {res.stderr}\n{res.stdout}"
    return json.loads(res.stdout)


def _match_pairs(matches: list[dict[str, Any]], root: Path) -> set[tuple[str, str]]:
    resolved_root = root.resolve()
    pairs: set[tuple[str, str]] = set()
    for match in matches:
        raw_path = Path(match["file"])
        rel = (
            raw_path.resolve().relative_to(resolved_root).as_posix() if raw_path.is_absolute() else raw_path.as_posix()
        )
        pairs.add((rel, match["ruleId"]))
    return pairs


def test_no_use_effect_flags_product_ui_and_exempts_hooks(tmp_path: Path) -> None:
    files = _write_fixtures(
        tmp_path,
        {
            "pages/Foo.tsx": (
                'import React, { useEffect, useLayoutEffect, useState } from "react";\n'
                "export function Foo() {\n"
                "  const [count, setCount] = useState(0);\n"
                "  useEffect(() => { setCount(1); }, []);\n"
                "  React.useLayoutEffect(() => {}, []);\n"
                "  return <div>{count}</div>;\n"
                "}\n"
            ),
            "components/Bar.jsx": (
                'import React, { useLayoutEffect } from "react";\n'
                "export function Bar() {\n"
                "  useLayoutEffect(() => {}, []);\n"
                "  React.useEffect(() => {}, []);\n"
                "  return <div />;\n"
                "}\n"
            ),
            "components/useHelper.ts": (
                'import { useEffect } from "react";\nexport function useHelper() {\n  useEffect(() => {}, []);\n}\n'
            ),
            "webhooks/Handler.tsx": (
                'import { useEffect } from "react";\n'
                "export function Handler() {\n"
                "  useEffect(() => {}, []);\n"
                "  return <div />;\n"
                "}\n"
            ),
            "components/Clean.tsx": (
                "export function Clean({ client }: { client: { useEffect: () => void } }) {\n"
                "  client.useEffect();\n"
                "  return <div />;\n"
                "}\n"
            ),
            "hooks/useFoo.ts": (
                'import { useEffect, useLayoutEffect } from "react";\n'
                "export function useFoo() {\n"
                "  useEffect(() => {}, []);\n"
                "  useLayoutEffect(() => {}, []);\n"
                "}\n"
            ),
            "hooks/useFoo.tsx": (
                'import React from "react";\nexport function useFooTsx() {\n  React.useEffect(() => {}, []);\n}\n'
            ),
            "src/hooks/useBar.jsx": (
                'import { useEffect } from "react";\nexport function useBar() {\n  useEffect(() => {}, []);\n}\n'
            ),
        },
    )

    expected = {
        ("pages/Foo.tsx", "react.no-use-effect"),
        ("components/Bar.jsx", "react.no-use-effect-js"),
        ("components/useHelper.ts", "react.no-use-effect-ts"),
        ("webhooks/Handler.tsx", "react.no-use-effect"),
    }

    whole_repo = _match_pairs(_scan_with_ast_grep(tmp_path), tmp_path)
    assert whole_repo == expected

    explicit_abs = _match_pairs(_scan_with_ast_grep(tmp_path, [f.resolve() for f in files]), tmp_path)
    assert explicit_abs == expected


def test_no_effect_async_wrapper_flags_everywhere_including_hooks(tmp_path: Path) -> None:
    files = _write_fixtures(
        tmp_path,
        {
            "hooks/useFoo.ts": (
                'import React, { startTransition, useEffect, useLayoutEffect } from "react";\n'
                "export function useFoo(setState: (v: number) => void) {\n"
                "  useEffect(() => {\n"
                "    queueMicrotask(() => setState(1));\n"
                "  }, [setState]);\n"
                "  useLayoutEffect(() => {\n"
                "    startTransition(() => setState(2));\n"
                "  }, [setState]);\n"
                "  React.useEffect(() => {\n"
                "    React.startTransition(() => setState(3));\n"
                "  }, [setState]);\n"
                "}\n"
            ),
            "hooks/useGlobal.tsx": (
                'import { useEffect } from "react";\n'
                "export function useGlobal(setState: (v: number) => void) {\n"
                "  useEffect(() => {\n"
                "    window.queueMicrotask(() => setState(1));\n"
                "    globalThis.queueMicrotask(() => setState(2));\n"
                "  }, [setState]);\n"
                "}\n"
            ),
            "pages/Foo.tsx": (
                'import { startTransition, useEffect } from "react";\n'
                "export function Foo({ setVal }: { setVal: (v: number) => void }) {\n"
                "  useEffect(() => {\n"
                "    startTransition(() => setVal(1));\n"
                "  }, [setVal]);\n"
                "  return <div />;\n"
                "}\n"
            ),
            "components/Bar.jsx": (
                'import { useLayoutEffect } from "react";\n'
                "export function Bar({ setVal }) {\n"
                "  useLayoutEffect(() => {\n"
                "    queueMicrotask(() => setVal(1));\n"
                "  }, [setVal]);\n"
                "  return <div />;\n"
                "}\n"
            ),
            "components/EventHandler.tsx": (
                'import { startTransition } from "react";\n'
                "export function EventHandler({ setTab }: { setTab: (v: string) => void }) {\n"
                "  function onClick() {\n"
                '    startTransition(() => setTab("next"));\n'
                '    queueMicrotask(() => setTab("done"));\n'
                "  }\n"
                "  return <button onClick={onClick}>Go</button>;\n"
                "}\n"
            ),
        },
    )

    matches = _scan_with_ast_grep(tmp_path, [f.resolve() for f in files])
    pairs = _match_pairs(matches, tmp_path)

    assert ("hooks/useFoo.ts", "react.no-effect-async-wrapper-ts") in pairs
    assert ("hooks/useGlobal.tsx", "react.no-effect-async-wrapper") in pairs
    assert ("pages/Foo.tsx", "react.no-effect-async-wrapper") in pairs
    assert ("components/Bar.jsx", "react.no-effect-async-wrapper-js") in pairs
    # Hooks must NOT trigger react.no-use-effect*, only react.no-effect-async-wrapper*.
    assert ("hooks/useFoo.ts", "react.no-use-effect-ts") not in pairs
    assert ("hooks/useGlobal.tsx", "react.no-use-effect") not in pairs
    # Event handlers outside effects must NOT trigger react.no-effect-async-wrapper*.
    assert not any(file == "components/EventHandler.tsx" for file, _ in pairs)


def test_no_try_finally_prompt_does_not_recommend_use_effect(tmp_path: Path) -> None:
    files = _write_fixtures(
        tmp_path,
        {
            "components/Modal.tsx": (
                "export function Modal() {\n"
                "  try {\n"
                "    return <div />;\n"
                "  } finally {\n"
                "    console.log('done');\n"
                "  }\n"
                "}\n"
            ),
            "components/ModalJs.jsx": (
                "export function ModalJs() {\n"
                "  try {\n"
                "    return <div />;\n"
                "  } finally {\n"
                "    console.log('done');\n"
                "  }\n"
                "}\n"
            ),
        },
    )

    matches = _scan_with_ast_grep(tmp_path, [f.resolve() for f in files])
    by_id = {match["ruleId"]: match for match in matches}
    assert set(by_id) == {"react.no-try-finally", "react.no-try-finally-js"}
    for match in by_id.values():
        prompt = match["metadata"]["byor"]["agent_prompt"]
        assert "useEffect" not in prompt
        assert "hooks/" in prompt


def test_byor_agent_check_runs_web_package_rules_end_to_end(tmp_path: Path) -> None:
    byor_bin = shutil.which("byor")
    assert byor_bin is not None, "byor CLI must be installed to run end-to-end web rule checks"

    xdg_config = tmp_path / "xdg-config"
    xdg_state = tmp_path / "xdg-state"
    byor_cfg = xdg_config / "byor"
    byor_cfg.mkdir(parents=True)
    (byor_cfg / "rules").mkdir()
    (byor_cfg / "commands").mkdir()
    (byor_cfg / "packages").symlink_to(REPO / "config/byor/packages")
    (byor_cfg / "config.yml").write_text(
        "version: 1\n"
        "paths:\n"
        "  rules: rules\n"
        "  packages: packages\n"
        "  repos: repos.yml\n"
        "  commands: commands\n"
        "ast_grep:\n"
        "  command: auto\n",
        encoding="utf-8",
    )

    repo_dir = tmp_path / "app"
    repo_dir.mkdir()
    env = _clean_git_env({"XDG_CONFIG_HOME": str(xdg_config), "XDG_STATE_HOME": str(xdg_state)})
    subprocess.run(["git", "init", "-q"], cwd=repo_dir, env=env, check=True, timeout=10)

    init_res = subprocess.run(
        [
            byor_bin,
            "init",
            "--repo",
            str(repo_dir),
            "--packages",
            "web",
            "--no-gate",
            "--no-register",
            "--non-interactive",
        ],
        cwd=repo_dir,
        env=env,
        capture_output=True,
        text=True,
        check=False,
        timeout=15,
    )
    assert init_res.returncode == 0, init_res.stdout + init_res.stderr

    files = _write_fixtures(
        repo_dir,
        {
            "pages/Foo.tsx": (
                'import { useEffect } from "react";\n'
                "export function Foo() {\n"
                "  useEffect(() => {}, []);\n"
                "  return <div />;\n"
                "}\n"
            ),
            "hooks/useClean.ts": (
                'import { useEffect } from "react";\nexport function useClean() {\n  useEffect(() => {}, []);\n}\n'
            ),
            "hooks/useWorkaround.ts": (
                'import { useEffect } from "react";\n'
                "export function useWorkaround(setX: (n: number) => void) {\n"
                "  useEffect(() => { queueMicrotask(() => setX(1)); }, [setX]);\n"
                "}\n"
            ),
        },
    )

    check_res = subprocess.run(
        [
            byor_bin,
            "agent-check",
            "--repo",
            str(repo_dir),
            "--scope",
            "file",
            "--format",
            "json",
            "--files",
            *(str(path) for path in files),
        ],
        cwd=repo_dir,
        env=env,
        capture_output=True,
        text=True,
        check=False,
        timeout=15,
    )
    assert check_res.returncode == 2, check_res.stdout + check_res.stderr
    payload = json.loads(check_res.stdout)
    issues = {(issue["file"], issue["rule_id"]) for issue in payload["issues"]}
    assert issues == {
        ("pages/Foo.tsx", "react.no-use-effect"),
        ("hooks/useWorkaround.ts", "react.no-effect-async-wrapper-ts"),
    }
