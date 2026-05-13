#!/usr/bin/env -S uv run -q --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml", "ruamel.yaml"]
# ///
"""Regression tests for the assisted-review skill tools."""

from __future__ import annotations

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path
from types import ModuleType

SKILL_DIR = Path(__file__).resolve().parents[1] / "skills" / "assisted-review"
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
    def run_git(self, root: Path, *args: str) -> None:
        subprocess.run(
            ["git", "-C", str(root), *args],
            check=True,
            capture_output=True,
            text=True,
        )

    def test_examples_validate(self) -> None:
        for path in (SKILL_DIR / "examples").glob("*.review.yaml"):
            with self.subTest(path=path.name):
                self.assertEqual(validate_mod.validate(path), [])

    def test_validation_requires_thread_type(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            review_path = Path(tmp) / "review.review.yaml"
            review_path.write_text(
                """
generated_at: 2026-05-05T09:30:00Z
generated_by: test
target:
  kind: local
  repo_root: /tmp/repo
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
      body: missing type
      status: open
      anchor_text: source line
      anchor_status: current
      replies: []
"""
            )

            self.assertIn(
                "threads[0].type is required", validate_mod.validate(review_path)
            )

    def test_validation_rejects_invalid_type_and_note_suggestion(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            review_path = Path(tmp) / "review.review.yaml"
            review_path.write_text(
                """
generated_at: 2026-05-05T09:30:00Z
generated_by: test
target:
  kind: local
  repo_root: /tmp/repo
review:
  event: COMMENT
  summary: test summary
  threads:
    - id: rev-001
      type: discussion
      author: ai
      file: src/sample.py
      line: 1
      severity: low
      confidence: high
      category: test
      body: invalid type
      status: open
      anchor_text: source line
      anchor_status: current
      replies: []
    - id: rev-002
      type: note
      author: ai
      file: src/sample.py
      line: 2
      severity: info
      confidence: medium
      category: context
      body: note with suggestion
      suggestion: replacement
      status: open
      anchor_text: other source line
      anchor_status: current
      replies: []
"""
            )

            errors = validate_mod.validate(review_path)

            self.assertTrue(
                any("threads[0].type must be one of" in error for error in errors)
            )
            self.assertIn(
                "threads[1].suggestion is not allowed when type is 'note'",
                errors,
            )

    def test_request_path_strips_query_string(self) -> None:
        self.assertEqual(
            view_mod.request_path("/api/refresh/repo/key?cache_bust=1"),
            "/api/refresh/repo/key",
        )

    def test_viewer_ping_payload_must_match_current_api_version(self) -> None:
        self.assertTrue(
            view_mod.is_current_viewer(
                {
                    "service": view_mod.SERVICE_SIGNATURE,
                    "api_version": view_mod.VIEWER_API_VERSION,
                }
            )
        )
        self.assertFalse(
            view_mod.is_current_viewer({"service": view_mod.SERVICE_SIGNATURE})
        )
        self.assertFalse(
            view_mod.is_current_viewer(
                {
                    "service": view_mod.SERVICE_SIGNATURE,
                    "api_version": view_mod.VIEWER_API_VERSION - 1,
                }
            )
        )

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
      type: comment
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
      type: comment
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

    def test_refresh_accepts_literal_block_trailing_newline(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "src" / "sample.py"
            source.parent.mkdir()
            source.write_text("source line\nnext line\n")
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
      type: comment
      author: ai
      file: src/sample.py
      line: 1
      severity: low
      confidence: high
      category: test
      body: literal block
      status: open
      anchor_text: |
        source line
      anchor_status: current
      replies: []
"""
            )

            result = view_mod.refresh_review_file(review_path)
            thread = result["review"]["review"]["threads"][0]

            self.assertEqual(thread["line"], 1)
            self.assertEqual(thread["anchor_status"], "current")

    def test_list_repo_files_respects_ignore_with_ignored_opt_in(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.run_git(root, "init")
            (root / ".gitignore").write_text("*.tmp\n")
            (root / "tracked.py").write_text("tracked\n")
            (root / ".tool-versions").write_text("python 3.11\n")
            (root / "notes.md").write_text("untracked\n")
            (root / "scratch.tmp").write_text("ignored\n")
            self.run_git(root, "add", ".gitignore", "tracked.py", ".tool-versions")

            default_files = view_mod.list_repo_files(str(root))
            with_ignored = view_mod.list_repo_files(str(root), include_ignored=True)

            self.assertIn(".gitignore", default_files)
            self.assertIn(".tool-versions", default_files)
            self.assertIn("tracked.py", default_files)
            self.assertIn("notes.md", default_files)
            self.assertNotIn("scratch.tmp", default_files)
            self.assertIn("scratch.tmp", with_ignored)

    def test_refresh_status_reports_dirty_fingerprint_without_mutating(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "repo"
            root.mkdir()
            self.run_git(root, "init")
            self.run_git(root, "config", "user.email", "test@example.com")
            self.run_git(root, "config", "user.name", "Test User")
            (root / "sample.py").write_text("print('one')\n")
            self.run_git(root, "add", "sample.py")
            self.run_git(root, "commit", "-m", "initial")
            fingerprint = view_mod.current_repo_fingerprint(str(root))
            self.assertIsNotNone(fingerprint)

            review_path = Path(tmp) / "review.review.yaml"
            review_path.write_text(
                f"""
generated_at: 2026-05-05T09:30:00Z
generated_by: test
target:
  kind: local
  repo_root: {root}
  fingerprint: {fingerprint}
review:
  event: COMMENT
  summary: test
  threads: []
"""
            )

            clean = view_mod.refresh_status_for_review(review_path)
            self.assertTrue(clean["ok"])
            self.assertFalse(clean["needs_refresh"])

            before = review_path.read_text()
            (root / "sample.py").write_text("print('two')\n")
            dirty = view_mod.refresh_status_for_review(review_path)

            self.assertTrue(dirty["ok"])
            self.assertTrue(dirty["needs_refresh"])
            self.assertEqual(review_path.read_text(), before)

    def test_refresh_status_reports_commit_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "repo"
            root.mkdir()
            self.run_git(root, "init")
            self.run_git(root, "config", "user.email", "test@example.com")
            self.run_git(root, "config", "user.name", "Test User")
            (root / "sample.py").write_text("print('one')\n")
            self.run_git(root, "add", "sample.py")
            self.run_git(root, "commit", "-m", "initial")
            initial_commit = subprocess.check_output(
                ["git", "-C", str(root), "rev-parse", "HEAD"],
                text=True,
            ).strip()
            (root / "sample.py").write_text("print('two')\n")
            self.run_git(root, "add", "sample.py")
            self.run_git(root, "commit", "-m", "second")

            review_path = Path(tmp) / "review.review.yaml"
            review_path.write_text(
                f"""
generated_at: 2026-05-05T09:30:00Z
generated_by: test
target:
  kind: local
  repo_root: {root}
  commit: {initial_commit}
review:
  event: COMMENT
  summary: test
  threads: []
"""
            )

            status = view_mod.refresh_status_for_review(review_path)

            self.assertTrue(status["ok"])
            self.assertTrue(status["needs_refresh"])
            self.assertEqual(status["mode"], "commit")

    def test_inbox_metadata_counts_comments_and_notes_separately(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            review_dir = Path(tmp) / "repo-slug"
            review_dir.mkdir()
            review_path = review_dir / "review.review.yaml"
            review_path.write_text(
                """
generated_at: 2026-05-05T09:30:00Z
generated_by: test
target:
  kind: local
  repo_root: /tmp/repo
  commit: abc123
review:
  event: COMMENT
  summary: test summary
  threads:
    - id: rev-001
      type: comment
      author: ai
      file: src/sample.py
      line: 1
      severity: high
      confidence: high
      category: correctness
      body: finding
      status: open
      anchor_text: source line
      anchor_status: current
      replies: []
    - id: rev-002
      type: note
      author: ai
      file: src/sample.py
      line: 2
      severity: info
      confidence: medium
      category: context
      body: local context
      status: open
      anchor_text: other source line
      anchor_status: current
      replies: []
"""
            )

            entry = view_mod.review_to_inbox_entry("repo-slug", "review", review_path)

            self.assertEqual(entry["thread_count"], 2)
            self.assertEqual(entry["comment_count"], 1)
            self.assertEqual(entry["note_count"], 1)
            self.assertEqual(entry["severity_counts"]["high"], 1)
            self.assertEqual(entry["severity_counts"]["info"], 0)

    def test_full_submit_keeps_only_notes_locally(self) -> None:
        threads = [
            {"id": "rev-001", "type": "comment", "status": "open"},
            {"id": "rev-002", "type": "comment", "status": "resolved"},
            {"id": "rev-003", "type": "note", "status": "open"},
        ]

        remaining = view_mod.remaining_threads_after_full_submit(threads)

        self.assertEqual(
            remaining, [{"id": "rev-003", "type": "note", "status": "open"}]
        )

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
      type: comment
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
      type: comment
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

    def test_single_comment_send_excludes_review_summary(self) -> None:
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
  summary:
    author: ai
    body: this is the full review summary
    replies: []
  note:
    author: ai
    body: local context only
    replies: []
  threads:
    - id: rev-001
      type: comment
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
      replies: []
"""
            )

            result = submit_mod.submit(review_path, "rev-001", dry_run=True)
            payload = result["payload"]

            self.assertEqual(result["endpoint"], "comments")
            self.assertEqual(payload["body"], "thread body")
            self.assertEqual(payload["commit_id"], "abc123")
            self.assertNotIn("this is the full review summary", str(payload))
            self.assertNotIn("comments", payload)
            self.assertNotIn("event", payload)

    def test_submit_payload_excludes_notes_and_refuses_direct_note_send(self) -> None:
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
      type: comment
      author: ai
      file: src/sample.py
      line: 1
      severity: high
      confidence: high
      category: correctness
      body: sendable comment
      status: open
      anchor_text: source line
      anchor_status: current
      replies: []
    - id: rev-002
      type: note
      author: ai
      file: src/sample.py
      line: 2
      severity: info
      confidence: medium
      category: context
      body: local note
      status: open
      anchor_text: other source line
      anchor_status: current
      replies: []
"""
            )

            payload = submit_mod.submit(review_path, None, dry_run=True)["payload"]

            self.assertEqual(len(payload["comments"]), 1)
            self.assertEqual(payload["comments"][0]["body"], "sendable comment")
            with self.assertRaisesRegex(RuntimeError, "thread type is not 'comment'"):
                submit_mod.submit(review_path, "rev-002", dry_run=True)

    def test_submit_treats_legacy_untyped_threads_as_comments(self) -> None:
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
      body: legacy comment
      status: open
      anchor_text: source line
      anchor_status: current
      replies: []
"""
            )

            payload = submit_mod.submit(review_path, None, dry_run=True)["payload"]

            self.assertEqual(len(payload["comments"]), 1)
            self.assertEqual(payload["comments"][0]["body"], "legacy comment")

    def test_submit_payload_preserves_empty_suggestion(self) -> None:
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
      type: comment
      author: ai
      file: src/sample.py
      line: 1
      severity: low
      confidence: high
      category: test
      body: delete this line
      status: open
      suggestion: ""
      anchor_text: source line
      anchor_status: current
      replies: []
"""
            )

            payload = submit_mod.submit(review_path, None, dry_run=True)["payload"]

            self.assertEqual(
                payload["comments"][0]["body"],
                "delete this line\n\n```suggestion\n\n```",
            )

    def test_submit_refuses_single_skipped_or_stale_thread(self) -> None:
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
      type: comment
      author: ai
      file: src/sample.py
      line: 1
      severity: low
      confidence: high
      category: test
      body: resolved
      status: resolved
      anchor_text: source line
      anchor_status: current
      replies: []
    - id: rev-002
      type: comment
      author: ai
      file: src/sample.py
      line: 2
      severity: low
      confidence: high
      category: test
      body: stale
      status: open
      anchor_text: other source line
      anchor_status: missing
      replies: []
"""
            )

            with self.assertRaisesRegex(RuntimeError, "not submittable: status"):
                submit_mod.submit(review_path, "rev-001", dry_run=True)
            with self.assertRaisesRegex(RuntimeError, "not submittable: anchor_status"):
                submit_mod.submit(review_path, "rev-002", dry_run=True)
            with self.assertRaisesRegex(RuntimeError, "stale threads: rev-002"):
                submit_mod.submit(review_path, None, dry_run=True)

    def test_submit_prefers_explicit_owner_repo(self) -> None:
        self.assertEqual(
            submit_mod.target_owner_repo(
                {
                    "owner": "example-owner",
                    "repo": "example-repo",
                    "repo_root": "/path/that/does/not/exist",
                }
            ),
            ("example-owner", "example-repo"),
        )


if __name__ == "__main__":
    unittest.main()
