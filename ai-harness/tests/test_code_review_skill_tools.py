#!/usr/bin/env -S uv run -q --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml", "ruamel.yaml"]
# ///
"""Regression tests for the code-review skill tools."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path
from types import ModuleType

SKILL_DIR = Path(__file__).resolve().parents[1] / "skills" / "code-review"
TOOLS_DIR = SKILL_DIR / "tools"


def load_module(name: str, path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


validate_mod = load_module("validate_tool", TOOLS_DIR / "validate.py")
view_mod = load_module("view_tool", TOOLS_DIR / "view.py")
submit_mod = load_module("submit_tool", TOOLS_DIR / "submit.py")


class ReviewToolTests(unittest.TestCase):
    def test_examples_validate(self) -> None:
        for path in (SKILL_DIR / "examples").glob("*.review.yaml"):
            with self.subTest(path=path.name):
                self.assertEqual(validate_mod.validate(path), [])

    def test_refresh_updates_only_obvious_anchors(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "src" / "sample.py"
            source.parent.mkdir()
            source.write_text("same\nx\nmoved\nambiguous\nambiguous\n")
            review_path = root / "review.review.yaml"
            review_path.write_text(
                f"""
generated_at: 2026-05-05T09:30:00Z
generated_by: test
target:
  kind: local
  repo_root: {root}
review:
  event: COMMENT
  summary: test
  threads:
    - id: rev-001
      author: ai
      file: src/sample.py
      line: 1
      severity: low
      confidence: high
      category: test
      body: same
      status: open
      anchor_text: same
      anchor_status: current
      replies: []
    - id: rev-002
      author: ai
      file: src/sample.py
      line: 1
      severity: low
      confidence: high
      category: test
      body: moved
      status: open
      anchor_text: moved
      anchor_status: current
      replies: []
    - id: rev-003
      author: ai
      file: src/sample.py
      line: 1
      severity: low
      confidence: high
      category: test
      body: missing
      status: open
      anchor_text: missing
      anchor_status: current
      replies: []
    - id: rev-004
      author: ai
      file: src/sample.py
      line: 1
      severity: low
      confidence: high
      category: test
      body: ambiguous
      status: open
      anchor_text: ambiguous
      anchor_status: current
      replies: []
"""
            )

            result = view_mod.refresh_review_file(review_path)
            threads = result["review"]["review"]["threads"]

            self.assertEqual(
                result["counts"],
                {
                    "current": 1,
                    "moved": 1,
                    "missing": 1,
                    "ambiguous": 1,
                },
            )
            self.assertEqual(threads[0]["anchor_status"], "current")
            self.assertEqual(threads[1]["anchor_status"], "moved")
            self.assertEqual(threads[1]["line"], 3)
            self.assertEqual(threads[2]["anchor_status"], "missing")
            self.assertEqual(threads[3]["anchor_status"], "ambiguous")

    def test_submit_payload_excludes_replies(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            review_path = Path(tmp) / "review.review.yaml"
            review_path.write_text(
                """
generated_at: 2026-05-05T09:30:00Z
generated_by: test
target:
  kind: pr
  repo_root: /tmp/repo
  commit: abc123
  pr_number: 12
review:
  event: COMMENT
  summary: test summary
  threads:
    - id: rev-001
      author: ai
      file: src/sample.py
      line: 1
      severity: low
      confidence: high
      category: test
      body: thread body
      status: open
      anchor_text: source line
      anchor_status: current
      replies:
        - author: user
          body: local reply only
    - id: rev-002
      author: ai
      file: src/sample.py
      line: 2
      severity: low
      confidence: high
      category: test
      body: skipped
      status: resolved
      anchor_text: other source line
      anchor_status: current
      replies: []
"""
            )

            payload = submit_mod.submit(review_path, None, dry_run=True)["payload"]

            self.assertEqual(len(payload["comments"]), 1)
            self.assertEqual(payload["comments"][0]["body"], "thread body")
            self.assertNotIn("local reply only", payload["comments"][0]["body"])


if __name__ == "__main__":
    unittest.main()
