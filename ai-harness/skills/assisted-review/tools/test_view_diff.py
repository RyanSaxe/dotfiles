#!/usr/bin/env -S uv run -q --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["ruamel.yaml", "pyyaml"]
# ///

from __future__ import annotations

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path


VIEW_PATH = Path(__file__).with_name("view.py")
SPEC = importlib.util.spec_from_file_location("assisted_review_view", VIEW_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load view.py")
view = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(view)


def git(repo: Path, *args: str) -> str:
    proc = subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True,
        text=True,
        check=True,
    )
    return proc.stdout.strip()


class DiffTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name)
        git(self.repo, "init", "-q")
        git(self.repo, "config", "user.email", "review@example.com")
        git(self.repo, "config", "user.name", "Review Test")
        (self.repo / "app.py").write_text("one\n")
        git(self.repo, "add", "app.py")
        git(self.repo, "commit", "-q", "-m", "initial")
        git(self.repo, "branch", "-M", "main")
        git(self.repo, "checkout", "-q", "-b", "feature")
        (self.repo / "app.py").write_text("one\ntwo\n")
        git(self.repo, "commit", "-am", "feature", "-q")

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def file_record(self, payload: dict, path: str) -> dict:
        for record in payload["files"]:
            if record["file"] == path:
                return record
        raise AssertionError(f"missing diff record for {path}")

    def test_branch_base_includes_committed_and_worktree_changes(self) -> None:
        (self.repo / "app.py").write_text("one\ntwo\nthree\n")

        payload = view.compute_diff(str(self.repo), {"base_ref": "main"})
        record = self.file_record(payload, "app.py")

        self.assertEqual(payload["base_ref"], "main")
        self.assertEqual(record["additions"], 2)
        self.assertEqual(record["deletions"], 0)
        self.assertEqual(record["hunk_count"], 1)
        self.assertEqual(record["hunks"][0]["changed_new_lines"], [2, 3])

    def test_head_base_only_shows_dirty_changes(self) -> None:
        (self.repo / "app.py").write_text("one\ntwo\nthree\n")

        payload = view.compute_diff(str(self.repo), {"base_ref": "HEAD"})
        record = self.file_record(payload, "app.py")

        self.assertEqual(payload["base_ref"], "HEAD")
        self.assertEqual(record["additions"], 1)
        self.assertEqual(record["hunks"][0]["changed_new_lines"], [3])

    def test_untracked_files_are_reported_as_added(self) -> None:
        (self.repo / "new.py").write_text("alpha\nbeta\n")

        payload = view.compute_diff(str(self.repo), {"base_ref": "HEAD"})
        record = self.file_record(payload, "new.py")

        self.assertEqual(record["status"], "A")
        self.assertEqual(record["additions"], 2)
        self.assertEqual(record["deletions"], 0)
        self.assertEqual(record["hunks"][0]["changed_new_lines"], [1, 2])

    def test_invalid_base_ref_raises_clear_error(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "could not resolve base ref"):
            view.compute_diff(str(self.repo), {"base_ref": "missing/ref"})


if __name__ == "__main__":
    unittest.main()
